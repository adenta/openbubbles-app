import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:bluebubbles/helpers/files/serial_work_queue.dart';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:universal_io/io.dart';

typedef HeicDecode = Future<void> Function(String source, String destination);

class HeicDecodeException implements Exception {
  final String reason;
  const HeicDecodeException(this.reason);
  @override
  String toString() => 'HEIC display conversion failed: $reason';
}

/// App-owned PNGs are disposable; the original file is always read-only.
class LinuxHeicDecoder {
  LinuxHeicDecoder(
      {HeicDecode? decode,
      String? executable,
      this.timeout = const Duration(seconds: 30)})
      : _decodeOverride = decode,
        executable = executable ??
            p.join(p.dirname(Platform.resolvedExecutable),
                'openbubbles-heic-decode');

  final String executable;
  final Duration timeout;
  final HeicDecode? _decodeOverride;
  final _queue = SerialWorkQueue();
  final Map<String, Future<Uint8List>> _pending = {};

  Future<Uint8List> load(String source) {
    source = p.normalize(p.absolute(source));
    return _pending.putIfAbsent(source, () {
      final path = source;
      return _queue.run(() => _load(path)).whenComplete(() {
        _pending.remove(path);
      });
    });
  }

  /// Wait for old work before deleting, so it cannot republish a stale cache.
  Future<void> invalidate(String source) => _queue.run(() async {
        for (final suffix in ['.png', '.png.heic-cache']) {
          final file = File('$source$suffix');
          if (await file.exists()) await file.delete();
        }
      });

  Future<Uint8List> _load(String source) async {
    final original = File(source);
    if (!await original.exists() || await original.length() == 0) {
      throw const HeicDecodeException('missing or empty source');
    }
    final sourceHash =
        (await sha256.bind(original.openRead()).first).toString();
    final png = File('$source.png');
    final receipt = File('$source.png.heic-cache');
    try {
      final metadata = jsonDecode(await receipt.readAsString());
      if (metadata['version'] == 1 && metadata['source'] == sourceHash) {
        final bytes = await png.readAsBytes();
        final hash = await _inspectPng(bytes);
        if (hash != null && hash == metadata['png']) return bytes;
      }
    } catch (_) {
      // A missing, old or corrupt cache is regenerated from the original.
    }

    final staging =
        await Directory(p.dirname(source)).createTemp('.heic-display-');
    try {
      final output = p.join(staging.path, 'display.png');
      await (_decodeOverride ?? _decode)(source, output);
      final bytes = await File(output).readAsBytes();
      final pngHash = await _inspectPng(bytes);
      if (pngHash == null)
        throw const HeicDecodeException('invalid PNG output');
      if ((await sha256.bind(original.openRead()).first).toString() !=
          sourceHash) {
        throw const HeicDecodeException(
            'source changed during conversion; retry');
      }
      final stagedReceipt = File(p.join(staging.path, 'receipt'));
      await stagedReceipt.writeAsString(
          jsonEncode({'version': 1, 'source': sourceHash, 'png': pngHash}),
          flush: true);
      await File(output).rename(png.path);
      await stagedReceipt.rename(receipt.path);
      return bytes;
    } finally {
      await staging.delete(recursive: true);
    }
  }

  // Validate the complete PNG off the UI isolate, not merely its magic bytes.
  static Future<String?> _inspectPng(Uint8List bytes) => Isolate.run(() {
        try {
          final image = img.decodePng(bytes);
          if (image == null || image.width == 0 || image.height == 0)
            return null;
          return sha256.convert(bytes).toString();
        } catch (_) {
          return null;
        }
      });

  Future<void> _decode(String source, String destination) async {
    final Process process;
    try {
      process = await Process.start(executable, [source, destination],
          runInShell: false);
    } on ProcessException {
      throw const HeicDecodeException('decoder unavailable');
    }
    // Drain both pipes immediately, retaining no filenames or unbounded output.
    final stdout = process.stdout.drain<void>();
    final stderr = process.stderr.drain<void>();
    try {
      final exit = await process.exitCode.timeout(timeout);
      if (exit != 0)
        throw HeicDecodeException('decoder exited with status $exit');
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
      throw const HeicDecodeException('decoder timed out');
    } finally {
      await Future.wait([stdout, stderr]);
    }
  }
}

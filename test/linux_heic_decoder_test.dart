import 'dart:async';
import 'dart:io';

import 'package:bluebubbles/services/ui/linux_heic_decoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  final helper = File('build/heic-tests/openbubbles-heic-decode').absolute.path;
  late Directory dir;
  late String source;
  final smallPng = img.encodePng(img.Image(width: 8, height: 4));
  Future<void> fakeDecode(String _, String output) =>
      File(output).writeAsBytes(smallPng).then((_) {});

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('openbubbles-heic-test-');
    source = '${dir.path}/photo.HEIC';
    await File('build/heic-tests/fixtures/ordinary.heic').copy(source);
  });
  tearDown(() => dir.delete(recursive: true));

  test(
      'native helper preserves dimensions, rotation, mirroring, alpha and primary item',
      () async {
    final decoder = LinuxHeicDecoder(executable: helper);
    for (final name in [
      'ordinary',
      'rotated',
      'mirrored',
      'ten-bit',
      'alpha',
      'multiple'
    ]) {
      final file = await File('build/heic-tests/fixtures/$name.heic')
          .copy('${dir.path}/$name.heic');
      final before = await file.readAsBytes();
      final decoded = img.decodePng(await decoder.load(file.path))!;
      final rotated = name == 'rotated' || name == 'multiple';
      expect(decoded.width, rotated ? 32 : 64, reason: name);
      expect(decoded.height, rotated ? 64 : 32, reason: name);
      if (name == 'mirrored') {
        expect(decoded.getPixel(4, 4).r, lessThan(decoded.getPixel(60, 4).r));
      } else if (name == 'ordinary' || name == 'ten-bit') {
        expect(
            decoded.getPixel(4, 4).r, greaterThan(decoded.getPixel(60, 4).r));
        expect(decoded.getPixel(4, 4).g, lessThan(decoded.getPixel(4, 28).g));
      }
      if (name == 'alpha') {
        expect(decoded.numChannels, 4);
        expect(decoded.getPixel(4, 4).a, greaterThan(240));
        expect(decoded.getPixel(60, 4).a, closeTo(80, 15));
      }
      expect(await file.readAsBytes(), before,
          reason: 'original $name changed');
    }
  });

  test('cache survives restart; corrupted PNG and receipt regenerate',
      () async {
    var conversions = 0;
    Future<void> decode(String input, String output) async {
      conversions++;
      await fakeDecode(input, output);
    }

    await LinuxHeicDecoder(decode: decode).load(source);
    await LinuxHeicDecoder(decode: decode).load(source);
    expect(conversions, 1);
    await File('$source.png').writeAsBytes([1, 2, 3]);
    await LinuxHeicDecoder(decode: decode).load(source);
    expect(conversions, 2);
    await File('$source.png.heic-cache').writeAsString('{invalid');
    await LinuxHeicDecoder(decode: decode).load(source);
    expect(conversions, 3);
    // Even syntactically valid metadata with a missing PNG hash is untrusted.
    await File('$source.png.heic-cache').writeAsString('{}');
    await LinuxHeicDecoder(decode: decode).load(source);
    expect(conversions, 4);
  });

  test(
      'same-size source replacement invalidates cache even with preserved timestamp',
      () async {
    var conversions = 0;
    final decoder = LinuxHeicDecoder(decode: (input, output) async {
      conversions++;
      await fakeDecode(input, output);
    });
    await decoder.load(source);
    final file = File(source);
    final before = await file.stat();
    final bytes = await file.readAsBytes();
    bytes[bytes.length - 1] ^= 1;
    await file.writeAsBytes(bytes);
    await file.setLastModified(before.modified);
    await decoder.load(source);
    expect(conversions, 2);
  });

  test('concurrent loads share conversion and different files serialize',
      () async {
    var conversions = 0;
    var active = 0;
    final gate = Completer<void>();
    final decoder = LinuxHeicDecoder(decode: (input, output) async {
      expect(++active, 1);
      conversions++;
      await gate.future;
      await fakeDecode(input, output);
      active--;
    });
    final other = await File(source).copy('${dir.path}/other.heic');
    final first = decoder.load(source);
    final same = decoder.load(source);
    final second = decoder.load(other.path);
    expect(identical(first, same), isTrue);
    gate.complete();
    await Future.wait([first, same, second]);
    expect(conversions, 2);
  });

  test('invalidation waits for old work and removes both cache files',
      () async {
    final gate = Completer<void>();
    final decoder = LinuxHeicDecoder(decode: (input, output) async {
      await gate.future;
      await fakeDecode(input, output);
    });
    final pending = decoder.load(source);
    final invalidation = decoder.invalidate(source);
    gate.complete();
    await pending;
    await invalidation;
    expect(await File(source).exists(), isTrue);
    expect(await File('$source.png').exists(), isFalse);
    expect(await File('$source.png.heic-cache').exists(), isFalse);
    await decoder.load(source);
    expect(await File('$source.png').exists(), isTrue);
  });

  test('source changing during conversion cannot publish a stale cache',
      () async {
    final decoder = LinuxHeicDecoder(decode: (input, output) async {
      await fakeDecode(input, output);
      await File(input).writeAsBytes([1, 2, 3]);
    });
    await expectLater(
        decoder.load(source), throwsA(isA<HeicDecodeException>()));
    expect(await File('$source.png').exists(), isFalse);
    expect(await dir.list().where((entry) => entry is Directory).length, 0);
  });

  test(
      'missing, empty and truncated sources fail without creating originals or PNGs',
      () async {
    final decoder = LinuxHeicDecoder(executable: helper);
    final missing = '${dir.path}/missing.heic';
    await expectLater(
        decoder.load(missing), throwsA(isA<HeicDecodeException>()));
    expect(await File(missing).exists(), isFalse);
    await File(source).writeAsBytes([]);
    await expectLater(
        decoder.load(source), throwsA(isA<HeicDecodeException>()));
    await File(source).writeAsBytes([1, 2, 3, 4]);
    await expectLater(
        decoder.load(source), throwsA(isA<HeicDecodeException>()));
    expect(await File('$source.png').exists(), isFalse);
  });

  test('missing helper and invalid output are recoverable errors', () async {
    await expectLater(
        LinuxHeicDecoder(executable: '${dir.path}/missing').load(source),
        throwsA(isA<HeicDecodeException>()));
    final decoder = LinuxHeicDecoder(
        decode: (_, output) => File(output).writeAsBytes([1]).then((_) {}));
    await expectLater(
        decoder.load(source), throwsA(isA<HeicDecodeException>()));
    expect(await File('$source.png').exists(), isFalse);
  });

  test('timeout kills helper; next request can succeed', () async {
    final script = File('${dir.path}/slow-decoder');
    await script.writeAsString('#!/bin/sh\nexec sleep 60\n');
    await Process.run('chmod', ['+x', script.path]);
    final decoder = LinuxHeicDecoder(
        executable: script.path, timeout: const Duration(milliseconds: 100));
    await expectLater(
        decoder.load(source),
        throwsA(isA<HeicDecodeException>()
            .having((e) => e.reason, 'reason', contains('timed out'))));
    await script.writeAsBytes(await File(helper).readAsBytes());
    expect(await decoder.load(source), isNotEmpty);
  });

  test('paths with spaces, quotes and shell metacharacters are literal',
      () async {
    final literal =
        await File(source).copy('${dir.path}/photo \'\$(touch injected).HEIC');
    expect(await LinuxHeicDecoder(executable: helper).load(literal.path),
        isNotEmpty);
    expect(await File('${dir.path}/injected').exists(), isFalse);
  });
}

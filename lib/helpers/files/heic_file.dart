import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_io/io.dart';

/// Detection only; never rewrites the attachment's original MIME or name.
class HeicFile {
  static bool matches(String? mime, String? name) {
    final type = mime?.split(';').first.trim().toLowerCase();
    final extension = name?.split('.').last.toLowerCase();
    return const {
          'image/heic',
          'image/heif',
          'image/heic-sequence',
          'image/heif-sequence'
        }.contains(type) ||
        const {'heic', 'heif'}.contains(extension);
  }

  static bool hasSignature(List<int> header) {
    if (header.length < 16 ||
        ascii.decode(header.sublist(4, 8), allowInvalid: true) != 'ftyp')
      return false;
    final size = ByteData.sublistView(Uint8List.fromList(header)).getUint32(0);
    if (size < 16) return false;
    final brands = <String>{};
    for (var offset = 8;
        offset + 4 <= header.length && offset + 4 <= size;
        offset += 4) {
      if (offset != 12)
        brands.add(ascii.decode(header.sublist(offset, offset + 4),
            allowInvalid: true));
    }
    if (brands.contains('avif') || brands.contains('avis')) return false;
    return brands.any(const {
      'heic',
      'heix',
      'hevc',
      'hevx',
      'heim',
      'heis',
      'hevm',
      'hevs',
      'mif1',
      'msf1'
    }.contains);
  }

  static bool isGeneric(String? mime) =>
      mime == null ||
      const {
        '',
        'application/octet-stream',
        'binary/octet-stream',
        'application/binary'
      }.contains(mime.split(';').first.trim().toLowerCase());

  // Bounded header read for synchronous attachment routing. No image is decoded
  // from a widget build; the expensive work lives in LinuxHeicDecoder.
  static bool matchesFile(String? mime, String? name, String path) {
    if (matches(mime, name)) return true;
    if (!isGeneric(mime)) return false;
    RandomAccessFile? file;
    try {
      file = File(path).openSync();
      return hasSignature(file.readSync(4096));
    } on FileSystemException {
      return false;
    } finally {
      file?.closeSync();
    }
  }
}

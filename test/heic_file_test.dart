import 'dart:io';
import 'dart:typed_data';

import 'package:bluebubbles/helpers/files/heic_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('case-insensitive HEIC/HEIF types and names', () {
    for (final name in ['photo.HEIC', 'photo.HeIf']) {
      expect(HeicFile.matches(null, name), isTrue);
    }
    expect(HeicFile.matches('IMAGE/HEIC; foo=bar', 'unknown'), isTrue);
    expect(HeicFile.matches('image/heif-sequence', null), isTrue);
    expect(HeicFile.matches('image/jpeg', 'photo.jpg'), isFalse);
  });

  test('sniffs generic MIME without misclassifying AVIF or ordinary files', () {
    Uint8List header(String brand) => Uint8List.fromList([
          0,
          0,
          0,
          24,
          ...'ftyp'.codeUnits,
          ...brand.codeUnits,
          0,
          0,
          0,
          0,
          ...'mif1'.codeUnits,
          ...brand.codeUnits,
        ]);
    expect(HeicFile.hasSignature(header('heic')), isTrue);
    expect(HeicFile.hasSignature(header('avif')), isFalse);
    expect(HeicFile.hasSignature(header('avis')), isFalse);
    expect(HeicFile.hasSignature([0, 0, 0]), isFalse);
    final dir = Directory.systemTemp.createTempSync('heic-detection-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/unknown.bin')
      ..writeAsBytesSync(header('heic'));
    expect(HeicFile.matchesFile(null, file.path, file.path), isTrue);
    expect(
        HeicFile.matchesFile('application/octet-stream', file.path, file.path),
        isTrue);
    expect(HeicFile.matchesFile('video/mp4', file.path, file.path), isFalse);
    expect(
        HeicFile.matchesFile(null, 'missing', '${dir.path}/missing'), isFalse);
  });
}

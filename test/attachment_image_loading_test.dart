import 'dart:io';

import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/ui/attachments_service.dart';
import 'package:bluebubbles/services/ui/linux_heic_decoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

class MemoryAttachment extends Attachment {
  MemoryAttachment(String path) : super(guid: 'temp-test', transferName: 'photo.heic',
      sourcePath: path, mimeType: 'image/heic', metadata: {'Image Orientation': 'Rotate 90'});

  @override
  Attachment save(Message? message) => this;
}

void main() {
  late Directory dir;
  late AttachmentsService service;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('attachment-image-test-');
    service = AttachmentsService(
        heicDecoder: LinuxHeicDecoder(
      executable:
          File('build/heic-tests/openbubbles-heic-decode').absolute.path,
    ));
  });
  tearDown(() => dir.delete(recursive: true));

  test(
      'shared loader converts named HEIC and generic MIME signature without modifying metadata',
      () async {
    for (final (name, mime) in [
      ('photo.HEIC', 'image/heic'),
      ('photo.bin', 'application/octet-stream'),
      ('unknown', null)
    ]) {
      final file = await File('build/heic-tests/fixtures/ordinary.heic')
          .copy('${dir.path}/$name');
      final attachment = Attachment(
          guid: 'temp-test',
          transferName: name,
          mimeType: mime,
          sourcePath: file.path);
      expect(attachment.mimeStart, 'image');
      expect(attachment.canCompress, isTrue);
      final before = await file.readAsBytes();
      final display = await service.loadAndGetProperties(attachment,
          actualPath: file.path, onlyFetchData: true);
      expect(img.decodePng(display!)!.width, 64);
      expect(attachment.mimeType, mime);
      expect(attachment.transferName, name);
      expect(await file.readAsBytes(), before);
    }
  });

  test('JPEG, PNG and GIF pass through; TIFF still converts to PNG', () async {
    final image = img.Image(width: 8, height: 4);
    final fixtures = {
      'jpeg': img.encodeJpg(image),
      'png': img.encodePng(image),
      'gif': img.encodeGif(image),
      'tiff': img.encodeTiff(image)
    };
    for (final entry in fixtures.entries) {
      final file = await File('${dir.path}/photo.${entry.key}')
          .writeAsBytes(entry.value);
      final attachment = Attachment(
          guid: 'temp-test',
          transferName: 'photo.${entry.key}',
          mimeType: 'image/${entry.key}');
      final bytes = await service.loadAndGetProperties(attachment,
          actualPath: file.path, onlyFetchData: true);
      if (entry.key == 'tiff') {
        expect(img.decodePng(bytes!)!.width, 8);
      } else {
        expect(bytes, entry.value);
      }
      expect(await file.readAsBytes(), entry.value);
    }
  });

  test('missing files are not fabricated during image loading', () async {
    final file = File('${dir.path}/missing.jpg');
    await expectLater(
        service.loadAndGetProperties(
            Attachment(mimeType: 'image/jpeg', transferName: 'missing.jpg'),
            actualPath: file.path),
        throwsA(isA<FileSystemException>()));
    expect(await file.exists(), isFalse);
  });

  test('display dimensions come from PNG and EXIF orientation is not applied twice', () async {
    for (final (name, ratio) in [('ordinary', 2.0), ('rotated', 0.5)]) {
      final file = await File('build/heic-tests/fixtures/$name.heic').copy('${dir.path}/$name.heic');
      final attachment = MemoryAttachment(file.path);
      await service.loadAndGetProperties(attachment, actualPath: file.path);
      expect(attachment.aspectRatio, ratio);
      expect(attachment.metadata!['Image Orientation'], 'Rotate 90');
    }
  });
}

import 'package:cross_file_io/cross_file_io.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:desktop_drop/src/drop_offer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(CrossFileIO.registerWith);

  test(
    'previews and files use the same MIME fallback without reading bytes',
    () {
      for (final (name, provided, expected) in <(String, String?, String?)>[
        (
          'cover.jpg@672w_378h_1c_!web-home-common-cover.avif',
          null,
          'image/avif',
        ),
        ('PHOTO.JPG', '', 'image/jpeg'),
        ('image.png', null, 'image/png'),
        ('image.jpg', 'image/png', 'image/png'),
        ('image.jpg', 'application/octet-stream', 'application/octet-stream'),
        ('item.unknown-extension', null, null),
        ('jpg', null, null),
        ('', null, null),
      ]) {
        final preview = DropOffer.fromMap({
          'files': [
            {'name': name, 'mimeType': provided},
          ],
        }).items.single;
        // This file does not exist: MIME inference must not read its contents.
        final item = DropFileItem(
          file: XFile.fileSystem(path: '/desktop-drop-metadata-only'),
          name: name,
          mimeType: provided,
        );
        expect(preview.mimeType, expected, reason: name);
        expect(item.mimeType, expected, reason: name);
      }
    },
  );

  test('files can infer from a known path when the name is unavailable', () {
    const preview = DropItemPreview(
      kind: DropItemKind.file,
      name: '',
      localPath: '/folder/photo.JPG',
    );
    final item = DropFileItem(
      file: XFile.fileSystem(path: '/folder/photo.JPG'),
      name: '',
      localPath: '/folder/photo.JPG',
    );
    expect(preview.mimeType, 'image/jpeg');
    expect(item.mimeType, preview.mimeType);
  });

  test('directory and string previews do not infer MIME types from names', () {
    const directory = DropItemPreview(
      kind: DropItemKind.directory,
      name: 'folder.avif',
    );
    const string = DropItemPreview(
      kind: DropItemKind.string,
      name: 'value.avif',
      mimeType: 'application/x-example',
    );
    const unknownString = DropItemPreview(
      kind: DropItemKind.string,
      name: 'value.avif',
    );
    expect(directory.mimeType, isNull);
    expect(string.mimeType, 'application/x-example');
    expect(unknownString.mimeType, isNull);
  });
}

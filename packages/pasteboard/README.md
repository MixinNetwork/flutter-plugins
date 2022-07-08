# pasteboard

[![Pub](https://img.shields.io/pub/v/pasteboard.svg)](https://pub.dev/packages/pasteboard)

A flutter plugin which could read image,files from clipboard and write files to clipboard.

|         |     |
| ------- | --- |
| Windows | ✅  |
| Linux   | ✅  |
| macOS   | ✅  |
| iOS     | ✅  |
| Web     | ✅  |

## Getting Started

1. add `package:pasteboard` to `pubspec.yaml`

   ```yaml
   dependencies:
     pasteboard: ^latest
   ```

2. example

   ```dart
   import 'package:pasteboard/pasteboard.dart';

   Future<void> readAndWriteFiles() async {
     final paths = ['your_file_path'];
     await Pasteboard.writeFiles(paths);

     final files = await Pasteboard.files();
     print(files);
   }

   Future<void> readImages() async {
     final imageBytes = await Pasteboard.image;
     print(imageBytes?.length);
   }
   ```

## License

See the [LICENSE](LICENSE) file for the full license.

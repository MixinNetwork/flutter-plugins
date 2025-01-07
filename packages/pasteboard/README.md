# pasteboard

[![Pub](https://img.shields.io/pub/v/pasteboard.svg)](https://pub.dev/packages/pasteboard)

A Flutter plugin that allows reading images and files from the clipboard and writing files to the clipboard.

| Platform | Supported | Requires Setup |
|----------|---------- |--------------- |
| Windows  | ✅        | No             |
| Linux    | ✅        | No             |
| macOS    | ✅        | No             |
| iOS      | ✅        | No             |
| Web      | ✅        | No             |
| Android  | ✅        | Yes            |

## Getting Started

1. Add `package:pasteboard` to `pubspec.yaml`:

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

## Android Setup
To use this package on Android without errors, follow these steps:

1. Add the following `<provider>` entry inside the `<application>` tag in your AndroidManifest.xml (`android/app/src/main/AndroidManifest.xml`):

```xml
<provider
    android:name="androidx.core.content.FileProvider"
    android:authorities="${applicationId}.provider"
    android:exported="false"
    android:grantUriPermissions="true">
    <meta-data
        android:name="android.support.FILE_PROVIDER_PATHS"
        android:resource="@xml/provider_paths" />
</provider>
```
2. Create the file `provider_paths.xml` at `android/app/src/main/res/xml/provider_paths.xml` with the following content:

```xml
<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <external-path
        name="external_files"
        path="." />
</paths>
```

### Common Issues
If these steps are not followed, you may encounter the following runtime error:

```
Couldn't find meta-data for provider with authority
```

Make sure the `<provider>` entry is correctly added to the `AndroidManifest.xml` and that the `provider_paths.xml` file exists in the correct location.

## License

See the [LICENSE](LICENSE) file for the full license.

## 0.0.3

- Linux: Fix builds with CMake older than 3.25, which skipped the Breakpad Linux sources and failed to link. ([#542](https://github.com/MixinNetwork/flutter-plugins/pull/542))
- Fix the logger reading freed native strings, and release the previous callback when `setLogger` is called again. ([#542](https://github.com/MixinNetwork/flutter-plugins/pull/542))
- Windows: Support dump directories with non-ASCII paths, and log crash dump paths instead of pointer addresses. ([#542](https://github.com/MixinNetwork/flutter-plugins/pull/542))
- Write crash-time messages to stderr only; the Dart logger receives setup messages. ([#542](https://github.com/MixinNetwork/flutter-plugins/pull/542))

## 0.0.2

* fix lls not published

## 0.0.1

* initial release.

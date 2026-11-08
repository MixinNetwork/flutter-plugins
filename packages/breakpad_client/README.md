# breakpad_client

A Flutter FFI plugin that installs a [Breakpad](https://chromium.googlesource.com/breakpad/breakpad)
exception handler and writes minidumps when the native process crashes.

Supported platforms: Linux and Windows.

## Usage

```dart
import 'package:breakpad_client/breakpad_client.dart' as breakpad;

void main() {
  breakpad.setLogger((log) => debugPrint(log));
  breakpad.initExceptionHandle('/path/to/crash/dumps');
  runApp(const MyApp());
}
```

`initExceptionHandle` creates the directory if needed and writes `.dmp` files
there on crash. Calling it again replaces the previous handler.

The logger receives messages produced while the handler is being set up.
Messages written while the process is crashing go to stderr only, because the
Dart side can no longer receive them.

## Build requirements

- Linux: CMake 3.10 or later and a C++17 compiler.
- Windows: Visual Studio with CMake 3.14 or later.

Clone the repository with submodules, since Breakpad and
linux-syscall-support are vendored as Git submodules:

```shell
git submodule update --init --recursive packages/breakpad_client
```

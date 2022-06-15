# mixin_logger

Simple logger tool for flutter.

## Features

### Print log

```dart
void main() {
  v('verbose message');
  d('debug message');
  i('info message');
  w('warning message');
  e('error message');
  wtf('wtf message');
}
```

### Save log to file.

```dart
void main() {
  // init logger with dir. then all logs will be saved to this dir.
  initLogger(
    'app_log_files_dir',
    maxFileCount: 10, // max 10 files.
    maxFileLength: 5 * 1024 * 1024, // max to 5 MB for single file.
  );
}
```

## License

see [LICENSE](LICENSE)
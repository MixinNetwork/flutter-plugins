# string_tokenizer

A Flutter package that provides a utility method for breaking text into individual words.

## Usage

To use this package, add `string_tokenizer` as
a [dependency in your pubspec.yaml file](https://flutter.dev/docs/development/packages-and-plugins/using-packages).

```yaml
dependencies:
  string_tokenizer:
    git:
      url: https://github.com/MixinNetwork/flutter-plugins.git
      path: packages/string_tokenizer
```

Then import the package:

```dart
import 'package:string_tokenizer/string_tokenizer.dart';
```

### Breaking Text Into Words

`string_tokenizer` provides a single method `tokenize` which takes a string and breaks it into individual words.

```dart

List<String> words = tokenize('This is a sentence.');
```

The `words` list will contain the following strings:

```log
['This', 'is', 'a', 'sentence']
```

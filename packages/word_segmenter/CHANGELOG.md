## 0.1.0

- Initial release. `wordBoundaries` splits text at word boundaries with the platform's own text services, so Chinese and Japanese are segmented with dictionaries on Android (API 31+), iOS, Linux, macOS, web, and Windows. ([#548](https://github.com/MixinNetwork/flutter-plugins/pull/548))
- Replaces the unpublished `string_tokenizer` package: `tokenize(text, options: [TokenizerUnit.wordBoundary])` becomes `wordBoundaries(text)`, which returns ranges instead of strings.

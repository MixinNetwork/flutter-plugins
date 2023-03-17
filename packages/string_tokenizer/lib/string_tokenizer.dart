import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'src/string_tokenizer_bindings_generated.dart' as binding;

final DynamicLibrary _dylib = DynamicLibrary.process();

final _bindings = binding.CFStringTokenizer(_dylib);

/// see https://developer.apple.com/documentation/corefoundation/1588024-tokenization_modifiers?language=objc
enum TokenizerUnit {
  word,
  sentence,
  paragraph,
  lineBreak,
  wordBoundary,
  attributeLatinTranscription,
  attributeLanguage,
}

extension _TokenizerUnitExtension on TokenizerUnit {
  int get value {
    switch (this) {
      case TokenizerUnit.word:
        return binding.kCFStringTokenizerUnitWord;
      case TokenizerUnit.sentence:
        return binding.kCFStringTokenizerUnitSentence;
      case TokenizerUnit.paragraph:
        return binding.kCFStringTokenizerUnitParagraph;
      case TokenizerUnit.lineBreak:
        return binding.kCFStringTokenizerUnitLineBreak;
      case TokenizerUnit.wordBoundary:
        return binding.kCFStringTokenizerUnitWordBoundary;
      case TokenizerUnit.attributeLatinTranscription:
        return binding.kCFStringTokenizerAttributeLatinTranscription;
      case TokenizerUnit.attributeLanguage:
        return binding.kCFStringTokenizerAttributeLanguage;
    }
  }
}

/// Tokenize a string into a list of tokens.
///
/// [options] empty meanings [TokenizerUnit.word].
List<String> tokenize(
  String string, {
  List<TokenizerUnit> options = const [],
}) {
  final range = malloc<binding.CFRange>();
  range.ref.location = 0;
  range.ref.length = string.length;

  final cfString = _bindings.CFStringCreateWithCString(
    nullptr,
    string.toNativeUtf8().cast(),
    binding.CFStringBuiltInEncodings.kCFStringEncodingUTF8,
  );

  int optionsInt = 0;
  for (final option in options) {
    optionsInt |= option.value;
  }

  final tokenizer = _bindings.CFStringTokenizerCreate(
    nullptr,
    cfString,
    range.ref,
    optionsInt,
    nullptr,
  );
  final tokens = <String>[];
  while (true) {
    final tokenType = _bindings.CFStringTokenizerAdvanceToNextToken(tokenizer);
    if (tokenType == 0) {
      break;
    }
    final tokenRange =
        _bindings.CFStringTokenizerGetCurrentTokenRange(tokenizer);
    final token = string.substring(
        tokenRange.location, tokenRange.location + tokenRange.length);
    tokens.add(token);
  }
  _bindings.CFRelease(tokenizer.cast());
  _bindings.CFRelease(cfString.cast());
  malloc.free(range);
  return tokens;
}

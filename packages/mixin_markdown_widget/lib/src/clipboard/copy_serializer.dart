import '../core/document.dart';

abstract class MarkdownCopySerializer {
  const MarkdownCopySerializer();

  String serialize(MarkdownDocument document);
}

/// A fragment of a parsed XML document. Nested nodes share the document text
/// and store start/end offsets. [text] creates the substring on access.
final class EpubXmlFragment {
  const EpubXmlFragment(this.document, this.start, this.end);
  final String document;
  final int start;
  final int end;
  String get text => document.substring(start, end);
}

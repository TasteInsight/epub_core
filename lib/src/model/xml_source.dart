/// A view into one shared, parsed XML document. Text is materialized on demand;
/// nested nodes retain offsets rather than repeated copies of their subtrees.
final class EpubXmlFragment {
  const EpubXmlFragment(this.document, this.start, this.end);
  final String document;
  final int start;
  final int end;
  String get text => document.substring(start, end);
}

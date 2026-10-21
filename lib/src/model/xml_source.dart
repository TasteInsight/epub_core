/// A span in shared document text, materialized by [text] on access.
/// XML parsing uses preprocessed text; HTML recovery uses original HTML.
final class EpubXmlFragment {
  /// References the half-open interval [start], [end] in [document].
  const EpubXmlFragment(this.document, this.start, this.end);

  /// Shared document text referenced by [start] and [end].
  final String document;

  /// Inclusive source offset, measured in Dart string code units.
  final int start;

  /// Exclusive source offset, measured in Dart string code units.
  final int end;

  /// Source substring for this node, materialized on access.
  String get text => document.substring(start, end);
}

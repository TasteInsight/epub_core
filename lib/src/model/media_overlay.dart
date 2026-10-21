import 'xml_source.dart';

/// A node of the SMIL body/seq/par/text/audio hierarchy.
final class EpubSmilNode {
  /// Creates a SMIL node retaining its attributes, timing, and source span.
  EpubSmilNode({
    required this.name,
    required Map<String, String> attributes,
    required Set<String> types,
    required List<EpubSmilNode> children,
    this._sourceXml = '',
    this.xmlFragment,
    this.source,
    this.textReference,
    this.clipBegin,
    this.clipEnd,
  }) : attributes = Map.unmodifiable(attributes),
       types = Set.unmodifiable(types),
       children = List.unmodifiable(children);

  /// Local element name, such as body, seq, par, text, or audio.
  final String name;

  /// Parsed SMIL attributes keyed by qualified XML name.
  final Map<String, String> attributes;

  /// Semantic type tokens from epub:type.
  final Set<String> types;

  /// Child SMIL nodes in document order.
  final List<EpubSmilNode> children;
  final String _sourceXml;

  /// Source span sharing the SMIL document, when available.
  final EpubXmlFragment? xmlFragment;

  /// Preprocessed XML obtained from [xmlFragment] or supplied source text.
  String get sourceXml => xmlFragment?.text ?? _sourceXml;

  /// Resolved src resource URI, including any fragment.
  final String? source;

  /// Resolved epub:textref URI for the associated text.
  final String? textReference;

  /// Audio clip start; parsed audio elements default to zero.
  final Duration? clipBegin;

  /// Audio clip end, when explicitly declared.
  final Duration? clipEnd;

  /// Identifier of the SMIL element.
  String? get id => attributes['id'];

  /// Descendant nodes in depth-first document order, excluding this node.
  Iterable<EpubSmilNode> get descendants sync* {
    for (final child in children) {
      yield child;
      yield* child.descendants;
    }
  }
}

/// A parsed SMIL document associating publication text with audio.
final class EpubMediaOverlay {
  /// Creates a parsed media overlay with its SMIL body tree.
  const EpubMediaOverlay({
    required this.href,
    required this.sourceXml,
    required this.body,
  });

  /// SMIL resource URI relative to the archive root.
  final String href;

  /// Original SMIL document text.
  final String sourceXml;

  /// Root body node of the parsed SMIL hierarchy.
  final EpubSmilNode body;
}

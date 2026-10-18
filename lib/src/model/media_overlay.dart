import 'xml_source.dart';

/// A node of the SMIL body/seq/par/text/audio hierarchy.
final class EpubSmilNode {
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
  final String name;
  final Map<String, String> attributes;
  final Set<String> types;
  final List<EpubSmilNode> children;
  final String _sourceXml;
  final EpubXmlFragment? xmlFragment;
  String get sourceXml => xmlFragment?.text ?? _sourceXml;
  final String? source;
  final String? textReference;
  final Duration? clipBegin;
  final Duration? clipEnd;
  String? get id => attributes['id'];
  Iterable<EpubSmilNode> get descendants sync* {
    for (final child in children) {
      yield child;
      yield* child.descendants;
    }
  }
}

final class EpubMediaOverlay {
  const EpubMediaOverlay({
    required this.href,
    required this.sourceXml,
    required this.body,
  });
  final String href;
  final String sourceXml;
  final EpubSmilNode body;
}

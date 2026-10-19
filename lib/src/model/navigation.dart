import 'xml_source.dart';

/// A navigation entry. Group labels use a null [href];
/// fragments remain URI-encoded.
final class EpubNavItem {
  EpubNavItem({
    required this.title,
    this.href,
    required List<EpubNavItem> children,
    Set<String> types = const {},
    Map<String, String> attributes = const {},
    this._sourceXml = '',
    this.xmlFragment,
  }) : types = Set.unmodifiable(types),
       attributes = Map.unmodifiable(attributes),
       children = List.unmodifiable(children);
  final Set<String> types;
  final Map<String, String> attributes;
  final String _sourceXml;
  final EpubXmlFragment? xmlFragment;
  String get sourceXml => xmlFragment?.text ?? _sourceXml;
  final String title;
  final String? href;
  final List<EpubNavItem> children;
}

/// An XHTML nav or NCX list with its types, title and entries.
final class EpubNavigationSection {
  EpubNavigationSection({
    required Set<String> types,
    required this.title,
    required this.href,
    required List<EpubNavItem> items,
    required this.sourceXml,
    this.isNcx = false,
  }) : types = Set.unmodifiable(types),
       items = List.unmodifiable(items);
  final Set<String> types;
  final String title;
  final String href;
  final List<EpubNavItem> items;
  final String sourceXml;
  final bool isNcx;
}

final class EpubNavigation {
  EpubNavigation({
    required List<EpubNavigationSection> sections,
    required Map<String, String> documents,
  }) : sections = List.unmodifiable(sections),
       documents = Map.unmodifiable(documents);
  final List<EpubNavigationSection> sections;
  final Map<String, String> documents;
  List<EpubNavItem> itemsFor(String type) =>
      sections
          .where(
            (section) =>
                section.types.contains(type) && section.items.isNotEmpty,
          )
          .firstOrNull
          ?.items ??
      const [];
  List<EpubNavItem> get toc => itemsFor('toc');
  List<EpubNavItem> get pageList => itemsFor('page-list');
  List<EpubNavItem> get landmarks => itemsFor('landmarks');
}

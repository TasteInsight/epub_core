import 'xml_source.dart';

/// A navigation entry. Group labels use a null [href];
/// fragments remain URI-encoded.
final class EpubNavItem {
  /// Creates a navigation entry with read-only children and property tokens.
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

  /// Semantic type tokens attached to this entry.
  final Set<String> types;

  /// Parsed navigation element attributes.
  final Map<String, String> attributes;
  final String _sourceXml;

  /// Source span sharing the navigation document, when available.
  final EpubXmlFragment? xmlFragment;

  /// Parsed markup obtained from [xmlFragment] or supplied source text.
  String get sourceXml => xmlFragment?.text ?? _sourceXml;

  /// Display label, including text derived from image alt attributes.
  final String title;

  /// Target URI, including any fragment; null for a grouping label.
  final String? href;

  /// Nested navigation entries in document order.
  final List<EpubNavItem> children;
}

/// An XHTML nav or NCX list with its types, title and entries.
final class EpubNavigationSection {
  /// Creates one navigation list from XHTML nav or EPUB 2 NCX.
  EpubNavigationSection({
    required Set<String> types,
    required this.title,
    required this.href,
    required List<EpubNavItem> items,
    required this.sourceXml,
    this.isNcx = false,
  }) : types = Set.unmodifiable(types),
       items = List.unmodifiable(items);

  /// Semantic navigation types, such as toc or page-list.
  final Set<String> types;

  /// Display title of this navigation section.
  final String title;

  /// URI of the navigation document relative to the archive root.
  final String href;

  /// Top-level entries in this list.
  final List<EpubNavItem> items;

  /// Source markup of the navigation section.
  final String sourceXml;

  /// Whether this list originated in an EPUB 2 NCX document.
  final bool isNcx;
}

/// Navigation lists and their original XHTML or NCX documents.
final class EpubNavigation {
  /// Creates navigation sections and their source-document lookup.
  EpubNavigation({
    required List<EpubNavigationSection> sections,
    required Map<String, String> documents,
  }) : sections = List.unmodifiable(sections),
       documents = Map.unmodifiable(documents);

  /// All parsed navigation lists in source order.
  final List<EpubNavigationSection> sections;

  /// Navigation source documents keyed by resource URI.
  final Map<String, String> documents;

  /// Entries from the first nonempty section declaring [type].
  List<EpubNavItem> itemsFor(String type) =>
      sections
          .where(
            (section) =>
                section.types.contains(type) && section.items.isNotEmpty,
          )
          .firstOrNull
          ?.items ??
      const [];

  /// Entries from the first nonempty table-of-contents section.
  List<EpubNavItem> get toc => itemsFor('toc');

  /// Entries from the first nonempty page-list section.
  List<EpubNavItem> get pageList => itemsFor('page-list');

  /// Entries from the first nonempty landmarks section.
  List<EpubNavItem> get landmarks => itemsFor('landmarks');
}

import '../errors.dart';
import 'metadata.dart';
import 'xml_source.dart';

/// Resolved publication or spine-item presentation declarations.
final class EpubRenditionSettings {
  /// Creates presentation settings with EPUB default values.
  const EpubRenditionSettings({
    this.layout = 'reflowable',
    this.orientation = 'auto',
    this.spread = 'auto',
    this.flow = 'auto',
    this.pageSpread,
  });

  /// Layout mode, such as reflowable or pre-paginated.
  final String layout;

  /// Preferred orientation, such as auto, landscape, or portrait.
  final String orientation;

  /// Synthetic spread preference, such as auto, none, or both.
  final String spread;

  /// Content flow preference, such as auto or scrolled-continuous.
  final String flow;

  /// Spine-item page placement override, when declared.
  final String? pageSpread;
}

/// An EPUB 2 guide target identifying a structural part of the publication.
final class EpubGuideReference {
  /// Creates an EPUB 2 guide reference with its XML declaration.
  EpubGuideReference({
    required this.href,
    required this.type,
    required this.title,
    required this.sourceXml,
    required Map<String, String> attributes,
  }) : attributes = Map.unmodifiable(attributes);

  /// Guide target URI resolved relative to the archive root.
  final String href;

  /// Declared guide reference type.
  final String type;

  /// Human-readable label from the guide declaration.
  final String title;

  /// Guide reference markup after XML preprocessing.
  final String sourceXml;

  /// Parsed attributes keyed by qualified XML name, including DTD defaults.
  final Map<String, String> attributes;
}

/// An EPUB media-type binding to a manifest-declared content handler.
final class EpubBinding {
  /// Creates a media-type handler binding.
  EpubBinding({
    required this.mediaType,
    required this.handler,
    required Map<String, String> attributes,
  }) : attributes = Map.unmodifiable(attributes);

  /// Media type handled by this binding.
  final String mediaType;

  /// Manifest ID of the resource implementing the handler.
  final String handler;

  /// Parsed mediaType declaration attributes.
  final Map<String, String> attributes;
}

/// A manifest resource. [href] is a URI relative to the archive root.
final class EpubManifestItem {
  /// Creates a manifest declaration with read-only properties and attributes.
  EpubManifestItem({
    required this.id,
    required this.href,
    required this.mediaType,
    required Set<String> properties,
    this.fallback,
    this.mediaOverlay,
    this.sourceXml = '',
    Map<String, String> attributes = const {},
  }) : attributes = Map.unmodifiable(attributes),
       properties = Set.unmodifiable(properties);

  /// Manifest ID of the associated SMIL media overlay.
  final String? mediaOverlay;

  /// Manifest item markup after XML preprocessing.
  final String sourceXml;

  /// Parsed attributes keyed by qualified XML name, including DTD defaults.
  final Map<String, String> attributes;

  /// Identifier used by spine, fallback, and media-overlay references.
  final String id;

  /// Resource URI resolved relative to the archive root.
  final String href;

  /// Declared MIME media type.
  final String mediaType;

  /// Whitespace-separated property tokens from the item declaration.
  final Set<String> properties;

  /// Manifest ID of the fallback resource, when declared.
  final String? fallback;

  /// HTML and XHTML content documents.
  bool get isHtmlContentDocument =>
      mediaType == 'application/xhtml+xml' || mediaType == 'text/html';

  /// Whether the declared media type belongs to the image family.
  bool get isImage => mediaType.startsWith('image/');
}

/// A reading-order entry, retaining the original ID and resolved fallback item.
final class EpubSpineItem {
  /// Creates a reading-order entry and its resolved fallback chain.
  EpubSpineItem({
    required this.idref,
    required this.item,
    required this.linear,
    required Set<String> properties,
    EpubManifestItem? sourceItem,
    List<EpubManifestItem> fallbackChain = const [],
    this.renditionSettings = const EpubRenditionSettings(),
    Map<String, String> attributes = const {},
  }) : sourceItem = sourceItem ?? item,
       fallbackChain = List.unmodifiable(fallbackChain),
       attributes = Map.unmodifiable(attributes),
       properties = Set.unmodifiable(properties);

  /// Original manifest resource referenced by [idref].
  final EpubManifestItem sourceItem;

  /// Resources visited during fallback resolution, in traversal order.
  final List<EpubManifestItem> fallbackChain;

  /// Presentation settings after applying this entry's overrides.
  final EpubRenditionSettings renditionSettings;

  /// Parsed itemref attributes keyed by qualified XML name.
  final Map<String, String> attributes;

  /// Manifest ID from the original spine itemref.
  final String idref;

  /// Selected content resource after fallback resolution.
  final EpubManifestItem item;

  /// Whether this entry belongs to the primary reading sequence.
  final bool linear;

  /// Property tokens declared on the spine itemref.
  final Set<String> properties;
}

/// Hierarchical package collections, retaining local metadata and extensions.
final class EpubCollection {
  /// Creates a package collection with read-only child collections.
  EpubCollection({
    required Set<String> roles,
    required this.metadata,
    required List<EpubLink> links,
    required List<EpubCollection> children,
    this._sourceXml = '',
    this.xmlFragment,
    required Map<String, String> attributes,
  }) : roles = Set.unmodifiable(roles),
       links = List.unmodifiable(links),
       children = List.unmodifiable(children),
       attributes = Map.unmodifiable(attributes);

  /// Declared collection role tokens.
  final Set<String> roles;

  /// Metadata local to this collection.
  final EpubMetadata metadata;

  /// Resource links declared by this collection.
  final List<EpubLink> links;

  /// Nested collections in document order.
  final List<EpubCollection> children;
  final String _sourceXml;

  /// Source span sharing the enclosing XML document, when available.
  final EpubXmlFragment? xmlFragment;

  /// Preprocessed XML obtained from [xmlFragment] or supplied source text.
  String get sourceXml => xmlFragment?.text ?? _sourceXml;

  /// Parsed collection attributes keyed by qualified XML name.
  final Map<String, String> attributes;
}

/// Parsed OPF declarations for one rendition, independent of resource caches.
final class EpubPackage {
  /// Creates the declarations for a selected OPF package document.
  EpubPackage({
    required this.path,
    required this.sourceXml,
    required this.version,
    required this.metadata,
    required List<EpubManifestItem> manifest,
    required List<EpubSpineItem> spine,
    required this.renditionSettings,
    required this.pageProgressionDirection,
    required this.ncxId,
    required List<EpubGuideReference> guide,
    required List<EpubBinding> bindings,
    required List<EpubCollection> collections,
    required List<EpubDiagnostic> diagnostics,
    required Map<String, String> attributes,
    required Map<String, String> spineAttributes,
    required Map<String, String> prefixes,
  }) : manifest = List.unmodifiable(manifest),
       spine = List.unmodifiable(spine),
       guide = List.unmodifiable(guide),
       bindings = List.unmodifiable(bindings),
       collections = List.unmodifiable(collections),
       diagnostics = List.unmodifiable(diagnostics),
       attributes = Map.unmodifiable(attributes),
       spineAttributes = Map.unmodifiable(spineAttributes),
       prefixes = Map.unmodifiable(prefixes);

  /// Package document URI relative to the archive root.
  final String path;

  /// Original OPF package document text.
  final String sourceXml;

  /// EPUB version declared on the package element.
  final String version;

  /// Publication metadata and ordered extension entries.
  final EpubMetadata metadata;

  /// Declared publication resources in document order.
  final List<EpubManifestItem> manifest;

  /// Reading-order entries with resolved fallback resources.
  final List<EpubSpineItem> spine;

  /// Package-level presentation preferences.
  final EpubRenditionSettings renditionSettings;

  /// Page progression direction, defaulting to default.
  final String pageProgressionDirection;

  /// Manifest ID of the EPUB 2 NCX document, when declared.
  final String? ncxId;

  /// EPUB 2 guide references in document order.
  final List<EpubGuideReference> guide;

  /// Media-type handler declarations.
  final List<EpubBinding> bindings;

  /// Top-level package collections.
  final List<EpubCollection> collections;

  /// Recoverable issues found while parsing this package.
  final List<EpubDiagnostic> diagnostics;

  /// Parsed package attributes keyed by qualified XML name.
  final Map<String, String> attributes;

  /// Parsed spine element attributes.
  final Map<String, String> spineAttributes;

  /// Declared property-vocabulary prefixes mapped to their namespace IRIs.
  final Map<String, String> prefixes;
}

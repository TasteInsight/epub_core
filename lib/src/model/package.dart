import '../errors.dart';
import 'metadata.dart';
import 'xml_source.dart';

/// Resolved publication or spine-item presentation declarations.
final class EpubRenditionSettings {
  const EpubRenditionSettings({
    this.layout = 'reflowable',
    this.orientation = 'auto',
    this.spread = 'auto',
    this.flow = 'auto',
    this.pageSpread,
  });
  final String layout;
  final String orientation;
  final String spread;
  final String flow;
  final String? pageSpread;
}

final class EpubGuideReference {
  EpubGuideReference({
    required this.href,
    required this.type,
    required this.title,
    required this.sourceXml,
    required Map<String, String> attributes,
  }) : attributes = Map.unmodifiable(attributes);
  final String href;
  final String type;
  final String title;
  final String sourceXml;
  final Map<String, String> attributes;
}

final class EpubBinding {
  EpubBinding({
    required this.mediaType,
    required this.handler,
    required Map<String, String> attributes,
  }) : attributes = Map.unmodifiable(attributes);
  final String mediaType;
  final String handler;
  final Map<String, String> attributes;
}

/// A manifest resource. [href] is a URI relative to the archive root.
final class EpubManifestItem {
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

  final String? mediaOverlay;
  final String sourceXml;
  final Map<String, String> attributes;

  final String id;
  final String href;
  final String mediaType;
  final Set<String> properties;
  final String? fallback;

  /// HTML and XHTML content documents.
  bool get isHtmlContentDocument =>
      mediaType == 'application/xhtml+xml' || mediaType == 'text/html';
  bool get isImage => mediaType.startsWith('image/');
}

/// A reading-order entry, retaining the original ID and resolved fallback item.
final class EpubSpineItem {
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
  final EpubManifestItem sourceItem;
  final List<EpubManifestItem> fallbackChain;
  final EpubRenditionSettings renditionSettings;
  final Map<String, String> attributes;
  final String idref;
  final EpubManifestItem item;
  final bool linear;
  final Set<String> properties;
}

/// Hierarchical package collections, retaining local metadata and extensions.
final class EpubCollection {
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
  final Set<String> roles;
  final EpubMetadata metadata;
  final List<EpubLink> links;
  final List<EpubCollection> children;
  final String _sourceXml;
  final EpubXmlFragment? xmlFragment;
  String get sourceXml => xmlFragment?.text ?? _sourceXml;
  final Map<String, String> attributes;
}

/// Parsed OPF declarations for one rendition, independent of resource caches.
final class EpubPackage {
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
  final String path;
  final String sourceXml;
  final String version;
  final EpubMetadata metadata;
  final List<EpubManifestItem> manifest;
  final List<EpubSpineItem> spine;
  final EpubRenditionSettings renditionSettings;
  final String pageProgressionDirection;
  final String? ncxId;
  final List<EpubGuideReference> guide;
  final List<EpubBinding> bindings;
  final List<EpubCollection> collections;
  final List<EpubDiagnostic> diagnostics;
  final Map<String, String> attributes;
  final Map<String, String> spineAttributes;
  final Map<String, String> prefixes;
}

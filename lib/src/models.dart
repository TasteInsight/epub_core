/// Machine-readable failures at the EPUB boundary.
enum EpubErrorCode {
  invalidArchive,
  resourceLimit,
  missingResource,
  invalidXml,
  invalidPackage,
  unsupportedVersion,
  encryptedResource,
  invalidText,
}

/// A malformed or unsupported publication, optionally tied to a resource.
class EpubException extends FormatException {
  const EpubException(this.code, String message, {this.path}) : super(message);

  final EpubErrorCode code;
  final String? path;

  @override
  String toString() =>
      'EpubException(${code.name}${path == null ? '' : ', $path'}): $message';
}

/// Memory budgets checked before resources are decompressed.
class EpubLimits {
  const EpubLimits({
    this.maxArchiveBytes = 256 * 1024 * 1024,
    this.maxEntries = 10000,
    this.maxEntryBytes = 64 * 1024 * 1024,
    this.maxUncompressedBytes = 512 * 1024 * 1024,
  });

  final int maxArchiveBytes;
  final int maxEntries;
  final int maxEntryBytes;
  final int maxUncompressedBytes;
}

/// A creator or contributor and optional EPUB role/sort key.
class EpubPerson {
  const EpubPerson(this.name, {this.role, this.fileAs});
  final String name;
  final String? role;
  final String? fileAs;
}

/// Dublin Core publication metadata. Description retains its source markup.
class EpubMetadata {
  EpubMetadata({
    required this.title,
    required this.identifier,
    required List<String> identifiers,
    required List<EpubPerson> creators,
    required List<EpubPerson> contributors,
    required List<String> languages,
    required List<String> subjects,
    this.description,
    this.publisher,
    this.rights,
    this.date,
  }) : identifiers = List.unmodifiable(identifiers),
       creators = List.unmodifiable(creators),
       contributors = List.unmodifiable(contributors),
       languages = List.unmodifiable(languages),
       subjects = List.unmodifiable(subjects);

  final String title;
  final String? identifier;
  final List<String> identifiers;
  final List<EpubPerson> creators;
  final List<EpubPerson> contributors;
  final List<String> languages;
  final List<String> subjects;
  final String? description;
  final String? publisher;
  final String? rights;
  final String? date;
}

/// A manifest resource. [href] is a URI relative to the archive root.
class EpubManifestItem {
  EpubManifestItem({
    required this.id,
    required this.href,
    required this.mediaType,
    required Set<String> properties,
    this.fallback,
  }) : properties = Set.unmodifiable(properties);

  final String id;
  final String href;
  final String mediaType;
  final Set<String> properties;
  final String? fallback;

  bool get isXhtml =>
      mediaType == 'application/xhtml+xml' || mediaType == 'text/html';
  bool get isImage => mediaType.startsWith('image/');
}

/// A reading-order entry, retaining the original ID and resolved fallback item.
class EpubSpineItem {
  EpubSpineItem({
    required this.idref,
    required this.item,
    required this.linear,
    required Set<String> properties,
  }) : properties = Set.unmodifiable(properties);
  final String idref;
  final EpubManifestItem item;
  final bool linear;
  final Set<String> properties;
}

/// A TOC node. Group labels may have no [href]; fragments remain URI-encoded.
class EpubNavItem {
  EpubNavItem({
    required this.title,
    this.href,
    required List<EpubNavItem> children,
  }) : children = List.unmodifiable(children);
  final String title;
  final String? href;
  final List<EpubNavItem> children;
}

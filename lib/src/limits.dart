/// Resource size and XML/HTML parsing limits.
final class EpubLimits {
  /// Creates archive, document, entity expansion, and resource cache limits.
  const EpubLimits({
    this.maxArchiveBytes = 256 * 1024 * 1024,
    this.maxEntries = 10000,
    this.maxEntryBytes = 64 * 1024 * 1024,
    this.maxUncompressedBytes = 512 * 1024 * 1024,
    this.maxDocumentDepth = 256,
    this.maxParseItems = 250000,
    this.maxCachedBytes = 64 * 1024 * 1024,
    this.maxEntityExpansionBytes = 1024 * 1024,
  });

  /// Maximum total size in bytes of the input ZIP archive.
  final int maxArchiveBytes;

  /// Maximum number of entries declared in the ZIP archive.
  final int maxEntries;

  /// Maximum uncompressed size in bytes of an individual resource.
  final int maxEntryBytes;

  /// Maximum combined uncompressed size in bytes of archive entries.
  final int maxUncompressedBytes;

  /// Maximum XML/HTML nesting depth and XML entity expansion depth.
  final int maxDocumentDepth;

  /// Maximum item count for each parsing stage.
  ///
  /// Limits DTD entity declarations and attribute definitions, XML events plus
  /// DTD attribute applications, HTML tokens, and nodes in the returned HTML DOM.
  /// Each stage counts its items separately against this limit.
  final int maxParseItems;

  /// Maximum total resource bytes retained by the shared cache.
  final int maxCachedBytes;

  /// Maximum cumulative entity expansion budget in UTF-16 bytes.
  ///
  /// Each expanded string contributes twice its Dart string code-unit length.
  final int maxEntityExpansionBytes;
}

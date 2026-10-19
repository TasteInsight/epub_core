/// Resource size and XML/HTML parsing limits.
final class EpubLimits {
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

  final int maxArchiveBytes;
  final int maxEntries;
  final int maxEntryBytes;
  final int maxUncompressedBytes;

  /// Maximum XML/HTML nesting depth and XML entity expansion depth.
  final int maxDocumentDepth;

  /// Maximum item count for each parsing stage.
  ///
  /// Limits DTD entity declarations and attribute definitions, XML events plus
  /// DTD attribute applications, HTML tokens, and nodes in the returned HTML DOM.
  /// Each stage counts its items separately against this limit.
  final int maxParseItems;
  final int maxCachedBytes;
  final int maxEntityExpansionBytes;
}

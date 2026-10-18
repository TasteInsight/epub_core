/// Resource and document parsing budgets. XML limits also apply to HTML tree depth
/// and token/node counts. Input bytes, tokens and returned nodes are bounded separately.
final class EpubLimits {
  const EpubLimits({
    this.maxArchiveBytes = 256 * 1024 * 1024,
    this.maxEntries = 10000,
    this.maxEntryBytes = 64 * 1024 * 1024,
    this.maxUncompressedBytes = 512 * 1024 * 1024,
    this.maxXmlDepth = 256,
    this.maxXmlNodes = 250000,
    this.maxCachedBytes = 64 * 1024 * 1024,
    this.maxEntityExpansionBytes = 1024 * 1024,
  });

  final int maxArchiveBytes;
  final int maxEntries;
  final int maxEntryBytes;
  final int maxUncompressedBytes;
  final int maxXmlDepth;
  final int maxXmlNodes;
  final int maxCachedBytes;
  final int maxEntityExpansionBytes;
}

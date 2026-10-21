import '../errors.dart';
import 'metadata.dart';

/// One rendition declared by OCF container.xml.
final class EpubRootfile {
  /// Creates a rendition declaration with its original XML attributes.
  EpubRootfile({
    required this.fullPath,
    required this.mediaType,
    required Map<String, String> attributes,
  }) : attributes = Map.unmodifiable(attributes);

  /// URI of the package document, relative to the archive root.
  final String fullPath;

  /// Declared media type of the package document.
  final String mediaType;

  /// Parsed rootfile attributes keyed by qualified XML name.
  final Map<String, String> attributes;
}

/// OCF encryption metadata. Algorithm declarations are retained even when the
/// consumer must supply the decoder for the encrypted resource.
final class EpubEncryption {
  /// Creates an encryption declaration for a publication resource.
  const EpubEncryption({
    required this.href,
    required this.algorithm,
    required this.sourceXml,
    this.id,
    this.compressionMethod,
    this.originalLength,
  });

  /// Encrypted resource URI, relative to the archive root.
  final String href;

  /// Encryption or font-obfuscation algorithm URI.
  final String algorithm;

  /// Encrypted-data element markup after XML preprocessing.
  final String sourceXml;

  /// Optional identifier of the encrypted-data declaration.
  final String? id;

  /// Declared compression method for the encrypted resource.
  final int? compressionMethod;

  /// Declared resource length in bytes before compression.
  final int? originalLength;

  /// Whether the algorithm is supported IDPF or Adobe font obfuscation.
  bool get isFontObfuscation =>
      algorithm == 'http://www.idpf.org/2008/embedding' ||
      algorithm == 'http://ns.adobe.com/pdf/enc#RC';
}

/// Archive entry information; file names are literal, hrefs are URI-encoded.
final class EpubResourceInfo {
  /// Describes the stored and expanded sizes of one ZIP entry.
  const EpubResourceInfo({
    required this.path,
    required this.href,
    required this.size,
    required this.compressedSize,
  });

  /// Literal ZIP entry name with percent characters preserved.
  final String path;

  /// URI-encoded path suitable for resource reads.
  final String href;

  /// Uncompressed resource size in bytes.
  final int size;

  /// Size in bytes of the resource payload stored in the ZIP archive.
  final int compressedSize;
}

/// OCF declarations and optional META-INF XML documents.
final class EpubContainer {
  /// Creates container declarations with read-only collection snapshots.
  EpubContainer({
    required this.sourceXml,
    required List<EpubRootfile> rootfiles,
    required List<EpubLink> links,
    required List<EpubEncryption> encryption,
    required Map<String, String> documents,
    List<EpubDiagnostic> diagnostics = const [],
  }) : diagnostics = List.unmodifiable(diagnostics),
       rootfiles = List.unmodifiable(rootfiles),
       links = List.unmodifiable(links),
       encryption = List.unmodifiable(encryption),
       documents = Map.unmodifiable(documents);

  /// Original META-INF/container.xml text.
  final String sourceXml;

  /// Recoverable issues found while reading container declarations.
  final List<EpubDiagnostic> diagnostics;

  /// Declared renditions in container document order.
  final List<EpubRootfile> rootfiles;

  /// Links declared by the container.
  final List<EpubLink> links;

  /// Resource encryption and font-obfuscation declarations.
  final List<EpubEncryption> encryption;

  /// Available META-INF XML documents keyed by archive path.
  final Map<String, String> documents;
}

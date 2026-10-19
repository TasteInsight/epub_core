import '../errors.dart';
import 'metadata.dart';

/// One rendition declared by OCF container.xml.
final class EpubRootfile {
  EpubRootfile({
    required this.fullPath,
    required this.mediaType,
    required Map<String, String> attributes,
  }) : attributes = Map.unmodifiable(attributes);
  final String fullPath;
  final String mediaType;
  final Map<String, String> attributes;
}

/// OCF encryption metadata. Algorithm declarations are retained even when the
/// consumer must supply the decoder for the encrypted resource.
final class EpubEncryption {
  const EpubEncryption({
    required this.href,
    required this.algorithm,
    required this.sourceXml,
    this.id,
    this.compressionMethod,
    this.originalLength,
  });
  final String href;
  final String algorithm;
  final String sourceXml;
  final String? id;
  final int? compressionMethod;
  final int? originalLength;
  bool get isFontObfuscation =>
      algorithm == 'http://www.idpf.org/2008/embedding' ||
      algorithm == 'http://ns.adobe.com/pdf/enc#RC';
}

/// Archive entry information; file names are literal, hrefs are URI-encoded.
final class EpubResourceInfo {
  const EpubResourceInfo({
    required this.path,
    required this.href,
    required this.size,
    required this.compressedSize,
  });
  final String path;
  final String href;
  final int size;
  final int compressedSize;
}

/// OCF declarations and optional META-INF XML documents.
final class EpubContainer {
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
  final String sourceXml;
  final List<EpubDiagnostic> diagnostics;
  final List<EpubRootfile> rootfiles;
  final List<EpubLink> links;
  final List<EpubEncryption> encryption;
  final Map<String, String> documents;
}

import 'package:xml/xml.dart';

import '../archive/resource_archive.dart';
import '../document/html_document.dart';
import '../document/xml_document.dart';
import '../epub_path.dart';
import '../errors.dart';
import '../limits.dart';
import '../model/metadata.dart';
import '../model/package.dart';
import '../vocabulary.dart';

EpubManifestItem? findCover(
  ResourceArchive archive,
  EpubMetadata metadata,
  List<EpubManifestItem> manifest,
  Map<String, EpubManifestItem> byId,
  List<EpubGuideReference> guide,
  List<EpubDiagnostic> diagnostics,
) {
  final candidates = <EpubManifestItem>[
    ...manifest.where((item) => item.properties.contains('cover-image')),
    for (final node in metadata.entries)
      if (node.name == 'meta' &&
          (node.namespaceUri == opfNamespace || node.namespaceUri.isEmpty) &&
          node.attributes['name'] == 'cover' &&
          byId[node.attributes['content']] != null)
        byId[node.attributes['content']]!,
  ];
  for (final candidate in candidates) {
    if (candidate.isImage && archive.contains(candidate.href)) return candidate;
  }
  for (final reference in guide.where(
    (ref) => tokens(ref.type).contains('cover'),
  )) {
    try {
      final path = archive.pathFor(reference.href);
      if (path == null) continue;
      final direct = manifest
          .where((item) => item.isImage && archive.pathFor(item.href) == path)
          .firstOrNull;
      if (direct != null) return direct;
      final source = archive.readText(reference.href);
      if (source == null) continue;
      for (final href in _coverImageUris(
        source,
        reference.href,
        archive.limits,
        diagnostics,
      )) {
        final imagePath = archive.pathFor(href);
        if (imagePath == null) continue;
        final item = manifest
            .where(
              (item) => item.isImage && archive.pathFor(item.href) == imagePath,
            )
            .firstOrNull;
        if (item != null) return item;
      }
    } on EpubException catch (error) {
      diagnostics.add(error.toDiagnostic());
    }
  }
  return null;
}

Iterable<String> _coverImageUris(
  String source,
  String href,
  EpubLimits limits,
  List<EpubDiagnostic> diagnostics,
) sync* {
  final XmlDocument document;
  try {
    document = parseEpubXml(source, href, limits);
  } on EpubException catch (error) {
    if (error.code != EpubErrorCode.invalidXml) rethrow;
    diagnostics.add(
      EpubDiagnostic('htmlCoverRecovery', error.message, path: href),
    );
    final html = parseEpubHtml(source, href, limits);
    final base = html.querySelector('base[href]')?.attributes['href'];
    final documentHref = base == null ? href : EpubPath.resolve(href, base);
    for (final image in html.querySelectorAll('img,image')) {
      final src =
          image.attributes['src'] ??
          image.attributes['href'] ??
          image.attributes.entries
              .where((a) => a.key.toString() == 'xlink:href')
              .firstOrNull
              ?.value;
      if (src != null) yield EpubPath.resolve(documentHref, src);
    }
    return;
  }
  final baseElement = document.descendantElements
      .where((node) => xmlIs(node, 'base', xhtmlNamespace))
      .firstOrNull;
  final base = baseElement?.getAttribute('href');
  final documentHref = base == null
      ? href
      : EpubPath.resolve(elementBase(baseElement!, href), base);
  for (final image in document.descendantElements.where(
    (node) =>
        xmlIs(node, 'img', xhtmlNamespace) ||
        xmlIs(node, 'image', 'http://www.w3.org/2000/svg'),
  )) {
    final src =
        image.getAttribute('src') ??
        image.getAttribute('href') ??
        xmlAttribute(image, 'href', 'http://www.w3.org/1999/xlink');
    if (src != null) {
      yield EpubPath.resolve(elementBase(image, documentHref), src);
    }
  }
}

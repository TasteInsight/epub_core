import 'package:xml/xml.dart';

import '../archive/resource_archive.dart';
import '../document/xml_document.dart';
import '../epub_path.dart';
import '../errors.dart';
import '../model/container.dart';
import '../model/metadata.dart';
import '../vocabulary.dart';

EpubContainer readContainer(ResourceArchive archive) {
  final diagnostics = <EpubDiagnostic>[];
  final mime = archive.readText('mimetype');
  if (mime != null && mime.trim() != 'application/epub+zip') {
    throw const EpubException(
      EpubErrorCode.invalidPackage,
      'Unexpected EPUB mimetype.',
    );
  }
  if (mime == null) {
    diagnostics.add(
      const EpubDiagnostic(
        'missingMimetype',
        'Container has no mimetype entry.',
      ),
    );
  }
  const href = 'META-INF/container.xml';
  final source = archive.readText(href);
  if (source == null) {
    throw const EpubException(
      EpubErrorCode.missingResource,
      'Container document is missing.',
      path: href,
    );
  }
  final root = parseEpubXml(source, href, archive.limits).rootElement;
  if (!xmlIs(root, 'container', ocfNamespace)) {
    throw const EpubException(
      EpubErrorCode.invalidPackage,
      'Expected an OCF container.',
      path: href,
    );
  }
  final roots = xmlChild(root, 'rootfiles', ocfNamespace);
  final rootfiles = <EpubRootfile>[];
  if (roots != null) {
    for (final entry in xmlChildren(roots, 'rootfile', ocfNamespace)) {
      final path = entry.getAttribute('full-path');
      if (path == null || EpubPath.archivePath(path) == null) {
        throw const EpubException(
          EpubErrorCode.invalidPackage,
          'Container has an invalid rootfile.',
          path: href,
        );
      }
      rootfiles.add(
        EpubRootfile(
          fullPath: path,
          mediaType: entry.getAttribute('media-type') ?? '',
          attributes: xmlAttributes(entry),
        ),
      );
    }
  }
  if (rootfiles.isEmpty) {
    throw const EpubException(
      EpubErrorCode.invalidPackage,
      'Container has no rootfiles.',
      path: href,
    );
  }
  final links = <EpubLink>[];
  for (final group in xmlChildren(root, 'links', ocfNamespace)) {
    for (final link in xmlChildren(group, 'link', ocfNamespace)) {
      final reference = link.getAttribute('href');
      if (reference != null) {
        links.add(
          EpubLink(
            href: EpubPath.resolve('', reference),
            sourceXml: xmlFragment(link).text,
            attributes: xmlAttributes(link),
            rel: tokens(link.getAttribute('rel')),
          ),
        );
      }
    }
  }
  final documents = <String, String>{href: source};
  final encryption = <EpubEncryption>[];
  for (final path in [
    'META-INF/encryption.xml',
    'META-INF/manifest.xml',
    'META-INF/metadata.xml',
    'META-INF/rights.xml',
    'META-INF/signatures.xml',
  ]) {
    try {
      final text = archive.readText(path);
      if (text == null) continue;
      documents[path] = text;
      final document = parseEpubXml(text, path, archive.limits);
      if (path != 'META-INF/encryption.xml') continue;
      if (!xmlIs(document.rootElement, 'encryption', ocfNamespace)) {
        throw EpubException(
          EpubErrorCode.invalidPackage,
          'Expected an OCF encryption document.',
          path: path,
        );
      }
      for (final node in document.descendantElements.where(
        (node) => xmlIs(node, 'EncryptedData', encryptionNamespace),
      )) {
        final method =
            xmlChild(
              node,
              'EncryptionMethod',
              encryptionNamespace,
            )?.getAttribute('Algorithm') ??
            '';
        final cipherData = xmlChild(node, 'CipherData', encryptionNamespace);
        final reference = cipherData == null
            ? null
            : xmlChild(
                cipherData,
                'CipherReference',
                encryptionNamespace,
              )?.getAttribute('URI');
        if (reference == null || reference.trim().isEmpty) {
          throw EpubException(
            EpubErrorCode.invalidPackage,
            'Encryption declarations require a resource URI.',
            path: path,
          );
        }
        final resourceHref = EpubPath.resolve('', reference);
        if (EpubPath.archivePath(resourceHref) == null) {
          throw EpubException(
            EpubErrorCode.invalidPackage,
            'Encryption declarations require a container resource path.',
            path: path,
          );
        }
        final compression = node.descendantElements
            .where(
              (node) =>
                  node.name.local == 'Compression' &&
                  node.name.namespaceUri ==
                      'http://www.idpf.org/2016/encryption#compression',
            )
            .firstOrNull;
        encryption.add(
          EpubEncryption(
            href: resourceHref,
            algorithm: method,
            id: node.getAttribute('Id'),
            sourceXml: xmlFragment(node).text,
            compressionMethod: int.tryParse(
              compression?.getAttribute('Method') ?? '',
            ),
            originalLength: int.tryParse(
              compression?.getAttribute('OriginalLength') ?? '',
            ),
          ),
        );
      }
    } on EpubException catch (error) {
      if (path == 'META-INF/encryption.xml') rethrow;
      diagnostics.add(error.toDiagnostic());
    }
  }
  return EpubContainer(
    sourceXml: source,
    rootfiles: rootfiles,
    links: links,
    encryption: encryption,
    documents: documents,
    diagnostics: diagnostics,
  );
}

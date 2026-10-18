import '../archive/resource_archive.dart';
import '../document/xml_document.dart';
import '../epub_path.dart';
import '../errors.dart';
import '../model/package.dart';
import '../vocabulary.dart';
import 'metadata_parser.dart';

EpubPackage readPackage(ResourceArchive archive, String packagePath) {
  final diagnostics = <EpubDiagnostic>[];
  final source = archive.readText(packagePath);
  if (source == null) {
    throw EpubException(
      EpubErrorCode.missingResource,
      'Package document is missing.',
      path: packagePath,
    );
  }
  final package = parseEpubXml(source, packagePath, archive.limits).rootElement;
  if (!xmlIs(package, 'package', opfNamespace)) {
    _packageError('Expected an OPF package document.', packagePath);
  }
  final version = package.getAttribute('version') ?? '';
  if (!RegExp(r'^\d+(?:\.\d+)?$').hasMatch(version)) {
    throw EpubException(
      EpubErrorCode.unsupportedVersion,
      'Package version must be numeric.',
      path: packagePath,
    );
  }
  if (!version.startsWith('2.') && !version.startsWith('3.')) {
    diagnostics.add(
      EpubDiagnostic(
        'unrecognizedVersion',
        'Processing available package structure for version $version.',
        path: packagePath,
      ),
    );
  }
  final metadataElement = xmlChild(package, 'metadata', opfNamespace);
  final manifestElement = xmlChild(package, 'manifest', opfNamespace);
  final spineElement = xmlChild(package, 'spine', opfNamespace);
  if (metadataElement == null ||
      manifestElement == null ||
      spineElement == null) {
    _packageError(
      'Package requires metadata, manifest and spine.',
      packagePath,
    );
  }
  final metadata = readMetadata(
    metadataElement,
    package.getAttribute('unique-identifier'),
    packagePath,
  );
  final prefixes = vocabularyPrefixes(package);
  final byId = <String, EpubManifestItem>{};
  for (final node in xmlChildren(manifestElement, 'item', opfNamespace)) {
    final id = node.getAttribute('id');
    final reference = node.getAttribute('href');
    final type = node.getAttribute('media-type');
    if (id == null ||
        id.isEmpty ||
        reference == null ||
        reference.isEmpty ||
        type == null ||
        type.isEmpty ||
        byId.containsKey(id)) {
      _packageError(
        'Manifest items require unique IDs, hrefs and media types.',
        packagePath,
      );
    }
    final href = EpubPath.resolve(elementBase(node, packagePath), reference);
    if (!EpubPath.isExternal(href) && EpubPath.archivePath(href) == null) {
      _packageError('Invalid manifest resource URI.', href);
    }
    byId[id] = EpubManifestItem(
      id: id,
      href: href,
      mediaType: type,
      properties: tokens(node.getAttribute('properties')),
      fallback: node.getAttribute('fallback'),
      mediaOverlay: node.getAttribute('media-overlay'),
      sourceXml: xmlFragment(node).text,
      attributes: xmlAttributes(node),
    );
  }
  final spine = <EpubSpineItem>[];
  for (final node in xmlChildren(spineElement, 'itemref', opfNamespace)) {
    final idref = node.getAttribute('idref') ?? '';
    final original = byId[idref];
    if (original == null) {
      _packageError(
        'Spine references an unknown manifest ID: $idref.',
        packagePath,
      );
    }
    var item = original;
    final chain = <EpubManifestItem>[original];
    final visited = <String>{};
    bool supported(EpubManifestItem entry) =>
        entry.isHtmlContentDocument ||
        entry.mediaType == 'image/svg+xml' ||
        ((double.tryParse(version) ?? 3) < 3 &&
            const {
              'application/x-dtbook+xml',
              'text/x-oeb1-document',
            }.contains(entry.mediaType));
    while (!supported(item)) {
      if (!visited.add(item.id)) {
        _packageError('Cyclic manifest fallback.', item.href);
      }
      if (item.fallback == null) {
        diagnostics.add(
          EpubDiagnostic(
            'unsupportedSpineContent',
            'Spine content requires a renderer for ${original.mediaType}.',
            path: original.href,
          ),
        );
        item = original;
        break;
      }
      final next = byId[item.fallback];
      if (next == null) {
        _packageError(
          'Fallback references an unknown manifest ID: ${item.fallback}.',
          packagePath,
        );
      }
      item = next;
      chain.add(item);
    }
    if (!EpubPath.isExternal(item.href) && !archive.contains(item.href)) {
      throw EpubException(
        EpubErrorCode.missingResource,
        'Spine resource is missing.',
        path: item.href,
      );
    }
    final properties = tokens(node.getAttribute('properties'));
    spine.add(
      EpubSpineItem(
        idref: idref,
        sourceItem: original,
        item: item,
        fallbackChain: chain,
        linear: node.getAttribute('linear') != 'no',
        properties: properties,
        renditionSettings: readRenditionSettings(
          metadata,
          properties: properties,
          prefixes: prefixes,
        ),
        attributes: xmlAttributes(node),
      ),
    );
  }
  if (spine.isEmpty) _packageError('Package has an empty spine.', packagePath);
  final manifest = byId.values.toList();
  for (final item in manifest) {
    if (item.mediaOverlay != null &&
        byId[item.mediaOverlay]?.mediaType != 'application/smil+xml') {
      diagnostics.add(
        EpubDiagnostic(
          'invalidMediaOverlayReference',
          'media-overlay does not reference a SMIL manifest item.',
          path: item.href,
        ),
      );
    }
  }
  final guide = <EpubGuideReference>[];
  final guideElement = xmlChild(package, 'guide', opfNamespace);
  if (guideElement != null) {
    for (final node in xmlChildren(guideElement, 'reference', opfNamespace)) {
      try {
        guide.add(
          EpubGuideReference(
            href: EpubPath.resolve(
              elementBase(node, packagePath),
              node.getAttribute('href') ?? '',
            ),
            type: node.getAttribute('type') ?? '',
            title: node.getAttribute('title') ?? '',
            sourceXml: xmlFragment(node).text,
            attributes: xmlAttributes(node),
          ),
        );
      } on EpubException catch (error) {
        diagnostics.add(
          EpubDiagnostic(error.code.name, error.message, path: error.path),
        );
      }
    }
  }
  final bindingsElement = xmlChild(package, 'bindings', opfNamespace);
  final bindings = <EpubBinding>[
    if (bindingsElement != null)
      for (final node in xmlChildren(
        bindingsElement,
        'mediaType',
        opfNamespace,
      ))
        EpubBinding(
          mediaType: node.getAttribute('media-type') ?? '',
          handler: node.getAttribute('handler') ?? '',
          attributes: xmlAttributes(node),
        ),
  ];
  return EpubPackage(
    path: packagePath,
    sourceXml: source,
    version: version,
    metadata: metadata,
    manifest: manifest,
    spine: spine,
    ncxId: spineElement.getAttribute('toc'),
    diagnostics: diagnostics,
    pageProgressionDirection:
        spineElement.getAttribute('page-progression-direction') ?? 'default',
    renditionSettings: readRenditionSettings(metadata),
    guide: guide,
    bindings: bindings,
    collections: xmlChildren(
      package,
      'collection',
      opfNamespace,
    ).map((node) => readCollection(node, packagePath)).toList(),
    attributes: xmlAttributes(package),
    spineAttributes: xmlAttributes(spineElement),
    prefixes: prefixes,
  );
}

Never _packageError(String message, String path) =>
    throw EpubException(EpubErrorCode.invalidPackage, message, path: path);

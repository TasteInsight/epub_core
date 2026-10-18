part of 'epub_book.dart';

EpubBook _readPackage(ResourceArchive archive) {
  final warnings = <String>[];
  final mime = archive.readText('mimetype');
  if (mime != null && mime.trim() != 'application/epub+zip') {
    throw const EpubException(
      EpubErrorCode.invalidPackage,
      'Unexpected EPUB mimetype.',
    );
  }
  if (mime == null) warnings.add('The container has no mimetype entry.');
  final container = _xml(archive, 'META-INF/container.xml');
  final roots = container.descendantElements.where(
    (node) => node.name.local == 'rootfile',
  );
  final rootfile =
      roots
          .where(
            (node) =>
                node.getAttribute('media-type') ==
                'application/oebps-package+xml',
          )
          .firstOrNull ??
      roots.firstOrNull;
  final packagePath = rootfile?.getAttribute('full-path');
  if (packagePath == null || EpubPath.archivePath(packagePath) == null) {
    throw const EpubException(
      EpubErrorCode.invalidPackage,
      'Container has no usable package path.',
    );
  }
  final encryptionPath = 'META-INF/encryption.xml';
  if (archive.contains(encryptionPath)) {
    for (final node in _xml(archive, encryptionPath).descendantElements.where(
      (node) => node.name.local == 'CipherReference',
    )) {
      final reference = node.getAttribute('URI');
      final path = reference == null ? null : archive.pathFor(reference);
      if (path != null) archive.encryptedPaths.add(path);
    }
  }
  final package = _xml(archive, packagePath).rootElement;
  if (package.name.local != 'package') {
    _packageError('Expected an OPF package document.', packagePath);
  }
  final version = package.getAttribute('version') ?? '';
  if (!RegExp(r'^[23]\.\d+$').hasMatch(version)) {
    throw EpubException(
      EpubErrorCode.unsupportedVersion,
      'Supported EPUB versions are 2.x and 3.x.',
      path: packagePath,
    );
  }
  final metadata = _child(package, 'metadata');
  final manifestElement = _child(package, 'manifest');
  final spineElement = _child(package, 'spine');
  if (metadata == null || manifestElement == null || spineElement == null) {
    _packageError(
      'Package requires metadata, manifest and spine.',
      packagePath,
    );
  }
  final byId = <String, EpubManifestItem>{};
  for (final node in _children(manifestElement, 'item')) {
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
    final href = EpubPath.resolve(packagePath, reference);
    if (!EpubPath.isExternal(href) && EpubPath.archivePath(href) == null) {
      _packageError('Invalid manifest resource URI.', href);
    }
    byId[id] = EpubManifestItem(
      id: id,
      href: href,
      mediaType: type,
      properties: _tokens(node.getAttribute('properties')),
      fallback: node.getAttribute('fallback'),
    );
  }
  final spine = <EpubSpineItem>[];
  for (final node in _children(spineElement, 'itemref')) {
    final idref = node.getAttribute('idref') ?? '';
    var item = byId[idref];
    final visited = <String>{};
    while (item != null && !item.isXhtml && item.mediaType != 'image/svg+xml') {
      if (!visited.add(item.id)) {
        _packageError('Cyclic manifest fallback.', item.href);
      }
      item = byId[item.fallback];
    }
    if (item == null) {
      _packageError(
        'Spine entry has no supported manifest resource: $idref.',
        packagePath,
      );
    }
    archive.ensureReadable(item.href);
    spine.add(
      EpubSpineItem(
        idref: idref,
        item: item,
        linear: node.getAttribute('linear') != 'no',
        properties: _tokens(node.getAttribute('properties')),
      ),
    );
  }
  if (spine.isEmpty) _packageError('Package has an empty spine.', packagePath);

  final manifest = byId.values.toList();
  final navigation = _readNavigation(
    archive,
    manifest,
    byId[spineElement.getAttribute('toc')],
    warnings,
  );
  final cover = _findCover(
    archive,
    packagePath,
    package,
    metadata,
    manifest,
    byId,
    warnings,
  );
  return EpubBook._(
    archive: archive,
    packagePath: packagePath,
    version: version,
    metadata: _readMetadata(
      metadata,
      package.getAttribute('unique-identifier'),
    ),
    manifest: manifest,
    spine: spine,
    navigation: navigation,
    warnings: warnings,
    pageProgressionDirection:
        spineElement.getAttribute('page-progression-direction') ?? 'default',
    cover: cover,
  );
}

EpubMetadata _readMetadata(XmlElement metadata, String? identifierId) {
  List<String> values(String name) => _children(metadata, name)
      .map((node) => node.innerText.trim())
      .where((text) => text.isNotEmpty)
      .toList();
  String? first(String name) => values(name).firstOrNull;
  String? refinement(XmlElement node, String property) =>
      _children(metadata, 'meta')
          .where(
            (meta) =>
                node.getAttribute('id') != null &&
                meta.getAttribute('refines') == '#${node.getAttribute('id')}' &&
                meta.getAttribute('property') == property,
          )
          .map((meta) => meta.innerText.trim())
          .firstOrNull;
  List<EpubPerson> people(String name) => [
    for (final node in _children(metadata, name))
      if (node.innerText.trim().isNotEmpty)
        EpubPerson(
          node.innerText.trim(),
          role: refinement(node, 'role') ?? _attribute(node, 'role'),
          fileAs: refinement(node, 'file-as') ?? _attribute(node, 'file-as'),
        ),
  ];
  final identifiers = values('identifier');
  return EpubMetadata(
    title: first('title') ?? '',
    identifier:
        _children(metadata, 'identifier')
            .where(
              (node) =>
                  identifierId != null &&
                  node.getAttribute('id') == identifierId,
            )
            .firstOrNull
            ?.innerText
            .trim() ??
        identifiers.firstOrNull,
    identifiers: identifiers,
    creators: people('creator'),
    contributors: people('contributor'),
    languages: values('language'),
    subjects: values('subject'),
    description: first('description'),
    publisher: first('publisher'),
    rights: first('rights'),
    date: first('date'),
  );
}

EpubManifestItem? _findCover(
  ResourceArchive archive,
  String packagePath,
  XmlElement package,
  XmlElement metadata,
  List<EpubManifestItem> manifest,
  Map<String, EpubManifestItem> byId,
  List<String> warnings,
) {
  final candidates = <EpubManifestItem>[
    ...manifest.where((item) => item.properties.contains('cover-image')),
    for (final node in _children(metadata, 'meta'))
      if (node.getAttribute('name') == 'cover' &&
          byId[node.getAttribute('content')] != null)
        byId[node.getAttribute('content')]!,
  ];
  for (final candidate in candidates) {
    if (candidate.isImage && archive.contains(candidate.href)) return candidate;
  }
  final guide = _child(package, 'guide');
  if (guide == null) return null;
  final reference = _children(guide, 'reference')
      .where((node) => _tokens(node.getAttribute('type')).contains('cover'))
      .firstOrNull
      ?.getAttribute('href');
  if (reference == null) return null;
  try {
    final href = EpubPath.resolve(packagePath, reference);
    final direct = manifest
        .where(
          (item) =>
              item.isImage &&
              archive.pathFor(item.href) != null &&
              archive.pathFor(item.href) == archive.pathFor(href),
        )
        .firstOrNull;
    if (direct != null) return direct;
    final source = archive.readText(href);
    if (source == null) return null;
    final document = html.parse(source);
    final base = document.querySelector('base[href]')?.attributes['href'];
    final documentHref = base == null ? href : EpubPath.resolve(href, base);
    for (final image in document.querySelectorAll('img, image')) {
      final src =
          image.attributes['src'] ??
          image.attributes['href'] ??
          image.attributes[const dom.AttributeName(
            'xlink',
            'href',
            'http://www.w3.org/1999/xlink',
          )];
      final path = src == null
          ? null
          : archive.pathFor(EpubPath.resolve(documentHref, src));
      if (path == null) continue;
      final item = manifest
          .where((item) => item.isImage && archive.pathFor(item.href) == path)
          .firstOrNull;
      if (item != null) return item;
    }
  } on EpubException catch (error) {
    warnings.add(error.toString());
  }
  return null;
}

XmlDocument _xml(ResourceArchive archive, String href) {
  final source = archive.readText(href);
  if (source == null) {
    throw EpubException(
      EpubErrorCode.missingResource,
      'Required XML resource is missing.',
      path: href,
    );
  }
  try {
    return XmlDocument.parse(source);
  } on XmlException catch (error) {
    throw EpubException(EpubErrorCode.invalidXml, error.message, path: href);
  }
}

Iterable<XmlElement> _children(XmlElement parent, String name) =>
    parent.childElements.where((node) => node.name.local == name);
XmlElement? _child(XmlElement parent, String name) =>
    _children(parent, name).firstOrNull;
String? _attribute(XmlElement node, String name) => node.attributes
    .where((attribute) => attribute.name.local == name)
    .firstOrNull
    ?.value;
Set<String> _tokens(String? value) => (value ?? '')
    .split(RegExp(r'\s+'))
    .where((token) => token.isNotEmpty)
    .toSet();
Never _packageError(String message, String path) =>
    throw EpubException(EpubErrorCode.invalidPackage, message, path: path);

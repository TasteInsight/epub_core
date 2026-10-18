import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:csslib/parser.dart' as css;
import 'package:csslib/visitor.dart' show StyleSheet;
import 'package:html/dom.dart' as dom;
import 'package:xml/xml.dart';

import 'archive/resource_archive.dart';
import 'document/html_document.dart';
import 'document/xml_document.dart';
import 'epub_path.dart';
import 'errors.dart';
import 'limits.dart';
import 'model/container.dart';
import 'model/media_overlay.dart';
import 'model/metadata.dart';
import 'model/navigation.dart';
import 'model/package.dart';
import 'parsing/container_parser.dart';
import 'parsing/cover_parser.dart';
import 'parsing/media_overlay.dart';
import 'parsing/metadata_parser.dart';
import 'parsing/navigation.dart';
import 'parsing/package_parser.dart';
import 'vocabulary.dart';

/// A selected rendition and its shared container resources.
/// Parsing and resource reads perform no network or filesystem I/O.
final class EpubBook {
  factory EpubBook.fromBytes(
    List<int> bytes, {
    EpubLimits limits = const EpubLimits(),
    String? packagePath,
  }) {
    final archive = ResourceArchive(bytes, limits);
    final container = readContainer(archive);
    return EpubBook._open(archive, container, packagePath);
  }

  factory EpubBook._open(
    ResourceArchive archive,
    EpubContainer container,
    String? path,
  ) {
    final package = readPackage(
      archive,
      _selectRootfile(container, path).fullPath,
    );
    final byId = {for (final item in package.manifest) item.id: item};
    final diagnostics = [...container.diagnostics, ...package.diagnostics];
    final navigation = readNavigation(
      archive,
      package.manifest,
      byId[package.ncxId],
      diagnostics,
    );
    final cover = findCover(
      archive,
      package.metadata,
      package.manifest,
      byId,
      package.guide,
      diagnostics,
    );
    return EpubBook._(
      archive,
      container,
      package,
      navigation,
      cover,
      diagnostics,
    );
  }

  EpubBook._(
    this._archive,
    this.container,
    this.package,
    this.readingNavigation,
    this.cover,
    List<EpubDiagnostic> diagnostics,
  ) : diagnostics = List.unmodifiable(diagnostics) {
    for (final item in manifest) {
      _itemsById[item.id] = item;
      _itemsByUri.putIfAbsent(_resourceKey(item.href), () => item);
    }
    for (final (index, entry) in spine.indexed) {
      _spineByUri.putIfAbsent(_resourceKey(entry.item.href), () => index);
      _spineByUri.putIfAbsent(_resourceKey(entry.sourceItem.href), () => index);
    }
  }
  final ResourceArchive _archive;
  final _itemsById = <String, EpubManifestItem>{};
  final _itemsByUri = <String, EpubManifestItem>{};
  final _spineByUri = <String, int>{};
  final _overlayCache = <String, EpubMediaOverlay>{};
  final EpubContainer container;
  final EpubPackage package;
  final EpubNavigation readingNavigation;
  final EpubManifestItem? cover;
  final List<EpubDiagnostic> diagnostics;
  String get packagePath => package.path;
  String get packageXml => package.sourceXml;
  String get version => package.version;
  EpubMetadata get metadata => package.metadata;
  List<EpubManifestItem> get manifest => package.manifest;
  List<EpubSpineItem> get spine => package.spine;
  EpubRenditionSettings get renditionSettings => package.renditionSettings;
  String get pageProgressionDirection => package.pageProgressionDirection;
  List<EpubGuideReference> get guide => package.guide;
  List<EpubBinding> get bindings => package.bindings;
  List<EpubCollection> get collections => package.collections;
  Map<String, String> get attributes => package.attributes;
  Map<String, String> get spineAttributes => package.spineAttributes;
  Map<String, String> get prefixes => package.prefixes;

  /// The default table of contents, retained for existing consumers.
  List<EpubNavItem> get navigation => readingNavigation.toc;
  @Deprecated(
    'Use readingNavigation for the aggregate of navigation documents.',
  )
  EpubNavigation get navigationDocument => readingNavigation;
  @Deprecated('Use renditionSettings.')
  EpubRenditionSettings get rendition => renditionSettings;
  List<String> get warnings =>
      List.unmodifiable(diagnostics.map((d) => d.toString()));
  List<EpubResourceInfo> get resources => _archive.resources;

  /// Selects another rendition while sharing container diagnostics and byte cache.
  EpubBook openRendition(String packagePath) =>
      EpubBook._open(_archive, container, packagePath);
  EpubManifestItem? itemById(String id) => _itemsById[id];
  EpubManifestItem? itemByHref(String href) => _itemsByUri[_resourceKey(href)];
  int spineIndexOfHref(String href) => _spineByUri[_resourceKey(href)] ?? -1;
  String _resourceKey(String href) =>
      _archive.pathFor(href) ??
      EpubPath.archivePath(href) ??
      EpubPath.parse(href).removeFragment().toString();

  late final String? _obfuscationIdentifier = _defaultIdentifier();
  String? _defaultIdentifier() {
    final defaultPath = _selectRootfile(container, null).fullPath;
    if (EpubPath.archivePath(defaultPath) ==
        EpubPath.archivePath(packagePath)) {
      return metadata.identifier;
    }
    final source = _archive.readText(defaultPath);
    if (source == null) return null;
    final root = parseEpubXml(source, defaultPath, _archive.limits).rootElement;
    final element = xmlChild(root, 'metadata', opfNamespace);
    return element == null
        ? null
        : readMetadata(
            element,
            root.getAttribute('unique-identifier'),
            defaultPath,
          ).identifier;
  }

  /// Original ZIP resource bytes, including obfuscated/encrypted EPUB payloads.
  /// ZIP encryption itself is unsupported. CRC and size limits still apply.
  Uint8List? readRawBytes(String href) => _archive.read(href);

  /// Reads resources, deobfuscating standard IDPF/Adobe font resources.
  /// Other encryption algorithms retain their declarations and require a decoder.
  Uint8List? readBytes(String href) {
    final path = _archive.pathFor(href);
    if (path == null) return null;
    final declarations = container.encryption
        .where((entry) => _archive.pathFor(entry.href) == path)
        .toList();
    if (declarations.isEmpty) return readRawBytes(href);
    if (declarations.length != 1 || !declarations.single.isFontObfuscation) {
      throw EpubException(
        EpubErrorCode.encryptedResource,
        'Resource requires a decoder for its declared encryption algorithm.',
        path: href,
      );
    }
    final encryption = declarations.single;
    final identifier = _obfuscationIdentifier;
    if (identifier == null || identifier.isEmpty) {
      throw EpubException(
        EpubErrorCode.encryptedResource,
        'Font obfuscation requires a unique publication identifier.',
        path: href,
      );
    }
    final List<int> key;
    final int length;
    if (encryption.algorithm == 'http://www.idpf.org/2008/embedding') {
      key = sha1
          .convert(
            utf8.encode(
              identifier.replaceAll(RegExp(r'[\x20\x09\x0d\x0a]'), ''),
            ),
          )
          .bytes;
      length = 1040;
    } else {
      final uuid = identifier
          .replaceFirst(RegExp(r'^urn:uuid:', caseSensitive: false), '')
          .replaceAll('-', '')
          .trim();
      if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(uuid)) {
        throw EpubException(
          EpubErrorCode.encryptedResource,
          'Adobe font obfuscation requires a UUID identifier.',
          path: href,
        );
      }
      key = [
        for (var i = 0; i < uuid.length; i += 2)
          int.parse(uuid.substring(i, i + 2), radix: 16),
      ];
      length = 1024;
    }
    final bytes = Uint8List.fromList(readRawBytes(href)!);
    for (var i = 0; i < length && i < bytes.length; i++) {
      bytes[i] ^= key[i % key.length];
    }
    return bytes.asUnmodifiableView();
  }

  String? readString(String href) {
    final bytes = readBytes(href);
    return bytes == null ? null : ResourceArchive.decodeText(bytes, href);
  }

  /// A fresh DOM for XML, XHTML, SVG, MathML, DTBook or META-INF documents.
  XmlDocument? readXmlDocument(String href) {
    final source = readString(href);
    return source == null ? null : parseEpubXml(source, href, _archive.limits);
  }

  /// HTML5 recovery is explicit; use readXmlDocument for XHTML namespace semantics.
  dom.Document? readHtmlDocument(String href) {
    final source = readString(href);
    return source == null ? null : parseEpubHtml(source, href, _archive.limits);
  }

  /// CSS syntax is handled by csslib; errors remain available to the caller.
  ({StyleSheet stylesheet, List<String> errors})? readCssDocument(String href) {
    final source = readString(href);
    if (source == null) return null;
    final errors = <css.Message>[];
    final stylesheet = css.parse(source, errors: errors);
    return (
      stylesheet: stylesheet,
      errors: List.unmodifiable(errors.map((error) => error.toString())),
    );
  }

  /// Reads a SMIL resource by its manifest ID.
  EpubMediaOverlay readMediaOverlayById(String id) =>
      _readOverlay(itemById(id), id);

  /// Reads a SMIL resource by its container-relative URI.
  EpubMediaOverlay readMediaOverlayByHref(String href) =>
      _readOverlay(itemByHref(href), href);

  /// Legacy lookup. Ambiguous ID/URI matches report ambiguousReference.
  @Deprecated('Use readMediaOverlayById or readMediaOverlayByHref.')
  EpubMediaOverlay readMediaOverlay(String idOrHref) {
    final byId = itemById(idOrHref);
    final byHref = itemByHref(idOrHref);
    if (byId != null && byHref != null && byId != byHref) {
      throw EpubException(
        EpubErrorCode.ambiguousReference,
        'Reference matches different manifest ID and URI resources.',
        path: idOrHref,
      );
    }
    return _readOverlay(byId ?? byHref, idOrHref);
  }

  EpubMediaOverlay _readOverlay(EpubManifestItem? item, String reference) {
    if (item == null || item.mediaType != 'application/smil+xml') {
      throw EpubException(
        EpubErrorCode.invalidMediaOverlay,
        'No SMIL manifest resource matches this reference.',
        path: reference,
      );
    }
    return _overlayCache.putIfAbsent(
      item.href,
      () => readMediaOverlayDocument(
        readString(item.href),
        item.href,
        _archive.limits,
      ),
    );
  }

  /// Parses all declared SMIL documents on first access; failures are propagated.
  List<EpubMediaOverlay> get mediaOverlays => List.unmodifiable(
    manifest
        .where((item) => item.mediaType == 'application/smil+xml')
        .map((item) => readMediaOverlayById(item.id)),
  );

  /// Clears shared byte cache and this rendition's media overlay cache.
  void clearResourceCache() {
    _archive.clearCache();
    _overlayCache.clear();
  }
}

EpubRootfile _selectRootfile(EpubContainer container, String? path) {
  if (path == null) {
    return container.rootfiles
            .where((root) => root.mediaType == 'application/oebps-package+xml')
            .firstOrNull ??
        container.rootfiles.first;
  }
  final selected = container.rootfiles
      .where(
        (root) =>
            EpubPath.archivePath(root.fullPath) == EpubPath.archivePath(path),
      )
      .firstOrNull;
  if (selected == null) {
    throw EpubException(
      EpubErrorCode.invalidPackage,
      'Requested rendition is not declared by the container.',
      path: path,
    );
  }
  return selected;
}

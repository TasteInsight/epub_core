import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';

import 'epub_path.dart';
import 'models.dart';
import 'resource_archive.dart';

part 'package_parser.dart';
part 'navigation.dart';

/// A publication parsed entirely in memory, with lazy resource reads.
///
/// This class performs no filesystem or network I/O. Its data can cross Dart
/// isolate boundaries. Resource bytes and exposed collections are read-only.
class EpubBook {
  factory EpubBook.fromBytes(
    List<int> bytes, {
    EpubLimits limits = const EpubLimits(),
  }) => _readPackage(ResourceArchive(bytes, limits));

  EpubBook._({
    required ResourceArchive archive,
    required this.packagePath,
    required this.version,
    required this.metadata,
    required List<EpubManifestItem> manifest,
    required List<EpubSpineItem> spine,
    required List<EpubNavItem> navigation,
    required List<String> warnings,
    required this.pageProgressionDirection,
    this.cover,
  }) : _archive = archive,
       manifest = List.unmodifiable(manifest),
       spine = List.unmodifiable(spine),
       navigation = List.unmodifiable(navigation),
       warnings = List.unmodifiable(warnings) {
    for (final item in manifest) {
      final path = archive.pathFor(item.href);
      if (path != null) _itemsByPath.putIfAbsent(path, () => item);
    }
    for (final (index, entry) in spine.indexed) {
      final path = archive.pathFor(entry.item.href);
      if (path != null) _spineByPath.putIfAbsent(path, () => index);
    }
  }

  final ResourceArchive _archive;
  final _itemsByPath = <String, EpubManifestItem>{};
  final _spineByPath = <String, int>{};

  /// Root-relative URI of the selected OPF package document.
  final String packagePath;
  final String version;
  final EpubMetadata metadata;
  final List<EpubManifestItem> manifest;
  final List<EpubSpineItem> spine;
  final List<EpubNavItem> navigation;
  final String pageProgressionDirection;
  final EpubManifestItem? cover;

  /// Recoverable navigation/cover errors. Required package/spine failures throw.
  final List<String> warnings;

  EpubManifestItem? itemByHref(String href) =>
      _itemsByPath[_archive.pathFor(href)];
  int spineIndexOfHref(String href) =>
      _spineByPath[_archive.pathFor(href)] ?? -1;

  /// Reads a root-relative resource URI. Missing/external references return null;
  /// corrupt or encrypted resources throw [EpubException].
  Uint8List? readBytes(String href) => _archive.read(href);

  /// Decodes UTF-8 or UTF-16 resource text. Does not transform XHTML markup.
  String? readString(String href) => _archive.readText(href);
}

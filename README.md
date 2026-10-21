# epub_core

A pure Dart EPUB 2/3 parser for Flutter, Dart VM, and Web. Read publication
structure, metadata, reading order, navigation, and resources on demand.

[中文文档](README.zh-CN.md)

## Installation

```sh
dart pub add epub_core
```

Requires Dart 3.12 or later.

## Read a publication

```dart
import 'package:epub_core/epub_core.dart';

void inspectBook(List<int> bytes) {
  final book = EpubBook.fromBytes(bytes);
  print(book.metadata.title);
  print(book.metadata.creators.map((person) => person.name).join(', '));

  for (final entry in book.spine.where((entry) => entry.linear)) {
    print('${entry.sourceItem.mediaType}: ${entry.sourceItem.href}');
    if (entry.item.isHtmlContentDocument) {
      print(book.readString(entry.item.href));
    }
  }

  for (final page in book.readingNavigation.pageList) {
    print('${page.title}: ${page.href}');
  }
  final cover = book.cover;
  if (cover != null) print(book.readBytes(cover.href)?.length);
}
```

`spine[].item` is the selected content resource. `sourceItem` retains the original
manifest item, and `fallbackChain` records the resources visited during fallback
resolution. Applications can inspect each manifest item's `fallback` declaration
and select handlers for content formats they support.

Applications own rendering, chapter segmentation, and persistence.

## Publication structure

| API | Contents |
| --- | --- |
| `container` | Renditions, links, encryption declarations, and META-INF XML |
| `metadata` | Dublin Core values, refinements, language, direction, property IRIs, and links |
| `package` | OPF metadata, resource declarations, and reading order |
| `manifest` / `spine` | Resources, reading-order references, and fallback chains |
| `readingNavigation` | EPUB 3 nav lists and EPUB 2 NCX lists |
| `renditionSettings` / `spine[].renditionSettings` | Global and local presentation settings |
| `collections` / `bindings` / `guide` | Collections, media-type handlers, and EPUB 2 navigation |
| `mediaOverlays` | SMIL trees, text references, audio clips, and clock values |
| `packageXml` / `resources` | Original OPF text and ZIP entry information |

Use `readingNavigation.toc`, `pageList`, and `landmarks` for the corresponding
navigation lists. The [format support guide](doc/format-support.md) and
[validation record](doc/validation.md) describe supported features, resource
limits, and validation results in Chinese.

## Metadata and resources

```dart
final book = EpubBook.fromBytes(bytes);
final alternate = book.openRendition(book.container.rootfiles.last.fullPath);
final titles = book.metadata.values('title');
final properties = book.metadata.properties('http://purl.org/dc/terms/modified');
final xml = book.readXmlDocument(book.packagePath);
final cssItem = book.manifest.where((item) => item.mediaType == 'text/css').firstOrNull;
final stylesheet = cssItem == null ? null : book.readCssDocument(cssItem.href);
```

Convenience fields such as `metadata.title` and `metadata.creators` are extracted
from ordered metadata entries. `refinementsFor` and `properties` use indexed
lookups. Use `EpubMetadata.fromEntries` to derive these fields from entries, or
the `EpubMetadata` constructor to supply them explicitly.

`readXmlDocument` preserves XML namespaces; `readHtmlDocument` builds an HTML5 DOM.
`readBytes` deobfuscates IDPF/Adobe fonts; `readRawBytes` returns the original ZIP
payload. Commercial DRM declarations and payloads are available for an
application's authorized decoder.

Read media overlays by manifest ID or resource URI:

```dart
final overlay = book.readMediaOverlayById('chapter-audio');
final sameResource = book.readMediaOverlayByHref(overlay.href);
```

## Resource URIs and errors

Resource URIs are relative to the archive root. Resolve document references with
`EpubPath.resolve(documentHref, reference)`. Byte reads return `null` for missing
or external resources. Malformed URIs throw `EpubException` with
`EpubErrorCode.invalidUri`.

```dart
try {
  final book = EpubBook.fromBytes(
    bytes,
    limits: const EpubLimits(maxCachedBytes: 32 * 1024 * 1024),
  );
  for (final diagnostic in book.diagnostics) {
    print('${diagnostic.code}: ${diagnostic.path}: ${diagnostic.message}');
  }
} on EpubException catch (error) {
  print('${error.code.name}: ${error.path}: ${error.message}');
}
```

`container.diagnostics` contains container issues. Each rendition's `diagnostics`
includes both container and rendition issues. Recoverable META-INF failures
retain the original resources and produce diagnostics. Invalid encryption XML
and encryption entries with missing resource paths throw exceptions.

`container.encryption` retains resource encryption declarations. `readBytes`
reports `encryptedResource` when an external decoder is required. XML errors
retain the resource path and available `offset`, `line`, and `column` values.
`locationSource` identifies original resource text, expanded XML, or entity
replacement text; entity replacement errors also expose `entityName`.

## Models and limits

Resources are decompressed, checked, and cached on demand. `EpubLimits` bounds
archive sizes, entry counts, document complexity, entity expansion, and cache
capacity. `maxDocumentDepth` limits XML/HTML nesting and entity expansion depth;
`maxParseItems` bounds the item count independently in each parsing stage.

Model collections and resource bytes are read-only. Parsed books support Dart
isolates; Flutter Web's `compute` uses the current event loop.
`clearResourceCache()` clears the shared byte cache and the current rendition's
media overlay cache. Nested XML nodes share source text through source spans.
Public data classes are `final`; applications can compose their own models with
these objects to attach business data.

## Development

ZIP, XML, HTML, CSS, hashing, and declaration grammars use `archive`, `xml`,
`html`, `csslib`, `crypto`, and `petitparser`.

```sh
dart pub get
dart format --output=none --set-exit-if-changed lib test example tool
dart analyze --fatal-infos
dart test
dart test --platform chrome
dart run example/epub_core_example.dart /path/to/book.epub
dart pub publish --dry-run
```

Use Dart 3.12.2 for formatting. CI checks Dart 3.12.2 and the latest stable SDK,
VM and Chrome tests, dependency lower bounds, and the pinned W3C EPUB corpus.
See the [release guide](doc/releasing.md) for publishing a version by pushing a tag.

MIT License. Copyright (c) 2026 [Sam Kuler](https://github.com/SamKuler).

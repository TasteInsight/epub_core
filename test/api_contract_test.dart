import 'package:epub_core/epub_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('container diagnostics survive every rendition selection', () {
    final files = epubFiles()..remove('mimetype');
    final book = EpubBook.fromBytes(zipFiles(files));
    expect(
      book.openRendition(book.packagePath).diagnostics.map((d) => d.code),
      contains('missingMimetype'),
    );
  });

  test('optional sidecar corruption preserves publication and diagnostic', () {
    final files = epubFiles()..['META-INF/metadata.xml'] = '<metadata>';
    final book = EpubBook.fromBytes(zipFiles(files));
    expect(book.metadata.title, 'A small book');
    expect(book.container.documents['META-INF/metadata.xml'], '<metadata>');
    expect(
      book.diagnostics.any((d) => d.path == 'META-INF/metadata.xml'),
      isTrue,
    );
  });

  test('malformed encryption declarations remain fatal', () {
    final files = epubFiles()..['META-INF/encryption.xml'] = '<encryption>';
    expect(
      () => EpubBook.fromBytes(zipFiles(files)),
      throwsA(isA<EpubException>()),
    );
  });

  test('malformed URIs have one typed failure across public operations', () {
    final book = EpubBook.fromBytes(epubBytes());
    final operations = <Object? Function()>[
      () => book.readBytes('http://['),
      () => book.readRawBytes('http://['),
      () => book.itemByHref('http://['),
      () => book.spineIndexOfHref('http://['),
      () => book.readMediaOverlayByHref('http://['),
      () => EpubPath.isExternal('http://['),
      () => EpubPath.fragment('http://['),
      () => EpubPath.archivePath('bad%ZZ'),
    ];
    for (final operation in operations) {
      expect(
        operation,
        throwsA(
          isA<EpubException>().having((e) => e.code.name, 'code', 'invalidUri'),
        ),
      );
    }
    expect(book.readBytes('https://example.org/a'), isNull);
    expect(book.readBytes('absent.xhtml'), isNull);
  });

  test('explicit overlay lookup separates manifest IDs from URIs', () {
    final book = EpubBook.fromBytes(zipFiles(overlayCollisionFiles()));
    expect(book.readMediaOverlayByHref('target.smil').body.id, 'wanted');
    expect(book.readMediaOverlayById('target.smil').body.id, 'other');
    expect(book.readMediaOverlayById('target').body.id, 'wanted');
    expect(
      book.readMediaOverlayById('target'),
      same(book.readMediaOverlayByHref('target.smil')),
    );
    expect(book.package.metadata, same(book.metadata));
    expect(
      book.renditionSettings.layout,
      book.spine.first.renditionSettings.layout,
    );
  });

  test('XML failures retain source offset for a malformed resource', () {
    final files = epubFiles()
      ..['OPS/text/one.xhtml'] = '<root>\n<a>\n</b>\n</root>';
    final book = EpubBook.fromBytes(zipFiles(files));
    expect(
      () => book.readXmlDocument('OPS/text/one.xhtml'),
      throwsA(
        isA<EpubException>()
            .having((e) => e.path, 'path', 'OPS/text/one.xhtml')
            .having((e) => e.offset, 'offset', isNotNull)
            .having((e) => e.line, 'line', 3)
            .having((e) => e.column, 'column', 1),
      ),
    );
  });

  test('HTML resource reads enforce structural budgets during parsing', () {
    final files = epubFiles()
      ..['OPS/text/one.xhtml'] =
          '<html><body>${List.filled(2000, '<div>').join()}text${List.filled(2000, '</div>').join()}</body></html>';
    final book = EpubBook.fromBytes(
      zipFiles(files),
      limits: const EpubLimits(maxDocumentDepth: 16),
    );
    expect(
      () => book.readHtmlDocument('OPS/text/one.xhtml'),
      throwsA(
        isA<EpubException>().having(
          (e) => e.code,
          'code',
          EpubErrorCode.resourceLimit,
        ),
      ),
    );
  });
}

Map<String, Object> overlayCollisionFiles() {
  final files = <String, Object>{
    for (final e in epubFiles().entries)
      e.key.replaceFirst(RegExp(r'^OPS/'), ''): e.value,
  };
  files['META-INF/container.xml'] = (files['META-INF/container.xml'] as String)
      .replaceAll('OPS/package.opf', 'package.opf');
  files['package.opf'] = (files['package.opf'] as String).replaceFirst(
    '</manifest>',
    '<item id="target" href="target.smil" media-type="application/smil+xml"/>'
        '<item id="target.smil" href="other.smil" media-type="application/smil+xml"/></manifest>',
  );
  files['target.smil'] =
      '<smil xmlns="http://www.w3.org/ns/SMIL"><body id="wanted"/></smil>';
  files['other.smil'] =
      '<smil xmlns="http://www.w3.org/ns/SMIL"><body id="other"/></smil>';
  return files;
}

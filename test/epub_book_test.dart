import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:epub_core/epub_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

TypeMatcher<EpubException> errorCode(EpubErrorCode code) =>
    isA<EpubException>().having((error) => error.code, 'code', code);

void main() {
  for (final version in ['2.0', '3.0', '3.3']) {
    test('EPUB $version metadata, spine, nested navigation and cover', () {
      final book = EpubBook.fromBytes(epubBytes(version: version));
      expect(book.version, version);
      expect(book.metadata.title, 'A small book');
      expect(book.metadata.identifier, 'urn:example:book');
      expect(book.metadata.creators.single.name, 'Writer');
      expect(book.metadata.creators.single.role, 'aut');
      expect(book.metadata.languages, ['zh', 'en']);
      expect(book.metadata.subjects, ['Fiction']);
      expect(book.spine.map((entry) => entry.item.id), ['one', 'two']);
      expect(book.spine.last.linear, isFalse);
      expect(book.pageProgressionDirection, 'rtl');
      expect(book.readingNavigation.toc.single.title, 'Part one');
      final chapter = book.readingNavigation.toc.single.children.single;
      expect(chapter.title, 'A & B');
      expect(chapter.href, 'OPS/text/one.xhtml#start');
      expect(book.cover?.mediaType, 'image/png');
      expect(book.readBytes(book.cover!.href), [1, 2, 3]);
      expect(book.readString(book.spine.first.item.href), contains('Hello'));
    });
  }

  test('reads resources repeatedly without exposing mutable cached bytes', () {
    final book = EpubBook.fromBytes(epubBytes());
    final first = book.readBytes(book.cover!.href)!;
    expect(() => first[0] = 99, throwsUnsupportedError);
    expect(book.readBytes(book.cover!.href), [1, 2, 3]);
    expect(() => book.manifest.clear(), throwsUnsupportedError);
    expect(() => book.spine.clear(), throwsUnsupportedError);
  });

  test('URI paths decode once, preserve case, and separate fragments', () {
    final files = epubFiles();
    files['OPS/package.opf'] = (files['OPS/package.opf']! as String).replaceAll(
      'images/cover.png',
      'images/%E5%9B%BE%20%2520%23.png',
    );
    files['OPS/images/图 %20#.png'] = files.remove('OPS/images/cover.png')!;
    final book = EpubBook.fromBytes(zipFiles(files));
    final href = EpubPath.resolve(
      'OPS/text/one.xhtml',
      '../images/图 %2520%23.png',
    );
    expect(book.itemByHref(href), book.cover);
    expect(book.readBytes('$href#unused'), [1, 2, 3]);
    expect(
      EpubPath.resolve('OPS/text/one.xhtml', '#start'),
      'OPS/text/one.xhtml#start',
    );
    expect(EpubPath.fragment('OPS/text/one.xhtml#a%20b'), 'a%20b');
    expect(book.readBytes('https://example.org/cover.png'), isNull);
    expect(book.readBytes('../../outside'), isNull);
  });

  test('unique case-insensitive lookup tolerates publisher casing errors', () {
    final book = EpubBook.fromBytes(epubBytes());
    expect(book.itemByHref('OPS/TEXT/ONE.XHTML')?.id, 'one');
    expect(book.readString('OPS/TEXT/ONE.XHTML'), contains('Hello'));
    final files = epubFiles()..['OPS/text/ONE.xhtml'] = 'different';
    final ambiguous = EpubBook.fromBytes(zipFiles(files));
    expect(ambiguous.readBytes('OPS/TEXT/ONE.XHTML'), isNull);
    expect(ambiguous.readString('OPS/text/ONE.xhtml'), 'different');
  });

  test('missing navigation leaves the reading order available', () {
    final files = epubFiles()
      ..remove('OPS/nav.xhtml')
      ..remove('OPS/toc.ncx');
    final book = EpubBook.fromBytes(zipFiles(files));
    expect(book.readingNavigation.toc, isEmpty);
    expect(book.spine, hasLength(2));
    expect(book.diagnostics, isNotEmpty);
  });

  test('invalid EPUB3 navigation falls back to NCX', () {
    final files = epubFiles()
      ..['OPS/nav.xhtml'] = '<html><body>Empty</body></html>';
    final book = EpubBook.fromBytes(zipFiles(files));
    expect(book.readingNavigation.toc.single.children.single.title, 'A & B');
  });

  test('malformed optional guide cover leaves the publication readable', () {
    final files = epubFiles();
    files['OPS/package.opf'] = (files['OPS/package.opf']! as String)
        .replaceAll('properties="cover-image"', '')
        .replaceAll('<meta name="cover" content="cover"/>', '')
        .replaceAll(
          '</package>',
          '<guide><reference type="cover" href="http://[invalid"/></guide></package>',
        );
    final book = EpubBook.fromBytes(zipFiles(files));
    expect(book.cover, isNull);
    expect(book.diagnostics, isNotEmpty);
    expect(book.readString(book.spine.first.item.href), contains('Hello'));
  });

  test('malformed optional navigation URI falls back to usable NCX', () {
    final files = epubFiles()
      ..['OPS/nav.xhtml'] =
          '<nav epub:type="toc"><ol><li><a href="http://[invalid">Broken</a></li></ol></nav>';
    final book = EpubBook.fromBytes(zipFiles(files));
    expect(book.readingNavigation.toc.single.children.single.title, 'A & B');
    expect(book.diagnostics, isNotEmpty);
  });

  test('navigation honors XHTML base URI and image alternative labels', () {
    final files = epubFiles()
      ..['OPS/nav.xhtml'] =
          '<html><head><base href="text/"/></head><body>'
          '<nav epub:type="toc"><ol><li><a href="one.xhtml#start">'
          '<img src="label.png" alt="First chapter"/></a></li></ol></nav></body></html>';
    final book = EpubBook.fromBytes(zipFiles(files));
    expect(book.readingNavigation.toc.single.href, 'OPS/text/one.xhtml#start');
    expect(book.readingNavigation.toc.single.title, 'First chapter');
    expect(book.itemByHref(book.readingNavigation.toc.single.href!)?.id, 'one');
  });

  test(
    'corrupt optional DEFLATE resource uses stable errors and NCX fallback',
    () {
      final bytes = corruptCompressedEntry(epubBytes(), 'OPS/nav.xhtml');
      final book = EpubBook.fromBytes(bytes);
      expect(book.readingNavigation.toc.single.children.single.title, 'A & B');
      expect(book.diagnostics, isNotEmpty);
      expect(
        () => book.readBytes('OPS/nav.xhtml'),
        throwsA(errorCode(EpubErrorCode.invalidArchive)),
      );
    },
  );

  test('navigation respects document order and retains fragment targets', () {
    final files = epubFiles();
    files['OPS/toc.ncx'] = (files['OPS/toc.ncx']! as String).replaceAll(
      'playOrder="1"',
      'playOrder="20"',
    );
    final book = EpubBook.fromBytes(zipFiles(files));
    expect(
      book.readingNavigation.toc.single.children.single.href,
      endsWith('#start'),
    );
  });

  test('UTF-16 XML and content are decoded with BOM and byte order', () {
    for (final littleEndian in [true, false]) {
      final files = epubFiles();
      for (final name in ['OPS/package.opf', 'OPS/text/one.xhtml']) {
        final source = (files[name]! as String).replaceAll('UTF-8', 'UTF-16');
        files[name] = utf16(source, littleEndian: littleEndian);
      }
      final book = EpubBook.fromBytes(zipFiles(files));
      expect(book.metadata.title, 'A small book');
      expect(book.readString('OPS/text/one.xhtml'), contains('Hello'));
    }
  });

  test('manifest fallback resolves a non-core spine resource', () {
    final files = epubFiles();
    files['OPS/package.opf'] = (files['OPS/package.opf']! as String)
        .replaceFirst(
          '<manifest>',
          '<manifest><item id="foreign" href="page.bin" media-type="application/x-custom" fallback="one"/>',
        )
        .replaceFirst('idref="one"', 'idref="foreign"');
    final book = EpubBook.fromBytes(zipFiles(files));
    expect(book.spine.first.item.id, 'one');
    expect(book.spine.first.idref, 'foreign');
  });

  test('missing spine resource fails instead of losing a chapter', () {
    final files = epubFiles()..remove('OPS/text/one.xhtml');
    expect(
      () => EpubBook.fromBytes(zipFiles(files)),
      throwsA(errorCode(EpubErrorCode.missingResource)),
    );
  });

  test('broken spine ID and fallback cycles report package errors', () {
    for (final replacement in [
      '<spine><itemref idref="absent"/></spine>',
      '<spine><itemref idref="foreign"/></spine>',
    ]) {
      final files = epubFiles();
      files['OPS/package.opf'] = (files['OPS/package.opf']! as String)
          .replaceFirst(
            '<manifest>',
            '<manifest><item id="foreign" href="page.bin" media-type="application/x-custom" fallback="foreign"/>',
          )
          .replaceFirst(
            RegExp(r'<spine[^>]*>.*?</spine>', dotAll: true),
            replacement,
          );
      expect(
        () => EpubBook.fromBytes(zipFiles(files)),
        throwsA(errorCode(EpubErrorCode.invalidPackage)),
      );
    }
  });

  test('font obfuscation does not block text and remains explicit on read', () {
    final files = epubFiles()
      ..['META-INF/encryption.xml'] = encryption(
        'OPS/font.otf',
        'http://www.idpf.org/2008/embedding',
      )
      ..['OPS/font.otf'] = [1, 2, 3];
    final book = EpubBook.fromBytes(zipFiles(files));
    expect(book.readString(book.spine.first.item.href), contains('Hello'));
    expect(book.readRawBytes('OPS/font.otf'), [1, 2, 3]);
    expect(book.readBytes('OPS/font.otf'), hasLength(3));
  });

  test('encrypted spine content reports encryption instead of mojibake', () {
    final files = epubFiles()
      ..['META-INF/encryption.xml'] = encryption(
        'OPS/text/one.xhtml',
        'http://www.w3.org/2001/04/xmlenc#aes256-cbc',
      );
    expect(
      () =>
          EpubBook.fromBytes(zipFiles(files)).readString('OPS/text/one.xhtml'),
      throwsA(errorCode(EpubErrorCode.encryptedResource)),
    );
  });

  test('malformed ZIP and missing container have stable error codes', () {
    expect(
      () => EpubBook.fromBytes([1, 2, 3]),
      throwsA(errorCode(EpubErrorCode.invalidArchive)),
    );
    expect(
      () => EpubBook.fromBytes(zipFiles({'mimetype': 'application/epub+zip'})),
      throwsA(errorCode(EpubErrorCode.missingResource)),
    );
  });

  test('broken required XML is a format error with its resource path', () {
    final files = epubFiles()..['OPS/package.opf'] = '<package><invalid>';
    expect(
      () => EpubBook.fromBytes(zipFiles(files)),
      throwsA(
        errorCode(
          EpubErrorCode.invalidXml,
        ).having((error) => (error).path, 'path', 'OPS/package.opf'),
      ),
    );
  });

  test(
    'archive, entry count, individual and cumulative size budgets apply',
    () {
      final bytes = epubBytes();
      for (final limits in [
        const EpubLimits(maxArchiveBytes: 1),
        const EpubLimits(maxEntries: 1),
        const EpubLimits(maxEntryBytes: 1),
        const EpubLimits(maxUncompressedBytes: 1),
      ]) {
        expect(
          () => EpubBook.fromBytes(bytes, limits: limits),
          throwsA(errorCode(EpubErrorCode.resourceLimit)),
        );
      }
    },
  );

  test('truncated stored content and CRC mismatch fail on read', () {
    final files = epubFiles()..['OPS/text/one.xhtml'] = 'abcdef';
    final bytes = zipFiles(files, compress: false);
    final needle = utf8.encode('abcdef');
    for (var i = 0; i <= bytes.length - needle.length; i++) {
      if (List.generate(needle.length, (j) => bytes[i + j]).join(',') ==
          needle.join(',')) {
        bytes[i] = 120;
        break;
      }
    }
    final book = EpubBook.fromBytes(bytes);
    expect(
      () => book.readString('OPS/text/one.xhtml'),
      throwsA(errorCode(EpubErrorCode.invalidArchive)),
    );
  });

  test('oversized deflate output cannot bypass a forged declared size', () {
    final bytes = zipFiles(epubFiles()..['OPS/text/one.xhtml'] = 'A' * 10000);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < bytes.length - 46; i++) {
      if (data.getUint32(i, Endian.little) != 0x02014b50) continue;
      final size = data.getUint16(i + 28, Endian.little);
      if (utf8.decode(bytes.sublist(i + 46, i + 46 + size)) !=
          'OPS/text/one.xhtml') {
        continue;
      }
      data.setUint32(i + 24, 10, Endian.little);
      final local = data.getUint32(i + 42, Endian.little);
      data.setUint32(local + 22, 10, Endian.little);
      break;
    }
    final book = EpubBook.fromBytes(bytes);
    expect(
      () => book.readBytes('OPS/text/one.xhtml'),
      throwsA(errorCode(EpubErrorCode.invalidArchive)),
    );
  });

  test('book and its lazy resources can cross an isolate boundary', () async {
    final bytes = epubBytes();
    final book = await Isolate.run(() => EpubBook.fromBytes(bytes));
    expect(book.readString(book.spine.first.item.href), contains('Hello'));
  }, testOn: 'vm');
  test('manifest URI identity is independent of resource existence', () {
    for (final present in [false, true]) {
      final files = epubFiles();
      addManifest(
        files,
        '<item id="optional" href="missing%20image.png" media-type="image/png"/>',
      );
      if (present) files['OPS/missing image.png'] = [1];
      final book = EpubBook.fromBytes(zipFiles(files));
      for (final href in [
        'OPS/missing%20image.png',
        '/OPS/missing%20image.png',
        'OPS/missing%20image.png?q=1#f',
      ]) {
        expect(book.itemByHref(href)?.id, 'optional');
      }
    }
  });
  test('guide cover pages retain bounded HTML recovery', () {
    final files = epubFiles();
    files['OPS/package.opf'] = (files['OPS/package.opf'] as String)
        .replaceAll('properties="cover-image"', '')
        .replaceAll('<meta name="cover" content="cover"/>', '')
        .replaceFirst(
          '</manifest>',
          '<item id="cover-page" href="cover.html" media-type="text/html"/></manifest>',
        )
        .replaceFirst(
          '</package>',
          '<guide><reference type="cover" href="cover.html"/></guide></package>',
        );
    files['OPS/cover.html'] =
        '<!doctype html><html><head><base href="images/"></head><body><img src="cover.png"></body></html>';
    final book = EpubBook.fromBytes(zipFiles(files));
    expect(book.cover?.href, 'OPS/images/cover.png');
    expect(book.diagnostics.any((d) => d.code == 'htmlCoverRecovery'), isTrue);
    files['OPS/cover.html'] =
        '<html><body><br>${'<div>' * 2000}<img src="images/cover.png">';
    final limited = EpubBook.fromBytes(
      zipFiles(files),
      limits: const EpubLimits(maxXmlDepth: 16),
    );
    expect(limited.cover, isNull);
    expect(
      limited.diagnostics.any(
        (d) => d.code == 'resourceLimit' && d.path == 'OPS/cover.html',
      ),
      isTrue,
    );
  });
}

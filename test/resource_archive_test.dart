import 'dart:typed_data';
import 'package:epub_core/epub_core.dart';
import 'package:test/test.dart';
import 'fixtures.dart';

TypeMatcher<EpubException> code(EpubErrorCode value) =>
    isA<EpubException>().having((e) => e.code, 'code', value);

void main() {
  test('ZIP EOCD signatures inside a legal archive comment are harmless', () {
    final original = epubBytes();
    final comment = [0x50, 0x4b, 0x05, 0x06, ...List.filled(26, 65)];
    final bytes = Uint8List.fromList([...original, ...comment]);
    ByteData.sublistView(
      bytes,
    ).setUint16(original.length - 2, comment.length, Endian.little);
    expect(EpubBook.fromBytes(bytes).metadata.title, 'A small book');
  });

  test(
    'cache eviction preserves repeatable reads and malformed UTF16 is explicit',
    () {
      final files = epubFiles()..['OPS/bad.txt'] = [0xff, 0xfe, 0x00, 0xd8];
      final book = EpubBook.fromBytes(
        zipFiles(files),
        limits: const EpubLimits(maxCachedBytes: 4),
      );
      final first = book.readString('OPS/text/one.xhtml');
      book.readString('OPS/text/two.xhtml');
      book.clearResourceCache();
      expect(book.readString('OPS/text/one.xhtml'), first);
      expect(
        () => book.readString('OPS/bad.txt'),
        throwsA(code(EpubErrorCode.invalidText)),
      );
    },
  );

  test('IDPF font key always comes from the default rendition', () {
    final files = epubFiles();
    files['OPS/package.opf'] = (files['OPS/package.opf']! as String).replaceAll(
      'urn:example:book',
      'urn:uuid:00000000-0000-4000-8000-000000000001',
    );
    files['OPS/second.opf'] = (files['OPS/package.opf']! as String).replaceAll(
      '000000000001',
      '000000000002',
    );
    files['META-INF/container.xml'] =
        (files['META-INF/container.xml']! as String).replaceFirst(
          '</rootfiles>',
          '<rootfile full-path="OPS/second.opf" media-type="application/oebps-package+xml"/></rootfiles>',
        );
    final hex = '62f2ff8a6e1cd08b5ee1657bd31fae18cca09cd2';
    final key = [
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
    final plain = List.generate(1300, (i) => i % 251);
    files['OPS/font.otf'] = [
      for (var i = 0; i < plain.length; i++)
        i < 1040 ? plain[i] ^ key[i % key.length] : plain[i],
    ];
    files['META-INF/encryption.xml'] = encryption(
      'OPS/font.otf',
      'http://www.idpf.org/2008/embedding',
    );
    final bytes = zipFiles(files);
    expect(
      EpubBook.fromBytes(
        bytes,
      ).openRendition('OPS/second.opf').readBytes('OPS/font.otf'),
      plain,
    );
    expect(
      EpubBook.fromBytes(
        bytes,
        packagePath: 'OPS/second.opf',
      ).readBytes('OPS/font.otf'),
      plain,
    );
  });

  test(
    'ZIP index budgets use actual central entries as well as EOCD counts',
    () {
      final bytes = epubBytes();
      final data = ByteData.sublistView(bytes);
      data.setUint16(bytes.length - 22 + 8, 1, Endian.little);
      data.setUint16(bytes.length - 22 + 10, 1, Endian.little);
      expect(
        () =>
            EpubBook.fromBytes(bytes, limits: const EpubLimits(maxEntries: 2)),
        throwsA(
          isA<EpubException>().having(
            (error) => error.code,
            'code',
            EpubErrorCode.resourceLimit,
          ),
        ),
      );
    },
  );
}

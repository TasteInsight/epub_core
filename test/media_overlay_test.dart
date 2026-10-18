import 'package:epub_core/epub_core.dart';
import 'package:test/test.dart';
import 'fixtures.dart';

TypeMatcher<EpubException> code(EpubErrorCode value) =>
    isA<EpubException>().having((e) => e.code, 'code', value);

void main() {
  test('SMIL hierarchy, XML base, text references and clip timing parse', () {
    final files = epubFiles();
    addManifest(
      files,
      '<item id="overlay" href="overlays/one.smil" media-type="application/smil+xml"/>',
    );
    files['OPS/package.opf'] = (files['OPS/package.opf']! as String)
        .replaceFirst('id="one" ', 'id="one" media-overlay="overlay" ');
    files['OPS/overlays/one.smil'] =
        '<s:smil xmlns:s="http://www.w3.org/ns/SMIL" xmlns:e="http://www.idpf.org/2007/ops">'
        '<s:body><s:seq e:textref="../text/one.xhtml" e:type="chapter"><s:par id="p1"><s:text src="../text/one.xhtml#start"/>'
        '<s:audio xml:base="../audio/" src="one.mp3" clipBegin="01:02.125" clipEnd="65.5s"/></s:par></s:seq></s:body></s:smil>';
    final book = EpubBook.fromBytes(zipFiles(files));
    expect(book.itemById('one')!.mediaOverlay, 'overlay');
    final overlay = book.readMediaOverlayById('overlay');
    expect(overlay.body.children.single.types, {'chapter'});
    expect(overlay.body.children.single.textReference, 'OPS/text/one.xhtml');
    final audio = overlay.body.descendants
        .where((node) => node.name == 'audio')
        .single;
    expect(audio.source, 'OPS/audio/one.mp3');
    expect(audio.clipBegin, const Duration(seconds: 62, milliseconds: 125));
    expect(audio.clipEnd, const Duration(seconds: 65, milliseconds: 500));
    expect(book.mediaOverlays, hasLength(1));
    expect(overlay.sourceXml, files['OPS/overlays/one.smil']);
  });

  test('SMIL clock syntax is exact across native and web', () {
    expect(
      parseSmilClock('02:30:03.125'),
      const Duration(hours: 2, minutes: 30, seconds: 3, milliseconds: 125),
    );
    expect(parseSmilClock('1.5min'), const Duration(seconds: 90));
    expect(parseSmilClock('0.001ms'), const Duration(microseconds: 1));
    expect(
      parseSmilClock('12.1234567s'),
      const Duration(seconds: 12, microseconds: 123456),
    );
    for (final invalid in ['-1s', '00:99:00', 'NaN', '1:2:3', '2fortnights']) {
      expect(
        () => parseSmilClock(invalid),
        throwsA(code(EpubErrorCode.invalidMediaOverlay)),
      );
    }
  });

  test(
    'SMIL clock overflow stays typed and agrees with web numeric limits',
    () {
      for (final value in [
        '100000000000:00:00',
        '${'9' * 100}:00:00',
        '${'9' * 100}s',
      ]) {
        expect(
          () => parseSmilClock(value),
          throwsA(
            isA<EpubException>().having(
              (error) => error.code,
              'code',
              EpubErrorCode.invalidMediaOverlay,
            ),
          ),
        );
      }
    },
  );
}

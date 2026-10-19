import 'package:epub_core/epub_core.dart';
import 'package:epub_core/src/document/html_document.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('HTML5 recovery preserves implicit closes, raw text and tables', () {
    const source =
        '<!doctype html><title>T</title><body>'
        '<script>if (a < b) { value = "<div>"; }</script>'
        '<!-- <span><span> -->'
        '<p title="<div>">one<p>two<table><tr><td>cell</table><b><i>A</b>B</i>';
    final document = parseEpubHtml(
      source,
      'chapter.html',
      const EpubLimits(maxDocumentDepth: 16),
    );
    expect(document.querySelectorAll('p').map((p) => p.text), ['one', 'two']);
    expect(document.querySelector('tbody td')?.text, 'cell');
    expect(document.querySelector('script')?.text, contains('"<div>"'));
  });

  test('HTML token work is bounded even when elements close implicitly', () {
    expect(
      () => parseEpubHtml(
        List.filled(500, '<p>x').join(),
        'chapter.html',
        const EpubLimits(maxParseItems: 100),
      ),
      throwsA(
        isA<EpubException>().having(
          (e) => e.code,
          'code',
          EpubErrorCode.resourceLimit,
        ),
      ),
    );
  });

  test('HTML implicit nodes are included in the returned node budget', () {
    expect(
      () => parseEpubHtml('', 'empty.html', const EpubLimits(maxParseItems: 2)),
      throwsA(
        isA<EpubException>().having(
          (e) => e.code,
          'code',
          EpubErrorCode.resourceLimit,
        ),
      ),
    );
  });

  test('malformed navigation uses the same HTML parsing budget', () {
    final files = epubFiles();
    files['OPS/nav.xhtml'] =
        '<html><body><br><nav epub:type="toc">'
        '${List.filled(2000, '<div>').join()}<ol><li><a href="text/one.xhtml">T</a></ol>';
    final book = EpubBook.fromBytes(
      zipFiles(files),
      limits: const EpubLimits(maxDocumentDepth: 16),
    );
    expect(
      book.diagnostics.any(
        (d) => d.code == 'resourceLimit' && d.path == 'OPS/nav.xhtml',
      ),
      isTrue,
    );
    expect(book.readingNavigation.toc, isNotEmpty); // NCX remains usable.
  });
}

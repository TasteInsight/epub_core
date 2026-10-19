import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
// HtmlParser documents custom tokenizers as its streaming extension point.
// html 0.15 exposes this type under src; keep that dependency in this adapter.
// ignore: implementation_imports
import 'package:html/src/tokenizer.dart';

import '../errors.dart';
import '../limits.dart';

/// Uses HTML5 tree construction with bounded token work and open-element depth.
/// Final node/depth validation includes implicit and reparented HTML elements.
dom.Document parseEpubHtml(
  String source,
  String path,
  EpubLimits limits, {
  bool generateSpans = false,
}) {
  final tokenizer = _BudgetedTokenizer(
    source,
    path,
    limits,
    generateSpans: generateSpans,
  );
  final document = html.HtmlParser(
    tokenizer,
    generateSpans: generateSpans,
  ).parse();
  final stack = <(dom.Node, int)>[(document, 0)];
  var count = 0;
  while (stack.isNotEmpty) {
    final (node, depth) = stack.removeLast();
    if (++count > limits.maxParseItems || depth > limits.maxDocumentDepth) {
      throw EpubException(
        EpubErrorCode.resourceLimit,
        'HTML DOM exceeds document structural limits.',
        path: path,
      );
    }
    stack.addAll(node.nodes.map((child) => (child, depth + 1)));
  }
  return document;
}

final class _BudgetedTokenizer extends HtmlTokenizer {
  _BudgetedTokenizer(
    String super.source,
    this.path,
    this.limits, {
    required super.generateSpans,
  }) : super(parseMeta: false);

  final String path;
  final EpubLimits limits;
  int _tokens = 0;

  @override
  bool moveNext() {
    // The parser has consumed the previous token before requesting the next.
    // Check before scanning more input, including at EOF.
    if ((parser?.tree.openElements.length ?? 0) > limits.maxDocumentDepth) {
      throw EpubException(
        EpubErrorCode.resourceLimit,
        'HTML exceeds maxDocumentDepth during parsing.',
        path: path,
      );
    }
    final available = super.moveNext();
    if (available && ++_tokens > limits.maxParseItems) {
      throw EpubException(
        EpubErrorCode.resourceLimit,
        'HTML token work exceeds maxParseItems.',
        path: path,
      );
    }
    return available;
  }
}

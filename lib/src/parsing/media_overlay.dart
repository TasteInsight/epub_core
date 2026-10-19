import 'package:xml/xml.dart';

import '../document/xml_document.dart';
import '../epub_path.dart';
import '../errors.dart';
import '../limits.dart';
import '../model/media_overlay.dart';
import '../vocabulary.dart';

EpubMediaOverlay readMediaOverlayDocument(
  String? source,
  String href,
  EpubLimits limits,
) {
  if (source == null) {
    throw EpubException(
      EpubErrorCode.missingResource,
      'SMIL resource is missing.',
      path: href,
    );
  }
  final root = parseEpubXml(source, href, limits).rootElement;
  final body = xmlChild(root, 'body', smilNamespace);
  if (!xmlIs(root, 'smil', smilNamespace) || body == null) {
    throw EpubException(
      EpubErrorCode.invalidMediaOverlay,
      'Expected SMIL with a body element.',
      path: href,
    );
  }
  EpubSmilNode visit(XmlElement node) {
    final base = elementBase(node, href);
    final src = node.getAttribute('src');
    final textref = xmlAttribute(node, 'textref', epubNamespace);
    final clipBegin = node.getAttribute('clipBegin');
    final clipEnd = node.getAttribute('clipEnd');
    Duration? clock(String? value) =>
        value == null ? null : parseSmilClock(value, path: href);
    final begin = node.name.local == 'audio'
        ? clock(clipBegin) ?? Duration.zero
        : null;
    final end = clock(clipEnd);
    if (begin != null && end != null && end < begin) {
      throw EpubException(
        EpubErrorCode.invalidMediaOverlay,
        'Audio clipEnd precedes clipBegin.',
        path: href,
      );
    }
    return EpubSmilNode(
      name: node.name.local,
      attributes: xmlAttributes(node),
      xmlFragment: xmlFragment(node),
      types: tokens(xmlAttribute(node, 'type', epubNamespace)),
      children: node.childElements.map(visit).toList(),
      source: src == null ? null : EpubPath.resolve(base, src),
      textReference: textref == null ? null : EpubPath.resolve(base, textref),
      clipBegin: begin,
      clipEnd: end,
    );
  }

  return EpubMediaOverlay(href: href, sourceXml: source, body: visit(body));
}

/// Parses SMIL full/partial clock values and timecounts with integer arithmetic.
/// Returned durations have microsecond precision.
Duration parseSmilClock(String input, {String? path}) {
  final value = input.trim().replaceFirst(RegExp(r'^npt='), '');
  final clock = RegExp(
    r'^(?:(\d+):)?(\d{2}):(\d{2})(?:\.(\d+))?$',
  ).firstMatch(value);
  if (clock != null) {
    final hours = BigInt.parse(clock[1] ?? '0');
    final minutes = int.parse(clock[2]!);
    final seconds = int.parse(clock[3]!);
    if (minutes < 60 && seconds < 60) {
      final fraction = (clock[4] ?? '').padRight(6, '0').substring(0, 6);
      final micros =
          hours * BigInt.from(3600000000) +
          BigInt.from(
            minutes * 60000000 + seconds * 1000000 + int.parse(fraction),
          );
      if (micros <= BigInt.from(9007199254740991)) {
        return Duration(microseconds: micros.toInt());
      }
    }
  } else {
    final count = RegExp(r'^(\d+)(?:\.(\d+))?(h|min|s|ms)?$').firstMatch(value);
    if (count != null) {
      final scale = switch (count[3]) {
        'h' => 3600000000,
        'min' => 60000000,
        'ms' => 1000,
        _ => 1000000,
      };
      final fraction = count[2] ?? '';
      var fractionalMicros = 0;
      for (var i = fraction.length - 1; i >= 0; i--) {
        fractionalMicros =
            ((fraction.codeUnitAt(i) - 48) * scale + fractionalMicros) ~/ 10;
      }
      final micros =
          BigInt.parse(count[1]!) * BigInt.from(scale) +
          BigInt.from(fractionalMicros);
      if (micros <= BigInt.from(9007199254740991)) {
        return Duration(microseconds: micros.toInt());
      }
    }
  }
  throw EpubException(
    EpubErrorCode.invalidMediaOverlay,
    'Invalid SMIL clock value: $input',
    path: path,
  );
}

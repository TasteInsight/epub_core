import 'package:petitparser/petitparser.dart';
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import '../errors.dart';
import '../limits.dart';
import 'xml_error.dart';

typedef DtdAttribute = ({String name, bool cdata, String? value});
typedef PreparedXml = ({
  String source,
  Map<String, List<DtdAttribute>> attributes,
  int expansionBytes,
});

/// Complements xml's DTD-preserving parser with bounded internal entity
/// substitution. XML events delimit markup/text: CDATA, comments, processing
/// instructions and the DTD itself are copied verbatim.
PreparedXml expandInternalEntities(
  String source,
  String path,
  EpubLimits limits,
) {
  final events = parseEvents(
    source,
    entityMapping: const XmlNullEntityMapping(),
    withLocation: true,
  );
  String? subset;
  for (final event in events) {
    if (event is XmlDoctypeEvent) subset = event.internalSubset;
    if (event is XmlStartElementEvent) break;
  }
  if (subset == null || subset.isEmpty) {
    return (source: source, attributes: const {}, expansionBytes: 0);
  }
  final entities = <String, String>{};
  final parameters = <String, String>{};
  final attributes = <String, List<DtdAttribute>>{};
  var used = 0;
  var declarationCount = 0;
  late String Function(String, Set<String>) expandTokens;
  Never fail(String message) =>
      throw EpubException(EpubErrorCode.invalidXml, message, path: path);
  void budget(int amount) {
    used += amount;
    if (used > limits.maxEntityExpansionBytes) {
      throw EpubException(
        EpubErrorCode.resourceLimit,
        'Internal entities exceed maxEntityExpansionBytes.',
        path: path,
      );
    }
  }

  String substitute(
    String input,
    String marker,
    Map<String, String> values,
    Set<String> active, {
    bool attribute = false,
  }) {
    final out = StringBuffer();
    var offset = 0;
    while (offset < input.length) {
      final start = input.indexOf(marker, offset);
      if (start < 0) {
        out.write(input.substring(offset));
        break;
      }
      out.write(input.substring(offset, start));
      final end = input.indexOf(';', start + 1);
      if (end < 0) {
        out.write(input.substring(start));
        break;
      }
      final name = input.substring(start + 1, end);
      final replacement = values[name];
      if (replacement == null) {
        if (marker == '%') fail('Undefined parameter entity: $name');
        out.write(input.substring(start, end + 1));
      } else {
        if (!active.add(name) || active.length > limits.maxDocumentDepth) {
          fail('Recursive internal entity: $name');
        }
        var expanded = attribute
            ? substitute(replacement, marker, values, active, attribute: true)
            : expandTokens(replacement, active);
        active.remove(name);
        if (attribute) {
          if (expanded.contains('<')) {
            fail('Entity markup is not allowed in an attribute value.');
          }
          expanded = expanded
              .replaceAll('"', '&quot;')
              .replaceAll("'", '&apos;');
        }
        budget(expanded.length * 2);
        out.write(expanded);
      }
      offset = end + 1;
    }
    return out.toString();
  }

  // Tokenize DTD declarations with PetitParser, treating quoted literals and
  // comments as single tokens.
  final quoted =
      ((char('"') & pattern('^"').star().flatten() & char('"')) |
              (char("'") & pattern("^'").star().flatten() & char("'")))
          .map((parts) => (parts as List)[1] as String);
  final name = pattern('^ \t\r\n<>"\'=%;&').plus().flatten();
  final internal = quoted.map((value) => (value: value, external: false));
  final external =
      ((string('SYSTEM') | string('PUBLIC')) & (quoted | pattern('^>')).star())
          .flatten()
          .map((value) => (value: value, external: true));
  final declaration =
      (string('<!ENTITY') &
      whitespace().plus() &
      (char('%') & whitespace().plus()).optional() &
      name &
      whitespace().plus() &
      (internal | external) &
      whitespace().star() &
      char('>'));
  final enumeration = char('(') & pattern('^)').star() & char(')');
  final attributeType =
      ((string('NOTATION') & whitespace().plus() & enumeration) |
              enumeration |
              pattern('A-Z').plus())
          .flatten();
  final attributeDefault =
      ((string('#REQUIRED') | string('#IMPLIED')).map<String?>((_) => null) |
      ((string('#FIXED') & whitespace().plus()).optional() & quoted)
          .map<String?>((value) => value[1] as String));
  final attributeDefinition =
      (whitespace().plus() &
              name &
              whitespace().plus() &
              attributeType &
              whitespace().plus() &
              attributeDefault)
          .map(
            (parts) => (
              name: parts[1] as String,
              cdata: parts[3] == 'CDATA',
              value: parts[5] as String?,
            ),
          );
  final attributeList =
      string('<!ATTLIST') &
      whitespace().plus() &
      name &
      attributeDefinition.star() &
      whitespace().star() &
      char('>');
  final comment =
      string('<!--') & any().starLazy(string('-->')) & string('-->');
  final instruction =
      string('<?') & any().starLazy(string('?>')) & string('?>');
  final otherDeclaration =
      string('<!') & (quoted | pattern('^>')).star() & char('>');
  void declarations(String input, Set<String> activeParameters) {
    var offset = 0;
    while (offset < input.length) {
      if (input.startsWith('<!--', offset) || input.startsWith('<?', offset)) {
        final result = (comment | instruction).parseOn(Context(input, offset));
        if (result is Failure) {
          fail('Malformed DTD comment or processing instruction.');
        }
        offset = result.position;
      } else if (input.startsWith('<!ENTITY', offset)) {
        if (++declarationCount > limits.maxParseItems) {
          throw EpubException(
            EpubErrorCode.resourceLimit,
            'DTD exceeds maxParseItems.',
            path: path,
          );
        }
        final result = declaration.parseOn(Context(input, offset));
        if (result is Failure) fail('Malformed entity declaration.');
        final values = result.value;
        final value = values[5] as ({String value, bool external});
        if (value.external) {
          fail('External entity declarations are unsupported.');
        }
        // Numeric references are interpreted at declaration time. Predefined
        // references retain their escaping until the XML parser consumes them.
        final decoded = value.value.replaceAllMapped(
          RegExp(r'&#(?:x[0-9a-fA-F]+|[0-9]+);'),
          (match) => const XmlDefaultEntityMapping.xml().decode(match[0]!),
        );
        final entityName = values[3] as String;
        final target = values[2] == null ? entities : parameters;
        target.putIfAbsent(entityName, () => decoded);
        offset = result.position;
      } else if (input.startsWith('<!ATTLIST', offset)) {
        final result = attributeList.parseOn(Context(input, offset));
        if (result is Failure) fail('Malformed attribute-list declaration.');
        final parts = result.value;
        final target = attributes.putIfAbsent(parts[2] as String, () => []);
        for (final attribute in parts[3] as List<DtdAttribute>) {
          if (++declarationCount > limits.maxParseItems) {
            throw EpubException(
              EpubErrorCode.resourceLimit,
              'DTD exceeds maxParseItems.',
              path: path,
            );
          }
          if (!target.any((existing) => existing.name == attribute.name)) {
            target.add(attribute);
          }
        }
        offset = result.position;
      } else if (input[offset] == '%') {
        final end = input.indexOf(';', offset);
        if (end < 0) fail('Malformed parameter entity reference.');
        final entityName = input.substring(offset + 1, end);
        if (!activeParameters.add(entityName) ||
            activeParameters.length > limits.maxDocumentDepth) {
          fail('Recursive parameter entity.');
        }
        final value = parameters[entityName];
        if (value == null) fail('Undefined parameter entity: $entityName');
        budget(value.length * 2);
        declarations(value, activeParameters);
        activeParameters.remove(entityName);
        offset = end + 1;
      } else if (input.startsWith('<!', offset)) {
        final result = otherDeclaration.parseOn(Context(input, offset));
        if (result is Failure) fail('Malformed DTD declaration.');
        offset = result.position;
      } else {
        offset++;
      }
    }
  }

  declarations(subset, {});

  expandTokens = (String input, Set<String> active) {
    final out = StringBuffer();
    var offset = 0;
    try {
      for (final event in parseEvents(
        input,
        entityMapping: const XmlNullEntityMapping(),
        withLocation: true,
      )) {
        final start = event.start!;
        final stop = event.stop!;
        out.write(input.substring(offset, start));
        final text = input.substring(start, stop);
        out.write(
          event is XmlTextEvent || event is XmlStartElementEvent
              ? substitute(
                  text,
                  '&',
                  entities,
                  active,
                  attribute: event is XmlStartElementEvent,
                )
              : text,
        );
        offset = stop;
      }
    } on XmlException catch (error) {
      if (active.isEmpty) rethrow;
      throw xmlFailure(
        error,
        path,
        locationSource: EpubLocationSource.entityReplacement,
        entityName: active.last,
      );
    }
    out.write(input.substring(offset));
    return out.toString();
  };
  final defaults = <String, List<DtdAttribute>>{
    for (final entry in attributes.entries)
      entry.key: [
        for (final attribute in entry.value)
          (
            name: attribute.name,
            cdata: attribute.cdata,
            value: attribute.value == null
                ? null
                : substitute(
                    attribute.value!,
                    '&',
                    entities,
                    {},
                    attribute: true,
                  ),
          ),
      ],
  };
  return (
    source: entities.isEmpty ? source : expandTokens(source, {}),
    attributes: defaults,
    expansionBytes: used,
  );
}

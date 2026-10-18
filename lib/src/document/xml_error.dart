import 'package:xml/xml.dart';

import '../errors.dart';

/// Converts parser locations without retaining an entire failing input buffer.
EpubException xmlFailure(
  XmlException error,
  String path, {
  EpubLocationSource locationSource = EpubLocationSource.resource,
  String? entityName,
}) {
  final location = error is XmlFormatException
      ? error as XmlFormatException
      : null;
  return EpubException(
    EpubErrorCode.invalidXml,
    error.message,
    path: path,
    offset: location?.offset,
    line: location?.line,
    column: location?.column,
    locationSource: locationSource,
    entityName: entityName,
  );
}

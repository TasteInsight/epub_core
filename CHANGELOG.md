## 0.2.0

- Parse multiple renditions, complete OPF metadata, collections, bindings, guide references and presentation settings.
- Preserve EPUB 3 navigation lists, NCX page/navigation lists, SMIL media overlays and unknown XML declarations.
- Support EPUB 2 legacy metadata, DTBook/OEB1 content and IDPF/Adobe font deobfuscation.
- Expose XML/HTML/CSS resource parsers, raw resource bytes and immutable publication models through `EpubPackage`.
- Index metadata refinements and share nested XML source fragments.
- Add explicit media-overlay ID/URI lookup, descriptive API names and deprecated compatibility aliases.
- Preserve container diagnostics across renditions; recover optional sidecars and reject unlocatable encryption declarations.
- Unify malformed URI errors and preserve XML error positions with their coordinate source.
- Bound archive indexing, decompression, XML entities and DTD-generated attributes, HTML parsing work and resource caches.
- Preserve bounded HTML guide-cover recovery, normalize missing-resource URI lookups and read standard encryption compression metadata.
- Organize models, format readers, document adapters and archive access as independent libraries.
- Add native/web regression tests, minimum-dependency checks and a pinned W3C corpus CI job.

Compatibility changes: public data classes are final; invalid URI queries throw `invalidUri`;
ambiguous legacy media-overlay lookups throw `ambiguousReference`. Encrypted content fails on decoded
resource reads, while metadata and raw payloads remain accessible. See the README migration guide.

## 0.1.0

- Add EPUB 2/3 container and OPF parsing with Dublin Core metadata.
- Preserve spine order, fallback resources, supplementary entries and RTL direction.
- Read EPUB 3 navigation and EPUB 2 NCX with nested labels and fragment references.
- Resolve EPUB 2/3 covers and document-relative resources.
- Add lazy, immutable resource reads with UTF-8/UTF-16 text decoding.
- Validate ZIP resource budgets, declared sizes and CRC; report encrypted resources.
- Support Dart VM and Web with standalone synthetic-fixture tests.

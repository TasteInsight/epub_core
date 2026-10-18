## 0.1.0

- Add EPUB 2/3 container and OPF parsing with Dublin Core metadata.
- Preserve spine order, fallback resources, supplementary entries and RTL direction.
- Read EPUB 3 navigation and EPUB 2 NCX with nested labels and fragment references.
- Resolve EPUB 2/3 covers and document-relative resources.
- Add lazy, immutable resource reads with UTF-8/UTF-16 text decoding.
- Validate ZIP resource budgets, declared sizes and CRC; report encrypted resources.
- Support Dart VM and Web with standalone synthetic-fixture tests.

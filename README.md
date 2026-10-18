# epub_core

纯 Dart EPUB 2/3 结构解析库，适用于 Flutter、Dart VM 和 Web。
解析容器、出版物声明、阅读顺序与资源，提供内容 DOM 和 XML 扩展原文。

## 读取出版物

```dart
import 'package:epub_core/epub_core.dart';

void inspectBook(List<int> bytes) {
  final book = EpubBook.fromBytes(bytes);
  print(book.metadata.title);
  print(book.metadata.creators.map((person) => person.name).join(', '));

  for (final entry in book.spine.where((entry) => entry.linear)) {
    print('${entry.sourceItem.mediaType}: ${entry.sourceItem.href}');
    if (entry.item.isHtmlContentDocument) {
      final xhtml = book.readString(entry.item.href);
      print(xhtml);
    }
  }

  for (final page in book.readingNavigation.pageList) {
    print('${page.title}: ${page.href}');
  }
  final cover = book.cover;
  if (cover != null) print(book.readBytes(cover.href)?.length);
}
```

`spine.item` 提供选用的内容资源；`sourceItem` 保留原始项，`fallbackChain` 记录本次遍历的回退链。
完整 fallback 声明可从 `manifest` 各项的 `fallback` 字段查询。
外来媒体仍可通过资源 API 访问。应用负责选择渲染器、章节分段和持久化。

## 出版物结构

| 对象 | 内容 |
| --- | --- |
| `container` | 全部 rootfiles、links、加密描述和 META-INF XML |
| `metadata` | 全部 Dublin Core、重复项、meta/refines、语言方向、属性 IRI 及 links |
| `package` | 独立 OPF 声明模型，包含元数据、资源与阅读顺序 |
| `manifest` / `spine` | 所有资源声明、阅读顺序、原始引用及 fallback |
| `readingNavigation` | EPUB 3 全部 nav 类型，以及 NCX 的 TOC、pageList、navList |
| `renditionSettings` / `spine[].renditionSettings` | 全局和局部版式声明 |
| `collections` / `bindings` / `guide` | 集合、处理器绑定与旧式导航 |
| `mediaOverlays` | SMIL 层级、文本引用、音频片段和时钟值 |
| `packageXml` / `resources` | 原始 OPF 与完整 ZIP 文件清单 |

完整能力、资源预算和职责划分见 [格式支持说明](doc/format-support.md)，测试与外部语料结果见 [验证记录](doc/validation.md)。

```dart
final book = EpubBook.fromBytes(bytes);
final alternate = book.openRendition(book.container.rootfiles.last.fullPath);
final titles = book.metadata.values('title');
final properties = book.metadata.properties('http://purl.org/dc/terms/modified');
final xml = book.readXmlDocument(book.packagePath);
final cssItem = book.manifest.where((item) => item.mediaType == 'text/css').firstOrNull;
final stylesheet = cssItem == null ? null : book.readCssDocument(cssItem.href);
```

`readXmlDocument` 使用命名空间感知 XML；`readHtmlDocument` 提供显式 HTML5 容错入口。
`readBytes` 自动还原 IDPF/Adobe 混淆字体；`readRawBytes` 返回原始归档载荷。
商业 DRM 的声明和载荷可读取，解密由消费方的授权解码器完成。

## URI、错误和性能

资源 URI 相对于容器根目录。文档内引用通过
`EpubPath.resolve(documentHref, reference)` 解析。缺失或远程资源的字节读取返回 `null`，非法 URI 抛出 `EpubException(invalidUri)`。
资源按需解压、校验并缓存；`EpubLimits` 控制大小、数量、XML/HTML 复杂度、实体展开和缓存容量。

```dart
try {
  final book = EpubBook.fromBytes(
    bytes,
    limits: const EpubLimits(maxCachedBytes: 32 * 1024 * 1024),
  );
  for (final diagnostic in book.diagnostics) {
    print('${diagnostic.code}: ${diagnostic.path}: ${diagnostic.message}');
  }
} on EpubException catch (error) {
  print('${error.code.name}: ${error.path}: ${error.message}');
}
```

模型集合与资源字节为只读。解析结果支持 Dart isolate；Flutter Web 的 `compute` 使用当前事件循环。
`clearResourceCache()` 释放共享的资源字节缓存及当前 rendition 的媒体叠加缓存。嵌套节点源码采用共享文本片段，避免重复常驻整棵子树。

## API 与迁移

媒体叠加使用明确的查找入口：

```dart
final overlay = book.readMediaOverlayById('chapter-audio');
final sameResource = book.readMediaOverlayByHref(overlay.href);
```

`metadata` 的便捷字段由全部声明派生，重复查询使用索引。构造元数据时优先使用
`EpubMetadata.fromEntries`；原构造器保留给需要手动提供便捷字段的调用方。

容器诊断在 `container.diagnostics` 中保存，每个 rendition 的 `diagnostics` 同时包含容器与当前 rendition 的结果。
辅助 META-INF 文档解析失败会产生诊断并保留可访问的原始资源；加密 XML 损坏或缺少资源定位会中止打开；位置明确而算法未知的资源保持受保护状态。
XML 错误保留资源路径，以及底层解析器可提供的 `offset`、`line`、`column`；`locationSource` 标明坐标来自资源原文、展开后的 XML 或实体替换文本；后者还提供 `entityName`。
异常只保留位置数据，调用方可通过资源 API 获取文本。

旧名称在 0.2 系列保留兼容入口：

| 旧 API | 推荐 API |
| --- | --- |
| `navigationDocument` | `readingNavigation` |
| `rendition`、`EpubRendition` | `renditionSettings`、`EpubRenditionSettings` |
| `isXhtml`（含 HTML） | `isHtmlContentDocument` |
| `readMediaOverlay(idOrHref)` | `readMediaOverlayById` / `readMediaOverlayByHref` |

旧媒体叠加入口遇到 ID 与 URI 指向不同资源时抛出 `ambiguousReference`。
公开模型为 `final class`，通过组合使用；类型演进由库维护，扩展数据通过原始声明读取。

## 0.1 → 0.2

`EpubBook.fromBytes`、`metadata` 便捷字段、`spine`、`navigation`、`cover` 与资源读取入口保留。

- 加密正文的错误在 `readBytes` / `readString` 时报告，元数据和加密声明仍可解析。
- 字体混淆资源默认返回还原后的字节；`readRawBytes` 提供原始字节。
- 未知正文类型保留资源与诊断，消费方选择渲染能力。
- 数值版本号保留并尝试兼容处理；OCF URI 按容器根 URL 解析。
- `navigation` 保持默认 TOC 视图，完整目录数据通过 `readingNavigation` 获取。
- 非法 URI 统一报告 `invalidUri`；公开数据类采用 `final`，扩展使用组合包装。

## 开发

最低 Dart SDK 为 3.12。ZIP、XML、HTML、CSS、散列和声明语法分别复用
`archive`、`xml`、`html`、`csslib`、`crypto`、`petitparser`。

```sh
dart pub get
dart analyze --fatal-infos
dart test
dart test --platform chrome
dart run example/epub_core_example.dart /path/to/book.epub
dart pub publish --dry-run
```

MIT License，Copyright (c) 2026 [Sam Kuler](https://github.com/SamKuler)。

# epub_core

[English](README.md)

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
各资源的回退声明可通过 `manifest` 项的 `fallback` 字段查询。
应用可读取资源内容和 fallback 链，并按内容格式选择处理器。
应用负责选择渲染器、章节分段和持久化。

## 出版物结构

| 对象 | 内容 |
| --- | --- |
| `container` | rootfiles、links、加密描述和 META-INF XML |
| `metadata` | Dublin Core、重复项、meta/refines、语言方向、属性 IRI 及 links |
| `package` | OPF 元数据、资源声明与阅读顺序 |
| `manifest` / `spine` | 所有资源声明、阅读顺序、原始引用及 fallback |
| `readingNavigation` | EPUB 3 nav 列表，以及 NCX 的 TOC、pageList、navList |
| `renditionSettings` / `spine[].renditionSettings` | 全局和局部版式声明 |
| `collections` / `bindings` / `guide` | 集合、处理器绑定与旧式导航 |
| `mediaOverlays` | SMIL 层级、文本引用、音频片段和时钟值 |
| `packageXml` / `resources` | 原始 OPF 与 ZIP 文件清单 |

`readingNavigation.toc` 提供目录，`pageList` 和 `landmarks` 分别提供页码与地标导航。

支持的格式、资源限制和应用负责的功能见 [格式支持说明](doc/format-support.md)，测试与外部语料结果见 [验证记录](doc/validation.md)。

## 元数据与资源

```dart
final book = EpubBook.fromBytes(bytes);
final alternate = book.openRendition(book.container.rootfiles.last.fullPath);
final titles = book.metadata.values('title');
final properties = book.metadata.properties('http://purl.org/dc/terms/modified');
final xml = book.readXmlDocument(book.packagePath);
final cssItem = book.manifest.where((item) => item.mediaType == 'text/css').firstOrNull;
final stylesheet = cssItem == null ? null : book.readCssDocument(cssItem.href);
```

`metadata.title`、`metadata.creators` 等字段从元数据条目中提取。`refinementsFor` 和 `properties` 查询使用索引。
使用 `EpubMetadata.fromEntries` 可从条目构造元数据；`EpubMetadata` 构造器支持手动指定这些字段。

`readXmlDocument` 返回保留 XML 命名空间的 DOM；`readHtmlDocument` 按 HTML5 规则构建 DOM。
`readBytes` 自动还原 IDPF/Adobe 混淆字体；`readRawBytes` 返回原始归档载荷。
商业 DRM 的声明和载荷可读取，解密由消费方的授权解码器完成。

## 媒体叠加

媒体叠加可按 manifest ID 或资源 URI 读取：

```dart
final overlay = book.readMediaOverlayById('chapter-audio');
final sameResource = book.readMediaOverlayByHref(overlay.href);
```

## URI 与错误处理

资源 URI 相对于容器根目录。文档内引用通过
`EpubPath.resolve(documentHref, reference)` 解析。缺失或远程资源的字节读取返回 `null`，URI 格式有误时抛出 `EpubException(invalidUri)`。

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

容器诊断在 `container.diagnostics` 中保存，每个 rendition 的 `diagnostics` 同时包含容器与当前 rendition 的结果。
辅助 META-INF 文档解析失败时，解析器记录错误并保留原始资源。加密 XML 损坏或缺少资源路径时抛出异常。
带资源路径的加密声明保存在 `container.encryption`；`readBytes` 对需要外部解码器的资源报告 `encryptedResource`。
XML 错误保留资源路径，以及底层解析器可提供的 `offset`、`line`、`column`；`locationSource` 标明坐标来自资源原文、展开后的 XML 或实体替换文本；后者还提供 `entityName`。
错误坐标以数值保存，调用方可通过资源 API 获取对应文本。

## 模型与资源限制

资源按需解压、校验并缓存；`EpubLimits` 控制大小、数量、XML/HTML 复杂度、实体展开和缓存容量。
`maxDocumentDepth` 限制 XML/HTML 嵌套及实体展开深度；`maxParseItems` 设置各解析阶段的计数上限。
模型集合与资源字节为只读。解析结果支持 Dart isolate；Flutter Web 的 `compute` 使用当前事件循环。
`clearResourceCache()` 释放共享的资源字节缓存及当前 rendition 的媒体叠加缓存。嵌套节点共享文档文本，用起止位置表示各自的源码片段。

公开数据类使用 `final`。需要附加业务字段时，可定义自己的对象，并在其中保存这些模型。

## 开发

最低 Dart SDK 为 3.12。ZIP、XML、HTML、CSS、散列和声明语法分别复用
`archive`、`xml`、`html`、`csslib`、`crypto`、`petitparser`。
代码格式统一使用 Dart 3.12.2；CI 同时使用 3.12.2 和最新 stable 检查兼容性。
版本标签的自动发布流程见[发布指南](doc/releasing.md)。

```sh
dart pub get
dart format --output=none --set-exit-if-changed lib test example tool
dart analyze --fatal-infos
dart test
dart test --platform chrome
dart run example/epub_core_example.dart /path/to/book.epub
dart pub publish --dry-run
```

MIT License，Copyright (c) 2026 [Sam Kuler](https://github.com/SamKuler)。

# epub_core

纯 Dart EPUB 2/3 解析包，提供出版物元数据、阅读顺序、目录、封面与按需资源读取。
可用于 Dart VM、Flutter 和 Web。ZIP、XML、HTML 分别由 `archive`、`xml`、`html` 处理。

## 使用

`EpubBook.fromBytes` 接收 EPUB 字节，返回保留原始文档结构的出版物对象：

```dart
import 'package:epub_core/epub_core.dart';

void readBook(List<int> bytes) {
  final book = EpubBook.fromBytes(bytes);
  print(book.metadata.title);
  print(book.metadata.creators.map((person) => person.name).join(', '));

  for (final entry in book.spine.where((entry) => entry.linear)) {
    if (!entry.item.isXhtml) continue;
    final xhtml = book.readString(entry.item.href);
    print(xhtml);
  }

  final cover = book.cover;
  if (cover != null) {
    final imageBytes = book.readBytes(cover.href);
    print('${cover.mediaType}: ${imageBytes?.length} bytes');
  }
}
```

应用负责文件选择、网络下载、渲染、章节分段和持久化。
在 Flutter 中，可以通过 `compute` 或 `Isolate.run` 把解析移到后台 isolate；
Flutter Web 的 `compute` 在当前事件循环执行。

命令行示例：

```sh
dart run example/epub_core_example.dart /path/to/book.epub
```

## 数据与行为

| API | 内容 |
| --- | --- |
| `metadata` | 标题、标识符、作者及角色、贡献者、语言、分类、简介、出版者、日期、版权 |
| `manifest` | 资源 ID、根目录相对 URI、MIME 类型、属性 token、fallback |
| `spine` | OPF 阅读顺序、`linear`、原始 `idref`、解析后的 fallback 资源 |
| `navigation` | EPUB 3 TOC 或 EPUB 2 NCX 的层次结构、标签和片段 URI |
| `pageProgressionDirection` | OPF 的 `ltr`、`rtl` 或 `default` |
| `cover` | EPUB 3 `cover-image`、EPUB 2 `meta name="cover"` 或 guide 指定的封面 |
| `warnings` | 可恢复的目录或封面解析问题 |

spine 保留线性及补充内容，调用者根据 `linear` 选择阅读路线。
一个 XHTML 文档可以对应多个 TOC 锚点；目录树和 spine 分别保留这些信息。
外来 spine 媒体通过 manifest fallback 解析到 XHTML 或 SVG；失败时抛出错误。
SVG 文档以原始资源形式读取。

`readBytes` 和 `readString` 接收根目录相对 URI；
文档内的相对引用可通过 `EpubPath.resolve(documentHref, reference)` 解析。
URI 路径解码一次，查询和片段与 ZIP 文件名分开处理。
资源先按大小写精确匹配；只有唯一候选时才使用忽略大小写的兼容查找。
缺失或外部资源返回 `null`。资源读取只访问内存中的 ZIP 内容。

字节在首次读取时解压和缓存，返回只读视图；模型集合也为只读。
文本支持 UTF-8 和 UTF-16。XHTML、CSS、图片和字体保留原始内容。
EPUB 3 TOC 不可用时尝试 NCX；目录全部不可用时仍提供 spine。

## 错误与资源限制

```dart
try {
  final book = EpubBook.fromBytes(
    bytes,
    limits: const EpubLimits(maxArchiveBytes: 128 * 1024 * 1024),
  );
  print(book.metadata.title);
} on EpubException catch (error) {
  print('${error.code.name}: ${error.path}: ${error.message}');
}
```

`EpubException` 继承 `FormatException`，提供稳定错误码和相关资源路径。
默认上限为压缩输入 256 MiB、10,000 个条目、单条目 64 MiB、累计解压大小 512 MiB。
解析器在资源解压前检查声明大小；`archive` 限制实际解压输出，读取后校验长度和 CRC。
缺失正文、无法解析的必要 XML、错误 spine 引用和加密正文会抛出明确错误。
可选资源由调用者决定恢复方式。

本版本聚焦解析。EPUB 写入、排版渲染、DRM 解密、字体解混淆、媒体叠加播放及
EPUB 完整规范验证属于上层或专用组件。带字体混淆的书籍可读取正文；直接读取混淆字体会报告
`encryptedResource`。`encryption.xml` 中标记的资源均按加密资源处理。

## 开发与发布检查

最低 Dart SDK 为 3.12。独立运行：

```sh
dart pub get
dart analyze
dart test
dart test --platform chrome
dart pub publish --dry-run
```

测试使用合成 EPUB，包内包含所有测试资源构造代码。
MIT License，Copyright (c) 2026 [Sam Kuler](https://github.com/SamKuler)。

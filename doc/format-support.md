# EPUB 格式支持与工程边界

## 解析契约

`epub_core` 提供 EPUB 2.0.1 与 EPUB 3.x 的结构和资源解析。出版物数据分为三个层次：

1. **原始资料**：ZIP 资源字节、OPF、container、导航文档以及 META-INF 文档。
2. **结构模型**：元数据条目、阅读顺序、导航列表、媒体叠加、版式声明、集合、绑定及加密描述。
3. **便捷视图**：书名、作者、默认 TOC、已解析 fallback、封面和资源 DOM。

扩展元素、属性、未知词汇及未识别媒体类型通过原始文档和完整声明持续可访问。
解析器以 `archive`、`xml`、`html`、`csslib` 为基础；XML 内部子集适配使用 `xml_events` 和 `petitparser`。

## 规范能力矩阵

| 范围 | API / 行为 | 验证入口 |
| --- | --- | --- |
| OCF 多 rendition | `container.rootfiles`、`openRendition`、`fromBytes(packagePath:)`；保留 rootfile 扩展属性与 container links | `container_test.dart` |
| OCF 保留文件 | `container.documents` 保留 container、metadata、rights、manifest、signatures、encryption XML；`readXmlDocument` 返回可查询 DOM | `container_test.dart` |
| OPF 元数据 | Dublin Core、重复值、`meta`、`refines`、`scheme`、`link`、词汇前缀、语言和方向；主标题优先 `title-type=main` | `metadata_test.dart` |
| EPUB 2 兼容 | `dc-metadata` / `x-metadata`、OPF 角色与排序名、guide、NCX、DTBook、OEB1 内容类型 | `metadata_test.dart`、`package_test.dart`、`navigation_test.dart` |
| Manifest | ID、href、类型、properties、fallback、media-overlay、完整属性与源声明；远程资源只保留引用 | `package_test.dart` |
| Spine | 顺序、linear、原始 item、已遍历 fallback chain、选用 item、itemref 属性和版式覆盖 | `package_test.dart` |
| EPUB 3 导航 | TOC、page-list、landmarks、其他 nav 类型、嵌套节点、图片替代文字；保留每个 nav 文档 | `navigation_test.dart` |
| NCX | navMap、pageList、navList；保留顺序、标签、属性与资源片段 | `navigation_test.dart` |
| 版式声明 | 全局 layout/orientation/spread/flow 与 itemref 局部覆盖、page-spread、阅读方向 | `package_test.dart` |
| 集合与绑定 | 递归 collection 及其完整 metadata/links；bindings/handler；guide references | `package_test.dart` |
| 媒体叠加 | `mediaOverlays`、`readMediaOverlayById` / `readMediaOverlayByHref`；SMIL body/seq/par/text/audio、textref、epub:type、片段及精确 clip 时间 | `media_overlay_test.dart` |
| 内容资源 | XHTML、SVG、MathML、DTBook 通过 `readXmlDocument`；HTML5 容错通过 `readHtmlDocument`；CSS 通过 `readCssDocument` | `xml_document_test.dart`、`html_document_test.dart` |
| 字体混淆 | IDPF SHA-1/1040 字节与 Adobe UUID/1024 字节；多 rendition 统一使用默认 rendition 标识符 | `resource_archive_test.dart` |
| 加密声明 | 算法、CipherReference、压缩声明、原始 XML；`readRawBytes` 提供原始载荷，`readBytes` 对需解码的资源报告 `encryptedResource` | `epub_book_test.dart` |
| XML | 命名空间 URI、继承 xml:lang/dir、XML Base、UTF-8/UTF-16、内部实体、参数实体、默认属性、tokenized 属性；XHTML 标准实体采用离线映射 | `xml_document_test.dart` |
| URI | 容器根 URL、相对路径、百分号编码、片段、查询、XHTML base；ZIP 文件名与 URI 分别处理 | `epub_book_test.dart`、`package_test.dart` |

其他数值 package version 会保留版本信息，并通过 `unrecognizedVersion` 诊断尝试读取已有结构。
外来正文缺少内置内容处理能力时，保留原始资源和 fallback 链，通过 `unsupportedSpineContent` 提示消费者选择处理器。

## 模型与资源预算

- 公开集合与资源字节为只读数据。`readXmlDocument` 和 `readHtmlDocument` 每次创建独立 DOM，调用者可编辑自己的副本。
- 解压缓存采用容量上限和最近使用淘汰策略；`clearResourceCache` 释放缓存。返回值由调用者持有时，其生命周期由调用者管理。
- 嵌套导航、collection 和 SMIL 源码采用 `EpubXmlFragment`：共享文档文本和偏移，访问 `sourceXml` 时生成片段。
- ZIP 校验包括完整 EOCD、实际中央目录条目数、声明边界、单条目与累计大小、实际解压长度和 CRC。
- HTML 使用成熟 HTML5 tokenizer，在请求下一个 token 前检查开放元素深度，并限制 token 工作量；返回 DOM 前检查实际节点数和深度（含隐式节点及重排结果）。这些约束限制解析工作与输出结构，进程峰值内存仍取决于输入和依赖的分配行为。
- XML 在构建 DOM 前检查深度和事件预算，DTD 属性应用次数计入同一工作预算。实体替换及默认属性生成的文本共用累计容量限制，CDATA/注释中的引用保持文本语义。
- 标准 XHTML 实体采用离线映射；通用外部实体声明报告 `invalidXml`。外部 DTD 标识保留在 XML 中，网络加载由消费应用在库外处理。

| 限制项 | 默认值 |
| --- | --- |
| 压缩输入 | 256 MiB |
| ZIP 条目数 | 10,000 |
| 单条目解压大小 | 64 MiB |
| 总声明解压大小 | 512 MiB |
| 解压缓存 | 64 MiB |
| XML / HTML 深度 | 256 |
| XML 事件/DTD 声明及属性应用、HTML token/返回节点预算 | 250,000 |
| 实体与 DTD 默认文本展开预算 | 1 MiB（按 UTF-16 存储量保守计数） |

这些值通过 `EpubLimits` 配置。进程实际内存还包含压缩输入、解析模型、DOM 和调用者持有的数据。

## 诊断与职责

`EpubException` 保持 `FormatException` 兼容，提供错误码、资源路径和可用的 XML 坐标。
`locationSource` 区分原始资源、展开后的 XML 和实体替换文本，`entityName` 标识对应实体。异常仅保存位置数据。
`container.diagnostics` 持有容器问题并随 rendition 共享；`diagnostics` 提供结构化可恢复问题；`warnings` 保留字符串列表兼容视图。
目录及 guide 封面页共享有预算的 HTML5 容错入口。目录与辅助 META-INF XML 损坏时保留可读取的 spine 和诊断，加密声明损坏、必要结构缺失或引用循环会明确失败。
加密声明缺少资源定位时中止打开；资源位置明确而算法未提供或未知时保留声明，普通读取报告 `encryptedResource`，原始载荷仍可读取。
资源字节查询遇到缺失或远程资源时返回 `null`；非法 URI 统一抛出 `invalidUri`。

| 后续处理 | 责任组件 |
| --- | --- |
| 页面排版、分页、字体布局、音视频播放、脚本运行 | 阅读系统 |
| CFI 片段的解析定位与选区执行 | 阅读定位组件；本包保留完整片段引用 |
| 商业 DRM 密钥取得与解密 | 授权解码器；本包保留加密声明和原始载荷 |
| 数字签名的可信链与加密验证 | 签名验证器；本包提供签名 XML 和原始资源 |
| 全部 EPUB 作者规范、Schematron/XSD/DTD 验证 | EPUBCheck 等专用验证器 |
| CSS 计算、资源下载、外部链接访问 | 消费应用 |

## 外部语料验证

`tool/check_corpus.dart` 接收解包后的出版物目录，依次验证容器、全部资源字节、所有 rendition 与媒体叠加。
语料报告反映文件解析与资源可访问性；阅读系统的视觉、交互、播放和无障碍行为需要各自验收。

```sh
dart run tool/check_corpus.dart /path/to/epub-tests/tests /tmp/epub-report.json
```

W3C 语料基线：`w3c/epub-tests`，提交 `54092b4233253e9aac80e93ec4782b380b4b3403`。
语料由其贡献者按 W3C Software and Document License 提供，保留在外部测试目录。

## 规范与依赖依据

- [EPUB 3.3](https://www.w3.org/TR/epub-33/)
- [EPUB Reading Systems 3.3](https://www.w3.org/TR/epub-rs-33/)
- [OPF 2.0.1](https://idpf.org/epub/20/spec/OPF_2.0_latest.htm)
- [EPUB Multiple-Rendition Publications 1.1](https://www.w3.org/TR/epub-multi-rend-11/)
- [XML 1.0](https://www.w3.org/TR/xml/)、[XML Namespaces](https://www.w3.org/TR/xml-names/)、[XHTML 标准实体](https://www.w3.org/TR/xhtml1/#h-A2)
- [SMIL 时钟语法](https://www.w3.org/TR/REC-smil/smil-timing.html)
- [W3C EPUB 公开语料](https://github.com/w3c/epub-tests)

## 模块职责与依赖

- `model/`：只读出版物模型，按容器、元数据、OPF、导航、SMIL 和源码片段分类。
- `parsing/`：格式读取函数，接收资源访问或文本、路径、限制，返回模型。
- `document/`：XML/HTML 解析适配及 XML 实体处理，集中管理文档复杂度限制。
- `archive/`：ZIP 索引、校验、文本解码与有界字节缓存。
- `epub_book.dart`：组合容器、OPF 和导航，维护 rendition 资源访问与媒体叠加缓存。
- `errors.dart`、`limits.dart`、`epub_path.dart`、`vocabulary.dart`：错误契约、预算、URI 语义和规范标识符。

模型层依赖规范常量与其他模型；解析层依赖模型、文档和归档层。各解析文件是独立 Dart library，参数明确传递。
`EpubPackage` 仅保存 OPF 解析结果；`EpubBook` 的便捷字段指向同一份模型。

`html` 的自定义 tokenizer 输入是其解析扩展入口，相关类型位于依赖的 `src` 中。
本库将这项依赖集中在 `document/html_document.dart`；升级 `html` 时运行深度、token、隐式节点、原始文本和错误恢复测试。

## 源码与 DOM 语义

文档级 `packageXml`、`container.documents`、`readingNavigation.documents` 和媒体叠加 `sourceXml` 保留解码后的原始资源文本。
元素级 `sourceXml` 引用 XML 实体展开后的文档片段；DTD 默认属性体现在结构模型和返回 DOM 中。
HTML 恢复节点的片段引用输入文本；由 HTML5 恢复创建的导航 section 使用序列化 HTML。
原始字节统一通过 `readRawBytes` 获取。DOM 每次读取独立创建，编辑 DOM 与解析模型的生命周期分别管理。

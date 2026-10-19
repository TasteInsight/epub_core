# 0.2.0 验证

验证日期：2026-10-19。环境：macOS、Dart 3.12.2、Chrome。

## 本地检查

| 范围 | 结果 |
| --- | --- |
| 格式与静态分析（含严格类型检查） | 通过 |
| Dart VM | 86 项通过 |
| Chrome | 85 项通过；另有 1 项 VM isolate 测试 |
| 最低依赖组合 | 静态分析及 86 项 VM 测试通过 |
| 发布预检 | 0 警告 |

在仓库根目录执行：

```sh
dart pub get
dart format --output=none --set-exit-if-changed lib test example tool
dart analyze --fatal-infos
dart test
dart test --platform chrome
dart pub downgrade
dart analyze --fatal-infos
dart test
dart pub upgrade
dart pub publish --dry-run
```

测试按容器、元数据、OPF、导航、媒体叠加、XML、HTML 和归档职责组织。
API 测试覆盖 URI 错误、ID/URI 歧义、容器与 rendition 的错误记录、可选文档恢复及错误坐标来源。
规模输入包含 4,000 作者及其 refinement；损坏输入测试包含固定种子的 500 组 ZIP 字节变异。

CI 配置 Dart 3.12.2 与 stable，执行上述包检查，并运行固定提交的 W3C 语料任务。

## 外部语料

来源：[W3C EPUB Tests](https://github.com/w3c/epub-tests)，提交
`54092b4233253e9aac80e93ec4782b380b4b3403`。

| 指标 | 结果 |
| --- | --- |
| 出版物 | 209 / 209 |
| Rendition | 211 |
| 资源文件 | 1,676 |
| 读取资源字节 | 386,878,737 |
| 媒体叠加文档 | 24 |

获取语料并运行：

```sh
git clone https://github.com/w3c/epub-tests.git /path/to/epub-tests
git -C /path/to/epub-tests checkout 54092b4233253e9aac80e93ec4782b380b4b3403
dart run tool/check_corpus.dart /path/to/epub-tests/tests /path/to/epub-report.json
```

工具将解包目录构造成内存 EPUB，读取容器、每个资源的字节、各 rendition 和媒体叠加。
结果覆盖结构解析与资源访问。视觉布局、脚本、音视频和无障碍交互由阅读系统另行验收。
语料按 W3C Software and Document License 提供，保存在库外。

## 消费应用

InkNode 使用本地解析包依赖进行验收：静态分析、88 项相关回归和 1 项 Widget 集成测试通过。
集成流程覆盖文件选择入口、EPUB 导入、SQLite 保存与重开、图片阅读、翻章、滚动与分页，以及进度保存与恢复。
测试使用受控文件选择器和本地 SQLite，执行实际导入服务、阅读界面与导航状态。
原生平台文件选择器交互属于设备验收范围。

支持的格式、资源限制和应用负责的功能见[格式支持说明](format-support.md)。

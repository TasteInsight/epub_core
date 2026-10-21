# 版本发布

## CI 检查

GitHub Actions 在推送、Pull Request 和手动运行时执行：

- Dart 3.12.2 与最新 stable 的静态分析、VM 和 Chrome 测试、发布预检及最低依赖组合检查。
- Dart 3.12.2 格式检查。
- 固定提交的 W3C EPUB 语料解析。

## 配置 pub.dev

包上传者在 [epub_core 管理页](https://pub.dev/packages/epub_core/admin)的
**Automated publishing** 中启用 **Enable publishing from GitHub Actions**，填写：

| 设置 | 值 |
| --- | --- |
| GitHub repository | `TasteInsight/epub_core` |
| Tag pattern | `v{{version}}` |
| Require GitHub Actions environment | 保持关闭 |

发布采用 GitHub OIDC 临时凭据。认证配置由 `dart-lang/setup-dart` 的官方
发布工作流管理。配置方法见 [Dart 自动发布文档](https://dart.dev/tools/pub/automated-publishing)。

## 发布版本

1. 更新 `pubspec.yaml` 的 `version` 和 `CHANGELOG.md`，将改动提交到 `main`。
2. 创建与 `pubspec.yaml` 一致的版本标签并推送。例如，发布 `0.2.1`：

   ```sh
   git tag v0.2.1
   git push origin v0.2.1
   ```

3. 查看 [Publish to pub.dev](https://github.com/TasteInsight/epub_core/actions/workflows/publish.yml)
   的运行结果。该工作流先对标签指向的提交执行完整 CI，全部通过后调用官方发布工作流。
4. 在 [pub.dev 版本列表](https://pub.dev/packages/epub_core/versions)和管理页的
   Audit log 确认发布结果。

标签支持 `v0.3.0-dev.1` 等预发布版本。pub.dev 要求标签中的版本与
`pubspec.yaml` 完全一致。每个版本号仅可发布一次。

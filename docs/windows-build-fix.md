# Windows 构建修复范围

基线：`11671bc0ec61727e99e34810f142a1b5e4121a8e`，分支：`codex/windows-build-validation`。

目标：修复 `ech_http 0.2.1` 将全部 CA 证书嵌入单个 C++ 字符串导致的 MSVC C2026，继续运行 Kazumi 全量测试和 Windows 构建。

允许修改：`third_party/ech_http`（原包完整副本，局部修复 CMake/证书模板）、`pubspec.yaml`、`pubspec.lock`、`analysis_options.yaml`（隔离依赖包自身测试的独立开发依赖）、`test/native_ca_bundle`、本次 `docs` 验证产物。应用 `lib`、原有 Dart 测试及平台业务代码保持基线内容。

验收：用 MSVC 编译证书回归程序，逐字节核对嵌入证书与原始 PEM；原有 Flutter 测试、静态分析、Windows 构建；可构建后启动并检查窗口。

回滚：移除本次本地依赖覆盖并恢复基线 `pubspec.yaml` / `pubspec.lock` / `analysis_options.yaml`，重新 `flutter pub get`；原始依赖副本位于本机 Pub 缓存及迁移备份。D 盘路径设置和 Web 平台适配暂缓。

验证：MSVC 回归修复前失败、修复后通过，证书 188900 字节全部一致；原有 211 项测试通过；静态分析 0 error / 0 warning，17 条原有 info；Windows Release 构建成功、已启动窗口。桌面工具无法截图/点击，交互与播放测试受阻，详情见 `kazumi-analysis.md`。

修改文件用途：`pubspec.yaml` / `pubspec.lock` 切换项目内依赖，`analysis_options.yaml` 排除上游包自身开发测试，`third_party/ech_http/src/CMakeLists.txt` / `CaBundle.cmake` / `ca_bundle.h.in` 修复 MSVC 字符串限制并使用 UTF-8；`test/native_ca_bundle` 保证真实编译与完整证书内容；`docs` 保存分析与验证证据。应用 `lib`、原有测试和 Windows runner 内容未改动。

依赖副本的 `.gitattributes` 保留原始字节，避免 Windows Git 自动转换 PEM 换行。上游说明文件原有 9 处行尾空白已核对来源，保持原样；本次手改文件的 diff 空白检查通过。

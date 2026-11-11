# 剪藏库 · Flutter 版

内容收藏 APP 的原生实现（Flutter：Android + iOS 共用一套 Dart 代码）。
对应设计与规格：`../应用开发/剪藏库-设计说明.html`、Ardot 画布「剪藏库 · 内容收藏 APP 设计稿」。

> **位置说明**：本工程位于 `F:\AISpace\WorkBuddy\clippings_app`，不在「应用开发」目录内。
> 原因：Android Gradle 拒绝包含非 ASCII 字符的项目路径（`应用开发` 是中文），构建会直接失败。
> 如需放回工作区，请用英文目录名，或建一个 junction 指过来。

---

## 1. 技术栈

| 项目 | 选择 | 说明 |
|---|---|---|
| 框架 | **Flutter 3.47 / Dart 3.13** | 一套代码双端，UI 与设计稿对齐 |
| 依赖 | **零三方包** | 只用 Flutter SDK + AndroidX；不引 sqflite / path_provider / image_picker |
| 存储 | 应用私有目录 + JSON | 原子写（tmp + rename）：`clips.json` / `tags.json` / `settings.json` |
| 分享接收 | 原生 `Intent` + `MethodChannel` | 自己写 Kotlin，无插件 |
| 导出 | 写文件 + FileProvider + `ACTION_SEND` | 生成 `.md` / `.txt` 并调起系统分享 |
| 主题 | `ThemeExtension` + `ThemeMode` | 浅色 / 深色 / 跟随系统，9 个 token 一一对应 |

## 2. 目录结构

```
clippings_app/
├── lib/
│   ├── main.dart              # 入口、主题、胶囊底部导航、分享落地
│   ├── theme.dart             # 设计 token（AppColors）+ ThemeData
│   ├── models.dart            # Clip / AppTag / TagCount / ClipGroup
│   ├── core.dart              # 纯逻辑：识别、检索、分组、导出、标签推荐
│   ├── store.dart             # JSON 持久化 + ChangeNotifier
│   ├── bridge.dart            # MethodChannel：私有目录 / 待处理分享 / 分享文件
│   ├── widgets.dart           # 卡片三态、chips、页头、空状态、提示
│   └── ui/                    # 8 个页面 + 设置
├── android/app/src/main/
│   ├── AndroidManifest.xml              # ACTION_SEND / SEND_MULTIPLE + FileProvider
│   ├── kotlin/.../MainActivity.kt       # 原生桥
│   └── res/xml/file_paths.xml
├── ios/                        # 待补 Share Extension（需 macOS）
└── test/core_test.dart         # 17 个纯逻辑用例
```

## 3. 运行与构建

```bash
cd F:\AISpace\WorkBuddy\clippings_app
flutter pub get
flutter run                     # 连真机 / 模拟器
flutter build apk --debug       # 产物 build/app/outputs/flutter-apk/app-debug.apk
```

**单元测试**（代理变量会劫持 flutter_tester 的本地连接，需清掉）：

```bash
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy flutter test
```

**静态分析**：`flutter analyze`（当前 0 error / 0 warning）。

## 4. 功能对照（设计稿 8 屏）

| 屏 | 文件 | 已实现 |
|---|---|---|
| 01 内容列表 | `ui/home_page.dart` | 今天/昨天/更早分组、类型快筛、三态卡片、空状态、悬浮「＋」 |
| 02 分享速存 | `ui/paste_page.dart` | 分享 → 自动识别 → 确认页 → 入库（Android 真机可用） |
| 03 搜索 | `ui/search_page.dart` | 四字段检索、关键词高亮、类型筛选、未分类入口 |
| 04 标签 | `ui/tags_page.dart` | 数量聚合、色点、新建/重命名/删除、点标签看内容 |
| 05 详情 | `ui/detail_page.dart` | 正文、图片、标签增删、复制全文、删除 |
| 06 批量导出 | `ui/export_page.dart` | 多选/全选、md/txt、图片复制、时间分组、前 14 行预览 |
| 07 导出完成 | `ui/done_page.dart` | 文件名/大小/条数、再次分享 |
| 08 粘贴速存 | `ui/paste_page.dart` | 读剪贴板、三步条、自动识别、建议标签、手动粘贴兜底 |
| 设置 | `ui/settings_page.dart` | 主题、统计、分享说明、示例数据、清空 |

## 5. Android 分享接入

`AndroidManifest.xml` 已注册三段 `intent-filter`：

- `ACTION_SEND` + `text/plain` / `text/html` → 链接与文字
- `ACTION_SEND` + `image/*` → 单张图片
- `ACTION_SEND_MULTIPLE` + `image/*` → 多图（当前取第一张）

`MainActivity` 收到后暂存：文本走 `EXTRA_TEXT` / `EXTRA_SUBJECT`；图片用 `ContentResolver` 复制到 `filesDir/share_incoming/`（原 Uri 读权限会过期），再通过 `MethodChannel` 交给 Dart。

冷启动：Dart 调 `takePendingShare()`；热启动：原生 `onNewIntent` 主动 `invokeMethod('onShare')`。

> 源 APP 若使用自绘分享面板（微信、抖音等），本应用不会出现在其分享列表——Android 生态限制，用「复制 → 粘贴速存」兜底。

## 6. iOS 部分（未完成）

`ios/` 目录已生成，但 **Share Extension 需要 macOS + Xcode 才能创建、编译和调试**，当前 Windows 环境无法完成。

在 Mac 上需要：

1. Xcode 打开 `ios/Runner.xcworkspace`，新增 Share Extension target；
2. 配置 `NSExtensionActivationRule`（WebURL / Text / Image）；
3. 主 App 与扩展启用同一 App Group，扩展把内容写进共享容器；
4. Dart 侧加一条读取分支（`MethodChannel` + `UserDefaults(suiteName:)`）；
5. 真机验证，或用 GitHub Actions macOS runner 构建。

数据模型与导出规则可直接复用 `core.dart` / `models.dart`。

## 7. 已知限制

- **iOS 分享入口未实现**（需 macOS，见上）。
- Flutter 内置 `Clipboard` 只支持文本，图片剪贴板待补（目前图片走系统分享）。
- 搜索历史仅本次会话内存，未持久化。
- 导出图片为「复制到 `exports/images/` + Markdown 相对路径引用」，需连同文件夹拷走；未做 zip。
- 仅提供 `debug` 包；上架需自行配置签名与 `applicationId`。

## 8. 与 PWA 版本的关系

`../应用开发/clippings-app`（PWA）保留作 Web 版：数据模型、识别规则、导出格式一致，可互相参照。原生版解决了 PWA 的两个硬伤——iOS 无法进分享面板、Android 依赖浏览器安装。

## 9. 验证记录

- `flutter analyze`：0 error / 0 warning
- `flutter test`：17/17 通过（识别、检索、分组、Markdown/TXT 导出、图片相对路径、标签推荐）
- `flutter build apk --debug`：构建成功

# 剪藏库 · Flutter 版

内容收藏 APP 的原生实现（Flutter：Android + iOS 共用一套 Dart 代码）。
对应设计与规格：`../应用开发/剪藏库-设计说明.html`、Ardot 画布「剪藏库 · 内容收藏 APP 设计稿」。

> **位置说明**：本工程位于 `F:\AISpace\WorkBuddy\clippings_app`，不在「应用开发」目录内。
> 原因：Android Gradle 拒绝包含非 ASCII 字符的项目路径（`应用开发` 是中文），构建会直接失败。
> 如需放回工作区，请用英文目录名，或建一个 junction 指过来。

---

## 快速获取安装包（CI 出包）

仓库：<https://github.com/RisoMi/clippings-app.git>
每次推送到 `main`，GitHub Actions 会先跑静态分析与单元测试，通过后再构建 **Release APK** 并上传为产物。

**拿包两步**：
1. 打开 [Actions · Build APK](https://github.com/RisoMi/clippings-app/actions/workflows/build.yml) → 点进最新一次运行（绿色勾）
2. 页面底部 **Artifacts** → 下载 `clippings-app-apk-<运行号>` → 解压出 `.apk` → 传到手机安装

打 tag 时附件名会跟随版本号（如 `clippings-app-1.1.0.apk`），日常推送则是 `clippings-app-<运行号>.apk`。

也可以直接调 API（公开仓库无需登录）：

```bash
curl -sL -o apk.zip "https://api.github.com/repos/RisoMi/clippings-app/actions/artifacts/<artifact_id>/zip"
```

**手动重跑**：Actions → 左栏 *Build APK* → 右上 `Run workflow`。

**发版（自动建 Release）**：打 tag 推送即可，Release 里会附带 APK；同一 tag 重跑会覆盖同一个附件，不会堆一堆旧包。

```bash
git tag v1.1.0 && git push origin v1.1.0
```

**流水线做了什么**

| Job | 内容 |
|---|---|
| 静态分析 + 单元测试 | `flutter analyze` + `flutter test`（17 用例），不通过不进入构建 |
| 构建 Release APK | JDK 17 + Flutter 3.47.2 + Gradle 缓存 → `flutter build apk --release`（versionCode 用流水号，保证可覆盖升级） |
| 分享入口断言 | 用 `aapt2` 反解 APK 内 Manifest，逐个校验 `ACTION_SEND`、`SEND_MULTIPLE`、`text/plain`、`text/html`、`image/*`、FileProvider、`MainActivity`；缺任一项直接判失败 |

> 最后这个断言是刻意加的：光编译通过不代表「分享到剪藏库」真的能出现，只有成品 Manifest 里注册齐了才算数。

iOS 侧另有手动工作流 `.github/workflows/ios-verify.yml`（macOS runner，未签名模拟器构建）。它只验证编译，**不产出可安装的 ipa**——打 ipa 需要 Apple 开发者账号与证书。

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
| 01 内容列表 | `ui/home_page.dart` | 今天/昨天/更早分组、类型快筛、三态卡片、空状态、**左滑删除（带 5 秒撤销）**、悬浮「＋」 |
| 02 分享速存 | `ui/paste_page.dart` | 分享 → 自动识别 → 确认页 → 入库（Android 真机可用） |
| 03 搜索 | `ui/search_page.dart` | 四字段检索、关键词高亮、类型筛选、未分类入口 |
| 04 标签 | `ui/tags_page.dart` | 数量聚合、色点、新建/重命名/删除、点标签看内容 |
| 05 详情 | `ui/detail_page.dart` | 正文、图片、标签增删、复制全文、删除 |
| 06 批量导出 | `ui/export_page.dart` | 多选/全选、md/txt、**原文链接单列**、**含图片自动打包 zip**、时间分组、前 14 行预览 |
| 07 导出完成 | `ui/done_page.dart` | 文件名/大小/条数（含图片数）、再次分享 |
| 08 粘贴速存 | `ui/paste_page.dart` | **加号先弹「剪贴板新增 / 手动输入」两选项**、**选剪贴板即自动读取、不用再点一次**、三步条、自动识别、建议标签、手动兜底 |
| 设置 | `ui/settings_page.dart` | 主题、统计、分享说明、示例数据、清空 |

## 5. Android 分享接入

`AndroidManifest.xml` 已注册三段 `intent-filter`：

- `ACTION_SEND` + `text/plain` / `text/html` → 链接与文字
- `ACTION_SEND` + `image/*` → 单张图片
- `ACTION_SEND_MULTIPLE` + `image/*` → 多图（当前取第一张）

`MainActivity` 收到后暂存：文本走 `EXTRA_TEXT` / `EXTRA_SUBJECT`；图片用 `ContentResolver` 复制到 `filesDir/share_incoming/`（原 Uri 读权限会过期），再通过 `MethodChannel` 交给 Dart。

冷启动：Dart 启动后调 `takePendingShare()` 领取；热启动：原生 `onNewIntent` **只发一个 `onShare` 信号、不带内容**，Dart 收到信号再回调用 `takePendingShare()` 拉取。这样做是因为 Dart 侧 handler 尚未注册时 `invokeMethod` 会静默丢弃，分享就永久丢了；「暂存 + 通知」两边都安全。Dart 回到前台时也会补拉一次。

### launchMode 必须是 singleTask（重要）

Flutter 模板默认给的是 `launchMode="singleTop"` + `taskAffinity=""`，这对**分享接收类应用是有害的**：

- 从其他 APP 分享过来时，系统会带 `FLAG_ACTIVITY_NEW_TASK` 启动；
- 空的 `taskAffinity` 让每次都被当作新任务，`singleTop` 又只在同一任务栈内去重；
- 结果是从不同 APP 分享会开出**多个 Activity 实例 → 多个 Dart 引擎**，各自持有启动时读到的内存快照；
- 表现就是「明明存了 4 条只显示 2 条，全部杀掉重开又正常」——文件里其实是全的，只是某个实例在看过期快照。

现在改为 `launchMode="singleTask"` + `taskAffinity="com.stonemii.clippings"`：全程只有一个实例，新分享走 `onNewIntent`。另外 `ClipStore` 增加了 `reloadIfChanged()`，回前台时按 `clips.json` 的修改时间决定是否重载，作为兜底。

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
- 不做网页元数据抓取，链接的标题与封面取决于源 APP 给了什么（原因见第 11 节）。
- CI 出的 APK 用 **debug 密钥签名**（Flutter 默认），可直接安装自用；上架应用商店需自行配置正式签名与 `applicationId`。

## 8. 与 PWA 版本的关系

`../应用开发/clippings-app`（PWA）保留作 Web 版：数据模型、识别规则、导出格式一致，可互相参照。原生版解决了 PWA 的两个硬伤——iOS 无法进分享面板、Android 依赖浏览器安装。

## 9. 验证记录

- `flutter analyze`：0 error / 0 warning
- `flutter test`：**31/31 通过**（识别、检索、分组、导出、原文链接、zip 方案分支、CRC32 标准向量、ZIP 结构自洽、示例数据判定，另有 4 个存储层用例跑真实读写）
- `dart run tool/zip_selftest.dart` 生成真实压缩包，再用 **Python `zipfile`** 独立校验：`testzip()` 无损坏条目、两条目 CRC 正确、`extractall()` 目录树为 `clips-2026-11-11.md` + `images/img_1.jpg` —— 确认「别的软件真的打得开」
- `flutter build apk --release`：构建成功（47.9 MB）
- `aapt2` 反查 APK Manifest：`launchMode=2`（singleTask）、`taskAffinity=com.stonemii.clippings`、分享入口六项齐全
- **GitHub Actions**：run #1~#3 全绿，产物与 Release 见开头

## 10. 导出格式

| 情况 | 产物 | 说明 |
|---|---|---|
| 无图片，或关掉「包含图片」 | `clips-YYYY-MM-DD.md` / `.txt` | 单文件，直接分享 |
| 含图片且开关打开 | `clips-YYYY-MM-DD.zip` | 内含正文 + `images/` 目录，正文用相对路径 `![](images/xxx.jpg)` 引用 |

- **原文链接**：Markdown 与纯文本都单独输出一行 `原文：<url>`，Markdown 里标题本身也是可点链接。加这一行是因为不少编辑器不渲染标题里的链接语法，纯文本更是完全没有链接。
- **zip 是自己写的**：`lib/zip.dart` 只做 store（不压缩）+ CRC32，约 130 行，没有引入 `archive` 这类三方包。
- zip 内正文文件名固定、图片按 `images/<原名>` 存放，解压即用。

## 11. 为什么分享 x.com 只有链接，分享到微信却有标题和图片

不是本应用的 bug，是两件事的差别：

1. **分享 Intent 只带源 APP 愿意给的东西。** Android `ACTION_SEND` 里没有「标题」「封面」这类字段，只有 `EXTRA_TEXT` / `EXTRA_SUBJECT` / `EXTRA_STREAM`。X（Twitter）分享通常只塞一个裸 URL，所以到我们手里就只有链接。
2. **预览卡片是「接收方自己抓的」。** 微信显示标题和缩略图，是微信客户端收到链接后**自己去请求网页**，读 `<head>` 里的 Open Graph 标签（`og:title` / `og:image` / `og:description`）再画成卡片。谁抓谁有卡片，不抓就只有一条 URL。

要让本应用也显示标题与封面，需要**自己加网页元数据抓取**（请求页面 → 解析 og 标签 → 下载封面存本地）。这块尚未实现，因为它是一个独立模块：要联网权限、要处理超时/反爬/图片体积限制。**X 尤其难**——它的页面依赖 JS 渲染且拦截非浏览器请求，直接抓 og 标签多数拿不到，通常得走官方 oEmbed / API。

## 12. 本轮变更（2026-11-11 第二轮）

1. 导出补原文链接（md 与 txt 都有独立行）
2. 含图片的导出改为 zip 打包，图片放包内并相对引用
3. 列表支持左滑删除，5 秒内可撤销（撤销窗口内先保留图片文件，超时才清理）
4. 加号改为先弹「从剪贴板新增 / 手动输入」两个选项
5. 修复多实例导致的数据不同步（singleTask + 暂存通知 + 回前台重载）
6. 单元测试从 17 个补到 24 个

## 13. 本轮变更（2026-11-11 第三轮）

1. **剪贴板自动读取**：选「从剪贴板新增」进页面就自动读一次，不用再点按钮。读不到就静默停在空状态（文案改为「没读到可识别的内容」，按钮改为「再读一次剪贴板」），不弹提示打扰。
2. **修复清空数据后重启又被补回来**：原来 `init()` 只要发现「列表为空」就种示例数据，把「用户主动清空」误判成「首次安装」。现在 `settings.json` 里记 `demoSeeded`，只有「没有内容」**且**「从未种过」才种（判定抽成 `core.shouldSeedDemo`）。清空时会把 `demoSeeded` 置 true 并落盘，所以重启后是干净的空状态。
   - **升级兼容**：`settings.json` 存在但没有 `demoSeeded` 字段时视为「已种过」（老版本安装），避免从旧版升级上来又被塞一次示例数据；全新安装时该文件不存在，仍会正常种一次。
3. 新增 `test/store_test.dart`：用临时目录 + mock 原生通道跑真实读写，覆盖「清空 → 重启不再补数据」「旧版设置文件升级不补数据」「清空后新增的内容重启仍在」「首次启动会种数据并落标记」。

/// 应用入口：主题、根导航（胶囊底部导航）、系统分享的落地处理。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bridge.dart';
import 'store.dart';
import 'theme.dart';
import 'ui/export_page.dart';
import 'ui/home_page.dart';
import 'ui/paste_page.dart';
import 'ui/settings_page.dart';
import 'ui/tags_page.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ClippingsApp());
}

class ClippingsApp extends StatefulWidget {
  const ClippingsApp({super.key});

  @override
  State<ClippingsApp> createState() => _ClippingsAppState();
}

class _ClippingsAppState extends State<ClippingsApp> with WidgetsBindingObserver {
  static const MethodChannel _channel = MethodChannel('com.stonemii.clippings/bridge');

  bool _ready = false;
  bool _draining = false;
  ThemeMode _mode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  Future<void> _boot() async {
    await ClipStore.instance.init();
    _mode = _toMode(ClipStore.instance.themeMode);
    ClipStore.instance.addListener(_syncTheme);

    _channel.setMethodCallHandler((call) async {
      // 原生在热启动收到新分享时只发信号，内容留在 pendingShare 里由这里主动拉
      if (call.method == 'onShare') await _drainShare();
      return null;
    });

    if (mounted) setState(() => _ready = true);

    // 等首帧完成再跳转，避免 Navigator 尚未挂载
    WidgetsBinding.instance.addPostFrameCallback((_) => _drainShare());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // 回到前台：对齐磁盘 + 补拉可能漏掉的分享
    ClipStore.instance.reloadIfChanged();
    _drainShare();
  }

  /// 取走原生暂存的分享内容并打开确认页。
  /// 冷启动、热启动、回前台三条路径都汇到这里，保证不漏也不重复。
  Future<void> _drainShare() async {
    if (_draining || !mounted) return;
    _draining = true;
    try {
      await ClipStore.instance.reloadIfChanged();
      final payload = await Bridge.takePendingShare();
      if (payload != null) openSharePayload(payload);
    } finally {
      _draining = false;
    }
  }

  void _syncTheme() {
    final next = _toMode(ClipStore.instance.themeMode);
    if (next != _mode && mounted) setState(() => _mode = next);
  }

  ThemeMode _toMode(String value) => switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ClipStore.instance.removeListener(_syncTheme);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '剪藏库',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _mode,
      home: _ready ? const RootShell() : const _BootScreen(),
    );
  }
}

class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.bookmark_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 16),
            Text('剪藏库', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 6),
            Text('正在打开本地收藏…', style: TextStyle(fontSize: 12, color: c.sub)),
          ],
        ),
      ),
    );
  }
}

/// 根容器：四个主 tab + 胶囊底部导航 + 全局悬浮「＋」
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static const _pages = [HomePage(), TagsPage(), ExportPage(), SettingsPage()];

  static const _tabs = [
    (Icons.bookmark_border_rounded, '收藏'),
    (Icons.sell_outlined, '标签'),
    (Icons.ios_share_rounded, '导出'),
    (Icons.settings_outlined, '设置'),
  ];

  /// 加号：先选「剪贴板新增 / 手动输入」，再进对应的录入页
  Future<void> _showAddSheet() async {
    final mode = await showModalBottomSheet<PasteMode>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final sc = sheetContext.colors;
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: BoxDecoration(
              color: sc.card,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: sc.line),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: sc.line, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '新增收藏',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: sc.ink),
                ),
                const SizedBox(height: 12),
                _AddOption(
                  icon: Icons.content_paste_rounded,
                  title: '从剪贴板新增',
                  subtitle: '自动读取并识别链接或文字',
                  onTap: () => Navigator.of(sheetContext).pop(PasteMode.clipboard),
                ),
                const SizedBox(height: 10),
                _AddOption(
                  icon: Icons.edit_note_rounded,
                  title: '手动输入',
                  subtitle: '自己粘贴链接，或写一段想法',
                  onTap: () => Navigator.of(sheetContext).pop(PasteMode.manual),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('取消'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (mode == null || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PastePage(mode: mode)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeFg = isDark ? const Color(0xFF151917) : Colors.white;

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: _pages),
      floatingActionButton: _index == 0
          ? Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FloatingActionButton(
                onPressed: _showAddSheet,
                backgroundColor: c.accent,
                foregroundColor: activeFg,
                elevation: 4,
                shape: const CircleBorder(),
                child: const Icon(Icons.add_rounded, size: 26),
              ),
            )
          : null,
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: Container(
          height: 62,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(31),
            border: Border.all(color: c.line),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: List.generate(_tabs.length, (i) {
              final active = _index == i;
              final (icon, label) = _tabs[i];
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _index = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: active ? c.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 18, color: active ? activeFg : c.weak),
                        const SizedBox(height: 3),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: active ? activeFg : c.weak,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// 底部选择面板里的一行选项
class _AddOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AddOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.row),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.soft,
          borderRadius: BorderRadius.circular(AppRadii.row),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 19, color: c.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: c.sub)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: c.weak),
          ],
        ),
      ),
    );
  }
}

/// 分享内容 → 打开确认页
void openSharePayload(SharePayload payload) {
  final nav = rootNavigatorKey.currentState;
  if (nav == null) return;
  final draft = buildDraftFromShare(payload);
  if (draft == null) return;
  nav.push(MaterialPageRoute(builder: (_) => PastePage(initial: draft)));
}

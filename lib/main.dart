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

class _ClippingsAppState extends State<ClippingsApp> {
  static const MethodChannel _channel = MethodChannel('com.stonemii.clippings/bridge');

  bool _ready = false;
  ThemeMode _mode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await ClipStore.instance.init();
    _mode = _toMode(ClipStore.instance.themeMode);
    ClipStore.instance.addListener(_syncTheme);

    _channel.setMethodCallHandler((call) async {
      // 原生在热启动时收到新分享会回调这里
      if (call.method == 'onShare' && call.arguments is Map) {
        openSharePayload(SharePayload.fromMap(call.arguments as Map));
      }
      return null;
    });

    if (mounted) setState(() => _ready = true);

    final pending = await Bridge.takePendingShare();
    if (pending != null) {
      // 等首帧完成再跳转，避免 Navigator 尚未挂载
      WidgetsBinding.instance.addPostFrameCallback((_) => openSharePayload(pending));
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
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PastePage()),
                ),
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

/// 分享内容 → 打开确认页
void openSharePayload(SharePayload payload) {
  final nav = rootNavigatorKey.currentState;
  if (nav == null) return;
  final draft = buildDraftFromShare(payload);
  if (draft == null) return;
  nav.push(MaterialPageRoute(builder: (_) => PastePage(initial: draft)));
}

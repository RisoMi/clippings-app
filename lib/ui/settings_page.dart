/// 设置：外观、数据统计、分享接入说明、示例数据与清空。
library;

import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'paste_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const _themes = [
    ('light', '浅色'),
    ('dark', '深色'),
    ('system', '跟随系统'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: c.bg,
      body: ListenableBuilder(
        listenable: ClipStore.instance,
        builder: (context, _) {
          final store = ClipStore.instance;
          final stats = store.stats;

          return SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
              children: [
                const PageHeader(eyebrow: '偏好与数据', title: '设置'),
                const SectionHeader(title: '外观'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (value, label) in _themes)
                      GestureDetector(
                        onTap: () => store.setThemeMode(value),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          height: 30,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: store.themeMode == value ? c.accent : c.card,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: store.themeMode == value ? c.accent : c.line,
                            ),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: store.themeMode == value ? FontWeight.w600 : FontWeight.w500,
                              color: store.themeMode == value
                                  ? (isDark ? const Color(0xFF151917) : Colors.white)
                                  : c.sub,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SectionHeader(title: '数据'),
                _InfoRow(
                  title: '收藏总数',
                  subtitle: '链接 ${stats.byType[ClipType.link] ?? 0} · 文本 ${stats.byType[ClipType.text] ?? 0} · 图片 ${stats.byType[ClipType.image] ?? 0}',
                  trailing: '${stats.total}',
                ),
                _InfoRow(title: '本周新增', subtitle: '最近 7 天', trailing: '${stats.week}'),
                _InfoRow(title: '未分类', subtitle: '还没有标签的内容', trailing: '${stats.uncategorized}'),
                _InfoRow(
                  title: '存储方式',
                  subtitle: store.isMemoryOnly
                      ? '内存（重启会丢失，请检查存储权限）'
                      : '应用私有目录 · JSON',
                  trailing: '',
                ),
                const SectionHeader(title: '分享接入'),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.accentSoft,
                    borderRadius: BorderRadius.circular(AppRadii.row),
                  ),
                  child: Text(
                    '在任意 APP 里选「分享」→「剪藏库」，链接、文字或图片会直接进入确认页。\n'
                    '如果某个 APP 的分享面板里没有本应用，说明它用的是自绘面板，改用「复制 → 粘贴速存」。',
                    style: TextStyle(fontSize: 11, height: 1.75, color: c.accent),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PastePage()),
                  ),
                  child: const Text('打开粘贴速存'),
                ),
                const SectionHeader(title: '维护'),
                OutlinedButton(
                  onPressed: () async {
                    await store.seedDemo();
                    if (context.mounted) showToast(context, '已载入示例数据');
                  },
                  child: const Text('重新载入示例数据'),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('清空全部数据', style: TextStyle(fontSize: 16)),
                        content: const Text('收藏、标签与图片都会被删除，此操作不可恢复。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('清空'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await store.clearAll();
                      if (context.mounted) showToast(context, '已清空');
                    }
                  },
                  child: Text('清空全部数据', style: TextStyle(color: c.danger)),
                ),
                const SizedBox(height: 20),
                Text(
                  '剪藏库 · Flutter 版 v1.0\n数据只存在本机，不上传任何服务器',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, height: 1.8, color: c.weak),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String trailing;

  const _InfoRow({required this.title, required this.subtitle, required this.trailing});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadii.row),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ink)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 11, color: c.weak)),
              ],
            ),
          ),
          if (trailing.isNotEmpty)
            Text(trailing, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.sub)),
        ],
      ),
    );
  }
}

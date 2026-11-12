/// 设置：外观、数据统计、备份与恢复、分享接入说明、维护。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../backup.dart';
import '../bridge.dart';
import '../core.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'paste_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _themes = [
    ('light', '浅色'),
    ('dark', '深色'),
    ('system', '跟随系统'),
  ];

  bool _busy = false;

  /* ------------------------------ 备份与恢复 ------------------------------ */

  Future<void> _exportBackup() async {
    setState(() => _busy = true);
    try {
      final file = await ClipStore.instance.createBackup();
      final size = await file.length();
      final name = file.path.split(Platform.pathSeparator).last;
      final shared = await Bridge.shareFile(file.path, 'application/zip', title: name);
      if (!mounted) return;
      final sizeLabel = size > 1024 * 1024
          ? '${(size / 1024 / 1024).toStringAsFixed(1)} MB'
          : '${(size / 1024).ceil()} KB';
      showToast(
        context,
        shared
            ? '备份已生成（$sizeLabel），选「保存到文件」或发到电脑'
            : '备份已生成（$sizeLabel），保存在应用目录',
      );
    } catch (error) {
      if (mounted) showToast(context, '导出备份失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBackup() async {
    setState(() => _busy = true);
    try {
      final picked = await Bridge.pickBackupFile();
      if (!mounted) return;
      if (picked.status == Bridge.pickCancelled) return;
      if (picked.status == Bridge.pickTooLarge) {
        showToast(context, '备份文件超过 200 MB，暂不支持导入');
        return;
      }
      if (!picked.ok) {
        showToast(context, '没能读取到文件，请换一个文件管理器再试');
        return;
      }

      final store = ClipStore.instance;
      final content = await store.readBackupFile(picked.path!);
      if (!mounted) return;

      // 本地只有示例数据（或空空如也）时直接覆盖，不必多问一步
      var replace = onlySampleData(store.clips);
      if (!replace) {
        final choice = await _askImportMode(content, store.clips.length);
        if (choice == null || !mounted) return;
        replace = choice;
      }

      final total = await store.applyBackup(content, replace: replace);
      if (!mounted) return;
      showToast(context, '已导入 ${content.clipCount} 条，当前共 $total 条');
    } on BackupException catch (error) {
      if (mounted) showToast(context, error.message);
    } catch (error) {
      if (mounted) showToast(context, '导入失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _askImportMode(BackupContent content, int localCount) {
    final exported = content.manifest.exportedAt.year == 1970
        ? '未知时间'
        : formatDateTime(content.manifest.exportedAt);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('导入备份', style: TextStyle(fontSize: 16)),
        content: Text(
          '备份里有 ${content.clipCount} 条内容'
          '${content.imageCount > 0 ? '、${content.imageCount} 张图片' : ''}'
          '，导出于 $exported。\n\n'
          '本地现有 $localCount 条。\n'
          '「覆盖」会清空本地、只保留备份内容；「合并」会保留本地，并按 id 去重。',
          style: const TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('合并')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('覆盖')),
        ],
      ),
    );
  }

  /* ------------------------------ 界面 ------------------------------ */

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
                const SectionHeader(title: '备份与恢复'),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.accentSoft,
                    borderRadius: BorderRadius.circular(AppRadii.row),
                  ),
                  child: Text(
                    '备份是一个 .zip，包含全部收藏、标签与图片原图。'
                    '重装应用或换手机后，把它导回来即可恢复历史内容。',
                    style: TextStyle(fontSize: 11, height: 1.75, color: c.accent),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _exportBackup,
                        icon: const Icon(Icons.archive_outlined, size: 17),
                        label: const Text('导出备份'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _importBackup,
                        icon: const Icon(Icons.unarchive_outlined, size: 17),
                        label: const Text('导入备份'),
                      ),
                    ),
                  ],
                ),
                if (_busy)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
                        ),
                        const SizedBox(width: 8),
                        Text('处理中…', style: TextStyle(fontSize: 11, color: c.sub)),
                      ],
                    ),
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
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('保存链接时自动获取标题', style: TextStyle(fontSize: 12, color: c.ink)),
                            const SizedBox(height: 2),
                            Text(
                              '会请求一次网页，只读标题与摘要；关掉后只存链接本身',
                              style: TextStyle(fontSize: 11, color: c.weak),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: store.fetchMetadata,
                        onChanged: (value) => store.setFetchMetadata(value),
                        activeThumbColor: isDark ? const Color(0xFF151917) : Colors.white,
                        activeTrackColor: c.accent,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PastePage()),
                  ),
                  child: const Text('打开粘贴速存'),
                ),
                const SectionHeader(title: '维护'),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await store.seedDemo();
                          if (context.mounted) showToast(context, '已载入示例数据');
                        },
                  child: const Text('重新载入示例数据'),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('清空全部数据', style: TextStyle(fontSize: 16)),
                              content: const Text('收藏、标签与图片都会被删除，此操作不可恢复。建议先导出备份。'),
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
                  '剪藏库 · Flutter 版 v1.2\n数据只存在本机，不上传任何服务器',
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

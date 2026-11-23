/// 06 批量导出：按有数据的日期单选、Markdown / 纯文本、图片打包、文件预览。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../bridge.dart';
import '../core.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import '../zip.dart';
import 'done_page.dart';

class ExportPage extends StatefulWidget {
  const ExportPage({super.key});

  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  String? _selectedKey;
  bool _initialized = false;
  bool _busy = false;

  /// 首次进入默认选中今天（今天没数据则选最近有数据的一天）；
  /// 选中日期被删空后自动回退，避免停在无效日期上。
  void _syncSelection(List<ExportDateGroup> groups) {
    if (!_initialized) {
      _initialized = true;
      _selectedKey = defaultExportDateKey(groups);
      return;
    }
    if (_selectedKey != null && !groups.any((g) => g.key == _selectedKey)) {
      _selectedKey = defaultExportDateKey(groups);
    }
  }

  ExportDateGroup? get _selectedGroup {
    final groups = groupByExportDate(ClipStore.instance.clips);
    for (final group in groups) {
      if (group.key == _selectedKey) return group;
    }
    return null;
  }

  List<Clip> get _selectedClips => _selectedGroup?.clips ?? const [];

  /// 当前选中的内容里，真实存在于磁盘的图片（文件名 → 文件）
  Future<Map<String, File>> _collectImages(List<Clip> clips) async {
    final store = ClipStore.instance;
    final result = <String, File>{};
    for (final clip in clips) {
      final name = clip.imageFileName;
      if (name == null || result.containsKey(name)) continue;
      final file = store.imageFile(name);
      if (await file.exists()) result[name] = file;
    }
    return result;
  }

  ExportPlan _plan({required DateTime fileDate}) {
    final store = ClipStore.instance;
    return planExport(
      _selectedClips,
      format: store.exportFormat,
      groupByTime: store.exportGroup,
      includeImages: store.exportImages,
      fileDate: fileDate,
    );
  }

  String _preview({required DateTime fileDate}) {
    if (_selectedClips.isEmpty) return '还没有勾选内容。';
    final lines = _plan(fileDate: fileDate).content.split('\n');
    final head = lines.take(14).join('\n');
    return lines.length > 14 ? '$head\n…' : head;
  }

  Future<void> _export() async {
    final key = _selectedKey;
    if (key == null) return;
    final clips = _selectedClips;
    if (clips.isEmpty) return;
    setState(() => _busy = true);
    final store = ClipStore.instance;
    try {
      final dir = Directory('${store.dataDir}/exports');
      await dir.create(recursive: true);

      final images = store.exportImages ? await _collectImages(clips) : <String, File>{};
      final now = DateTime.now();
      final fileDate = DateTime.parse(key);
      // hasImages 用「真实存在的图片」判断，避免勾了开关但图已丢失时产出空包
      // fileDate 只影响文件名；正文里的「今天/昨天」仍按真实当前时间分组
      final plan = planExport(
        clips,
        format: store.exportFormat,
        groupByTime: store.exportGroup,
        includeImages: store.exportImages,
        hasImages: images.isNotEmpty,
        now: now,
        fileDate: fileDate,
      );

      final file = File('${dir.path}/${plan.fileName}');
      if (plan.asZip) {
        // 正文与 images/ 同在一个压缩包里；正文里的 `![](images/xxx.jpg)`
        // 是相对路径，解压后直接能显示。
        final entries = <ZipEntry>[
          ZipEntry(plan.textFileName, utf8.encode(plan.content), modified: now),
        ];
        for (final entry in images.entries) {
          final bytes = await entry.value.readAsBytes();
          var modified = now;
          try {
            modified = await entry.value.lastModified();
          } catch (_) {}
          entries.add(ZipEntry('images/${entry.key}', bytes, modified: modified));
        }
        await file.writeAsBytes(buildZipArchive(entries), flush: true);
      } else {
        await file.writeAsString(plan.content, flush: true);
      }

      final size = await file.length();
      final shared = await Bridge.shareFile(file.path, plan.mime, title: plan.fileName);

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DonePage(
            fileName: plan.fileName,
            filePath: file.path,
            byteSize: size,
            count: clips.length,
            format: plan.asZip ? 'zip' : store.exportFormat,
            shared: shared,
            imageCount: images.length,
          ),
        ),
      );
    } catch (error) {
      if (mounted) showToast(context, '导出失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final store = ClipStore.instance;

    return Scaffold(
      backgroundColor: c.bg,
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final groups = groupByExportDate(store.clips);
          _syncSelection(groups);
          final selected = _selectedGroup;
          final selectedCount = selected?.count ?? 0;
          final fileDate = selected != null ? DateTime.parse(selected.key) : DateTime.now();
          final visible = selected?.clips.take(8).toList() ?? const <Clip>[];

          return SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
              children: [
                const PageHeader(eyebrow: '批量导出', title: '导出内容'),
                const SizedBox(height: 4),
                Text(
                  '按日期导出，一次打包某一天的全部收藏。',
                  style: TextStyle(fontSize: 12, color: c.sub),
                ),
                const SizedBox(height: 14),
                SectionHeader(title: '选择日期', trailing: groups.isEmpty ? null : '共 ${groups.length} 天'),
                if (groups.isEmpty)
                  const EmptyView(
                    icon: Icons.ios_share_rounded,
                    title: '还没有内容可导出',
                    description: '先存几条收藏，再回来打包成 Markdown 或纯文本。',
                  )
                else
                  for (final group in groups)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _DateRow(
                        label: group.label,
                        date: group.key,
                        count: group.count,
                        active: group.key == _selectedKey,
                        onTap: () => setState(() => _selectedKey = group.key),
                      ),
                    ),
                if (selected != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${selected.label}共 $selectedCount 条，导出会包含全部内容。',
                    style: TextStyle(fontSize: 11, color: c.weak),
                  ),
                  const SizedBox(height: 10),
                  for (final clip in visible)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ClipCard(clip: clip),
                    ),
                  if (selectedCount > visible.length)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 4),
                      child: Text(
                        '仅预览前 ${visible.length} 条。',
                        style: TextStyle(fontSize: 11, color: c.weak),
                      ),
                    ),
                ],
                const SectionHeader(title: '导出格式'),
                Row(
                  children: [
                    Expanded(
                      child: _FormatCard(
                        title: 'Markdown .md',
                        subtitle: '含标题、标签、原文链接',
                        active: store.exportFormat == 'md',
                        onTap: () => store.setExportOptions(format: 'md'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _FormatCard(
                        title: '纯文本 .txt',
                        subtitle: '仅正文，体积最小',
                        active: store.exportFormat == 'txt',
                        onTap: () => store.setExportOptions(format: 'txt'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SwitchRow(
                  label: '包含图片（自动打包成 zip）',
                  value: store.exportImages,
                  onChanged: (v) => store.setExportOptions(images: v),
                ),
                _SwitchRow(
                  label: '按收藏时间分组',
                  value: store.exportGroup,
                  onChanged: (v) => store.setExportOptions(group: v),
                ),
                const SectionHeader(title: '文件预览', trailing: '前 14 行'),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: c.soft, borderRadius: BorderRadius.circular(AppRadii.row)),
                  child: Text(
                    _preview(fileDate: fileDate),
                    style: TextStyle(fontSize: 11, height: 1.7, color: c.ink, fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: (_busy || selectedCount == 0) ? null : _export,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('生成文件并分享'),
                ),
                const SizedBox(height: 8),
                Text(
                  '无图片导出 .md / .txt；勾选内容含图片时导出 .zip，解压后正文可直接看到配图。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: c.weak),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  final String label;
  final String date;
  final int count;
  final bool active;
  final VoidCallback onTap;

  const _DateRow({
    required this.label,
    required this.date,
    required this.count,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(AppRadii.row),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.row),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.row),
            border: Border.all(color: active ? c.accent : c.line, width: active ? 1.4 : 1),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_month_rounded, size: 18, color: active ? c.accent : c.weak),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: active ? c.accent : c.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(date, style: TextStyle(fontSize: 11, color: c.weak)),
                  ],
                ),
              ),
              Text('$count 条', style: TextStyle(fontSize: 11, color: c.sub)),
              const SizedBox(width: 10),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? c.accent : Colors.transparent,
                  border: Border.all(color: active ? c.accent : c.weak, width: 1.6),
                ),
                child: active
                    ? Icon(
                        Icons.check_rounded,
                        size: 13,
                        color: isDark ? const Color(0xFF151917) : Colors.white,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormatCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool active;
  final VoidCallback onTap;

  const _FormatCard({
    required this.title,
    required this.subtitle,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: active ? c.accentSoft : c.card,
          borderRadius: BorderRadius.circular(AppRadii.row),
          border: Border.all(color: active ? c.accent : c.line, width: active ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? c.accent : c.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 10, height: 1.5, color: active ? c.sub : c.weak)),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: c.ink))),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF151917)
                : Colors.white,
            activeTrackColor: c.accent,
          ),
        ],
      ),
    );
  }
}

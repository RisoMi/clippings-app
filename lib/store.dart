/// 本地存储：JSON 文件（clips.json / tags.json）放在应用私有目录。
/// 用 ChangeNotifier 驱动 UI 刷新；写入走「临时文件 + rename」保证原子性。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'bridge.dart';
import 'models.dart';

class AppStats {
  final int total;
  final int week;
  final int uncategorized;
  final Map<ClipType, int> byType;

  const AppStats({
    required this.total,
    required this.week,
    required this.uncategorized,
    required this.byType,
  });
}

class ClipStore extends ChangeNotifier {
  ClipStore._();

  static final ClipStore instance = ClipStore._();

  final List<Clip> _clips = [];
  final List<AppTag> _tags = [];

  String _dir = '';
  bool _ready = false;
  bool _memoryOnly = false;

  bool get isReady => _ready;
  bool get isMemoryOnly => _memoryOnly;

  List<Clip> get clips => List.unmodifiable(_clips);

  List<AppTag> get tags => List.unmodifiable(_tags);

  String get dataDir => _dir;

  File imageFile(String fileName) => File('$_dir/images/$fileName');

  String imagePath(String fileName) => '$_dir/images/$fileName';

  Directory get exportDir => Directory('$_dir/exports');

  String get clipsFile => '$_dir/clips.json';

  String get tagsFile => '$_dir/tags.json';

  Future<void> init() async {
    if (_ready) return;
    _dir = await Bridge.filesDir();
    try {
      await Directory('$_dir/images').create(recursive: true);
      await Directory('$_dir/exports').create(recursive: true);
      await _load();
      if (_clips.isEmpty) {
        await seedDemo(silent: true);
      }
    } catch (error, stack) {
      // 目录不可写时退化为纯内存，至少保证本次会话可用
      _memoryOnly = true;
      debugPrint('ClipStore init failed: $error\n$stack');
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> _load() async {
    final clipsFile = File(this.clipsFile);
    if (await clipsFile.exists()) {
      final raw = await clipsFile.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      _clips
        ..clear()
        ..addAll(list.map((e) => Clip.fromJson(e as Map<String, dynamic>)));
      _clips.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    final tagsFile = File(this.tagsFile);
    if (await tagsFile.exists()) {
      final raw = await tagsFile.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      _tags
        ..clear()
        ..addAll(list.map((e) => AppTag.fromJson(e as Map<String, dynamic>)));
    }

    final settingsFile = File(settingsPath);
    if (await settingsFile.exists()) {
      final raw = await settingsFile.readAsString();
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _themeMode = map['themeMode'] as String? ?? 'system';
      _exportFormat = map['exportFormat'] as String? ?? 'md';
      _exportGroup = map['exportGroup'] as bool? ?? true;
      _exportImages = map['exportImages'] as bool? ?? true;
    }
  }

  Future<void> _persistClips() async {
    if (_memoryOnly) return;
    await _atomicWrite(clipsFile, jsonEncode(_clips.map((e) => e.toJson()).toList()));
  }

  Future<void> _persistTags() async {
    if (_memoryOnly) return;
    await _atomicWrite(tagsFile, jsonEncode(_tags.map((e) => e.toJson()).toList()));
  }

  Future<void> _atomicWrite(String path, String content) async {
    final tmp = File('$path.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(path);
  }

  /* ------------------------------ 设置 ------------------------------ */

  String get settingsPath => '$_dir/settings.json';

  String _themeMode = 'system';
  String _exportFormat = 'md';
  bool _exportGroup = true;
  bool _exportImages = true;

  String get themeMode => _themeMode;

  String get exportFormat => _exportFormat;

  bool get exportGroup => _exportGroup;

  bool get exportImages => _exportImages;

  Future<void> setThemeMode(String mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    await _persistSettings();
    notifyListeners();
  }

  Future<void> setExportOptions({String? format, bool? group, bool? images}) async {
    if (format != null) _exportFormat = format;
    if (group != null) _exportGroup = group;
    if (images != null) _exportImages = images;
    await _persistSettings();
    notifyListeners();
  }

  Future<void> _persistSettings() async {
    if (_memoryOnly) return;
    await _atomicWrite(
      settingsPath,
      jsonEncode({
        'themeMode': _themeMode,
        'exportFormat': _exportFormat,
        'exportGroup': _exportGroup,
        'exportImages': _exportImages,
      }),
    );
  }

  /* ------------------------------ clips ------------------------------ */

  Future<void> addClip(Clip clip) async {
    final index = _clips.indexWhere((item) => item.id == clip.id);
    if (index >= 0) {
      _clips[index] = clip;
    } else {
      _clips.insert(0, clip);
    }
    _clips.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _persistClips();
    notifyListeners();
  }

  Future<void> updateClip(Clip clip) async {
    final index = _clips.indexWhere((item) => item.id == clip.id);
    if (index < 0) return;
    _clips[index] = clip;
    await _persistClips();
    notifyListeners();
  }

  Future<void> deleteClip(String id) async {
    final index = _clips.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final removed = _clips.removeAt(index);
    if (removed.imageFileName != null) {
      try {
        final file = imageFile(removed.imageFileName!);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // 图片删不掉不影响主流程
      }
    }
    await _persistClips();
    notifyListeners();
  }

  /* ------------------------------ tags ------------------------------ */

  List<TagCount> get tagCounts {
    final counts = <String, int>{};
    for (final clip in _clips) {
      for (final tag in clip.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final colors = {for (final tag in _tags) tag.name: tag.color};
    final names = <String>{...counts.keys, ...colors.keys};
    final list = names
        .map((name) => TagCount(
              name: name,
              count: counts[name] ?? 0,
              color: colors[name] ?? 0xFF2F6A54,
            ))
        .toList()
      ..sort((a, b) => b.count != a.count ? b.count.compareTo(a.count) : a.name.compareTo(b.name));
    return list;
  }

  Future<void> ensureTags(Iterable<String> names) async {
    var changed = false;
    for (final name in names) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) continue;
      if (_tags.any((tag) => tag.name == trimmed)) continue;
      _tags.add(AppTag(name: trimmed, color: _palette[_tags.length % _palette.length]));
      changed = true;
    }
    if (changed) {
      await _persistTags();
    }
  }

  Future<void> renameTag(String from, String to) async {
    final target = to.trim();
    if (target.isEmpty || from == target) return;
    for (var i = 0; i < _clips.length; i++) {
      final clip = _clips[i];
      if (!clip.tags.contains(from)) continue;
      final next = clip.tags.map((tag) => tag == from ? target : tag).toSet().toList();
      _clips[i] = clip.copyWith(tags: next);
    }
    _tags.removeWhere((tag) => tag.name == from);
    await ensureTags([target]);
    await _persistClips();
    notifyListeners();
  }

  Future<void> deleteTag(String name) async {
    for (var i = 0; i < _clips.length; i++) {
      final clip = _clips[i];
      if (!clip.tags.contains(name)) continue;
      _clips[i] = clip.copyWith(tags: clip.tags.where((tag) => tag != name).toList());
    }
    _tags.removeWhere((tag) => tag.name == name);
    await _persistClips();
    await _persistTags();
    notifyListeners();
  }

  AppStats get stats {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final byType = <ClipType, int>{ClipType.link: 0, ClipType.text: 0, ClipType.image: 0};
    var week = 0;
    var uncategorized = 0;
    for (final clip in _clips) {
      byType[clip.type] = (byType[clip.type] ?? 0) + 1;
      if (clip.createdAt.isAfter(weekAgo)) week++;
      if (clip.tags.isEmpty) uncategorized++;
    }
    return AppStats(
      total: _clips.length,
      week: week,
      uncategorized: uncategorized,
      byType: byType,
    );
  }

  Future<void> clearAll() async {
    _clips.clear();
    _tags.clear();
    if (!_memoryOnly) {
      try {
        final images = Directory('$_dir/images');
        if (await images.exists()) {
          for (final entity in images.listSync()) {
            if (entity is File) {
              try {
                await entity.delete();
              } catch (_) {}
            }
          }
        }
        for (final path in [clipsFile, tagsFile]) {
          final file = File(path);
          if (await file.exists()) await file.delete();
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  /* ------------------------------ 示例数据 ------------------------------ */

  static const _palette = [
    0xFF2F6A54,
    0xFF6E8F7C,
    0xFF9AAE9F,
    0xFFC1A47C,
    0xFF8C8A80,
    0xFFB5B0A2,
  ];

  Future<void> seedDemo({bool silent = false}) async {
    final now = DateTime.now();
    final demo = <Clip>[
      Clip(
        id: 'seed-link-1',
        type: ClipType.link,
        title: '如何用一张卡片整理零散灵感',
        summary: '把刷到的好内容先存下来，再用标签慢慢归位。',
        source: '少数派 · sspai.com',
        url: 'https://sspai.com/post/84217',
        domain: 'sspai.com',
        tags: const ['效率工具', '待读'],
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      Clip(
        id: 'seed-text-1',
        type: ClipType.text,
        title: '读到的一段话，先存下来',
        summary: '「信息的价值不在于收藏那一刻，而在于重新找到它的那一刻。」',
        source: '微信 · 11:08',
        url: '',
        domain: '',
        tags: const ['摘录'],
        createdAt: now.subtract(const Duration(hours: 5)),
      ),
      Clip(
        id: 'seed-image-1',
        type: ClipType.image,
        title: '周末在颐和路拍到的光',
        summary: '那天下午的光刚好落在梧桐叶上，路边全是老房子。',
        source: '小红书 · 09:24',
        url: '',
        domain: '',
        tags: const ['摄影'],
        createdAt: now.subtract(const Duration(hours: 8)),
      ),
      Clip(
        id: 'seed-link-2',
        type: ClipType.link,
        title: '南京颐和路的一条 City Walk 路线',
        summary: '从公馆区走到先锋书店，全程 4 公里，适合下午出发。',
        source: '少数派 · sspai.com',
        url: 'https://sspai.com/post/85120',
        domain: 'sspai.com',
        tags: const ['旅行'],
        createdAt: now.subtract(const Duration(hours: 26)),
      ),
    ];

    for (final clip in demo) {
      final index = _clips.indexWhere((item) => item.id == clip.id);
      if (index >= 0) {
        _clips[index] = clip;
      } else {
        _clips.add(clip);
      }
    }
    _clips.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await ensureTags(demo.expand((clip) => clip.tags));
    await _persistClips();
    if (!silent) notifyListeners();
  }

  /// 把分享进来的图片归位到 images 目录，返回文件名
  Future<String?> adoptImage(String sourcePath) async {
    try {
      final file = File(sourcePath);
      if (!await file.exists()) return null;
      final name = 'img_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final target = File('$_dir/images/$name');
      await target.parent.create(recursive: true);
      await file.copy(target.path);
      if (file.path != target.path) {
        try {
          await file.delete();
        } catch (_) {}
      }
      return name;
    } catch (_) {
      return null;
    }
  }
}

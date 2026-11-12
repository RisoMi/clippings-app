/// 本地存储：JSON 文件（clips.json / tags.json）放在应用私有目录。
/// 用 ChangeNotifier 驱动 UI 刷新；写入走「临时文件 + rename」保证原子性。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'backup.dart';
import 'bridge.dart';
import 'core.dart';
import 'models.dart';
import 'zip.dart';

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

  /// clips.json 最近一次已知的修改时间，用于判断磁盘上是否有别的写入
  DateTime? _clipsMtime;

  /// 测试用：把单例恢复到「刚创建」的状态，用来模拟杀掉进程再打开
  @visibleForTesting
  void resetForTest() {
    _clips.clear();
    _tags.clear();
    _dir = '';
    _ready = false;
    _memoryOnly = false;
    _demoSeeded = false;
    _clipsMtime = null;
    _themeMode = 'system';
    _exportFormat = 'md';
    _exportGroup = true;
    _exportImages = true;
  }

  Future<void> init() async {
    if (_ready) return;
    _dir = await Bridge.filesDir();
    try {
      await Directory('$_dir/images').create(recursive: true);
      await Directory('$_dir/exports').create(recursive: true);
      await _load();
      // 注意：只判「列表为空」会在「用户主动清空后重启」时把示例数据种回来，
      // 所以必须同时满足「没种过」。
      if (shouldSeedDemo(hasClips: _clips.isNotEmpty, demoSeeded: _demoSeeded)) {
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
      _clipsMtime = await clipsFile.lastModified();
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
      // 兼容旧版本：settings.json 存在但没有 demoSeeded 字段，说明是 1.1.1 之前的安装，
      // 已经种过数据了。这里默认 true，避免升级后示例数据突然又冒回来。
      // （全新安装时 settings.json 根本不存在，走不到这里，仍会正常种一次。）
      _demoSeeded = map['demoSeeded'] as bool? ?? true;
    }
  }

  /// 磁盘上的数据被别人改过就重新加载。
  /// 正常情况下 singleTask 只会有这一个实例；这是兜底，防止
  /// 极端情况（进程被回收后重启、用户手动清数据）读到过期快照。
  Future<void> reloadIfChanged() async {
    if (_memoryOnly || !_ready) return;
    try {
      final file = File(clipsFile);
      if (!await file.exists()) return;
      final mtime = await file.lastModified();
      if (_clipsMtime != null && !mtime.isAfter(_clipsMtime!)) return;
      await _load();
      notifyListeners();
    } catch (_) {
      // 读不到就保持现状，不打断界面
    }
  }

  Future<void> _persistClips() async {
    if (_memoryOnly) return;
    await _atomicWrite(clipsFile, jsonEncode(_clips.map((e) => e.toJson()).toList()));
    try {
      _clipsMtime = await File(clipsFile).lastModified();
    } catch (_) {}
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

  /// 是否已经种过示例数据。用来区分「首次安装」和「用户主动清空」。
  bool _demoSeeded = false;

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
        'demoSeeded': _demoSeeded,
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

  /// 删除一条收藏。
  /// [keepImage] 为 true 时先留着图片，给「撤销」留余地；
  /// 撤销窗口结束后再调 [purgeImage] 清理，避免撤销回来图没了。
  Future<void> deleteClip(String id, {bool keepImage = false}) async {
    final index = _clips.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final removed = _clips.removeAt(index);
    if (!keepImage && removed.imageFileName != null) {
      await purgeImage(removed.imageFileName!);
    }
    await _persistClips();
    notifyListeners();
  }

  /// 清理不再被引用的图片文件
  Future<void> purgeImage(String fileName) async {
    try {
      final file = imageFile(fileName);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 图片删不掉不影响主流程
    }
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
    // 记住「已经种过」：清空是用户的明确意图，重启后不该把示例数据补回来
    _demoSeeded = true;
    await _persistSettings();
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
    _demoSeeded = true;
    await _persistClips();
    await _persistSettings();
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

  /* ------------------------------ 备份与恢复 ------------------------------ */

  /// 打一个备份包（收藏 + 标签 + 图片），写到 backups/ 下并返回文件
  Future<File> createBackup() async {
    final now = DateTime.now();
    final images = <String, List<int>>{};
    for (final clip in _clips) {
      final name = clip.imageFileName;
      if (name == null || images.containsKey(name)) continue;
      final file = imageFile(name);
      if (!await file.exists()) continue;
      images[name] = await file.readAsBytes();
    }

    final entries = buildBackupEntries(clips: _clips, tags: _tags, images: images, now: now);
    final dir = Directory('$_dir/backups');
    await dir.create(recursive: true);
    final file = File('${dir.path}/${buildBackupFileName(now)}');
    await file.writeAsBytes(buildZipArchive(entries), flush: true);
    return file;
  }

  /// 读取并解析一个备份文件
  Future<BackupContent> readBackupFile(String path) async {
    final file = File(path);
    if (!await file.exists()) throw const BackupException('备份文件不存在');
    final length = await file.length();
    if (length > 200 * 1024 * 1024) {
      throw const BackupException('备份文件超过 200 MB，暂不支持导入');
    }
    final bytes = await file.readAsBytes();
    try {
      return parseBackup(unzipArchive(bytes));
    } on ZipFormatException catch (error) {
      throw BackupException('备份包无法解开：${error.message}');
    }
  }

  /// 应用备份。[replace] 为 true 时清空本地再写入，否则按 id 合并。
  /// 返回导入后的总条数。
  Future<int> applyBackup(BackupContent content, {required bool replace}) async {
    if (replace) {
      _clips.clear();
      _tags.clear();
      try {
        final dir = Directory('$_dir/images');
        if (await dir.exists()) {
          for (final entity in dir.listSync()) {
            if (entity is File) {
              try {
                await entity.delete();
              } catch (_) {}
            }
          }
        }
      } catch (_) {}
    }

    await Directory('$_dir/images').create(recursive: true);
    for (final entry in content.images.entries) {
      // 文件名来自外部包，落地前再挡一次路径跳转
      if (entry.key.isEmpty || entry.key.contains('/') || entry.key.contains('..')) continue;
      try {
        final target = File('$_dir/images/${entry.key}');
        await target.writeAsBytes(entry.value, flush: true);
      } catch (_) {}
    }

    final nextClips = replace ? [...content.clips] : mergeClips(_clips, content.clips);
    final nextTags = replace ? [...content.tags] : mergeTags(_tags, content.tags);
    nextClips.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    _clips
      ..clear()
      ..addAll(nextClips);
    _tags
      ..clear()
      ..addAll(nextTags);

    // 导入过真实数据，之后不该再自动种示例数据
    _demoSeeded = true;
    await _persistClips();
    await _persistTags();
    await _persistSettings();
    notifyListeners();
    return _clips.length;
  }
}

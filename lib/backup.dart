/// 备份包格式：一个 zip，内含
///   manifest.json   标识、schema 版本、导出时间与统计
///   clips.json      全部收藏
///   tags.json       全部标签
///   images/…        图片原文件（文件名与 clips 里的引用一致）
///
/// 这里只有纯函数（打包 / 解析 / 合并判定），文件读写放在 store 里，
/// 这样格式能直接在单测里验证，不用碰磁盘。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'models.dart';
import 'zip.dart';

const String backupAppId = 'com.stonemii.clippings';
const int backupSchema = 1;

const String backupManifestName = 'manifest.json';
const String backupClipsName = 'clips.json';
const String backupTagsName = 'tags.json';
const String backupImagesPrefix = 'images/';

class BackupException implements Exception {
  final String message;

  const BackupException(this.message);

  @override
  String toString() => message;
}

class BackupManifest {
  final int schema;
  final DateTime exportedAt;
  final int clipCount;
  final int tagCount;
  final int imageCount;

  const BackupManifest({
    required this.schema,
    required this.exportedAt,
    required this.clipCount,
    required this.tagCount,
    required this.imageCount,
  });
}

class BackupContent {
  final BackupManifest manifest;
  final List<Clip> clips;
  final List<AppTag> tags;
  final Map<String, Uint8List> images;

  const BackupContent({
    required this.manifest,
    required this.clips,
    required this.tags,
    required this.images,
  });

  int get clipCount => clips.length;

  int get tagCount => tags.length;

  int get imageCount => images.length;
}

/// 打包成 zip 条目（不含文件 I/O）
List<ZipEntry> buildBackupEntries({
  required List<Clip> clips,
  required List<AppTag> tags,
  required Map<String, List<int>> images,
  required DateTime now,
}) {
  final manifest = {
    'app': backupAppId,
    'schema': backupSchema,
    'exportedAt': now.toIso8601String(),
    'clips': clips.length,
    'tags': tags.length,
    'images': images.length,
  };

  final entries = <ZipEntry>[
    ZipEntry(backupManifestName, utf8.encode(jsonEncode(manifest)), modified: now),
    ZipEntry(
      backupClipsName,
      utf8.encode(jsonEncode(clips.map((clip) => clip.toJson()).toList())),
      modified: now,
    ),
    ZipEntry(
      backupTagsName,
      utf8.encode(jsonEncode(tags.map((tag) => tag.toJson()).toList())),
      modified: now,
    ),
  ];

  for (final entry in images.entries) {
    entries.add(ZipEntry('$backupImagesPrefix${entry.key}', entry.value, modified: now));
  }

  return entries;
}

/// 解析解包结果。任何不认识的结构都直接抛 [BackupException]，
/// 让界面能给出「这不是剪藏库的备份」这种明确反馈，而不是崩掉。
BackupContent parseBackup(List<UnzippedFile> files) {
  final byName = <String, UnzippedFile>{for (final file in files) file.name: file};

  final manifestFile = byName[backupManifestName];
  if (manifestFile == null) {
    throw const BackupException('这不是「剪藏库」的备份包（缺少 manifest.json）');
  }

  Map<String, dynamic> manifestJson;
  try {
    manifestJson = jsonDecode(utf8.decode(manifestFile.bytes)) as Map<String, dynamic>;
  } catch (_) {
    throw const BackupException('备份包描述文件损坏');
  }

  if (manifestJson['app'] != backupAppId) {
    throw const BackupException('这不是「剪藏库」的备份包');
  }

  final schema = (manifestJson['schema'] as num?)?.toInt() ?? 0;
  if (schema <= 0) throw const BackupException('备份包缺少版本信息');
  if (schema > backupSchema) {
    throw BackupException('备份包来自更新的版本（schema $schema），请先升级应用');
  }

  final clipsFile = byName[backupClipsName];
  if (clipsFile == null) throw const BackupException('备份包缺少收藏数据');

  List<Clip> clips;
  try {
    final raw = jsonDecode(utf8.decode(clipsFile.bytes)) as List<dynamic>;
    clips = raw.map((e) => Clip.fromJson(e as Map<String, dynamic>)).toList();
  } catch (_) {
    throw const BackupException('备份包里的收藏数据无法解析');
  }

  var tags = <AppTag>[];
  final tagsFile = byName[backupTagsName];
  if (tagsFile != null) {
    try {
      final raw = jsonDecode(utf8.decode(tagsFile.bytes)) as List<dynamic>;
      tags = raw.map((e) => AppTag.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      // 标签坏了不致命：收藏本身才是主体，后续会按内容重新聚合
      tags = <AppTag>[];
    }
  }

  final images = <String, Uint8List>{};
  for (final file in files) {
    if (!file.name.startsWith(backupImagesPrefix)) continue;
    final fileName = file.name.substring(backupImagesPrefix.length);
    if (fileName.isEmpty || fileName.contains('/')) continue;
    images[fileName] = file.bytes;
  }

  final exportedAt = DateTime.tryParse(manifestJson['exportedAt']?.toString() ?? '');

  return BackupContent(
    manifest: BackupManifest(
      schema: schema,
      exportedAt: exportedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      clipCount: (manifestJson['clips'] as num?)?.toInt() ?? clips.length,
      tagCount: (manifestJson['tags'] as num?)?.toInt() ?? tags.length,
      imageCount: (manifestJson['images'] as num?)?.toInt() ?? images.length,
    ),
    clips: clips,
    tags: tags,
    images: images,
  );
}

/// 本地是不是只有示例数据（或干脆没有）。
/// 这种情况直接覆盖导入即可，不必再问用户「要覆盖还是合并」。
bool onlySampleData(List<Clip> clips) => clips.every((clip) => clip.id.startsWith('seed-'));

/// 合并导入：按 id 去重，同一个 id 以备份里的为准（恢复场景下备份才是权威）
List<Clip> mergeClips(List<Clip> local, List<Clip> incoming) {
  final byId = <String, Clip>{for (final clip in local) clip.id: clip};
  for (final clip in incoming) {
    byId[clip.id] = clip;
  }
  return byId.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

/// 合并标签：保留本地已有的配色，只补进本地没有的
List<AppTag> mergeTags(List<AppTag> local, List<AppTag> incoming) {
  final byName = <String, AppTag>{for (final tag in local) tag.name: tag};
  for (final tag in incoming) {
    byName.putIfAbsent(tag.name, () => tag);
  }
  return byName.values.toList();
}

/// 备份包文件名：clippings-backup-YYYY-MM-DD.zip
String buildBackupFileName(DateTime now) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'clippings-backup-${now.year}-${two(now.month)}-${two(now.day)}.zip';
}

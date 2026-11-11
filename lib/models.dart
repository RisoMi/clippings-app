/// 数据模型：与设计说明一致的 Clip / Tag 结构。
/// 图片只存文件名（相对 `<filesDir>/images/`），保证数据可移植、可导出。
library;

enum ClipType { link, text, image }

extension ClipTypeX on ClipType {
  String get label => switch (this) {
        ClipType.link => '链接',
        ClipType.text => '文本',
        ClipType.image => '图片',
      };

  static ClipType fromName(String name) => switch (name) {
        'link' => ClipType.link,
        'image' => ClipType.image,
        _ => ClipType.text,
      };
}

class Clip {
  final String id;
  final ClipType type;
  final String title;
  final String summary;
  final String source;
  final String url;
  final String domain;
  final List<String> tags;
  final DateTime createdAt;
  final String? imageFileName;
  final int readCount;

  const Clip({
    required this.id,
    required this.type,
    required this.title,
    required this.summary,
    required this.source,
    required this.url,
    required this.domain,
    required this.tags,
    required this.createdAt,
    this.imageFileName,
    this.readCount = 0,
  });

  Clip copyWith({
    String? title,
    String? summary,
    List<String>? tags,
    int? readCount,
    String? imageFileName,
  }) {
    return Clip(
      id: id,
      type: type,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      source: source,
      url: url,
      domain: domain,
      tags: tags ?? this.tags,
      createdAt: createdAt,
      imageFileName: imageFileName ?? this.imageFileName,
      readCount: readCount ?? this.readCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'summary': summary,
        'source': source,
        'url': url,
        'domain': domain,
        'tags': tags,
        'createdAt': createdAt.toIso8601String(),
        'imageFileName': imageFileName,
        'readCount': readCount,
      };

  factory Clip.fromJson(Map<String, dynamic> json) {
    return Clip(
      id: json['id'] as String? ?? '',
      type: ClipTypeX.fromName(json['type'] as String? ?? 'text'),
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      source: json['source'] as String? ?? '',
      url: json['url'] as String? ?? '',
      domain: json['domain'] as String? ?? '',
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      imageFileName: json['imageFileName'] as String?,
      readCount: (json['readCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 标签：数量由 clips 实时聚合，这里只存名称与配色。
class AppTag {
  final String name;
  final int color;
  final int sort;

  const AppTag({required this.name, this.color = 0xFF2F6A54, this.sort = 0});

  Map<String, dynamic> toJson() => {'name': name, 'color': color, 'sort': sort};

  factory AppTag.fromJson(Map<String, dynamic> json) => AppTag(
        name: json['name'] as String? ?? '',
        color: (json['color'] as num?)?.toInt() ?? 0xFF2F6A54,
        sort: (json['sort'] as num?)?.toInt() ?? 0,
      );
}

/// 标签 + 使用数量（用于标签页）
class TagCount {
  final String name;
  final int count;
  final int color;

  const TagCount({required this.name, required this.count, required this.color});
}

/// 时间分组（今天 / 昨天 / 具体日期）
class ClipGroup {
  final String label;
  final List<Clip> items;

  const ClipGroup({required this.label, required this.items});
}

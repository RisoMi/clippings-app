/// 与 Android 原生的桥：取应用私有目录、拉取分享内容、把导出文件发出去。
/// 只用一个 MethodChannel，没有引入任何第三方插件。
library;

import 'package:flutter/services.dart';

class SharePayload {
  final String type; // link / text / image
  final String title;
  final String text;
  final String url;
  final String? imagePath; // 原生已复制到私有目录的图片路径

  const SharePayload({
    required this.type,
    this.title = '',
    this.text = '',
    this.url = '',
    this.imagePath,
  });

  factory SharePayload.fromMap(Map<dynamic, dynamic> map) => SharePayload(
        type: map['type']?.toString() ?? 'text',
        title: map['title']?.toString() ?? '',
        text: map['text']?.toString() ?? '',
        url: map['url']?.toString() ?? '',
        imagePath: map['imagePath']?.toString(),
      );
}

class Bridge {
  static const MethodChannel _channel = MethodChannel('com.stonemii.clippings/bridge');

  static String? _cachedDir;

  /// 应用私有目录（Android 为 filesDir）；失败时退回当前目录
  static Future<String> filesDir() async {
    if (_cachedDir != null) return _cachedDir!;
    try {
      final dir = await _channel.invokeMethod<String>('getFilesDir');
      _cachedDir = (dir == null || dir.isEmpty) ? '.' : dir;
    } on PlatformException {
      _cachedDir = '.';
    } on MissingPluginException {
      _cachedDir = '.';
    }
    return _cachedDir!;
  }

  /// 拉取一次待处理的分享（APP 被分享唤起时原生会暂存）
  static Future<SharePayload?> takePendingShare() async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('takePendingShare');
      if (map == null || map.isEmpty) return null;
      return SharePayload.fromMap(map);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// 用系统分享把导出的文件发出去
  static Future<bool> shareFile(String path, String mime, {String? title}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('shareFile', {
        'path': path,
        'mime': mime,
        'title': title,
      });
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

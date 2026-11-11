import 'dart:io';

import 'package:clippings/bridge.dart';
import 'package:clippings/models.dart';
import 'package:clippings/store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 存储层行为测试：重点是「清空数据后重启不该自动补示例数据」这个 bug。
/// 用临时目录 + mock 掉原生取目录的通道，跑真实的读写流程。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.stonemii.clippings/bridge');
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('clippings_store_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'getFilesDir' ? tempDir.path : null,
    );
    Bridge.resetCacheForTest();
    ClipStore.instance.resetForTest();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('首次启动会写入示例数据，并把 demoSeeded 标记落盘', () async {
    final store = ClipStore.instance;
    await store.init();

    expect(store.clips.length, 4);
    final settings = File('${tempDir.path}/settings.json');
    expect(await settings.exists(), isTrue);
    expect(await settings.readAsString(), contains('"demoSeeded":true'));
  });

  test('清空后重启，示例数据不会再被补回来', () async {
    final store = ClipStore.instance;
    await store.init();
    expect(store.clips.length, 4);

    await store.clearAll();
    expect(store.clips, isEmpty);

    // 模拟杀掉应用再打开：内存状态清零，重新走一遍 init
    store.resetForTest();
    Bridge.resetCacheForTest();
    await store.init();

    expect(store.clips, isEmpty, reason: '清空是用户的明确意图，重启后不该自动补数据');
  });

  test('旧版本的设置文件（没有 demoSeeded 字段）升级后不会补示例数据', () async {
    // 模拟 1.1.1 之前留下的 settings.json：有设置、无 demoSeeded
    File('${tempDir.path}/settings.json').writeAsStringSync(
      '{"themeMode":"dark","exportFormat":"md","exportGroup":true,"exportImages":true}',
    );

    final store = ClipStore.instance;
    await store.init();

    expect(store.clips, isEmpty, reason: '老用户升级上来不该被塞示例数据');
  });

  test('清空后手动新增的内容，重启仍然在', () async {
    final store = ClipStore.instance;
    await store.init();
    await store.clearAll();

    await store.addClip(
      Clip(
        id: 'manual-1',
        type: ClipType.text,
        title: '手写的一条',
        summary: '正文',
        source: '手动',
        url: '',
        domain: '',
        tags: const [],
        createdAt: DateTime(2026, 11, 11, 12),
      ),
    );

    store.resetForTest();
    Bridge.resetCacheForTest();
    await store.init();

    expect(store.clips.length, 1);
    expect(store.clips.first.title, '手写的一条');
  });
}

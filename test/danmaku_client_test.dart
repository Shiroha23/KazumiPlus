import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'package:kazumi/pages/player/danmaku_source_sheet.dart';
import 'package:kazumi/request/clients/danmaku_client.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/dandan_credentials.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPaths;
  late _Adapter adapter;

  setUpAll(() async {
    Logger.level = Level.off;
    directory = await Directory.systemTemp.createTemp('kazumi_danmaku_test_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
    await GStorage.putSetting(SettingsKeys.privateMode, true);
  });

  setUp(() {
    DioFactory.reset();
    adapter = _Adapter();
    DioFactory.apiDio.httpClientAdapter.close();
    DioFactory.apiDio.httpClientAdapter = adapter;
  });

  tearDownAll(() async {
    DioFactory.reset();
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    expect(
      directory.absolute.path.startsWith(Directory.systemTemp.absolute.path),
      isTrue,
    );
    expect(
      directory.uri.pathSegments.where((part) => part.isNotEmpty).last,
      startsWith('kazumi_danmaku_test_'),
    );
    await directory.delete(recursive: true);
  });

  test('missing credentials fail before sending an unsigned request', () async {
    await expectLater(
      DanmakuClient.instance.get('https://api.dandanplay.net/api/v2/bangumi/1'),
      throwsA(
        isA<NetworkException>().having(
          (error) => error.message,
          'message',
          '当前构建未配置弹幕服务凭据',
        ),
      ),
    );
    expect(adapter.requests, isEmpty);
  }, skip: hasDandanCredentials);

  test('configured builds sign the path without query parameters', () async {
    await DanmakuClient.instance.get(
      'https://api.dandanplay.net/api/v2/search/episodes',
      queryParameters: {'anime': '葬送的芙莉莲', 'v2': 'true'},
    );
    final request = adapter.requests.single;
    final timestamp = request.headers['X-Timestamp'];
    final expected = base64Encode(
      sha256
          .convert(
            utf8.encode(
              '${dandanCredentials['id']}$timestamp/api/v2/search/episodes${dandanCredentials['value']}',
            ),
          )
          .bytes,
    );
    expect(request.headers['X-Signature'], expected);
    expect(request.headers['X-AppId'], dandanCredentials['id']);
    expect(request.uri.queryParameters['anime'], '葬送的芙莉莲');
  }, skip: !hasDandanCredentials);

  for (final status in [401, 403]) {
    test('HTTP $status preserves an actionable access error', () async {
      adapter.status = status;
      await expectLater(
        DanmakuClient.instance.get(
          'https://api.dandanplay.net/api/v2/bangumi/1',
        ),
        throwsA(
          isA<NetworkException>()
              .having((error) => error.statusCode, 'statusCode', status)
              .having((error) => error.message, 'message', contains('应用凭据')),
        ),
      );
    }, skip: !hasDandanCredentials);
  }

  test('automatic loading carries the cause to the playback result', () async {
    adapter.status = 403;
    final controller = _controller();
    controller.beginDanmakuLoad();
    final result = await controller.fetchDanmaku(1, 'test', 1);
    expect(result.isFailed, isTrue);
    expect(result.errorMessage, _expectedError);
    controller.applyUnavailableDanmakuLoad(result);
    expect(controller.danmakuLoading, isFalse);
    expect(controller.danmakuOn, isFalse);
  });

  testWidgets('manual search displays the credential or access failure', (
    tester,
  ) async {
    adapter.status = 403;
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [KazumiDialog.observer],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDanmakuSourceSheet(
                context,
                bangumiId: 1,
                initialKeyword: '葬送的芙莉莲',
                danmakuController: _controller(),
                onBeforeApply: () {},
              ),
              child: const Text('选择弹幕源'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('选择弹幕源'));
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text(_expectedError), findsOneWidget);
    expect(find.text('未找到番剧'), findsNothing);
    expect(find.text('搜索失败'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

String get _expectedError =>
    hasDandanCredentials ? '弹幕服务拒绝访问（HTTP 403），请检查应用凭据或访问限制' : '当前构建未配置弹幕服务凭据';

PlayerDanmakuController _controller() => PlayerDanmakuController(
  isLocalPlayback: () => false,
  downloadController: _UnusedDownloads(),
);

class _UnusedDownloads implements DownloadController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int status = 200;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '{}',
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

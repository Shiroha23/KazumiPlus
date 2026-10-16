import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/pages/search/search_controller.dart';
import 'package:kazumi/pages/search/search_page.dart';
import 'package:kazumi/repositories/collect_repository.dart';
import 'package:kazumi/repositories/search_history_repository.dart';
import 'package:kazumi/request/clients/bangumi_client.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/bangumi_mirror_credentials.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPaths;
  late _SearchAdapter adapter;

  setUpAll(() async {
    Logger.level = Level.off;
    directory = await Directory.systemTemp.createTemp('kazumi_search_test_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
    await GStorage.putSetting(SettingsKeys.privateMode, true);
  });

  setUp(() async {
    await GStorage.putSetting(SettingsKeys.bangumiAcceleration, 'mirror');
    DioFactory.reset();
    adapter = _SearchAdapter();
    DioFactory.bangumiDio.httpClientAdapter.close();
    DioFactory.bangumiDio.httpClientAdapter = adapter;
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
      startsWith('kazumi_search_test_'),
    );
    await directory.delete(recursive: true);
  });

  for (final mode in ['direct', 'ech', 'mirror']) {
    test('search routes correctly in $mode mode for this build', () async {
      await GStorage.putSetting(SettingsKeys.bangumiAcceleration, mode);
      await BangumiClient.instance.post(
        'https://api.bgm.tv/v0/search/subjects?limit=20&offset=40',
        data: {'keyword': '葬送的芙莉莲'},
      );
      final request = adapter.requests.single;
      final signedMirror = mode == 'mirror' && hasBangumiMirrorCredentials;
      expect(request.uri.host, signedMirror ? 'api.kazumi.fyi' : 'api.bgm.tv');
      expect(request.uri.queryParameters, {'limit': '20', 'offset': '40'});
      expect(
        request.extra['bangumiEch'] == true,
        mode == 'ech' || (mode == 'mirror' && !signedMirror),
      );
      expect(request.headers.containsKey('X-Signature'), signedMirror);
      expect(request.data, {'keyword': '葬送的芙莉莲'});
    });
  }

  test('unsigned public mirror requests still use the mirror', () async {
    await BangumiClient.instance.get('https://api.bgm.tv/v0/subjects/1');
    expect(adapter.requests.single.uri.host, 'api.kazumi.fyi');
    expect(adapter.requests.single.headers, isNot(contains('X-Signature')));
  });

  test('comments use the same credential-aware routing as search', () async {
    await BangumiClient.instance.get(
      'https://next.bgm.tv/p1/subjects/1/comments?limit=20&offset=0',
    );
    expect(
      adapter.requests.single.uri.host,
      hasBangumiMirrorCredentials ? 'api.kazumi.fyi' : 'next.bgm.tv',
    );
    expect(
      adapter.requests.single.extra['bangumiEch'] == true,
      !hasBangumiMirrorCredentials,
    );
  });

  testWidgets('a failed search offers retry instead of reporting no matches', (
    tester,
  ) async {
    final controller = _controller();
    adapter.respond = (_) async => _json({}, status: 401);
    await tester.pumpWidget(
      MaterialApp(home: SearchPage(controller: controller)),
    );
    await tester.enterText(find.byType(TextField), '葬送的芙莉莲');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('没有找到番剧'), findsNothing);
    expect(find.text('暂时无法加载番剧'), findsOneWidget);
    expect(controller.isLoading, isFalse);
    expect(controller.isTimeOut, isTrue);

    adapter.respond = (_) async => _json({
      'data': [_item(1)],
    });
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法加载番剧'), findsNothing);
    expect(controller.bangumiList.single.id, 1);
    expect(controller.isTimeOut, isFalse);
    expect(find.text('番剧 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a successful empty response reports no matches', (tester) async {
    final controller = _controller();
    await tester.pumpWidget(
      MaterialApp(home: SearchPage(controller: controller)),
    );
    await tester.enterText(find.byType(TextField), '没有这个番剧');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(find.text('没有找到番剧'), findsOneWidget);
    expect(find.text('暂时无法加载番剧'), findsNothing);
    expect(controller.isTimeOut, isFalse);
    expect(controller.hasMoreSearchResults, isFalse);
    expect(tester.takeException(), isNull);
  });

  test(
    'failed pagination retains results and retries the same offset',
    () async {
      final controller = _controller();
      adapter.respond = (_) async =>
          _json({'data': List.generate(20, (index) => _item(index + 1))});
      await controller.searchBangumi('番剧', type: 'init');
      adapter.respond = (_) async => _json({}, status: 503);
      await controller.searchBangumi('番剧');
      expect(controller.bangumiList, hasLength(20));
      expect(controller.isTimeOut, isTrue);
      expect(controller.isLoading, isFalse);
      adapter.respond = (_) async => _json({
        'data': [_item(21)],
      });
      await controller.searchBangumi('番剧');
      expect(adapter.requests.last.uri.queryParameters['offset'], '20');
      expect(controller.bangumiList, hasLength(21));
      expect(controller.isTimeOut, isFalse);
    },
  );
}

SearchPageController _controller() =>
    SearchPageController(CollectRepository(), SearchHistoryRepository());

Map<String, dynamic> _item(int id) => {
  'id': id,
  'name': 'Anime $id',
  'name_cn': '番剧 $id',
  'images': <String, dynamic>{},
  'rating': <String, dynamic>{},
};

ResponseBody _json(Object data, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(data),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

class _SearchAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Future<ResponseBody> Function(RequestOptions) respond = (_) async =>
      _json({'data': []});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

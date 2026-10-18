import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/pages/category/category_controller.dart';
import 'package:kazumi/pages/category/category_page.dart';
import 'package:kazumi/pages/search/search_controller.dart';
import 'package:kazumi/pages/search/search_page.dart';
import 'package:kazumi/repositories/collect_repository.dart';
import 'package:kazumi/repositories/search_history_repository.dart';
import 'package:kazumi/request/clients/bangumi_client.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/bangumi_mirror_credentials.dart';
import 'package:kazumi/utils/search_parser.dart';
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

  testWidgets(
    'category loads all API pages before showing the end of results',
    (tester) async {
      final controller = CategoryController();
      addTearDown(controller.dispose);
      adapter.respond = (request) async {
        final offset = int.parse(request.uri.queryParameters['offset']!);
        final count = offset < 40 ? 20 : 5;
        final items = List.generate(
          count,
          (index) => _item(offset + index + 1),
        );
        // Parsing removes this entry; pagination must still advance by 20.
        if (offset == 0) {
          items.first['name_cn'] = '';
          items.first['name'] = '';
        }
        return _json({
          'data': items,
          'total': 45,
          'limit': 20,
          'offset': offset,
        });
      };
      unawaited(controller.setFilters(const SearchFilterState(sort: 'score')));
      await tester.pumpWidget(
        MaterialApp(home: CategoryPage(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(controller.items, hasLength(19));
      expect(controller.hasMore, isTrue);
      expect(find.text('已经看到全部结果'), findsNothing);
      unawaited(controller.load());
      await tester.pumpAndSettle();
      expect(controller.items, hasLength(39));
      expect(controller.hasMore, isTrue);
      expect(find.text('已经看到全部结果'), findsNothing);
      unawaited(controller.load());
      await tester.pumpAndSettle();
      expect(controller.items, hasLength(44));
      expect(controller.hasMore, isFalse);
      await tester.scrollUntilVisible(
        find.text('已经看到全部结果'),
        500,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('已经看到全部结果'), findsOneWidget);
      expect(adapter.requests.map((r) => r.uri.queryParameters['offset']), [
        '0',
        '20',
        '40',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in ['direct', 'ech', 'mirror']) {
    test('native category routes to the official API in $mode mode', () async {
      await GStorage.putSetting(SettingsKeys.bangumiAcceleration, mode);
      adapter.respond = (request) async {
        expect(request.method, 'GET');
        expect(request.uri.host, 'next.bgm.tv');
        expect(request.uri.path, '/p1/subjects');
        expect(request.uri.queryParameters['sort'], 'trends');
        expect(request.extra['bangumiEch'] == true, mode != 'direct');
        return _json({
          'data': [_item(8), _item(2), _item(6)],
          'total': 1,
        });
      };
      final controller = CategoryController();
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.items.map((item) => item.id), [8, 2, 6]);
      expect(controller.hasMore, isFalse);
      expect(controller.hasError, isFalse);
    });

    test(
      'other browse also bypasses the unsupported mirror in $mode mode',
      () async {
        await GStorage.putSetting(SettingsKeys.bangumiAcceleration, mode);
        adapter.respond = (request) async {
          expect(request.method, 'GET');
          expect(request.extra['bangumiEch'] == true, mode != 'direct');
          if (request.uri.path == '/p1/trending/subjects') {
            expect(request.uri.host, 'next.bgm.tv');
            return _json({
              'data': [
                {'subject': _item(1)},
              ],
              'total': 1,
            });
          }
          expect(request.uri.host, 'api.bgm.tv');
          expect(request.uri.path, '/v0/subjects');
          expect(request.uri.queryParameters['cat'], '0');
          expect(request.extra['bangumiEch'] == true, mode != 'direct');
          return _json({
            'data': [_item(1)],
            'total': 1,
          });
        };
        final controller = CategoryController();
        addTearDown(controller.dispose);
        await controller.setFilters(
          const SearchFilterState(metaTags: ['其他'], sort: 'score'),
        );
        expect(controller.items.single.id, 1);
        expect(controller.hasError, isFalse);
        await controller.setFilters(const SearchFilterState(metaTags: ['其他']));
        expect(controller.items.single.id, 1);
        expect(controller.hasError, isFalse);
        expect(adapter.requests, hasLength(2));
      },
    );
  }

  for (final sort in ['heat', 'rank', 'score']) {
    const formats = {'TV': 1, '剧场版': 3, 'OVA': 2, 'WEB': 5, '动态漫画': 2006};
    for (final format in formats.entries) {
      test(
        'category queries real ${format.key} parameters with $sort sorting',
        () async {
          await GStorage.putSetting(SettingsKeys.bangumiAcceleration, 'direct');
          adapter.respond = (request) async {
            if (sort == 'score') {
              expect(request.method, 'POST');
              expect(request.uri.path, '/v0/search/subjects');
              final params = request.data as Map<String, dynamic>;
              expect(params['sort'], 'score');
              expect(params['filter']['meta_tags'], [format.key]);
            } else {
              expect(request.method, 'GET');
              expect(request.uri.path, '/p1/subjects');
              expect(
                request.uri.queryParameters['cat'],
                format.value.toString(),
              );
              expect(
                request.uri.queryParameters['sort'],
                sort == 'heat' ? 'trends' : 'rank',
              );
              expect(request.uri.queryParameters['page'], '1');
            }
            return _json({
              'data': [_item(format.value)],
              'total': 1,
            });
          };
          final controller = CategoryController();
          addTearDown(controller.dispose);
          await controller.setFilters(
            SearchFilterState(sort: sort, metaTags: [format.key]),
          );
          expect(controller.items.single.id, format.value);
          expect(controller.hasError, isFalse);
          expect(controller.hasMore, isFalse);
          expect(adapter.requests, hasLength(1));
        },
      );
    }
  }

  for (final sort in ['heat', 'rank', 'score']) {
    test(
      'category forwards genre and full calendar year with $sort sorting',
      () async {
        await GStorage.putSetting(SettingsKeys.bangumiAcceleration, 'direct');
        adapter.respond = (request) async {
          if (sort == 'score') {
            final filter = (request.data as Map<String, dynamic>)['filter'];
            expect(filter['tag'], ['日常', '原创']);
            expect(filter['meta_tags'], ['剧场版']);
            expect(filter['air_date'], ['>=2025-01-01', '<2026-01-01']);
          } else {
            expect(request.uri.queryParameters['cat'], '3');
            expect(request.uri.queryParameters['year'], '2025');
            expect(request.uri.queryParameters['tagsCat'], 'subject');
            expect(request.uri.queryParametersAll['tags'], ['日常', '原创']);
          }
          return _json({
            'data': [_item(1)],
            'total': 1,
          });
        };
        final controller = CategoryController();
        addTearDown(controller.dispose);
        await controller.setFilters(
          SearchFilterState(
            tags: ['日常', '原创'],
            metaTags: ['剧场版'],
            sort: sort,
            dateRange: const SearchDateRange(
              start: '2025-01-01',
              end: '2026-01-01',
            ),
          ),
        );
        expect(controller.items.single.id, 1);
        expect(controller.hasError, isFalse);
        expect(adapter.requests, hasLength(1));
      },
    );
  }

  test(
    'native pagination uses total pages and advances past short or malformed pages',
    () async {
      await GStorage.putSetting(SettingsKeys.bangumiAcceleration, 'direct');
      adapter.respond = (request) async {
        final page = int.parse(request.uri.queryParameters['page']!);
        final items = List.generate(
          page == 1 ? 23 : 24,
          (i) => _item((page - 1) * 24 + i + 1),
        );
        if (page == 1) {
          items.first['name'] = '';
          items.first['name_cn'] = '';
        }
        return _json({'data': items, 'total': 2});
      };
      final controller = CategoryController();
      addTearDown(controller.dispose);
      await controller.setFilters(const SearchFilterState(metaTags: ['剧场版']));
      expect(controller.items, hasLength(22));
      expect(controller.hasMore, isTrue);
      await controller.load();
      expect(controller.items, hasLength(46));
      expect(controller.items.last.id, 48);
      expect(controller.hasMore, isFalse);
      await controller.load();
      expect(adapter.requests.map((r) => r.uri.queryParameters['page']), [
        '1',
        '2',
      ]);
    },
  );

  test(
    'native pagination failures retain data and retry the same page',
    () async {
      await GStorage.putSetting(SettingsKeys.bangumiAcceleration, 'direct');
      var fail = true;
      adapter.respond = (request) async {
        final page = int.parse(request.uri.queryParameters['page']!);
        return page == 2 && fail
            ? _json({}, status: 503)
            : _json({
                'data': [_item(page)],
                'total': 2,
              });
      };
      final controller = CategoryController();
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.load();
      expect(controller.items.single.id, 1);
      expect(controller.hasError, isTrue);
      fail = false;
      await controller.load();
      expect(controller.items.map((item) => item.id), [1, 2]);
      expect(controller.hasError, isFalse);
      expect(controller.hasMore, isFalse);
      expect(adapter.requests.map((r) => r.uri.queryParameters['page']), [
        '1',
        '2',
        '2',
      ]);
    },
  );

  test(
    'other catalog pages scores globally and keeps real recent popularity order',
    () async {
      await GStorage.putSetting(SettingsKeys.bangumiAcceleration, 'direct');
      adapter.respond = (request) async {
        final offset = int.parse(request.uri.queryParameters['offset']!);
        if (request.uri.path == '/p1/trending/subjects') {
          return _json({
            'data': [
              if (offset == 0)
                for (var i = 0; i < 100; i++) {'subject': _item(1000 + i)}
              else
                for (final id in [3, 24]) {'subject': _item(id)},
            ],
            'total': 102,
          });
        }
        expect(request.uri.path, '/v0/subjects');
        expect(request.uri.queryParameters['cat'], '0');
        return _json({
          'data': [
            for (var i = 1; i <= (offset == 0 ? 20 : 5); i++)
              {
                ..._item(offset + i),
                'date': offset + i == 2 ? '2024-01-01' : '2025-01-01',
                'tags': [
                  {'name': '日常'},
                ],
                'nsfw': offset + i == 25,
                'rating': {
                  'score': (offset + i) / 3,
                  'rank': offset + i == 24 ? 0 : 26 - offset - i,
                },
              },
          ],
          'total': 25,
          'limit': 20,
        });
      };
      final controller = CategoryController();
      addTearDown(controller.dispose);
      await controller.setFilters(
        const SearchFilterState(metaTags: ['其他'], sort: 'score'),
      );
      expect(
        controller.items.map((item) => item.id),
        List.generate(20, (i) => 24 - i),
      );
      expect(controller.hasMore, isTrue);
      await controller.load();
      expect(
        controller.items.map((item) => item.id),
        List.generate(24, (i) => 24 - i),
      );
      expect(controller.hasMore, isFalse);
      await controller.setFilters(
        const SearchFilterState(
          metaTags: ['其他'],
          tags: ['日常'],
          sort: 'rank',
          dateRange: SearchDateRange(start: '2025-01-01', end: '2026-01-01'),
        ),
      );
      expect(controller.items.first.id, 23);
      await controller.load();
      expect(controller.items, hasLength(22));
      expect(
        controller.items.any((item) => item.rank == 0 || item.id == 2),
        isFalse,
      );
      await controller.setFilters(const SearchFilterState(metaTags: ['其他']));
      expect(controller.items.map((item) => item.id), [3, 24]);
      expect(controller.hasMore, isFalse);
      expect(
        adapter.requests
            .where((r) => r.uri.path == '/v0/subjects')
            .map((r) => r.uri.queryParameters['offset']),
        ['0', '20'],
      );
      expect(
        adapter.requests
            .where((r) => r.uri.path == '/p1/trending/subjects')
            .map((r) => r.uri.queryParameters['offset']),
        ['0', '100'],
      );
    },
  );

  test(
    'failed other catalog requests retry without caching partial results',
    () async {
      await GStorage.putSetting(SettingsKeys.bangumiAcceleration, 'direct');
      var fail = true;
      adapter.respond = (_) async => fail
          ? _json({}, status: 503)
          : _json({
              'data': [_item(1)],
              'total': 1,
            });
      final controller = CategoryController();
      addTearDown(controller.dispose);
      await controller.setFilters(
        const SearchFilterState(metaTags: ['其他'], sort: 'score'),
      );
      expect(controller.hasError, isTrue);
      fail = false;
      await controller.load();
      expect(controller.hasError, isFalse);
      expect(controller.items.single.id, 1);
      expect(adapter.requests, hasLength(2));
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

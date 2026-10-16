import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/player/default_plugin_playback.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;

void main() {
  late _PlaybackPlugin plugin;
  late BangumiItem item;

  setUp(() {
    plugin = _PlaybackPlugin();
    item = BangumiItem(
      id: 1,
      type: 2,
      name: 'Original title',
      nameCn: '番剧名称',
      summary: '',
      airDate: '',
      airWeekday: 0,
      rank: 0,
      images: {},
      tags: [],
      alias: ['别名'],
      ratingScore: 0,
      votes: 0,
      votesCount: [],
      info: '',
    );
  });

  test(
    'resolves the exact title to player arguments without a source selection',
    () async {
      plugin.results = [
        SearchItem(name: '番剧名称 第二季', src: '/other'),
        SearchItem(name: '番剧名称', src: '/match'),
      ];
      final token = RuleCancelToken();
      final args = await resolveDefaultPluginPlayback(
        plugin: plugin,
        bangumiItem: item,
        cancelToken: token,
      );

      expect(plugin.keyword, '番剧名称');
      expect(plugin.source, '/match');
      expect(plugin.searchToken, same(token));
      expect(plugin.chapterToken, same(token));
      expect(args.bangumiItem, same(item));
      expect(args.plugin, same(plugin));
      expect(args.title, '番剧名称');
      expect(args.src, '/match');
      expect(args.roads, same(plugin.roads));
    },
  );

  test(
    'uses original title when there is no Chinese title and plays first result',
    () async {
      item.nameCn = '';
      plugin.results = [
        SearchItem(name: 'Site title', src: '/first'),
        SearchItem(name: 'Another site title', src: '/second'),
      ];

      final args = await resolveDefaultPluginPlayback(
        plugin: plugin,
        bangumiItem: item,
      );
      expect(plugin.keyword, 'Original title');
      expect(args.src, '/first');
    },
  );

  test('matches aliases ahead of unrelated search results', () async {
    plugin.results = [
      SearchItem(name: 'Other title', src: '/other'),
      SearchItem(name: '别名', src: '/alias'),
    ];
    final args = await resolveDefaultPluginPlayback(
      plugin: plugin,
      bangumiItem: item,
    );
    expect(args.src, '/alias');
  });

  test(
    'empty search result returns an error for manual source fallback',
    () async {
      plugin.results = [];
      await expectLater(
        resolveDefaultPluginPlayback(plugin: plugin, bangumiItem: item),
        throwsA(isA<NoResultException>()),
      );
      expect(plugin.source, isNull);
    },
  );

  test('empty playlist returns an error for manual source fallback', () async {
    plugin.roads = [];
    await expectLater(
      resolveDefaultPluginPlayback(plugin: plugin, bangumiItem: item),
      throwsA(isA<ChapterErrorException>()),
    );
  });

  test('captcha propagates to the caller for manual verification', () async {
    plugin.searchError = const CaptchaRequiredException('default');
    await expectLater(
      resolveDefaultPluginPlayback(plugin: plugin, bangumiItem: item),
      throwsA(isA<CaptchaRequiredException>()),
    );
    expect(plugin.source, isNull);
  });

  test('cancelling search prevents a subsequent playlist request', () async {
    final token = RuleCancelToken();
    plugin.cancelAfterSearch = true;
    await expectLater(
      resolveDefaultPluginPlayback(
        plugin: plugin,
        bangumiItem: item,
        cancelToken: token,
      ),
      throwsA(same(token.cancelError)),
    );
    expect(token.isCancelled, isTrue);
    expect(plugin.source, isNull);
  });
}

class _PlaybackPlugin implements Plugin {
  @override
  String get name => 'default';

  List<SearchItem> results = [SearchItem(name: '番剧名称', src: '/match')];
  List<Road> roads = [
    Road(name: '线路 1', data: ['/episode/1'], identifier: ['1']),
  ];
  String? keyword;
  String? source;
  RuleCancelToken? searchToken;
  RuleCancelToken? chapterToken;
  Object? searchError;
  bool cancelAfterSearch = false;

  @override
  Future<PluginSearchResponse> queryBangumi(
    String keyword, {
    bool shouldRethrow = false,
    RuleCancelToken? cancelToken,
  }) async {
    this.keyword = keyword;
    searchToken = cancelToken;
    expect(shouldRethrow, isTrue);
    if (searchError != null) throw searchError!;
    if (cancelAfterSearch) cancelToken!.cancel();
    return PluginSearchResponse(pluginName: name, data: results);
  }

  @override
  Future<List<Road>> queryChapterRoads(
    String source, {
    RuleCancelToken? cancelToken,
  }) async {
    this.source = source;
    chapterToken = cancelToken;
    return roads;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

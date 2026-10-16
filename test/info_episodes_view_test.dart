import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/pages/info/info_episodes_view.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/repositories/download_repository.dart';
import 'package:kazumi/services/download/download_manager.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:logger/logger.dart';

void main() {
  late BangumiItem item;
  late _Plugin plugin;

  setUp(() {
    Logger.level = Level.off;
    plugin = _Plugin();
    item = BangumiItem(
      id: 1,
      type: 2,
      name: 'Anime',
      nameCn: '',
      summary: '',
      airDate: '',
      airWeekday: 0,
      rank: 0,
      images: {},
      tags: [],
      alias: [],
      ratingScore: 0,
      votes: 0,
      votesCount: [],
      info: '',
    );
  });

  OnlineVideoPlaybackArgs args({int? episode, int road = 0}) =>
      OnlineVideoPlaybackArgs(
        bangumiItem: item,
        plugin: plugin,
        title: 'Anime',
        src: '/anime',
        roads: plugin.roads,
        initialEpisode: episode,
        initialRoad: road,
      );

  Widget view({
    bool active = true,
    double textScale = 1,
    Plugin? defaultPlugin,
    Future<OnlineVideoPlaybackArgs?> Function()? choose,
    ValueChanged<OnlineVideoPlaybackArgs>? play,
  }) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: InfoEpisodesView(
        bangumiItem: item,
        defaultPlugin: defaultPlugin,
        isActive: active,
        onChooseSource: choose ?? () async => null,
        onPlay: play ?? (_) {},
      ),
    ),
  );

  testWidgets('loads the default source only when the episodes tab is active', (
    tester,
  ) async {
    plugin.roads.first.data.addAll([
      for (var episode = 3; episode <= 100; episode++) '/$episode',
    ]);
    plugin.roads.first.identifier.addAll([
      for (var episode = 3; episode <= 100; episode++) 'EP $episode',
    ]);
    await tester.pumpWidget(view(active: false, defaultPlugin: plugin));
    await tester.pumpAndSettle();
    expect(plugin.searches, 0);
    await tester.pumpWidget(view(defaultPlugin: plugin));
    await tester.pumpAndSettle();
    expect(plugin.searches, 1);
    expect(find.text('EP 2'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'EP 2'), findsOneWidget);
    expect(find.byTooltip('缓存剧集'), findsNothing);
    expect(find.text('Anime'), findsNothing);
    final countY = tester.getCenter(find.text('全部剧集 · 100 集')).dy;
    expect(find.text('播放线路'), findsNothing);
    expect(tester.getCenter(find.text('Line 1')).dy, closeTo(countY, 2));
    expect(tester.getCenter(find.text('Line 1')).dx,
        greaterThan(tester.getTopRight(find.text('全部剧集 · 100 集')).dx));
    expect(tester.getCenter(find.text('来源：default')).dy, closeTo(countY, 2));
    expect(tester.getCenter(find.text('换源')).dy, closeTo(countY, 2));
    expect(tester.getCenter(find.text('来源：default')).dx,
        greaterThan(tester.getCenter(find.text('Line 1')).dx));
    final count = find.text('全部剧集 · 100 集');
    final episodesScroll = find.byKey(const PageStorageKey('episode-buttons:0'));
    await tester.drag(episodesScroll, const Offset(0, -350));
    await tester.pumpAndSettle();
    final countPosition = tester.getTopLeft(count);
    await tester.drag(episodesScroll, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(count), countPosition);
    expect(
      tester.widgetList<ColoredBox>(
        find.ancestor(of: count, matching: find.byType(ColoredBox)),
      ).every((box) => box.color.a == 0),
      isTrue,
    );
    await tester.pumpWidget(view(active: false, defaultPlugin: plugin));
    await tester.pumpWidget(view(defaultPlugin: plugin));
    await tester.pumpAndSettle();
    expect(plugin.searches, 1);
  });

  for (final layout in [(width: 320.0, scale: 1.0), (width: 360.0, scale: 2.0)]) {
    testWidgets('header fits ${layout.width} width at ${layout.scale} text scale',
        (tester) async {
      tester.view.physicalSize = Size(layout.width, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(view(defaultPlugin: plugin, textScale: layout.scale));
      await tester.pumpAndSettle();
      final count = find.text('全部剧集 · 2 集');
      expect(find.ancestor(of: count,
          matching: find.byType(SingleChildScrollView)), findsNothing);
      expect(tester.getTopRight(find.widgetWithText(TextButton, '换源')).dx,
          lessThanOrEqualTo(layout.width));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'manual source selection shows episodes before starting playback',
    (tester) async {
      OnlineVideoPlaybackArgs? played;
      await tester.pumpWidget(
        view(choose: () async => args(), play: (value) => played = value),
      );
      await tester.pumpAndSettle();
      expect(find.text('选择播放来源以查看剧集'), findsOneWidget);
      await tester.tap(find.text('选择来源'));
      await tester.pumpAndSettle();
      expect(played, isNull);
      await tester.tap(find.text('EP 2'));
      await tester.pumpAndSettle();
      expect(played!.initialEpisode, 2);
      expect(played!.initialRoad, 0);
      expect(played!.src, '/anime');
    },
  );

  testWidgets(
    'switching lines preserves the selected line and episode in playback',
    (tester) async {
      OnlineVideoPlaybackArgs? played;
      await tester.pumpWidget(
        view(defaultPlugin: plugin, play: (value) => played = value),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Line 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('road-option-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alternative 2'));
      await tester.pumpAndSettle();
      expect(played!.initialRoad, 1);
      expect(played!.initialEpisode, 2);
      expect(played!.roads[1].data[1], '/line2/2');
    },
  );

  testWidgets('failed default source can be retried', (tester) async {
    plugin.error = const SearchErrorException('default');
    await tester.pumpWidget(view(defaultPlugin: plugin));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法加载剧集'), findsOneWidget);
    plugin.error = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(plugin.searches, 2);
    expect(find.text('EP 2'), findsOneWidget);
  });

  testWidgets('disposing cancels pending episode loading', (tester) async {
    plugin.gate = Completer<void>();
    await tester.pumpWidget(view(defaultPlugin: plugin));
    await tester.pump();
    expect(find.text('正在加载剧集'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(plugin.token!.isCancelled, isTrue);
    plugin.gate!.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('episodes remain accessible below the collapsing details header',
      (tester) async {
    OnlineVideoPlaybackArgs? played;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: const SliverAppBar(
                title: Text('Anime details'),
                expandedHeight: 240,
                pinned: true,
              ),
            ),
          ],
          body: InfoEpisodesView(
            bangumiItem: item,
            defaultPlugin: plugin,
            isActive: true,
            onChooseSource: () async => null,
            onPlay: (args) => played = args,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('EP 2'));
    await tester.tap(find.text('EP 2'));
    await tester.pumpAndSettle();
    expect(played?.initialEpisode, 2);
    expect(tester.takeException(), isNull);
  });

  for (final wheel in [false, true]) {
    testWidgets('${wheel ? 'wheel' : 'drag'} respects header and episode scroll priority',
        (tester) async {
      plugin.roads.first.data.addAll([
        for (var episode = 3; episode <= 100; episode++) '/$episode',
      ]);
      plugin.roads.first.identifier.addAll([
        for (var episode = 3; episode <= 100; episode++) 'EP $episode',
      ]);
      final nestedKey = GlobalKey<NestedScrollViewState>();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NestedScrollView(
            key: nestedKey,
            headerSliverBuilder: (context, _) => [
              SliverOverlapAbsorber(
                handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
                sliver: const SliverAppBar(
                  title: Text('Anime details'),
                  expandedHeight: 240,
                  pinned: true,
                ),
              ),
            ],
            body: InfoEpisodesView(
              bangumiItem: item,
              defaultPlugin: plugin,
              isActive: true,
              onChooseSource: () async => null,
              onPlay: (_) {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final nested = nestedKey.currentState!;
      final episodes = find.byKey(const PageStorageKey('episode-buttons:0'));
      final position = tester.getRect(episodes).bottomCenter - const Offset(0, 40);
      final gesture = wheel ? null : await tester.startGesture(position);
      if (gesture != null) {
        // Cross touch slop so subsequent moves are handled as scroll updates.
        await gesture.moveBy(const Offset(0, -24));
        await tester.pump();
      }
      Future<void> scroll(double delta) async {
        if (wheel) {
          await tester.sendEventToBinding(PointerScrollEvent(
            position: position,
            scrollDelta: Offset(0, delta),
            kind: PointerDeviceKind.mouse,
          ));
        } else {
          await gesture!.moveBy(Offset(0, -delta));
        }
        await tester.pump();
      }

      await scroll(80);
      expect(nested.outerController.offset, greaterThan(0));
      expect(nested.outerController.offset,
          lessThan(nested.outerController.position.maxScrollExtent));
      expect(nested.innerController.offset, 0);

      await scroll(500);
      final collapsed = nested.outerController.position.maxScrollExtent;
      expect(nested.outerController.offset, collapsed);
      final episodeOffset = nested.innerController.offset;
      expect(episodeOffset, greaterThan(0));

      await scroll(-80);
      expect(nested.outerController.offset, collapsed);
      expect(nested.innerController.offset, lessThan(episodeOffset));

      await scroll(-nested.innerController.offset - 50);
      expect(nested.innerController.offset, 0);
      expect(nested.outerController.offset, lessThan(collapsed));
      await gesture?.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  test('player starts from the explicitly selected episode and line', () {
    final controller = VideoPageController(
      _History(),
      _Downloads(),
      _Manager(),
    );
    controller.applyPlaybackArgs(args(episode: 2, road: 1));
    expect(
      controller.selectedEpisode,
      const VideoEpisodeSelection(episode: 2, road: 1),
    );
    expect(args().hasInitialSelection, isFalse);
    expect(args(episode: 3).hasInitialSelection, isFalse);
    expect(args(episode: 1, road: -1).hasInitialSelection, isFalse);
    expect(args(episode: 1, road: 5).hasInitialSelection, isFalse);
  });
}

class _Plugin implements Plugin {
  @override
  String get name => 'default';
  final roads = [
    Road(name: 'Line 1', data: ['/1', '/2'], identifier: ['EP 1', 'EP 2']),
    Road(
      name: 'Line 2',
      data: ['/line2/1', '/line2/2'],
      identifier: ['Alternative 1', 'Alternative 2'],
    ),
  ];
  int searches = 0;
  Object? error;
  Completer<void>? gate;
  RuleCancelToken? token;

  @override
  Future<PluginSearchResponse> queryBangumi(
    String keyword, {
    bool shouldRethrow = false,
    RuleCancelToken? cancelToken,
  }) async {
    searches++;
    token = cancelToken;
    await gate?.future;
    if (error != null) throw error!;
    return PluginSearchResponse(
      pluginName: name,
      data: [SearchItem(name: 'Anime', src: '/anime')],
    );
  }

  @override
  Future<List<Road>> queryChapterRoads(
    String source, {
    RuleCancelToken? cancelToken,
  }) async => roads;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _History implements HistoryController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Downloads implements IDownloadRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Manager implements IDownloadManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

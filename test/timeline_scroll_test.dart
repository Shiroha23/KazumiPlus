import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/timeline/timeline_controller.dart';
import 'package:kazumi/pages/timeline/timeline_page.dart';
import 'package:kazumi/repositories/collect_repository.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  late Directory directory;
  late PathProviderPlatform originalPaths;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('kazumi_timeline_test_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });

  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    expect(
      directory.absolute.path.startsWith(Directory.systemTemp.absolute.path),
      isTrue,
    );
    expect(
      directory.uri.pathSegments.where((part) => part.isNotEmpty).last,
      startsWith('kazumi_timeline_test_'),
    );
    await directory.delete(recursive: true);
  });

  for (final size in [const Size(1280, 800), const Size(520, 850)]) {
    testWidgets(
      'timeline headers stay fixed and season picker scrolls smoothly at $size',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final controller = _RecordingTimelineController();
        controller.bangumiCalendar.addAll(
          List.generate(
            7,
            (day) => List.generate(30, (index) => _item(day * 100 + index)),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.windows),
            home: TimelinePage(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        final season = find.byTooltip('切换放送季度');
        final weekdays = find.byType(TabBar);
        final seasonPosition = tester.getTopLeft(season);
        final weekPosition = tester.getTopLeft(weekdays);
        final list = find.byType(CustomScrollView).hitTestable();
        final scroll = tester.widget<CustomScrollView>(list).controller!;
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(list),
            scrollDelta: const Offset(0, 240),
            kind: PointerDeviceKind.mouse,
          ),
        );
        expect(scroll.offset, 0);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        expect(scroll.offset, inExclusiveRange(0, 240));
        expect(tester.getTopLeft(season), seasonPosition);
        expect(tester.getTopLeft(weekdays), weekPosition);
        await tester.pumpAndSettle();
        expect(scroll.offset, closeTo(240, .01));
        expect(tester.getTopLeft(season), seasonPosition);
        expect(tester.getTopLeft(weekdays), weekPosition);

        final nextDay = DateTime.now().weekday % 7;
        await tester.tapAt(tester.getCenter(find.byType(Tab).at(nextDay)));
        await tester.pumpAndSettle();
        expect(
          DefaultTabController.of(tester.element(weekdays)).index,
          nextDay,
        );
        expect(tester.getTopLeft(season), seasonPosition);
        expect(tester.getTopLeft(weekdays), weekPosition);

        await tester.tapAt(tester.getCenter(season));
        await tester.pumpAndSettle();
        final years = find.byType(ListView);
        final yearScroll = tester.widget<ListView>(years).controller!;
        final titlePosition = tester.getTopLeft(find.text('放送季度'));
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(years),
            scrollDelta: const Offset(0, 240),
            kind: PointerDeviceKind.mouse,
          ),
        );
        expect(yearScroll.offset, 0);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        expect(yearScroll.offset, inExclusiveRange(0, 240));
        await tester.pumpAndSettle();
        expect(yearScroll.offset, closeTo(240, .01));
        expect(tester.getTopLeft(find.text('放送季度')), titlePosition);
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(years),
            scrollDelta: const Offset(0, -240),
            kind: PointerDeviceKind.mouse,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, '冬季').first);
        await tester.pumpAndSettle();
        expect(controller.requestedSeason, DateTime(DateTime.now().year, 1));
        expect(find.text('放送季度'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _RecordingTimelineController extends TimelineController {
  _RecordingTimelineController() : super(CollectRepository());

  DateTime? requestedSeason;

  @override
  Future<void> loadSeason(DateTime date) async {
    requestedSeason = date;
  }
}

BangumiItem _item(int id) => BangumiItem(
  id: id,
  type: 2,
  name: 'Anime $id',
  nameCn: '番剧 $id',
  summary: '',
  airDate: '',
  airWeekday: 1,
  rank: 0,
  images: {},
  tags: [],
  alias: [],
  ratingScore: 7,
  votes: 0,
  votesCount: [],
  info: '12 话',
);

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/popular/popular_controller.dart';
import 'package:kazumi/pages/popular/popular_page.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:mobx/mobx.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  late Directory directory;
  late PathProviderPlatform originalPaths;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('kazumi_popular_test_');
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
      startsWith('kazumi_popular_test_'),
    );
    await directory.delete(recursive: true);
  });

  for (final tag in ['', '原创']) {
    for (final initiallyEmpty in [true, false]) {
      testWidgets(
        'recommendations update after loading (tag: $tag, empty: $initiallyEmpty)',
        (tester) async {
          final controller = _DeferredPopularController();
          controller.currentTag = tag;
          // A previously loaded trend list is retained when selecting a tag.
          if (tag.isNotEmpty) controller.trendList.add(_item(100));
          final items = tag.isEmpty
              ? controller.trendList
              : controller.bangumiList;
          if (!initiallyEmpty) items.add(_item(1));
          Future<void>? pending;
          if (tag.isNotEmpty) {
            pending = controller.queryBangumiByTag();
          } else if (!initiallyEmpty) {
            pending = controller.queryBangumiByTrend();
          }

          await tester.pumpWidget(
            MaterialApp(home: PopularPage(controller: controller)),
          );
          expect(
            find.byType(BangumiCardV),
            findsNWidgets(initiallyEmpty ? 0 : 1),
          );

          controller.response.complete([_item(2)]);
          if (pending != null) await pending;
          await tester.pumpAndSettle();

          // No navigation, window resize, or parent rebuild is needed.
          expect(find.text('番剧 2'), findsOneWidget);
          expect(
            find.byType(BangumiCardV),
            findsNWidgets(initiallyEmpty ? 1 : 2),
          );
          expect(find.byType(LinearProgressIndicator), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('switching category shows its delayed response immediately', (
    tester,
  ) async {
    final controller = _DeferredPopularController();
    controller.trendList.add(_item(1));
    await tester.pumpWidget(
      MaterialApp(home: PopularPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('切换推荐分类'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('原创'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.currentTag, '原创');
    expect(find.byType(BangumiCardV), findsNothing);

    controller.response.complete([_item(2)]);
    await tester.pumpAndSettle();
    expect(find.text('番剧 2'), findsOneWidget);
    expect(find.text('番剧 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _DeferredPopularController extends PopularController {
  final response = Completer<List<BangumiItem>>();

  Future<void> _load(ObservableList<BangumiItem> items) async {
    runInAction(() => isLoadingMore = true);
    final result = await response.future;
    runInAction(() {
      items.addAll(result);
      isLoadingMore = false;
      isTimeOut = items.isEmpty;
    });
  }

  @override
  Future<void> queryBangumiByTrend({String type = 'add'}) => _load(trendList);

  @override
  Future<void> queryBangumiByTag({String type = 'add'}) => _load(bangumiList);
}

BangumiItem _item(int id) => BangumiItem.fromJson({
  'id': id,
  'name': 'Anime $id',
  'name_cn': '番剧 $id',
  'images': <String, dynamic>{},
  'rating': <String, dynamic>{},
});

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

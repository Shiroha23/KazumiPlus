import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/card/bangumi_poster_grid.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/category/category_controller.dart';
import 'package:kazumi/pages/category/category_module.dart';
import 'package:kazumi/pages/category/category_page.dart';
import 'package:kazumi/pages/menu/menu.dart';
import 'package:kazumi/pages/router.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/search_parser.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  late Directory directory;
  late PathProviderPlatform originalPaths;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('kazumi_category_test_');
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
      startsWith('kazumi_category_test_'),
    );
    await directory.delete(recursive: true);
  });

  for (final size in [
    const Size(360, 800),
    const Size(1200, 800),
    const Size(700, 360),
  ]) {
    testWidgets('category filters fit $size and apply combined conditions', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final filters = <SearchFilterState>[];
      final controller = CategoryController(
        loader: (filter, _) async {
          filters.add(filter);
          return const BangumiSearchPage(items: [], rawCount: 0);
        },
      );
      addTearDown(controller.dispose);
      controller.setFilterLayout(CategoryFilterLayout.dropdown);
      await tester.pumpWidget(
        MaterialApp(home: CategoryPage(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(find.text('放送季度'), findsNothing);
      expect(find.byType(FilterChip), findsNothing);
      await tester.tap(find.byKey(const ValueKey('format-')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TV').last);
      await tester.pumpAndSettle();
      expect(filters.last.metaTags, ['TV']);
      await tester.tap(find.byKey(const ValueKey('tag-')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('日常').last);
      await tester.pumpAndSettle();
      expect(filters.last.tags, ['日常']);
      final year = find.byKey(const ValueKey('year-'));
      await tester.tap(year);
      await tester.pumpAndSettle();
      final currentYear = DateTime.now().year;
      await tester.tap(find.text('$currentYear 年').last);
      await tester.pumpAndSettle();
      expect(
        filters.last.dateRange,
        SearchDateRange(
          start: '$currentYear-01-01',
          end: '${currentYear + 1}-01-01',
        ),
      );
      expect(filters.last.season, isEmpty);
      await tester.tap(find.byKey(const ValueKey('sort-heat')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('评分最高').last);
      await tester.pumpAndSettle();
      expect(filters.last.sort, 'score');
      await tester.tap(find.byKey(const ValueKey('tag-日常')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('原创').last);
      await tester.pumpAndSettle();
      expect(filters.last.tags, ['原创']);
      expect(filters.last.dateRange?.start, '$currentYear-01-01');
      expect(filters.last.sort, 'score');
      await tester.tap(find.byKey(const ValueKey('tag-原创')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('不限题材'),
        -80,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('不限题材').last);
      await tester.pumpAndSettle();
      expect(filters.last.tags, isEmpty);
      expect(filters.last.dateRange?.start, '$currentYear-01-01');
      expect(filters.last.sort, 'score');
      final reset = find.byTooltip('重置筛选');
      expect(filters.last.metaTags, ['TV']);
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(filters.last.hasAdvancedFilters, isFalse);
      expect(find.text('没有符合条件的番剧'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final rows in [false, true]) {
    testWidgets(
      'category resizes filters and posters without losing state (rows: $rows)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 800);
        addTearDown(tester.view.reset);
        var calls = 0;
        final items = List.generate(
          24,
          (index) => BangumiItem.fromJson({
            'id': index + 1,
            'name': '番剧 ${index + 1}',
            'name_cn': '番剧 ${index + 1}',
            'images': <String, dynamic>{},
            'rating': <String, dynamic>{},
          }),
        );
        final controller = CategoryController(
          loader: (_, offset) async {
            calls++;
            return BangumiSearchPage(
              items: items,
              rawCount: items.length,
              total: items.length,
            );
          },
        );
        addTearDown(controller.dispose);
        await controller.setFilters(
          const SearchFilterState(
            metaTags: ['TV'],
            tags: ['日常'],
            sort: 'score',
            dateRange: SearchDateRange(start: '2021-01-01', end: '2022-01-01'),
          ),
        );
        if (!rows) controller.setFilterLayout(CategoryFilterLayout.dropdown);
        await tester.pumpWidget(
          MaterialApp(home: CategoryPage(controller: controller)),
        );
        await tester.pumpAndSettle();
        int columns() =>
            (tester.widget<SliverGrid>(find.byType(SliverGrid)).gridDelegate
                    as SliverGridDelegateWithFixedCrossAxisCount)
                .crossAxisCount;
        final narrowColumns = columns();
        expect(tester.getRect(find.byType(BangumiPosterCard).first).left, 16);
        final filters = controller.filters;
        if (!rows) {
          final format = tester.getRect(
            find.byKey(const ValueKey('format-TV')),
          );
          final tag = tester.getRect(find.byKey(const ValueKey('tag-日常')));
          final year = tester.getRect(find.byKey(const ValueKey('year-2021')));
          expect(format.top, tag.top);
          expect(year.top, greaterThan(format.top));
        }
        tester.view.physicalSize = const Size(1600, 900);
        await tester.pumpAndSettle();
        final cards = find.byType(BangumiPosterCard);
        expect(tester.getRect(cards.first).left, 16);
        expect(1600 - tester.getRect(cards.at(columns() - 1)).right, 16);
        expect(columns(), greaterThan(narrowColumns));
        expect(
          tester
              .widget<BangumiPosterGrid>(find.byType(BangumiPosterGrid))
              .width,
          greaterThan(1400),
        );
        if (!rows) {
          final top = tester
              .getTopLeft(find.byKey(const ValueKey('format-TV')))
              .dy;
          for (final key in ['tag-日常', 'year-2021', 'sort-score']) {
            expect(tester.getTopLeft(find.byKey(ValueKey(key))).dy, top);
          }
        }
        tester.view.physicalSize = const Size(360, 800);
        await tester.pumpAndSettle();
        expect(columns(), narrowColumns);
        if (rows) {
          expect(
            find.byKey(const ValueKey('row-年份-2021')).hitTestable(),
            findsOneWidget,
          );
        }
        expect(identical(controller.filters, filters), isTrue);
        expect(controller.useFilterRows, rows);
        expect(controller.items, hasLength(24));
        expect(calls, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('dropdowns use one full-width column for enlarged text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    final controller = CategoryController(
      loader: (_, offset) async =>
          const BangumiSearchPage(items: [], rawCount: 0),
    );
    addTearDown(controller.dispose);
    controller.setFilterLayout(CategoryFilterLayout.dropdown);
    await controller.setFilters(const SearchFilterState(metaTags: ['剧场版']));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: CategoryPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    final format = tester.getRect(find.byKey(const ValueKey('format-剧场版')));
    final tag = tester.getRect(find.byKey(const ValueKey('tag-')));
    expect(format.width, greaterThan(300));
    expect(tag.top, greaterThan(format.top));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed category request offers retry and then shows empty state',
    (tester) async {
      var calls = 0;
      final controller = CategoryController(
        loader: (_, offset) async {
          return ++calls == 1
              ? null
              : const BangumiSearchPage(items: [], rawCount: 0);
        },
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: CategoryPage(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(find.text('暂时无法加载番剧'), findsOneWidget);
      expect(find.text('没有符合条件的番剧'), findsNothing);
      await tester.ensureVisible(find.text('重试'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('暂时无法加载番剧'), findsNothing);
      expect(find.text('没有符合条件的番剧'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'filter rows allow mouse dragging without selecting or refetching',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.reset);
      var calls = 0;
      final controller = CategoryController(
        loader: (_, offset) async {
          calls++;
          return const BangumiSearchPage(items: [], rawCount: 0);
        },
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: CategoryPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Scrollbar), findsNothing);
      final year = DateTime.now().year;
      final yearOption = find.byKey(ValueKey('row-年份-$year'));
      final position = Scrollable.of(
        tester.element(yearOption),
        axis: Axis.horizontal,
      ).position;
      final before = position.pixels;
      await tester.dragFrom(
        tester.getCenter(yearOption),
        const Offset(-220, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(before));
      expect(controller.filters.hasAdvancedFilters, isFalse);
      expect(calls, 1);
      await tester.ensureVisible(yearOption);
      await tester.pumpAndSettle();
      await tester.tap(yearOption);
      await tester.pumpAndSettle();
      expect(controller.filters.dateRange?.start, '$year-01-01');
      expect(calls, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('filter rows fit a narrow screen with enlarged text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    final controller = CategoryController(
      loader: (_, offset) async =>
          const BangumiSearchPage(items: [], rawCount: 0),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: CategoryPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    final movie = find.byKey(const ValueKey('row-类型-剧场版'));
    await tester.ensureVisible(movie);
    await tester.pumpAndSettle();
    await tester.tap(movie);
    await tester.pumpAndSettle();
    expect(controller.filters.metaTags, ['剧场版']);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(360, 800),
    const Size(1200, 800),
    const Size(700, 360),
  ]) {
    testWidgets(
      'row and dropdown layouts share filters without refetching at $size',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        var calls = 0;
        final controller = CategoryController(
          loader: (_, offset) async {
            calls++;
            return const BangumiSearchPage(items: [], rawCount: 0);
          },
        );
        addTearDown(controller.dispose);
        await controller.setFilters(
          const SearchFilterState(
            metaTags: ['TV'],
            tags: ['日常'],
            sort: 'score',
            dateRange: SearchDateRange(start: '2000-01-01', end: '2001-01-01'),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              colorSchemeSeed: Colors.red,
              brightness: size.width > 600 ? Brightness.dark : Brightness.light,
            ),
            home: CategoryPage(controller: controller),
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.useFilterRows, isTrue);
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        expect(
          find.byKey(const ValueKey('row-年份-2000')).hitTestable(),
          findsOneWidget,
        );
        expect(calls, 1);
        // Clicking the selected option does not repeat the request.
        await tester.tap(find.byKey(const ValueKey('row-年份-2000')));
        await tester.pumpAndSettle();
        expect(calls, 1);
        Future<void> select(String key) async {
          final finder = find.byKey(ValueKey(key));
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        await select('row-类型-剧场版');
        await select('row-年份-2021');
        await select('row-排序-heat');
        expect(controller.filters.metaTags, ['剧场版']);
        expect(controller.filters.tags, ['日常']);
        expect(controller.filters.dateRange?.start, '2021-01-01');
        expect(controller.filters.sort, 'heat');
        expect(calls, 4);
        await _selectLayout(tester, '下拉视图');
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('format-剧场版')), findsOneWidget);
        expect(find.byKey(const ValueKey('tag-日常')), findsOneWidget);
        expect(find.byKey(const ValueKey('year-2021')), findsOneWidget);
        expect(find.byKey(const ValueKey('sort-heat')), findsOneWidget);
        expect(calls, 4);
        await _selectLayout(tester, '分行视图');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byTooltip('重置筛选'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('重置筛选'));
        await tester.pumpAndSettle();
        expect(controller.filters.hasAdvancedFilters, isFalse);
        expect(controller.useFilterRows, isTrue);
        expect(calls, 5);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [const Size(360, 800), const Size(1200, 800)]) {
    testWidgets('sidebar shares filters and resets at $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      var calls = 0;
      final controller = CategoryController(
        loader: (_, offset) async {
          calls++;
          return const BangumiSearchPage(items: [], rawCount: 0);
        },
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: CategoryPage(controller: controller)),
      );
      await tester.pumpAndSettle();
      await _selectLayout(tester, '侧边栏视图');
      await tester.pumpAndSettle();
      expect(controller.filterLayout, CategoryFilterLayout.sidebar);
      expect(calls, 1);
      expect(find.byKey(const ValueKey('row-类型-TV')), findsNothing);
      expect(
        find.byKey(const ValueKey('category-sidebar')),
        size.width >= 800 ? findsOneWidget : findsNothing,
      );
      if (size.width < 800) {
        expect(find.byTooltip('收起筛选'), findsOneWidget);
        expect(tester.getRect(find.byType(Drawer)).right, size.width);
      } else {
        expect(
          tester.getRect(find.byKey(const ValueKey('category-sidebar'))).width,
          320,
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('category-sidebar'))).left,
          greaterThan(size.width / 2),
        );
      }
      for (final tag in [
        '科幻',
        '战斗',
        '冒险',
        '运动',
        '音乐',
        '美食',
        '职场',
        '漫画改',
        '游戏改',
        '小说改',
      ]) {
        expect(find.byKey(ValueKey('sidebar-题材-$tag')), findsOneWidget);
      }

      Future<void> select(String key) async {
        final finder = find.byKey(ValueKey(key));
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await select('sidebar-类型-剧场版');
      await select('sidebar-题材-科幻');
      await select('sidebar-year-');
      final year = DateTime.now().year;
      await tester.tap(find.text('$year 年').last);
      await tester.pumpAndSettle();
      await select('sidebar-排序-score');
      expect(controller.filters.metaTags, ['剧场版']);
      expect(controller.filters.tags, ['科幻']);
      expect(controller.filters.dateRange?.start, '$year-01-01');
      expect(controller.filters.sort, 'score');
      expect(calls, 5);
      await select('sidebar-排序-score');
      expect(calls, 5);
      if (size.width < 800) {
        await tester.tap(find.byTooltip('收起筛选'));
        await tester.pumpAndSettle();
        expect(find.text('筛选条件'), findsOneWidget);
      }
      await _selectLayout(tester, '下拉视图');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('format-剧场版')), findsOneWidget);
      expect(find.byKey(const ValueKey('tag-科幻')), findsOneWidget);
      expect(find.byKey(ValueKey('year-$year')), findsOneWidget);
      expect(find.byKey(const ValueKey('sort-score')), findsOneWidget);
      expect(calls, 5);
      await _selectLayout(tester, '侧边栏视图');
      await tester.pumpAndSettle();
      if (size.width < 800) {
        await tester.tap(find.byTooltip('收起筛选'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('重置筛选'));
      await tester.pumpAndSettle();
      expect(controller.filters.hasAdvancedFilters, isFalse);
      expect(controller.filterLayout, CategoryFilterLayout.sidebar);
      expect(calls, 6);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'sidebar changes between drawer and panel while resizing with enlarged text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.reset);
      var calls = 0;
      final controller = CategoryController(
        loader: (_, offset) async {
          calls++;
          return const BangumiSearchPage(items: [], rawCount: 0);
        },
      );
      addTearDown(controller.dispose);
      await controller.setFilters(
        const SearchFilterState(metaTags: ['OVA'], tags: ['奇幻']),
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: CategoryPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await _selectLayout(tester, '侧边栏视图');
      await tester.pumpAndSettle();
      expect(find.byTooltip('收起筛选'), findsOneWidget);
      expect(find.byKey(const ValueKey('sidebar-类型-OVA')), findsOneWidget);
      tester.view.physicalSize = const Size(1400, 900);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('category-sidebar')), findsOneWidget);
      expect(find.byTooltip('收起筛选'), findsNothing);
      expect(controller.filters.metaTags, ['OVA']);
      expect(controller.filters.tags, ['奇幻']);
      tester.view.physicalSize = const Size(700, 360);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('category-sidebar')), findsNothing);
      await tester.tap(find.text('筛选条件'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('收起筛选'), findsOneWidget);
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final layout in CategoryFilterLayout.values) {
    testWidgets(
      'back to top scrolls results without changing $layout filters',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = layout == CategoryFilterLayout.rows
            ? const Size(360, 800)
            : const Size(1200, 800);
        addTearDown(tester.view.reset);
        var calls = 0;
        final items = List.generate(
          48,
          (index) => BangumiItem.fromJson({
            'id': index + 1,
            'name': '番剧 ${index + 1}',
            'images': <String, dynamic>{},
            'rating': <String, dynamic>{},
          }),
        );
        final controller = CategoryController(
          loader: (_, offset) async {
            calls++;
            return BangumiSearchPage(
              items: items,
              rawCount: items.length,
              total: items.length,
            );
          },
        );
        addTearDown(controller.dispose);
        controller.setFilterLayout(layout);
        await controller.setFilters(
          const SearchFilterState(metaTags: ['OVA'], tags: ['奇幻']),
        );
        await tester.pumpWidget(
          MaterialApp(home: CategoryPage(controller: controller)),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('回到顶部'), findsOneWidget);
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
        await tester.pumpAndSettle();
        expect(controller.scrollOffset, greaterThan(400));
        expect(find.byTooltip('回到顶部'), findsOneWidget);
        final pageRect = tester.getRect(find.byType(Scaffold));
        final buttonRect = tester.getRect(find.byType(FloatingActionButton));
        expect(pageRect.right - buttonRect.right, 16);
        expect(pageRect.bottom - buttonRect.bottom, 16);
        await tester.tap(find.byTooltip('回到顶部'));
        await tester.pumpAndSettle();
        expect(controller.scrollOffset, 0);
        expect(find.byTooltip('回到顶部'), findsOneWidget);
        expect(controller.filters.metaTags, ['OVA']);
        expect(controller.filters.tags, ['奇幻']);
        expect(controller.filterLayout, layout);
        expect(calls, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [const Size(400, 800), const Size(1200, 800)]) {
    testWidgets(
      'main navigation opens the category route and retains filters at $size',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        var calls = 0;
        final controller = CategoryController(
          loader: (_, offset) async {
            calls++;
            return const BangumiSearchPage(items: [], rawCount: 0);
          },
        );
        final module = createModule(
          register: (c) {
            c.addSingleton<CategoryController>(() => controller);
            c.route(
              '/tab',
              child: (_, state) => ScaffoldMenu(location: state.uri.path),
              children: (sub) {
                sub.module(categoryModule);
                for (final path in [
                  '/popular',
                  '/timeline',
                  '/collect',
                  '/my',
                ]) {
                  sub.route(
                    '$path/',
                    child: (_, _) => const Center(child: Text('其他页面')),
                  );
                }
              },
            );
          },
        );
        await tester.pumpWidget(
          ModularApp(
            module: module,
            initialRoute: '/tab/popular/',
            child: Builder(
              builder: (context) => MaterialApp.router(
                routerConfig: ModularApp.routerConfigOf(context),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final navigationType = size.width < size.height
            ? NavigationBar
            : NavigationRail;
        Finder destination(String label) => find.descendant(
          of: find.byType(navigationType),
          matching: find.byIcon(
            label == '分类' ? Icons.category_outlined : Icons.timeline_outlined,
          ),
        );
        await tester.tap(destination('分类'));
        await tester.pumpAndSettle();
        expect(find.byType(CategoryPage), findsOneWidget);
        expect(menu.indexForPath('/tab/category/'), 1);
        expect(controller.useFilterRows, isTrue);
        final genre = find.byKey(const ValueKey('row-题材-日常'));
        await tester.ensureVisible(genre);
        await tester.pumpAndSettle();
        await tester.tap(genre);
        await tester.pumpAndSettle();
        expect(calls, 2);
        final movie = find.byKey(const ValueKey('row-类型-剧场版'));
        await tester.ensureVisible(movie);
        await tester.pumpAndSettle();
        await tester.tap(movie);
        await tester.pumpAndSettle();
        await tester.tap(destination('时间表'));
        await tester.pumpAndSettle();
        expect(find.byType(CategoryPage), findsNothing);
        await tester.tap(destination('分类'));
        await tester.pumpAndSettle();
        expect(controller.filters.tags, ['日常']);
        expect(controller.filters.metaTags, ['剧场版']);
        expect(controller.useFilterRows, isTrue);
        expect(
          find.byKey(const ValueKey('row-题材-日常')).hitTestable(),
          findsOneWidget,
        );
        expect(calls, 3);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}

Future<void> _selectLayout(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('切换筛选视图'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

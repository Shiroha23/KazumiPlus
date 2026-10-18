import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/category/category_controller.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/utils/search_parser.dart';

void main() {
  test(
    'filter changes discard pending results from the previous category',
    () async {
      final requests = <Completer<BangumiSearchPage?>>[];
      final controller = CategoryController(
        loader: (filters, offset) {
          final response = Completer<BangumiSearchPage?>();
          requests.add(response);
          return response.future;
        },
      );
      addTearDown(controller.dispose);
      final oldRequest = controller.initialize();
      final newRequest = controller.setFilters(
        const SearchFilterState(tags: ['奇幻'], season: '2026Q1', sort: 'score'),
      );
      requests.last.complete(_page([2]));
      await newRequest;
      requests.first.complete(_page([1]));
      await oldRequest;
      expect(controller.items.map((item) => item.id), [2]);
      expect(controller.filters.tags, ['奇幻']);
      expect(
        controller.filters.effectiveDateRange,
        const SearchDateRange(start: '2025-12-01', end: '2026-03-01'),
      );
      expect(controller.isLoading, isFalse);
      expect(controller.hasError, isFalse);
    },
  );

  test(
    'pagination uses raw offsets, deduplicates and stops at the last page',
    () async {
      final offsets = <int>[];
      final controller = CategoryController(
        loader: (_, offset) async {
          offsets.add(offset);
          return offset == 0
              ? _page([1, 2], rawCount: CategoryController.pageSize)
              : _page([2, 3]);
        },
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.load();
      await controller.load();
      expect(offsets, [0, 20]);
      expect(controller.items.map((item) => item.id), [1, 2, 3]);
      expect(controller.hasMore, isFalse);
    },
  );

  test(
    'a failed next page retains results and retries the same offset',
    () async {
      final offsets = <int>[];
      final controller = CategoryController(
        loader: (_, offset) async {
          offsets.add(offset);
          if (offsets.length == 2) return null;
          return _page([offset + 1], rawCount: CategoryController.pageSize);
        },
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.load();
      expect(controller.hasError, isTrue);
      expect(controller.items.single.id, 1);
      await controller.load();
      expect(offsets, [0, 20, 20]);
      expect(controller.items.map((item) => item.id), [1, 21]);
      expect(controller.hasError, isFalse);
    },
  );

  test(
    'empty parsed pages advance with a bounded number of requests',
    () async {
      final offsets = <int>[];
      final controller = CategoryController(
        loader: (_, offset) async {
          offsets.add(offset);
          return _page([], rawCount: CategoryController.pageSize);
        },
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(offsets, [0, 20, 40]);
      expect(controller.hasMore, isTrue);
      expect(controller.isLoading, isFalse);
    },
  );

  test(
    'returning to the tab retains filters and avoids another initial request',
    () async {
      var calls = 0;
      final controller = CategoryController(
        loader: (_, offset) async {
          calls++;
          return _page([1]);
        },
      );
      addTearDown(controller.dispose);
      await controller.setFilters(const SearchFilterState(tags: ['日常']));
      controller.scrollOffset = 200;
      await controller.initialize();
      expect(calls, 1);
      expect(controller.scrollOffset, 200);
      expect(controller.filters.tags, ['日常']);
    },
  );

  test('disposing the tab shell ignores an outstanding response', () async {
    final response = Completer<BangumiSearchPage?>();
    final controller = CategoryController(
      loader: (_, offset) => response.future,
    );
    final request = controller.initialize();
    controller.dispose();
    response.complete(_page([1]));
    await request;
    expect(controller.items, isEmpty);
  });

  for (final total in [25, null]) {
    test('server-capped pages keep loading (total: $total)', () async {
      final offsets = <int>[];
      final controller = CategoryController(
        loader: (_, offset) async {
          offsets.add(offset);
          return _page(
            [offset + 1],
            rawCount: offset < 20 ? 10 : 5,
            total: total,
            limit: 10,
          );
        },
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.hasMore, isTrue);
      await controller.load();
      expect(controller.hasMore, isTrue);
      await controller.load();
      expect(controller.hasMore, isFalse);
      await controller.load();
      expect(offsets, [0, 10, 20]);
      expect(controller.items.map((item) => item.id), [1, 11, 21]);
    });
  }

  test('a full final page stops at the reported total', () async {
    final controller = CategoryController(
      loader: (_, offset) async =>
          _page([offset + 1], rawCount: 20, total: 40, limit: 20),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.hasMore, isTrue);
    await controller.load();
    expect(controller.hasMore, isFalse);
  });

  test('an empty page stops even when the reported total is stale', () async {
    final controller = CategoryController(
      loader: (_, offset) async =>
          _page([], rawCount: 0, total: 100, limit: 20),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.hasMore, isFalse);
    expect(controller.hasError, isFalse);
  });
}

BangumiSearchPage _page(
  List<int> ids, {
  int? rawCount,
  int? total,
  int? limit,
}) => BangumiSearchPage(
  items: ids
      .map(
        (id) => BangumiItem.fromJson({
          'id': id,
          'name': 'Anime $id',
          'name_cn': '番剧 $id',
          'images': <String, dynamic>{},
          'rating': <String, dynamic>{},
        }),
      )
      .toList(),
  rawCount: rawCount ?? ids.length,
  total: total,
  limit: limit,
);

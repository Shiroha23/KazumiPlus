import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/utils/search_parser.dart';

class CategoryDataSource {
  CategoryDataSource({required this.pageSize});

  final int pageSize;
  Future<List<BangumiItem>?>? _otherCatalog;
  Future<List<BangumiItem>?>? _trends;

  Future<BangumiSearchPage?> load(SearchFilterState filters, int offset) {
    if (filters.metaTags.contains('其他')) return _loadOther(filters, offset);
    if (filters.sort == 'score') {
      return BangumiApi.bangumiSearch(
        '',
        tags: filters.tags,
        metaTags: filters.metaTags,
        sort: 'score',
        dateRange: filters.effectiveDateRange,
        limit: pageSize,
        offset: offset,
      );
    }
    final date = filters.effectiveDateRange?.start;
    return BangumiApi.getBangumiCategoryPage(
      format: filters.metaTags.firstOrNull ?? '',
      tags: filters.tags,
      year: date == null ? null : int.tryParse(date.substring(0, 4)),
      sort: filters.sort,
      offset: offset,
    );
  }

  Future<BangumiSearchPage?> _loadOther(
    SearchFilterState filters,
    int offset,
  ) async {
    final catalogRequest = _otherCatalog ??= _readAll(
      (offset) => BangumiApi.getBangumiOtherAnimePage(offset: offset),
    );
    final catalog = await catalogRequest;
    if (catalog == null) {
      if (identical(catalogRequest, _otherCatalog)) _otherCatalog = null;
      return null;
    }
    final dates = filters.effectiveDateRange;
    final matches = catalog.where((item) {
      return filters.tags.every(item.tags.map((tag) => tag.name).contains) &&
          (dates == null ||
              (item.airDate.isNotEmpty &&
                  item.airDate.compareTo(dates.start) >= 0 &&
                  item.airDate.compareTo(dates.end) < 0));
    }).toList();
    List<BangumiItem> ordered;
    if (filters.sort == 'heat') {
      final request = _trends ??= _readAll(
        (offset) => BangumiApi.getBangumiTrendsPage(limit: 100, offset: offset),
      );
      final trends = await request;
      if (trends == null) {
        if (identical(request, _trends)) _trends = null;
        return null;
      }
      final byId = {for (final item in matches) item.id: item};
      ordered = [
        for (final item in trends)
          if (byId.containsKey(item.id)) byId[item.id]!,
      ];
    } else {
      ordered = matches
          .where((item) => filters.sort != 'rank' || item.rank > 0)
          .toList();
      ordered.sort((a, b) {
        final comparison = filters.sort == 'score'
            ? b.ratingScore.compareTo(a.ratingScore)
            : a.rank.compareTo(b.rank);
        if (comparison != 0) return comparison;
        final votes = b.votes.compareTo(a.votes);
        return votes != 0 ? votes : a.id.compareTo(b.id);
      });
    }
    final items = ordered.skip(offset).take(pageSize).toList();
    return BangumiSearchPage(
      items: items,
      rawCount: items.length,
      total: ordered.length,
      limit: pageSize,
    );
  }

  // The other catalog is small. Resolve it fully before sorting scores so
  // pagination includes unranked entries without reordering subsequent pages.
  Future<List<BangumiItem>?> _readAll(
    Future<BangumiSearchPage?> Function(int) loader,
  ) async {
    final items = <int, BangumiItem>{};
    var offset = 0;
    for (var pageIndex = 0; pageIndex < 200; pageIndex++) {
      final page = await loader(offset);
      if (page == null) return null;
      for (final item in page.items) {
        items[item.id] = item;
      }
      offset = page.nextOffset ?? offset + page.rawCount;
      if (!page.hasMore(nextOffset: offset, requestedLimit: 100)) {
        return items.values.toList();
      }
    }
    return null;
  }
}

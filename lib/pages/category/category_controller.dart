import 'package:flutter/foundation.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/category/category_data_source.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/utils/search_parser.dart';

typedef CategoryLoader =
    Future<BangumiSearchPage?> Function(SearchFilterState filters, int offset);

enum CategoryFilterLayout { rows, dropdown, sidebar }

class CategoryController extends ChangeNotifier {
  CategoryController({CategoryLoader? loader})
    : _loader = loader ?? CategoryDataSource(pageSize: pageSize).load;

  static const pageSize = 20;
  final CategoryLoader _loader;
  final List<BangumiItem> _items = [];
  SearchFilterState _filters = const SearchFilterState();
  int _offset = 0;
  int _generation = 0;
  bool _initialized = false;
  CategoryFilterLayout _filterLayout = CategoryFilterLayout.rows;

  SearchFilterState get filters => _filters;
  CategoryFilterLayout get filterLayout => _filterLayout;
  bool get useFilterRows => _filterLayout == CategoryFilterLayout.rows;
  List<BangumiItem> get items => List.unmodifiable(_items);
  bool isLoading = false;
  bool hasError = false;
  bool hasMore = true;
  double scrollOffset = 0;

  void setFilterLayout(CategoryFilterLayout layout) {
    if (_filterLayout == layout) return;
    _filterLayout = layout;
    notifyListeners();
  }

  Future<void> initialize() async {
    if (!_initialized) await load();
  }

  Future<void> setFilters(SearchFilterState filters) {
    _filters = filters.copyWith(
      tags: List.unmodifiable(filters.tags),
      metaTags: List.unmodifiable(filters.metaTags),
    );
    scrollOffset = 0;
    return load(refresh: true);
  }

  Future<void> load({bool refresh = false}) async {
    if (!refresh && (isLoading || !hasMore)) return;
    _initialized = true;
    if (refresh) {
      _generation++;
      _offset = 0;
      _items.clear();
      hasMore = true;
    }
    final generation = _generation;
    final filters = _filters;
    isLoading = true;
    hasError = false;
    notifyListeners();
    try {
      // A page may contain no usable entries after API parsing. Advance using
      // its raw count, with a bound so sparse results cannot loop indefinitely.
      for (var attempt = 0; attempt < 3; attempt++) {
        final page = await _loader(filters, _offset);
        if (generation != _generation) return;
        if (page == null) {
          hasError = true;
          break;
        }
        _offset = page.nextOffset ?? _offset + page.rawCount;
        hasMore = page.hasMore(nextOffset: _offset, requestedLimit: pageSize);
        final ids = _items.map((item) => item.id).toSet();
        final additions = page.items.where((item) => ids.add(item.id)).toList();
        _items.addAll(additions);
        if (additions.isNotEmpty || !hasMore) break;
      }
    } catch (_) {
      if (generation == _generation) hasError = true;
    } finally {
      if (generation == _generation) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }
}

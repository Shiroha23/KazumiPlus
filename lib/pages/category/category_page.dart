import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/card/bangumi_poster_grid.dart';
import 'package:kazumi/bean/widget/bangumi_mirror_error_widget.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:kazumi/bean/widget/smooth_scroll.dart';
import 'package:kazumi/pages/category/category_controller.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/utils/search_parser.dart';

part 'category_filter_rows.dart';
part 'category_filter_sidebar.dart';

class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key, required this.controller});

  final CategoryController controller;

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  double _availableWidth = 0;
  late final _scroll = SmoothScrollController(
    initialScrollOffset: _controller.scrollOffset,
  );
  CategoryController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _controller.initialize();
  }

  void _onScroll() {
    _controller.scrollOffset = _scroll.offset;
    if (_scroll.position.extentAfter < 360 && !_controller.hasError) {
      _controller.load();
    }
  }

  void _apply(SearchFilterState filters) {
    _controller.setFilters(filters);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _backToTop() {
    if (!_scroll.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(0);
    } else {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String get _year =>
      _controller.filters.dateRange?.start.substring(0, 4) ?? '';

  void _selectYear(String year) {
    final selectedYear = int.tryParse(year);
    _apply(
      _controller.filters.copyWith(
        season: '',
        dateRange: selectedYear != null
            ? SearchDateRange(
                start: '$year-01-01',
                end: '${selectedYear + 1}-01-01',
              )
            : null,
      ),
    );
  }

  double get _sidebarWidth =>
      math.max(320.0, MediaQuery.textScalerOf(context).scale(100) + 180);

  bool _showExpandedSidebar(double width) =>
      width >= math.max(800.0, _sidebarWidth + 440);

  void _selectFilterLayout(CategoryFilterLayout layout) {
    _controller.setFilterLayout(layout);
    if (layout == CategoryFilterLayout.sidebar &&
        !_showExpandedSidebar(_availableWidth)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scaffoldKey.currentState?.openEndDrawer();
      });
    }
  }

  Widget _sidebar({bool closable = false}) => _CategoryFilterSidebar(
    filters: _controller.filters,
    year: _year,
    onChanged: _apply,
    onYearChanged: _selectYear,
    onClose: closable
        ? () => _scaffoldKey.currentState?.closeEndDrawer()
        : null,
  );

  Widget _resultScroll(double width, {bool sidebar = false}) =>
      RefreshIndicator(
        onRefresh: () => _controller.load(refresh: true),
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 24),
              sliver: SliverMainAxisGroup(
                slivers: [
                  if (!sidebar)
                    SliverToBoxAdapter(child: _filters(width))
                  else if (!_showExpandedSidebar(_availableWidth))
                    SliverToBoxAdapter(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextButton.icon(
                            onPressed: () =>
                                _scaffoldKey.currentState?.openEndDrawer(),
                            icon: const Icon(Icons.tune_rounded),
                            label: const Text('筛选条件'),
                          ),
                        ),
                      ),
                    ),
                  ..._results(width),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _filters(double width) {
    final filters = _controller.filters;
    if (_controller.useFilterRows) {
      return _CategoryFilterRows(
        filters: filters,
        year: _year,
        onChanged: _apply,
        onYearChanged: _selectYear,
      );
    }
    final tag = filters.tags.firstOrNull ?? '';
    final format = filters.metaTags.firstOrNull ?? '';
    const fieldSpacing = 12.0;
    final minFieldWidth = math.max(
      140.0,
      MediaQuery.textScalerOf(context).scale(100),
    );
    final columns = ((width + fieldSpacing) / (minFieldWidth + fieldSpacing))
        .floor()
        .clamp(1, 4);
    final fieldWidth = (width - fieldSpacing * (columns - 1)) / columns;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: fieldWidth,
            child: DropdownButtonFormField<String>(
              key: ValueKey('format-$format'),
              initialValue: format,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '类型'),
              items: [
                const DropdownMenuItem(value: '', child: Text('不限类型')),
                for (final format in _categoryFormats)
                  DropdownMenuItem(value: format, child: Text(format)),
              ],
              onChanged: (value) => _apply(
                filters.copyWith(
                  metaTags: value == null || value.isEmpty ? [] : [value],
                ),
              ),
            ),
          ),
          SizedBox(
            width: fieldWidth,
            child: DropdownButtonFormField<String>(
              key: ValueKey('tag-$tag'),
              initialValue: tag,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '题材'),
              items: [
                const DropdownMenuItem(value: '', child: Text('不限题材')),
                for (final option in {..._categoryTags, ...filters.tags})
                  DropdownMenuItem(value: option, child: Text(option)),
              ],
              onChanged: (value) => _apply(
                filters.copyWith(
                  tags: value == null || value.isEmpty ? [] : [value],
                ),
              ),
            ),
          ),
          SizedBox(
            width: fieldWidth,
            child: DropdownButtonFormField<String>(
              key: ValueKey('year-$_year'),
              initialValue: _year,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '放送年份'),
              items: [
                const DropdownMenuItem(value: '', child: Text('不限年份')),
                for (var year = DateTime.now().year; year >= 1900; year--)
                  DropdownMenuItem(value: '$year', child: Text('$year 年')),
              ],
              onChanged: (value) => _selectYear(value ?? ''),
            ),
          ),
          SizedBox(
            width: fieldWidth,
            child: DropdownButtonFormField<String>(
              key: ValueKey('sort-${filters.sort}'),
              initialValue: filters.sort,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '排序方式'),
              items: [
                for (final sort in _categorySortLabels.entries)
                  DropdownMenuItem(value: sort.key, child: Text(sort.value)),
              ],
              onChanged: (value) =>
                  _apply(filters.copyWith(sort: value ?? 'heat')),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _results(double width) {
    final items = _controller.items;
    return [
      if (items.isEmpty && _controller.isLoading)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: LoadingIndicator()),
          ),
        )
      else if (items.isNotEmpty)
        BangumiPosterGrid(
          items: items,
          width: width,
          showRating: GStorage.getSetting(SettingsKeys.showRating),
        )
      else if (!_controller.hasError)
        SliverToBoxAdapter(
          child: GeneralEmptyState(
            icon: Icons.filter_alt_off_rounded,
            title: _controller.hasMore ? '当前批次暂无匹配番剧，可继续加载' : '没有符合条件的番剧',
          ),
        ),
      if (_controller.hasError)
        SliverToBoxAdapter(
          child: BangumiMirrorErrorWidget(
            onRetry: () => _controller.load(),
            onSettingsReturned: () {
              if (mounted) setState(() {});
            },
          ),
        )
      else if (!_controller.isLoading || items.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: _controller.isLoading
                  ? const LoadingIndicator(size: 32)
                  : _controller.hasMore
                  ? TextButton.icon(
                      onPressed: () => _controller.load(),
                      icon: const Icon(Icons.expand_more_rounded),
                      label: const Text('加载更多'),
                    )
                  : Text(
                      '已经看到全部结果',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _availableWidth = math.max(
        0.0,
        constraints.maxWidth - MediaQuery.paddingOf(context).horizontal,
      );
      return Scaffold(
        key: _scaffoldKey,
        floatingActionButton: FloatingActionButton(
          heroTag: 'category-back-to-top',
          tooltip: '回到顶部',
          onPressed: _backToTop,
          child: const Icon(Icons.arrow_upward_rounded),
        ),
        endDrawerEnableOpenDragGesture: false,
        endDrawer: Drawer(
          width: math.min(
            _sidebarWidth + 32,
            math.max(0.0, _availableWidth - 32),
          ),
          child: SafeArea(
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => _sidebar(closable: true),
            ),
          ),
        ),
        appBar: SysAppBar(
          needTopOffset: false,
          toolbarHeight: 72,
          title: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => LayoutBuilder(
              builder: (context, constraints) {
                final showResetLabel =
                    constraints.maxWidth >=
                    MediaQuery.textScalerOf(context).scale(110) + 64;
                void reset() => _apply(const SearchFilterState());
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        '分类',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (_controller.filters.hasAdvancedFilters) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: '重置筛选',
                        child: showResetLabel
                            ? TextButton.icon(
                                onPressed: reset,
                                icon: const Icon(Icons.restart_alt_rounded),
                                label: const Text('重置筛选'),
                              )
                            : IconButton(
                                onPressed: reset,
                                icon: const Icon(Icons.restart_alt_rounded),
                              ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          actions: [
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => PopupMenuButton<CategoryFilterLayout>(
                tooltip: '切换筛选视图',
                initialValue: _controller.filterLayout,
                onSelected: _selectFilterLayout,
                icon: Icon(_categoryLayoutIcon(_controller.filterLayout)),
                itemBuilder: (context) => [
                  for (final layout in CategoryFilterLayout.values)
                    PopupMenuItem(
                      value: layout,
                      child: Row(
                        children: [
                          Icon(_categoryLayoutIcon(layout)),
                          const SizedBox(width: 12),
                          Text(_categoryLayoutLabel(layout)),
                          const SizedBox(width: 16),
                          if (layout == _controller.filterLayout)
                            const Icon(Icons.check_rounded, size: 18),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: '搜索番剧',
              onPressed: () => context.pushNamed('/search/'),
              icon: const Icon(Icons.search_rounded),
            ),
          ],
        ),
        body: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const inset = StyleString.pageHorizontalPadding;
                final width = math.max(0.0, constraints.maxWidth - inset * 2);
                return ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) {
                    final sidebar =
                        _controller.filterLayout ==
                        CategoryFilterLayout.sidebar;
                    final expanded =
                        sidebar && _showExpandedSidebar(constraints.maxWidth);
                    if (expanded &&
                        (_scaffoldKey.currentState?.isEndDrawerOpen ?? false)) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          _scaffoldKey.currentState?.closeEndDrawer();
                        }
                      });
                    }
                    return Padding(
                      padding: EdgeInsets.symmetric(horizontal: inset),
                      child: expanded
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, results) =>
                                        _resultScroll(
                                          results.maxWidth,
                                          sidebar: true,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 20),
                                SizedBox(
                                  key: const ValueKey('category-sidebar'),
                                  width: _sidebarWidth,
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 24),
                                    child: _sidebar(),
                                  ),
                                ),
                              ],
                            )
                          : _resultScroll(width, sidebar: sidebar),
                    );
                  },
                );
              },
            ),
          ),
        ),
      );
    },
  );
}

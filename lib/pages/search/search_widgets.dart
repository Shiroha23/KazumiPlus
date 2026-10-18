part of 'search_page.dart';

const _searchSortLabels = {
  'heat': '热度',
  'rank': '排名',
  'score': '评分',
  'match': '匹配',
};

String _sortLabel(String sort) => _searchSortLabels[sort] ?? '热度';

String _filterSummary(SearchFilterState state) => [
      ...state.tags,
      ...state.metaTags,
      if (state.season.isNotEmpty) state.season,
      if (state.season.isEmpty && state.dateRange != null)
        '${state.dateRange!.start} 至 ${state.dateRange!.end}',
      if (state.scoreRange?.isValid == true)
        '评分 ${state.scoreRange!.toToken()}',
      if (state.rankRange?.isValid == true) '排名 ${state.rankRange!.toToken()}',
      if (state.weekdays.isNotEmpty)
        '周${state.weekdays.map((day) => '一二三四五六日'[day - 1]).join('、')}',
    ].join(' · ');

String _readableQuery(String query) {
  final state = SearchParser(query).toFilterState();
  final summary = _filterSummary(state);
  return [
    if (state.keyword.isNotEmpty) state.keyword,
    if (state.id.isNotEmpty) '条目 ${state.id}',
    if (summary.isNotEmpty) summary,
    if (state.sort != 'heat') '${_sortLabel(state.sort)}排序',
  ].join(' · ');
}

class _SearchSortMenu extends StatelessWidget {
  const _SearchSortMenu({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KazumiMenuButton(
      animated: true,
      menuChildren: [
        for (final sort in _searchSortLabels.entries)
          KazumiMenuItem(
            label: '按${sort.value}排序',
            selected: sort.key == value,
            onPressed: () => onChanged(sort.key),
          ),
      ],
      builder: (context, toggle) => Tooltip(
        message: '排序方式',
        child: TextButton.icon(
          onPressed: toggle,
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurfaceVariant,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          iconAlignment: IconAlignment.end,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          label: Text(_sortLabel(value)),
        ),
      ),
    );
  }
}

class _SearchLoadingState extends StatelessWidget {
  const _SearchLoadingState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
        child: Column(children: [
          const LoadingIndicator(size: 40),
          const SizedBox(height: 20),
          Semantics(
              liveRegion: true,
              child: Text('正在搜索番剧',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium)),
        ]));
  }
}

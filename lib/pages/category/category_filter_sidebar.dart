part of 'category_page.dart';

String _categoryLayoutLabel(CategoryFilterLayout layout) => switch (layout) {
  CategoryFilterLayout.rows => '分行视图',
  CategoryFilterLayout.dropdown => '下拉视图',
  CategoryFilterLayout.sidebar => '侧边栏视图',
};

IconData _categoryLayoutIcon(CategoryFilterLayout layout) => switch (layout) {
  CategoryFilterLayout.rows => Icons.view_stream_outlined,
  CategoryFilterLayout.dropdown => Icons.expand_circle_down_outlined,
  CategoryFilterLayout.sidebar => Icons.view_sidebar_outlined,
};

class _CategoryFilterSidebar extends StatelessWidget {
  const _CategoryFilterSidebar({
    required this.filters,
    required this.year,
    required this.onChanged,
    required this.onYearChanged,
    this.onClose,
  });

  final SearchFilterState filters;
  final String year;
  final ValueChanged<SearchFilterState> onChanged;
  final ValueChanged<String> onYearChanged;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(16),
    clipBehavior: Clip.antiAlias,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '筛选条件',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (onClose != null)
                IconButton(
                  tooltip: '收起筛选',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            key: const PageStorageKey('category-sidebar-scroll'),
            primary: false,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _options(
                  context,
                  '类型',
                  filters.metaTags.firstOrNull ?? '',
                  {
                    '': '全部',
                    for (final format in _categoryFormats)
                      format: switch (format) {
                        'TV' => 'TV番组',
                        '剧场版' => '剧场番组',
                        _ => format,
                      },
                  },
                  (value) => onChanged(
                    filters.copyWith(metaTags: value.isEmpty ? [] : [value]),
                  ),
                ),
                const SizedBox(height: 16),
                _options(
                  context,
                  '题材',
                  filters.tags.firstOrNull ?? '',
                  {
                    '': '全部',
                    for (final tag in {..._categoryTags, ...filters.tags})
                      tag: tag,
                  },
                  (value) => onChanged(
                    filters.copyWith(tags: value.isEmpty ? [] : [value]),
                  ),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  key: ValueKey('sidebar-year-$year'),
                  initialValue: year,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '放送年份'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('不限年份')),
                    for (var year = DateTime.now().year; year >= 1900; year--)
                      DropdownMenuItem(value: '$year', child: Text('$year 年')),
                  ],
                  onChanged: (value) => onYearChanged(value ?? ''),
                ),
                const SizedBox(height: 20),
                _options(
                  context,
                  '排序',
                  filters.sort,
                  _categorySortLabels,
                  (value) => onChanged(filters.copyWith(sort: value)),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _options(
    BuildContext context,
    String label,
    String selected,
    Map<String, String> options,
    ValueChanged<String> onSelected,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final option in options.entries)
              Semantics(
                selected: option.key == selected,
                inMutuallyExclusiveGroup: true,
                child: TextButton(
                  key: ValueKey('sidebar-$label-${option.key}'),
                  style: TextButton.styleFrom(
                    backgroundColor: option.key == selected
                        ? colors.secondaryContainer
                        : Colors.transparent,
                    foregroundColor: option.key == selected
                        ? colors.onSecondaryContainer
                        : colors.onSurfaceVariant,
                  ),
                  onPressed: () {
                    if (option.key != selected) onSelected(option.key);
                  },
                  child: Text(option.value),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

part of 'category_page.dart';

const _categoryFormats = ['TV', '剧场版', 'OVA', 'WEB', '动态漫画', '其他'];
const _categorySortLabels = {'heat': '近期热度', 'rank': '排名优先', 'score': '评分最高'};

class _CategoryFilterRows extends StatelessWidget {
  const _CategoryFilterRows({
    required this.filters,
    required this.year,
    required this.onChanged,
    required this.onYearChanged,
  });

  final SearchFilterState filters;
  final String year;
  final ValueChanged<SearchFilterState> onChanged;
  final ValueChanged<String> onYearChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CategoryFilterRow(
          label: '类型',
          value: filters.metaTags.firstOrNull ?? '',
          options: {
            '': '全部',
            for (final format in _categoryFormats)
              format: switch (format) {
                'TV' => 'TV番组',
                '剧场版' => '剧场番组',
                _ => format,
              },
          },
          onChanged: (value) => onChanged(
            filters.copyWith(metaTags: value.isEmpty ? [] : [value]),
          ),
        ),
        _CategoryFilterRow(
          label: '题材',
          value: filters.tags.firstOrNull ?? '',
          options: {
            '': '全部',
            for (final tag in {...defaultAnimeTags, ...filters.tags}) tag: tag,
          },
          onChanged: (value) =>
              onChanged(filters.copyWith(tags: value.isEmpty ? [] : [value])),
        ),
        _CategoryFilterRow(
          label: '年份',
          value: year,
          options: {
            '': '全部',
            for (var year = DateTime.now().year; year >= 1900; year--)
              '$year': '$year',
          },
          onChanged: onYearChanged,
        ),
        _CategoryFilterRow(
          label: '排序',
          value: filters.sort,
          options: _categorySortLabels,
          onChanged: (value) => onChanged(filters.copyWith(sort: value)),
        ),
      ],
    ),
  );
}

class _CategoryFilterRow extends StatefulWidget {
  const _CategoryFilterRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  State<_CategoryFilterRow> createState() => _CategoryFilterRowState();
}

class _CategoryFilterRowState extends State<_CategoryFilterRow> {
  final _selectedKey = GlobalKey();
  double? _availableWidth;

  @override
  void didUpdateWidget(covariant _CategoryFilterRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _revealSelection();
  }

  void _revealSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _selectedKey.currentContext;
      final target = context?.findRenderObject();
      if (context == null || target == null) return;
      // Reveal only within this horizontal row, leaving the results' vertical
      // scroll position untouched when the user switches filter layouts.
      Scrollable.of(
        context,
        axis: Axis.horizontal,
      ).position.ensureVisible(target, alignment: .5);
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (_availableWidth != constraints.maxWidth) {
        _availableWidth = constraints.maxWidth;
        _revealSelection();
      }
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final optionStyle = theme.textTheme.labelLarge;
      final height = math.max(
        48.0,
        MediaQuery.textScalerOf(context).scale(optionStyle?.fontSize ?? 14) *
                (optionStyle?.height ?? 1.5) +
            24,
      );
      final entries = widget.options.entries.toList(growable: false);
      return SizedBox(
        height: height,
        child: Row(
          children: [
            SizedBox(
              width: MediaQuery.textScalerOf(context).scale(32) + 24,
              child: Semantics(
                header: true,
                child: Text(
                  widget.label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Expanded(
              child: SmoothScroll(
                key: PageStorageKey('category-filter-row-${widget.label}'),
                builder: (context, controller) => ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    scrollbars: false,
                    dragDevices: {
                      ...ScrollConfiguration.of(context).dragDevices,
                      PointerDeviceKind.mouse,
                    },
                  ),
                  child: SingleChildScrollView(
                    controller: controller,
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      spacing: 8,
                      children: [
                        for (final option in entries)
                          Semantics(
                            key: option.key == widget.value
                                ? _selectedKey
                                : null,
                            selected: option.key == widget.value,
                            inMutuallyExclusiveGroup: true,
                            child: TextButton(
                              key: ValueKey(
                                'row-${widget.label}-${option.key}',
                              ),
                              onPressed: () {
                                if (option.key != widget.value) {
                                  widget.onChanged(option.key);
                                }
                              },
                              style: TextButton.styleFrom(
                                backgroundColor: option.key == widget.value
                                    ? colors.secondaryContainer
                                    : Colors.transparent,
                                foregroundColor: option.key == widget.value
                                    ? colors.onSecondaryContainer
                                    : colors.onSurfaceVariant,
                              ),
                              child: Text(option.value, maxLines: 1),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

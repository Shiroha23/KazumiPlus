import 'package:kazumi/bean/widget/smooth_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/widget/bangumi_mirror_error_widget.dart';
import 'package:kazumi/bean/widget/kazumi_menu.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/popular/popular_controller.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/services/logging/logger.dart';

class PopularPage extends StatefulWidget {
  const PopularPage({super.key, required this.controller});

  final PopularController controller;

  @override
  State<PopularPage> createState() => _PopularPageState();
}

class _PopularPageState extends State<PopularPage> {
  late final ScrollController scrollController;
  PopularController get popularController => widget.controller;

  @override
  void initState() {
    super.initState();
    scrollController = SmoothScrollController(
      initialScrollOffset: popularController.scrollOffset,
    );
    scrollController.addListener(scrollListener);
    if (popularController.trendList.isEmpty) {
      popularController.queryBangumiByTrend();
    }
  }

  @override
  void dispose() {
    scrollController.removeListener(scrollListener);
    scrollController.dispose();
    super.dispose();
  }

  void scrollListener() {
    popularController.scrollOffset = scrollController.offset;
    if (scrollController.position.pixels >=
            scrollController.position.maxScrollExtent - 200 &&
        !popularController.isLoadingMore) {
      KazumiLogger().i(
        'PopularPageController: Fetching next recommendation batch',
      );
      if (popularController.currentTag != '') {
        popularController.queryBangumiByTag();
      } else {
        popularController.queryBangumiByTrend();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrowPortrait =
            constraints.maxWidth < 600 &&
            constraints.maxHeight > constraints.maxWidth;
        return Scaffold(
          appBar: SysAppBar(
            needTopOffset: false,
            toolbarHeight: 72,
            title: buildTitle(narrowPortrait: narrowPortrait),
            actions: buildActions(),
          ),
          body: SafeArea(
            top: false,
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Observer(
                    builder: (_) => AnimatedOpacity(
                      opacity: popularController.isLoadingMore ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: popularController.isLoadingMore
                          ? const LinearProgressIndicator(minHeight: 4)
                          : const SizedBox(height: 4),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    StyleString.cardSpace,
                    0,
                    StyleString.cardSpace,
                    0,
                  ),
                  sliver: Observer(
                    builder: (_) {
                      if (popularController.isTimeOut) {
                        return SliverToBoxAdapter(
                          child: SizedBox(
                            height: 400,
                            child: BangumiMirrorErrorWidget(
                              onRetry: () {
                                if (popularController.trendList.isEmpty) {
                                  popularController.queryBangumiByTrend();
                                } else {
                                  popularController.queryBangumiByTag();
                                }
                              },
                              onSettingsReturned: () {
                                if (mounted) {
                                  setState(() {});
                                }
                              },
                            ),
                          ),
                        );
                      }
                      // Read the list contents inside Observer so async updates
                      // rebuild the grid, whose layout/children are built later.
                      final items = popularController.currentTag.isEmpty
                          ? popularController.trendList
                          : popularController.bangumiList;
                      return contentGrid(items.toList(growable: false));
                    },
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
            ),
            child: const Icon(Icons.arrow_upward),
          ),
        );
      },
    );
  }

  Widget contentGrid(List<BangumiItem> bangumiList) {
    int crossCount = 3;
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.compact['width']!) {
      crossCount = 5;
    }
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.medium['width']!) {
      crossCount = 6;
    }
    return SliverPadding(
      padding: const EdgeInsets.all(8),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          const spacing = 12.0;
          final cardWidth =
              (constraints.crossAxisExtent - spacing * (crossCount - 1)) /
                  crossCount;
          final titlePainter = TextPainter(
            text: TextSpan(
              text: '番剧',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
            ),
            textDirection: Directionality.of(context),
            textScaler:
                MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.1),
          );
          // Match BangumiContent's three title lines and vertical padding.
          final titleHeight =
              (titlePainter.preferredLineHeight * 3 + 4).ceilToDouble();
          titlePainter.dispose();
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              crossAxisCount: crossCount,
              mainAxisExtent: cardWidth / 0.65 + titleHeight,
            ),
            delegate:
                SliverChildBuilderDelegate((BuildContext context, int index) {
              return BangumiCardV(bangumiItem: bangumiList[index]);
            }, childCount: bangumiList.length),
          );
        },
      ),
    );
  }

  Widget buildTitle({required bool narrowPortrait}) {
    final theme = Theme.of(context);
    final style = narrowPortrait
        ? theme.textTheme.titleMedium
        : theme.textTheme.headlineSmall;
    return Observer(
      builder: (_) {
        final tag = popularController.currentTag;
        return KazumiMenuButton(
          animated: true,
          style: const MenuStyle(
            maximumSize: WidgetStatePropertyAll(Size(240, 350)),
          ),
          menuChildren: [
            for (final option in ['', ...defaultAnimeTags])
              KazumiMenuItem(
                label: option.isEmpty ? '热门番组' : option,
                selected: option == tag,
                onPressed: () => _selectTag(option),
              ),
          ],
          builder: (context, toggle) => Tooltip(
            message: '切换推荐分类',
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: toggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        tag.isEmpty ? '热门番组' : tag,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.expand_more_rounded, size: 20),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> buildActions() {
    return <Widget>[
      if (MediaQuery.of(context).orientation == Orientation.portrait)
        IconButton(
          tooltip: '搜索',
          onPressed: () => context.pushNamed('/search/'),
          icon: const Icon(Icons.search),
        ),
      IconButton(
        tooltip: '历史记录',
        onPressed: () => context.pushNamed('/settings/history/'),
        icon: const Icon(Icons.history),
      ),
    ];
  }

  Future<void> _selectTag(String selected) async {
    if (!mounted || selected == popularController.currentTag) return;
    scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    popularController.setCurrentTag(selected);
    if (selected.isEmpty) {
      popularController.clearBangumiList();
      if (popularController.trendList.isEmpty) {
        await popularController.queryBangumiByTrend();
      }
    } else {
      await popularController.queryBangumiByTag(type: 'init');
    }
  }
}

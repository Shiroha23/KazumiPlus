import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/video/episode_selection_panel.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/player/default_plugin_playback.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;

class InfoEpisodesView extends StatefulWidget {
  const InfoEpisodesView({
    super.key,
    required this.bangumiItem,
    required this.defaultPlugin,
    required this.isActive,
    required this.onChooseSource,
    required this.onPlay,
  });

  final BangumiItem bangumiItem;
  final Plugin? defaultPlugin;
  final bool isActive;
  final Future<OnlineVideoPlaybackArgs?> Function() onChooseSource;
  final ValueChanged<OnlineVideoPlaybackArgs> onPlay;

  @override
  State<InfoEpisodesView> createState() => _InfoEpisodesViewState();
}

class _InfoEpisodesViewState extends State<InfoEpisodesView>
    with AutomaticKeepAliveClientMixin {
  OnlineVideoPlaybackArgs? _args;
  RuleCancelToken? _cancelToken;
  bool _loading = false;
  bool _failed = false;
  bool _choosingSource = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _load();
  }

  @override
  void didUpdateWidget(covariant InfoEpisodesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bangumiItem.id != widget.bangumiItem.id ||
        oldWidget.defaultPlugin != widget.defaultPlugin) {
      _cancelToken?.cancel();
      _cancelToken = null;
      _args = null;
      _loading = false;
      _failed = false;
    }
    if (widget.isActive && _args == null && !_loading && !_failed) _load();
  }

  Future<void> _load() async {
    final plugin = widget.defaultPlugin;
    if (plugin == null || _loading || _choosingSource) return;
    final token = _cancelToken = RuleCancelToken();
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final args = await resolveDefaultPluginPlayback(
        plugin: plugin,
        bangumiItem: widget.bangumiItem,
        cancelToken: token,
      );
      if (!mounted || !identical(_cancelToken, token)) return;
      setState(() => _args = args);
    } catch (error, stackTrace) {
      if (!mounted || !identical(_cancelToken, token) || token.isCancelled) {
        return;
      }
      KazumiLogger().w(
        'InfoEpisodesView: failed to load episodes',
        error: error,
        stackTrace: stackTrace,
      );
      setState(() => _failed = true);
    } finally {
      if (mounted && identical(_cancelToken, token)) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _chooseSource() async {
    if (_choosingSource || _loading) return;
    setState(() => _choosingSource = true);
    try {
      final args = await widget.onChooseSource();
      if (!mounted || args == null) return;
      setState(() {
        _args = args;
        _failed = false;
      });
    } finally {
      if (mounted) setState(() => _choosingSource = false);
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final nested = context.findAncestorStateOfType<NestedScrollViewState>();
    final overlap = nested == null
        ? null
        : NestedScrollView.sliverOverlapAbsorberHandleFor(context);
    final args = _args;
    if (args != null) {
      return EpisodeSelectionPanel(
        key: ValueKey('${args.plugin.name}:${args.src}'),
        title: args.title,
        roads: args.roads,
        selectedRoad: 0,
        selectedEpisode: 0,
        downloads: const {},
        showDownloadButton: false,
        useEpisodeButtons: true,
        sourceName: args.plugin.name,
        onChangeSource: _choosingSource ? null : _chooseSource,
        disableAnimations: MediaQuery.disableAnimationsOf(context),
        leadingSlivers: [
          if (overlap != null) SliverOverlapInjector(handle: overlap),
        ],
        onEpisodeSelected: (episode, road) => widget.onPlay(
          OnlineVideoPlaybackArgs(
            bangumiItem: args.bangumiItem,
            plugin: args.plugin,
            title: args.title,
            src: args.src,
            roads: args.roads,
            initialEpisode: episode,
            initialRoad: road,
          ),
        ),
      );
    }
    return CustomScrollView(
      slivers: [
        if (overlap != null) SliverOverlapInjector(handle: overlap),
        SliverFillRemaining(
          hasScrollBody: false,
          child: _loading
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LoadingIndicator(),
                      SizedBox(height: 16),
                      Text('正在加载剧集'),
                    ],
                  ),
                )
              : GeneralEmptyState(
                  icon: _failed
                      ? Icons.error_outline_rounded
                      : Icons.video_library_outlined,
                  title: _failed ? '暂时无法加载剧集' : '选择播放来源以查看剧集',
                  actions: [
                    if (_failed)
                      StateActionButton.tonal(onPressed: _load, text: '重试'),
                    StateActionButton(
                      onPressed: _choosingSource ? null : _chooseSource,
                      text: '选择来源',
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;

/// Tries preferred rules in their configured order, stopping at the first source
/// with a usable playlist. Cancellation stops the whole chain.
Future<OnlineVideoPlaybackArgs> resolveDefaultPluginsPlayback({
  required Iterable<Plugin> plugins,
  required BangumiItem bangumiItem,
  RuleCancelToken? cancelToken,
}) async {
  Object? lastError;
  StackTrace? lastStackTrace;
  for (final plugin in List<Plugin>.of(plugins)) {
    if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
    try {
      return await resolveDefaultPluginPlayback(
        plugin: plugin,
        bangumiItem: bangumiItem,
        cancelToken: cancelToken,
      );
    } catch (error, stackTrace) {
      if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
      lastError = error;
      lastStackTrace = stackTrace;
      KazumiLogger().w('Default rule ${plugin.name} unavailable', error: error);
    }
  }
  if (lastError != null) Error.throwWithStackTrace(lastError, lastStackTrace!);
  throw StateError('No default rules configured');
}

/// Resolves the default rule directly into the existing player entry point.
Future<OnlineVideoPlaybackArgs> resolveDefaultPluginPlayback({
  required Plugin plugin,
  required BangumiItem bangumiItem,
  RuleCancelToken? cancelToken,
}) async {
  final keyword = bangumiItem.nameCn.isEmpty
      ? bangumiItem.name
      : bangumiItem.nameCn;
  final response = await plugin.queryBangumi(
    keyword,
    shouldRethrow: true,
    cancelToken: cancelToken,
  );
  if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
  final results = response.data.where((item) => item.src.trim().isNotEmpty);
  if (results.isEmpty) throw NoResultException(plugin.name);

  // Prefer an exact title match over related seasons returned by the site.
  final names = {bangumiItem.name, bangumiItem.nameCn, ...bangumiItem.alias}
      .map((name) => name.trim().toLowerCase())
      .where((name) => name.isNotEmpty)
      .toSet();
  final result = results.firstWhere(
    (item) => names.contains(item.name.trim().toLowerCase()),
    orElse: () => results.first,
  );
  final roads = await plugin.queryChapterRoads(
    result.src,
    cancelToken: cancelToken,
  );
  if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
  if (roads.isEmpty || roads.first.data.isEmpty) {
    throw ChapterErrorException(plugin.name);
  }
  return OnlineVideoPlaybackArgs(
    bangumiItem: bangumiItem,
    plugin: plugin,
    title: result.name,
    src: result.src,
    roads: roads,
  );
}

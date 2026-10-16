import 'package:dio/dio.dart';
import 'package:kazumi/plugins/playback_rule_config.dart';
import 'package:kazumi/services/plugin/api_rule_strategy.dart';
import 'package:kazumi/services/plugin/plugin_cookie_manager.dart';
import 'package:kazumi/services/plugin/rule_request_pipeline.dart';
import 'package:kazumi/services/video_source/video_source_format.dart';
import 'package:kazumi/services/video_source/video_source_service.dart';

class RulePlaybackService {
  static const _api = ApiRuleStrategy();

  static void validate(PlaybackRuleConfig config) {
    if (!config.enabled) return;
    RuleRequestPipeline.validate(
      pagePattern: config.pagePattern,
      steps: config.steps,
    );
    if (!{'auto', 'hls'}.contains(config.format)) {
      throw const FormatException('播放格式仅支持 auto/hls');
    }
    for (final stream in [
      config.video,
      if (config.audio != null) config.audio!,
    ]) {
      RestrictedJsonPath.validate(stream.urlPath);
      for (final path in [
        stream.listPath,
        stream.qualityPath,
        stream.bandwidthPath,
        stream.codecPath,
      ]) {
        if (path.isNotEmpty) RestrictedJsonPath.validate(path);
      }
      if (stream.preferredCodecs.isNotEmpty && stream.codecPath.isEmpty) {
        throw const FormatException('编码偏好需要配置 codecPath');
      }
      if (stream.maxQuality != null &&
          (!stream.maxQuality!.isFinite ||
              stream.maxQuality! < 0 ||
              stream.qualityPath.isEmpty)) {
        throw const FormatException('清晰度上限需要有效数值和 qualityPath');
      }
    }
  }

  static Future<VideoSource> resolve({
    required PlaybackRuleConfig config,
    required String pageUrl,
    required String pluginName,
    int episodeNumber = 1,
    int offset = 0,
    Map<String, String> httpHeaders = const {},
    CancelToken? cancelToken,
  }) async {
    validate(config);
    final result = await RuleRequestPipeline.execute(
      pageUrl: pageUrl,
      pluginName: pluginName,
      episodeNumber: episodeNumber,
      pagePattern: config.pagePattern,
      defaults: config.defaults,
      queryVariables: config.queryVariables,
      steps: config.steps,
      httpHeaders: httpHeaders,
      cancelToken: cancelToken,
    );
    final parsed = parse(
      result.raw,
      config,
      pageUrl: pageUrl,
      variables: result.variables,
      httpHeaders: httpHeaders,
      offset: offset,
    );
    final videoHeaders = await PluginCookieManager.instance.headersFor(
      pluginName,
      parsed.url,
      parsed.httpHeaders,
    );
    final audioHeaders = parsed.audioUrl == null
        ? <String, String>{}
        : await PluginCookieManager.instance.headersFor(
            pluginName,
            parsed.audioUrl!,
            parsed.audioHttpHeaders,
          );
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    return VideoSource(
      url: parsed.url,
      audioUrl: parsed.audioUrl,
      offset: offset,
      type: VideoSourceType.online,
      format: parsed.format,
      httpHeaders: videoHeaders,
      audioHttpHeaders: audioHeaders,
    );
  }

  static VideoSource parse(
    String raw,
    PlaybackRuleConfig config, {
    required String pageUrl,
    Map<String, Object?> variables = const {},
    Map<String, String> httpHeaders = const {},
    int offset = 0,
  }) {
    validate(config);
    final document = _api.decodeResponse(raw);
    final page = Uri.parse(pageUrl);
    final values = <String, Object?>{
      'pageUrl': pageUrl,
      'origin': page.origin,
      ...variables,
    };
    String select(PlaybackStreamConfig stream, String label) {
      final nodes = stream.listPath.isEmpty
          ? [document]
          : RestrictedJsonPath.read(document, stream.listPath);
      final candidates =
          <({String url, num quality, num bandwidth, int codec, int index})>[];
      for (var i = 0; i < nodes.length; i++) {
        final node = nodes[i];
        Object? read(String path) =>
            path.isEmpty ? null : RestrictedJsonPath.readFirst(node, path);
        final rawUrl = read(stream.urlPath);
        if (rawUrl is! String || rawUrl.trim().isEmpty) continue;
        final candidateUri = Uri.tryParse(rawUrl.trim());
        if (candidateUri == null) continue;
        final uri = page.resolveUri(candidateUri);
        if (!{'https', 'http'}.contains(uri.scheme) ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty) {
          continue;
        }
        num numeric(String path) {
          final value = num.tryParse('${read(path)}');
          return value != null && value.isFinite ? value : 0;
        }

        final quality = numeric(stream.qualityPath);
        if (stream.maxQuality != null && quality > stream.maxQuality!) continue;
        final codec = '${read(stream.codecPath)}'.toLowerCase();
        final rank = stream.preferredCodecs.indexWhere(
          (prefix) => codec.startsWith(prefix.toLowerCase()),
        );
        candidates.add((
          url: uri.toString(),
          quality: quality,
          bandwidth: numeric(stream.bandwidthPath),
          codec: rank < 0 ? stream.preferredCodecs.length : rank,
          index: i,
        ));
      }
      if (candidates.isEmpty) {
        throw FormatException('$label地址未匹配到有效的 HTTP/HTTPS 媒体');
      }
      candidates.sort((a, b) {
        var order = a.codec.compareTo(b.codec);
        if (order == 0) order = b.quality.compareTo(a.quality);
        if (order == 0) order = b.bandwidth.compareTo(a.bandwidth);
        return order == 0 ? a.index.compareTo(b.index) : order;
      });
      return candidates.first.url;
    }

    Map<String, String> headers(PlaybackStreamConfig stream) => {
      'referer': pageUrl,
      for (final entry in httpHeaders.entries)
        entry.key.toLowerCase(): entry.value,
      for (final entry in stream.headers.entries)
        entry.key.toLowerCase(): RuleRequestPipeline.render(
          '${entry.value}',
          values,
        ),
    };
    return VideoSource(
      url: select(config.video, '视频'),
      audioUrl: config.audio == null ? null : select(config.audio!, '音频'),
      offset: offset,
      type: VideoSourceType.online,
      format: config.format == 'hls'
          ? VideoSourceFormat.hls
          : VideoSourceFormat.auto,
      httpHeaders: headers(config.video),
      audioHttpHeaders: config.audio == null
          ? const {}
          : headers(config.audio!),
    );
  }
}

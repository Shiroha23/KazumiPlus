import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/plugins/danmaku_rule_config.dart';
import 'package:kazumi/services/plugin/api_rule_strategy.dart';
import 'package:kazumi/services/plugin/rule_request_pipeline.dart';

/// Executes website rules without knowing any site name, domain or endpoint.
class RuleDanmakuService {
  static final instance = RuleDanmakuService();
  static const _api = ApiRuleStrategy();

  static void validate(DanmakuRuleConfig config) {
    if (config.pagePattern.isNotEmpty) RegExp(config.pagePattern);
    if (!config.timeScale.isFinite || config.timeScale <= 0) {
      throw const FormatException('弹幕时间倍率必须大于 0');
    }
    if (!{'json', 'dplayer', 'bilibiliXml'}.contains(config.format)) {
      throw const FormatException('不支持的弹幕格式');
    }
    if (!config.enabled) return;
    if (config.steps.isEmpty) throw const FormatException('弹幕规则至少需要一个请求');
    if (config.format == 'bilibiliXml') {
      final last = config.steps.last;
      if (last.captures.isNotEmpty ||
          last.listPath.isNotEmpty ||
          last.successPath.isNotEmpty) {
        throw const FormatException('XML 最后一步不支持 JSON 提取');
      }
    }
    if (config.format != 'bilibiliXml') {
      for (final path in [
        config.listPath,
        config.contentPath,
        config.timePath,
        config.modePath,
        config.colorPath,
      ]) {
        if (path.isNotEmpty) RestrictedJsonPath.validate(path);
      }
    }
    for (final step in config.steps) {
      if (step.request.url.trim().isEmpty ||
          !{'GET', 'POST'}.contains(step.request.method.toUpperCase())) {
        throw const FormatException('弹幕请求需要 URL，并仅支持 GET/POST');
      }
      if (step.pageSize < 0) throw const FormatException('分页大小不能为负数');
      for (final path in [
        step.listPath,
        step.matchPath,
        step.successPath,
        ...step.captures.values,
      ]) {
        if (path.isNotEmpty) RestrictedJsonPath.validate(path);
      }
      for (final pattern in step.regexCaptures.values) {
        RegExp(pattern);
      }
    }
  }

  Future<List<DanmakuEntry>> fetch({
    required DanmakuRuleConfig config,
    required String pageUrl,
    required String pluginName,
    required int episodeNumber,
    String videoUrl = '',
    CancelToken? cancelToken,
  }) async {
    validate(config);
    if (!config.enabled) return [];
    final result = await RuleRequestPipeline.execute(
      pageUrl: pageUrl,
      pluginName: pluginName,
      episodeNumber: episodeNumber,
      steps: config.steps,
      pagePattern: config.pagePattern,
      defaults: config.defaults,
      queryVariables: config.queryVariables,
      videoUrl: videoUrl,
      finalIsXml: config.format == 'bilibiliXml',
      cancelToken: cancelToken,
    );
    return parse(result.raw, config, source: pluginName);
  }

  static List<DanmakuEntry> parse(
    String raw,
    DanmakuRuleConfig config, {
    required String source,
  }) {
    validate(config);
    final result = <DanmakuEntry>[];
    if (config.format == 'bilibiliXml') {
      final document = html.parse(raw);
      if (document.querySelector('i') == null) {
        throw const FormatException('弹幕 XML 无效');
      }
      final nodes = document.querySelectorAll('d');
      for (final element in nodes) {
        final fields = (element.attributes['p'] ?? '').split(',');
        if (fields.length < 4) continue;
        _add(
          result,
          config,
          source,
          element.text,
          fields[0],
          fields[1],
          fields[3],
        );
      }
      if (nodes.isNotEmpty && result.isEmpty) {
        throw const FormatException('XML 中没有有效的弹幕条目');
      }
    } else {
      final document = _api.decodeResponse(raw);
      final nodes = RestrictedJsonPath.read(document, config.listPath);
      if (nodes.isEmpty && config.listPath.endsWith('[*]')) {
        final containers = RestrictedJsonPath.read(
          document,
          config.listPath.substring(0, config.listPath.length - 3),
        );
        if (!containers.any((value) => value is List || value is Map)) {
          throw const FormatException('弹幕列表路径未匹配');
        }
      }
      for (final node in nodes) {
        Object? read(String path) =>
            path.isEmpty ? null : RestrictedJsonPath.readFirst(node, path);
        _add(
          result,
          config,
          source,
          read(config.contentPath),
          read(config.timePath),
          read(config.modePath),
          read(config.colorPath),
        );
      }
      if (nodes.isNotEmpty && result.isEmpty) {
        throw const FormatException('弹幕字段映射未匹配到有效数据');
      }
    }
    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
  }

  static void _add(
    List<DanmakuEntry> result,
    DanmakuRuleConfig config,
    String source,
    Object? content,
    Object? time,
    Object? mode,
    Object? color,
  ) {
    final seconds =
        (num.tryParse('$time')?.toDouble() ?? double.nan) * config.timeScale;
    if (content is! String ||
        content.trim().isEmpty ||
        !seconds.isFinite ||
        seconds < 0) {
      return;
    }
    final type =
        config.modeMap['$mode'] ??
        switch ('$mode') {
          'top' || '5' => 5,
          'bottom' || '4' => 4,
          _ => 1,
        };
    final textColor = '$color';
    final rgb = color is num && color.isFinite
        ? color.toInt()
        : textColor.startsWith('#')
        ? int.tryParse(textColor.substring(1), radix: 16)
        : int.tryParse(textColor);
    result.add(
      DanmakuEntry(
        message: content.trim(),
        time: seconds,
        type: {1, 4, 5}.contains(type) ? type : 1,
        color: Color(0xff000000 | (rgb ?? 0xffffff).clamp(0, 0xffffff)),
        source: '[$source]',
      ),
    );
  }
}

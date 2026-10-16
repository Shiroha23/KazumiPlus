import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/plugins/danmaku_rule_config.dart';
import 'package:kazumi/request/clients/plugin_site_client.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/plugin/api_rule_strategy.dart';
import 'package:kazumi/services/plugin/plugin_cookie_manager.dart';

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
    final page = Uri.tryParse(pageUrl);
    if (page == null ||
        !{'http', 'https'}.contains(page.scheme) ||
        page.host.isEmpty) {
      throw const FormatException('弹幕规则需要有效的播放页 URL');
    }
    final variables = <String, Object?>{
      ...config.defaults,
      'pageUrl': pageUrl,
      'origin': page.origin,
      'videoUrl': videoUrl,
      'episodeNumber': episodeNumber,
    };
    if (config.pagePattern.isNotEmpty) {
      final match = RegExp(config.pagePattern).firstMatch(pageUrl);
      if (match == null) throw const FormatException('弹幕播放页正则未匹配');
      for (final name in match.groupNames) {
        if (match.namedGroup(name) != null) {
          variables[name] = match.namedGroup(name);
        }
      }
    }
    final number = int.tryParse('${variables['episodeNumber']}');
    if (number == null || number < 1) throw const FormatException('弹幕集数无效');
    variables['episodeNumber'] = number;
    variables['episodeIndex'] = number - 1;
    for (final entry in config.queryVariables.entries) {
      final value = page.queryParameters[entry.value];
      if (value != null && value.isNotEmpty) variables[entry.key] = value;
    }

    var raw = '';
    for (var i = 0; i < config.steps.length; i++) {
      final step = config.steps[i];
      _checkCancelled(cancelToken);
      if (step.pageSize > 0) {
        variables['pageNumber'] = (number - 1) ~/ step.pageSize + 1;
        variables['pageIndex'] = (number - 1) % step.pageSize;
      }
      final requestJson = step.request.toJson();
      var url = step.request.url.trim();
      if (RegExp(r'^@[A-Za-z_][A-Za-z0-9_]*$').hasMatch(url)) {
        // Whole captured URLs already contain their own escaping.
        url = _render(url, variables);
      } else if (url.startsWith('@origin/')) {
        url = page.origin + url.substring('@origin'.length);
      }
      if (url.startsWith('/')) url = page.resolve(url).toString();
      final request = _api.prepareRequest(
        ApiRequestConfig.fromJson({...requestJson, 'url': url}),
        variables,
      );
      if (!{'http', 'https'}.contains(Uri.parse(request.url).scheme)) {
        throw const FormatException('弹幕请求只支持 HTTP/HTTPS');
      }
      final headers = await PluginCookieManager.instance
          .headersFor(pluginName, request.url, {
            'referer': pageUrl,
            for (final entry in request.headers.entries)
              entry.key.toLowerCase(): entry.value.toString(),
          });
      if (request.bodyType != ApiBodyType.none) {
        headers.putIfAbsent(
          'content-type',
          () => request.bodyType == ApiBodyType.form
              ? 'application/x-www-form-urlencoded'
              : 'application/json',
        );
      }
      raw = await PluginSiteClient.instance.requestText(
        request.url,
        method: request.method,
        headers: headers,
        queryParameters: request.query,
        data: request.body,
        cancelToken: cancelToken,
      );
      _checkCancelled(cancelToken);
      final last = i == config.steps.length - 1;
      for (final entry in step.regexCaptures.entries) {
        final match = RegExp(entry.value).firstMatch(raw);
        if (match == null || match.groupCount < 1 || match.group(1) == null) {
          throw FormatException('弹幕正则未提取到变量 ${entry.key}');
        }
        variables[entry.key] = match.group(1);
      }
      if (!last &&
          step.captures.isEmpty &&
          step.listPath.isEmpty &&
          step.successPath.isEmpty) {
        continue;
      }
      if (last && config.format == 'bilibiliXml') {
        if (step.captures.isNotEmpty ||
            step.successPath.isNotEmpty ||
            step.listPath.isNotEmpty) {
          throw const FormatException('XML 最后一步不支持 JSON 提取');
        }
        continue;
      }
      final document = _api.decodeResponse(raw);
      if (step.successPath.isNotEmpty &&
          '${RestrictedJsonPath.readFirst(document, step.successPath)}' !=
              '${step.successValue}') {
        throw const FormatException('弹幕接口报告请求失败');
      }
      Object? selected = document;
      if (step.listPath.isNotEmpty) {
        final nodes = RestrictedJsonPath.read(document, step.listPath);
        final value = _render(step.matchValue, variables);
        var hasOrder = false;
        selected = null;
        if (step.matchPath.isNotEmpty) {
          for (final node in nodes) {
            final order = RestrictedJsonPath.readFirst(node, step.matchPath);
            hasOrder |= order != null;
            if (order != null && '$order' == value) {
              selected = node;
              break;
            }
          }
        }
        if (selected == null && !hasOrder) {
          final index = int.tryParse(_render(step.index, variables));
          if (index != null && index >= 0 && index < nodes.length) {
            selected = nodes[index];
          }
        }
        if (selected == null) throw const FormatException('弹幕预请求未找到对应集数');
      }
      for (final entry in step.captures.entries) {
        final value = RestrictedJsonPath.readFirst(selected, entry.value);
        if (value == null) throw FormatException('弹幕预请求缺少变量 ${entry.key}');
        variables[entry.key] = value;
      }
    }
    return parse(raw, config, source: pluginName);
  }

  static String _render(String template, Map<String, Object?> variables) =>
      template.replaceAllMapped(RegExp(r'@([A-Za-z_][A-Za-z0-9_]*)'), (match) {
        final name = match.group(1)!;
        if (!variables.containsKey(name)) {
          throw FormatException('缺少弹幕变量 @$name');
        }
        return '${variables[name]}';
      });

  static void _checkCancelled(CancelToken? token) {
    if (token != null && token.isCancelled) {
      throw NetworkException(
        type: NetworkExceptionType.cancel,
        message: '请求已被取消，请重新请求',
        rawError: token.cancelError,
      );
    }
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

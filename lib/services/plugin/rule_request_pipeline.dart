import 'package:dio/dio.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/plugins/rule_request_step.dart';
import 'package:kazumi/request/clients/plugin_site_client.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/plugin/api_rule_strategy.dart';
import 'package:kazumi/services/plugin/plugin_cookie_manager.dart';

class RuleRequestResult {
  final String raw;
  final Map<String, Object?> variables;
  RuleRequestResult(this.raw, this.variables);
}

/// Shared HTTP/JSON/HTML request steps for media and danmaku rules.
class RuleRequestPipeline {
  static const _api = ApiRuleStrategy();

  static void validate({
    required String pagePattern,
    required List<RuleRequestStep> steps,
  }) {
    if (pagePattern.isNotEmpty) RegExp(pagePattern);
    if (steps.isEmpty) throw const FormatException('规则至少需要一个请求');
    for (final step in steps) {
      if (step.request.url.trim().isEmpty ||
          !{'GET', 'POST'}.contains(step.request.method.toUpperCase())) {
        throw const FormatException('规则请求需要 URL，并仅支持 GET/POST');
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

  static Future<RuleRequestResult> execute({
    required String pageUrl,
    required String pluginName,
    required int episodeNumber,
    required List<RuleRequestStep> steps,
    String pagePattern = '',
    Map<String, dynamic> defaults = const {},
    Map<String, String> queryVariables = const {},
    String videoUrl = '',
    Map<String, String> httpHeaders = const {},
    bool finalIsXml = false,
    CancelToken? cancelToken,
  }) async {
    final page = Uri.tryParse(pageUrl);
    if (page == null ||
        !{'http', 'https'}.contains(page.scheme) ||
        page.host.isEmpty) {
      throw const FormatException('规则需要有效的播放页 URL');
    }
    final variables = <String, Object?>{
      ...defaults,
      'pageUrl': pageUrl,
      'origin': page.origin,
      'videoUrl': videoUrl,
      'episodeNumber': episodeNumber,
    };
    if (pagePattern.isNotEmpty) {
      final match = RegExp(pagePattern).firstMatch(pageUrl);
      if (match == null) throw const FormatException('规则播放页正则未匹配');
      for (final name in match.groupNames) {
        if (match.namedGroup(name) != null) {
          variables[name] = match.namedGroup(name);
        }
      }
    }
    final number = int.tryParse('${variables['episodeNumber']}');
    if (number == null || number < 1) throw const FormatException('规则集数无效');
    variables['episodeNumber'] = number;
    variables['episodeIndex'] = number - 1;
    for (final entry in queryVariables.entries) {
      final value = page.queryParameters[entry.value];
      if (value != null && value.isNotEmpty) variables[entry.key] = value;
    }

    var raw = '';
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      _checkCancelled(cancelToken);
      if (step.pageSize > 0) {
        variables['pageNumber'] = (number - 1) ~/ step.pageSize + 1;
        variables['pageIndex'] = (number - 1) % step.pageSize;
      }
      final requestJson = step.request.toJson();
      var url = step.request.url.trim();
      final completeUrl = RegExp(r'^@[A-Za-z_][A-Za-z0-9_]*$').hasMatch(url);
      if (completeUrl) {
        // Whole captured URLs already contain their own escaping.
        url = render(url, variables);
      } else if (url.startsWith('@origin/')) {
        url = page.origin + url.substring('@origin'.length);
      }
      if (url.startsWith('/')) url = page.resolve(url).toString();
      final request = _api.prepareRequest(
        ApiRequestConfig.fromJson({...requestJson, 'url': url}),
        variables,
        resolvedUrl: completeUrl ? url : null,
      );
      if (!{'http', 'https'}.contains(Uri.parse(request.url).scheme)) {
        throw const FormatException('规则请求只支持 HTTP/HTTPS');
      }
      final headers = await PluginCookieManager.instance
          .headersFor(pluginName, request.url, {
            'referer': pageUrl,
            for (final entry in httpHeaders.entries)
              entry.key.toLowerCase(): entry.value,
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
      final last = i == steps.length - 1;
      for (final entry in step.regexCaptures.entries) {
        final match = RegExp(entry.value).firstMatch(raw);
        if (match == null || match.groupCount < 1 || match.group(1) == null) {
          throw FormatException('规则正则未提取到变量 ${entry.key}');
        }
        variables[entry.key] = match.group(1);
      }
      if (!last &&
          step.captures.isEmpty &&
          step.listPath.isEmpty &&
          step.successPath.isEmpty) {
        continue;
      }
      if (last && finalIsXml) {
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
        throw const FormatException('规则接口报告请求失败');
      }
      Object? selected = document;
      if (step.listPath.isNotEmpty) {
        final nodes = RestrictedJsonPath.read(document, step.listPath);
        final value = render(step.matchValue, variables);
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
          final index = int.tryParse(render(step.index, variables));
          if (index != null && index >= 0 && index < nodes.length) {
            selected = nodes[index];
          }
        }
        if (selected == null) throw const FormatException('规则预请求未找到对应集数');
      }
      for (final entry in step.captures.entries) {
        final value = RestrictedJsonPath.readFirst(selected, entry.value);
        if (value == null) throw FormatException('规则预请求缺少变量 ${entry.key}');
        variables[entry.key] = value;
      }
    }
    return RuleRequestResult(raw, variables);
  }

  static String render(String template, Map<String, Object?> variables) =>
      template.replaceAllMapped(RegExp(r'@([A-Za-z_][A-Za-z0-9_]*)'), (match) {
        final name = match.group(1)!;
        if (!variables.containsKey(name)) {
          throw FormatException('缺少规则变量 @$name');
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
}

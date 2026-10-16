import 'package:kazumi/plugins/api_rule_config.dart';

/// Optional website danmaku rules; absent rules retain DanDanPlay behavior.
class DanmakuRuleConfig {
  DanmakuRuleConfig({
    this.enabled = true,
    this.pagePattern = '',
    Map<String, dynamic>? defaults,
    Map<String, String>? queryVariables,
    List<DanmakuRequestStep>? steps,
    this.format = 'json',
    this.listPath = r'$.data[*]',
    this.contentPath = r'$.content',
    this.timePath = r'$.time',
    this.modePath = r'$.mode',
    this.colorPath = r'$.color',
    Map<String, int>? modeMap,
    this.timeScale = 1,
  }) : defaults = defaults ?? {},
       queryVariables = queryVariables ?? {},
       steps = steps ?? [],
       modeMap = modeMap ?? {};

  final bool enabled;
  final String pagePattern;
  final Map<String, dynamic> defaults;
  final Map<String, String> queryVariables;
  final List<DanmakuRequestStep> steps;
  final String format;
  final String listPath;
  final String contentPath;
  final String timePath;
  final String modePath;
  final String colorPath;
  final Map<String, int> modeMap;
  final double timeScale;

  factory DanmakuRuleConfig.fromJson(Map<String, dynamic> json) {
    final format = json['format'] as String? ?? 'json';
    final dplayer = format == 'dplayer';
    return DanmakuRuleConfig(
      enabled: json['enabled'] as bool? ?? true,
      pagePattern: json['pagePattern'] as String? ?? '',
      defaults: _map(json['defaults']),
      queryVariables: _map(json['queryVariables']).cast<String, String>(),
      steps: (json['steps'] as List? ?? [])
          .map((step) => DanmakuRequestStep.fromJson(_map(step)))
          .toList(),
      format: format,
      listPath: json['listPath'] as String? ?? r'$.data[*]',
      contentPath:
          json['contentPath'] as String? ?? (dplayer ? r'$[4]' : r'$.content'),
      timePath: json['timePath'] as String? ?? (dplayer ? r'$[0]' : r'$.time'),
      modePath: json['modePath'] as String? ?? (dplayer ? r'$[1]' : r'$.mode'),
      colorPath:
          json['colorPath'] as String? ?? (dplayer ? r'$[2]' : r'$.color'),
      modeMap: json['modeMap'] is Map
          ? _map(json['modeMap']).map((k, v) => MapEntry(k, (v as num).toInt()))
          : (dplayer ? {'0': 1, '1': 5, '2': 4} : {}),
      timeScale: (json['timeScale'] as num?)?.toDouble() ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    if (pagePattern.isNotEmpty) 'pagePattern': pagePattern,
    if (defaults.isNotEmpty) 'defaults': defaults,
    if (queryVariables.isNotEmpty) 'queryVariables': queryVariables,
    'steps': steps.map((step) => step.toJson()).toList(),
    'format': format,
    'listPath': listPath,
    'contentPath': contentPath,
    'timePath': timePath,
    'modePath': modePath,
    'colorPath': colorPath,
    if (modeMap.isNotEmpty) 'modeMap': modeMap,
    'timeScale': timeScale,
  };
}

class DanmakuRequestStep {
  DanmakuRequestStep({
    required this.request,
    Map<String, String>? captures,
    Map<String, String>? regexCaptures,
    this.listPath = '',
    this.matchPath = '',
    this.matchValue = '@episodeNumber',
    this.index = '@episodeIndex',
    this.pageSize = 0,
    this.successPath = '',
    this.successValue = 0,
  }) : captures = captures ?? {},
       regexCaptures = regexCaptures ?? {};

  final ApiRequestConfig request;
  final Map<String, String> captures;
  final Map<String, String> regexCaptures;
  final String listPath;
  final String matchPath;
  final String matchValue;
  final String index;
  final int pageSize;
  final String successPath;
  final Object? successValue;

  factory DanmakuRequestStep.fromJson(Map<String, dynamic> json) =>
      DanmakuRequestStep(
        request: ApiRequestConfig.fromJson(_map(json['request'])),
        captures: _map(json['captures']).cast<String, String>(),
        regexCaptures: _map(json['regexCaptures']).cast<String, String>(),
        listPath: json['listPath'] as String? ?? '',
        matchPath: json['matchPath'] as String? ?? '',
        matchValue: json['matchValue']?.toString() ?? '@episodeNumber',
        index: json['index']?.toString() ?? '@episodeIndex',
        pageSize: (json['pageSize'] as num?)?.toInt() ?? 0,
        successPath: json['successPath'] as String? ?? '',
        successValue: json.containsKey('successValue')
            ? json['successValue']
            : 0,
      );

  Map<String, dynamic> toJson() => {
    'request': request.toJson(),
    if (captures.isNotEmpty) 'captures': captures,
    if (regexCaptures.isNotEmpty) 'regexCaptures': regexCaptures,
    if (listPath.isNotEmpty) ...{
      'listPath': listPath,
      'index': index,
      if (matchPath.isNotEmpty) ...{
        'matchPath': matchPath,
        'matchValue': matchValue,
      },
    },
    if (pageSize > 0) 'pageSize': pageSize,
    if (successPath.isNotEmpty) ...{
      'successPath': successPath,
      'successValue': successValue,
    },
  };
}

Map<String, dynamic> _map(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : {};

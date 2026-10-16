import 'package:kazumi/plugins/rule_request_step.dart';

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

typedef DanmakuRequestStep = RuleRequestStep;

Map<String, dynamic> _map(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : {};

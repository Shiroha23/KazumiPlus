import 'package:kazumi/plugins/api_rule_config.dart';

class RuleRequestStep {
  RuleRequestStep({
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

  factory RuleRequestStep.fromJson(Map<String, dynamic> json) =>
      RuleRequestStep(
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

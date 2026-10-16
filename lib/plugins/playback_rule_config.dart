import 'package:kazumi/plugins/rule_request_step.dart';

/// Declarative HTTP playback resolution, independent of a particular website.
class PlaybackRuleConfig {
  final bool enabled;
  final String pagePattern;
  final Map<String, dynamic> defaults;
  final Map<String, String> queryVariables;
  final List<RuleRequestStep> steps;
  final PlaybackStreamConfig video;
  final PlaybackStreamConfig? audio;
  final String format;

  PlaybackRuleConfig({
    this.enabled = true,
    this.pagePattern = '',
    Map<String, dynamic>? defaults,
    Map<String, String>? queryVariables,
    List<RuleRequestStep>? steps,
    required this.video,
    this.audio,
    this.format = 'auto',
  }) : defaults = defaults ?? {},
       queryVariables = queryVariables ?? {},
       steps = steps ?? [];

  factory PlaybackRuleConfig.fromJson(Map<String, dynamic> json) =>
      PlaybackRuleConfig(
        enabled: json['enabled'] as bool? ?? true,
        pagePattern: json['pagePattern'] as String? ?? '',
        defaults: _map(json['defaults']),
        queryVariables: _map(json['queryVariables']).cast<String, String>(),
        steps: (json['steps'] as List? ?? [])
            .map((step) => RuleRequestStep.fromJson(_map(step)))
            .toList(),
        video: PlaybackStreamConfig.fromJson(_map(json['video'])),
        audio: json['audio'] is Map
            ? PlaybackStreamConfig.fromJson(_map(json['audio']))
            : null,
        format: json['format'] as String? ?? 'auto',
      );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    if (pagePattern.isNotEmpty) 'pagePattern': pagePattern,
    if (defaults.isNotEmpty) 'defaults': defaults,
    if (queryVariables.isNotEmpty) 'queryVariables': queryVariables,
    'steps': steps.map((step) => step.toJson()).toList(),
    'video': video.toJson(),
    if (audio != null) 'audio': audio!.toJson(),
    'format': format,
  };
}

class PlaybackStreamConfig {
  /// Empty selects the response root; otherwise selects candidate streams.
  final String listPath;
  final String urlPath;
  final String qualityPath;
  final String bandwidthPath;
  final String codecPath;
  final List<String> preferredCodecs;
  final num? maxQuality;
  final Map<String, dynamic> headers;

  PlaybackStreamConfig({
    this.listPath = '',
    this.urlPath = r'$.url',
    this.qualityPath = '',
    this.bandwidthPath = '',
    this.codecPath = '',
    this.preferredCodecs = const [],
    this.maxQuality,
    Map<String, dynamic>? headers,
  }) : headers = headers ?? {};

  factory PlaybackStreamConfig.fromJson(Map<String, dynamic> json) =>
      PlaybackStreamConfig(
        listPath: json['listPath'] as String? ?? '',
        urlPath: json['urlPath'] as String? ?? r'$.url',
        qualityPath: json['qualityPath'] as String? ?? '',
        bandwidthPath: json['bandwidthPath'] as String? ?? '',
        codecPath: json['codecPath'] as String? ?? '',
        preferredCodecs: (json['preferredCodecs'] as List? ?? [])
            .cast<String>(),
        maxQuality: json['maxQuality'] as num?,
        headers: _map(json['headers']),
      );

  Map<String, dynamic> toJson() => {
    'listPath': listPath,
    'urlPath': urlPath,
    if (qualityPath.isNotEmpty) 'qualityPath': qualityPath,
    if (bandwidthPath.isNotEmpty) 'bandwidthPath': bandwidthPath,
    if (codecPath.isNotEmpty) 'codecPath': codecPath,
    if (preferredCodecs.isNotEmpty) 'preferredCodecs': preferredCodecs,
    if (maxQuality != null) 'maxQuality': maxQuality,
    if (headers.isNotEmpty) 'headers': headers,
  };
}

Map<String, dynamic> _map(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : {};

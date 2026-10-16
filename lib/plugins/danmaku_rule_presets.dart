import 'package:kazumi/plugins/danmaku_rule_config.dart';

/// Generic format examples for the rule editor.
abstract final class DanmakuRulePresets {
  static DanmakuRuleConfig json() => DanmakuRuleConfig.fromJson({
    'steps': [
      {
        'request': {
          'url': '/api/danmaku',
          'query': {'episode': '@episodeNumber'},
        },
      },
    ],
    'listPath': r'$.data[*]',
    'contentPath': r'$.content',
    'timePath': r'$.time',
  });

  static DanmakuRuleConfig dplayer() => DanmakuRuleConfig.fromJson({
    'format': 'dplayer',
    'steps': [
      {
        'request': {
          'url': '/v3/',
          'query': {'id': '@episodeNumber'},
        },
      },
    ],
  });

  static DanmakuRuleConfig bilibiliXml() => DanmakuRuleConfig.fromJson({
    'format': 'bilibiliXml',
    'steps': [
      {
        'request': {'url': '/danmaku/@episodeNumber.xml'},
      },
    ],
  });
}

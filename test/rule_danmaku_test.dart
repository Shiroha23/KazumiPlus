import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'package:kazumi/plugins/danmaku_rule_config.dart';
import 'package:kazumi/plugins/danmaku_rule_presets.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/pages/plugin_editor/plugin_editor_page.dart';
import 'package:kazumi/pages/plugin_editor/editor_form_widgets.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/danmaku/rule_danmaku_service.dart';
import 'package:kazumi/services/plugin/plugin_cookie_manager.dart';
import 'package:kazumi/services/plugin/plugin_import_parser.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

const _page = 'https://unrelated.example/anime/3946/play/1?from=source-a';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPaths;
  late _Adapter adapter;

  setUpAll(() async {
    Logger.level = Level.off;
    directory = await Directory.systemTemp.createTemp('kazumi_rule_danmaku_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });
  setUp(() {
    DioFactory.reset();
    adapter = _Adapter();
    DioFactory.pluginDio.httpClientAdapter.close();
    DioFactory.pluginDio.httpClientAdapter = adapter;
  });
  tearDownAll(() async {
    DioFactory.reset();
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    expect(
      directory.absolute.path.startsWith(Directory.systemTemp.absolute.path),
      isTrue,
    );
    expect(
      directory.uri.pathSegments.where((part) => part.isNotEmpty).last,
      startsWith('kazumi_rule_danmaku_'),
    );
    await directory.delete(recursive: true);
  });

  test(
    'rules without explicit danmaku configuration never inject site defaults',
    () {
      for (final url in [
        'https://example.com',
        'https://www.cycani.org',
        'https://cycani.org',
      ]) {
        final plugin = Plugin.fromJson({'baseURL': url});
        expect(plugin.danmakuConfig, isNull);
        expect(Plugin.fromJson(plugin.toJson()).danmakuConfig, isNull);
      }
    },
  );

  test('all optional rule fields survive JSON and sharing import/export', () {
    final config = _multiStepConfig();
    final plugin = Plugin.fromTemplate()
      ..api = '9'
      ..name = 'unrelated'
      ..danmakuConfig = config;
    final json = plugin.toJson();
    expect(json['api'], '10');
    expect(Plugin.fromJson(json).danmakuConfig!.toJson(), config.toJson());
    final imported = PluginImportParser.parse(jsonEncode(json)).plugins.single;
    expect(imported.danmakuConfig!.toJson(), config.toJson());
    final disabled = DanmakuRuleConfig.fromJson({
      ...config.toJson(),
      'enabled': false,
    });
    plugin.danmakuConfig = disabled;
    expect(Plugin.fromJson(plugin.toJson()).danmakuConfig!.enabled, isFalse);
  });

  test(
    'a multi-step configuration works on a completely different domain',
    () async {
      final result = await _fetch(_multiStepConfig());
      expect(result.single.source, '[自定义规则]');
      expect(result.single.time, 1.418);
      expect(adapter.requests.first.uri.host, 'unrelated.example');
      expect(adapter.requests.first.uri.path, '/api/videos/3946/sections');
      expect(adapter.requests.first.uri.queryParameters, {
        'player_code': 'source-a',
        'page': '1',
        'page_size': '100',
      });
      expect(adapter.requests.last.uri.path, '/api/sections/52408/danmaku');
      expect(adapter.requests.last.headers['referer'], _page);
    },
  );

  test(
    'paged lookup carries the line and selects the explicit episode order',
    () async {
      adapter.sections = {
        'list': [
          {'id': 90001, 'order': 101},
        ],
      };
      await _fetch(
        _multiStepConfig(),
        page: _page.replaceFirst('/play/1', '/play/101'),
      );
      expect(adapter.requests.first.uri.queryParameters['page'], '2');
      expect(adapter.requests.last.uri.path, '/api/sections/90001/danmaku');
    },
  );

  test(
    'lookup indexes the current page if the response omits episode order',
    () async {
      adapter.sections = {
        'list': [
          {'id': 90001},
        ],
      };
      await _fetch(
        _multiStepConfig(),
        page: _page.replaceFirst('/play/1', '/play/101'),
      );
      expect(adapter.requests.last.uri.path, '/api/sections/90001/danmaku');
    },
  );

  test(
    'never guesses a section when an explicit order does not match',
    () async {
      adapter.sections = {
        'list': [
          {'id': 52408, 'order': 99},
        ],
      };
      await expectLater(_fetch(_multiStepConfig()), throwsFormatException);
      expect(adapter.requests, hasLength(1));
    },
  );

  test('uses GET/POST templates and keeps body/query values typed', () async {
    adapter.respond = (_) => jsonEncode({
      'rows': [
        {'text': 'POST', 'at': 2500},
      ],
    });
    final config = DanmakuRuleConfig.fromJson({
      'steps': [
        {
          'request': {
            'method': 'POST',
            'url': '/custom',
            'bodyType': 'json',
            'body': {'episode': '@episodeNumber', 'video': '@videoUrl'},
            'headers': {'X-Source': '@pageUrl'},
            'query': {'q': '中文 空格'},
          },
        },
      ],
      'listPath': r'$.rows[*]',
      'contentPath': r'$.text',
      'timePath': r'$.at',
      'timeScale': .001,
      'modePath': '',
      'colorPath': '',
    });
    final result = await _fetch(
      config,
      episode: 3,
      videoUrl: 'https://media.example/a.m3u8',
    );
    expect(result.single.time, 2.5);
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.data, {
      'episode': 3,
      'video': 'https://media.example/a.m3u8',
    });
    expect(adapter.requests.single.headers['x-source'], _page);
    expect(adapter.requests.single.uri.queryParameters['q'], '中文 空格');
  });

  test(
    'pre-requests can extract an HTML ID and then a full URL from JSON',
    () async {
      adapter.respond = (request) => switch (request.uri.path) {
        '/anime/3946/play/1' => '<div data-id="abc def"></div>',
        '/resolve/abc%20def' => jsonEncode({
          'url': 'https://other.example/comments?key=a%2Fb',
        }),
        _ => jsonEncode({
          'data': [_comment()],
        }),
      };
      final config = DanmakuRuleConfig.fromJson({
        'steps': [
          {
            'request': {'url': '@pageUrl'},
            'regexCaptures': {'id': 'data-id="([^"]+)"'},
          },
          {
            'request': {'url': '/resolve/@id'},
            'captures': {'commentsUrl': r'$.url'},
          },
          {
            'request': {'url': '@commentsUrl'},
          },
        ],
        'timePath': r'$.time_point',
      });
      final entries = await _fetch(config);
      expect(entries, hasLength(1));
      expect(
        adapter.requests.last.uri.toString(),
        'https://other.example/comments?key=a%2Fb',
      );
    },
  );

  test('uses form content type when a rule declares a form request', () async {
    adapter.respond = (_) => jsonEncode({
      'data': [_comment()],
    });
    await _fetch(
      DanmakuRuleConfig.fromJson({
        'steps': [
          {
            'request': {
              'method': 'POST',
              'url': '/form',
              'bodyType': 'form',
              'body': {'episode': '@episodeNumber'},
            },
          },
        ],
        'timePath': r'$.time_point',
      }),
    );
    expect(
      adapter.requests.single.headers['content-type'],
      'application/x-www-form-urlencoded',
    );
  });

  test('DPlayer arrays map all three modes and preserve colors', () {
    final entries = RuleDanmakuService.parse(
      jsonEncode({
        'data': [
          [3, 0, 16711680, 'user', '滚动'],
          [1, 1, 65280, 'user', '顶部'],
          [2, 2, 255, 'user', '底部'],
        ],
      }),
      DanmakuRulePresets.dplayer(),
      source: 'DPlayer',
    );
    expect(entries.map((e) => e.type), [5, 4, 1]);
    expect(entries.last.color.toARGB32(), 0xffff0000);
  });

  test('Bilibili XML preserves escaped text, fractional seconds and color', () {
    final entries = RuleDanmakuService.parse(
      '<?xml version="1.0"?><i><d p="1.418,5,25,7590205,0,0,u,1">中文 &amp; 字幕</d>'
      '<d p="2,4,25,255,0,0,u,2">底部</d></i>',
      DanmakuRulePresets.bilibiliXml(),
      source: 'XML',
    );
    expect(entries.map((e) => e.type), [5, 4]);
    expect(entries.first.message, '中文 & 字幕');
    expect(entries.first.time, 1.418);
    expect(entries.first.color.toARGB32(), 0xff000000 | 7590205);
  });

  test('XML is also supported as a network response', () async {
    adapter.respond = (_) => '<i><d p="1,1,25,16777215">hello</d></i>';
    expect(
      (await _fetch(DanmakuRulePresets.bilibiliXml())).single.message,
      'hello',
    );
  });

  test(
    'reuses cookie scope and browser user agent across rule requests',
    () async {
      await PluginCookieManager.instance.saveFromWebView(
        '自定义规则',
        _page,
        'session=test',
        userAgent: 'RuleBrowser',
      );
      await _fetch(_multiStepConfig());
      expect(adapter.requests.last.headers['cookie'], 'session=test');
      expect(adapter.requests.last.headers['user-agent'], 'RuleBrowser');
    },
  );

  test('a cancelled pre-request never starts the next step', () async {
    final token = CancelToken();
    adapter.respond = (_) {
      token.cancel();
      return jsonEncode({'id': 1});
    };
    await expectLater(
      RuleDanmakuService.instance.fetch(
        config: _multiStepConfig(),
        pageUrl: _page,
        pluginName: '自定义规则',
        episodeNumber: 1,
        cancelToken: token,
      ),
      throwsA(
        isA<NetworkException>().having(
          (e) => e.type,
          'type',
          NetworkExceptionType.cancel,
        ),
      ),
    );
    expect(adapter.requests, hasLength(1));
  });

  test('a failed response code stops the chain', () async {
    adapter.respond = (_) => jsonEncode({'code': 403, 'data': {}});
    await expectLater(_fetch(_multiStepConfig()), throwsFormatException);
    expect(adapter.requests, hasLength(1));
  });

  test('bad field mappings are errors while an empty list is valid', () {
    final config = DanmakuRulePresets.json();
    expect(
      () => RuleDanmakuService.parse('{"unexpected":[]}', config, source: 'x'),
      throwsFormatException,
    );
    expect(
      RuleDanmakuService.parse('{"data":[]}', config, source: 'x'),
      isEmpty,
    );
    expect(
      () => RuleDanmakuService.parse(
        '{"data":[{"wrong":1}]}',
        config,
        source: 'x',
      ),
      throwsFormatException,
    );
    expect(
      () => RuleDanmakuService.validate(
        DanmakuRuleConfig.fromJson({...config.toJson(), 'timeScale': 0}),
      ),
      throwsFormatException,
    );
  });

  test(
    'online playback applies any configured rule independent of the domain',
    () async {
      final controller = _controller();
      final result = await controller.fetchDanmaku(
        0,
        '自定义规则',
        99,
        pageUrl: _page,
        config: _multiStepConfig(),
      );
      expect(result.hasDanmakus, isTrue);
      expect(controller.danDanmakus, isEmpty);
      controller.applyDanmakuLoad(result, enableDanmaku: true);
      expect(
        controller.danmakusForPlaybackPosition(const Duration(seconds: 1)),
        hasLength(1),
      );
    },
  );

  test(
    'website failures stay actionable without switching to an unrelated service',
    () async {
      adapter.status = 403;
      final result = await _controller().fetchDanmaku(
        0,
        '自定义规则',
        1,
        pageUrl: _page,
        config: _multiStepConfig(),
      );
      expect(result.isFailed, isTrue);
      expect(result.errorMessage, contains('自定义规则 网站弹幕'));
    },
  );

  test(
    'offline playback uses cached website danmaku without requests',
    () async {
      final downloads = _Downloads()
        ..cached = RuleDanmakuService.parse(
          jsonEncode({
            'data': {
              'items': [_comment()],
            },
          }),
          _multiStepConfig(),
          source: '自定义规则',
        );
      final result = await _controller(
        downloads: downloads,
        local: true,
      ).fetchDanmaku(0, '自定义规则', 1, pageUrl: _page);
      expect(result.hasDanmakus, isTrue);
      expect(adapter.requests, isEmpty);
    },
  );

  test('missing offline cache uses the installed rule configuration', () async {
    final downloads = _Downloads()..config = _multiStepConfig();
    final result = await _controller(
      downloads: downloads,
      local: true,
    ).fetchDanmaku(0, '自定义规则', 1, pageUrl: _page);
    expect(result.hasDanmakus, isTrue);
    expect(downloads.saved!.single.source, '[自定义规则]');
  });
  testWidgets('editor saves website rules after switching sections', (
    tester,
  ) async {
    final controller = _RecordingPlugins();
    await _openEditor(tester, controller);
    await tester.tap(find.text('弹幕'));
    await tester.pumpAndSettle();
    expect(find.text('次元城预设'), findsNothing);
    await tester.tap(find.text('DPlayer 示例'));
    final config = DanmakuRulePresets.dplayer().toJson();
    (config['steps'] as List).first['request']['url'] =
        'https://new.example/comments';
    await tester.enterText(_field('弹幕规则（JSON）'), jsonEncode(config));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('基本'));
    await tester.tap(find.text('基本'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(controller.saved!.danmakuConfig!.toJson(), config);
    expect(find.text('打开编辑'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor rejects invalid mappings before saving', (tester) async {
    final controller = _RecordingPlugins();
    await _openEditor(tester, controller);
    await tester.tap(find.text('弹幕'));
    await tester.pumpAndSettle();
    final config = DanmakuRulePresets.json().toJson()
      ..['listPath'] = r'$..items';
    await tester.enterText(_field('弹幕规则（JSON）'), jsonEncode(config));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(controller.saved, isNull);
    expect(find.textContaining('JSONPath').evaluate().isNotEmpty, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor tests the configured API against a playback page', (
    tester,
  ) async {
    adapter.respond = (_) => jsonEncode({
      'data': [
        {'content': 'test', 'time': 1},
      ],
    });
    await _openEditor(tester, _RecordingPlugins());
    await tester.tap(find.text('弹幕'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JSON 示例'));
    await tester.ensureVisible(_field('测试播放页 URL'));
    await tester.enterText(_field('测试播放页 URL'), 'https://new.example/watch/1');
    await tester.ensureVisible(find.text('测试弹幕'));
    await tester.tap(find.text('测试弹幕'));
    await tester.pumpAndSettle();
    expect(find.text('读取到 1 条弹幕'), findsOneWidget);
    expect(adapter.requests.single.uri.host, 'new.example');
    expect(tester.takeException(), isNull);
  });
}

DanmakuRuleConfig _multiStepConfig() => DanmakuRuleConfig.fromJson({
  'pagePattern': r'/anime/(?<videoId>[1-9]\d*)/play/(?<episodeNumber>[1-9]\d*)',
  'defaults': {'playerCode': 'default'},
  'queryVariables': {'playerCode': 'from'},
  'steps': [
    {
      'request': {
        'url': '/api/videos/@videoId/sections',
        'query': {
          'player_code': '@playerCode',
          'page': '@pageNumber',
          'page_size': 100,
        },
      },
      'pageSize': 100,
      'listPath': r'$.data.list[*]',
      'matchPath': r'$.order',
      'matchValue': '@episodeNumber',
      'index': '@pageIndex',
      'captures': {'sectionId': r'$.id'},
      'successPath': r'$.code',
      'successValue': 0,
    },
    {
      'request': {'url': '/api/sections/@sectionId/danmaku'},
      'successPath': r'$.code',
      'successValue': 0,
    },
  ],
  'listPath': r'$.data.items[*]',
  'contentPath': r'$.content',
  'timePath': r'$.time_point',
  'modePath': r'$.mode',
  'colorPath': r'$.color',
  'modeMap': {'normal': 1, 'top': 5, 'bottom': 4},
});

Finder _field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is EditorTextField && w.label == label),
  matching: find.byType(TextField),
);

Future<void> _openEditor(
  WidgetTester tester,
  _RecordingPlugins controller,
) async {
  final module = createModule(
    register: (routes) {
      routes
        ..route(
          '/',
          child: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.pushNamed('/editor'),
              child: const Text('打开编辑'),
            ),
          ),
        )
        ..route(
          '/editor',
          child: (_, _) => PluginEditorPage(
            plugin: Plugin.fromTemplate()..name = '规则',
            controller: controller,
          ),
        );
    },
  );
  await tester.pumpWidget(
    ModularApp(
      module: module,
      child: Builder(
        builder: (context) => MaterialApp.router(
          routerConfig: ModularApp.routerConfigOf(context),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('打开编辑'));
  await tester.pumpAndSettle();
}

class _RecordingPlugins extends PluginsController {
  Plugin? saved;
  @override
  Future<void> updatePlugin(Plugin plugin) async {
    saved = plugin;
  }
}

Future<List<DanmakuEntry>> _fetch(
  DanmakuRuleConfig config, {
  String page = _page,
  int episode = 1,
  String videoUrl = '',
}) => RuleDanmakuService.instance.fetch(
  config: config,
  pageUrl: page,
  pluginName: '自定义规则',
  episodeNumber: episode,
  videoUrl: videoUrl,
);

PlayerDanmakuController _controller({
  _Downloads? downloads,
  bool local = false,
}) => PlayerDanmakuController(
  isLocalPlayback: () => local,
  downloadController: downloads ?? _Downloads(),
);

Map<String, dynamic> _comment() => {
  'content': '网站弹幕',
  'time_point': 1.418,
  'mode': 'normal',
  'color': 16777215,
};

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int status = 200;
  Map<String, dynamic> sections = {
    'list': [
      {'id': 52408},
      {'id': 52492},
    ],
  };
  String Function(RequestOptions)? respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final raw =
        respond?.call(options) ??
        jsonEncode({
          'code': 0,
          'data': options.uri.path.endsWith('/sections')
              ? sections
              : {
                  'items': [_comment()],
                },
        });
    return ResponseBody.fromString(
      raw,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Downloads implements DownloadController {
  List<DanmakuEntry>? cached;
  List<DanmakuEntry>? saved;
  DanmakuRuleConfig? config;
  @override
  DanmakuRuleConfig? danmakuConfigFor(String name) => config;
  @override
  Future<List<DanmakuEntry>?> getCachedDanmakus(
    int id,
    String name,
    int episode,
  ) async => cached;
  @override
  Future<void> updateCachedDanmakus(
    int id,
    String name,
    int episode,
    List<DanmakuEntry> items,
    int danDanId,
  ) async {
    saved = items;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

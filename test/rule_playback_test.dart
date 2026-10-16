import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/pages/plugin_editor/plugin_editor_page.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/plugins/playback_rule_config.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/plugin/plugin_cookie_manager.dart';
import 'package:kazumi/services/plugin/plugin_import_parser.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/video_source/rule_playback_service.dart';
import 'package:kazumi/services/video_source/video_source_service.dart';
import 'package:kazumi/services/video_source/webview_video_source_service.dart';
import 'package:kazumi/utils/encoding.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform oldPaths;
  late _Adapter adapter;
  setUpAll(() async {
    Logger.level = Level.off;
    directory = await Directory.systemTemp.createTemp('kazumi_playback_rule_');
    oldPaths = PathProviderPlatform.instance;
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
    PathProviderPlatform.instance = oldPaths;
    expect(
      directory.absolute.path.startsWith(Directory.systemTemp.absolute.path),
      isTrue,
    );
    expect(
      directory.uri.pathSegments.where((part) => part.isNotEmpty).last,
      startsWith('kazumi_playback_rule_'),
    );
    await directory.delete(recursive: true);
  });

  test('playback rules survive sharing, import, and API version upgrade', () {
    final plugin = Plugin.fromTemplate()
      ..name = 'generic'
      ..api = '10'
      ..playbackConfig = _config();
    final exported = plugin.toJson();
    expect(exported['api'], '11');
    final imported = PluginImportParser.parse(
      jsonToKazumiBase64(jsonEncode(exported)),
    );
    expect(imported.failures, isEmpty);
    expect(
      imported.plugins.single.playbackConfig!.toJson(),
      plugin.playbackConfig!.toJson(),
    );
    expect(Plugin.fromJson({'name': 'legacy'}).playbackConfig, isNull);
  });

  test(
    'selects codec preference, then highest available quality and bandwidth',
    () {
      final config = _config();
      final media = RulePlaybackService.parse(
        jsonEncode(_response()),
        config,
        pageUrl: 'https://unrelated.test/watch/1',
        variables: {'token': 'abc'},
      );
      expect(media.url, 'https://video.unrelated.test/1080-high');
      expect(media.audioUrl, 'https://audio.unrelated.test/high');
      final capped = PlaybackRuleConfig.fromJson(
        config.toJson()..['video']['maxQuality'] = 720,
      );
      expect(
        RulePlaybackService.parse(
          jsonEncode(_response()),
          capped,
          pageUrl: 'https://unrelated.test/watch/1',
          variables: {'token': 'abc'},
        ).url,
        'https://video.unrelated.test/720',
      );
    },
  );

  test('ignores malformed candidates when another media URL is usable', () {
    final config = PlaybackRuleConfig.fromJson({
      'steps': [
        {
          'request': {'url': '/media'},
        },
      ],
      'video': {'listPath': r'$.streams[*]', 'urlPath': r'$.url'},
    });
    final source = RulePlaybackService.parse(
      jsonEncode({
        'streams': [
          {'url': 'https://[invalid/video.mp4'},
          {'url': 'https://cdn.test/video.mp4'},
        ],
      }),
      config,
      pageUrl: 'https://generic.test/watch',
    );
    expect(source.url, 'https://cdn.test/video.mp4');
  });

  test(
    'captured complete URLs remain opaque instead of being rendered twice',
    () async {
      const endpoint =
          'https://api.generic.test/media?signature=@opaque&part=a%2Fb';
      adapter.respond = (request) async => request.uri.path == '/metadata'
          ? jsonEncode({'endpoint': endpoint})
          : '{"url":"https://cdn.test/video.mp4"}';
      final config = PlaybackRuleConfig.fromJson({
        'steps': [
          {
            'request': {'url': '/metadata'},
            'captures': {'endpoint': r'$.endpoint'},
          },
          {
            'request': {'url': '@endpoint'},
          },
        ],
        'video': {'urlPath': r'$.url'},
      });
      final source = await RulePlaybackService.resolve(
        config: config,
        pageUrl: 'https://generic.test/watch',
        pluginName: 'literal-url-test',
      );
      expect(source.url, 'https://cdn.test/video.mp4');
      expect(adapter.requests.last.uri.toString(), endpoint);
      expect(adapter.requests.last.uri.queryParameters['signature'], '@opaque');
      expect(adapter.requests.last.uri.queryParameters['part'], 'a/b');
    },
  );

  test('missing required audio fails instead of playing a silent video', () {
    final raw = jsonDecode(jsonEncode(_response()))..['data']['audio'] = [];
    expect(
      () => RulePlaybackService.parse(
        jsonEncode(raw),
        _config(),
        pageUrl: 'https://unrelated.test/watch/1',
        variables: {'token': 'abc'},
      ),
      throwsFormatException,
    );
  });

  test('relative URLs resolve and unsafe media protocols are rejected', () {
    final config = PlaybackRuleConfig.fromJson({
      'steps': [
        {
          'request': {'url': '/media'},
        },
      ],
      'video': {'urlPath': r'$.media'},
    });
    expect(
      RulePlaybackService.parse(
        '{"media":"/movie.mp4"}',
        config,
        pageUrl: 'https://generic.test/watch/1',
      ).url,
      'https://generic.test/movie.mp4',
    );
    for (final url in [
      'file:///secret',
      'javascript:alert(1)',
      'https://user:pass@host.test/v',
    ]) {
      expect(
        () => RulePlaybackService.parse(
          jsonEncode({'media': url}),
          config,
          pageUrl: 'https://generic.test/watch/1',
        ),
        throwsFormatException,
      );
    }
  });

  test(
    'multistep HTML capture, POST JSON, and per-origin cookies work together',
    () async {
      adapter.respond = (request) async => request.uri.path == '/watch/7'
          ? '<div data-token="session-7"></div>'
          : jsonEncode(_response());
      await PluginCookieManager.instance.saveFromWebView(
        'generic-cookie-test',
        'https://video.unrelated.test/',
        'session=video',
      );
      final source = await RulePlaybackService.resolve(
        config: _config(),
        pageUrl: 'https://unrelated.test/watch/7?line=main',
        pluginName: 'generic-cookie-test',
        episodeNumber: 7,
        offset: 19,
        httpHeaders: const {'user-agent': 'same-agent'},
      );
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests.last.method, 'POST');
      expect(adapter.requests.last.data, {
        'token': 'session-7',
        'episode': 7,
        'line': 'main',
      });
      expect(source.offset, 19);
      expect(source.httpHeaders['cookie'], 'session=video');
      expect(source.audioHttpHeaders.containsKey('cookie'), isFalse);
      expect(source.audioHttpHeaders['authorization'], 'Bearer session-7');
      expect(source.httpHeaders['user-agent'], 'same-agent');
    },
  );

  test('business errors stop the chain before requesting media', () async {
    adapter.respond = (_) async => '{"code":-1}';
    final config = PlaybackRuleConfig.fromJson({
      'steps': [
        {
          'request': {'url': '/metadata'},
          'successPath': r'$.code',
          'successValue': 0,
        },
        {
          'request': {'url': '/media'},
        },
      ],
      'video': {'urlPath': r'$.url'},
    });
    await expectLater(
      RulePlaybackService.resolve(
        config: config,
        pageUrl: 'https://generic.test/watch/1',
        pluginName: 'generic',
      ),
      throwsFormatException,
    );
    expect(adapter.requests, hasLength(1));
  });

  test(
    'configured resolver cancels old requests without loading a WebView',
    () async {
      final started = Completer<void>();
      adapter.respond = (request) async {
        if (request.uri.queryParameters['id'] == '1') {
          if (!started.isCompleted) started.complete();
          return await Completer<String>().future;
        }
        return '{"url":"https://cdn.test/movie.mp4"}';
      };
      final config = PlaybackRuleConfig.fromJson({
        'queryVariables': {'id': 'id'},
        'steps': [
          {
            'request': {
              'url': '/media',
              'query': {'id': '@id'},
            },
          },
        ],
        'video': {'urlPath': r'$.url'},
      });
      final service = WebViewVideoSourceService();
      final first = service.resolve(
        'https://generic.test/watch?id=1',
        useLegacyParser: false,
        playbackConfig: config,
      );
      final firstExpectation = expectLater(
        first,
        throwsA(isA<VideoSourceCancelledException>()),
      );
      await started.future;
      final second = await service.resolve(
        'https://generic.test/watch?id=2',
        useLegacyParser: false,
        playbackConfig: config,
      );
      await firstExpectation;
      expect(second.url, 'https://cdn.test/movie.mp4');
      await service.dispose();
    },
  );

  test(
    'configured resolver enforces total timeout and remains reusable',
    () async {
      adapter.respond = (_) => Completer<String>().future;
      final config = PlaybackRuleConfig.fromJson({
        'steps': [
          {
            'request': {'url': '/media'},
          },
        ],
        'video': {'urlPath': r'$.url'},
      });
      final service = WebViewVideoSourceService();
      await expectLater(
        service.resolve(
          'https://generic.test/watch',
          useLegacyParser: false,
          playbackConfig: config,
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<VideoSourceTimeoutException>()),
      );
      adapter.respond = (_) async => '{"url":"https://cdn.test/movie.mp4"}';
      expect(
        (await service.resolve(
          'https://generic.test/watch',
          useLegacyParser: false,
          playbackConfig: config,
        )).url,
        'https://cdn.test/movie.mp4',
      );
      await service.dispose();
    },
  );

  testWidgets('editing other sections preserves the playback configuration', (
    tester,
  ) async {
    final plugin = Plugin.fromTemplate()
      ..name = 'generic'
      ..playbackConfig = _config();
    final controller = _Plugins();
    await tester.pumpWidget(
      MaterialApp(
        home: PluginEditorPage(plugin: plugin, controller: controller),
      ),
    );
    await tester.tap(find.text('播放', skipOffstage: false));
    await tester.pumpAndSettle();
    expect(find.text('播放规则（JSON）'), findsOneWidget);
    await tester.tap(find.text('基本', skipOffstage: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(
      controller.saved?.playbackConfig?.toJson(),
      plugin.playbackConfig!.toJson(),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

PlaybackRuleConfig _config() => PlaybackRuleConfig.fromJson({
  'queryVariables': {'line': 'line'},
  'steps': [
    {
      'request': {'url': '@pageUrl'},
      'regexCaptures': {'token': 'data-token="([^"]+)"'},
    },
    {
      'request': {
        'method': 'POST',
        'url': 'https://api.unrelated.test/media',
        'bodyType': 'json',
        'body': {
          'token': '@token',
          'episode': '@episodeNumber',
          'line': '@line',
        },
      },
      'successPath': r'$.code',
      'successValue': 0,
    },
  ],
  'video': {
    'listPath': r'$.data.video[*]',
    'urlPath': r'$.url',
    'qualityPath': r'$.height',
    'bandwidthPath': r'$.bandwidth',
    'codecPath': r'$.codec',
    'preferredCodecs': ['avc1', 'hev1'],
  },
  'audio': {
    'listPath': r'$.data.audio[*]',
    'urlPath': r'$.url',
    'bandwidthPath': r'$.bandwidth',
    'headers': {'Authorization': 'Bearer @token'},
  },
});

Map<String, dynamic> _response() => {
  'code': 0,
  'data': {
    'video': [
      {
        'url': 'https://video.unrelated.test/4k',
        'height': 2160,
        'codec': 'hev1',
        'bandwidth': 9,
      },
      {
        'url': 'https://video.unrelated.test/720',
        'height': 720,
        'codec': 'avc1',
        'bandwidth': 1,
      },
      {
        'url': 'https://video.unrelated.test/1080-low',
        'height': 1080,
        'codec': 'avc1',
        'bandwidth': 2,
      },
      {
        'url': 'https://video.unrelated.test/1080-high',
        'height': 1080,
        'codec': 'avc1',
        'bandwidth': 3,
      },
    ],
    'audio': [
      {'url': 'https://audio.unrelated.test/low', 'bandwidth': 1},
      {'url': 'https://audio.unrelated.test/high', 'bandwidth': 2},
    ],
  },
};

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Future<String> Function(RequestOptions)? respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final response =
        (respond?.call(options) ?? Future.value(jsonEncode(_response()))).then(
          (raw) => ResponseBody.fromString(
            raw,
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          ),
        );
    return await Future.any([
      response,
      if (cancelFuture != null)
        cancelFuture.then<ResponseBody>(
          (_) => throw DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
          ),
        ),
    ]);
  }

  @override
  void close({bool force = false}) {}
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Plugins extends PluginsController {
  Plugin? saved;
  @override
  Future<void> updatePlugin(Plugin plugin) async {
    saved = plugin;
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/update/auto_updater.dart';
import 'package:kazumi/services/update/update_download_source.dart';
import 'package:kazumi/services/update/update_downloader.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPaths;
  late _ReleaseAdapter adapter;

  setUpAll(() async {
    Logger.level = Level.off;
    directory = await Directory.systemTemp.createTemp(
      'kazumiplus_update_test_',
    );
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });

  setUp(() {
    DioFactory.reset();
    adapter = _ReleaseAdapter();
    DioFactory.downloadDio.httpClientAdapter.close();
    DioFactory.downloadDio.httpClientAdapter = adapter;
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
      startsWith('kazumiplus_update_test_'),
    );
    await directory.delete(recursive: true);
  });

  test('updates use KazumiPlus GitHub release metadata and assets', () async {
    final update = await AutoUpdater().checkForUpdates();

    expect(
      adapter.requests.single.uri.toString(),
      'https://api.github.com/repos/Shiroha23/KazumiPlus/releases/latest',
    );
    expect(update, isNotNull);
    expect(update!.version, '9999.0.0');
    expect(
      update.releaseNotes,
      'https://github.com/Shiroha23/KazumiPlus/releases/tag/9999.0.0',
    );
    final asset = getUpdateAssetForType(
      update.assets,
      InstallationType.windowsPortable,
    );
    expect(
      getUpdateDownloadUrlFromAsset(asset, UpdateDownloadSource.github),
      'https://github.com/Shiroha23/KazumiPlus/releases/download/'
      '9999.0.0/KazumiPlus_windows_9999.0.0.zip',
    );
  });

  test(
    'a repository with no release has no update or upstream fallback',
    () async {
      adapter.status = 404;

      expect(await AutoUpdater().checkForUpdates(), isNull);
      expect(adapter.requests, hasLength(1));
    },
  );

  test('GitHub access errors remain actionable failures', () async {
    adapter.status = 403;

    await expectLater(
      AutoUpdater().checkForUpdates(),
      throwsA(
        isA<NetworkException>().having(
          (error) => error.statusCode,
          'statusCode',
          403,
        ),
      ),
    );
    expect(adapter.requests, hasLength(1));
  });
}

class _ReleaseAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int status = 200;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({
        'tag_name': '9999.0.0',
        'body': 'KazumiPlus release',
        'html_url':
            'https://github.com/Shiroha23/KazumiPlus/releases/tag/9999.0.0',
        'published_at': '2026-10-16T00:00:00Z',
        'assets': [
          {
            'name': 'KazumiPlus_windows_9999.0.0.zip',
            'browser_download_url':
                'https://github.com/Shiroha23/KazumiPlus/releases/download/'
                '9999.0.0/KazumiPlus_windows_9999.0.0.zip',
          },
        ],
      }),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
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

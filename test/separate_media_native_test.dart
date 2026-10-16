import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/separate_media_playback.dart';
import 'package:media_kit/media_kit.dart';

/// Opt-in native integration using the same libmpv bundled with Windows builds.
/// No external site, credentials, codecs, or downloaded media fixtures required.
void main() {
  final library = File(
    'build/native_assets/windows/libmpv-2.dll',
  ).absolute.path;
  final enabled =
      Platform.isWindows &&
      Platform.environment['KAZUMI_NATIVE_PLAYBACK_TEST'] == '1' &&
      File(library).existsSync();
  test(
    'native player loads separate HTTP streams with isolated headers and resume',
    () async {
      MediaKit.ensureInitialized(libmpv: library);
      final video = await File(
        'test/fixtures/playback/video.mp4',
      ).readAsBytes();
      final audio = await File(
        'test/fixtures/playback/audio.m4a',
      ).readAsBytes();
      final videoRequests = <HttpRequest>[];
      final audioRequests = <HttpRequest>[];
      final videoServer = await _serve(video, 'video-session', videoRequests);
      final audioServer = await _serve(audio, 'audio-session', audioRequests);
      final player = Player(
        configuration: const PlayerConfiguration(osc: false),
      );
      final native = player.platform as NativePlayer;
      await native.setProperty('vo', 'null');
      await native.setProperty('ao', 'null');
      await native.setProperty('vid', 'auto');
      final audioUrl = 'http://127.0.0.1:${audioServer.port}/audio.m4a';
      final errors = <String>[];
      final errorSubscription = player.stream.error.listen(errors.add);
      try {
        await openPlaybackMedia(
          adapter: NativeMediaPlaybackAdapter(player),
          videoUrl: 'http://127.0.0.1:${videoServer.port}/video.mp4',
          videoHeaders: const {
            'authorization': 'video-session',
            'x-literal': r'comma,back\slash',
          },
          audioUrl: audioUrl,
          audioHeaders: const {
            'authorization': 'audio-session',
            'x-literal': r'comma,back\slash',
          },
          isCurrent: () => true,
          autoPlay: false,
          offset: 2,
        );
        final count = int.parse(await native.getProperty('track-list/count'));
        final types = <String>[];
        for (var i = 0; i < count; i++) {
          types.add(await native.getProperty('track-list/$i/type'));
        }
        expect(types, containsAll(['video', 'audio']));
        expect(await native.getProperty('pause'), 'yes');
        expect(videoRequests, isNotEmpty);
        expect(audioRequests, isNotEmpty);
        expect(
          videoRequests.every(
            (r) => r.headers.value('authorization') == 'video-session',
          ),
          isTrue,
        );
        expect(
          audioRequests.every(
            (r) => r.headers.value('authorization') == 'audio-session',
          ),
          isTrue,
        );
        expect(
          audioRequests.first.headers.value('x-literal'),
          r'comma,back\slash',
        );
        expect(
          double.parse(await native.getProperty('time-pos')),
          closeTo(2, 0.3),
        );
        await player.play();
        await player.stream.position
            .firstWhere((position) => position.inMilliseconds > 2200)
            .timeout(const Duration(seconds: 10));
        expect(await native.getProperty('audio-codec-name'), isNotEmpty);
        await player.pause();
        await player.seek(const Duration(seconds: 4));
        expect(
          double.parse(await native.getProperty('time-pos')),
          closeTo(4, 0.3),
        );

        // A missing audio stream must fail rather than silently start video only.
        await expectLater(
          openPlaybackMedia(
            adapter: NativeMediaPlaybackAdapter(player),
            videoUrl: 'http://127.0.0.1:${videoServer.port}/video.mp4',
            videoHeaders: const {'authorization': 'video-session'},
            audioUrl: '$audioUrl?missing=1',
            audioHeaders: const {'authorization': 'audio-session'},
            isCurrent: () => true,
            autoPlay: true,
          ),
          throwsFormatException,
        );
        expect(await native.getProperty('pause'), 'yes');
      } catch (error) {
        fail(
          '$error; video requests=${videoRequests.length}, audio requests=${audioRequests.length}, '
          'tracks=${player.state.tracks}, errors=$errors',
        );
      } finally {
        await errorSubscription.cancel();
        await player.dispose();
        await videoServer.close(force: true);
        await audioServer.close(force: true);
      }
    },
    skip: !enabled,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

Future<HttpServer> _serve(
  Uint8List bytes,
  String authorization,
  List<HttpRequest> requests,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    requests.add(request);
    if (request.headers.value('authorization') != authorization ||
        request.uri.queryParameters['missing'] == '1') {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    var start = 0;
    var end = bytes.length - 1;
    final range = request.headers.value('range');
    if (range != null) {
      final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
      if (match != null) {
        start = int.parse(match[1]!);
        if (match[2]!.isNotEmpty) end = int.parse(match[2]!).clamp(0, end);
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          'content-range',
          'bytes $start-$end/${bytes.length}',
        );
      }
    }
    request.response.headers.set('accept-ranges', 'bytes');
    request.response.contentLength = end - start + 1;
    if (request.method != 'HEAD') {
      request.response.add(bytes.sublist(start, end + 1));
    }
    await request.response.close();
  });
  return server;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/separate_media_playback.dart';

void main() {
  late _Adapter adapter;
  var current = true;
  setUp(() {
    adapter = _Adapter();
    current = true;
  });
  Future<void> open({
    String? audio = 'https://audio.test/track',
    bool autoPlay = true,
  }) => openPlaybackMedia(
    adapter: adapter,
    videoUrl: 'https://video.test/track',
    videoHeaders: const {'cookie': 'video-session=1'},
    audioHeaders: const {'authorization': 'audio-session'},
    isCurrent: () => current,
    autoPlay: autoPlay,
    offset: 120,
    audioUrl: audio,
  );

  test(
    'separate media pauses, loads audio with its own headers, then plays',
    () async {
      await open();
      expect(adapter.calls, [
        'open:120:false',
        'video-ready',
        'headers:{authorization: audio-session}',
        'audio:https://audio.test/track',
        'headers:{cookie: video-session=1}',
        'play',
      ]);
    },
  );
  test(
    'audio failure restores video headers and never starts playback',
    () async {
      adapter.failAudio = true;
      await expectLater(open(), throwsFormatException);
      expect(adapter.calls.last, 'headers:{cookie: video-session=1}');
      expect(adapter.calls, isNot(contains('play')));
    },
  );
  test('disabled autoplay stays paused after both streams are ready', () async {
    await open(autoPlay: false);
    expect(adapter.calls.first, 'open:120:false');
    expect(adapter.calls, isNot(contains('play')));
  });
  test(
    'switching episode while loading video prevents audio attachment',
    () async {
      adapter.onReady = () => current = false;
      await open();
      expect(adapter.calls, ['open:120:false', 'video-ready']);
    },
  );
  test(
    'switching during audio load does not mutate or play disposed player',
    () async {
      adapter.onAudio = () => current = false;
      await open();
      expect(adapter.calls.last, 'audio:https://audio.test/track');
    },
  );
  test('muxed media retains the original open behavior', () async {
    await open(audio: null);
    expect(adapter.calls, ['open:120:true']);
  });
}

class _Adapter implements MediaPlaybackAdapter {
  final calls = <String>[];
  bool failAudio = false;
  void Function()? onReady;
  void Function()? onAudio;
  @override
  Future<void> open(
    String url,
    Map<String, String> headers,
    int offset,
    bool play,
  ) async => calls.add('open:$offset:$play');
  @override
  Future<void> waitForVideo() async {
    calls.add('video-ready');
    onReady?.call();
  }

  @override
  Future<void> setHeaders(Map<String, String> headers) async =>
      calls.add('headers:$headers');
  @override
  Future<void> addAudio(String url) async {
    calls.add('audio:$url');
    onAudio?.call();
    if (failAudio) throw const FormatException('audio failed');
  }

  @override
  Future<void> play() async => calls.add('play');
}

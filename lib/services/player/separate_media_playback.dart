import 'package:media_kit/media_kit.dart';

abstract interface class MediaPlaybackAdapter {
  Future<void> open(
    String url,
    Map<String, String> headers,
    int offset,
    bool play,
  );
  Future<void> waitForVideo();
  Future<void> setHeaders(Map<String, String> headers);
  Future<void> addAudio(String url);
  Future<void> play();
}

/// Open both streams on one clock, remaining paused until audio is attached.
Future<void> openPlaybackMedia({
  required MediaPlaybackAdapter adapter,
  required String videoUrl,
  required Map<String, String> videoHeaders,
  required bool Function() isCurrent,
  required bool autoPlay,
  int offset = 0,
  String? audioUrl,
  Map<String, String> audioHeaders = const {},
}) async {
  if (!isCurrent()) return;
  if (audioUrl == null) {
    await adapter.open(videoUrl, videoHeaders, offset, autoPlay);
    return;
  }
  await adapter.open(videoUrl, videoHeaders, offset, false);
  if (!isCurrent()) return;
  await adapter.waitForVideo();
  if (!isCurrent()) return;
  try {
    // mpv copies these options into each new demuxer. Audio must not inherit
    // cookies or authorization belonging to a different video origin.
    await adapter.setHeaders(audioHeaders);
    if (!isCurrent()) return;
    await adapter.addAudio(audioUrl);
  } finally {
    if (isCurrent()) await adapter.setHeaders(videoHeaders);
  }
  if (isCurrent() && autoPlay) await adapter.play();
}

class NativeMediaPlaybackAdapter implements MediaPlaybackAdapter {
  NativeMediaPlaybackAdapter(this.player);
  final Player player;

  @override
  Future<void> open(
    String url,
    Map<String, String> headers,
    int offset,
    bool play,
  ) => player.open(
    Media(
      url,
      start: Duration(seconds: offset),
      httpHeaders: headers,
    ),
    play: play,
  );

  @override
  Future<void> waitForVideo() async {
    bool hasVideo(Tracks tracks) =>
        tracks.video.any((track) => track.id != 'auto' && track.id != 'no');
    if (hasVideo(player.state.tracks)) return;
    await player.stream.tracks
        .firstWhere(hasVideo)
        .timeout(const Duration(seconds: 30));
  }

  @override
  Future<void> setHeaders(Map<String, String> headers) async {
    final native = player.platform as NativePlayer;
    // append accepts a single literal item, including commas and backslashes.
    await native.command(['change-list', 'http-header-fields', 'clr', '']);
    for (final entry in headers.entries) {
      await native.command([
        'change-list',
        'http-header-fields',
        'append',
        '${entry.key}: ${entry.value}',
      ]);
    }
  }

  @override
  Future<void> addAudio(String url) async {
    await player.setAudioTrack(AudioTrack.uri(url));
    final native = player.platform as NativePlayer;
    final count =
        int.tryParse(await native.getProperty('track-list/count')) ?? 0;
    for (var i = 0; i < count; i++) {
      if (await native.getProperty('track-list/$i/type') == 'audio' &&
          await native.getProperty('track-list/$i/external-filename') == url &&
          await native.getProperty('track-list/$i/selected') == 'yes') {
        return;
      }
    }
    throw const FormatException('独立音轨加载失败，请检查音频地址和请求头');
  }

  @override
  Future<void> play() => player.play();
}

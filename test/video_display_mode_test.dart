import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/video/video_fullscreen_controller.dart';
import 'package:kazumi/services/platform/display_mode_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  final calls = <String>[];
  var fullscreen = false;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    calls.clear();
    fullscreen = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'isFullScreen') {
            calls.add('read');
            return fullscreen;
          }
          if (call.method == 'setFullScreen') {
            fullscreen = (call.arguments as Map)['isFullScreen'] as bool;
            calls.add('set:$fullscreen');
            return true;
          }
          throw StateError('Unexpected window operation: ${call.method}');
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'returning from windowed playback does not reset the native frame',
    () async {
      final controller = VideoFullscreenController(
        applyFullscreen: DisplayModeService.applyVideoFullscreen,
      );
      await controller.close();
      await controller.close();
      expect(calls, ['read']);
      expect(fullscreen, isFalse);
    },
  );

  test(
    'fullscreen playback exits once and ignores redundant exit requests',
    () async {
      await DisplayModeService.applyVideoFullscreen(true);
      final controller = VideoFullscreenController(
        applyFullscreen: DisplayModeService.applyVideoFullscreen,
      );
      await controller.close();
      await DisplayModeService.applyVideoFullscreen(false);
      expect(calls, ['read', 'set:true', 'read', 'set:false', 'read']);
      expect(fullscreen, isFalse);
    },
  );

  test('queued fullscreen requests read the completed native state', () async {
    await Future.wait([
      DisplayModeService.applyVideoFullscreen(true),
      DisplayModeService.applyVideoFullscreen(false),
      DisplayModeService.applyVideoFullscreen(false),
    ]);
    expect(calls, ['read', 'set:true', 'read', 'set:false', 'read']);
    expect(fullscreen, isFalse);
  });
}

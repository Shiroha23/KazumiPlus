import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/platform/window_effect_service.dart';

void main() {
  test('offers only materials supported by the Windows build', () {
    expect(supportedWindowMaterials('windows', 19045), [
      WindowMaterial.disabled,
      WindowMaterial.acrylic,
      WindowMaterial.transparent,
    ]);
    expect(
      supportedWindowMaterials('windows', 22000),
      contains(WindowMaterial.mica),
    );
    expect(
      supportedWindowMaterials('windows', 22000),
      isNot(contains(WindowMaterial.tabbed)),
    );
    expect(
      supportedWindowMaterials('windows', 22523),
      contains(WindowMaterial.tabbed),
    );
    expect(supportedWindowMaterials('macos', 0), [
      WindowMaterial.disabled,
      WindowMaterial.vibrancy,
    ]);
    expect(supportedWindowMaterials('linux', 0), [WindowMaterial.disabled]);
    expect(windowsBuildNumber('Windows 11 Pro 10.0 (Build 26100)'), 26100);
    expect(windowsBuildNumber('unknown'), 0);
  });

  test('unsupported platforms leave the native window untouched', () async {
    var nativeCalls = 0;
    final effects = WindowEffectService(
      materials: [WindowMaterial.disabled],
      initializeNative: () async => nativeCalls++,
      applyNative: (_, _, _) async => nativeCalls++,
    );
    await effects.initialize(material: 'acrylic');
    effects.syncTheme(ThemeData());
    expect(effects.enabled, isFalse);
    expect(nativeCalls, 0);
  });

  test(
    'restores valid preferences and ignores unavailable saved materials',
    () async {
      final effects = WindowEffectService(
        materials: supportedWindowMaterials('windows', 19045),
        initializeNative: () async {},
        applyNative: (_, _, _) async {},
      );
      await effects.initialize(material: 'mica', opacity: 2);
      expect(effects.material, WindowMaterial.disabled);
      expect(effects.opacity, 0.85);
      effects.setOpacity(double.nan);
      expect(effects.opacity, 0.85);
      await expectLater(
        effects.setMaterial(WindowMaterial.mica),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'native changes follow app brightness and restore an opaque theme on disable',
    () async {
      final calls = <(acrylic.WindowEffect, bool)>[];
      final effects = WindowEffectService(
        materials: supportedWindowMaterials('windows', 26100),
        initializeNative: () async {},
        applyNative: (effect, color, dark) async => calls.add((effect, dark)),
      );
      await effects.initialize();
      final light = ThemeData();
      effects.syncTheme(light);
      await effects.setMaterial(WindowMaterial.mica);
      expect(calls, [(acrylic.WindowEffect.mica, false)]);
      final decorated = effects.decorateTheme(light);
      expect(decorated.scaffoldBackgroundColor, Colors.transparent);
      expect(decorated.colorScheme, light.colorScheme);
      expect(decorated.textTheme, light.textTheme);
      expect(decorated.cardTheme, light.cardTheme);
      effects.syncTheme(ThemeData.dark());
      await effects.setMaterial(WindowMaterial.disabled);
      expect(calls, [
        (acrylic.WindowEffect.mica, false),
        (acrylic.WindowEffect.mica, true),
        (acrylic.WindowEffect.disabled, true),
      ]);
      expect(effects.decorateTheme(light), same(light));
    },
  );

  test('a rejected native effect does not commit the selection', () async {
    final effects = WindowEffectService(
      materials: supportedWindowMaterials('windows', 26100),
      initializeNative: () async {},
      applyNative: (_, _, _) async =>
          throw StateError('composition unavailable'),
    );
    await effects.initialize();
    await expectLater(
      effects.setMaterial(WindowMaterial.acrylic),
      throwsStateError,
    );
    expect(effects.material, WindowMaterial.disabled);
    expect(effects.enabled, isFalse);
  });

  test('failed theme synchronization falls back to an opaque app', () async {
    final changed = Completer<void>();
    final effects = WindowEffectService(
      materials: supportedWindowMaterials('windows', 26100),
      initializeNative: () async {},
      applyNative: (_, _, _) async =>
          throw StateError('composition unavailable'),
    );
    await effects.initialize(material: 'mica');
    effects.addListener(() {
      if (!changed.isCompleted) changed.complete();
    });
    effects.syncTheme(ThemeData.dark());
    await changed.future;
    expect(effects.enabled, isFalse);
    expect(
      effects.decorateTheme(ThemeData.dark()).scaffoldBackgroundColor.a,
      1,
    );
  });

  test(
    'reapply restores unchanged native material with the current theme',
    () async {
      final calls = <(acrylic.WindowEffect, Color, bool)>[];
      final effects = WindowEffectService(
        materials: supportedWindowMaterials('windows', 26100),
        initializeNative: () async {},
        applyNative: (effect, color, dark) async =>
            calls.add((effect, color, dark)),
      );
      await effects.initialize(material: 'mica', opacity: .45);
      final theme = ThemeData.dark();
      effects.syncTheme(theme);
      await effects.setMaterial(WindowMaterial.mica);
      expect(calls, hasLength(1));
      effects.syncTheme(theme);
      await effects.setMaterial(WindowMaterial.mica);
      expect(
        calls,
        hasLength(1),
        reason: 'Unchanged theme sync remains cached.',
      );

      await effects.reapply();
      expect(calls, hasLength(2));
      expect(calls.last, calls.first);
      expect(calls.last.$1, acrylic.WindowEffect.mica);
      expect(calls.last.$3, isTrue);
      expect(effects.material, WindowMaterial.mica);
      expect(effects.opacity, .45);
      expect(effects.enabled, isTrue);
    },
  );

  test('reapply cannot reenable a disabled material', () async {
    final calls = <acrylic.WindowEffect>[];
    final effects = WindowEffectService(
      materials: supportedWindowMaterials('windows', 26100),
      initializeNative: () async {},
      applyNative: (effect, _, _) async => calls.add(effect),
    );
    await effects.initialize();
    await effects.reapply();
    expect(calls, isEmpty);
    await effects.setMaterial(WindowMaterial.mica);
    await effects.setMaterial(WindowMaterial.disabled);
    await effects.reapply();
    expect(calls, [acrylic.WindowEffect.mica, acrylic.WindowEffect.disabled]);
  });

  test(
    'reapply waits for pending native changes and uses the latest material',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final calls = <acrylic.WindowEffect>[];
      final effects = WindowEffectService(
        materials: supportedWindowMaterials('windows', 26100),
        initializeNative: () async {},
        applyNative: (effect, _, _) async {
          calls.add(effect);
          if (calls.length == 1) {
            started.complete();
            await release.future;
          }
        },
      );
      await effects.initialize();
      final change = effects.setMaterial(WindowMaterial.acrylic);
      await started.future;
      final restore = effects.reapply();
      expect(calls, [acrylic.WindowEffect.acrylic]);
      release.complete();
      await Future.wait([change, restore]);
      expect(calls, [
        acrylic.WindowEffect.acrylic,
        acrylic.WindowEffect.acrylic,
      ]);
      expect(effects.material, WindowMaterial.acrylic);
    },
  );

  test(
    'failed restoration falls back to an opaque app without blocking exit',
    () async {
      var calls = 0;
      final effects = WindowEffectService(
        materials: supportedWindowMaterials('windows', 26100),
        initializeNative: () async {},
        applyNative: (_, _, _) async {
          if (++calls > 1) throw StateError('composition unavailable');
        },
      );
      await effects.initialize();
      await effects.setMaterial(WindowMaterial.mica);
      await expectLater(effects.reapply(), completes);
      expect(effects.enabled, isFalse);
      expect(effects.decorateTheme(ThemeData()).scaffoldBackgroundColor.a, 1);
    },
  );
}

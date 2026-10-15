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
}

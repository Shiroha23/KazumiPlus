import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/utils/async_serial_queue.dart';
import 'package:window_manager/window_manager.dart';

enum WindowMaterial {
  disabled('关闭'),
  acrylic('亚克力'),
  mica('Mica 云母'),
  tabbed('Mica Alt'),
  transparent('透明'),
  vibrancy('毛玻璃');

  const WindowMaterial(this.label);
  final String label;

  static WindowMaterial parse(String value) => values.firstWhere(
    (material) => material.name == value,
    orElse: () => disabled,
  );
}

List<WindowMaterial> supportedWindowMaterials(String platform, int build) =>
    switch (platform) {
      'windows' => [
        WindowMaterial.disabled,
        if (build >= 17134) WindowMaterial.acrylic,
        if (build >= 22000) WindowMaterial.mica,
        if (build >= 22523) WindowMaterial.tabbed,
        WindowMaterial.transparent,
      ],
      'macos' => [WindowMaterial.disabled, WindowMaterial.vibrancy],
      _ => [WindowMaterial.disabled],
    };

int windowsBuildNumber(String version) =>
    int.tryParse(
      RegExp(
            r'build\s+(\d+)',
            caseSensitive: false,
          ).firstMatch(version)?.group(1) ??
          '',
    ) ??
    0;

typedef WindowEffectApplier =
    Future<void> Function(acrylic.WindowEffect effect, Color color, bool dark);

class WindowEffectService extends ChangeNotifier {
  WindowEffectService({
    required this.materials,
    Future<void> Function()? initializeNative,
    WindowEffectApplier? applyNative,
  }) : _initializeNative = initializeNative ?? acrylic.Window.initialize,
       _applyNative =
           applyNative ??
           ((effect, color, dark) async {
             await acrylic.Window.setEffect(
               effect: effect,
               color: color,
               dark: dark,
             );
             if (Platform.isWindows) {
               await windowManager.setBrightness(
                 dark ? Brightness.dark : Brightness.light,
               );
             } else if (Platform.isMacOS) {
               await acrylic.Window.overrideMacOSBrightness(dark: dark);
             }
           });

  static final instance = WindowEffectService(
    materials: supportedWindowMaterials(
      Platform.operatingSystem,
      windowsBuildNumber(Platform.operatingSystemVersion),
    ),
  );

  final List<WindowMaterial> materials;
  final Future<void> Function() _initializeNative;
  final WindowEffectApplier _applyNative;
  final _operations = AsyncSerialQueue();
  bool _initialized = false;
  bool _available = true;
  WindowMaterial _material = WindowMaterial.disabled;
  double _opacity = 0.35;
  Color _surface = const Color(0xfff8faf5);
  Brightness _brightness = Brightness.light;
  (WindowMaterial, Color, Brightness)? _applied;

  bool get available => _initialized && _available && materials.length > 1;
  bool get enabled => available && _material != WindowMaterial.disabled;
  WindowMaterial get material => _material;
  double get opacity => _opacity;

  Future<void> initialize({
    String material = 'disabled',
    double opacity = 0.35,
  }) async {
    if (_initialized || materials.length <= 1) return;
    _opacity = opacity.isFinite ? opacity.clamp(0.15, 0.85) : 0.35;
    final saved = WindowMaterial.parse(material);
    _material = materials.contains(saved) ? saved : WindowMaterial.disabled;
    try {
      await _initializeNative();
      _initialized = true;
    } catch (error, stackTrace) {
      _available = false;
      _material = WindowMaterial.disabled;
      KazumiLogger().w(
        'Unable to initialize window effects',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> setMaterial(WindowMaterial value) => _operations.run(() async {
    if (!available || !materials.contains(value)) {
      throw UnsupportedError('当前系统不支持此窗口效果');
    }
    await _apply(value, _surface, _brightness);
    _material = value;
    notifyListeners();
  });

  void setOpacity(double value) {
    if (!value.isFinite) return;
    _opacity = value.clamp(0.15, 0.85);
    notifyListeners();
  }

  /// Called with the resolved app theme, including dynamic color and OLED mode.
  void syncTheme(ThemeData theme) {
    _surface = theme.colorScheme.surface;
    _brightness = theme.brightness;
    if (!available) return;
    final surface = _surface;
    final brightness = _brightness;
    unawaited(_operations.run(() => _applyOrDisable(surface, brightness)));
  }

  /// Native fullscreen changes can reset composition without changing the theme.
  Future<void> reapply() => _operations.run(() async {
    if (!enabled) return;
    await _applyOrDisable(_surface, _brightness, force: true);
  });

  Future<void> _applyOrDisable(
    Color surface,
    Brightness brightness, {
    bool force = false,
  }) async {
    try {
      await _apply(_material, surface, brightness, force: force);
    } catch (error, stackTrace) {
      // Restore an opaque Flutter background if native composition fails.
      _material = WindowMaterial.disabled;
      _available = false;
      notifyListeners();
      KazumiLogger().w(
        'Unable to apply window effect',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _apply(
    WindowMaterial material,
    Color surface,
    Brightness brightness, {
    bool force = false,
  }) async {
    final request = (material, surface, brightness);
    if (!force && _applied == request) return;
    // Keep default startup untouched until the user enables a material.
    if (_applied == null && material == WindowMaterial.disabled) return;
    final effect = switch (material) {
      WindowMaterial.disabled => acrylic.WindowEffect.disabled,
      WindowMaterial.acrylic => acrylic.WindowEffect.acrylic,
      WindowMaterial.mica => acrylic.WindowEffect.mica,
      WindowMaterial.tabbed => acrylic.WindowEffect.tabbed,
      WindowMaterial.transparent => acrylic.WindowEffect.transparent,
      WindowMaterial.vibrancy => acrylic.WindowEffect.sidebar,
    };
    await _applyNative(
      effect,
      surface.withValues(alpha: 0.2),
      brightness == Brightness.dark,
    );
    _applied = request;
  }

  ThemeData decorateTheme(ThemeData theme) => enabled
      ? theme.copyWith(
          scaffoldBackgroundColor: Colors.transparent,
          appBarTheme: theme.appBarTheme.copyWith(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
          ),
        )
      : theme;
}

/// Full-page shells let the native material show through; content cards retain
/// their opaque Material colors for contrast.
Color windowSurfaceColor(BuildContext context, Color fallback) =>
    Theme.of(context).scaffoldBackgroundColor.a == 0
    ? Colors.transparent
    : fallback;

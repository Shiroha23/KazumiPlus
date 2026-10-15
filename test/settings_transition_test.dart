import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/utils/constants.dart';

Future<int> backgroundPixel(WidgetTester tester, GlobalKey boundaryKey) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final offset = ((image.height - 20) * image.width + image.width ~/ 2) * 4;
      return Color.fromARGB(
        pixels.getUint8(offset + 3),
        pixels.getUint8(offset),
        pixels.getUint8(offset + 1),
        pixels.getUint8(offset + 2),
      ).toARGB32();
    } finally {
      image.dispose();
    }
  }))!;
}

Widget settingsPane(String title) => SettingsPaneScope(
  embedded: true,
  showBackButton: false,
  onBack: () {},
  child: SettingsDetailScaffold(
    title: Text(title),
    body: const SizedBox.shrink(),
  ),
);

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    for (final brightness in Brightness.values) {
      for (final glass in [true, false]) {
        testWidgets(
          '${platform.name} ${brightness.name} ${glass ? 'glass' : 'opaque'} keeps background during push, replace and pop',
          (tester) async {
            final navigator = GlobalKey<NavigatorState>();
            final boundaryKey = GlobalKey();
            final baseTheme = ThemeData(
              platform: platform,
              brightness: brightness,
              pageTransitionsTheme: settingsPageTransitionsTheme,
            );
            final backdrop = glass
                ? const Color(0xff336699)
                : baseTheme.scaffoldBackgroundColor;
            final theme = glass
                ? baseTheme.copyWith(
                    scaffoldBackgroundColor: Colors.transparent,
                  )
                : baseTheme;
            await tester.pumpWidget(
              RepaintBoundary(
                key: boundaryKey,
                child: MaterialApp(
                  navigatorKey: navigator,
                  theme: theme,
                  builder: (context, child) =>
                      ColoredBox(color: backdrop, child: child!),
                  home: settingsPane('播放设置'),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              await backgroundPixel(tester, boundaryKey),
              backdrop.toARGB32(),
            );

            unawaited(
              navigator.currentState!.push<void>(
                MaterialPageRoute(builder: (_) => settingsPane('规则管理')),
              ),
            );
            await tester.pump();
            for (final duration in [16, 64, 120]) {
              await tester.pump(Duration(milliseconds: duration));
              expect(
                await backgroundPixel(tester, boundaryKey),
                backdrop.toARGB32(),
                reason: 'The incoming pane must preserve the window backdrop.',
              );
            }
            await tester.pumpAndSettle();
            unawaited(
              navigator.currentState!.pushReplacement<void, void>(
                MaterialPageRoute(builder: (_) => settingsPane('界面设置')),
              ),
            );
            await tester.pump();
            for (final duration in [16, 64, 120]) {
              await tester.pump(Duration(milliseconds: duration));
              expect(
                await backgroundPixel(tester, boundaryKey),
                backdrop.toARGB32(),
                reason:
                    'Replacing a settings category must preserve the window backdrop.',
              );
            }
            await tester.pumpAndSettle();
            navigator.currentState!.pop();
            await tester.pump();
            for (final duration in [16, 64, 120]) {
              await tester.pump(Duration(milliseconds: duration));
              expect(
                await backgroundPixel(tester, boundaryKey),
                backdrop.toARGB32(),
                reason: 'The outgoing pane must preserve the window backdrop.',
              );
            }
            await tester.pumpAndSettle();
            expect(
              await backgroundPixel(tester, boundaryKey),
              backdrop.toARGB32(),
            );
          },
        );
      }
    }
  }
}

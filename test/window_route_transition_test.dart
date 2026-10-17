import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/platform/window_effect_service.dart';
import 'package:kazumi/utils/constants.dart';

double _opacity(WidgetTester tester, String page) => tester
    .widgetList<FadeTransition>(
      find.ancestor(
        of: find.byKey(ValueKey(page)),
        matching: find.byType(FadeTransition),
      ),
    )
    .fold(1.0, (opacity, fade) => opacity * fade.opacity.value);

Widget _page(String name) => Scaffold(
  body: Center(child: Text(name, key: ValueKey(name))),
);

Future<List<(Offset, double)>> _entranceFrames(
  WidgetTester tester,
  ThemeData theme,
) async {
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      navigatorKey: navigator,
      theme: theme,
      home: _page('tabs'),
    ),
  );
  await tester.pumpAndSettle();
  unawaited(
    navigator.currentState!.push<void>(
      MaterialPageRoute(builder: (_) => _page('details')),
    ),
  );
  await tester.pump();
  final frames = <(Offset, double)>[];
  for (final milliseconds in [40, 80, 180]) {
    await tester.pump(Duration(milliseconds: milliseconds));
    frames.add((
      tester.getTopLeft(find.byKey(const ValueKey('details'))),
      _opacity(tester, 'details'),
    ));
  }
  await tester.pumpAndSettle();
  return frames;
}

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    testWidgets('${platform.name} preserves the original entrance animation', (
      tester,
    ) async {
      final effects = WindowEffectService(
        materials: [WindowMaterial.disabled, WindowMaterial.transparent],
        initializeNative: () async {},
        applyNative: (_, _, _) async {},
      );
      addTearDown(effects.dispose);
      await effects.initialize(material: 'transparent');
      final base = ThemeData(
        platform: platform,
        pageTransitionsTheme: pageTransitionsTheme2024,
      );
      final original = await _entranceFrames(
        tester,
        base.copyWith(scaffoldBackgroundColor: Colors.transparent),
      );
      final corrected = await _entranceFrames(
        tester,
        effects.decorateTheme(base),
      );
      expect(corrected, original);
    });

    for (final brightness in Brightness.values) {
      testWidgets(
        '${platform.name} ${brightness.name} transparent full-page navigation fades both pages',
        (tester) async {
          final effects = WindowEffectService(
            materials: [WindowMaterial.disabled, WindowMaterial.transparent],
            initializeNative: () async {},
            applyNative: (_, _, _) async {},
          );
          addTearDown(effects.dispose);
          await effects.initialize(material: 'transparent');
          final theme = effects.decorateTheme(
            ThemeData(
              platform: platform,
              brightness: brightness,
              pageTransitionsTheme: pageTransitionsTheme2024,
            ),
          );
          final navigator = GlobalKey<NavigatorState>();
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigator,
              theme: theme,
              // The main shell has a short custom entrance animation. It must
              // also receive the incoming Material route's outgoing transition.
              onGenerateRoute: (_) => PageRouteBuilder<void>(
                transitionDuration: const Duration(milliseconds: 70),
                pageBuilder: (_, _, _) => _page('tabs'),
                transitionsBuilder: (_, animation, _, child) =>
                    FadeTransition(opacity: animation, child: child),
              ),
            ),
          );
          await tester.pumpAndSettle();

          const pages = ['tabs', 'search', 'info', 'history', 'settings'];
          for (var i = 1; i < pages.length; i++) {
            unawaited(
              navigator.currentState!.push<void>(
                MaterialPageRoute(builder: (_) => _page(pages[i])),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 40));
            expect(_opacity(tester, pages[i - 1]), inExclusiveRange(0, 1));
            expect(_opacity(tester, pages[i]), inExclusiveRange(0, 1));
            final previousOpacity = _opacity(tester, pages[i - 1]);
            await tester.pump(const Duration(milliseconds: 80));
            expect(_opacity(tester, pages[i - 1]), lessThan(previousOpacity));
            await tester.pumpAndSettle();
            expect(_opacity(tester, pages[i]), 1);
          }

          for (var i = pages.length - 1; i > 0; i--) {
            navigator.currentState!.pop();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 40));
            expect(_opacity(tester, pages[i]), inExclusiveRange(0, 1));
            expect(_opacity(tester, pages[i - 1]), inExclusiveRange(0, 1));
            await tester.pumpAndSettle();
            expect(_opacity(tester, pages[i - 1]), 1);
            expect(find.byKey(ValueKey(pages[i])), findsNothing);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

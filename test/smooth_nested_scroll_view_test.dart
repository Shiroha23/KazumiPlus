import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/smooth_nested_scroll_view.dart';

Future<NestedScrollViewState> mountView(
  WidgetTester tester, {
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(
          body: DefaultTabController(
            length: 2,
            child: SmoothNestedScrollView(
              headerSliverBuilder: (_, _) => [
                const SliverAppBar(
                  expandedHeight: 256,
                  pinned: true,
                  bottom: TabBar(
                    tabs: [
                      Tab(text: '概览'),
                      Tab(text: '吐槽'),
                    ],
                  ),
                ),
              ],
              body: TabBarView(
                children: [
                  for (var tab = 0; tab < 2; tab++)
                    ScrollConfiguration(
                      behavior: const ScrollBehavior().copyWith(
                        scrollbars: false,
                      ),
                      child: ListView.builder(
                        key: PageStorageKey(tab),
                        itemExtent: 100,
                        itemCount: 100,
                        itemBuilder: (_, index) => Text('$tab / $index'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
}

Future<void> wheel(
  WidgetTester tester,
  double delta, {
  PointerDeviceKind kind = PointerDeviceKind.mouse,
  Offset? position,
}) => tester.sendEventToBinding(
  PointerScrollEvent(
    position: position ?? tester.getCenter(find.byType(ListView).hitTestable()),
    scrollDelta: Offset(0, delta),
    kind: kind,
  ),
);

double offset(NestedScrollViewState state) =>
    state.outerController.offset + state.innerController.positions.first.pixels;

void main() {
  testWidgets('wheel smoothly crosses from header into body and reverses', (
    tester,
  ) async {
    final state = await mountView(tester);
    await wheel(tester, 500);
    expect(offset(state), 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(offset(state), inExclusiveRange(0, 500));
    await wheel(tester, 100);
    await tester.pumpAndSettle();
    expect(offset(state), closeTo(600, .01));
    expect(
      state.outerController.offset,
      state.outerController.position.maxScrollExtent,
    );
    expect(state.innerController.offset, greaterThan(0));
    expect(state.outerController.position.isScrollingNotifier.value, isFalse);
    expect(state.innerController.position.isScrollingNotifier.value, isFalse);
    await wheel(tester, -1000);
    await tester.pumpAndSettle();
    expect(offset(state), closeTo(0, .01));
  });

  testWidgets('header wheel input also animates', (tester) async {
    final state = await mountView(tester);
    await wheel(tester, 120, position: const Offset(200, 100));
    expect(offset(state), 0);
    await tester.pumpAndSettle();
    expect(offset(state), closeTo(120, .01));
  });

  testWidgets(
    'reversing discards the pending target and clamps at the bottom',
    (tester) async {
      final state = await mountView(tester);
      await wheel(tester, 1000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final beforeReverse = offset(state);
      await wheel(tester, -80);
      await tester.pumpAndSettle();
      expect(offset(state), closeTo(beforeReverse - 80, .01));
      await wheel(tester, 100000);
      await tester.pumpAndSettle();
      expect(
        state.innerController.offset,
        state.innerController.position.maxScrollExtent,
      );
      expect(state.innerController.position.isScrollingNotifier.value, isFalse);
    },
  );

  testWidgets('inner scroll ends once after wheel animation for pagination', (
    tester,
  ) async {
    final state = await mountView(tester);
    final inner = state.innerController.position;
    var ends = 0;
    inner.isScrollingNotifier.addListener(() {
      if (!inner.isScrollingNotifier.value) ends++;
    });
    await wheel(tester, 500);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await wheel(tester, 120);
    await tester.pumpAndSettle();
    expect(ends, 1);
  });

  testWidgets('trackpad and reduced motion retain native scrolling', (
    tester,
  ) async {
    var state = await mountView(tester);
    await wheel(tester, 120, kind: PointerDeviceKind.trackpad);
    expect(offset(state), 120);
    await tester.pumpWidget(const SizedBox.shrink());
    state = await mountView(tester, disableAnimations: true);
    await wheel(tester, 120);
    expect(offset(state), 120);
  });

  testWidgets('touch interrupts wheel animation', (tester) async {
    final state = await mountView(tester);
    await wheel(tester, 600);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListView).hitTestable()),
    );
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    final afterDrag = offset(state);
    await tester.pump(const Duration(milliseconds: 300));
    expect(offset(state), afterDrag);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('tab switching and disposal during motion leave no errors', (
    tester,
  ) async {
    await mountView(tester);
    await wheel(tester, 600);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.text('吐槽'));
    await tester.pumpAndSettle();
    final state = tester.state<NestedScrollViewState>(
      find.byType(NestedScrollView),
    );
    expect(state.outerController.position.isScrollingNotifier.value, isFalse);
    expect(state.innerController.position.isScrollingNotifier.value, isFalse);
    await wheel(tester, 200);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

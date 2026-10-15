import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/smooth_scroll.dart';

Future<void> wheel(
  WidgetTester tester,
  Offset delta, {
  PointerDeviceKind kind = PointerDeviceKind.mouse,
}) => tester.sendEventToBinding(
  PointerScrollEvent(
    position: tester.getCenter(find.byType(ListView)),
    scrollDelta: delta,
    kind: kind,
  ),
);

Future<SmoothScrollController> mountList(
  WidgetTester tester, {
  bool disableAnimations = false,
  TargetPlatform platform = TargetPlatform.windows,
  Axis axis = Axis.vertical,
  bool reverse = false,
  ScrollPhysics? physics,
}) async {
  late SmoothScrollController controller;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: SmoothScroll(
          builder: (context, scrollController) {
            controller = scrollController as SmoothScrollController;
            return ListView.builder(
              controller: controller,
              scrollDirection: axis,
              reverse: reverse,
              physics: physics,
              itemExtent: 100,
              itemCount: 100,
              itemBuilder: (_, index) => Text('Item $index'),
            );
          },
        ),
      ),
    ),
  );
  return controller;
}

void main() {
  testWidgets('wheel input animates and accumulates consecutive notches', (
    tester,
  ) async {
    final controller = await mountList(tester);
    await wheel(tester, const Offset(0, 120));
    expect(controller.offset, 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(controller.offset, inExclusiveRange(0, 120));
    await wheel(tester, const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(240, 0.01));
  });

  testWidgets('changing direction cancels the pending forward target', (
    tester,
  ) async {
    final controller = await mountList(tester);
    controller.jumpTo(500);
    await wheel(tester, const Offset(0, 120));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final beforeReverse = controller.offset;
    await wheel(tester, const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(beforeReverse - 80, 0.01));
  });

  testWidgets('wheel targets stay within both scroll boundaries', (
    tester,
  ) async {
    final controller = await mountList(tester);
    controller.jumpTo(controller.position.maxScrollExtent - 20);
    await wheel(tester, const Offset(0, 1000));
    await wheel(tester, const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);
    controller.jumpTo(20);
    await wheel(tester, const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
  });

  testWidgets('programmatic jumps discard pending wheel motion', (
    tester,
  ) async {
    final controller = await mountList(tester);
    await wheel(tester, const Offset(0, 120));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    controller.jumpTo(1000);
    await wheel(tester, const Offset(0, 80));
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(1080, 0.01));
  });

  testWidgets('reduced motion uses immediate native wheel scrolling', (
    tester,
  ) async {
    final controller = await mountList(tester, disableAnimations: true);
    await wheel(tester, const Offset(0, 120));
    expect(controller.offset, 120);
  });

  testWidgets('trackpad pointer signals keep native scrolling', (tester) async {
    final controller = await mountList(tester);
    await wheel(tester, const Offset(0, 120), kind: PointerDeviceKind.trackpad);
    expect(controller.offset, 120);
  });

  testWidgets('mobile wheel scrolling stays native', (tester) async {
    final controller = await mountList(
      tester,
      platform: TargetPlatform.android,
    );
    await wheel(tester, const Offset(0, 120));
    expect(controller.offset, 120);
  });

  testWidgets('horizontal reversed lists keep their native direction', (
    tester,
  ) async {
    final controller = await mountList(
      tester,
      axis: Axis.horizontal,
      reverse: true,
    );
    await wheel(tester, const Offset(-120, 0));
    expect(controller.offset, 0);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(120, 0.01));
  });

  testWidgets('disabled user scrolling does not animate', (tester) async {
    final controller = await mountList(
      tester,
      physics: const NeverScrollableScrollPhysics(),
    );
    await wheel(tester, const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
  });

  testWidgets('shift wheel scrolls a horizontal list', (tester) async {
    final controller = await mountList(tester, axis: Axis.horizontal);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await wheel(tester, const Offset(0, 120));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(120, 0.01));
  });

  testWidgets('touch dragging interrupts pending wheel motion', (tester) async {
    final controller = await mountList(tester);
    await wheel(tester, const Offset(0, 600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
    );
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    final draggedOffset = controller.offset;
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.offset, draggedOffset);
    expect(controller.offset, lessThan(600));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('disposing during wheel animation removes input handlers', (
    tester,
  ) async {
    await mountList(tester);
    await wheel(tester, const Offset(0, 120));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(10, 10),
        scrollDelta: Offset(0, 120),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

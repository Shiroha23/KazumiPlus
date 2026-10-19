import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Smooth wheel scrolling across a collapsing header and its inner tab views.
/// Keeps NestedScrollView's own controllers for touch and scroll coordination.
class SmoothNestedScrollView extends StatefulWidget {
  const SmoothNestedScrollView({
    super.key,
    required this.headerSliverBuilder,
    required this.body,
  });

  final NestedScrollViewHeaderSliversBuilder headerSliverBuilder;
  final Widget body;

  @override
  State<SmoothNestedScrollView> createState() => _SmoothNestedScrollViewState();
}

class _SmoothNestedScrollViewState extends State<SmoothNestedScrollView>
    with SingleTickerProviderStateMixin {
  final _nestedKey = GlobalKey<NestedScrollViewState>();
  late final _animation = AnimationController.unbounded(vsync: this)
    ..addListener(_tick);
  final _activities = <ScrollPosition, _NestedWheelActivity>{};
  double _target = 0;
  double _lastDelta = 0;
  bool _installing = false;
  bool _disposed = false;

  void _stop() {
    if (_installing || _disposed) return;
    _animation.stop();
    final activities = Map.of(_activities);
    // Native drag/tab changes may dispose several activities together. Wait
    // until that completes before finishing any remaining wheel activities.
    scheduleMicrotask(() {
      if (!_disposed) _finish(activities);
    });
  }

  void _finish(Map<ScrollPosition, _NestedWheelActivity> activities) {
    _installing = true;
    for (final entry in activities.entries) {
      if (!entry.value.isDisposed) {
        (entry.key as ScrollActivityDelegate).goBallistic(0);
      }
    }
    _installing = false;
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.kind != PointerDeviceKind.mouse) {
      _stop();
      return;
    }
    final platform = Theme.of(context).platform;
    if ((platform != TargetPlatform.windows &&
            platform != TargetPlatform.linux &&
            platform != TargetPlatform.macOS) ||
        MediaQuery.disableAnimationsOf(context) ||
        HardwareKeyboard.instance.logicalKeysPressed.any(
          ScrollConfiguration.of(context).pointerAxisModifiers.contains,
        )) {
      _stop();
      return;
    }
    final nested = _nestedKey.currentState;
    if (nested == null || !nested.outerController.hasClients) return;
    final positions = [
      nested.outerController.position,
      ...nested.innerController.positions,
    ];
    if (positions.any((position) => !position.hasContentDimensions)) return;
    final outer = positions.first;
    if (!outer.physics.shouldAcceptUserOffset(outer) &&
        !positions
            .skip(1)
            .any(
              (position) => position.physics.shouldAcceptUserOffset(position),
            )) {
      return;
    }
    final delta = event.scrollDelta.dy;
    if (delta == 0) return;
    final innerOffset = positions
        .skip(1)
        .fold<double>(
          0,
          (offset, position) =>
              math.max(offset, position.pixels - position.minScrollExtent),
        );
    final offset = outer.pixels - outer.minScrollExtent + innerOffset;
    final extent =
        outer.maxScrollExtent -
        outer.minScrollExtent +
        positions
            .skip(1)
            .fold<double>(
              0,
              (extent, position) => math.max(
                extent,
                position.maxScrollExtent - position.minScrollExtent,
              ),
            );
    final continuing =
        _animation.isAnimating &&
        delta.sign == _lastDelta.sign &&
        positions.length == _activities.length &&
        positions.every(
          (position) => _activities[position]?.isDisposed == false,
        );
    final target = ((continuing ? _target : offset) + delta)
        .clamp(0.0, extent)
        .toDouble();
    if (target == offset) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      event.respond(allowPlatformDefault: false);
      _animation.stop();
      _installing = true;
      _animation.value = offset;
      _target = target;
      _lastDelta = delta;
      _activities.clear();
      for (final position in positions) {
        final activity = _NestedWheelActivity(
          position as ScrollActivityDelegate,
          onDispose: _stop,
        );
        _activities[position] = activity;
        position.beginActivity(activity);
      }
      _installing = false;
      _animation
          .animateTo(
            target,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          )
          .whenCompleteOrCancel(() {
            if (mounted && _animation.value == _target) {
              _finish(Map.of(_activities));
            }
          });
    });
  }

  void _tick() {
    if (_activities.isEmpty || _installing) return;
    final positions = _activities.keys.toList(growable: false);
    if (positions.any((position) => _activities[position]!.isDisposed)) {
      _stop();
      return;
    }
    final outer = positions.first;
    final outerExtent = outer.maxScrollExtent - outer.minScrollExtent;
    for (final position in positions) {
      final value = identical(position, outer)
          ? _animation.value
          : _animation.value - outerExtent;
      position.setPixels(
        (position.minScrollExtent + value)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble(),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _WheelCapture(
    onSignal: _onSignal,
    child: NestedScrollView(
      key: _nestedKey,
      headerSliverBuilder: widget.headerSliverBuilder,
      body: widget.body,
    ),
  );
}

class _NestedWheelActivity extends ScrollActivity {
  _NestedWheelActivity(super.delegate, {required this.onDispose});

  final VoidCallback onDispose;
  bool isDisposed = false;

  @override
  bool get shouldIgnorePointer => false;

  @override
  bool get isScrolling => true;

  @override
  double get velocity => 0;

  @override
  void dispose() {
    isDisposed = true;
    onDispose();
    super.dispose();
  }
}

class _WheelCapture extends SingleChildRenderObjectWidget {
  const _WheelCapture({required this.onSignal, required super.child});

  final PointerSignalEventListener onSignal;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderWheelCapture(onSignal);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderWheelCapture renderObject,
  ) {
    renderObject.onSignal = onSignal;
  }
}

class _RenderWheelCapture extends RenderProxyBox {
  _RenderWheelCapture(this.onSignal);

  PointerSignalEventListener onSignal;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    // Register before the nested view's native wheel handlers. A normal
    // Listener outside the view runs after them and cannot smooth their input.
    result.add(BoxHitTestEntry(this, position));
    hitTestChildren(result, position: position);
    return true;
  }

  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    if (event is PointerSignalEvent) onSignal(event);
  }
}

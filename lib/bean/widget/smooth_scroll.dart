import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A scroll controller that animates desktop mouse wheel input.
class SmoothScrollController extends ScrollController {
  SmoothScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
    super.onAttach,
    super.onDetach,
  });

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _SmoothScrollPosition(
    physics: physics,
    context: context,
    initialPixels: initialScrollOffset,
    keepScrollOffset: keepScrollOffset,
    oldPosition: oldPosition,
    debugLabel: debugLabel,
  );
}

class _SmoothScrollPosition extends ScrollPositionWithSingleContext {
  _SmoothScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  }) {
    GestureBinding.instance.pointerRouter.addGlobalRoute(_trackPointerSignal);
  }

  PointerDeviceKind? _signalKind;
  ScrollActivity? _wheelActivity;
  double _target = 0;
  double _lastDelta = 0;

  void _trackPointerSignal(PointerEvent event) {
    // Global routes run before the pointer signal resolver calls pointerScroll.
    _signalKind = event is PointerScrollEvent ? event.kind : null;
  }

  @override
  void pointerScroll(double delta) {
    final buildContext = context.storageContext;
    final platform = Theme.of(buildContext).platform;
    final desktop =
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.macOS;
    if (delta == 0 ||
        _signalKind != PointerDeviceKind.mouse ||
        !desktop ||
        MediaQuery.disableAnimationsOf(buildContext)) {
      super.pointerScroll(delta);
      return;
    }

    final continuing =
        identical(activity, _wheelActivity) && delta.sign == _lastDelta.sign;
    final target = ((continuing ? _target : pixels) + delta)
        .clamp(minScrollExtent, maxScrollExtent)
        .toDouble();
    if (target == pixels) return;

    final motion = _WheelScrollActivity(
      this,
      from: pixels,
      to: target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      vsync: context.vsync,
    );
    beginActivity(motion);
    _target = target;
    _lastDelta = delta;
    _wheelActivity = motion;
    updateUserScrollDirection(
      delta > 0 ? ScrollDirection.reverse : ScrollDirection.forward,
    );
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _trackPointerSignal,
    );
    super.dispose();
  }
}

class _WheelScrollActivity extends DrivenScrollActivity {
  _WheelScrollActivity(
    super.delegate, {
    required super.from,
    required super.to,
    required super.duration,
    required super.curve,
    required super.vsync,
  });

  // Wheel motion must leave links clickable and allow touch drags to interrupt.
  @override
  bool get shouldIgnorePointer => false;
}

/// Owns a smooth controller for scroll views without an existing controller.
class SmoothScroll extends StatefulWidget {
  const SmoothScroll({super.key, required this.builder});

  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  @override
  State<SmoothScroll> createState() => _SmoothScrollState();
}

class _SmoothScrollState extends State<SmoothScroll> {
  final _controller = SmoothScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}

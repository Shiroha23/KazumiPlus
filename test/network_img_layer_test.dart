import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';

void main() {
  late ui.Image initialFrame;
  late ui.Image intermediateFrame;
  late ui.Image newFrame;

  setUpAll(() async {
    initialFrame = await createTestImage(width: 16, height: 24);
    intermediateFrame = await createTestImage(width: 24, height: 36);
    newFrame = await createTestImage(width: 32, height: 48);
  });

  tearDownAll(() {
    initialFrame.dispose();
    intermediateFrame.dispose();
    newFrame.dispose();
  });

  testWidgets('keeps the cover visible during consecutive resize decodes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(imageCache.clear);
    addTearDown(imageCache.clearLiveImages);

    const url = 'https://example.com/cover.png';
    final initial = await _pendingDecode(url, 120);
    initial.complete(ImageInfo(image: initialFrame.clone()));
    final resized = await _pendingDecode(url, 160);
    final resizedAgain = await _pendingDecode(url, 200);

    await tester.pumpWidget(_cover(url, 120));
    await tester.pumpAndSettle();
    expect(_hasFrame(tester, 16), isTrue);

    for (final width in [160.0, 200.0]) {
      await tester.pumpWidget(_cover(url, width));
      await tester.pump();
      expect(
        _hasFrame(tester, 16),
        isTrue,
        reason: 'The old cover must stay visible until decoding finishes.',
      );
    }

    resizedAgain.complete(ImageInfo(image: newFrame.clone()));
    await tester.pumpAndSettle();
    expect(_hasFrame(tester, 32), isTrue);

    resized.complete(ImageInfo(image: intermediateFrame.clone()));
    await tester.pumpAndSettle();
    expect(
      _hasFrame(tester, 32),
      isTrue,
      reason: 'An older decode must not replace the latest cover.',
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('does not keep the previous cover when the URL changes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(imageCache.clear);
    addTearDown(imageCache.clearLiveImages);

    const url = 'https://example.com/first.png';
    const nextUrl = 'https://example.com/second.png';
    final initial = await _pendingDecode(url, 120);
    initial.complete(ImageInfo(image: initialFrame.clone()));
    final next = await _pendingDecode(nextUrl, 120);

    await tester.pumpWidget(_cover(url, 120));
    await tester.pumpAndSettle();
    expect(_hasFrame(tester, 16), isTrue);

    await tester.pumpWidget(_cover(nextUrl, 120));
    await tester.pump();
    expect(_hasFrame(tester, 16), isFalse);

    next.complete(ImageInfo(image: newFrame.clone()));
    await tester.pumpAndSettle();
    expect(_hasFrame(tester, 32), isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}

Future<Completer<ImageInfo>> _pendingDecode(String url, int width) async {
  final provider = ResizeImage.resizeIfNeeded(
    width,
    null,
    CachedNetworkImageProvider(url),
  );
  final key = await provider.obtainKey(ImageConfiguration.empty);
  final frame = Completer<ImageInfo>();
  imageCache.putIfAbsent(key, () => OneFrameImageStreamCompleter(frame.future));
  return frame;
}

Widget _cover(String url, double width) {
  return MaterialApp(
    home: Center(
      child: NetworkImgLayer(
        src: url,
        width: width,
        height: width * 1.5,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
      ),
    ),
  );
}

bool _hasFrame(WidgetTester tester, int width) => tester
    .widgetList<RawImage>(find.byType(RawImage))
    .any((image) => image.image?.width == width);

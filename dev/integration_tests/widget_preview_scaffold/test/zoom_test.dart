// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widget_preview_scaffold/src/controls.dart';
import 'package:widget_preview_scaffold/src/widget_preview_rendering.dart';

void main() {
  group('ZoomControls', () {
    late TransformationController controller;

    setUp(() {
      controller = TransformationController();
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets('displays initial state correctly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZoomControls(transformationController: controller),
          ),
        ),
      );

      expect(find.byTooltip('Zoom in'), findsOneWidget);
      expect(find.byTooltip('Zoom out'), findsOneWidget);
      expect(find.byTooltip('Reset zoom'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);

      final IconButton zoomInButton = tester.widget(
        find.widgetWithIcon(IconButton, Icons.zoom_in_sharp),
      );
      final IconButton zoomOutButton = tester.widget(
        find.widgetWithIcon(IconButton, Icons.zoom_out),
      );
      final IconButton resetButton = tester.widget(
        find.widgetWithIcon(IconButton, Icons.zoom_out_map),
      );
      expect(zoomInButton.onPressed, isNotNull);
      expect(zoomOutButton.onPressed, isNotNull);
      expect(resetButton.onPressed, isNull);

      await tester.tap(find.byTooltip('Reset zoom'));
      await tester.pump();
      expect(controller.value.entry(0, 0), equals(1.0));
    });

    testWidgets('Zoom in and Zoom out linearly across 25% to 400%', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZoomControls(transformationController: controller),
          ),
        ),
      );

      // Zoom out below 100% down to 25%.
      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pumpAndSettle();
      expect(controller.value.entry(0, 0), equals(0.75));
      expect(find.text('75%'), findsOneWidget);

      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pumpAndSettle();
      expect(controller.value.entry(0, 0), equals(0.5));
      expect(find.text('50%'), findsOneWidget);

      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pumpAndSettle();
      expect(controller.value.entry(0, 0), equals(0.25));
      expect(find.text('25%'), findsOneWidget);

      // Clamped at 25%: Zoom out button is disabled.
      final IconButton minZoomOutButton = tester.widget(
        find.widgetWithIcon(IconButton, Icons.zoom_out),
      );
      expect(minZoomOutButton.onPressed, isNull);
      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pump();
      expect(controller.value.entry(0, 0), equals(0.25));

      // Reset back to 100% from zoomed-out state.
      await tester.tap(find.byTooltip('Reset zoom'));
      await tester.pumpAndSettle();
      expect(controller.value.entry(0, 0), equals(1.0));
      expect(find.text('100%'), findsOneWidget);

      // Zoom in above 100%.
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pumpAndSettle();
      expect(controller.value.entry(0, 0), equals(1.25));
      expect(find.text('125%'), findsOneWidget);

      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pumpAndSettle();
      expect(controller.value.entry(0, 0), equals(1.50));
      expect(find.text('150%'), findsOneWidget);

      // Clamped at 400%: Zoom in button is disabled.
      controller.value = Matrix4.diagonal3Values(3.75, 3.75, 1.0);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pumpAndSettle();
      expect(controller.value.entry(0, 0), equals(4.0));
      expect(find.text('400%'), findsOneWidget);
      final IconButton maxZoomInButton = tester.widget(
        find.widgetWithIcon(IconButton, Icons.zoom_in_sharp),
      );
      expect(maxZoomInButton.onPressed, isNull);
    });

    testWidgets('Reset zoom is disabled at 100% and enabled at 50% and 150%', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZoomControls(transformationController: controller),
          ),
        ),
      );

      final Finder resetIconButton = find.widgetWithIcon(
        IconButton,
        Icons.zoom_out_map,
      );
      expect(tester.widget<IconButton>(resetIconButton).onPressed, isNull);

      // Zoom out to 50% -> Reset enabled -> resets to 100% and disables again.
      controller.value = Matrix4.diagonal3Values(0.5, 0.5, 1.0);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(resetIconButton).onPressed, isNotNull);
      await tester.tap(find.byTooltip('Reset zoom'));
      await tester.pumpAndSettle();
      expect(controller.value.entry(0, 0), equals(1.0));
      expect(find.text('100%'), findsOneWidget);
      expect(tester.widget<IconButton>(resetIconButton).onPressed, isNull);

      // Zoom in to 150% -> Reset enabled -> resets to 100%.
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pumpAndSettle();
      expect(controller.value.entry(0, 0), equals(1.5));
      expect(tester.widget<IconButton>(resetIconButton).onPressed, isNotNull);

      await tester.tap(find.byTooltip('Reset zoom'));
      await tester.pumpAndSettle();
      expect(controller.value.entry(0, 0), equals(1.0));
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('Slider updates scale correctly across 25% to 400%', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZoomControls(transformationController: controller),
          ),
        ),
      );

      final Slider slider = tester.widget(find.byType(Slider));
      expect(slider.min, equals(kMinPreviewZoom));
      expect(slider.max, equals(kMaxPreviewZoom));
      expect(slider.value, equals(1.0));

      controller.value = Matrix4.diagonal3Values(0.5, 0.5, 1.0);
      await tester.pumpAndSettle();
      expect(find.text('50%'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).value, equals(0.5));

      controller.value = Matrix4.diagonal3Values(2.5, 2.5, 1.0);
      await tester.pumpAndSettle();

      expect(find.text('250%'), findsOneWidget);
      final Slider updatedSlider = tester.widget(find.byType(Slider));
      expect(updatedSlider.value, equals(2.5));
    });
  });

  group('ZoomablePreviewArea', () {
    late TransformationController controller;

    setUp(() {
      controller = TransformationController();
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets(
      'renders scaled layout wrapper when no tree construction error',
      (WidgetTester tester) async {
        const childKey = Key('preview_child');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ZoomablePreviewArea(
                transformationController: controller,
                errorThrownDuringTreeConstruction: false,
                child: const SizedBox(key: childKey, width: 100, height: 100),
              ),
            ),
          ),
        );

        expect(find.byKey(childKey), findsOneWidget);
        expect(find.byType(ScaledPreviewLayout), findsOneWidget);
        expect(find.byType(SingleChildScrollView), findsNWidgets(2));
      },
    );

    testWidgets(
      'supports Ctrl and Cmd scroll-wheel zoom, accumulates fractional trackpad deltas, and prevents inner scrollable jump',
      (WidgetTester tester) async {
        const childKey = Key('zoom_scroll_child');
        final innerScrollController = ScrollController();
        addTearDown(innerScrollController.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ZoomablePreviewArea(
                transformationController: controller,
                errorThrownDuringTreeConstruction: false,
                child: SizedBox(
                  key: childKey,
                  width: 200,
                  height: 200,
                  child: ListView(
                    controller: innerScrollController,
                    children: const <Widget>[
                      SizedBox(height: 300),
                      SizedBox(height: 300),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        final pointer = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(
          pointer.hover(tester.getCenter(find.byKey(childKey))),
        );

        // Unmodified wheel scrolls the inner ListView without zooming.
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 40)));
        await tester.pump();
        expect(controller.value.entry(0, 0), equals(1.0));
        expect(innerScrollController.offset, greaterThan(0.0));
        final double baselineScrollOffset = innerScrollController.offset;

        // Fractional trackpad deltas accumulate before stepping by 25%, without
        // scrolling the inner ListView while Ctrl is held.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        for (var i = 0; i < 3; i++) {
          await tester.sendEventToBinding(pointer.scroll(const Offset(0, -5)));
        }
        await tester.pump();
        expect(controller.value.entry(0, 0), equals(1.0));
        expect(innerScrollController.offset, equals(baselineScrollOffset));

        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -5)));
        await tester.pump();
        expect(controller.value.entry(0, 0), equals(1.25));
        expect(innerScrollController.offset, equals(baselineScrollOffset));

        // Discrete wheel notch down zooms out (-0.25).
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 20)));
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 20)));
        await tester.pump();
        expect(controller.value.entry(0, 0), equals(0.75));
        expect(innerScrollController.offset, equals(baselineScrollOffset));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

        // Cmd + wheel clamps at 25% and 400%.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        for (var i = 0; i < 4; i++) {
          await tester.sendEventToBinding(pointer.scroll(const Offset(0, 20)));
        }
        await tester.pump();
        expect(controller.value.entry(0, 0), equals(kMinPreviewZoom));

        controller.value = Matrix4.diagonal3Values(3.75, 3.75, 1.0);
        await tester.pump();
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -20)));
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -20)));
        await tester.pump();
        expect(controller.value.entry(0, 0), equals(kMaxPreviewZoom));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      },
    );

    testWidgets(
      'renders unscaled child directly when tree construction error occurred',
      (WidgetTester tester) async {
        const childKey = Key('error_child');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ZoomablePreviewArea(
                transformationController: controller,
                errorThrownDuringTreeConstruction: true,
                child: const SizedBox(key: childKey, width: 100, height: 100),
              ),
            ),
          ),
        );

        expect(find.byKey(childKey), findsOneWidget);
        // It shouldn't be wrapped inside SingleChildScrollView or any scaling logic
        expect(find.byType(SingleChildScrollView), findsNothing);
      },
    );
  });
}

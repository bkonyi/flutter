// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert'
    show base64Decode, base64Encode, jsonDecode, jsonEncode, utf8;
import 'dart:ui' as ui;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widget_preview_scaffold/src/dtd/dtd_services.dart';
import 'package:widget_preview_scaffold/src/dtd/editor_service.dart';
import 'package:widget_preview_scaffold/src/utils.dart';
import 'package:widget_preview_scaffold/src/widget_preview.dart';
import 'package:widget_preview_scaffold/src/widget_preview_rendering.dart';
import 'package:widget_preview_scaffold/src/widget_preview_scaffold_controller.dart';

import 'utils/widget_preview_scaffold_test_utils.dart';

final class _CaptureMaterialPreviewTheme extends PreviewThemeData {
  const _CaptureMaterialPreviewTheme({
    required this.darkColor,
    required this.lightColor,
  });

  final Color darkColor;
  final Color lightColor;

  @override
  Widget apply(BuildContext context, Widget child) {
    final Brightness brightness = MediaQuery.platformBrightnessOf(context);
    final Color surface = brightness == Brightness.dark
        ? darkColor
        : lightColor;
    final ThemeData base = brightness == Brightness.dark
        ? ThemeData.dark()
        : ThemeData.light();
    return Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(surface: surface),
      ),
      child: child,
    );
  }
}

final class _CaptureCupertinoPreviewTheme extends PreviewThemeData {
  const _CaptureCupertinoPreviewTheme({
    required this.darkColor,
    required this.lightColor,
  });

  final Color darkColor;
  final Color lightColor;

  @override
  Widget apply(BuildContext context, Widget child) {
    final Brightness brightness = MediaQuery.platformBrightnessOf(context);
    return CupertinoTheme(
      data: CupertinoThemeData(
        brightness: brightness,
        primaryColor: brightness == Brightness.dark ? darkColor : lightColor,
      ),
      child: child,
    );
  }
}

const _kLightSurfaceColor = Color(0xFFF5F5FF);
const _kDarkSurfaceColor = Color(0xFF101828);
const _kLightCupertinoColor = Color(0xFF0066CC);
const _kDarkCupertinoColor = Color(0xFF66B2FF);

PreviewThemeData _buildTestTheme() =>
    const MultiPreviewThemeData(<PreviewThemeData>[
      _CaptureMaterialPreviewTheme(
        darkColor: _kDarkSurfaceColor,
        lightColor: _kLightSurfaceColor,
      ),
      _CaptureCupertinoPreviewTheme(
        darkColor: _kDarkCupertinoColor,
        lightColor: _kLightCupertinoColor,
      ),
    ]);

Future<({int height, Uint8List rgba, int width})> _decodePngRgba(
  String imageBase64,
) async {
  expect(imageBase64, isNot(startsWith('data:')));
  final Uint8List pngBytes = base64Decode(imageBase64);
  // Verify PNG magic signature.
  expect(
    pngBytes.sublist(0, 8),
    equals(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
  );
  final ui.Codec codec = await ui.instantiateImageCodec(pngBytes);
  try {
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image image = frame.image;
    try {
      final ByteData byteData = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return (
        height: image.height,
        rgba: Uint8List.fromList(Uint8List.sublistView(byteData)),
        width: image.width,
      );
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

int _countDifferingBytes(Uint8List a, Uint8List b) {
  expect(a.length, b.length);
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      diff++;
    }
  }
  return diff;
}

class _ThrowingDescendantBuildWidget extends StatelessWidget {
  const _ThrowingDescendantBuildWidget();

  @override
  Widget build(BuildContext context) {
    throw StateError('staged descendant build failure');
  }
}

final class _ThrowingApplyPreviewTheme extends PreviewThemeData {
  const _ThrowingApplyPreviewTheme();

  @override
  Widget apply(BuildContext context, Widget child) {
    throw StateError('staged theme apply failure');
  }
}

PreviewThemeData _throwingThemeCallback() {
  throw StateError('staged theme callback failure');
}

PreviewThemeData _throwingApplyThemeCallback() =>
    const _ThrowingApplyPreviewTheme();

PreviewLocalizationsData _throwingLocalizationsCallback() {
  throw StateError('staged localizations callback failure');
}

PreviewLocalizationsData _defaultCaptureLocalizations() =>
    const PreviewLocalizationsData(
      locale: Locale('en', 'US'),
      localizationsDelegates: <LocalizationsDelegate<Object?>>[
        DefaultMaterialLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
    );

void main() {
  final LiveTestWidgetsFlutterBinding binding =
      LiveTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'captures previews filtered out by _filterBySelectedFile or unbuilt off-screen in SliverList',
    (tester) async {
      final dtdServices = FakeWidgetPreviewScaffoldDtdServices();
      final controller = WidgetPreviewScaffoldController(
        dtdServicesOverride: dtdServices,
        previews: () => <WidgetPreview>[
          for (var i = 0; i < 24; i++)
            buildWidgetPreview(
              column: 1,
              functionName: 'spacerPreview$i',
              libraryUri: 'package:my_app/spacers.dart',
              line: i + 1,
              packageName: 'my_app',
              previewFunction: () => SizedBox(
                width: 200,
                height: 300,
                child: Text('Spacer Group $i'),
              ),
              scriptUri: 'file:///project/lib/spacers.dart',
              transformedPreview: Preview(
                group: 'Group $i',
                name: 'Spacer $i',
              ).transform(),
            ),
          buildWidgetPreview(
            column: 4,
            functionName: 'tailOffscreenPreview',
            libraryUri: 'package:my_app/offscreen.dart',
            line: 50,
            packageName: 'my_app',
            previewFunction: () => const ColoredBox(
              color: Color(0xFF22AA44),
              child: SizedBox(
                width: 180,
                height: 90,
                child: Center(child: Text('Tail Offscreen Target')),
              ),
            ),
            scriptUri: 'file:///project/lib/offscreen.dart',
            transformedPreview: const Preview(
              group: 'Group 24',
              name: 'Tail Card',
            ).transform(),
          ),
        ],
      );
      await controller.initialize();

      // Keep _filterBySelectedFile == true and select spacers.dart so offscreen.dart
      // is completely excluded from filteredPreviewSetListenable.
      expect(controller.filterBySelectedFileListenable.value, isTrue);
      dtdServices.selectedSourceFile.value = TextDocument(
        uriAsString: 'file:///project/lib/spacers.dart',
        version: 1,
      );

      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: controller),
      );
      await tester.pump();
      expect(find.text('Tail Offscreen Target'), findsNothing);

      final CapturePreviewResponse filteredCapture = await controller
          .capturePreview(
            const PreviewCaptureRequest(
              previewId: 'package:my_app/offscreen.dart::tailOffscreenPreview',
            ),
          );
      expect(filteredCapture.hasErrors, isFalse);
      expect(filteredCapture.diagnostics, isEmpty);
      expect(
        filteredCapture.previewId,
        'package:my_app/offscreen.dart::tailOffscreenPreview',
      );
      expect(filteredCapture.name, 'Tail Card');
      expect(filteredCapture.renderedWidth, 180.0);
      expect(filteredCapture.renderedHeight, 90.0);
      expect(filteredCapture.pixelRatio, 1.0);
      expect(filteredCapture.imageBase64, isNotNull);

      final decodedFiltered = await _decodePngRgba(
        filteredCapture.imageBase64!,
      );
      expect(decodedFiltered.width, 180);
      expect(decodedFiltered.height, 90);
      // Top-left pixel is opaque #22AA44.
      expect(
        decodedFiltered.rgba.sublist(0, 4),
        equals(<int>[0x22, 0xAA, 0x44, 0xFF]),
      );
      // Stage unmounted after capture.
      expect(find.text('Tail Offscreen Target'), findsNothing);

      // Now disable _filterBySelectedFile so all 25 groups are in ListView.builder's
      // SliverList, while Group 24 (~7200px down) remains unbuilt off-screen.
      await controller.toggleFilterBySelectedFile();
      await tester.pump();
      expect(controller.filteredPreviewSetListenable.value, hasLength(25));
      expect(find.text('Spacer Group 0'), findsOneWidget);
      expect(find.text('Tail Offscreen Target'), findsNothing);

      final CapturePreviewResponse sliverCapture = await controller
          .capturePreview(const PreviewCaptureRequest(previewId: 'Tail Card'));
      expect(sliverCapture.hasErrors, isFalse);
      expect(
        sliverCapture.previewId,
        'package:my_app/offscreen.dart::tailOffscreenPreview',
      );
      expect(sliverCapture.renderedWidth, 180.0);
      expect(sliverCapture.renderedHeight, 90.0);
      expect(sliverCapture.imageBase64, isNotNull);
      expect(find.text('Tail Offscreen Target'), findsNothing);
    },
  );

  testWidgets(
    'applies width, height, brightness (light vs dark pixel diff), pixelRatio, '
    'textScaleFactor, includeImage, and isolates ScrollNotificationObserver and ScaffoldMessenger',
    (tester) async {
      Size? observedMediaQuerySize;
      double? observedPixelRatio;
      Brightness? observedPlatformBrightness;
      Color? observedCupertinoPrimary;
      ScrollNotificationObserverState? stagedScrollObserver;
      ScaffoldMessengerState? stagedMessenger;

      TextScaler? observedTextScaler;

      final dtdServices = FakeWidgetPreviewScaffoldDtdServices();
      final controller = WidgetPreviewScaffoldController(
        dtdServicesOverride: dtdServices,
        previews: () => <WidgetPreview>[
          buildWidgetPreview(
            column: 1,
            functionName: 'themedCard',
            libraryUri: 'package:my_app/themed.dart',
            line: 10,
            packageName: 'my_app',
            previewFunction: () => Builder(
              builder: (context) {
                observedMediaQuerySize = MediaQuery.sizeOf(context);
                observedPixelRatio = MediaQuery.devicePixelRatioOf(context);
                observedPlatformBrightness = MediaQuery.platformBrightnessOf(
                  context,
                );
                observedCupertinoPrimary = CupertinoTheme.of(
                  context,
                ).primaryColor;
                stagedScrollObserver = ScrollNotificationObserver.maybeOf(
                  context,
                );
                stagedMessenger = ScaffoldMessenger.maybeOf(context);
                return ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: const SizedBox.expand(),
                );
              },
            ),
            scriptUri: 'file:///project/lib/themed.dart',
            transformedPreview: const Preview(
              brightness: Brightness.light,
              name: 'Themed Card',
              size: Size(240, 120),
              theme: _buildTestTheme,
            ).transform(),
          ),
          buildWidgetPreview(
            column: 1,
            functionName: 'bareThemeCard',
            libraryUri: 'package:my_app/themed.dart',
            line: 30,
            packageName: 'my_app',
            previewFunction: () => Builder(
              builder: (context) => ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: const SizedBox(width: 100, height: 60),
              ),
            ),
            scriptUri: 'file:///project/lib/themed.dart',
            transformedPreview: const Preview(
              name: 'Bare Theme Card',
            ).transform(),
          ),
          buildWidgetPreview(
            column: 1,
            functionName: 'scalableText',
            libraryUri: 'package:my_app/themed.dart',
            line: 45,
            packageName: 'my_app',
            previewFunction: () => Builder(
              builder: (context) {
                observedTextScaler = MediaQuery.textScalerOf(context);
                return const Text('Scale Target');
              },
            ),
            scriptUri: 'file:///project/lib/themed.dart',
            transformedPreview: const Preview(
              name: 'Scalable Text',
            ).transform(),
          ),
          buildWidgetPreview(
            column: 1,
            functionName: 'isolatedAppBar',
            libraryUri: 'package:my_app/themed.dart',
            line: 60,
            packageName: 'my_app',
            previewFunction: () => SizedBox(
              width: 300,
              height: 56,
              child: AppBar(title: const Text('Header')),
            ),
            scriptUri: 'file:///project/lib/themed.dart',
            transformedPreview: const Preview(
              name: 'Isolated AppBar',
            ).transform(),
          ),
        ],
      );
      if (controller.filterBySelectedFileListenable.value) {
        await controller.toggleFilterBySelectedFile();
      }
      await controller.initialize();

      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: controller),
      );
      await tester.pump();

      // 1. Light vs dark capture with custom PreviewThemeData + width/height override.
      final CapturePreviewResponse lightCapture = await controller
          .capturePreview(
            const PreviewCaptureRequest(
              brightness: Brightness.light,
              height: 140,
              previewId: 'Themed Card',
              width: 320,
            ),
          );
      expect(lightCapture.hasErrors, isFalse);
      expect(lightCapture.renderedWidth, 320.0);
      expect(lightCapture.renderedHeight, 140.0);
      expect(observedMediaQuerySize, const Size(320, 140));
      expect(observedPlatformBrightness, Brightness.light);
      expect(observedCupertinoPrimary, _kLightCupertinoColor);
      expect(stagedScrollObserver, isNotNull);
      expect(stagedMessenger, isNotNull);

      final CapturePreviewResponse darkCapture = await controller
          .capturePreview(
            const PreviewCaptureRequest(
              brightness: Brightness.dark,
              height: 140,
              previewId: 'Themed Card',
              width: 320,
            ),
          );
      expect(darkCapture.hasErrors, isFalse);
      expect(observedPlatformBrightness, Brightness.dark);
      expect(observedCupertinoPrimary, _kDarkCupertinoColor);

      final lightPng = await _decodePngRgba(lightCapture.imageBase64!);
      final darkPng = await _decodePngRgba(darkCapture.imageBase64!);
      expect(lightPng.width, 320);
      expect(lightPng.height, 140);
      expect(darkPng.width, 320);
      expect(darkPng.height, 140);
      expect(_countDifferingBytes(lightPng.rgba, darkPng.rgba), greaterThan(0));
      expect(
        lightPng.rgba.sublist(0, 4),
        equals(<int>[0xF5, 0xF5, 0xFF, 0xFF]),
      );
      expect(darkPng.rgba.sublist(0, 4), equals(<int>[0x10, 0x18, 0x28, 0xFF]));

      // 2. Bare Material preview (without PreviewThemeData) also produces a real
      // light vs dark pixel diff rather than inheriting the scaffold's dark chrome.
      final CapturePreviewResponse bareLight = await controller.capturePreview(
        const PreviewCaptureRequest(
          brightness: Brightness.light,
          previewId: 'Bare Theme Card',
        ),
      );
      final CapturePreviewResponse bareDark = await controller.capturePreview(
        const PreviewCaptureRequest(
          brightness: Brightness.dark,
          previewId: 'Bare Theme Card',
        ),
      );
      final bareLightPng = await _decodePngRgba(bareLight.imageBase64!);
      final bareDarkPng = await _decodePngRgba(bareDark.imageBase64!);
      expect(
        _countDifferingBytes(bareLightPng.rgba, bareDarkPng.rgba),
        greaterThan(0),
      );
      // Light surface R channel is much brighter than dark surface R channel.
      expect(bareLightPng.rgba[0], greaterThan(200));
      expect(bareDarkPng.rgba[0], lessThan(60));

      // 3. pixelRatio override scales rasterized PNG dimensions while keeping
      // renderedWidth and renderedHeight in logical pixels.
      final CapturePreviewResponse hiDpiCapture = await controller
          .capturePreview(
            const PreviewCaptureRequest(
              height: 60,
              pixelRatio: 2.0,
              previewId: 'Themed Card',
              width: 120,
            ),
          );
      expect(hiDpiCapture.renderedWidth, 120.0);
      expect(hiDpiCapture.renderedHeight, 60.0);
      expect(hiDpiCapture.pixelRatio, 2.0);
      expect(observedPixelRatio, 2.0);
      final hiDpiPng = await _decodePngRgba(hiDpiCapture.imageBase64!);
      expect(hiDpiPng.width, 240);
      expect(hiDpiPng.height, 120);

      // Clamps raster pixelRatio when rendered dimension * pixelRatio exceeds 4096
      // and reports the clamped raster ratio in CapturePreviewResponse.pixelRatio.
      final CapturePreviewResponse clampedCapture = await controller
          .capturePreview(
            const PreviewCaptureRequest(
              height: 1440,
              pixelRatio: 2.0,
              previewId: 'Themed Card',
              width: 2560,
            ),
          );
      expect(clampedCapture.hasErrors, isFalse);
      expect(clampedCapture.renderedWidth, 2560.0);
      expect(clampedCapture.renderedHeight, 1440.0);
      expect(clampedCapture.pixelRatio, closeTo(4096.0 / 2560.0, 1e-6));
      final clampedPng = await _decodePngRgba(clampedCapture.imageBase64!);
      expect(clampedPng.width, 4096);
      expect(clampedPng.height, 2304);

      // 4. textScaleFactor override scales self-sizing Text layout and PNG dimensions.
      final CapturePreviewResponse scale1x = await controller.capturePreview(
        const PreviewCaptureRequest(
          previewId: 'Scalable Text',
          textScaleFactor: 1.0,
        ),
      );
      expect(observedTextScaler, const TextScaler.linear(1.0));
      final CapturePreviewResponse scale25x = await controller.capturePreview(
        const PreviewCaptureRequest(
          previewId: 'Scalable Text',
          textScaleFactor: 2.5,
        ),
      );
      expect(observedTextScaler, const TextScaler.linear(2.5));
      expect(scale25x.renderedWidth, closeTo(scale1x.renderedWidth * 2.5, 8.0));
      expect(
        scale25x.renderedHeight,
        closeTo(scale1x.renderedHeight * 2.5, 8.0),
      );
      final scale25Png = await _decodePngRgba(scale25x.imageBase64!);
      expect(scale25Png.width, scale25x.renderedWidth.ceil());
      expect(scale25Png.height, scale25x.renderedHeight.ceil());

      // 5. includeImage: false omits PNG encoding while preserving rendered dimensions.
      final CapturePreviewResponse metadataOnly = await controller
          .capturePreview(
            const PreviewCaptureRequest(
              height: 85,
              includeImage: false,
              previewId: 'Themed Card',
              width: 175,
            ),
          );
      expect(metadataOnly.imageBase64, isNull);
      expect(metadataOnly.renderedWidth, 175.0);
      expect(metadataOnly.renderedHeight, 85.0);
      expect(metadataOnly.hasErrors, isFalse);

      // 6. ScrollNotificationObserver isolation: scrolling the scaffold's outer
      // ListView does not tint a staged Scaffold-less AppBar.
      final CapturePreviewResponse appBarBeforeScroll = await controller
          .capturePreview(
            const PreviewCaptureRequest(
              brightness: Brightness.light,
              previewId: 'Isolated AppBar',
            ),
          );
      await tester.drag(find.byType(ListView).first, const Offset(0, -80));
      await tester.pump();
      final CapturePreviewResponse appBarAfterScroll = await controller
          .capturePreview(
            const PreviewCaptureRequest(
              brightness: Brightness.light,
              previewId: 'Isolated AppBar',
            ),
          );
      final beforeScrollPng = await _decodePngRgba(
        appBarBeforeScroll.imageBase64!,
      );
      final afterScrollPng = await _decodePngRgba(
        appBarAfterScroll.imageBase64!,
      );
      expect(
        _countDifferingBytes(beforeScrollPng.rgba, afterScrollPng.rgba),
        0,
      );
    },
  );

  testWidgets(
    'captures RenderFlex overflow with valid PNG snapshot and structured overflow diagnostic',
    (tester) async {
      final dtdServices = FakeWidgetPreviewScaffoldDtdServices();
      final controller = WidgetPreviewScaffoldController(
        dtdServicesOverride: dtdServices,
        previews: () => <WidgetPreview>[
          buildWidgetPreview(
            column: 1,
            functionName: 'overflowRow',
            libraryUri: 'package:my_app/overflow.dart',
            line: 12,
            packageName: 'my_app',
            previewFunction: () => const Row(
              children: <Widget>[
                SizedBox(
                  width: 148,
                  height: 40,
                  child: ColoredBox(color: Color(0xFF3366CC)),
                ),
              ],
            ),
            scriptUri: 'file:///project/lib/overflow.dart',
            transformedPreview: const Preview(
              name: 'Overflow Row',
              size: Size(100, 40),
            ).transform(),
          ),
        ],
      );
      // Keep filtered out of the interactive list so only the off-screen stage builds it.
      await controller.initialize();
      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: controller),
      );
      await tester.pump();

      final CapturePreviewResponse firstOverflow = await controller
          .capturePreview(
            const PreviewCaptureRequest(previewId: 'Overflow Row'),
          );
      expect(firstOverflow.hasErrors, isTrue);
      expect(firstOverflow.renderedWidth, 100.0);
      expect(firstOverflow.renderedHeight, 40.0);
      expect(firstOverflow.imageBase64, isNotNull);
      expect(
        firstOverflow.diagnostics,
        equals(<PreviewDiagnostic>[
          const PreviewDiagnostic(
            kind: .overflow,
            overflowAxis: 'horizontal',
            overflowPixels: 48.0,
            overflowSide: 'right',
            phase: .paint,
            summary: 'A RenderFlex overflowed by 48 pixels on the right.',
            targetType: 'RenderFlex',
          ),
        ]),
      );
      final overflowPng = await _decodePngRgba(firstOverflow.imageBase64!);
      expect(overflowPng.width, 100);
      expect(overflowPng.height, 40);

      // A second capture mounts a fresh stage subtree and reports the overflow again.
      final CapturePreviewResponse secondOverflow = await controller
          .capturePreview(
            const PreviewCaptureRequest(previewId: 'Overflow Row'),
          );
      expect(secondOverflow.hasErrors, isTrue);
      expect(secondOverflow.diagnostics, equals(firstOverflow.diagnostics));
      expect(secondOverflow.imageBase64, isNotNull);

      // Overriding width to 200 eliminates the overflow and returns hasErrors: false.
      final CapturePreviewResponse wideEnough = await controller.capturePreview(
        const PreviewCaptureRequest(previewId: 'Overflow Row', width: 200),
      );
      expect(wideEnough.hasErrors, isFalse);
      expect(wideEnough.diagnostics, isEmpty);
      expect(wideEnough.renderedWidth, 200.0);
      expect(wideEnough.renderedHeight, 40.0);
      expect(wideEnough.imageBase64, isNotNull);
    },
  );

  testWidgets(
    'captures unconstrained SizedBox.expand(), compile errors, and build exceptions cleanly without crashing',
    (tester) async {
      final dtdServices = FakeWidgetPreviewScaffoldDtdServices();
      final controller = WidgetPreviewScaffoldController(
        dtdServicesOverride: dtdServices,
        previews: () => <WidgetPreview>[
          buildWidgetPreview(
            column: 1,
            functionName: 'bareExpand',
            libraryUri: 'package:my_app/errors.dart',
            line: 5,
            packageName: 'my_app',
            previewFunction: () => const SizedBox.expand(),
            scriptUri: 'file:///project/lib/errors.dart',
            transformedPreview: const Preview(
              name: 'Bare SizedBox Expand',
            ).transform(),
          ),
          buildWidgetPreview(
            column: 1,
            functionName: 'unconstrainedBox',
            libraryUri: 'package:my_app/errors.dart',
            line: 10,
            packageName: 'my_app',
            previewFunction: () => const SizedBox.expand(
              child: ColoredBox(color: Color(0xFFCC3344)),
            ),
            scriptUri: 'file:///project/lib/errors.dart',
            transformedPreview: const Preview(
              name: 'Unconstrained Box',
            ).transform(),
          ),
          buildWidgetPreviewError(
            column: 1,
            dependencyHasErrors: false,
            functionName: 'compileBroken',
            libraryUri: 'package:my_app/broken.dart',
            line: 20,
            packageName: 'my_app',
            scriptUri: 'file:///project/lib/broken.dart',
          ),
          buildWidgetPreview(
            column: 1,
            functionName: 'syncThrowing',
            libraryUri: 'package:my_app/errors.dart',
            line: 30,
            packageName: 'my_app',
            previewFunction: () => throw ArgumentError('staged sync throw'),
            scriptUri: 'file:///project/lib/errors.dart',
            transformedPreview: const Preview(name: 'Sync Throw').transform(),
          ),
          buildWidgetPreview(
            column: 1,
            functionName: 'descendantThrowing',
            libraryUri: 'package:my_app/errors.dart',
            line: 40,
            packageName: 'my_app',
            previewFunction: () => const _ThrowingDescendantBuildWidget(),
            scriptUri: 'file:///project/lib/errors.dart',
            transformedPreview: const Preview(
              name: 'Descendant Throw',
            ).transform(),
          ),
          buildWidgetPreview(
            column: 1,
            functionName: 'themeCallbackThrowing',
            libraryUri: 'package:my_app/errors.dart',
            line: 50,
            packageName: 'my_app',
            previewFunction: () => const SizedBox(width: 80, height: 40),
            scriptUri: 'file:///project/lib/errors.dart',
            transformedPreview: const Preview(
              name: 'Theme Callback Throw',
              theme: _throwingThemeCallback,
            ).transform(),
          ),
          buildWidgetPreview(
            column: 1,
            functionName: 'themeApplyThrowing',
            libraryUri: 'package:my_app/errors.dart',
            line: 60,
            packageName: 'my_app',
            previewFunction: () => const SizedBox(width: 80, height: 40),
            scriptUri: 'file:///project/lib/errors.dart',
            transformedPreview: const Preview(
              name: 'Theme Apply Throw',
              theme: _throwingApplyThemeCallback,
            ).transform(),
          ),
          buildWidgetPreview(
            column: 1,
            functionName: 'localizationsCallbackThrowing',
            libraryUri: 'package:my_app/errors.dart',
            line: 70,
            packageName: 'my_app',
            previewFunction: () => const SizedBox(width: 80, height: 40),
            scriptUri: 'file:///project/lib/errors.dart',
            transformedPreview: const Preview(
              localizations: _throwingLocalizationsCallback,
              name: 'Localizations Callback Throw',
            ).transform(),
          ),
        ],
      );
      await controller.initialize();
      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: controller),
      );
      await tester.pump();

      // 1. Bare SizedBox.expand() and SizedBox.expand(child: ...) without width/height override.
      final CapturePreviewResponse bareExpand = await controller.capturePreview(
        const PreviewCaptureRequest(previewId: 'Bare SizedBox Expand'),
      );
      expect(bareExpand.hasErrors, isTrue);
      expect(bareExpand.imageBase64, isNull);
      expect(bareExpand.renderedWidth, 0.0);
      expect(bareExpand.renderedHeight, 0.0);
      expect(
        bareExpand.diagnostics.single.kind,
        PreviewDiagnosticKind.unconstrained,
      );

      final CapturePreviewResponse unconstrained = await controller
          .capturePreview(
            const PreviewCaptureRequest(previewId: 'Unconstrained Box'),
          );
      expect(unconstrained.hasErrors, isTrue);
      expect(unconstrained.imageBase64, isNull);
      expect(unconstrained.renderedWidth, 0.0);
      expect(unconstrained.renderedHeight, 0.0);
      expect(unconstrained.diagnostics, hasLength(1));
      expect(
        unconstrained.diagnostics.single.phase,
        PreviewDiagnosticPhase.layout,
      );
      expect(
        unconstrained.diagnostics.single.kind,
        PreviewDiagnosticKind.unconstrained,
      );

      // Supplying explicit width & height overrides allows SizedBox.expand() to render cleanly.
      final CapturePreviewResponse bounded = await controller.capturePreview(
        const PreviewCaptureRequest(
          height: 70,
          previewId: 'Unconstrained Box',
          width: 130,
        ),
      );
      expect(bounded.hasErrors, isFalse);
      expect(bounded.diagnostics, isEmpty);
      expect(bounded.renderedWidth, 130.0);
      expect(bounded.renderedHeight, 70.0);
      expect(bounded.imageBase64, isNotNull);

      // 2. Compile error short-circuits without mounting.
      final CapturePreviewResponse compileError = await controller
          .capturePreview(
            const PreviewCaptureRequest(
              previewId: 'package:my_app/broken.dart::compileBroken',
            ),
          );
      expect(compileError.hasErrors, isTrue);
      expect(compileError.imageBase64, isNull);
      expect(
        compileError.diagnostics,
        equals(<PreviewDiagnostic>[
          const PreviewDiagnostic(
            kind: .compileError,
            phase: .compile,
            summary: 'package:my_app/broken.dart has errors!',
          ),
        ]),
      );

      // 3. Synchronous previewBuilder throw & descendant StatelessWidget.build throw.
      final CapturePreviewResponse syncThrow = await controller.capturePreview(
        const PreviewCaptureRequest(previewId: 'Sync Throw'),
      );
      expect(syncThrow.hasErrors, isTrue);
      expect(syncThrow.imageBase64, isNull);
      expect(syncThrow.diagnostics, hasLength(1));
      expect(syncThrow.diagnostics.single.phase, PreviewDiagnosticPhase.build);
      expect(
        syncThrow.diagnostics.single.kind,
        PreviewDiagnosticKind.exception,
      );
      expect(
        syncThrow.diagnostics.single.summary,
        contains('staged sync throw'),
      );

      final CapturePreviewResponse descendantThrow = await controller
          .capturePreview(
            const PreviewCaptureRequest(previewId: 'Descendant Throw'),
          );
      expect(descendantThrow.hasErrors, isTrue);
      expect(descendantThrow.imageBase64, isNull);
      expect(descendantThrow.diagnostics, hasLength(1));
      expect(
        descendantThrow.diagnostics.single.phase,
        PreviewDiagnosticPhase.build,
      );
      expect(
        descendantThrow.diagnostics.single.kind,
        PreviewDiagnosticKind.exception,
      );
      expect(
        descendantThrow.diagnostics.single.summary,
        contains('staged descendant build failure'),
      );

      // 4. Throwing theme: callback, PreviewThemeData.apply, and localizations: callback.
      final CapturePreviewResponse themeCallbackThrow = await controller
          .capturePreview(
            const PreviewCaptureRequest(previewId: 'Theme Callback Throw'),
          );
      expect(themeCallbackThrow.hasErrors, isTrue);
      expect(themeCallbackThrow.imageBase64, isNull);
      expect(themeCallbackThrow.renderedWidth, 0.0);
      expect(themeCallbackThrow.renderedHeight, 0.0);
      expect(themeCallbackThrow.diagnostics, hasLength(1));
      expect(
        themeCallbackThrow.diagnostics.single.phase,
        PreviewDiagnosticPhase.build,
      );
      expect(
        themeCallbackThrow.diagnostics.single.kind,
        PreviewDiagnosticKind.exception,
      );
      expect(
        themeCallbackThrow.diagnostics.single.summary,
        contains('staged theme callback failure'),
      );

      final CapturePreviewResponse themeApplyThrow = await controller
          .capturePreview(
            const PreviewCaptureRequest(previewId: 'Theme Apply Throw'),
          );
      expect(themeApplyThrow.hasErrors, isTrue);
      expect(themeApplyThrow.imageBase64, isNull);
      expect(themeApplyThrow.renderedWidth, 0.0);
      expect(themeApplyThrow.renderedHeight, 0.0);
      expect(themeApplyThrow.diagnostics, hasLength(1));
      expect(
        themeApplyThrow.diagnostics.single.phase,
        PreviewDiagnosticPhase.build,
      );
      expect(
        themeApplyThrow.diagnostics.single.kind,
        PreviewDiagnosticKind.exception,
      );
      expect(
        themeApplyThrow.diagnostics.single.summary,
        contains('staged theme apply failure'),
      );

      final CapturePreviewResponse localizationsThrow = await controller
          .capturePreview(
            const PreviewCaptureRequest(
              previewId: 'Localizations Callback Throw',
            ),
          );
      expect(localizationsThrow.hasErrors, isTrue);
      expect(localizationsThrow.imageBase64, isNull);
      expect(localizationsThrow.renderedWidth, 0.0);
      expect(localizationsThrow.renderedHeight, 0.0);
      expect(localizationsThrow.diagnostics, hasLength(1));
      expect(
        localizationsThrow.diagnostics.single.phase,
        PreviewDiagnosticPhase.build,
      );
      expect(
        localizationsThrow.diagnostics.single.kind,
        PreviewDiagnosticKind.exception,
      );
      expect(
        localizationsThrow.diagnostics.single.summary,
        contains('staged localizations callback failure'),
      );
    },
  );

  testWidgets(
    'resolves unique name shorthand, rejects ambiguous or missing IDs, and serializes concurrent captures',
    (tester) async {
      final dtdServices = FakeWidgetPreviewScaffoldDtdServices();
      final controller = WidgetPreviewScaffoldController(
        dtdServicesOverride: dtdServices,
        previews: () => <WidgetPreview>[
          buildWidgetPreview(
            column: 1,
            functionName: 'alphaPreview',
            libraryUri: 'package:my_app/a.dart',
            line: 10,
            packageName: 'my_app',
            previewFunction: () => const ColoredBox(
              color: Color(0xFFFF0000),
              child: SizedBox(width: 110, height: 55),
            ),
            scriptUri: 'file:///project/lib/a.dart',
            transformedPreview: const Preview(name: 'Unique Alpha').transform(),
          ),
          buildWidgetPreview(
            column: 1,
            functionName: 'dupOne',
            libraryUri: 'package:my_app/a.dart',
            line: 20,
            packageName: 'my_app',
            previewFunction: () => const ColoredBox(
              color: Color(0xFF00FF00),
              child: SizedBox(width: 220, height: 75),
            ),
            scriptUri: 'file:///project/lib/a.dart',
            transformedPreview: const Preview(name: 'Shared Name').transform(),
          ),
          buildWidgetPreview(
            column: 1,
            functionName: 'dupTwo',
            libraryUri: 'package:my_app/b.dart',
            line: 30,
            packageName: 'my_app',
            previewFunction: () => const ColoredBox(
              color: Color(0xFF0000FF),
              child: SizedBox(width: 165, height: 95),
            ),
            scriptUri: 'file:///project/lib/b.dart',
            transformedPreview: const Preview(name: 'Shared Name').transform(),
          ),
        ],
      );
      await controller.initialize();
      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: controller),
      );
      await tester.pump();

      // Unique shorthand resolves and returns canonical ID.
      final CapturePreviewResponse alpha = await controller.capturePreview(
        const PreviewCaptureRequest(previewId: 'Unique Alpha'),
      );
      expect(alpha.previewId, 'package:my_app/a.dart::alphaPreview');
      expect(alpha.name, 'Unique Alpha');
      expect(alpha.renderedWidth, 110.0);
      expect(alpha.renderedHeight, 55.0);

      // Ambiguous shorthand throws RpcException 102 listing canonical candidate IDs.
      await expectLater(
        controller.capturePreview(
          const PreviewCaptureRequest(previewId: 'Shared Name'),
        ),
        throwsA(
          isA<RpcException>()
              .having(
                (RpcException e) => e.code,
                'code',
                WidgetPreviewScaffoldDtdServices.kAmbiguousPreviewNameErrorCode,
              )
              .having(
                (RpcException e) => e.message,
                'message',
                allOf(
                  contains('package:my_app/a.dart::dupOne'),
                  contains('package:my_app/b.dart::dupTwo'),
                ),
              ),
        ),
      );

      // Missing canonical ID and missing shorthand name both throw RpcException 101.
      await expectLater(
        controller.capturePreview(
          const PreviewCaptureRequest(
            previewId: 'package:my_app/missing.dart::missingFn',
          ),
        ),
        throwsA(
          isA<RpcException>()
              .having(
                (RpcException e) => e.code,
                'code',
                WidgetPreviewScaffoldDtdServices.kPreviewNotFoundErrorCode,
              )
              .having(
                (RpcException e) => e.message,
                'message',
                contains('package:my_app/a.dart::alphaPreview'),
              ),
        ),
      );
      await expectLater(
        controller.capturePreview(
          const PreviewCaptureRequest(previewId: 'Nonexistent Card'),
        ),
        throwsA(
          isA<RpcException>().having(
            (RpcException e) => e.code,
            'code',
            WidgetPreviewScaffoldDtdServices.kPreviewNotFoundErrorCode,
          ),
        ),
      );

      // Concurrent captures serialize cleanly through the async lock without clobbering.
      final List<CapturePreviewResponse> concurrent =
          await Future.wait(<Future<CapturePreviewResponse>>[
            controller.capturePreview(
              const PreviewCaptureRequest(
                previewId: 'package:my_app/a.dart::alphaPreview',
              ),
            ),
            controller.capturePreview(
              const PreviewCaptureRequest(
                previewId: 'package:my_app/a.dart::dupOne',
              ),
            ),
            controller.capturePreview(
              const PreviewCaptureRequest(
                previewId: 'package:my_app/b.dart::dupTwo',
              ),
            ),
          ]);
      expect(concurrent[0].renderedWidth, 110.0);
      expect(concurrent[0].renderedHeight, 55.0);
      expect(concurrent[1].renderedWidth, 220.0);
      expect(concurrent[1].renderedHeight, 75.0);
      expect(concurrent[2].renderedWidth, 165.0);
      expect(concurrent[2].renderedHeight, 95.0);

      final png0 = await _decodePngRgba(concurrent[0].imageBase64!);
      final png1 = await _decodePngRgba(concurrent[1].imageBase64!);
      final png2 = await _decodePngRgba(concurrent[2].imageBase64!);
      expect(png0.rgba.sublist(0, 4), equals(<int>[0xFF, 0x00, 0x00, 0xFF]));
      expect(png1.rgba.sublist(0, 4), equals(<int>[0x00, 0xFF, 0x00, 0xFF]));
      expect(png2.rgba.sublist(0, 4), equals(<int>[0x00, 0x00, 0xFF, 0xFF]));
    },
  );

  testWidgets(
    'waits for WidgetPreviewScaffold to mount when capturePreview is issued before mount and times out if never mounted',
    (tester) async {
      final dtdServices = FakeWidgetPreviewScaffoldDtdServices();
      final controller = WidgetPreviewScaffoldController(
        dtdServicesOverride: dtdServices,
        previews: () => <WidgetPreview>[
          buildWidgetPreview(
            column: 1,
            functionName: 'delayedMountPreview',
            libraryUri: 'package:my_app/startup.dart',
            line: 10,
            packageName: 'my_app',
            previewFunction: () => const ColoredBox(
              color: Color(0xFF4488CC),
              child: SizedBox(width: 160, height: 80),
            ),
            scriptUri: 'file:///project/lib/startup.dart',
            transformedPreview: const Preview(
              name: 'Delayed Mount Card',
            ).transform(),
          ),
        ],
      );
      await controller.initialize();

      // Issue capturePreview after controller.initialize() (when Connected has
      // been posted) but before WidgetPreviewScaffold mounts and attaches its
      // stage capture host.
      var completed = false;
      final Future<CapturePreviewResponse> pendingCapture = controller
          .capturePreview(
            const PreviewCaptureRequest(previewId: 'Delayed Mount Card'),
          )
          .whenComplete(() {
            completed = true;
          });
      await pumpEventQueue();
      expect(completed, isFalse);

      // Mounting the scaffold attaches the stage host and resolves the pending capture.
      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: controller),
      );
      final CapturePreviewResponse response = await pendingCapture;
      expect(completed, isTrue);
      expect(response.hasErrors, isFalse);
      expect(
        response.previewId,
        'package:my_app/startup.dart::delayedMountPreview',
      );
      expect(response.renderedWidth, 160.0);
      expect(response.renderedHeight, 80.0);
      expect(response.imageBase64, isNotNull);
      final decoded = await _decodePngRgba(response.imageBase64!);
      expect(decoded.width, 160);
      expect(decoded.height, 80);
      expect(decoded.rgba.sublist(0, 4), equals(<int>[0x44, 0x88, 0xCC, 0xFF]));

      // If a controller never mounts a WidgetPreviewScaffold within stageHostTimeout,
      // capturePreview fails with RpcException(200) and releases the capture lock.
      final unmountedController = WidgetPreviewScaffoldController(
        dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
        previews: () => <WidgetPreview>[
          buildWidgetPreview(
            column: 1,
            functionName: 'unmountedPreview',
            libraryUri: 'package:my_app/startup.dart',
            line: 25,
            packageName: 'my_app',
            previewFunction: () => const SizedBox(width: 50, height: 50),
            scriptUri: 'file:///project/lib/startup.dart',
            transformedPreview: const Preview(
              name: 'Unmounted Card',
            ).transform(),
          ),
        ],
        stageHostTimeout: const Duration(milliseconds: 40),
      );
      await unmountedController.initialize();
      await expectLater(
        unmountedController.capturePreview(
          const PreviewCaptureRequest(previewId: 'Unmounted Card'),
        ),
        throwsA(
          isA<RpcException>()
              .having(
                (RpcException e) => e.code,
                'code',
                WidgetPreviewScaffoldDtdServices.kNoValueForKey,
              )
              .having(
                (RpcException e) => e.message,
                'message',
                contains('WidgetPreviewScaffold is not currently mounted'),
              ),
        ),
      );
    },
  );

  testWidgets(
    'captures when AppLifecycleState is hidden (framesEnabled is false) and releases lock on frame timeout',
    (tester) async {
      addTearDown(() {
        binding.framePolicy =
            LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
        binding.resetInternalState();
      });

      WidgetPreview buildHiddenCard() => buildWidgetPreview(
        column: 1,
        functionName: 'hiddenTabPreview',
        libraryUri: 'package:my_app/hidden.dart',
        line: 10,
        packageName: 'my_app',
        previewFunction: () => const ColoredBox(
          color: Color(0xFFAA3377),
          child: SizedBox(
            width: 140,
            height: 70,
            child: Center(child: Text('Hidden Tab Target')),
          ),
        ),
        scriptUri: 'file:///project/lib/hidden.dart',
        transformedPreview: const Preview(name: 'Hidden Tab Card').transform(),
      );

      final dtdServices = FakeWidgetPreviewScaffoldDtdServices();
      final controller = WidgetPreviewScaffoldController(
        dtdServicesOverride: dtdServices,
        previews: () => <WidgetPreview>[buildHiddenCard()],
      );
      await controller.initialize();
      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: controller),
      );
      await tester.pump();

      // Simulate a minimized/hidden browser tab or hidden IDE webview:
      // AppLifecycleState.hidden sets SchedulerBinding.framesEnabled = false,
      // and benchmark framePolicy disables scheduleFrame() and scheduleForcedFrame()
      // engine vsyncs so only scheduleWarmUpFrame() can drive frames.
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmark;
      expect(SchedulerBinding.instance.framesEnabled, isFalse);

      final CapturePreviewResponse hiddenResponse = await controller
          .capturePreview(
            const PreviewCaptureRequest(previewId: 'Hidden Tab Card'),
          );
      expect(hiddenResponse.hasErrors, isFalse);
      expect(hiddenResponse.renderedWidth, 140.0);
      expect(hiddenResponse.renderedHeight, 70.0);
      expect(hiddenResponse.imageBase64, isNotNull);
      final hiddenPng = await _decodePngRgba(hiddenResponse.imageBase64!);
      expect(hiddenPng.width, 140);
      expect(hiddenPng.height, 70);
      expect(
        hiddenPng.rgba.sublist(0, 4),
        equals(<int>[0xAA, 0x33, 0x77, 0xFF]),
      );
      expect(find.text('Hidden Tab Target'), findsNothing);

      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(SchedulerBinding.instance.framesEnabled, isTrue);

      // Use a dedicated short-timeout controller for the expected frame-timeout
      // assertion so the success paths above never race a short timeout.
      final timeoutController = WidgetPreviewScaffoldController(
        dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
        previews: () => <WidgetPreview>[
          buildHiddenCard(),
          buildWidgetPreviewError(
            column: 1,
            dependencyHasErrors: false,
            functionName: 'compileBrokenAfterTimeout',
            libraryUri: 'package:my_app/hidden.dart',
            line: 25,
            packageName: 'my_app',
            scriptUri: 'file:///project/lib/hidden.dart',
          ),
        ],
        stageFrameTimeout: const Duration(milliseconds: 50),
      );
      await timeoutController.initialize();
      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: timeoutController),
      );
      await tester.pump();

      // Simulate a wedged frame pipeline where beginFrame/drawFrame are skipped
      // (fadePointers without an active pump or view paint), verifying that
      // _pumpStageFrame times out with RpcException, clears _activeStageSession,
      // and releases _captureLock.
      binding.framePolicy =
          LiveTestWidgetsFlutterBindingFramePolicy.fadePointers;
      await expectLater(
        timeoutController.capturePreview(
          const PreviewCaptureRequest(previewId: 'Hidden Tab Card'),
        ),
        throwsA(
          isA<RpcException>()
              .having(
                (RpcException e) => e.code,
                'code',
                WidgetPreviewScaffoldDtdServices.kNoValueForKey,
              )
              .having(
                (RpcException e) => e.message,
                'message',
                contains('Timed out waiting for widget preview frame'),
              ),
        ),
      );

      // Verify _captureLock on timeoutController was released by capturing the
      // compile-error preview (which acquires _captureLock without frame timing)
      // and verify _activeStageSession was cleared once frames resume.
      final CapturePreviewResponse lockAcquired = await timeoutController
          .capturePreview(
            const PreviewCaptureRequest(
              previewId:
                  'package:my_app/hidden.dart::compileBrokenAfterTimeout',
            ),
          );
      expect(lockAcquired.hasErrors, isTrue);
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      await tester.pump();
      expect(find.text('Hidden Tab Target'), findsNothing);
    },
  );

  testWidgets(
    'detaches stage host on unmount and throws RpcException(200) without disposed ValueNotifier errors when unmounted before or during capture',
    (tester) async {
      WidgetPreview buildUnmountCard() => buildWidgetPreview(
        column: 1,
        functionName: 'unmountPreview',
        libraryUri: 'package:my_app/unmount.dart',
        line: 10,
        packageName: 'my_app',
        previewFunction: () => const ColoredBox(
          color: Color(0xFF339966),
          child: SizedBox(width: 150, height: 75),
        ),
        scriptUri: 'file:///project/lib/unmount.dart',
        transformedPreview: const Preview(name: 'Unmount Card').transform(),
      );

      // 1. Unmount before capture with a short stageHostTimeout: detachStageCaptureHost
      // clears the host so capturing while unmounted throws RpcException(200)
      // rather than invoking the disposed State's ValueNotifier.
      final shortTimeoutController = WidgetPreviewScaffoldController(
        dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
        previews: () => <WidgetPreview>[buildUnmountCard()],
        stageHostTimeout: const Duration(milliseconds: 50),
      );
      await shortTimeoutController.initialize();
      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: shortTimeoutController),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      await expectLater(
        shortTimeoutController.capturePreview(
          const PreviewCaptureRequest(previewId: 'Unmount Card'),
        ),
        throwsA(
          isA<RpcException>()
              .having(
                (RpcException e) => e.code,
                'code',
                WidgetPreviewScaffoldDtdServices.kNoValueForKey,
              )
              .having(
                (RpcException e) => e.message,
                'message',
                contains('WidgetPreviewScaffold is not currently mounted'),
              ),
        ),
      );
      expect(tester.takeException(), isNull);

      // 2. Use default timeouts for all remount and mid-capture unmount paths
      // so success paths never race a short timeout.
      final controller = WidgetPreviewScaffoldController(
        dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
        previews: () => <WidgetPreview>[buildUnmountCard()],
      );
      await controller.initialize();
      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: controller),
      );
      await tester.pump();

      final CapturePreviewResponse initial = await controller.capturePreview(
        const PreviewCaptureRequest(previewId: 'Unmount Card'),
      );
      expect(initial.hasErrors, isFalse);
      expect(initial.renderedWidth, 150.0);
      expect(initial.renderedHeight, 75.0);

      // Unmount and remount while a capture is waiting for the host.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      final Future<CapturePreviewResponse> waitingForRemount = controller
          .capturePreview(
            const PreviewCaptureRequest(previewId: 'Unmount Card'),
          );
      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: controller),
      );
      final CapturePreviewResponse remounted = await waitingForRemount;
      expect(remounted.hasErrors, isFalse);
      expect(remounted.renderedWidth, 150.0);
      expect(remounted.renderedHeight, 75.0);
      expect(remounted.imageBase64, isNotNull);

      // 3. Unmount during an in-flight capture: start capturePreview while
      // mounted, let it enter _captureStagedPreview and set _activeStageSession,
      // then unmount the scaffold mid-frame. It must throw RpcException(200)
      // (not a 0x0 response or disposed ValueNotifier FlutterError) and release
      // _captureLock.
      final Future<void> inFlightExpectation = expectLater(
        controller.capturePreview(
          const PreviewCaptureRequest(previewId: 'Unmount Card'),
        ),
        throwsA(
          isA<RpcException>()
              .having(
                (RpcException e) => e.code,
                'code',
                WidgetPreviewScaffoldDtdServices.kNoValueForKey,
              )
              .having(
                (RpcException e) => e.message,
                'message',
                contains('WidgetPreviewScaffold is not currently mounted'),
              ),
        ),
      );
      await Future<void>.value();
      await tester.pumpWidget(const SizedBox.shrink());
      await inFlightExpectation;
      expect(tester.takeException(), isNull);

      // Remount and confirm _captureLock was released.
      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: controller),
      );
      await tester.pump();
      final CapturePreviewResponse afterMidCaptureUnmount = await controller
          .capturePreview(
            const PreviewCaptureRequest(previewId: 'Unmount Card'),
          );
      expect(afterMidCaptureUnmount.hasErrors, isFalse);
      expect(afterMidCaptureUnmount.renderedWidth, 150.0);
      expect(afterMidCaptureUnmount.renderedHeight, 75.0);
      expect(afterMidCaptureUnmount.imageBase64, isNotNull);
    },
  );

  testWidgets(
    'off-screen capturePreview renders a bare Material TextField when defaultLocalizations is provided',
    (tester) async {
      final WidgetPreview preview = buildWidgetPreview(
        column: 1,
        defaultLocalizations: _defaultCaptureLocalizations,
        functionName: 'bareMaterialTextField',
        libraryUri: 'package:my_app/text_field.dart',
        line: 10,
        packageName: 'my_app',
        previewFunction: () => const Material(
          child: SizedBox(width: 220, height: 80, child: TextField()),
        ),
        scriptUri: 'file:///project/lib/text_field.dart',
        transformedPreview: const Preview(
          name: 'Bare Material TextField',
        ).transform(),
      );
      final controller = WidgetPreviewScaffoldController(
        dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
        previews: () => <WidgetPreview>[preview],
      );
      await controller.initialize();
      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: controller),
      );
      await tester.pump();

      final CapturePreviewResponse response = await controller.capturePreview(
        const PreviewCaptureRequest(previewId: 'Bare Material TextField'),
      );
      expect(response.hasErrors, isFalse);
      expect(response.diagnostics, isEmpty);
      expect(response.imageBase64, isNotNull);

      final Uint8List pngBytes = base64Decode(response.imageBase64!);
      expect(pngBytes, isNotEmpty);

      final decoded = await _decodePngRgba(response.imageBase64!);
      expect(decoded.width, 220);
      expect(decoded.height, 80);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'PreviewAssetBundle aliases AssetManifest.bin and AssetManifest.bin.json',
    (tester) async {
      final rawManifest = <Object?, Object?>{
        'packages/my_app/assets/logo.png': <Map<Object?, Object?>>[
          <Object?, Object?>{'asset': 'packages/my_app/assets/logo.png'},
        ],
        'packages/other_pkg/assets/icon.png': <Map<Object?, Object?>>[
          <Object?, Object?>{'asset': 'packages/other_pkg/assets/icon.png'},
        ],
      };
      final ByteData manifestBin = const StandardMessageCodec().encodeMessage(
        rawManifest,
      )!;
      final ByteData manifestBinJson = ByteData.sublistView(
        Uint8List.fromList(
          utf8.encode(
            jsonEncode(base64Encode(Uint8List.sublistView(manifestBin))),
          ),
        ),
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMessageHandler('flutter/assets', (
        ByteData? message,
      ) async {
        final String key = utf8.decode(Uint8List.sublistView(message!));
        return switch (key) {
          'AssetManifest.bin' => manifestBin,
          'AssetManifest.bin.json' => manifestBinJson,
          _ => null,
        };
      });
      addTearDown(
        () => messenger.setMockMessageHandler('flutter/assets', null),
      );

      final bundle = PreviewAssetBundle(packageName: 'my_app');
      final AssetManifest parsed = await AssetManifest.loadFromAssetBundle(
        bundle,
      );
      expect(parsed.listAssets(), contains('assets/logo.png'));
      expect(parsed.listAssets(), contains('packages/my_app/assets/logo.png'));
      expect(parsed.listAssets(), isNot(contains('assets/icon.png')));

      final ByteData aliasedJsonBytes = await bundle.load(
        'AssetManifest.bin.json',
      );
      final Uint8List encodedStr = base64Decode(
        jsonDecode(utf8.decode(Uint8List.sublistView(aliasedJsonBytes)))
            as String,
      );
      final Object? decodedJsonMap = const StandardMessageCodec().decodeMessage(
        ByteData.sublistView(encodedStr),
      );
      expect(
        (decodedJsonMap! as Map<Object?, Object?>).containsKey(
          'assets/logo.png',
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'WidgetPreviewMediaQueryOverride keeps finite height for Size.fromWidth',
    (WidgetTester tester) async {
      Size? observedSize;
      final preview = WidgetPreview(
        scriptUri: 'file:///app/lib/widgets.dart',
        libraryUri: 'package:app/widgets.dart',
        functionName: 'widthOnly',
        line: 10,
        column: 1,
        builder: () => Builder(
          builder: (BuildContext context) {
            observedSize = MediaQuery.sizeOf(context);
            return const SizedBox(width: 100, height: 50);
          },
        ),
        previewData: const Preview(
          name: 'widthOnly',
          size: Size.fromWidth(300),
        ),
        packageName: 'app',
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: WidgetPreviewMediaQueryOverride(
            preview: preview,
            brightnessListenable: ValueNotifier<Brightness>(Brightness.light),
            child: preview.previewBuilder(),
          ),
        ),
      );

      expect(observedSize?.width, 300.0);
      expect(observedSize?.height, 600.0);
      expect(observedSize?.height.isFinite, isTrue);
    },
  );

  testWidgets('capturePreview emits zeroSize error for 0x0 preview', (
    WidgetTester tester,
  ) async {
    final dtd = FakeWidgetPreviewScaffoldDtdServices();
    final controller = WidgetPreviewScaffoldController(
      dtdServicesOverride: dtd,
      previews: () => <WidgetPreview>[
        buildWidgetPreview(
          column: 1,
          functionName: 'zeroPreview',
          libraryUri: 'package:app/widgets.dart',
          line: 10,
          packageName: 'app',
          previewFunction: () => const SizedBox.shrink(),
          scriptUri: 'file:///app/lib/widgets.dart',
          transformedPreview: const Preview(name: 'zeroPreview').transform(),
        ),
      ],
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await tester.pumpWidget(TestWidgetPreviewScaffold(controller: controller));

    final CapturePreviewResponse response = await dtd.onCapturePreview!(
      const PreviewCaptureRequest(
        previewId: 'package:app/widgets.dart::zeroPreview',
      ),
    );

    expect(response.hasErrors, isTrue);
    expect(
      response.diagnostics.any(
        (PreviewDiagnostic d) => d.kind == .zeroSize && d.severity == .error,
      ),
      isTrue,
    );
  });

  testWidgets(
    'capturePreview emits textTruncated warning without failing hasErrors',
    (WidgetTester tester) async {
      final dtd = FakeWidgetPreviewScaffoldDtdServices();
      final controller = WidgetPreviewScaffoldController(
        dtdServicesOverride: dtd,
        previews: () => <WidgetPreview>[
          buildWidgetPreview(
            column: 1,
            functionName: 'truncatedText',
            libraryUri: 'package:app/widgets.dart',
            line: 10,
            packageName: 'app',
            previewFunction: () => const Directionality(
              textDirection: TextDirection.ltr,
              child: SizedBox(
                width: 60,
                child: Text(
                  'Very long text that definitely overflows this narrow box',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            scriptUri: 'file:///app/lib/widgets.dart',
            transformedPreview: const Preview(
              name: 'truncatedText',
              size: Size(80, 40),
            ).transform(),
          ),
        ],
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: controller),
      );

      final CapturePreviewResponse response = await dtd.onCapturePreview!(
        const PreviewCaptureRequest(
          previewId: 'package:app/widgets.dart::truncatedText',
        ),
      );

      expect(response.hasErrors, isFalse);
      expect(
        response.diagnostics.any(
          (PreviewDiagnostic d) =>
              d.kind == .textTruncated && d.severity == .warning,
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'capturePreview emits smallTapTarget warning on mobile targets only',
    (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final dtd = FakeWidgetPreviewScaffoldDtdServices();
        final controller = WidgetPreviewScaffoldController(
          dtdServicesOverride: dtd,
          previews: () => <WidgetPreview>[
            buildWidgetPreview(
              column: 1,
              functionName: 'smallButton',
              libraryUri: 'package:app/widgets.dart',
              line: 10,
              packageName: 'app',
              previewFunction: () => Center(
                child: Semantics(
                  onTap: () {},
                  child: const SizedBox(width: 24, height: 24),
                ),
              ),
              scriptUri: 'file:///app/lib/widgets.dart',
              transformedPreview: const Preview(
                name: 'smallButton',
                size: Size(120, 80),
              ).transform(),
            ),
          ],
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        await tester.pumpWidget(
          TestWidgetPreviewScaffold(controller: controller),
        );

        final CapturePreviewResponse response = await dtd.onCapturePreview!(
          const PreviewCaptureRequest(
            previewId: 'package:app/widgets.dart::smallButton',
          ),
        );

        expect(response.hasErrors, isFalse);
        expect(
          response.diagnostics.any(
            (PreviewDiagnostic d) =>
                d.kind == .smallTapTarget && d.severity == .warning,
          ),
          isTrue,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('capturePreview emits pendingFrame warning for active ticker', (
    WidgetTester tester,
  ) async {
    final dtd = FakeWidgetPreviewScaffoldDtdServices();
    final controller = WidgetPreviewScaffoldController(
      dtdServicesOverride: dtd,
      previews: () => <WidgetPreview>[
        buildWidgetPreview(
          column: 1,
          functionName: 'animatingPreview',
          libraryUri: 'package:app/widgets.dart',
          line: 10,
          packageName: 'app',
          previewFunction: () => const _ActiveTickerWidget(),
          scriptUri: 'file:///app/lib/widgets.dart',
          transformedPreview: const Preview(
            name: 'animatingPreview',
            size: Size(120, 80),
          ).transform(),
        ),
      ],
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await tester.pumpWidget(TestWidgetPreviewScaffold(controller: controller));

    final CapturePreviewResponse response = await dtd.onCapturePreview!(
      const PreviewCaptureRequest(
        previewId: 'package:app/widgets.dart::animatingPreview',
      ),
    );

    expect(response.hasErrors, isFalse);
    expect(
      response.diagnostics.any(
        (PreviewDiagnostic d) =>
            d.kind == .pendingFrame && d.severity == .warning,
      ),
      isTrue,
    );
  });

  testWidgets('capturePreview pumpMs settles delayed state and clamps at max', (
    WidgetTester tester,
  ) async {
    final dtd = FakeWidgetPreviewScaffoldDtdServices();
    final controller = WidgetPreviewScaffoldController(
      dtdServicesOverride: dtd,
      previews: () => <WidgetPreview>[
        buildWidgetPreview(
          column: 1,
          functionName: 'delayedPreview',
          libraryUri: 'package:app/widgets.dart',
          line: 10,
          packageName: 'app',
          previewFunction: () => const _DelayedSettlingWidget(),
          scriptUri: 'file:///app/lib/widgets.dart',
          transformedPreview: const Preview(
            name: 'delayedPreview',
            size: Size(200, 100),
          ).transform(),
        ),
      ],
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await tester.pumpWidget(TestWidgetPreviewScaffold(controller: controller));

    final CapturePreviewResponse settled = await dtd.onCapturePreview!(
      const PreviewCaptureRequest(
        previewId: 'package:app/widgets.dart::delayedPreview',
        pumpMs: 30,
      ),
    );
    expect(settled.hasErrors, isFalse);
    expect(settled.imageBase64, isNotNull);

    final stopwatch = Stopwatch()..start();
    final CapturePreviewResponse clamped = await dtd.onCapturePreview!(
      const PreviewCaptureRequest(
        previewId: 'package:app/widgets.dart::delayedPreview',
        pumpMs: 5000,
      ),
    );
    stopwatch.stop();
    expect(clamped.hasErrors, isFalse);
    expect(stopwatch.elapsedMilliseconds, lessThan(3500));
  });
}

class _DelayedSettlingWidget extends StatefulWidget {
  const _DelayedSettlingWidget();

  @override
  State<_DelayedSettlingWidget> createState() => _DelayedSettlingWidgetState();
}

class _DelayedSettlingWidgetState extends State<_DelayedSettlingWidget> {
  var _settled = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 10), () {
      if (mounted) {
        setState(() {
          _settled = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(_settled ? 'Ready' : 'Loading');
}

class _ActiveTickerWidget extends StatefulWidget {
  const _ActiveTickerWidget();

  @override
  State<_ActiveTickerWidget> createState() => _ActiveTickerWidgetState();
}

class _ActiveTickerWidgetState extends State<_ActiveTickerWidget>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _controller,
    child: const SizedBox(width: 20, height: 20),
  );
}

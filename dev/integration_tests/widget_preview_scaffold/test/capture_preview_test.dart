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
    final ThemeData base = brightness == Brightness.dark
        ? ThemeData.dark()
        : ThemeData.light();
    return Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(
          surface: brightness == Brightness.dark ? darkColor : lightColor,
        ),
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

Matcher _throwsNotMountedRpcException() => throwsA(
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
);

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
    (WidgetTester tester) async {
      final dtdServices = FakeWidgetPreviewScaffoldDtdServices();
      final controller = WidgetPreviewScaffoldController(
        dtdServicesOverride: dtdServices,
        previews: () => <WidgetPreview>[
          for (var i = 0; i < 24; i++)
            makeTestPreview(
              fileStem: 'spacers',
              functionName: 'spacerPreview$i',
              group: 'Group $i',
              line: i + 1,
              name: 'Spacer $i',
              previewFunction: () => SizedBox(
                width: 200,
                height: 300,
                child: Text('Spacer Group $i'),
              ),
            ),
          makeTestPreview(
            column: 4,
            fileStem: 'offscreen',
            functionName: 'tailOffscreenPreview',
            group: 'Group 24',
            line: 50,
            name: 'Tail Card',
            previewFunction: () => const ColoredBox(
              color: Color(0xFF22AA44),
              child: SizedBox(
                width: 180,
                height: 90,
                child: Center(child: Text('Tail Offscreen Target')),
              ),
            ),
          ),
        ],
      );
      addTearDown(controller.dispose);
      await controller.initialize();

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
      expect(
        filteredCapture.previewId,
        'package:my_app/offscreen.dart::tailOffscreenPreview',
      );
      expect(filteredCapture.hasErrors, isFalse);
      expect(filteredCapture.diagnostics, isEmpty);
      expect(filteredCapture.name, 'Tail Card');
      expect(filteredCapture.pixelRatio, 1.0);
      expect(filteredCapture.renderedWidth, 180.0);
      expect(filteredCapture.renderedHeight, 90.0);
      final decodedFiltered = await _decodePngRgba(
        filteredCapture.imageBase64!,
      );
      expect(decodedFiltered.width, 180);
      expect(decodedFiltered.height, 90);
      expect(
        decodedFiltered.rgba.sublist(0, 4),
        equals(<int>[0x22, 0xAA, 0x44, 0xFF]),
      );
      expect(find.text('Tail Offscreen Target'), findsNothing);

      await controller.toggleFilterBySelectedFile();
      await tester.pump();
      expect(controller.filteredPreviewSetListenable.value, hasLength(25));
      expect(find.text('Spacer Group 0'), findsOneWidget);
      expect(find.text('Tail Offscreen Target'), findsNothing);

      final CapturePreviewResponse sliverCapture = await controller
          .capturePreview(const PreviewCaptureRequest(previewId: 'Tail Card'));
      expect(
        sliverCapture.previewId,
        'package:my_app/offscreen.dart::tailOffscreenPreview',
      );
      expect(sliverCapture.hasErrors, isFalse);
      expect(sliverCapture.renderedWidth, 180.0);
      expect(sliverCapture.renderedHeight, 90.0);
      expect(sliverCapture.imageBase64, isNotNull);
      expect(find.text('Tail Offscreen Target'), findsNothing);
    },
  );

  testWidgets(
    'applies width, height, brightness (light vs dark pixel diff), pixelRatio, '
    'textScaleFactor, includeImage, and isolates ScrollNotificationObserver and ScaffoldMessenger',
    (WidgetTester tester) async {
      Size? observedMediaQuerySize;
      double? observedPixelRatio;
      Brightness? observedPlatformBrightness;
      Color? observedCupertinoPrimary;
      ScrollNotificationObserverState? stagedScrollObserver;
      ScaffoldMessengerState? stagedMessenger;
      TextScaler? observedTextScaler;

      final WidgetPreviewScaffoldController controller = await pumpTestScaffold(
        tester,
        disableSelectedFileFilter: true,
        previews: () => <WidgetPreview>[
          makeTestPreview(
            brightness: Brightness.light,
            fileStem: 'themed',
            functionName: 'themedCard',
            name: 'Themed Card',
            size: const Size(240, 120),
            theme: _buildTestTheme,
            previewFunction: () => Builder(
              builder: (BuildContext context) {
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
          ),
          makeTestPreview(
            fileStem: 'themed',
            functionName: 'bareThemeCard',
            line: 30,
            name: 'Bare Theme Card',
            previewFunction: () => Builder(
              builder: (BuildContext context) => ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: const SizedBox(width: 100, height: 60),
              ),
            ),
          ),
          makeTestPreview(
            fileStem: 'themed',
            functionName: 'scalableText',
            line: 45,
            name: 'Scalable Text',
            previewFunction: () => Builder(
              builder: (BuildContext context) {
                observedTextScaler = MediaQuery.textScalerOf(context);
                return const Text('Scale Target');
              },
            ),
          ),
          makeTestPreview(
            fileStem: 'themed',
            functionName: 'isolatedAppBar',
            line: 60,
            name: 'Isolated AppBar',
            previewFunction: () => SizedBox(
              width: 300,
              height: 56,
              child: AppBar(title: const Text('Header')),
            ),
          ),
        ],
      );

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
      expect(_countDifferingBytes(lightPng.rgba, darkPng.rgba), greaterThan(0));
      expect(
        lightPng.rgba.sublist(0, 4),
        equals(<int>[0xF5, 0xF5, 0xFF, 0xFF]),
      );
      expect(darkPng.rgba.sublist(0, 4), equals(<int>[0x10, 0x18, 0x28, 0xFF]));

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
      expect(bareLightPng.rgba[0], greaterThan(200));
      expect(bareDarkPng.rgba[0], lessThan(60));

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

      final CapturePreviewResponse clampedCapture = await controller
          .capturePreview(
            const PreviewCaptureRequest(
              height: 1440,
              pixelRatio: 2.0,
              previewId: 'Themed Card',
              width: 2560,
            ),
          );
      expect(clampedCapture.pixelRatio, closeTo(4096.0 / 2560.0, 1e-6));
      final clampedPng = await _decodePngRgba(clampedCapture.imageBase64!);
      expect(clampedPng.width, 4096);
      expect(clampedPng.height, 2304);

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
    (WidgetTester tester) async {
      final WidgetPreviewScaffoldController controller = await pumpTestScaffold(
        tester,
        previews: () => <WidgetPreview>[
          makeTestPreview(
            fileStem: 'overflow',
            functionName: 'overflowRow',
            name: 'Overflow Row',
            size: const Size(100, 40),
            previewFunction: () => const Row(
              children: <Widget>[
                SizedBox(
                  width: 148,
                  height: 40,
                  child: ColoredBox(color: Color(0xFF3366CC)),
                ),
              ],
            ),
          ),
        ],
      );

      final CapturePreviewResponse firstOverflow = await controller
          .capturePreview(
            const PreviewCaptureRequest(previewId: 'Overflow Row'),
          );
      expect(firstOverflow.hasErrors, isTrue);
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

      final CapturePreviewResponse secondOverflow = await controller
          .capturePreview(
            const PreviewCaptureRequest(previewId: 'Overflow Row'),
          );
      expect(secondOverflow.diagnostics, equals(firstOverflow.diagnostics));

      final CapturePreviewResponse wideEnough = await controller.capturePreview(
        const PreviewCaptureRequest(previewId: 'Overflow Row', width: 200),
      );
      expect(wideEnough.hasErrors, isFalse);
      expect(wideEnough.diagnostics, isEmpty);
      expect(wideEnough.renderedWidth, 200.0);
    },
  );

  testWidgets(
    'captures unconstrained SizedBox.expand(), compile errors, and build exceptions cleanly without crashing',
    (WidgetTester tester) async {
      final WidgetPreviewScaffoldController controller = await pumpTestScaffold(
        tester,
        previews: () => <WidgetPreview>[
          makeTestPreview(
            fileStem: 'errors',
            functionName: 'bareExpand',
            name: 'Bare SizedBox Expand',
            previewFunction: () => const SizedBox.expand(),
          ),
          makeTestPreview(
            fileStem: 'errors',
            functionName: 'unconstrainedBox',
            name: 'Unconstrained Box',
            previewFunction: () => const SizedBox.expand(
              child: ColoredBox(color: Color(0xFFCC3344)),
            ),
          ),
          makeTestErrorPreview(
            fileStem: 'broken',
            functionName: 'compileBroken',
          ),
          makeTestPreview(
            fileStem: 'errors',
            functionName: 'syncThrowing',
            name: 'Sync Throw',
            previewFunction: () => throw ArgumentError('staged sync throw'),
          ),
          makeTestPreview(
            fileStem: 'errors',
            functionName: 'descendantThrowing',
            name: 'Descendant Throw',
            previewFunction: () => const _ThrowingDescendantBuildWidget(),
          ),
          makeTestPreview(
            fileStem: 'errors',
            functionName: 'themeCallbackThrowing',
            name: 'Theme Callback Throw',
            previewFunction: () => const SizedBox(width: 80, height: 40),
            theme: _throwingThemeCallback,
          ),
          makeTestPreview(
            fileStem: 'errors',
            functionName: 'themeApplyThrowing',
            name: 'Theme Apply Throw',
            previewFunction: () => const SizedBox(width: 80, height: 40),
            theme: _throwingApplyThemeCallback,
          ),
          makeTestPreview(
            fileStem: 'errors',
            functionName: 'localizationsCallbackThrowing',
            localizations: _throwingLocalizationsCallback,
            name: 'Localizations Callback Throw',
            previewFunction: () => const SizedBox(width: 80, height: 40),
          ),
        ],
      );

      for (final String unconstrainedName in const <String>[
        'Bare SizedBox Expand',
        'Unconstrained Box',
      ]) {
        final CapturePreviewResponse res = await controller.capturePreview(
          PreviewCaptureRequest(previewId: unconstrainedName),
        );
        expect(res.hasErrors, isTrue);
        expect(res.imageBase64, isNull);
        expect(res.renderedWidth, 0.0);
        expect(res.renderedHeight, 0.0);
        expect(res.diagnostics.single.phase, PreviewDiagnosticPhase.layout);
        expect(
          res.diagnostics.single.kind,
          PreviewDiagnosticKind.unconstrained,
        );
      }

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

      final CapturePreviewResponse compileError = await controller
          .capturePreview(
            const PreviewCaptureRequest(
              previewId: 'package:my_app/broken.dart::compileBroken',
            ),
          );
      expect(compileError.hasErrors, isTrue);
      expect(compileError.imageBase64, isNull);
      expect(
        compileError.diagnostics.single.phase,
        PreviewDiagnosticPhase.compile,
      );
      expect(
        compileError.diagnostics.single.kind,
        PreviewDiagnosticKind.compileError,
      );
      expect(
        compileError.diagnostics.single.summary,
        'package:my_app/broken.dart has errors!',
      );

      for (final (String name, String expectedSnippet)
          in const <(String, String)>[
            ('Sync Throw', 'staged sync throw'),
            ('Descendant Throw', 'staged descendant build failure'),
            ('Theme Callback Throw', 'staged theme callback failure'),
            ('Theme Apply Throw', 'staged theme apply failure'),
            (
              'Localizations Callback Throw',
              'staged localizations callback failure',
            ),
          ]) {
        final CapturePreviewResponse res = await controller.capturePreview(
          PreviewCaptureRequest(previewId: name),
        );
        expect(res.hasErrors, isTrue);
        expect(res.imageBase64, isNull);
        expect(res.renderedWidth, 0.0);
        expect(res.renderedHeight, 0.0);
        expect(res.diagnostics.single.phase, PreviewDiagnosticPhase.build);
        expect(res.diagnostics.single.kind, PreviewDiagnosticKind.exception);
        expect(res.diagnostics.single.summary, contains(expectedSnippet));
      }
    },
  );

  testWidgets(
    'resolves unique name shorthand, rejects ambiguous or missing IDs, and serializes concurrent captures',
    (WidgetTester tester) async {
      final WidgetPreviewScaffoldController controller = await pumpTestScaffold(
        tester,
        previews: () => <WidgetPreview>[
          makeTestPreview(
            fileStem: 'a',
            functionName: 'alphaPreview',
            name: 'Unique Alpha',
            previewFunction: () => const ColoredBox(
              color: Color(0xFFFF0000),
              child: SizedBox(width: 110, height: 55),
            ),
          ),
          makeTestPreview(
            fileStem: 'a',
            functionName: 'dupOne',
            name: 'Shared Name',
            previewFunction: () => const ColoredBox(
              color: Color(0xFF00FF00),
              child: SizedBox(width: 220, height: 75),
            ),
          ),
          makeTestPreview(
            fileStem: 'b',
            functionName: 'dupTwo',
            name: 'Shared Name',
            previewFunction: () => const ColoredBox(
              color: Color(0xFF0000FF),
              child: SizedBox(width: 165, height: 95),
            ),
          ),
        ],
      );

      final CapturePreviewResponse alpha = await controller.capturePreview(
        const PreviewCaptureRequest(previewId: 'Unique Alpha'),
      );
      expect(alpha.previewId, 'package:my_app/a.dart::alphaPreview');
      expect(alpha.name, 'Unique Alpha');
      expect(alpha.renderedWidth, 110.0);
      expect(alpha.renderedHeight, 55.0);

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

      for (final String missing in const <String>[
        'package:my_app/missing.dart::missingFn',
        'Nonexistent Card',
      ]) {
        await expectLater(
          controller.capturePreview(PreviewCaptureRequest(previewId: missing)),
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
      }

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
    (WidgetTester tester) async {
      final controller = WidgetPreviewScaffoldController(
        dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
        previews: () => <WidgetPreview>[
          makeTestPreview(
            fileStem: 'startup',
            functionName: 'delayedMountPreview',
            name: 'Delayed Mount Card',
            previewFunction: () => const ColoredBox(
              color: Color(0xFF4488CC),
              child: SizedBox(width: 160, height: 80),
            ),
          ),
        ],
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      var completed = false;
      final Future<CapturePreviewResponse> pendingCapture = controller
          .capturePreview(
            const PreviewCaptureRequest(previewId: 'Delayed Mount Card'),
          )
          .whenComplete(() => completed = true);
      await pumpEventQueue();
      expect(completed, isFalse);

      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: controller),
      );
      final CapturePreviewResponse response = await pendingCapture;
      expect(
        response.previewId,
        'package:my_app/startup.dart::delayedMountPreview',
      );
      expect(response.hasErrors, isFalse);
      expect(response.renderedWidth, 160.0);
      expect(response.renderedHeight, 80.0);
      final delayedPng = await _decodePngRgba(response.imageBase64!);
      expect(delayedPng.width, 160);
      expect(delayedPng.height, 80);
      expect(
        delayedPng.rgba.sublist(0, 4),
        equals(<int>[0x44, 0x88, 0xCC, 0xFF]),
      );

      final unmountedController = WidgetPreviewScaffoldController(
        dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
        previews: () => <WidgetPreview>[
          makeTestPreview(
            fileStem: 'startup',
            functionName: 'unmountedPreview',
            name: 'Unmounted Card',
            previewFunction: () => const SizedBox(width: 50, height: 50),
          ),
        ],
        stageHostTimeout: const Duration(milliseconds: 40),
      );
      addTearDown(unmountedController.dispose);
      await unmountedController.initialize();
      await expectLater(
        unmountedController.capturePreview(
          const PreviewCaptureRequest(previewId: 'Unmounted Card'),
        ),
        _throwsNotMountedRpcException(),
      );
    },
  );

  testWidgets(
    'captures when AppLifecycleState is hidden (framesEnabled is false) and releases lock on frame timeout',
    (WidgetTester tester) async {
      addTearDown(() {
        binding.framePolicy =
            LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
        binding.resetInternalState();
      });

      WidgetPreview buildHiddenCard() => makeTestPreview(
        fileStem: 'hidden',
        functionName: 'hiddenTabPreview',
        name: 'Hidden Tab Card',
        previewFunction: () => const ColoredBox(
          color: Color(0xFFAA3377),
          child: SizedBox(
            width: 140,
            height: 70,
            child: Center(child: Text('Hidden Tab Target')),
          ),
        ),
      );

      final WidgetPreviewScaffoldController controller = await pumpTestScaffold(
        tester,
        previews: () => <WidgetPreview>[buildHiddenCard()],
      );

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
      final hiddenPng = await _decodePngRgba(hiddenResponse.imageBase64!);
      expect(
        hiddenPng.rgba.sublist(0, 4),
        equals(<int>[0xAA, 0x33, 0x77, 0xFF]),
      );

      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      final WidgetPreviewScaffoldController timeoutController =
          await pumpTestScaffold(
            tester,
            stageFrameTimeout: const Duration(milliseconds: 50),
            previews: () => <WidgetPreview>[
              buildHiddenCard(),
              makeTestErrorPreview(
                fileStem: 'hidden',
                functionName: 'compileBrokenAfterTimeout',
              ),
            ],
          );

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
    (WidgetTester tester) async {
      WidgetPreview buildUnmountCard() => makeTestPreview(
        fileStem: 'unmount',
        functionName: 'unmountPreview',
        name: 'Unmount Card',
        previewFunction: () => const ColoredBox(
          color: Color(0xFF339966),
          child: SizedBox(width: 150, height: 75),
        ),
      );

      final WidgetPreviewScaffoldController shortTimeoutController =
          await pumpTestScaffold(
            tester,
            stageHostTimeout: const Duration(milliseconds: 50),
            previews: () => <WidgetPreview>[buildUnmountCard()],
          );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await expectLater(
        shortTimeoutController.capturePreview(
          const PreviewCaptureRequest(previewId: 'Unmount Card'),
        ),
        _throwsNotMountedRpcException(),
      );
      expect(tester.takeException(), isNull);

      final WidgetPreviewScaffoldController controller = await pumpTestScaffold(
        tester,
        previews: () => <WidgetPreview>[buildUnmountCard()],
      );
      expect(
        (await controller.capturePreview(
          const PreviewCaptureRequest(previewId: 'Unmount Card'),
        )).renderedWidth,
        150.0,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      final Future<CapturePreviewResponse> waitingForRemount = controller
          .capturePreview(
            const PreviewCaptureRequest(previewId: 'Unmount Card'),
          );
      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: controller),
      );
      expect((await waitingForRemount).hasErrors, isFalse);

      final Future<void> inFlightExpectation = expectLater(
        controller.capturePreview(
          const PreviewCaptureRequest(previewId: 'Unmount Card'),
        ),
        _throwsNotMountedRpcException(),
      );
      await Future<void>.value();
      await tester.pumpWidget(const SizedBox.shrink());
      await inFlightExpectation;
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: controller),
      );
      await tester.pump();
      expect(
        (await controller.capturePreview(
          const PreviewCaptureRequest(previewId: 'Unmount Card'),
        )).hasErrors,
        isFalse,
      );
    },
  );

  testWidgets(
    'off-screen capturePreview renders a bare Material TextField when defaultLocalizations is provided',
    (WidgetTester tester) async {
      final WidgetPreviewScaffoldController controller = await pumpTestScaffold(
        tester,
        previews: () => <WidgetPreview>[
          makeTestPreview(
            defaultLocalizations: _defaultCaptureLocalizations,
            fileStem: 'text_field',
            functionName: 'bareMaterialTextField',
            name: 'Bare Material TextField',
            previewFunction: () => const Material(
              child: SizedBox(width: 220, height: 80, child: TextField()),
            ),
          ),
        ],
      );

      final CapturePreviewResponse response = await controller.capturePreview(
        const PreviewCaptureRequest(previewId: 'Bare Material TextField'),
      );
      expect(response.hasErrors, isFalse);
      expect(response.diagnostics, isEmpty);
      expect(tester.takeException(), isNull);
      final decoded = await _decodePngRgba(response.imageBase64!);
      expect(decoded.width, 220);
      expect(decoded.height, 80);
    },
  );

  testWidgets(
    'PreviewAssetBundle aliases AssetManifest.bin and AssetManifest.bin.json',
    (WidgetTester tester) async {
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
        return switch (utf8.decode(Uint8List.sublistView(message!))) {
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
      expect(parsed.listAssets(), contains('packages/my_app/assets/logo.png'));
      expect(parsed.listAssets(), contains('assets/logo.png'));
      expect(parsed.listAssets(), isNot(contains('assets/icon.png')));

      final ByteData aliasedJsonBytes = await bundle.load(
        'AssetManifest.bin.json',
      );
      final Object? decodedJsonMap = const StandardMessageCodec().decodeMessage(
        ByteData.sublistView(
          base64Decode(
            jsonDecode(utf8.decode(Uint8List.sublistView(aliasedJsonBytes)))
                as String,
          ),
        ),
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
      final preview = WidgetPreview.test(
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
      );
      final brightnessNotifier = ValueNotifier<Brightness>(Brightness.light);
      addTearDown(brightnessNotifier.dispose);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: WidgetPreviewMediaQueryOverride(
            preview: preview,
            brightnessListenable: brightnessNotifier,
            child: preview.previewBuilder(),
          ),
        ),
      );
      expect(observedSize, const Size(300, 600));
    },
  );

  testWidgets(
    'capturePreview emits zeroSize, textTruncated, smallTapTarget, and pendingFrame diagnostics',
    (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final dtd = FakeWidgetPreviewScaffoldDtdServices();
        await pumpTestScaffold(
          tester,
          dtdServices: dtd,
          previews: () => <WidgetPreview>[
            makeTestPreview(
              functionName: 'zeroPreview',
              name: 'zeroPreview',
              previewFunction: () => const SizedBox.shrink(),
            ),
            makeTestPreview(
              functionName: 'truncatedText',
              name: 'truncatedText',
              size: const Size(80, 40),
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
            ),
            makeTestPreview(
              functionName: 'smallButton',
              name: 'smallButton',
              size: const Size(120, 80),
              previewFunction: () => Center(
                child: Semantics(
                  onTap: () {},
                  child: const SizedBox(width: 24, height: 24),
                ),
              ),
            ),
            makeTestPreview(
              functionName: 'animatingPreview',
              name: 'animatingPreview',
              size: const Size(120, 80),
              previewFunction: () => const _ActiveTickerWidget(),
            ),
          ],
        );

        for (final (
              String name,
              bool expectedHasErrors,
              PreviewDiagnosticKind expectedKind,
              PreviewDiagnosticSeverity expectedSeverity,
            )
            in const <
              (String, bool, PreviewDiagnosticKind, PreviewDiagnosticSeverity)
            >[
              ('zeroPreview', true, .zeroSize, .error),
              ('truncatedText', false, .textTruncated, .warning),
              ('smallButton', false, .smallTapTarget, .warning),
              ('animatingPreview', false, .pendingFrame, .warning),
            ]) {
          final CapturePreviewResponse response = await dtd.onCapturePreview!(
            PreviewCaptureRequest(previewId: name),
          );
          expect(response.hasErrors, expectedHasErrors);
          expect(
            response.diagnostics.any(
              (PreviewDiagnostic d) =>
                  d.kind == expectedKind && d.severity == expectedSeverity,
            ),
            isTrue,
          );
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('capturePreview pumpMs settles delayed state and clamps at max', (
    WidgetTester tester,
  ) async {
    final dtd = FakeWidgetPreviewScaffoldDtdServices();
    await pumpTestScaffold(
      tester,
      dtdServices: dtd,
      previews: () => <WidgetPreview>[
        makeTestPreview(
          functionName: 'delayedPreview',
          name: 'delayedPreview',
          previewFunction: () => const _DelayedSettlingWidget(),
          size: const Size(200, 100),
        ),
      ],
    );

    final CapturePreviewResponse settled = await dtd.onCapturePreview!(
      const PreviewCaptureRequest(previewId: 'delayedPreview', pumpMs: 30),
    );
    expect(settled.hasErrors, isFalse);
    expect(settled.imageBase64, isNotNull);

    final stopwatch = Stopwatch()..start();
    final CapturePreviewResponse clamped = await dtd.onCapturePreview!(
      const PreviewCaptureRequest(previewId: 'delayedPreview', pumpMs: 5000),
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
        setState(() => _settled = true);
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

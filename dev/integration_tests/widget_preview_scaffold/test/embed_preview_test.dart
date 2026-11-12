// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_rpc_2/json_rpc_2.dart' show RpcException;
import 'package:material_ui/material_ui.dart';
import 'package:widget_preview_scaffold/src/controls.dart';
import 'package:widget_preview_scaffold/src/dtd/dtd_services.dart';
import 'package:widget_preview_scaffold/src/theme/ide_theme.dart';
import 'package:widget_preview_scaffold/src/utils.dart';
import 'package:widget_preview_scaffold/src/utils/url/url.dart';
import 'package:widget_preview_scaffold/src/widget_preview.dart';
import 'package:widget_preview_scaffold/src/widget_preview_rendering.dart';
import 'package:widget_preview_scaffold/src/widget_preview_scaffold_controller.dart';

import 'utils/widget_preview_scaffold_test_utils.dart';

const _kAlphaId = 'package:my_app/alpha.dart::alphaPreview';
const _kBetaId = 'package:my_app/beta.dart::betaPreview';
const _kBrokenId = 'package:my_app/broken.dart::brokenPreview';
const _kDupOneId = 'package:my_app/dup_a.dart::dupPreview';
const _kDupTwoId = 'package:my_app/dup_b.dart::dupPreview';

class _InteractiveCardPreview extends StatefulWidget {
  const _InteractiveCardPreview({required this.label});

  final String label;

  @override
  State<_InteractiveCardPreview> createState() =>
      _InteractiveCardPreviewState();
}

class _InteractiveCardPreviewState extends State<_InteractiveCardPreview> {
  final _textController = TextEditingController();
  var _count = 0;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size mediaSize = MediaQuery.sizeOf(context);
    final Brightness platformBrightness = MediaQuery.platformBrightnessOf(
      context,
    );
    final double textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final Brightness themeBrightness = Theme.of(context).brightness;
    final BoxConstraints windowConstraints =
        WidgetPreviewerWindowConstraints.getRootConstraints(context);
    final bool hasScrollObserver =
        ScrollNotificationObserver.maybeOf(context) != null;

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('${widget.label}: count=$_count'),
          Text(
            'media=${mediaSize.width.toInt()}x${mediaSize.height.toInt()} '
            'platform=${platformBrightness.name} '
            'theme=${themeBrightness.name} '
            'scale=${textScale.toStringAsFixed(1)} '
            'constraints=${windowConstraints.maxWidth.toInt()}x${windowConstraints.maxHeight.toInt()} '
            'scrollObserver=$hasScrollObserver',
          ),
          ElevatedButton(
            onPressed: () => setState(() => _count++),
            child: const Text('Increment'),
          ),
          TextField(
            controller: _textController,
            decoration: const InputDecoration(hintText: 'Note'),
          ),
        ],
      ),
    );
  }
}

final class _BrightnessAwarePreviewTheme extends PreviewThemeData {
  const _BrightnessAwarePreviewTheme();

  static const kLightPrimary = Color(0xFF0055AA);
  static const kDarkPrimary = Color(0xFF99CCFF);

  @override
  Widget apply(BuildContext context, Widget child) {
    final Brightness brightness = MediaQuery.platformBrightnessOf(context);
    final ThemeData base = brightness == Brightness.dark
        ? ThemeData.dark()
        : ThemeData.light();
    return Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(
          primary: brightness == Brightness.dark ? kDarkPrimary : kLightPrimary,
        ),
      ),
      child: child,
    );
  }
}

PreviewThemeData _brightnessAwareTheme() =>
    const _BrightnessAwarePreviewTheme();

WidgetPreview _buildAlphaPreview() => buildWidgetPreview(
  column: 1,
  functionName: 'alphaPreview',
  libraryUri: 'package:my_app/alpha.dart',
  line: 10,
  packageName: 'my_app',
  previewFunction: () => const _InteractiveCardPreview(label: 'Alpha'),
  scriptUri: 'file:///project/lib/alpha.dart',
  transformedPreview: Preview(
    name: 'Alpha Card',
    theme: _brightnessAwareTheme,
  ).transform(),
);

WidgetPreview _buildBetaPreview() => buildWidgetPreview(
  column: 1,
  functionName: 'betaPreview',
  libraryUri: 'package:my_app/beta.dart',
  line: 15,
  packageName: 'my_app',
  previewFunction: () => const _InteractiveCardPreview(label: 'Beta'),
  scriptUri: 'file:///project/lib/beta.dart',
  transformedPreview: const Preview(
    brightness: Brightness.dark,
    name: 'Beta Card',
    size: Size(300, 400),
  ).transform(),
);

WidgetPreview _buildExpandingPreview() => buildWidgetPreview(
  column: 1,
  functionName: 'expandingPreview',
  libraryUri: 'package:my_app/expanding.dart',
  line: 20,
  packageName: 'my_app',
  previewFunction: () => const SizedBox.expand(
    child: ColoredBox(
      color: Color(0xFF228844),
      child: Center(child: Text('Expanded Preview')),
    ),
  ),
  scriptUri: 'file:///project/lib/expanding.dart',
  transformedPreview: const Preview(name: 'Expanding').transform(),
);

List<WidgetPreview> _buildTestPreviews() => <WidgetPreview>[
  _buildAlphaPreview(),
  _buildBetaPreview(),
  _buildExpandingPreview(),
  buildWidgetPreview(
    column: 1,
    functionName: 'dupPreview',
    libraryUri: 'package:my_app/dup_a.dart',
    line: 30,
    packageName: 'my_app',
    previewFunction: () => const Text('Dup A'),
    scriptUri: 'file:///project/lib/dup_a.dart',
    transformedPreview: const Preview(name: 'Shared Name').transform(),
  ),
  buildWidgetPreview(
    column: 1,
    functionName: 'dupPreview',
    libraryUri: 'package:my_app/dup_b.dart',
    line: 40,
    packageName: 'my_app',
    previewFunction: () => const Text('Dup B'),
    scriptUri: 'file:///project/lib/dup_b.dart',
    transformedPreview: const Preview(name: 'Shared Name').transform(),
  ),
  buildWidgetPreviewError(
    column: 1,
    dependencyHasErrors: false,
    functionName: 'brokenPreview',
    libraryUri: 'package:my_app/broken.dart',
    line: 50,
    packageName: 'my_app',
    scriptUri: 'file:///project/lib/broken.dart',
  ),
];

void main() {
  tearDown(debugResetUrlTestState);

  group('$EmbedPreviewParams', () {
    test('strips leading /, #, ? from fragments and decodes embed parameters', () {
      expect(
        parseFragmentParameters(
          '/#?embed=1&previewId=package%3Amy_app%2Falpha.dart%3A%3AalphaPreview'
          '&brightness=dark&width=375&height=667.5&textScale=1.5&dtdProxy=%2Fdtd_ws',
        ),
        equals(<String, String>{
          'embed': '1',
          'previewId': _kAlphaId,
          'brightness': 'dark',
          'width': '375',
          'height': '667.5',
          'textScale': '1.5',
          'dtdProxy': '/dtd_ws',
        }),
      );

      final parsed = EmbedPreviewParams.fromFragment(
        '#/embed=1&previewId=package%3Amy_app%2Falpha.dart%3A%3AalphaPreview'
        '&brightness=light&width=412&height=915&textScale=1.3&dtdProxy=%2Fdtd_ws',
      );
      expect(parsed.isEmbed, isTrue);
      expect(parsed.previewId, _kAlphaId);
      expect(parsed.brightness, Brightness.light);
      expect(parsed.width, 412.0);
      expect(parsed.height, 915.0);
      expect(parsed.textScale, 1.3);
      expect(parsed.dtdProxy, '/dtd_ws');
      expect(
        parsed.resolveDtdProxyUri(
          Uri.parse('https://preview.proxy.example:8443/live'),
        ),
        Uri.parse('wss://preview.proxy.example:8443/dtd_ws'),
      );
      expect(
        parsed.resolveDtdProxyUri(Uri.parse('http://127.0.0.1:5050/')),
        Uri.parse('ws://127.0.0.1:5050/dtd_ws'),
      );
      expect(
        parsed.resolveDtdProxyUri(Uri.parse('file:///tmp/index.html')),
        isNull,
      );

      // Ignores invalid/non-positive dimensions, unknown brightness, and
      // malformed percent-encoding without throwing.
      final invalid = EmbedPreviewParams.fromFragment(
        'embed=1&brightness=sepia&width=0&height=-10&textScale=NaN',
      );
      expect(invalid.isEmbed, isTrue);
      expect(invalid.isAllPreviews, isTrue);
      expect(invalid.brightness, isNull);
      expect(invalid.width, isNull);
      expect(invalid.height, isNull);
      expect(invalid.textScale, isNull);
      expect(parseFragmentParameters('embed=1&bad=%ZZ'), isEmpty);

      expect(EmbedPreviewParams.fromFragment('embed=1').isAllPreviews, isTrue);
      expect(
        EmbedPreviewParams.fromFragment('embed=1&previewId=').isAllPreviews,
        isTrue,
      );
      expect(
        EmbedPreviewParams.fromFragment('embed=1&previewId=*').isAllPreviews,
        isTrue,
      );
      expect(
        EmbedPreviewParams.fromFragment(
          'embed=1&previewId=alpha',
        ).isAllPreviews,
        isFalse,
      );
    });
  });

  group('Chromeless embed mode', () {
    testWidgets(
      'renders single preview interactively without chrome, connects readOnly, and switches in-memory on hash changes',
      (WidgetTester tester) async {
        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent(_kAlphaId)}'
          '&brightness=light&width=375&height=667&textScale=1.0',
        );

        final fakeDtd = FakeWidgetPreviewScaffoldDtdServices();
        final controller = WidgetPreviewScaffoldController(
          dtdServicesOverride: fakeDtd,
          previews: _buildTestPreviews,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        expect(fakeDtd.lastConnectReadOnly, isTrue);

        await tester.pumpWidget(
          TestWidgetPreviewScaffold(controller: controller),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        // Chromeless mode omits toolbar and card controls.
        expect(find.byType(PreviewSearchControls), findsNothing);
        expect(find.byType(LayoutTypeSelector), findsNothing);
        expect(find.byType(WidgetPreviewerRestartButton), findsNothing);
        expect(find.byType(WidgetInspectorToggle), findsNothing);
        expect(find.byType(ZoomControls), findsNothing);
        expect(find.byType(BrightnessToggleButton), findsNothing);
        expect(find.byType(SoftRestartButton), findsNothing);

        // Required ancestor tree wraps the embedded preview.
        expect(find.byType(Scaffold), findsOneWidget);
        expect(find.byType(LayoutBuilder), findsAtLeastNWidgets(1));
        expect(find.byType(WidgetPreviewerWindowConstraints), findsOneWidget);
        expect(find.byType(WidgetPreviewTheming), findsOneWidget);
        expect(
          find.byType(ScrollNotificationObserver),
          findsAtLeastNWidgets(1),
        );

        expect(find.text('Alpha: count=0'), findsOneWidget);
        expect(
          find.text(
            'media=375x667 platform=light theme=light scale=1.0 '
            'constraints=375x667 scrollObserver=true',
          ),
          findsOneWidget,
        );
        expect(
          Theme.of(
            tester.element(find.text('Alpha: count=0')),
          ).colorScheme.primary,
          _BrightnessAwarePreviewTheme.kLightPrimary,
        );

        // Interactive tap and text input work directly in the chromeless preview.
        await tester.tap(find.text('Increment'));
        await tester.pump();
        expect(find.text('Alpha: count=1'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'Hello live');
        await tester.pump();
        expect(find.text('Hello live'), findsOneWidget);

        // Update hash to dark mode + new viewport + textScale on the same preview:
        // updates in-memory in a single frame while preserving widget state.
        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent(_kAlphaId)}'
          '&brightness=dark&width=768&height=1024&textScale=1.6',
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        expect(find.text('Alpha: count=1'), findsOneWidget);
        expect(find.text('Hello live'), findsOneWidget);
        expect(
          find.text(
            'media=768x1024 platform=dark theme=dark scale=1.6 '
            'constraints=768x1024 scrollObserver=true',
          ),
          findsOneWidget,
        );
        expect(
          Theme.of(
            tester.element(find.text('Alpha: count=1')),
          ).colorScheme.primary,
          _BrightnessAwarePreviewTheme.kDarkPrimary,
        );

        // Oversized desktop viewport inside a smaller scaffold viewport scrolls
        // without overflowing.
        tester.view.physicalSize = const Size(450, 500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent(_kAlphaId)}'
          '&brightness=light&width=1280&height=800&textScale=1.0',
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
          find.text(
            'media=1280x800 platform=light theme=light scale=1.0 '
            'constraints=1280x800 scrollObserver=true',
          ),
          findsOneWidget,
        );

        // Switch previewId by unique shorthand name: switches cleanly and resets
        // preview state for the new preview.
        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent('Beta Card')}',
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        expect(find.text('Alpha: count=1'), findsNothing);
        expect(find.text('Beta: count=0'), findsOneWidget);
        expect(
          find.text(
            'media=300x400 platform=dark theme=dark scale=1.0 '
            'constraints=300x400 scrollObserver=true',
          ),
          findsOneWidget,
        );

        // Switch to an unconstrained SizedBox.expand() preview without width/height
        // hash overrides: bounded cleanly by LayoutBuilder / WidgetPreviewWrapper.
        debugSetUrlFragment('embed=1&previewId=Expanding');
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Expanded Preview'), findsOneWidget);

        // Hash transitions never triggered a browser reload.
        expect(debugReloadCount, 0);

        // Unmounting cleans up onUrlFragmentChange subscription without error.
        await tester.pumpWidget(const SizedBox.shrink());
        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent(_kBetaId)}',
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'displays clean status messages for unknown, ambiguous, compile-error, and throwing previews',
      (WidgetTester tester) async {
        debugSetUrlFragment('embed=1&previewId=MissingCard');

        final controller = WidgetPreviewScaffoldController(
          dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
          previews: () => <WidgetPreview>[
            ..._buildTestPreviews(),
            buildWidgetPreview(
              column: 1,
              functionName: 'throwingPreview',
              libraryUri: 'package:my_app/throwing.dart',
              line: 60,
              packageName: 'my_app',
              previewFunction: () => throw StateError('boom during build'),
              scriptUri: 'file:///project/lib/throwing.dart',
              transformedPreview: const Preview(name: 'Throwing').transform(),
            ),
          ],
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await tester.pumpWidget(
          TestWidgetPreviewScaffold(controller: controller),
        );
        await tester.pump();

        // 1. Unknown previewId.
        expect(find.text('Preview not found'), findsOneWidget);
        expect(find.textContaining('MissingCard'), findsOneWidget);
        expect(find.textContaining(_kAlphaId), findsOneWidget);

        // 3. Ambiguous shorthand name.
        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent('Shared Name')}',
        );
        await tester.pump();
        expect(find.text('Ambiguous preview name'), findsOneWidget);
        expect(find.textContaining(_kDupOneId), findsOneWidget);
        expect(find.textContaining(_kDupTwoId), findsOneWidget);

        // 4. Compile-error preview.
        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent(_kBrokenId)}',
        );
        await tester.pump();
        expect(find.text('Preview has errors'), findsOneWidget);
        expect(
          find.textContaining('package:my_app/broken.dart has errors!'),
          findsOneWidget,
        );

        // 5. Runtime build error shows WidgetPreviewErrorWidget without crashing.
        debugSetUrlFragment('embed=1&previewId=Throwing');
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(WidgetPreviewErrorWidget), findsOneWidget);
        expect(find.textContaining('boom during build'), findsOneWidget);
      },
    );

    testWidgets(
      'clears _layoutError when hash dimensions or viewport constraints recover on the same preview',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(240, 400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        debugSetUrlFragment('embed=1&previewId=MinWidth&width=200&height=300');

        final controller = WidgetPreviewScaffoldController(
          dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
          previews: () => <WidgetPreview>[
            buildWidgetPreview(
              column: 1,
              functionName: 'minWidthPreview',
              libraryUri: 'package:my_app/min_width.dart',
              line: 70,
              packageName: 'my_app',
              previewFunction: () => const _MinWidthGuard(
                minWidth: 300.0,
                child: Text('Width OK'),
              ),
              scriptUri: 'file:///project/lib/min_width.dart',
              transformedPreview: const Preview(name: 'MinWidth').transform(),
            ),
          ],
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await tester.pumpWidget(
          TestWidgetPreviewScaffold(controller: controller),
        );
        expect(tester.takeException(), isA<StateError>());
        await tester.pump();
        expect(find.byType(WidgetPreviewErrorWidget), findsOneWidget);
        expect(find.textContaining('Requires width >= 300.0'), findsOneWidget);

        // Increasing width via location.hash clears _layoutError for the same
        // ValueKey(preview.id) without replacing the preview instance.
        debugSetUrlFragment('embed=1&previewId=MinWidth&width=350&height=300');
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(WidgetPreviewErrorWidget), findsNothing);
        expect(find.text('Width OK'), findsOneWidget);

        // Drop width/height overrides so preview relies on viewport constraints
        // (currently 240px wide -> fails again), then resize viewport >= 300.
        debugSetUrlFragment('embed=1&previewId=MinWidth');
        await tester.pump();
        expect(tester.takeException(), isA<StateError>());
        await tester.pump();
        expect(find.byType(WidgetPreviewErrorWidget), findsOneWidget);

        tester.view.physicalSize = const Size(420, 400);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(WidgetPreviewErrorWidget), findsNothing);
        expect(find.text('Width OK'), findsOneWidget);
      },
    );

    testWidgets(
      'falls back to ideTheme brightness when neither hash nor preview specifies brightness',
      (WidgetTester tester) async {
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent(_kAlphaId)}',
        );

        final controller = WidgetPreviewScaffoldController(
          dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
          previews: _buildTestPreviews,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await tester.pumpWidget(
          WidgetPreviewScaffold(
            controller: controller,
            enableWebView: false,
            ideTheme: const IdeTheme(isDarkMode: true),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        expect(find.textContaining('platform=dark theme=dark'), findsOneWidget);
        expect(
          Theme.of(tester.element(find.byType(Scaffold))).brightness,
          Brightness.dark,
        );
        expect(
          Theme.of(
            tester.element(find.text('Alpha: count=0')),
          ).colorScheme.primary,
          _BrightnessAwarePreviewTheme.kDarkPrimary,
        );
      },
    );

    testWidgets(
      'detaches stage capture host when transitioning from standard scaffold to embed mode',
      (WidgetTester tester) async {
        debugSetUrlFragment('');

        final controller = WidgetPreviewScaffoldController(
          dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
          previews: _buildTestPreviews,
          stageHostTimeout: const Duration(milliseconds: 20),
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await tester.pumpWidget(
          TestWidgetPreviewScaffold(controller: controller),
        );
        await tester.pump();
        expect(find.byType(PreviewSearchControls), findsOneWidget);

        debugSetUrlFragment('embed=1&previewId=Expanding');
        await tester.pump();
        expect(find.text('Expanded Preview'), findsOneWidget);
        expect(find.byType(PreviewSearchControls), findsNothing);

        final Future<CapturePreviewResponse> captureFuture = controller
            .capturePreview(
              const PreviewCaptureRequest(previewId: 'Expanding'),
            );
        final Future<void> assertion = expectLater(
          captureFuture,
          throwsA(
            isA<RpcException>().having(
              (RpcException e) => e.code,
              'code',
              WidgetPreviewScaffoldDtdServices.kNoValueForKey,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 25));
        await assertion;
      },
    );

    testWidgets(
      'handles browser pushRouteInformation fragment updates without route lookup errors or single-entry history',
      (WidgetTester tester) async {
        final navigationCalls = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.navigation, (
              MethodCall call,
            ) async {
              navigationCalls.add(call.method);
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.navigation, null),
        );

        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent(_kAlphaId)}&brightness=dark',
        );

        final controller = WidgetPreviewScaffoldController(
          dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
          previews: _buildTestPreviews,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await tester.pumpWidget(
          TestWidgetPreviewScaffold(controller: controller),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Alpha: count=0'), findsOneWidget);
        expect(navigationCalls, contains('selectMultiEntryHistory'));
        expect(navigationCalls, isNot(contains('selectSingleEntryHistory')));

        final bool handled = await WidgetsBinding.instance.handlePushRoute(
          'embed=1&previewId=${Uri.encodeQueryComponent(_kBetaId)}&brightness=light',
        );
        expect(handled, isTrue);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Beta: count=0'), findsOneWidget);
        expect(
          find.textContaining('platform=light theme=light'),
          findsOneWidget,
        );

        // Non-embed route push while in embed mode is absorbed without errors.
        final bool ignoredHome = await WidgetsBinding.instance.handlePushRoute(
          '/',
        );
        expect(ignoredHome, isTrue);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Beta: count=0'), findsOneWidget);

        // Subsequent fragment update via onUrlFragmentChange continues to work.
        debugSetUrlFragment('embed=1&previewId=Expanding');
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Expanded Preview'), findsOneWidget);
        expect(navigationCalls, isNot(contains('selectSingleEntryHistory')));
      },
    );

    testWidgets(
      'transitions from standard scaffold to embed mode via handlePushRoute and switches to multi-entry history',
      (WidgetTester tester) async {
        final navigationCalls = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.navigation, (
              MethodCall call,
            ) async {
              navigationCalls.add(call.method);
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.navigation, null),
        );

        debugSetUrlFragment('');

        final controller = WidgetPreviewScaffoldController(
          dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
          previews: _buildTestPreviews,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await tester.pumpWidget(
          TestWidgetPreviewScaffold(controller: controller),
        );
        await tester.pump();
        expect(find.byType(PreviewSearchControls), findsOneWidget);
        expect(navigationCalls, contains('selectSingleEntryHistory'));

        navigationCalls.clear();
        final bool handled = await WidgetsBinding.instance.handlePushRoute(
          'embed=1&previewId=Expanding',
        );
        expect(handled, isTrue);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Expanded Preview'), findsOneWidget);
        expect(find.byType(PreviewSearchControls), findsNothing);
        expect(navigationCalls, contains('selectMultiEntryHistory'));
        expect(navigationCalls, isNot(contains('selectSingleEntryHistory')));
      },
    );

    testWidgets(
      'renders all previews grouped by group when previewId is omitted or *',
      (WidgetTester tester) async {
        debugSetUrlFragment('embed=1');

        final controller = WidgetPreviewScaffoldController(
          dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
          previews: _buildGroupedTestPreviews,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await tester.pumpWidget(
          TestWidgetPreviewScaffold(controller: controller),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        expect(find.byType(PreviewSearchControls), findsNothing);
        expect(find.byType(LayoutTypeSelector), findsNothing);
        expect(find.text('Buttons'), findsOneWidget);
        expect(find.text('Cards'), findsOneWidget);
        expect(find.text('Invalid Previews'), findsOneWidget);
        expect(find.text('1'), findsNWidgets(2));
        expect(find.text('2'), findsOneWidget);
        expect(find.text('Primary Button'), findsOneWidget);
        expect(find.text('brokenButtonPreview'), findsOneWidget);
        expect(
          find.text('package:my_app/broken_button.dart has errors!'),
          findsOneWidget,
        );
        expect(find.text('Alpha Card'), findsOneWidget);

        // Interactive sibling cards continue working even when another card has errors.
        expect(find.text('Alpha: count=0'), findsOneWidget);
        await tester.tap(find.text('Increment').first);
        await tester.pump();
        expect(find.text('Alpha: count=1'), findsOneWidget);

        await tester.scrollUntilVisible(
          find.text('Beta Card'),
          200.0,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Beta Card'), findsOneWidget);
        expect(find.text('300\u00D7400'), findsOneWidget);

        // Switching to previewId=* also renders the grouped gallery.
        debugSetUrlFragment('embed=1&previewId=*');
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Buttons'),
          -200.0,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Buttons'), findsOneWidget);
        expect(find.text('Primary Button'), findsOneWidget);
      },
    );

    testWidgets(
      'renders empty state when no previews exist in all-previews mode',
      (WidgetTester tester) async {
        debugSetUrlFragment('embed=1');

        final controller = WidgetPreviewScaffoldController(
          dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
          previews: () => const <WidgetPreview>[],
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await tester.pumpWidget(
          TestWidgetPreviewScaffold(controller: controller),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        expect(find.text('No widget previews detected'), findsOneWidget);
        expect(
          find.text('No widget previews were detected in this project.'),
          findsOneWidget,
        );

        debugSetUrlFragment('embed=1&previewId=*');
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('No widget previews detected'), findsOneWidget);
      },
    );

    testWidgets(
      'applies brightness and width overrides across all-previews gallery cards',
      (WidgetTester tester) async {
        debugSetUrlFragment('embed=1&previewId=*&brightness=dark&width=375');

        final controller = WidgetPreviewScaffoldController(
          dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
          previews: () => <WidgetPreview>[
            _buildAlphaPreview(),
            _buildBetaPreview(),
          ],
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await tester.pumpWidget(
          TestWidgetPreviewScaffold(controller: controller),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        expect(find.textContaining('media=375x'), findsNWidgets(2));
        expect(
          find.textContaining('platform=dark theme=dark'),
          findsNWidgets(2),
        );
        expect(find.text('375\u00D7auto'), findsOneWidget);
        expect(find.text('375\u00D7400'), findsOneWidget);
      },
    );

    testWidgets(
      'scrolls wide 720px gallery cards horizontally inside narrow 400px viewport without overflow',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(400, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        debugSetUrlFragment('embed=1&previewId=*&width=720&height=300');

        final controller = WidgetPreviewScaffoldController(
          dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
          previews: () => <WidgetPreview>[_buildAlphaPreview()],
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await tester.pumpWidget(
          TestWidgetPreviewScaffold(controller: controller),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        expect(find.text('720\u00D7300'), findsOneWidget);
        expect(find.textContaining('media=720x300'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (Widget widget) =>
                widget is SingleChildScrollView &&
                widget.scrollDirection == Axis.horizontal,
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'switches fragment between all-previews gallery and single-preview mode',
      (WidgetTester tester) async {
        debugSetUrlFragment('embed=1&previewId=*');

        final controller = WidgetPreviewScaffoldController(
          dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
          previews: _buildGroupedTestPreviews,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await tester.pumpWidget(
          TestWidgetPreviewScaffold(controller: controller),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        expect(find.text('Buttons'), findsOneWidget);
        expect(find.text('Cards'), findsOneWidget);
        expect(find.text('Alpha: count=0'), findsOneWidget);

        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent('Beta Card')}',
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Buttons'), findsNothing);
        expect(find.text('Alpha: count=0'), findsNothing);
        expect(find.text('Beta: count=0'), findsOneWidget);

        debugSetUrlFragment('embed=1');
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Buttons'), findsOneWidget);
        expect(find.text('Alpha: count=0'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Beta: count=0'),
          200.0,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Beta: count=0'), findsOneWidget);
      },
    );
  });
}

List<WidgetPreview> _buildGroupedTestPreviews() => <WidgetPreview>[
  buildWidgetPreview(
    column: 1,
    functionName: 'primaryButtonPreview',
    libraryUri: 'package:my_app/buttons.dart',
    line: 10,
    packageName: 'my_app',
    previewFunction: () => const Text('Primary Button Widget'),
    scriptUri: 'file:///project/lib/buttons.dart',
    transformedPreview: const Preview(
      group: 'Buttons',
      name: 'Primary Button',
    ).transform(),
  ),
  buildWidgetPreviewError(
    column: 1,
    dependencyHasErrors: false,
    functionName: 'brokenButtonPreview',
    libraryUri: 'package:my_app/broken_button.dart',
    line: 20,
    packageName: 'my_app',
    scriptUri: 'file:///project/lib/broken_button.dart',
  ),
  buildWidgetPreview(
    column: 1,
    functionName: 'alphaPreview',
    libraryUri: 'package:my_app/alpha.dart',
    line: 30,
    packageName: 'my_app',
    previewFunction: () => const _InteractiveCardPreview(label: 'Alpha'),
    scriptUri: 'file:///project/lib/alpha.dart',
    transformedPreview: const Preview(
      group: 'Cards',
      name: 'Alpha Card',
    ).transform(),
  ),
  buildWidgetPreview(
    column: 1,
    functionName: 'betaPreview',
    libraryUri: 'package:my_app/beta.dart',
    line: 40,
    packageName: 'my_app',
    previewFunction: () => const _InteractiveCardPreview(label: 'Beta'),
    scriptUri: 'file:///project/lib/beta.dart',
    transformedPreview: const Preview(
      brightness: Brightness.dark,
      group: 'Cards',
      name: 'Beta Card',
      size: Size(300, 400),
    ).transform(),
  ),
];

class _MinWidthGuard extends SingleChildRenderObjectWidget {
  const _MinWidthGuard({required this.minWidth, super.child});

  final double minWidth;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MinWidthGuardRenderBox(minWidth);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _MinWidthGuardRenderBox renderObject,
  ) {
    renderObject.minWidth = minWidth;
  }
}

class _MinWidthGuardRenderBox extends RenderProxyBox {
  _MinWidthGuardRenderBox(this._minWidth);

  double _minWidth;
  set minWidth(double value) {
    if (_minWidth == value) {
      return;
    }
    _minWidth = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    if (constraints.maxWidth < _minWidth) {
      throw StateError(
        'Requires width >= $_minWidth, got ${constraints.maxWidth}',
      );
    }
    super.performLayout();
  }
}

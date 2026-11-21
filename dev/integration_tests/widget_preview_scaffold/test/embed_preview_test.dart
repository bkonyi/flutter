// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_rpc_2/json_rpc_2.dart' show RpcException;
import 'package:material_ui/material_ui.dart';
import 'package:widget_preview_scaffold/src/controls.dart';
import 'package:widget_preview_scaffold/src/dtd/dtd_services.dart';
import 'package:widget_preview_scaffold/src/embed_live_controls.dart';
import 'package:widget_preview_scaffold/src/embed_selection.dart';
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
      expect(
        parsed.resolveDtdProxyUri(Uri.parse('ftp://example.com/')),
        isNull,
      );

      // Defaults to relative dtd_ws in embed mode when dtdProxy is omitted.
      const defaultEmbed = EmbedPreviewParams(isEmbed: true);
      expect(
        defaultEmbed.resolveDtdProxyUri(
          Uri.parse('http://127.0.0.1:5050/?embed=1'),
        ),
        Uri.parse('ws://127.0.0.1:5050/dtd_ws'),
      );
      expect(
        defaultEmbed.resolveDtdProxyUri(
          Uri.parse('https://preview.proxy.example:8443/subpath/'),
        ),
        Uri.parse('wss://preview.proxy.example:8443/subpath/dtd_ws'),
      );
      expect(
        defaultEmbed.resolveDtdProxyUri(Uri.parse('file:///tmp/index.html')),
        isNull,
      );
      expect(
        const EmbedPreviewParams().resolveDtdProxyUri(
          Uri.parse('http://127.0.0.1:5050/'),
        ),
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

      // Zoom parameter parsing, clamping, equality, and canonical formatting.
      expect(EmbedPreviewParams.fromFragment('embed=1').zoom, isNull);
      expect(EmbedPreviewParams.fromFragment('embed=1&zoom=0').zoom, isNull);
      expect(EmbedPreviewParams.fromFragment('embed=1&zoom=-1').zoom, isNull);
      expect(EmbedPreviewParams.fromFragment('embed=1&zoom=NaN').zoom, isNull);
      expect(
        EmbedPreviewParams.fromFragment('embed=1&zoom=0.05').zoom,
        EmbedPreviewParams.kMinZoom,
      );
      expect(EmbedPreviewParams.fromFragment('embed=1&zoom=0.5').zoom, 0.5);
      expect(EmbedPreviewParams.fromFragment('embed=1&zoom=1.25').zoom, 1.25);
      expect(
        EmbedPreviewParams.fromFragment('embed=1&zoom=12').zoom,
        EmbedPreviewParams.kMaxZoom,
      );
      expect(
        const EmbedPreviewParams(isEmbed: true, zoom: 0.5),
        isNot(equals(const EmbedPreviewParams(isEmbed: true, zoom: 1.5))),
      );
      expect(
        const EmbedPreviewParams(isEmbed: true, zoom: 0.5).hashCode,
        equals(const EmbedPreviewParams(isEmbed: true, zoom: 0.5).hashCode),
      );
      expect(formatEmbedZoom(0.25), '0.25');
      expect(formatEmbedZoom(0.5), '0.5');
      expect(formatEmbedZoom(1.0), '1');
      expect(formatEmbedZoom(1.25), '1.25');
      expect(formatEmbedZoom(2.0), '2');
      expect(formatEmbedZoom(4.0), '4');
      expect(const EmbedPreviewParams(isEmbed: true).withZoom(1.5).zoom, 1.5);
      expect(
        const EmbedPreviewParams(isEmbed: true, zoom: 1.5).withZoom(1.0).zoom,
        isNull,
      );
      expect(
        buildUpdatedZoomFragment('embed=1&previewId=*', 1.5),
        'embed=1&previewId=%2A&zoom=1.5',
      );
      expect(
        buildUpdatedZoomFragment('embed=1&previewId=*&zoom=1.5', 1.0),
        'embed=1&previewId=%2A',
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

    testWidgets(
      'scales single preview across 50% and 200% without changing logical MediaQuery, preserves button hit-testing and TextField +/-/0 input, and supports Ctrl+wheel/keyboard zoom',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent(_kAlphaId)}'
          '&width=375&height=400&zoom=0.5',
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

        // Logical MediaQuery.size, textScale, and windowConstraints remain 375x400,
        // while visual ScaledPreviewLayout box scales to 187.5x200 centered in 800x600.
        expect(find.textContaining('media=375x400'), findsOneWidget);
        expect(
          find.textContaining('scale=1.0 constraints=375x400'),
          findsOneWidget,
        );
        expect(
          tester.getSize(find.byType(ScaledPreviewLayout)),
          const Size(187.5, 200.0),
        );
        expect(
          tester.getCenter(find.byType(ScaledPreviewLayout)),
          const Offset(400.0, 300.0),
        );

        // Button hit-testing works accurately at 50% zoom.
        await tester.tap(find.text('Increment'));
        await tester.pump();
        expect(find.text('Alpha: count=1'), findsOneWidget);

        // Oversized 1280x800 preview zoomed out to 50% (640x400) fits centered
        // inside 800x600 without overflow while keeping logical 1280x800 layout.
        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent(_kAlphaId)}'
          '&width=1280&height=800&zoom=0.5',
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('media=1280x800'), findsOneWidget);
        expect(find.textContaining('constraints=1280x800'), findsOneWidget);
        expect(
          tester.getSize(find.byType(ScaledPreviewLayout)),
          const Size(640.0, 400.0),
        );

        // Zooming to 200% on 375x400 (750x800 > 800x600 vertically) scrolls cleanly
        // without overflow and preserves button hit-testing.
        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent(_kAlphaId)}'
          '&width=375&height=400&zoom=2',
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('media=375x400'), findsOneWidget);
        expect(find.textContaining('constraints=375x400'), findsOneWidget);
        expect(
          tester.getSize(find.byType(ScaledPreviewLayout)),
          const Size(750.0, 800.0),
        );
        await tester.tap(find.text('Increment'));
        await tester.pump();
        expect(find.text('Alpha: count=2'), findsOneWidget);

        // Updating fragment from zoom=1.5 to omitted (null) resets zoom to 100%.
        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent(_kAlphaId)}'
          '&width=375&height=400&zoom=1.5',
        );
        await tester.pump();
        expect(
          tester.getSize(find.byType(ScaledPreviewLayout)),
          const Size(562.5, 600.0),
        );
        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent(_kAlphaId)}'
          '&width=375&height=400',
        );
        await tester.pump();
        expect(
          tester.getSize(find.byType(ScaledPreviewLayout)),
          const Size(375.0, 400.0),
        );

        // Keyboard shortcuts (+/=, -, 0) and Ctrl+wheel adjust zoom when TextField
        // is not focused.
        await tester.sendKeyEvent(LogicalKeyboardKey.equal);
        await tester.pump();
        expect(
          tester
              .widget<ScaledPreviewLayout>(find.byType(ScaledPreviewLayout))
              .scale,
          1.25,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.minus);
        await tester.sendKeyEvent(LogicalKeyboardKey.minus);
        await tester.pump();
        expect(
          tester
              .widget<ScaledPreviewLayout>(find.byType(ScaledPreviewLayout))
              .scale,
          0.75,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
        await tester.pump();
        expect(
          tester
              .widget<ScaledPreviewLayout>(find.byType(ScaledPreviewLayout))
              .scale,
          1.0,
        );

        final pointer = TestPointer(7, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(
          pointer.hover(tester.getCenter(find.byType(ScaledPreviewLayout))),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -20)));
        await tester.pump();
        expect(
          tester
              .widget<ScaledPreviewLayout>(find.byType(ScaledPreviewLayout))
              .scale,
          1.25,
        );
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 20)));
        await tester.pump();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        expect(
          tester
              .widget<ScaledPreviewLayout>(find.byType(ScaledPreviewLayout))
              .scale,
          1.0,
        );

        // Focusing TextField and typing '0', '+', '-' does NOT hijack input or zoom.
        await tester.tap(find.byType(TextField));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.equal);
        await tester.sendKeyEvent(LogicalKeyboardKey.minus);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
        await tester.enterText(find.byType(TextField), '0+-');
        await tester.pump();
        expect(find.text('0+-'), findsOneWidget);
        expect(
          tester
              .widget<ScaledPreviewLayout>(find.byType(ScaledPreviewLayout))
              .scale,
          1.0,
        );

        // Responsive mode (no explicit width/height) keeps finite maxWidth on bare
        // TextField when zoomed to 200%.
        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent(_kAlphaId)}&zoom=2',
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(ScaledPreviewLayout)).width, 1600.0);
      },
    );

    testWidgets(
      'resets back to 100% when parent clears zoom hash after local iframe zoom and does not steal unmodified keys from focused preview controls',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final autofocusFieldNode = FocusNode(debugLabel: 'autofocus-textfield');
        addTearDown(autofocusFieldNode.dispose);
        final childFocusNode = FocusNode(debugLabel: 'custom-preview-control');
        addTearDown(childFocusNode.dispose);
        final receivedKeys = <LogicalKeyboardKey>[];

        const baseFragment = 'embed=1&previewId=Focusable&width=300&height=200';
        debugSetUrlFragment(baseFragment);

        final controller = WidgetPreviewScaffoldController(
          dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
          previews: () => <WidgetPreview>[
            buildWidgetPreview(
              column: 1,
              functionName: 'focusablePreview',
              libraryUri: 'package:my_app/focusable.dart',
              line: 10,
              packageName: 'my_app',
              previewFunction: () => Focus(
                focusNode: childFocusNode,
                onKeyEvent: (FocusNode _, KeyEvent event) {
                  if (event is KeyDownEvent) {
                    receivedKeys.add(event.logicalKey);
                  }
                  return KeyEventResult.ignored;
                },
                child: const SizedBox(width: 100, height: 100),
              ),
              scriptUri: 'file:///project/lib/focusable.dart',
              transformedPreview: const Preview(name: 'Focusable').transform(),
            ),
            buildWidgetPreview(
              column: 1,
              functionName: 'autofocusPreview',
              libraryUri: 'package:my_app/autofocus.dart',
              line: 20,
              packageName: 'my_app',
              previewFunction: () => Material(
                child: TextField(
                  autofocus: true,
                  focusNode: autofocusFieldNode,
                ),
              ),
              scriptUri: 'file:///project/lib/autofocus.dart',
              transformedPreview: const Preview(name: 'Autofocus').transform(),
            ),
          ],
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await tester.pumpWidget(
          TestWidgetPreviewScaffold(controller: controller),
        );
        await tester.pump();

        // 1. Start at zoom: null (100%), zoom locally via '+' twice to 150%.
        expect(EmbedPreviewParams.fromFragment(getUrlFragment()).zoom, isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.equal);
        await tester.sendKeyEvent(LogicalKeyboardKey.equal);
        await tester.pump();
        expect(
          tester
              .widget<ScaledPreviewLayout>(find.byType(ScaledPreviewLayout))
              .scale,
          1.5,
        );
        expect(EmbedPreviewParams.fromFragment(getUrlFragment()).zoom, 1.5);

        // 2. Outer /live toolbar clicks Reset (100%), setting hash without zoom:
        // single-source-of-truth _embedParams transitions 1.5 -> null and resets!
        debugSetUrlFragment(baseFragment);
        await tester.pump();
        expect(
          tester
              .widget<ScaledPreviewLayout>(find.byType(ScaledPreviewLayout))
              .scale,
          1.0,
        );

        // 3. When a preview descendant holds focus, unmodified -/=/0 are NOT
        // stolen, while Ctrl + '=' / Ctrl + '0' still adjusts zoom.
        childFocusNode.requestFocus();
        await tester.pump();
        expect(childFocusNode.hasPrimaryFocus, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.equal);
        await tester.sendKeyEvent(LogicalKeyboardKey.minus);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
        await tester.pump();
        expect(
          receivedKeys,
          equals(<LogicalKeyboardKey>[
            LogicalKeyboardKey.equal,
            LogicalKeyboardKey.minus,
            LogicalKeyboardKey.digit0,
          ]),
        );
        expect(
          tester
              .widget<ScaledPreviewLayout>(find.byType(ScaledPreviewLayout))
              .scale,
          1.0,
        );

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.equal);
        await tester.pump();
        expect(
          tester
              .widget<ScaledPreviewLayout>(find.byType(ScaledPreviewLayout))
              .scale,
          1.25,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(
          tester
              .widget<ScaledPreviewLayout>(find.byType(ScaledPreviewLayout))
              .scale,
          1.0,
        );

        // 4. A preview with TextField(autofocus: true) retains primary focus on
        // mount without being preempted by the embed keyboard zoom listener.
        debugSetUrlFragment('embed=1&previewId=Autofocus&width=300&height=200');
        await tester.pump();
        expect(autofocusFieldNode.hasPrimaryFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.equal);
        await tester.pump();
        expect(
          tester
              .widget<ScaledPreviewLayout>(find.byType(ScaledPreviewLayout))
              .scale,
          1.0,
        );
      },
    );

    testWidgets(
      'scales all-previews gallery cards at 50% and 200% without nested vertical scroll views',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(450, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        debugSetUrlFragment('embed=1&previewId=*&zoom=0.5');

        final controller = WidgetPreviewScaffoldController(
          dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
          previews: () => <WidgetPreview>[
            _buildBetaPreview(),
            _buildAlphaPreview(),
          ],
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await tester.pumpWidget(
          TestWidgetPreviewScaffold(controller: controller),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        // Beta Card has @Preview(size: Size(300, 400)) -> logical 300x400 preserved,
        // visual ScaledPreviewLayout box shrinks to 150x200 at 50% zoom.
        expect(find.textContaining('media=300x400'), findsOneWidget);
        expect(
          tester.getSize(find.byType(ScaledPreviewLayout).first),
          const Size(150.0, 200.0),
        );
        // Gallery cards use horizontal SingleChildScrollView only (no nested vertical
        // SingleChildScrollView fighting the outer ListView).
        expect(
          find.byWidgetPredicate(
            (Widget widget) =>
                widget is SingleChildScrollView &&
                widget.scrollDirection == Axis.vertical,
          ),
          findsNothing,
        );

        // Zooming gallery to 200% grows Beta Card visual box to 600x800 and scrolls
        // horizontally inside the 450px viewport without overflow.
        debugSetUrlFragment('embed=1&previewId=*&zoom=2');
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(ScaledPreviewLayout).first),
          const Size(600.0, 800.0),
        );

        // Omitting zoom resets gallery cards back to 100% (300x400).
        debugSetUrlFragment('embed=1&previewId=*');
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(ScaledPreviewLayout).first),
          const Size(300.0, 400.0),
        );
      },
    );
  });

  group('/live native controls', () {
    test(
      'resolveLiveRootUri and EmbedPreviewParams handle /live and brightness',
      () {
        expect(
          resolveLiveRootUri(
            Uri.parse('http://localhost:8080/live?root=/app#foo'),
          ).resolve('dtd_ws').toString(),
          'http://localhost:8080/dtd_ws',
        );
        expect(
          resolveLiveRootUri(
            Uri.parse('http://localhost:8080/sub/live/'),
          ).resolve('__api/sync').toString(),
          'http://localhost:8080/sub/__api/sync',
        );
        expect(
          EmbedPreviewParams.isLiveUriPath(
            Uri.parse('http://localhost:8080/live'),
          ),
          isTrue,
        );
        expect(
          EmbedPreviewParams.isLiveUriPath(
            Uri.parse('http://localhost:8080/sub/live/'),
          ),
          isTrue,
        );
        expect(
          EmbedPreviewParams.isLiveUriPath(Uri.parse('http://localhost:8080/')),
          isFalse,
        );

        final EmbedPreviewParams fromLivePath = EmbedPreviewParams.fromFragment(
          '',
          baseUri: Uri.parse('http://localhost:8080/live?brightness=dark'),
        );
        expect(fromLivePath.showControls, isTrue);
        expect(fromLivePath.isEmbed, isTrue);
        expect(fromLivePath.brightness, Brightness.dark);

        final EmbedPreviewParams chromeless = EmbedPreviewParams.fromFragment(
          'embed=1',
          baseUri: Uri.parse('http://localhost:8080/'),
        );
        expect(chromeless.showControls, isFalse);
        expect(chromeless.isEmbed, isTrue);
      },
    );

    testWidgets(
      'chromeless #embed=1 hides live controls while #live=1 renders top bar, reload error banner, and selection bar',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(420, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent(_kAlphaId)}',
          baseUri: Uri.parse('http://localhost:8080/'),
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
        expect(find.byType(EmbedLiveTopBar), findsNothing);
        expect(find.byType(EmbedLiveSelectionBar), findsNothing);

        // Switch to /live without a host selection handler.
        debugSetTriggerSyncHandler(
          () async => (
            compileSuccess: false,
            errorMessage: 'Syntax error in main.dart',
          ),
        );
        debugSetUrlFragment(
          'previewId=${Uri.encodeQueryComponent(_kAlphaId)}',
          baseUri: Uri.parse('http://localhost:8080/live'),
        );
        await tester.pump();
        await tester.pump();

        expect(find.byType(EmbedLiveTopBar), findsOneWidget);
        expect(find.byType(EmbedLiveSelectionBar), findsOneWidget);
        expect(
          find.byKey(const Key('embed-live-preview-selector')),
          findsOneWidget,
        );

        // Toggle brightness -> updates params to dark.
        await tester.tap(find.byKey(const Key('embed-live-brightness-toggle')));
        await tester.pump();
        expect(getUrlFragment(), contains('brightness=dark'));

        // Select 375px width preset, then Responsive to clear.
        await tester.tap(find.byKey(const Key('embed-live-width-375')));
        await tester.pump();
        expect(getUrlFragment(), contains('width=375'));

        await tester.tap(find.byKey(const Key('embed-live-width-responsive')));
        await tester.pump();
        expect(getUrlFragment(), isNot(contains('width=')));

        // Zoom + and - and reset.
        await tester.tap(find.byKey(const Key('embed-live-zoom-in')));
        await tester.pump();
        expect(getUrlFragment(), contains('zoom=1.25'));
        await tester.tap(find.byKey(const Key('embed-live-zoom-reset')));
        await tester.pump();
        expect(getUrlFragment(), isNot(contains('zoom=')));

        // Reload shows error banner on compile failure, and dismiss hides it.
        await tester.tap(find.byKey(const Key('embed-live-sync-button')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('embed-live-error-banner')),
          findsOneWidget,
        );
        expect(find.text('Syntax error in main.dart'), findsOneWidget);
        await tester.tap(find.byKey(const Key('embed-live-error-dismiss')));
        await tester.pump();
        expect(find.byKey(const Key('embed-live-error-banner')), findsNothing);

        // Toggle select mode and create a selection.
        await tester.tap(find.byKey(const Key('embed-live-select-toggle')));
        await tester.pump();
        final Offset surfaceTopLeft = tester.getTopLeft(
          find.byType(EmbedSelectablePreviewSurface).first,
        );
        final TestGesture gesture = await tester.startGesture(
          surfaceTopLeft + const Offset(10, 10),
        );
        await gesture.moveTo(surfaceTopLeft + const Offset(60, 40));
        await gesture.up();
        await tester.pump();

        expect(find.byKey(const Key('embed-live-chip-sel-1')), findsOneWidget);
        expect(find.byKey(const Key('embed-live-copy-button')), findsOneWidget);
        expect(
          find.byKey(const Key('embed-live-clear-button')),
          findsOneWidget,
        );
        // canSendLiveSelection is false so Send button is hidden.
        expect(find.byKey(const Key('embed-live-send-button')), findsNothing);

        // Clear removes selection bar content.
        await tester.tap(find.byKey(const Key('embed-live-clear-button')));
        await tester.pump();
        expect(find.byKey(const Key('embed-live-chip-sel-1')), findsNothing);
      },
    );

    testWidgets(
      'canSendLiveSelection disables Send when note is empty, sends on submit, and ignores +-0 zoom keys in note TextField',
      (WidgetTester tester) async {
        String? sentMessage;
        List<Map<String, Object?>>? sentSelections;
        debugSetSendSelectionHandler(({
          required String message,
          required List<Map<String, Object?>> selections,
          String? brightness,
          String? previewId,
          String? previewName,
          String? textScale,
          String? viewport,
          String? zoom,
        }) async {
          sentMessage = message;
          sentSelections = selections;
        });

        debugSetUrlFragment(
          'live=1&previewId=${Uri.encodeQueryComponent(_kAlphaId)}&select=1',
          baseUri: Uri.parse('http://localhost:8080/'),
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
        await tester.pumpAndSettle();

        final Offset surfaceTopLeft = tester.getTopLeft(
          find.byType(EmbedSelectablePreviewSurface).first,
        );
        final TestGesture gesture = await tester.startGesture(
          surfaceTopLeft + const Offset(10, 10),
        );
        await gesture.moveTo(surfaceTopLeft + const Offset(50, 35));
        await gesture.up();
        await tester.pump();

        final Finder sendFinder = find.byKey(
          const Key('embed-live-send-button'),
        );
        expect(sendFinder, findsOneWidget);
        expect(tester.widget<FilledButton>(sendFinder).onPressed, isNull);

        // Typing +-0 in the note TextField must not trigger zoom.
        final Finder noteFinder = find.byKey(
          const Key('embed-live-note-input'),
        );
        await tester.enterText(noteFinder, 'Fix +-0 padding');
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.equal);
        await tester.sendKeyEvent(LogicalKeyboardKey.minus);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
        await tester.pump();
        expect(getUrlFragment(), isNot(contains('zoom=')));

        expect(tester.widget<FilledButton>(sendFinder).onPressed, isNotNull);
        await tester.tap(sendFinder);
        await tester.pumpAndSettle();

        expect(sentMessage, 'Fix +-0 padding');
        expect(sentSelections, hasLength(1));
        expect(find.byKey(const Key('embed-live-chip-sel-1')), findsNothing);
      },
    );

    testWidgets('clears query-string overrides without snap-back', (
      WidgetTester tester,
    ) async {
      debugSetUrlFragment(
        'select=1',
        baseUri: Uri.parse(
          'http://localhost:8080/live?token=host123&previewId=${Uri.encodeQueryComponent(_kAlphaId)}&width=375',
        ),
      );
      final controller = WidgetPreviewScaffoldController(
        dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
        previews: () => _buildTestPreviews().take(2).toList(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: controller),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('embed-live-width-responsive')));
      await tester.pump();
      expect(getBaseUri().queryParameters['width'], isNull);
      expect(getBaseUri().queryParameters['token'], 'host123');

      await tester.tap(find.byKey(const Key('embed-live-preview-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('All Previews (').last);
      await tester.pumpAndSettle();
      expect(getBaseUri().queryParameters['previewId'], isNull);
      expect(getBaseUri().queryParameters['token'], 'host123');
      expect(getUrlFragment(), isNot(contains('previewId=')));
    });

    testWidgets(
      'surfaces sendSelection errors and recovers from compile error on Reload',
      (WidgetTester tester) async {
        var shouldFailSync = true;
        debugSetTriggerSyncHandler(() async {
          if (shouldFailSync) {
            return (compileSuccess: false, errorMessage: 'Undefined name foo');
          }
          return (compileSuccess: true, errorMessage: null);
        });
        debugSetSendSelectionHandler(({
          required String message,
          required List<Map<String, Object?>> selections,
          String? brightness,
          String? previewId,
          String? previewName,
          String? textScale,
          String? viewport,
          String? zoom,
        }) async {
          throw StateError('Host bridge unavailable');
        });

        debugSetUrlFragment(
          'live=1&previewId=${Uri.encodeQueryComponent(_kAlphaId)}&select=1',
          baseUri: Uri.parse('http://localhost:8080/'),
        );
        final controller = WidgetPreviewScaffoldController(
          dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
          previews: () => _buildTestPreviews().take(2).toList(),
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await tester.pumpWidget(
          TestWidgetPreviewScaffold(controller: controller),
        );
        await tester.pumpAndSettle();

        final Offset surfaceTopLeft = tester.getTopLeft(
          find.byType(EmbedSelectablePreviewSurface).first,
        );
        final TestGesture gesture = await tester.startGesture(
          surfaceTopLeft + const Offset(10, 10),
        );
        await gesture.moveTo(surfaceTopLeft + const Offset(50, 35));
        await gesture.up();
        await tester.pump();
        expect(find.byKey(const Key('embed-live-chip-sel-1')), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('embed-live-note-input')),
          'Check this',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('embed-live-send-button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('embed-live-send-error')), findsOneWidget);
        expect(find.textContaining('Host bridge unavailable'), findsOneWidget);

        await tester.tap(find.byKey(const Key('embed-live-sync-button')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('embed-live-error-banner')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('embed-live-chip-sel-1')), findsOneWidget);

        shouldFailSync = false;
        await tester.tap(find.byKey(const Key('embed-live-sync-button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('embed-live-error-banner')), findsNothing);
        expect(find.byKey(const Key('embed-live-chip-sel-1')), findsNothing);
      },
    );

    testWidgets('dropdown matches shorthand previewId', (
      WidgetTester tester,
    ) async {
      final WidgetPreview interactivePreview = buildWidgetPreview(
        column: 1,
        functionName: 'shorthandButton',
        libraryUri: 'package:my_app/button.dart',
        line: 10,
        packageName: 'my_app',
        previewFunction: () => const Text('Shorthand'),
        scriptUri: 'file:///project/lib/button.dart',
        transformedPreview: const Preview(name: 'ShorthandBtn').transform(),
      );

      debugSetUrlFragment(
        'live=1&previewId=ShorthandBtn',
        baseUri: Uri.parse('http://localhost:8080/'),
      );
      final controller = WidgetPreviewScaffoldController(
        dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
        previews: () => <WidgetPreview>[
          interactivePreview,
          ..._buildTestPreviews(),
        ],
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: controller),
      );
      await tester.pumpAndSettle();

      final DropdownButton<String> dropdown = tester.widget(
        find.byKey(const Key('embed-live-preview-selector')),
      );
      expect(dropdown.value, interactivePreview.id);
    });

    testWidgets(
      'clears _layoutError when brightness or textScale updates on the same preview',
      (WidgetTester tester) async {
        final WidgetPreview guardPreview = buildWidgetPreview(
          column: 1,
          functionName: 'guardPreview',
          libraryUri: 'package:my_app/guard.dart',
          line: 10,
          packageName: 'my_app',
          previewFunction: () => Builder(
            builder: (BuildContext context) {
              if (MediaQuery.textScalerOf(context).scale(1.0) > 1.5 ||
                  Theme.of(context).brightness == Brightness.dark) {
                return const _MinWidthGuard(minWidth: 9999, child: SizedBox());
              }
              return const Text('Recovered Preview');
            },
          ),
          scriptUri: 'file:///project/lib/guard.dart',
          transformedPreview: const Preview(name: 'Guard').transform(),
        );

        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent(guardPreview.id)}'
          '&brightness=dark&textScale=2.0',
        );
        final controller = WidgetPreviewScaffoldController(
          dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
          previews: () => <WidgetPreview>[guardPreview],
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await tester.pumpWidget(
          TestWidgetPreviewScaffold(controller: controller),
        );
        expect(tester.takeException(), isA<StateError>());
        await tester.pump();
        expect(find.byType(WidgetPreviewErrorWidget), findsOneWidget);

        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent(guardPreview.id)}'
          '&brightness=light&textScale=1.0',
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Recovered Preview'), findsOneWidget);
        expect(find.byType(WidgetPreviewErrorWidget), findsNothing);
      },
    );

    testWidgets('/live 1280px preset sets width=1280 without height', (
      WidgetTester tester,
    ) async {
      debugSetUrlFragment(
        'live=1&previewId=${Uri.encodeQueryComponent('package:my_app/alpha.dart::alphaPreview')}',
      );
      final controller = WidgetPreviewScaffoldController(
        dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
        previews: _buildGroupedTestPreviews,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: controller),
      );

      await tester.tap(find.byKey(const Key('embed-live-width-1280')));
      await tester.pump();
      expect(getUrlFragment(), contains('width=1280'));
      expect(getUrlFragment(), isNot(contains('height=')));
    });

    testWidgets('/live Light + Dark split renders Light and Dark panes', (
      WidgetTester tester,
    ) async {
      debugSetUrlFragment(
        'live=1&previewId=${Uri.encodeQueryComponent('package:my_app/alpha.dart::alphaPreview')}',
      );
      final controller = WidgetPreviewScaffoldController(
        dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
        previews: _buildGroupedTestPreviews,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: controller),
      );

      await tester.tap(find.byKey(const Key('embed-live-split-brightness')));
      await tester.pump();

      final Finder lightPane = find.byKey(const Key('embed-split-light'));
      final Finder darkPane = find.byKey(const Key('embed-split-dark'));
      expect(lightPane, findsOneWidget);
      expect(darkPane, findsOneWidget);
      final WidgetPreviewEnvironment lightEnv = tester.widget(
        find.descendant(
          of: lightPane,
          matching: find.byType(WidgetPreviewEnvironment),
        ),
      );
      final WidgetPreviewEnvironment darkEnv = tester.widget(
        find.descendant(
          of: darkPane,
          matching: find.byType(WidgetPreviewEnvironment),
        ),
      );
      expect(lightEnv.brightness, Brightness.light);
      expect(darkEnv.brightness, Brightness.dark);
    });

    testWidgets('/live Bounds toggle enables bounds overlay', (
      WidgetTester tester,
    ) async {
      debugSetUrlFragment(
        'live=1&previewId=${Uri.encodeQueryComponent('package:my_app/alpha.dart::alphaPreview')}',
      );
      final controller = WidgetPreviewScaffoldController(
        dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
        previews: _buildGroupedTestPreviews,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: controller),
      );

      await tester.tap(find.byKey(const Key('embed-live-bounds-toggle')));
      await tester.pump();
      expect(find.byKey(const Key('embed-bounds-overlay')), findsOneWidget);
    });

    testWidgets('/live copy previewId button copies canonical ID', (
      WidgetTester tester,
    ) async {
      String? copiedId;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            final Map<Object?, Object?> args =
                call.arguments! as Map<Object?, Object?>;
            copiedId = args['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      debugSetUrlFragment(
        'live=1&previewId=${Uri.encodeQueryComponent('package:my_app/alpha.dart::alphaPreview')}',
      );
      final controller = WidgetPreviewScaffoldController(
        dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
        previews: _buildGroupedTestPreviews,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: controller),
      );

      await tester.tap(find.byKey(const Key('embed-live-copy-preview-id')));
      await tester.pump();
      expect(copiedId, 'package:my_app/alpha.dart::alphaPreview');
    });
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

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
import 'package:widget_preview_scaffold/src/theme/ide_theme.dart';
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

WidgetPreview _buildAlphaPreview({String group = 'Default'}) => makeTestPreview(
  fileStem: 'alpha',
  functionName: 'alphaPreview',
  group: group,
  name: 'Alpha Card',
  previewFunction: () => const _InteractiveCardPreview(label: 'Alpha'),
  theme: _brightnessAwareTheme,
);

WidgetPreview _buildBetaPreview({String group = 'Default'}) => makeTestPreview(
  brightness: Brightness.dark,
  fileStem: 'beta',
  functionName: 'betaPreview',
  group: group,
  line: 15,
  name: 'Beta Card',
  previewFunction: () => const _InteractiveCardPreview(label: 'Beta'),
  size: const Size(300, 400),
);

WidgetPreview _buildExpandingPreview() => makeTestPreview(
  fileStem: 'expanding',
  functionName: 'expandingPreview',
  line: 20,
  name: 'Expanding',
  previewFunction: () => const SizedBox.expand(
    child: ColoredBox(
      color: Color(0xFF228844),
      child: Center(child: Text('Expanded Preview')),
    ),
  ),
);

List<WidgetPreview> _buildTestPreviews() => <WidgetPreview>[
  _buildAlphaPreview(),
  _buildBetaPreview(),
  _buildExpandingPreview(),
  makeTestPreview(
    fileStem: 'dup_a',
    functionName: 'dupPreview',
    line: 30,
    name: 'Shared Name',
    previewFunction: () => const Text('Dup A'),
  ),
  makeTestPreview(
    fileStem: 'dup_b',
    functionName: 'dupPreview',
    line: 40,
    name: 'Shared Name',
    previewFunction: () => const Text('Dup B'),
  ),
  makeTestErrorPreview(
    fileStem: 'broken',
    functionName: 'brokenPreview',
    line: 50,
  ),
];

List<WidgetPreview> _buildGroupedTestPreviews() => <WidgetPreview>[
  makeTestPreview(
    fileStem: 'buttons',
    functionName: 'primaryButtonPreview',
    group: 'Buttons',
    name: 'Primary Button',
    previewFunction: () => const Text('Primary Button Widget'),
  ),
  makeTestErrorPreview(
    fileStem: 'broken_button',
    functionName: 'brokenButtonPreview',
    line: 20,
  ),
  _buildAlphaPreview(group: 'Cards'),
  _buildBetaPreview(group: 'Cards'),
];

List<String> _mockNavigationCalls() {
  final navigationCalls = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.navigation, (
        MethodCall call,
      ) async {
        navigationCalls.add(call.method);
        return null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.navigation, null),
  );
  return navigationCalls;
}

double _currentScaledLayoutZoom(WidgetTester tester) =>
    tester.widget<ScaledPreviewLayout>(find.byType(ScaledPreviewLayout)).scale;

void main() {
  tearDown(debugResetUrlTestState);

  group('$EmbedPreviewParams', () {
    test(
      'strips leading /, #, ? from fragments, resolves DTD proxy URIs, and clamps zoom',
      () {
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

        for (final (EmbedPreviewParams p, String base, String? expected)
            in <(EmbedPreviewParams, String, String?)>[
              (
                parsed,
                'https://preview.proxy.example:8443/live',
                'wss://preview.proxy.example:8443/dtd_ws',
              ),
              (parsed, 'http://127.0.0.1:5050/', 'ws://127.0.0.1:5050/dtd_ws'),
              (parsed, 'file:///tmp/index.html', null),
              (parsed, 'ftp://example.com/', null),
              (
                const EmbedPreviewParams(isEmbed: true),
                'http://127.0.0.1:5050/?embed=1',
                'ws://127.0.0.1:5050/dtd_ws',
              ),
              (
                const EmbedPreviewParams(isEmbed: true),
                'https://preview.proxy.example:8443/subpath/',
                'wss://preview.proxy.example:8443/subpath/dtd_ws',
              ),
              (const EmbedPreviewParams(), 'http://127.0.0.1:5050/', null),
            ]) {
          expect(
            p.resolveDtdProxyUri(Uri.parse(base)),
            expected == null ? null : Uri.parse(expected),
          );
        }

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

        for (final (String frag, bool expectedAll) in const <(String, bool)>[
          ('embed=1', true),
          ('embed=1&previewId=', true),
          ('embed=1&previewId=*', true),
          ('embed=1&previewId=alpha', false),
        ]) {
          expect(
            EmbedPreviewParams.fromFragment(frag).isAllPreviews,
            expectedAll,
          );
        }

        for (final (String frag, double? expectedZoom)
            in const <(String, double?)>[
              ('embed=1', null),
              ('embed=1&zoom=0', null),
              ('embed=1&zoom=-1', null),
              ('embed=1&zoom=NaN', null),
              ('embed=1&zoom=0.05', EmbedPreviewParams.kMinZoom),
              ('embed=1&zoom=0.5', 0.5),
              ('embed=1&zoom=1.25', 1.25),
              ('embed=1&zoom=12', EmbedPreviewParams.kMaxZoom),
            ]) {
          expect(EmbedPreviewParams.fromFragment(frag).zoom, expectedZoom);
        }

        expect(
          const EmbedPreviewParams(isEmbed: true, zoom: 0.5),
          isNot(equals(const EmbedPreviewParams(isEmbed: true, zoom: 1.5))),
        );
        expect(
          const EmbedPreviewParams(isEmbed: true, zoom: 0.5).hashCode,
          equals(const EmbedPreviewParams(isEmbed: true, zoom: 0.5).hashCode),
        );
        for (final (double val, String str) in const <(double, String)>[
          (0.25, '0.25'),
          (0.5, '0.5'),
          (1.0, '1'),
          (1.25, '1.25'),
          (2.0, '2'),
          (4.0, '4'),
        ]) {
          expect(formatEmbedZoom(val), str);
        }
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
      },
    );
  });

  group('Chromeless embed mode', () {
    testWidgets(
      'renders single preview interactively without chrome, connects readOnly, and switches in-memory on hash changes',
      (WidgetTester tester) async {
        final fakeDtd = FakeWidgetPreviewScaffoldDtdServices();
        await pumpTestScaffold(
          tester,
          dtdServices: fakeDtd,
          fragment:
              'embed=1&previewId=${Uri.encodeQueryComponent(_kAlphaId)}'
              '&brightness=light&width=375&height=667&textScale=1.0',
          previews: _buildTestPreviews,
        );
        expect(fakeDtd.lastConnectReadOnly, isTrue);
        expect(tester.takeException(), isNull);

        for (final Type hiddenType in const <Type>[
          PreviewSearchControls,
          LayoutTypeSelector,
          WidgetPreviewerRestartButton,
          WidgetInspectorToggle,
          ZoomControls,
          BrightnessToggleButton,
          SoftRestartButton,
        ]) {
          expect(find.byType(hiddenType), findsNothing);
        }

        expect(find.byType(Scaffold), findsOneWidget);
        expect(find.byType(WidgetPreviewerWindowConstraints), findsOneWidget);
        expect(find.byType(WidgetPreviewTheming), findsOneWidget);
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

        await tester.tap(find.text('Increment'));
        await tester.pump();
        expect(find.text('Alpha: count=1'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'Hello live');
        await tester.pump();
        expect(find.text('Hello live'), findsOneWidget);

        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent(_kAlphaId)}'
          '&brightness=dark&width=768&height=1024&textScale=1.6',
        );
        await tester.pump();
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

        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent('Beta Card')}',
        );
        await tester.pump();
        expect(find.text('Alpha: count=1'), findsNothing);
        expect(find.text('Beta: count=0'), findsOneWidget);
        expect(
          find.text(
            'media=300x400 platform=dark theme=dark scale=1.0 '
            'constraints=300x400 scrollObserver=true',
          ),
          findsOneWidget,
        );

        debugSetUrlFragment('embed=1&previewId=Expanding');
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Expanded Preview'), findsOneWidget);
        expect(debugReloadCount, 0);

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
        await pumpTestScaffold(
          tester,
          fragment: 'embed=1&previewId=MissingCard',
          previews: () => <WidgetPreview>[
            ..._buildTestPreviews(),
            makeTestPreview(
              fileStem: 'throwing',
              functionName: 'throwingPreview',
              line: 60,
              name: 'Throwing',
              previewFunction: () => throw StateError('boom during build'),
            ),
          ],
        );

        expect(find.text('Preview not found'), findsOneWidget);
        expect(find.textContaining('MissingCard'), findsOneWidget);
        expect(find.textContaining(_kAlphaId), findsOneWidget);

        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent('Shared Name')}',
        );
        await tester.pump();
        expect(find.text('Ambiguous preview name'), findsOneWidget);
        expect(find.textContaining(_kDupOneId), findsOneWidget);
        expect(find.textContaining(_kDupTwoId), findsOneWidget);

        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent(_kBrokenId)}',
        );
        await tester.pump();
        expect(find.text('Preview has errors'), findsOneWidget);
        expect(
          find.textContaining('package:my_app/broken.dart has errors!'),
          findsOneWidget,
        );

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
        await pumpTestScaffold(
          tester,
          fragment: 'embed=1&previewId=MinWidth&width=200&height=300',
          viewSize: const Size(240, 400),
          previews: () => <WidgetPreview>[
            makeTestPreview(
              fileStem: 'min_width',
              functionName: 'minWidthPreview',
              name: 'MinWidth',
              previewFunction: () => const _MinWidthGuard(
                minWidth: 300.0,
                child: Text('Width OK'),
              ),
            ),
          ],
        );
        expect(tester.takeException(), isA<StateError>());
        await tester.pump();
        expect(find.byType(WidgetPreviewErrorWidget), findsOneWidget);
        expect(find.textContaining('Requires width >= 300.0'), findsOneWidget);

        debugSetUrlFragment('embed=1&previewId=MinWidth&width=350&height=300');
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(WidgetPreviewErrorWidget), findsNothing);
        expect(find.text('Width OK'), findsOneWidget);

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

        await pumpTestScaffold(
          tester,
          fragment: 'embed=1&previewId=${Uri.encodeQueryComponent(_kAlphaId)}',
          ideTheme: const IdeTheme(isDarkMode: true),
          previews: _buildTestPreviews,
        );
        expect(
          Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
          Brightness.dark,
        );
        expect(find.textContaining('platform=dark theme=dark'), findsOneWidget);
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
        final WidgetPreviewScaffoldController controller =
            await pumpTestScaffold(
              tester,
              fragment: '',
              previews: _buildTestPreviews,
              stageHostTimeout: const Duration(milliseconds: 20),
            );
        expect(find.byType(PreviewSearchControls), findsOneWidget);

        debugSetUrlFragment('embed=1&previewId=Expanding');
        await tester.pump();
        expect(find.text('Expanded Preview'), findsOneWidget);
        expect(find.byType(PreviewSearchControls), findsNothing);

        final Future<void> assertion = expectLater(
          controller.capturePreview(
            const PreviewCaptureRequest(previewId: 'Expanding'),
          ),
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
      'handles browser pushRouteInformation fragment updates and standard-to-embed transition with multi-entry history',
      (WidgetTester tester) async {
        final List<String> navigationCalls = _mockNavigationCalls();
        await pumpTestScaffold(
          tester,
          fragment:
              'embed=1&previewId=${Uri.encodeQueryComponent(_kAlphaId)}&brightness=dark',
          previews: _buildTestPreviews,
        );
        expect(find.text('Alpha: count=0'), findsOneWidget);
        expect(navigationCalls, contains('selectMultiEntryHistory'));
        expect(navigationCalls, isNot(contains('selectSingleEntryHistory')));

        expect(
          await WidgetsBinding.instance.handlePushRoute(
            'embed=1&previewId=${Uri.encodeQueryComponent(_kBetaId)}&brightness=light',
          ),
          isTrue,
        );
        await tester.pump();
        expect(find.text('Beta: count=0'), findsOneWidget);
        expect(
          find.textContaining('platform=light theme=light'),
          findsOneWidget,
        );

        expect(await WidgetsBinding.instance.handlePushRoute('/'), isTrue);
        await tester.pump();
        expect(find.text('Beta: count=0'), findsOneWidget);

        debugSetUrlFragment('embed=1&previewId=Expanding');
        await tester.pump();
        expect(find.text('Expanded Preview'), findsOneWidget);
        expect(navigationCalls, isNot(contains('selectSingleEntryHistory')));
      },
    );

    testWidgets(
      'transitions from standard scaffold to embed mode via handlePushRoute and switches to multi-entry history',
      (WidgetTester tester) async {
        final List<String> navigationCalls = _mockNavigationCalls();
        await pumpTestScaffold(
          tester,
          fragment: '',
          previews: _buildTestPreviews,
        );
        expect(find.byType(PreviewSearchControls), findsOneWidget);
        expect(navigationCalls, contains('selectSingleEntryHistory'));

        navigationCalls.clear();
        expect(
          await WidgetsBinding.instance.handlePushRoute(
            'embed=1&previewId=Expanding',
          ),
          isTrue,
        );
        await tester.pump();
        expect(find.text('Expanded Preview'), findsOneWidget);
        expect(find.byType(PreviewSearchControls), findsNothing);
        expect(navigationCalls, contains('selectMultiEntryHistory'));
        expect(navigationCalls, isNot(contains('selectSingleEntryHistory')));
      },
    );

    testWidgets(
      'renders all previews grouped by group and switches between gallery and single-preview fragments',
      (WidgetTester tester) async {
        await pumpTestScaffold(
          tester,
          fragment: 'embed=1',
          previews: _buildGroupedTestPreviews,
        );
        expect(find.byType(PreviewSearchControls), findsNothing);
        expect(find.byType(LayoutTypeSelector), findsNothing);
        expect(find.text('Buttons'), findsOneWidget);
        expect(find.text('Cards'), findsOneWidget);
        expect(find.text('Invalid Previews'), findsOneWidget);
        expect(find.text('1'), findsNWidgets(2));
        expect(find.text('2'), findsOneWidget);
        expect(find.text('Primary Button'), findsOneWidget);
        expect(find.text('Alpha Card'), findsOneWidget);
        expect(find.text('brokenButtonPreview'), findsOneWidget);
        expect(
          find.text('package:my_app/broken_button.dart has errors!'),
          findsOneWidget,
        );

        await tester.tap(find.text('Increment').first);
        await tester.pump();
        expect(find.text('Alpha: count=1'), findsOneWidget);

        await tester.scrollUntilVisible(
          find.text('Beta Card'),
          200.0,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('300\u00D7400'), findsOneWidget);

        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent('Beta Card')}',
        );
        await tester.pump();
        expect(find.text('Buttons'), findsNothing);
        expect(find.text('Alpha: count=1'), findsNothing);
        expect(find.text('Beta: count=0'), findsOneWidget);

        debugSetUrlFragment('embed=1&previewId=*');
        await tester.pump();
        expect(find.text('Buttons'), findsOneWidget);
        expect(find.text('Primary Button'), findsOneWidget);

        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent(_kAlphaId)}',
        );
        await tester.pump();
        expect(find.text('Buttons'), findsNothing);
        expect(find.text('Alpha: count=0'), findsOneWidget);

        debugSetUrlFragment('embed=1');
        await tester.pump();
        expect(find.text('Buttons'), findsOneWidget);
        expect(find.text('Alpha Card'), findsOneWidget);
      },
    );

    testWidgets(
      'renders empty state when no previews exist in all-previews mode',
      (WidgetTester tester) async {
        await pumpTestScaffold(
          tester,
          fragment: 'embed=1',
          previews: () => const <WidgetPreview>[],
        );
        expect(find.text('No widget previews detected'), findsOneWidget);
        expect(
          find.text('No widget previews were detected in this project.'),
          findsOneWidget,
        );
        debugSetUrlFragment('embed=1&previewId=*');
        await tester.pump();
        expect(find.text('No widget previews detected'), findsOneWidget);
      },
    );

    testWidgets(
      'applies brightness and width overrides across all-previews gallery cards',
      (WidgetTester tester) async {
        await pumpTestScaffold(
          tester,
          fragment: 'embed=1&previewId=*&brightness=dark&width=375',
          previews: () => <WidgetPreview>[
            _buildAlphaPreview(),
            _buildBetaPreview(),
          ],
        );
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
        await pumpTestScaffold(
          tester,
          fragment: 'embed=1&previewId=*&width=720&height=300',
          previews: () => <WidgetPreview>[_buildAlphaPreview()],
          viewSize: const Size(400, 600),
        );
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
      'scales single preview at 50% and 200% without changing logical MediaQuery, preserves hit-testing and TextField input, and supports Ctrl+wheel/keyboard zoom',
      (WidgetTester tester) async {
        await pumpTestScaffold(
          tester,
          fragment:
              'embed=1&previewId=${Uri.encodeQueryComponent(_kAlphaId)}'
              '&width=375&height=400&zoom=0.5',
          previews: _buildTestPreviews,
          viewSize: const Size(800, 600),
        );

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

        await tester.tap(find.text('Increment'));
        await tester.pump();
        expect(find.text('Alpha: count=1'), findsOneWidget);

        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent(_kAlphaId)}&width=1280&height=800&zoom=0.5',
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('media=1280x800'), findsOneWidget);
        expect(find.textContaining('constraints=1280x800'), findsOneWidget);
        expect(
          tester.getSize(find.byType(ScaledPreviewLayout)),
          const Size(640.0, 400.0),
        );

        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent(_kAlphaId)}&width=375&height=400&zoom=2',
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

        for (final (String frag, Size expectedVisualSize) in <(String, Size)>[
          (
            'embed=1&previewId=${Uri.encodeQueryComponent(_kAlphaId)}&width=375&height=400&zoom=1.5',
            const Size(562.5, 600.0),
          ),
          (
            'embed=1&previewId=${Uri.encodeQueryComponent(_kAlphaId)}&width=375&height=400',
            const Size(375.0, 400.0),
          ),
        ]) {
          debugSetUrlFragment(frag);
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(find.byType(ScaledPreviewLayout)),
            expectedVisualSize,
          );
        }

        await tester.sendKeyEvent(LogicalKeyboardKey.equal);
        await tester.pump();
        expect(_currentScaledLayoutZoom(tester), 1.25);
        await tester.sendKeyEvent(LogicalKeyboardKey.minus);
        await tester.sendKeyEvent(LogicalKeyboardKey.minus);
        await tester.pump();
        expect(_currentScaledLayoutZoom(tester), 0.75);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
        await tester.pump();
        expect(_currentScaledLayoutZoom(tester), 1.0);

        final pointer = TestPointer(7, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(
          pointer.hover(tester.getCenter(find.byType(ScaledPreviewLayout))),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -20)));
        await tester.pump();
        expect(_currentScaledLayoutZoom(tester), 1.25);
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 20)));
        await tester.pump();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        expect(_currentScaledLayoutZoom(tester), 1.0);

        await tester.tap(find.byType(TextField));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.equal);
        await tester.sendKeyEvent(LogicalKeyboardKey.minus);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
        await tester.enterText(find.byType(TextField), '0+-');
        await tester.pump();
        expect(find.text('0+-'), findsOneWidget);
        expect(_currentScaledLayoutZoom(tester), 1.0);

        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent(_kAlphaId)}&zoom=2',
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(ScaledPreviewLayout)).width, 1600.0);
      },
    );

    testWidgets(
      'resets back to 100% when parent clears zoom hash and does not steal unmodified keys from focused preview controls',
      (WidgetTester tester) async {
        final autofocusFieldNode = FocusNode();
        addTearDown(autofocusFieldNode.dispose);
        final childFocusNode = FocusNode();
        addTearDown(childFocusNode.dispose);
        final receivedKeys = <LogicalKeyboardKey>[];

        const baseFragment = 'embed=1&previewId=Focusable&width=300&height=200';
        await pumpTestScaffold(
          tester,
          fragment: baseFragment,
          viewSize: const Size(800, 600),
          previews: () => <WidgetPreview>[
            makeTestPreview(
              fileStem: 'focusable',
              functionName: 'focusablePreview',
              name: 'Focusable',
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
            ),
            makeTestPreview(
              fileStem: 'autofocus',
              functionName: 'autofocusPreview',
              name: 'Autofocus',
              previewFunction: () => Material(
                child: TextField(
                  autofocus: true,
                  focusNode: autofocusFieldNode,
                ),
              ),
            ),
          ],
        );

        expect(EmbedPreviewParams.fromFragment(getUrlFragment()).zoom, isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.equal);
        await tester.sendKeyEvent(LogicalKeyboardKey.equal);
        await tester.pump();
        expect(_currentScaledLayoutZoom(tester), 1.5);
        expect(EmbedPreviewParams.fromFragment(getUrlFragment()).zoom, 1.5);

        debugSetUrlFragment(baseFragment);
        await tester.pump();
        expect(_currentScaledLayoutZoom(tester), 1.0);

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
        expect(_currentScaledLayoutZoom(tester), 1.0);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.equal);
        await tester.pump();
        expect(_currentScaledLayoutZoom(tester), 1.25);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(_currentScaledLayoutZoom(tester), 1.0);

        debugSetUrlFragment('embed=1&previewId=Autofocus&width=300&height=200');
        await tester.pump();
        expect(autofocusFieldNode.hasPrimaryFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.equal);
        await tester.pump();
        expect(_currentScaledLayoutZoom(tester), 1.0);
      },
    );

    testWidgets(
      'scales all-previews gallery cards at 50% and 200% without nested vertical scroll views',
      (WidgetTester tester) async {
        await pumpTestScaffold(
          tester,
          fragment: 'embed=1&previewId=*&zoom=0.5',
          previews: () => <WidgetPreview>[
            _buildBetaPreview(),
            _buildAlphaPreview(),
          ],
          viewSize: const Size(450, 700),
        );
        expect(find.textContaining('media=300x400'), findsOneWidget);
        expect(
          tester.getSize(find.byType(ScaledPreviewLayout).first),
          const Size(150.0, 200.0),
        );
        expect(
          find.byWidgetPredicate(
            (Widget widget) =>
                widget is SingleChildScrollView &&
                widget.scrollDirection == Axis.vertical,
          ),
          findsNothing,
        );

        debugSetUrlFragment('embed=1&previewId=*&zoom=2');
        await tester.pump();
        expect(
          tester.getSize(find.byType(ScaledPreviewLayout).first),
          const Size(600.0, 800.0),
        );

        debugSetUrlFragment('embed=1&previewId=*');
        await tester.pump();
        expect(
          tester.getSize(find.byType(ScaledPreviewLayout).first),
          const Size(300.0, 400.0),
        );
      },
    );
  });
}

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
    if (_minWidth != value) {
      _minWidth = value;
      markNeedsLayout();
    }
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

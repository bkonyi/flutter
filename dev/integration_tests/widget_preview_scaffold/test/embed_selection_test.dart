// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widget_preview_scaffold/src/embed_selection.dart';
import 'package:widget_preview_scaffold/src/utils.dart';
import 'package:widget_preview_scaffold/src/utils/url/url.dart';
import 'package:widget_preview_scaffold/src/widget_preview.dart';
import 'package:widget_preview_scaffold/src/widget_preview_rendering.dart';
import 'package:widget_preview_scaffold/src/widget_preview_scaffold_controller.dart';

import 'utils/widget_preview_scaffold_test_utils.dart';

const _kCardPreviewId = 'package:my_app/card.dart::cardPreview';
const _kUnnamedPreviewId = 'package:my_app/unnamed.dart::unnamedPreview';
const _kSubmitKey = Key('submit');
const _kKeyedWrapperKey = Key('explicit-padding');

class _InspectableCard extends StatefulWidget {
  const _InspectableCard();

  @override
  State<_InspectableCard> createState() => _InspectableCardState();
}

class _InspectableCardState extends State<_InspectableCard> {
  final _controller = TextEditingController(
    text:
        'Line one   with   extra\nwhitespace and a tail that exceeds eighty characters in total length for truncation verification',
  );
  var _tapCount = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 400,
      height: 300,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 32,
            top: 24,
            width: 120,
            height: 40,
            child: ElevatedButton(
              key: _kSubmitKey,
              onPressed: () => setState(() => _tapCount++),
              child: const Text('Submit'),
            ),
          ),
          Positioned(
            left: 200,
            top: 24,
            child: Padding(
              key: _kKeyedWrapperKey,
              padding: const EdgeInsets.all(4.0),
              child: Text('Taps: $_tapCount'),
            ),
          ),
          Positioned(
            left: 32,
            top: 90,
            width: 240,
            height: 48,
            child: TextField(controller: _controller),
          ),
          Positioned(
            left: 32,
            top: 160,
            child: RichText(
              text: const TextSpan(
                text: 'Rich ',
                style: TextStyle(color: Colors.black, fontSize: 14),
                children: <InlineSpan>[TextSpan(text: 'caption')],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

WidgetPreview _buildCardPreview() => buildWidgetPreview(
  column: 1,
  functionName: 'cardPreview',
  libraryUri: 'package:my_app/card.dart',
  line: 10,
  packageName: 'my_app',
  previewFunction: () => const _InspectableCard(),
  scriptUri: 'file:///project/lib/card.dart',
  transformedPreview: const Preview(
    name: 'My Card',
    size: Size(400, 300),
  ).transform(),
);

WidgetPreview _buildUnnamedPreview() => buildWidgetPreview(
  column: 1,
  functionName: 'unnamedPreview',
  libraryUri: 'package:my_app/unnamed.dart',
  line: 20,
  packageName: 'my_app',
  previewFunction: () => SizedBox(
    width: 300,
    height: 160,
    child: Center(
      child: ElevatedButton(
        onPressed: () {},
        child: const Text('Secondary Action'),
      ),
    ),
  ),
  scriptUri: 'file:///project/lib/unnamed.dart',
  transformedPreview: const Preview(size: Size(300, 160)).transform(),
);

Future<WidgetPreviewScaffoldController> _pumpEmbedPreview(
  WidgetTester tester, {
  required String fragment,
  List<WidgetPreview>? previewList,
}) async {
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  debugSetUrlFragment(fragment);
  final controller = WidgetPreviewScaffoldController(
    dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
    previews: () =>
        previewList ??
        <WidgetPreview>[_buildCardPreview(), _buildUnnamedPreview()],
  );
  addTearDown(controller.dispose);
  await controller.initialize();

  await tester.pumpWidget(TestWidgetPreviewScaffold(controller: controller));
  await tester.pump();
  expect(tester.takeException(), isNull);
  return controller;
}

Future<void> _dragBetweenGlobal(
  WidgetTester tester, {
  required Offset start,
  required Offset end,
  int pointerId = 1,
}) async {
  final TestGesture gesture = await tester.startGesture(
    start,
    pointer: pointerId,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  final Offset delta = end - start;
  await gesture.moveBy(delta / 2.0);
  await tester.pump();
  await gesture.moveTo(end);
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

void main() {
  tearDown(debugResetUrlTestState);

  group('$EmbedPreviewParams select parameter', () {
    test('parses select=1 and select=true and omits select when false', () {
      expect(EmbedPreviewParams.parse('embed=1').selectMode, isFalse);
      expect(EmbedPreviewParams.parse('embed=1&select=0').selectMode, isFalse);
      expect(EmbedPreviewParams.parse('embed=1&select=1').selectMode, isTrue);
      expect(
        EmbedPreviewParams.parse('embed=1&select=true').selectMode,
        isTrue,
      );
      expect(
        EmbedPreviewParams.parse('embed=1&select=TRUE').selectMode,
        isTrue,
      );

      const disabled = EmbedPreviewParams(
        brightness: Brightness.light,
        height: 300,
        isEmbed: true,
        previewId: _kCardPreviewId,
        width: 400,
      );
      expect(disabled.toFragment().contains('select='), isFalse);

      final EmbedPreviewParams enabled = disabled.copyWith(selectMode: true);
      expect(enabled.selectMode, isTrue);
      expect(enabled, isNot(equals(disabled)));
      expect(enabled.hashCode, isNot(equals(disabled.hashCode)));
      expect(enabled.toFragment(), contains('select=1'));
      expect(EmbedPreviewParams.parse(enabled.toFragment()), equals(enabled));

      // Preserves selectMode across withZoom.
      expect(enabled.withZoom(2.0).selectMode, isTrue);
      expect(enabled.withZoom(2.0).toFragment(), contains('select=1'));
      expect(enabled.withZoom(2.0).toFragment(), contains('zoom=2'));
    });
  });

  group('Multi-region selection and live RenderBox inspection', () {
    testWidgets(
      'marquee drag at zoom=1.0 and zoom=2.0 produces identical unzoomed logical coordinates and extracts widget metadata',
      (WidgetTester tester) async {
        await _pumpEmbedPreview(
          tester,
          fragment:
              'embed=1&previewId=${Uri.encodeQueryComponent(_kCardPreviewId)}'
              '&brightness=light&textScale=1.0&select=1',
        );

        final Finder scaledFinder = find.byType(ScaledPreviewLayout);
        expect(scaledFinder, findsOneWidget);
        final EmbedSelectionController selectionController = tester
            .widget<EmbedSelectablePreviewSurface>(
              find.byType(EmbedSelectablePreviewSurface).first,
            )
            .selectionController;
        final Offset topLeftZoom1 = tester.getTopLeft(scaledFinder);
        expect(tester.getSize(scaledFinder), const Size(400, 300));

        // Drag from preview-local (24, 16) to (204, 80) -> 180x64 region covering Submit button.
        await _dragBetweenGlobal(
          tester,
          start: topLeftZoom1 + const Offset(24, 16),
          end: topLeftZoom1 + const Offset(204, 80),
        );

        expect(selectionController.selectionsJson, hasLength(1));
        final Map<String, Object?> zoom1Selection =
            selectionController.selectionsJson.single;
        expect(zoom1Selection['id'], 'sel-1');
        expect(zoom1Selection['index'], 1);
        expect(zoom1Selection['kind'], 'region');
        expect(zoom1Selection['previewId'], _kCardPreviewId);
        expect(zoom1Selection['previewName'], 'My Card');
        expect(zoom1Selection['x'], 24);
        expect(zoom1Selection['y'], 16);
        expect(zoom1Selection['width'], 180);
        expect(zoom1Selection['height'], 64);
        expect(zoom1Selection['previewWidth'], 400);
        expect(zoom1Selection['previewHeight'], 300);
        expect(zoom1Selection['brightness'], 'light');
        expect(zoom1Selection['textScale'], 1.0);
        expect(zoom1Selection['zoom'], 1.0);

        final zoom1Widgets = (zoom1Selection['widgets']! as List<Object?>)
            .cast<Map<String, Object?>>();
        expect(
          zoom1Widgets,
          contains(
            allOf(
              containsPair('widget', 'ElevatedButton'),
              containsPair('key', "[<'submit'>]"),
              containsPair('x', 32),
              containsPair('y', 24),
              containsPair('width', 120),
              containsPair('height', 40),
            ),
          ),
        );
        expect(
          zoom1Widgets,
          contains(
            allOf(
              containsPair('widget', 'Text'),
              containsPair('text', 'Submit'),
            ),
          ),
        );
        // Unkeyed private/plumbing wrappers are excluded.
        expect(
          zoom1Widgets.any(
            (Map<String, Object?> w) =>
                (w['widget']! as String).startsWith('_'),
          ),
          isFalse,
        );
        expect(
          zoom1Widgets.any(
            (Map<String, Object?> w) =>
                w['widget'] == 'Semantics' && !w.containsKey('key'),
          ),
          isFalse,
        );

        // Clear selection and switch to zoom=2.0, then drag the exact same logical region
        // (scaled by 2.0 in screen space).
        selectionController.clearSelections();
        await tester.pump();
        expect(selectionController.selectionsJson, isEmpty);

        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent(_kCardPreviewId)}'
          '&brightness=light&textScale=1.0&zoom=2&select=1',
        );
        await tester.pump();

        expect(tester.getSize(scaledFinder), const Size(800, 600));
        final Offset topLeftZoom2 = tester.getTopLeft(scaledFinder);

        await _dragBetweenGlobal(
          tester,
          pointerId: 2,
          start: topLeftZoom2 + const Offset(24 * 2.0, 16 * 2.0),
          end: topLeftZoom2 + const Offset(204 * 2.0, 80 * 2.0),
        );

        final Map<String, Object?> zoom2Selection =
            selectionController.selectionsJson.single;
        expect(zoom2Selection['zoom'], 2.0);
        expect(zoom2Selection['x'], zoom1Selection['x']);
        expect(zoom2Selection['y'], zoom1Selection['y']);
        expect(zoom2Selection['width'], zoom1Selection['width']);
        expect(zoom2Selection['height'], zoom1Selection['height']);
        expect(zoom2Selection['previewWidth'], 400);
        expect(zoom2Selection['previewHeight'], 300);

        final zoom2Widgets = (zoom2Selection['widgets']! as List<Object?>)
            .cast<Map<String, Object?>>();
        expect(zoom2Widgets, equals(zoom1Widgets));
      },
    );

    testWidgets(
      'drag under 4px creates a point selection and extracts collapsed/truncated text from EditableText and RichText',
      (WidgetTester tester) async {
        await _pumpEmbedPreview(
          tester,
          fragment:
              'embed=1&previewId=${Uri.encodeQueryComponent(_kCardPreviewId)}&select=1',
        );

        final EmbedSelectionController selectionController = tester
            .widget<EmbedSelectablePreviewSurface>(
              find.byType(EmbedSelectablePreviewSurface).first,
            )
            .selectionController;
        final Offset topLeft = tester.getTopLeft(
          find.byType(ScaledPreviewLayout),
        );

        // Click (< 4px movement) on the TextField at logical (80, 110).
        await _dragBetweenGlobal(
          tester,
          start: topLeft + const Offset(80, 110),
          end: topLeft + const Offset(82, 111),
        );

        final Map<String, Object?> pointSelection =
            selectionController.selectionsJson.single;
        expect(pointSelection['kind'], 'point');
        expect(pointSelection['x'], 82);
        expect(pointSelection['y'], 111);
        expect(pointSelection['width'], 0);
        expect(pointSelection['height'], 0);

        final pointWidgets = (pointSelection['widgets']! as List<Object?>)
            .cast<Map<String, Object?>>();
        final Map<String, Object?> editableEntry = pointWidgets.firstWhere(
          (Map<String, Object?> w) => w['widget'] == 'EditableText',
        );
        final editableText = editableEntry['text']! as String;
        expect(editableText.length, 80);
        expect(editableText, startsWith('Line one with extra whitespace'));
        expect(editableText, endsWith('...'));

        // Select over RichText + keyed Padding wrapper.
        await _dragBetweenGlobal(
          tester,
          pointerId: 3,
          start: topLeft + const Offset(28, 20),
          end: topLeft + const Offset(290, 195),
        );

        final Map<String, Object?> secondSelection =
            selectionController.selectionsJson.last;
        final secondWidgets = (secondSelection['widgets']! as List<Object?>)
            .cast<Map<String, Object?>>();
        expect(
          secondWidgets,
          contains(
            allOf(
              containsPair('widget', 'RichText'),
              containsPair('text', 'Rich caption'),
            ),
          ),
        );
        expect(
          secondWidgets,
          contains(
            allOf(
              containsPair('widget', 'Padding'),
              containsPair('key', "[<'explicit-padding'>]"),
            ),
          ),
        );
      },
    );

    testWidgets(
      'passes pointer events through when selectMode is false, supports Shift+drag selection, Escape key, and x badge removal',
      (WidgetTester tester) async {
        await _pumpEmbedPreview(
          tester,
          fragment:
              'embed=1&previewId=${Uri.encodeQueryComponent(_kCardPreviewId)}',
        );

        final EmbedSelectionController selectionController = tester
            .widget<EmbedSelectablePreviewSurface>(
              find.byType(EmbedSelectablePreviewSurface).first,
            )
            .selectionController;

        // Normal tap on ElevatedButton works when selectMode is false and Shift is not pressed.
        expect(find.text('Taps: 0'), findsOneWidget);
        await tester.tap(find.byKey(_kSubmitKey));
        await tester.pump();
        expect(find.text('Taps: 1'), findsOneWidget);
        expect(selectionController.selections, isEmpty);

        // Holding Shift + click/drag selects without triggering ElevatedButton.onPressed!
        final Offset topLeft = tester.getTopLeft(
          find.byType(ScaledPreviewLayout),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await _dragBetweenGlobal(
          tester,
          pointerId: 4,
          start: topLeft + const Offset(30, 20),
          end: topLeft + const Offset(160, 70),
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();

        expect(find.text('Taps: 1'), findsOneWidget);
        expect(selectionController.selectMode, isFalse);
        expect(selectionController.selections, hasLength(1));
        expect(
          find.byKey(const ValueKey<String>('embed-selection-overlay-sel-1')),
          findsOneWidget,
        );

        // Enable selectMode directly on controller, add a second selection (#2).
        selectionController.setSelectMode(true);
        await tester.pump();
        expect(getUrlFragment(), contains('select=1'));
        expect(selectionController.selectMode, isTrue);

        await _dragBetweenGlobal(
          tester,
          pointerId: 5,
          start: topLeft + const Offset(195, 20),
          end: topLeft + const Offset(280, 55),
        );
        expect(selectionController.selections, hasLength(2));
        expect(find.text('#1'), findsOneWidget);
        expect(find.text('#2'), findsOneWidget);

        // Tapping the 'x' badge on #1 removes sel-1 and renumbers sel-2 to index 1 (#1)
        // without creating a new point selection even while selectMode is true.
        await tester.tap(
          find.byKey(const ValueKey<String>('embed-selection-remove-sel-1')),
        );
        await tester.pump();

        expect(selectionController.selections, hasLength(1));
        final Map<String, Object?> remaining =
            selectionController.selectionsJson.single;
        expect(remaining['id'], 'sel-2');
        expect(remaining['index'], 1);
        expect(find.text('#1'), findsOneWidget);
        expect(find.text('#2'), findsNothing);

        // First Escape exits selectMode and strips select=1 from URL while keeping #1.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(getUrlFragment().contains('select='), isFalse);
        expect(selectionController.selectMode, isFalse);
        expect(selectionController.selections, hasLength(1));

        // Second Escape clears all remaining selections.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(selectionController.selections, isEmpty);
        expect(find.text('#1'), findsNothing);
      },
    );

    testWidgets(
      'supports multi-region #1 + #2 across All Previews gallery cards and removeSelectionById',
      (WidgetTester tester) async {
        await _pumpEmbedPreview(
          tester,
          fragment: 'embed=1&previewId=*&select=1',
        );

        final Finder surfaces = find.byType(EmbedSelectablePreviewSurface);
        expect(surfaces, findsNWidgets(2));
        final EmbedSelectionController selectionController = tester
            .widget<EmbedSelectablePreviewSurface>(surfaces.first)
            .selectionController;

        final Offset cardOneTopLeft = tester.getTopLeft(surfaces.at(0));
        final Offset cardTwoTopLeft = tester.getTopLeft(surfaces.at(1));

        // Select region #1 on Card 1 (My Card).
        await _dragBetweenGlobal(
          tester,
          pointerId: 10,
          start: cardOneTopLeft + const Offset(24, 16),
          end: cardOneTopLeft + const Offset(170, 72),
        );

        // Select region #2 on Card 2 (unnamed preview - omits previewName).
        await _dragBetweenGlobal(
          tester,
          pointerId: 11,
          start: cardTwoTopLeft + const Offset(40, 30),
          end: cardTwoTopLeft + const Offset(260, 120),
        );

        final List<Map<String, Object?>> selections =
            selectionController.selectionsJson;
        expect(selections, hasLength(2));
        expect(selections[0]['id'], 'sel-1');
        expect(selections[0]['index'], 1);
        expect(selections[0]['previewId'], _kCardPreviewId);
        expect(selections[0]['previewName'], 'My Card');

        expect(selections[1]['id'], 'sel-2');
        expect(selections[1]['index'], 2);
        expect(selections[1]['previewId'], _kUnnamedPreviewId);
        expect(selections[1].containsKey('previewName'), isFalse);

        expect(find.text('#1'), findsOneWidget);
        expect(find.text('#2'), findsOneWidget);

        // Removing 'sel-1' leaves 'sel-2' renumbered to index 1.
        selectionController.removeSelectionById('sel-1');
        await tester.pump();

        final List<Map<String, Object?>> afterRemoveOne =
            selectionController.selectionsJson;
        expect(afterRemoveOne, hasLength(1));
        expect(afterRemoveOne.single['id'], 'sel-2');
        expect(afterRemoveOne.single['index'], 1);
        expect(afterRemoveOne.single['previewId'], _kUnnamedPreviewId);
      },
    );

    test(
      'formatEmbedSelectionContext formats selections with project root and widgets',
      () {
        const entry = EmbedSelectionEntry(
          brightness: Brightness.dark,
          height: 40,
          id: 'sel-1',
          index: 1,
          kind: EmbedSelectionKind.region,
          previewHeight: 300,
          previewId: _kCardPreviewId,
          previewName: 'My Card',
          previewWidth: 400,
          textScale: 1.25,
          widgets: <EmbedSelectedWidgetInfo>[
            EmbedSelectedWidgetInfo(
              height: 36,
              key: "[<'submit'>]",
              text: 'Submit',
              widget: 'ElevatedButton',
              width: 100,
              x: 12,
              y: 16,
            ),
          ],
          width: 120,
          x: 10,
          y: 20,
          zoom: 1.5,
        );
        final String formatted = formatEmbedSelectionContext(
          selections: const <EmbedSelectionEntry>[entry],
          projectRoot: '/tmp/my_app',
        );
        expect(formatted, contains('Selected Widget Preview Context (1):'));
        expect(formatted, contains('Project: /tmp/my_app'));
        expect(
          formatted,
          contains(
            '#1 My Card ($_kCardPreviewId) - region (10, 20) 120x40 in 400x300 '
            '[dark, textScale=1.25, zoom=1.5]',
          ),
        );
        expect(
          formatted,
          contains(
            '  - ElevatedButton key=[<\'submit\'>] "Submit" (12, 16) 100x36',
          ),
        );
      },
    );

    testWidgets('marquee selection aligns after scrolling a zoomed preview', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(500, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      debugSetUrlFragment(
        'embed=1&previewId=${Uri.encodeQueryComponent(_kCardPreviewId)}'
        '&zoom=2&select=1',
      );
      final controller = WidgetPreviewScaffoldController(
        dtdServicesOverride: FakeWidgetPreviewScaffoldDtdServices(),
        previews: () => <WidgetPreview>[_buildCardPreview()],
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: controller),
      );
      await tester.pump();

      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(40.0);
      tester
          .state<ScrollableState>(find.byType(Scrollable).last)
          .position
          .jumpTo(50.0);
      await tester.pump();

      final Finder surfaceFinder = find
          .byType(EmbedSelectablePreviewSurface)
          .first;
      final EmbedSelectionController selectionController = tester
          .widget<EmbedSelectablePreviewSurface>(surfaceFinder)
          .selectionController;
      final Offset surfaceTopLeft = tester.getTopLeft(surfaceFinder);

      await _dragBetweenGlobal(
        tester,
        pointerId: 20,
        start: surfaceTopLeft + const Offset(28 * 2.0, 20 * 2.0),
        end: surfaceTopLeft + const Offset(160 * 2.0, 70 * 2.0),
      );

      expect(selectionController.selectionsJson, hasLength(1));
      final Map<String, Object?> sel =
          selectionController.selectionsJson.single;
      expect(sel['x'], 28);
      expect(sel['y'], 20);
      expect(sel['width'], 132);
      expect(sel['height'], 50);
      final widgets = (sel['widgets']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        widgets,
        contains(
          allOf(
            containsPair('widget', 'ElevatedButton'),
            containsPair('key', "[<'submit'>]"),
          ),
        ),
      );
    });

    testWidgets(
      'narrow preview badge x button stays within bounds and is tappable',
      (WidgetTester tester) async {
        final WidgetPreview narrowPreview = buildWidgetPreview(
          column: 1,
          functionName: 'narrowPreview',
          libraryUri: 'package:my_app/narrow.dart',
          line: 1,
          packageName: 'my_app',
          previewFunction: () => const SizedBox(width: 40, height: 40),
          scriptUri: 'file:///project/lib/narrow.dart',
          transformedPreview: const Preview(size: Size(40, 40)).transform(),
        );
        await _pumpEmbedPreview(
          tester,
          fragment:
              'embed=1&previewId=${Uri.encodeQueryComponent(narrowPreview.id)}&select=1',
          previewList: <WidgetPreview>[narrowPreview],
        );

        final Finder narrowSurface = find
            .byType(EmbedSelectablePreviewSurface)
            .first;
        final EmbedSelectionController narrowSelectionController = tester
            .widget<EmbedSelectablePreviewSurface>(narrowSurface)
            .selectionController;
        final Offset narrowTopLeft = tester.getTopLeft(narrowSurface);
        await _dragBetweenGlobal(
          tester,
          pointerId: 21,
          start: narrowTopLeft + const Offset(4, 4),
          end: narrowTopLeft + const Offset(30, 30),
        );
        expect(narrowSelectionController.selections, hasLength(1));
        final String narrowSelId =
            narrowSelectionController.selections.single.id;
        await tester.tap(
          find.byKey(ValueKey<String>('embed-selection-remove-$narrowSelId')),
        );
        await tester.pump();
        expect(narrowSelectionController.selections, isEmpty);
      },
    );
  });
}

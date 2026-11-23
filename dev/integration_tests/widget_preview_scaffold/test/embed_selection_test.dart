// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widget_preview_scaffold/src/embed_selection.dart';
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

WidgetPreview _buildCardPreview() => makeTestPreview(
  fileStem: 'card',
  functionName: 'cardPreview',
  name: 'My Card',
  previewFunction: () => const _InspectableCard(),
  size: const Size(400, 300),
);

WidgetPreview _buildUnnamedPreview() => makeTestPreview(
  fileStem: 'unnamed',
  functionName: 'unnamedPreview',
  line: 20,
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
  size: const Size(300, 160),
);

Future<WidgetPreviewScaffoldController> _pumpSelectionPreview(
  WidgetTester tester, {
  required String fragment,
  List<WidgetPreview>? previewList,
  Size viewSize = const Size(1000, 900),
}) => pumpTestScaffold(
  tester,
  fragment: fragment,
  previews: () =>
      previewList ??
      <WidgetPreview>[_buildCardPreview(), _buildUnnamedPreview()],
  viewSize: viewSize,
);

EmbedSelectionController _selectionControllerOf(WidgetTester tester) => tester
    .widget<EmbedSelectablePreviewSurface>(
      find.byType(EmbedSelectablePreviewSurface).first,
    )
    .selectionController;

void main() {
  tearDown(debugResetUrlTestState);

  group('$EmbedPreviewParams select parameter', () {
    test('parses select=1 and select=true and omits select when false', () {
      for (final (String fragment, bool expected) in const <(String, bool)>[
        ('embed=1', false),
        ('embed=1&select=0', false),
        ('embed=1&select=1', true),
        ('embed=1&select=true', true),
        ('embed=1&select=TRUE', true),
      ]) {
        expect(EmbedPreviewParams.parse(fragment).selectMode, expected);
      }

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
      expect(enabled.withZoom(2.0).selectMode, isTrue);
      expect(
        enabled.withZoom(2.0).toFragment(),
        allOf(contains('select=1'), contains('zoom=2')),
      );
    });
  });

  group('Multi-region selection and live RenderBox inspection', () {
    testWidgets(
      'marquee drag at zoom=1.0 and zoom=2.0 produces identical unzoomed logical coordinates and extracts widget metadata',
      (WidgetTester tester) async {
        await _pumpSelectionPreview(
          tester,
          fragment:
              'embed=1&previewId=${Uri.encodeQueryComponent(_kCardPreviewId)}'
              '&brightness=light&textScale=1.0&select=1',
        );

        final Finder scaledFinder = find.byType(ScaledPreviewLayout);
        final EmbedSelectionController selectionController =
            _selectionControllerOf(tester);
        final Offset topLeftZoom1 = tester.getTopLeft(scaledFinder);
        expect(tester.getSize(scaledFinder), const Size(400, 300));

        await dragBetweenGlobal(
          tester,
          start: topLeftZoom1 + const Offset(24, 16),
          end: topLeftZoom1 + const Offset(204, 80),
        );

        final Map<String, Object?> zoom1Selection =
            selectionController.selectionsJson.single;
        expect(
          zoom1Selection,
          allOf(<Matcher>[
            containsPair('id', 'sel-1'),
            containsPair('index', 1),
            containsPair('kind', 'region'),
            containsPair('previewId', _kCardPreviewId),
            containsPair('previewName', 'My Card'),
            containsPair('x', 24),
            containsPair('y', 16),
            containsPair('width', 180),
            containsPair('height', 64),
            containsPair('previewWidth', 400),
            containsPair('previewHeight', 300),
            containsPair('brightness', 'light'),
            containsPair('textScale', 1.0),
            containsPair('zoom', 1.0),
          ]),
        );

        final zoom1Widgets = (zoom1Selection['widgets']! as List<Object?>)
            .cast<Map<String, Object?>>();
        expect(
          zoom1Widgets,
          containsAll(<Matcher>[
            allOf(
              containsPair('widget', 'ElevatedButton'),
              containsPair('key', "[<'submit'>]"),
              containsPair('x', 32),
              containsPair('y', 24),
              containsPair('width', 120),
              containsPair('height', 40),
            ),
            allOf(
              containsPair('widget', 'Text'),
              containsPair('text', 'Submit'),
            ),
          ]),
        );
        expect(
          zoom1Widgets.any(
            (Map<String, Object?> w) =>
                (w['widget']! as String).startsWith('_') ||
                (w['widget'] == 'Semantics' && !w.containsKey('key')),
          ),
          isFalse,
        );

        selectionController.clearSelections();
        await tester.pump();
        debugSetUrlFragment(
          'embed=1&previewId=${Uri.encodeQueryComponent(_kCardPreviewId)}'
          '&brightness=light&textScale=1.0&zoom=2&select=1',
        );
        await tester.pump();

        expect(tester.getSize(scaledFinder), const Size(800, 600));
        final Offset topLeftZoom2 = tester.getTopLeft(scaledFinder);
        await dragBetweenGlobal(
          tester,
          pointerId: 2,
          start: topLeftZoom2 + const Offset(48, 32),
          end: topLeftZoom2 + const Offset(408, 160),
        );

        final Map<String, Object?> zoom2Selection =
            selectionController.selectionsJson.single;
        expect(zoom2Selection['zoom'], 2.0);
        for (final String key in const <String>[
          'x',
          'y',
          'width',
          'height',
          'previewWidth',
          'previewHeight',
          'widgets',
        ]) {
          expect(zoom2Selection[key], equals(zoom1Selection[key]));
        }
      },
    );

    testWidgets(
      'drag under 4px creates a point selection and extracts collapsed/truncated text from EditableText and RichText',
      (WidgetTester tester) async {
        await _pumpSelectionPreview(
          tester,
          fragment:
              'embed=1&previewId=${Uri.encodeQueryComponent(_kCardPreviewId)}&select=1',
        );

        final EmbedSelectionController selectionController =
            _selectionControllerOf(tester);
        final Offset topLeft = tester.getTopLeft(
          find.byType(ScaledPreviewLayout),
        );

        await dragBetweenGlobal(
          tester,
          start: topLeft + const Offset(80, 110),
          end: topLeft + const Offset(82, 111),
        );

        final Map<String, Object?> pointSelection =
            selectionController.selectionsJson.single;
        expect(
          pointSelection,
          allOf(
            containsPair('kind', 'point'),
            containsPair('x', 82),
            containsPair('y', 111),
            containsPair('width', 0),
            containsPair('height', 0),
          ),
        );

        final pointWidgets = (pointSelection['widgets']! as List<Object?>)
            .cast<Map<String, Object?>>();
        final editableText =
            pointWidgets.firstWhere(
                  (Map<String, Object?> w) => w['widget'] == 'EditableText',
                )['text']!
                as String;
        expect(editableText, hasLength(80));
        expect(editableText, startsWith('Line one with extra whitespace'));
        expect(editableText, endsWith('...'));

        await dragBetweenGlobal(
          tester,
          pointerId: 3,
          start: topLeft + const Offset(28, 20),
          end: topLeft + const Offset(290, 195),
        );
        final secondWidgets =
            (selectionController.selectionsJson.last['widgets']!
                    as List<Object?>)
                .cast<Map<String, Object?>>();
        expect(
          secondWidgets,
          containsAll(<Matcher>[
            allOf(
              containsPair('widget', 'RichText'),
              containsPair('text', 'Rich caption'),
            ),
            allOf(
              containsPair('widget', 'Padding'),
              containsPair('key', "[<'explicit-padding'>]"),
            ),
          ]),
        );
      },
    );

    testWidgets(
      'passes pointer events through when selectMode is false, supports Shift+drag selection, Escape key, and x badge removal',
      (WidgetTester tester) async {
        await _pumpSelectionPreview(
          tester,
          fragment:
              'embed=1&previewId=${Uri.encodeQueryComponent(_kCardPreviewId)}',
        );
        final EmbedSelectionController selectionController =
            _selectionControllerOf(tester);

        await tester.tap(find.byKey(_kSubmitKey));
        await tester.pump();
        expect(find.text('Taps: 1'), findsOneWidget);
        expect(selectionController.selections, isEmpty);

        final Offset topLeft = tester.getTopLeft(
          find.byType(ScaledPreviewLayout),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await dragBetweenGlobal(
          tester,
          pointerId: 4,
          start: topLeft + const Offset(30, 20),
          end: topLeft + const Offset(160, 70),
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();

        expect(find.text('Taps: 1'), findsOneWidget);
        expect(selectionController.selectMode, isFalse);
        expect(
          find.byKey(const ValueKey<String>('embed-selection-overlay-sel-1')),
          findsOneWidget,
        );

        selectionController.setSelectMode(true);
        await tester.pump();
        expect(getUrlFragment(), contains('select=1'));

        await dragBetweenGlobal(
          tester,
          pointerId: 5,
          start: topLeft + const Offset(195, 20),
          end: topLeft + const Offset(280, 55),
        );
        expect(find.text('#1'), findsOneWidget);
        expect(find.text('#2'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey<String>('embed-selection-remove-sel-1')),
        );
        await tester.pump();

        final Map<String, Object?> remaining =
            selectionController.selectionsJson.single;
        expect(remaining['id'], 'sel-2');
        expect(remaining['index'], 1);
        expect(find.text('#1'), findsOneWidget);
        expect(find.text('#2'), findsNothing);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(getUrlFragment().contains('select='), isFalse);
        expect(selectionController.selectMode, isFalse);
        expect(selectionController.selections, hasLength(1));

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(selectionController.selections, isEmpty);
        expect(find.text('#1'), findsNothing);
      },
    );

    testWidgets(
      'supports multi-region #1 + #2 across All Previews gallery cards and removeSelectionById',
      (WidgetTester tester) async {
        await _pumpSelectionPreview(
          tester,
          fragment: 'embed=1&previewId=*&select=1',
        );

        final Finder surfaces = find.byType(EmbedSelectablePreviewSurface);
        expect(surfaces, findsNWidgets(2));
        final EmbedSelectionController selectionController =
            _selectionControllerOf(tester);

        await dragBetweenGlobal(
          tester,
          pointerId: 10,
          start: tester.getTopLeft(surfaces.at(0)) + const Offset(24, 16),
          end: tester.getTopLeft(surfaces.at(0)) + const Offset(170, 72),
        );
        await dragBetweenGlobal(
          tester,
          pointerId: 11,
          start: tester.getTopLeft(surfaces.at(1)) + const Offset(40, 30),
          end: tester.getTopLeft(surfaces.at(1)) + const Offset(260, 120),
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

        selectionController.removeSelectionById('sel-1');
        await tester.pump();
        expect(selectionController.selectionsJson.single['id'], 'sel-2');
        expect(selectionController.selectionsJson.single['index'], 1);
        expect(find.text('#1'), findsOneWidget);
        expect(find.text('#2'), findsNothing);
      },
    );

    test(
      'formatEmbedSelectionContext formats selections with project root and widgets',
      () {
        const entry = EmbedSelectionEntry(
          brightness: Brightness.dark,
          height: 40,
          id: 'sel-1',
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
      await _pumpSelectionPreview(
        tester,
        fragment:
            'embed=1&previewId=${Uri.encodeQueryComponent(_kCardPreviewId)}'
            '&zoom=2&select=1',
        previewList: <WidgetPreview>[_buildCardPreview()],
        viewSize: const Size(500, 400),
      );

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
      final Offset surfaceTopLeft = tester.getTopLeft(surfaceFinder);
      await dragBetweenGlobal(
        tester,
        pointerId: 20,
        start: surfaceTopLeft + const Offset(56, 40),
        end: surfaceTopLeft + const Offset(320, 140),
      );

      final Map<String, Object?> sel = _selectionControllerOf(
        tester,
      ).selectionsJson.single;
      expect(
        sel,
        allOf(
          containsPair('x', 28),
          containsPair('y', 20),
          containsPair('width', 132),
          containsPair('height', 50),
        ),
      );
      expect(
        (sel['widgets']! as List<Object?>).cast<Map<String, Object?>>(),
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
        final WidgetPreview narrowPreview = makeTestPreview(
          fileStem: 'narrow',
          functionName: 'narrowPreview',
          previewFunction: () => const SizedBox(width: 40, height: 40),
          size: const Size(40, 40),
        );
        await _pumpSelectionPreview(
          tester,
          fragment:
              'embed=1&previewId=${Uri.encodeQueryComponent(narrowPreview.id)}&select=1',
          previewList: <WidgetPreview>[narrowPreview],
        );

        final EmbedSelectionController selectionController =
            _selectionControllerOf(tester);
        final Offset narrowTopLeft = tester.getTopLeft(
          find.byType(EmbedSelectablePreviewSurface).first,
        );
        await dragBetweenGlobal(
          tester,
          pointerId: 21,
          start: narrowTopLeft + const Offset(4, 4),
          end: narrowTopLeft + const Offset(30, 30),
        );
        final String selId = selectionController.selections.single.id;
        await tester.tap(
          find.byKey(ValueKey<String>('embed-selection-remove-$selId')),
        );
        await tester.pump();
        expect(selectionController.selections, isEmpty);
      },
    );
  });
}

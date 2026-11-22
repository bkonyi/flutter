// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/widget_previews.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widget_preview_scaffold/src/controls.dart';
import 'package:widget_preview_scaffold/src/dtd/editor_service.dart';
import 'package:widget_preview_scaffold/src/utils.dart';
import 'package:widget_preview_scaffold/src/widget_preview.dart';
import 'package:widget_preview_scaffold/src/widget_preview_rendering.dart';
import 'package:widget_preview_scaffold/src/widget_preview_scaffold_controller.dart';

import 'utils/widget_preview_scaffold_test_utils.dart';

final class _DualVariantMultiPreview extends MultiPreview {
  const _DualVariantMultiPreview();

  @override
  List<Preview> get previews => const <Preview>[
    Preview(name: 'Variant A', brightness: Brightness.light),
    Preview(name: 'Variant B', brightness: Brightness.dark),
  ];
}

class _ThrowingBuildWidget extends StatelessWidget {
  const _ThrowingBuildWidget({required this.shouldThrow});

  final bool shouldThrow;

  @override
  Widget build(BuildContext context) {
    if (shouldThrow) {
      throw StateError('descendant build failure');
    }
    return const Text('Recovered from build failure');
  }
}

class _ThrowingLayoutWidget extends LeafRenderObjectWidget {
  const _ThrowingLayoutWidget();

  @override
  RenderObject createRenderObject(BuildContext context) => _ThrowingRenderBox();
}

class _ThrowingRenderBox extends RenderBox {
  @override
  void performLayout() {
    throw StateError('custom layout failure');
  }
}

void main() {
  test(
    'canonical preview IDs, @MultiPreview indices, and getPreviews filtering',
    () async {
      final dtdServices = FakeWidgetPreviewScaffoldDtdServices(isWindows: true);
      final WidgetPreview singlePreview = makeTestPreview(
        brightness: Brightness.light,
        column: 5,
        fileStem: 'card',
        functionName: 'cardPreview',
        line: 12,
        name: 'Mobile Light',
        previewFunction: () => const Text('Card'),
        scriptUri: 'file:///c:/proj/lib/card.dart',
        size: const Size(375, 667),
        textScaleFactor: 1.5,
      );
      final List<WidgetPreview> multiPreviews = buildMultiWidgetPreview(
        column: 3,
        functionName: 'cardVariants',
        libraryUri: 'package:my_app/variants.dart',
        line: 30,
        packageName: 'my_app',
        preview: const _DualVariantMultiPreview(),
        previewFunction: () => const Text('Variant'),
        scriptUri: 'file:///C:/proj/lib/variants.dart',
      ).toList();
      final WidgetPreview errorPreview = makeTestErrorPreview(
        dependencyHasErrors: true,
        fileStem: 'broken',
        functionName: 'brokenPreview',
        line: 8,
        scriptUri: 'file:///c:/proj/lib/broken.dart',
      );

      expect(singlePreview.id, 'package:my_app/card.dart::cardPreview');
      expect(singlePreview.multiPreviewIndex, isNull);
      expect(multiPreviews, hasLength(2));
      expect(
        multiPreviews[0].id,
        'package:my_app/variants.dart::cardVariants#0',
      );
      expect(
        multiPreviews[1].id,
        'package:my_app/variants.dart::cardVariants#1',
      );
      expect(errorPreview.id, 'package:my_app/broken.dart::brokenPreview');
      expect(errorPreview.hasError, isTrue);

      final controller = WidgetPreviewScaffoldController(
        dtdServicesOverride: dtdServices,
        previews: () => <WidgetPreview>[
          singlePreview,
          ...multiPreviews,
          errorPreview,
        ],
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      dtdServices.selectedSourceFile.value = TextDocument(
        uriAsString: 'file:///c:/proj/lib/card.dart',
        version: 1,
      );
      controller.updateSearchQuery('nonexistent_query');
      expect(controller.filteredPreviewSetListenable.value, isEmpty);

      final PreviewListResponse all = controller.getPreviews();
      expect(all.previews, hasLength(4));
      expect(
        all.previews.first.toJson(),
        equals(<String, Object?>{
          'id': 'package:my_app/card.dart::cardPreview',
          'libraryUri': 'package:my_app/card.dart',
          'scriptUri': 'file:///c:/proj/lib/card.dart',
          'packageName': 'my_app',
          'functionName': 'cardPreview',
          'multiPreviewIndex': null,
          'line': 12,
          'column': 5,
          'group': 'Default',
          'name': 'Mobile Light',
          'width': 375.0,
          'height': 667.0,
          'textScaleFactor': 1.5,
          'brightness': 'light',
          'hasError': false,
          'errorMessage': null,
        }),
      );
      expect(
        controller.diagnosticsFor(errorPreview),
        equals(<PreviewDiagnostic>[
          const PreviewDiagnostic(
            kind: .compileError,
            phase: .compile,
            summary: 'Dependency of package:my_app/broken.dart has errors!',
          ),
        ]),
      );

      expect(
        controller
            .getPreviews(fileUri: 'package:my_app/variants.dart')
            .previews
            .map((PreviewEntry e) => e.id)
            .toList(),
        equals(<String>[
          'package:my_app/variants.dart::cardVariants#0',
          'package:my_app/variants.dart::cardVariants#1',
        ]),
      );
      expect(
        controller
            .getPreviews(fileUri: 'file:///C%3A/proj/lib/card.dart')
            .previews
            .single
            .id,
        'package:my_app/card.dart::cardPreview',
      );
    },
  );

  testWidgets(
    'captures RenderFlex paint overflow without replacing card with '
    'WidgetPreviewErrorWidget, isolates sibling previews, and resets on rebuild and hot reload',
    (WidgetTester tester) async {
      final overflowWidth = ValueNotifier<double>(148);
      addTearDown(overflowWidth.dispose);

      final WidgetPreviewScaffoldController controller = await pumpTestScaffold(
        tester,
        disableSelectedFileFilter: true,
        previews: () => <WidgetPreview>[
          makeTestPreview(
            fileStem: 'overflow',
            functionName: 'overflowPreview',
            name: 'Overflow Card',
            previewFunction: () => ValueListenableBuilder<double>(
              valueListenable: overflowWidth,
              builder: (BuildContext _, double width, _) => SizedBox(
                width: 100,
                height: 40,
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: width,
                      height: 20,
                      child: const Text('Wide'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          makeTestPreview(
            fileStem: 'healthy',
            functionName: 'healthyPreview',
            line: 20,
            name: 'Healthy Card',
            previewFunction: () =>
                const SizedBox(width: 80, height: 40, child: Text('Healthy')),
          ),
        ],
      );

      expect(
        (tester.takeException()! as FlutterError).message,
        contains('RenderFlex overflowed by 48 pixels on the right'),
      );
      await tester.pump();
      expect(find.byType(WidgetPreviewErrorWidget), findsNothing);
      expect(find.text('Wide'), findsOneWidget);
      expect(find.text('Healthy'), findsOneWidget);

      final List<WidgetPreview> currentPreviews = controller.previews.toList();
      expect(
        controller.diagnosticsFor(currentPreviews[0]),
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
      expect(controller.diagnosticsFor(currentPreviews[1]), isEmpty);

      final PreviewListResponse listWithOverflow = controller.getPreviews();
      expect(listWithOverflow.previews[0].hasError, isTrue);
      expect(
        listWithOverflow.previews[0].errorMessage,
        'A RenderFlex overflowed by 48 pixels on the right.',
      );
      expect(listWithOverflow.previews[1].hasError, isFalse);
      expect(listWithOverflow.previews[1].errorMessage, isNull);

      for (final String query in const <String>['Overflow', 'Healthy', '']) {
        controller.updateSearchQuery(query);
        await tester.pump();
        while (tester.takeException() != null) {}
        final PreviewEntry overflowEntry = controller.getPreviews().previews[0];
        expect(overflowEntry.hasError, isTrue);
        expect(
          overflowEntry.errorMessage,
          'A RenderFlex overflowed by 48 pixels on the right.',
        );
      }

      await tester.tap(find.byType(BrightnessToggleButton).first);
      await tester.pump();
      expect(controller.diagnosticsFor(currentPreviews[0]), hasLength(1));

      overflowWidth.value = 80;
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(controller.diagnosticsFor(currentPreviews[0]), isEmpty);
      expect(controller.getPreviews().previews[0].hasError, isFalse);

      var verticalOverflow = true;
      final WidgetPreviewScaffoldController reloadController =
          await pumpTestScaffold(
            tester,
            disableSelectedFileFilter: true,
            previews: () => <WidgetPreview>[
              makeTestPreview(
                fileStem: 'vertical',
                functionName: 'verticalPreview',
                name: 'Vertical Card',
                previewFunction: () => SizedBox(
                  width: 100,
                  height: 50,
                  child: Column(
                    children: <Widget>[
                      SizedBox(width: 40, height: verticalOverflow ? 75 : 30),
                    ],
                  ),
                ),
              ),
            ],
          );
      expect(tester.takeException(), isA<FlutterError>());
      expect(
        reloadController.diagnosticsFor(reloadController.previews.single),
        equals(<PreviewDiagnostic>[
          const PreviewDiagnostic(
            kind: .overflow,
            overflowAxis: 'vertical',
            overflowPixels: 25.0,
            overflowSide: 'bottom',
            phase: .paint,
            summary: 'A RenderFlex overflowed by 25 pixels on the bottom.',
            targetType: 'RenderFlex',
          ),
        ]),
      );
      expect(reloadController.getPreviews().previews.single.hasError, isTrue);

      verticalOverflow = false;
      reloadController.onHotReload();
      unawaited(tester.binding.reassembleApplication());
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        reloadController.diagnosticsFor(reloadController.previews.single),
        isEmpty,
      );
      expect(reloadController.getPreviews().previews.single.hasError, isFalse);
    },
  );

  testWidgets(
    'captures build and layout diagnostics per preview and resets on rebuild/reassemble',
    (WidgetTester tester) async {
      final shouldFailDescendantBuild = ValueNotifier<bool>(true);
      addTearDown(shouldFailDescendantBuild.dispose);
      var failSyncBuilder = true;
      var failUnconstrainedLayout = true;
      var failCustomLayout = true;

      final WidgetPreviewScaffoldController controller = await pumpTestScaffold(
        tester,
        disableSelectedFileFilter: true,
        viewSize: const Size(1200, 2400),
        previews: () => <WidgetPreview>[
          makeTestPreview(
            fileStem: 'errors',
            functionName: 'syncBuildPreview',
            name: 'Sync Build',
            previewFunction: () => failSyncBuilder
                ? throw ArgumentError('sync previewBuilder boom')
                : const Text('Sync Fixed'),
          ),
          makeTestPreview(
            fileStem: 'errors',
            functionName: 'descendantBuildPreview',
            line: 20,
            name: 'Descendant Build',
            previewFunction: () => ValueListenableBuilder<bool>(
              valueListenable: shouldFailDescendantBuild,
              builder: (BuildContext _, bool shouldThrow, _) =>
                  _ThrowingBuildWidget(shouldThrow: shouldThrow),
            ),
          ),
          makeTestPreview(
            fileStem: 'errors',
            functionName: 'unconstrainedPreview',
            line: 30,
            name: 'Unconstrained Layout',
            previewFunction: () => failUnconstrainedLayout
                ? const SizedBox.expand(child: Text('Infinite'))
                : const SizedBox(width: 60, height: 30, child: Text('Bounded')),
          ),
          makeTestPreview(
            fileStem: 'errors',
            functionName: 'customLayoutPreview',
            line: 40,
            name: 'Custom Layout',
            previewFunction: () => failCustomLayout
                ? const _ThrowingLayoutWidget()
                : const SizedBox(
                    width: 60,
                    height: 30,
                    child: Text('Layout OK'),
                  ),
          ),
        ],
      );
      while (tester.takeException() != null) {}
      await tester.pump();

      final List<WidgetPreview> initialPreviews = controller.previews.toList();
      final expectedSpecs =
          <(int, PreviewDiagnosticPhase, PreviewDiagnosticKind, String?)>[
            (0, .build, .exception, 'sync previewBuilder boom'),
            (1, .build, .exception, 'descendant build failure'),
            (2, .layout, .unconstrained, null),
            (3, .layout, .exception, 'custom layout failure'),
          ];
      for (final (
            int idx,
            PreviewDiagnosticPhase phase,
            PreviewDiagnosticKind kind,
            String? snippet,
          )
          in expectedSpecs) {
        final PreviewDiagnostic diag = controller
            .diagnosticsFor(initialPreviews[idx])
            .single;
        expect(diag.phase, phase);
        expect(diag.kind, kind);
        if (snippet != null) {
          expect(diag.summary, contains(snippet));
        }
      }

      expect(
        controller.getPreviews().previews.every(
          (PreviewEntry e) => e.hasError && e.errorMessage != null,
        ),
        isTrue,
      );
      controller.updateSearchQuery('Unconstrained');
      await tester.pump();
      expect(
        controller.getPreviews().previews.every((PreviewEntry e) => e.hasError),
        isTrue,
      );
      controller.updateSearchQuery('');
      await tester.pump();
      while (tester.takeException() != null) {}
      await tester.pump();

      shouldFailDescendantBuild.value = false;
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(controller.diagnosticsFor(initialPreviews[1]), isEmpty);
      expect(controller.getPreviews().previews[1].hasError, isFalse);
      expect(find.text('Recovered from build failure'), findsOneWidget);

      failSyncBuilder = false;
      failUnconstrainedLayout = false;
      failCustomLayout = false;
      controller.onHotReload();
      unawaited(tester.binding.reassembleApplication());
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(WidgetPreviewErrorWidget), findsNothing);
      expect(
        controller.getPreviews().previews.every(
          (PreviewEntry e) => !e.hasError,
        ),
        isTrue,
      );
    },
  );

  test('PreviewDiagnostic round-trips severity and new kinds', () {
    for (final PreviewDiagnosticKind kind in <PreviewDiagnosticKind>[
      .zeroSize,
      .textTruncated,
      .smallTapTarget,
      .pendingFrame,
    ]) {
      final diagnostic = PreviewDiagnostic(
        kind: kind,
        phase: .layout,
        severity: .warning,
        summary: 'summary-${kind.wireValue}',
      );
      final Map<String, Object?> json = diagnostic.toJson();
      expect(json[PreviewDiagnostic.kSeverity], 'warning');
      expect(PreviewDiagnostic.fromJson(json), equals(diagnostic));
    }

    final PreviewDiagnostic defaulted =
        PreviewDiagnostic.fromJson(const <String, Object?>{
          PreviewDiagnostic.kKind: 'zero_size',
          PreviewDiagnostic.kPhase: 'layout',
          PreviewDiagnostic.kSummary: 'zero',
        });
    expect(defaulted.severity, PreviewDiagnosticSeverity.error);
  });
}

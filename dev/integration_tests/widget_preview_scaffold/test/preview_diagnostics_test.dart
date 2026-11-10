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
      final singlePreview = buildWidgetPreview(
        column: 5,
        functionName: 'cardPreview',
        libraryUri: 'package:my_app/card.dart',
        line: 12,
        packageName: 'my_app',
        previewFunction: () => const Text('Card'),
        scriptUri: 'file:///c:/proj/lib/card.dart',
        transformedPreview: const Preview(
          brightness: Brightness.light,
          name: 'Mobile Light',
          size: Size(375, 667),
          textScaleFactor: 1.5,
        ),
      );
      final multiPreviews = buildMultiWidgetPreview(
        column: 3,
        functionName: 'cardVariants',
        libraryUri: 'package:my_app/variants.dart',
        line: 30,
        packageName: 'my_app',
        preview: const _DualVariantMultiPreview(),
        previewFunction: () => const Text('Variant'),
        scriptUri: 'file:///C:/proj/lib/variants.dart',
      ).toList();
      final errorPreview = buildWidgetPreviewError(
        column: 1,
        dependencyHasErrors: true,
        functionName: 'brokenPreview',
        libraryUri: 'package:my_app/broken.dart',
        line: 8,
        packageName: 'my_app',
        scriptUri: 'file:///c:/proj/lib/broken.dart',
      );

      expect(singlePreview.id, 'package:my_app/card.dart::cardPreview');
      expect(singlePreview.multiPreviewIndex, isNull);
      expect(multiPreviews, hasLength(2));
      expect(multiPreviews[0].multiPreviewIndex, 0);
      expect(
        multiPreviews[0].id,
        'package:my_app/variants.dart::cardVariants#0',
      );
      expect(multiPreviews[1].multiPreviewIndex, 1);
      expect(
        multiPreviews[1].id,
        'package:my_app/variants.dart::cardVariants#1',
      );
      expect(errorPreview.id, 'package:my_app/broken.dart::brokenPreview');
      expect(errorPreview.hasError, isTrue);
      expect(
        errorPreview.errorMessage,
        'Dependency of package:my_app/broken.dart has errors!',
      );

      final controller = WidgetPreviewScaffoldController(
        dtdServicesOverride: dtdServices,
        previews: () => <WidgetPreview>[
          singlePreview,
          ...multiPreviews,
          errorPreview,
        ],
      );
      await controller.initialize();

      // Restrict UI filter to only card.dart and set a search query; getPreviews
      // must ignore both UI filters and return all unfiltered previews.
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

      // Filter by libraryUri.
      final PreviewListResponse byPackage = controller.getPreviews(
        fileUri: 'package:my_app/variants.dart',
      );
      expect(
        byPackage.previews.map((PreviewEntry e) => e.id).toList(),
        equals(<String>[
          'package:my_app/variants.dart::cardVariants#0',
          'package:my_app/variants.dart::cardVariants#1',
        ]),
      );

      // Filter by Windows encoded file:// URI with differing drive-letter case.
      final PreviewListResponse byEncodedScript = controller.getPreviews(
        fileUri: 'file:///C%3A/proj/lib/card.dart',
      );
      expect(byEncodedScript.previews, hasLength(1));
      expect(
        byEncodedScript.previews.single.id,
        'package:my_app/card.dart::cardPreview',
      );
    },
  );

  testWidgets('captures RenderFlex paint overflow without replacing card with '
      'WidgetPreviewErrorWidget, isolates sibling previews, and resets on rebuild and hot reload', (
    tester,
  ) async {
    final overflowWidth = ValueNotifier<double>(148);
    addTearDown(overflowWidth.dispose);

    final fakeDtdServices = FakeWidgetPreviewScaffoldDtdServices();
    // Construct fresh WidgetPreview instances inside the callback just as
    // generated_preview.dart's `previews()` function does on every call.
    final controller = WidgetPreviewScaffoldController(
      dtdServicesOverride: fakeDtdServices,
      previews: () => <WidgetPreview>[
        buildWidgetPreview(
          column: 1,
          functionName: 'overflowPreview',
          libraryUri: 'package:my_app/overflow.dart',
          line: 10,
          packageName: 'my_app',
          previewFunction: () => ValueListenableBuilder<double>(
            valueListenable: overflowWidth,
            builder: (context, width, _) => SizedBox(
              width: 100,
              height: 40,
              child: Row(
                children: <Widget>[
                  SizedBox(width: width, height: 20, child: const Text('Wide')),
                ],
              ),
            ),
          ),
          scriptUri: 'file:///project/lib/overflow.dart',
          transformedPreview: const Preview(name: 'Overflow Card').transform(),
        ),
        buildWidgetPreview(
          column: 1,
          functionName: 'healthyPreview',
          libraryUri: 'package:my_app/healthy.dart',
          line: 20,
          packageName: 'my_app',
          previewFunction: () =>
              const SizedBox(width: 80, height: 40, child: Text('Healthy')),
          scriptUri: 'file:///project/lib/healthy.dart',
          transformedPreview: const Preview(name: 'Healthy Card').transform(),
        ),
      ],
    );
    if (controller.filterBySelectedFileListenable.value) {
      await controller.toggleFilterBySelectedFile();
    }
    await controller.initialize();

    await tester.pumpWidget(TestWidgetPreviewScaffold(controller: controller));

    final Object? overflowException = tester.takeException();
    expect(overflowException, isA<FlutterError>());
    expect(
      (overflowException! as FlutterError).message,
      contains('RenderFlex overflowed by 48 pixels on the right'),
    );

    // Paint overflow MUST NOT swap in WidgetPreviewErrorWidget, even on subsequent frames.
    await tester.pump();
    expect(find.byType(WidgetPreviewErrorWidget), findsNothing);
    expect(find.text('Wide'), findsOneWidget);
    expect(find.text('Healthy'), findsOneWidget);

    final List<WidgetPreview> currentPreviews = controller.previews.toList();
    final WidgetPreview overflowingPreview = currentPreviews[0];
    final WidgetPreview healthyPreview = currentPreviews[1];

    final List<PreviewDiagnostic> overflowDiags = controller.diagnosticsFor(
      overflowingPreview,
    );
    expect(
      overflowDiags,
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
    // Sibling healthy preview has zero diagnostics.
    expect(controller.diagnosticsFor(healthyPreview), isEmpty);

    final PreviewListResponse listWithOverflow = controller.getPreviews();
    expect(listWithOverflow.previews[0].hasError, isTrue);
    expect(
      listWithOverflow.previews[0].errorMessage,
      'A RenderFlex overflowed by 48 pixels on the right.',
    );
    expect(listWithOverflow.previews[1].hasError, isFalse);
    expect(listWithOverflow.previews[1].errorMessage, isNull);

    // Filtering via updateSearchQuery (both matching and hiding the card) must not
    // allocate fresh WidgetPreview instances or wipe captured runtime diagnostics.
    controller.updateSearchQuery('Overflow');
    await tester.pump();
    expect(controller.getPreviews().previews[0].hasError, isTrue);
    expect(
      controller.getPreviews().previews[0].errorMessage,
      'A RenderFlex overflowed by 48 pixels on the right.',
    );

    controller.updateSearchQuery('Healthy');
    await tester.pump();
    expect(controller.getPreviews().previews[0].hasError, isTrue);
    expect(
      controller.getPreviews().previews[0].errorMessage,
      'A RenderFlex overflowed by 48 pixels on the right.',
    );

    controller.updateSearchQuery('');
    await tester.pump();
    while (tester.takeException() != null) {}
    expect(controller.getPreviews().previews[0].hasError, isTrue);

    // Unrelated card brightness toggle while still overflowing retains the diagnostic.
    await tester.tap(find.byType(BrightnessToggleButton).first);
    await tester.pump();
    expect(controller.diagnosticsFor(overflowingPreview), hasLength(1));

    // Fixing the overflow via ValueNotifier rebuild clears the diagnostic without hot reload.
    overflowWidth.value = 80;
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(controller.diagnosticsFor(overflowingPreview), isEmpty);
    expect(controller.getPreviews().previews[0].hasError, isFalse);

    // Re-introduce a vertical overflow on hot reload (reassemble), then fix on a second reload.
    var verticalOverflow = true;
    final reloadController = WidgetPreviewScaffoldController(
      dtdServicesOverride: fakeDtdServices,
      previews: () => <WidgetPreview>[
        buildWidgetPreview(
          column: 1,
          functionName: 'verticalPreview',
          libraryUri: 'package:my_app/vertical.dart',
          line: 30,
          packageName: 'my_app',
          previewFunction: () => SizedBox(
            width: 100,
            height: 50,
            child: Column(
              children: <Widget>[
                SizedBox(width: 40, height: verticalOverflow ? 75 : 30),
              ],
            ),
          ),
          scriptUri: 'file:///project/lib/vertical.dart',
          transformedPreview: const Preview(name: 'Vertical Card').transform(),
        ),
      ],
    );
    if (reloadController.filterBySelectedFileListenable.value) {
      await reloadController.toggleFilterBySelectedFile();
    }
    await reloadController.initialize();

    await tester.pumpWidget(
      TestWidgetPreviewScaffold(controller: reloadController),
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
  });

  testWidgets(
    'captures build and layout diagnostics per preview and resets on rebuild/reassemble',
    (tester) async {
      final shouldFailDescendantBuild = ValueNotifier<bool>(true);
      addTearDown(shouldFailDescendantBuild.dispose);
      var failSyncBuilder = true;
      var failUnconstrainedLayout = true;
      var failCustomLayout = true;

      final fakeDtdServices = FakeWidgetPreviewScaffoldDtdServices();
      final controller = WidgetPreviewScaffoldController(
        dtdServicesOverride: fakeDtdServices,
        previews: () => <WidgetPreview>[
          buildWidgetPreview(
            column: 1,
            functionName: 'syncBuildPreview',
            libraryUri: 'package:my_app/errors.dart',
            line: 10,
            packageName: 'my_app',
            previewFunction: () => failSyncBuilder
                ? throw ArgumentError('sync previewBuilder boom')
                : const Text('Sync Fixed'),
            scriptUri: 'file:///project/lib/errors.dart',
            transformedPreview: const Preview(name: 'Sync Build').transform(),
          ),
          buildWidgetPreview(
            column: 1,
            functionName: 'descendantBuildPreview',
            libraryUri: 'package:my_app/errors.dart',
            line: 20,
            packageName: 'my_app',
            previewFunction: () => ValueListenableBuilder<bool>(
              valueListenable: shouldFailDescendantBuild,
              builder: (context, shouldThrow, _) =>
                  _ThrowingBuildWidget(shouldThrow: shouldThrow),
            ),
            scriptUri: 'file:///project/lib/errors.dart',
            transformedPreview: const Preview(
              name: 'Descendant Build',
            ).transform(),
          ),
          buildWidgetPreview(
            column: 1,
            functionName: 'unconstrainedPreview',
            libraryUri: 'package:my_app/errors.dart',
            line: 30,
            packageName: 'my_app',
            previewFunction: () => failUnconstrainedLayout
                ? const SizedBox.expand(child: Text('Infinite'))
                : const SizedBox(width: 60, height: 30, child: Text('Bounded')),
            scriptUri: 'file:///project/lib/errors.dart',
            transformedPreview: const Preview(
              name: 'Unconstrained Layout',
            ).transform(),
          ),
          buildWidgetPreview(
            column: 1,
            functionName: 'customLayoutPreview',
            libraryUri: 'package:my_app/errors.dart',
            line: 40,
            packageName: 'my_app',
            previewFunction: () => failCustomLayout
                ? const _ThrowingLayoutWidget()
                : const SizedBox(
                    width: 60,
                    height: 30,
                    child: Text('Layout OK'),
                  ),
            scriptUri: 'file:///project/lib/errors.dart',
            transformedPreview: const Preview(
              name: 'Custom Layout',
            ).transform(),
          ),
        ],
      );
      if (controller.filterBySelectedFileListenable.value) {
        await controller.toggleFilterBySelectedFile();
      }
      await controller.initialize();

      // Increase surface height so ListView builds all 4 preview cards.
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: controller),
      );
      // Drain the three framework-reported exceptions (descendant build,
      // unconstrained layout, custom layout).
      while (tester.takeException() != null) {}
      await tester.pump();

      final List<WidgetPreview> initialPreviews = controller.previews.toList();
      final List<PreviewDiagnostic> syncDiags = controller.diagnosticsFor(
        initialPreviews[0],
      );
      expect(syncDiags, hasLength(1));
      expect(syncDiags.single.phase, PreviewDiagnosticPhase.build);
      expect(syncDiags.single.kind, PreviewDiagnosticKind.exception);
      expect(syncDiags.single.summary, contains('sync previewBuilder boom'));

      final List<PreviewDiagnostic> descendantDiags = controller.diagnosticsFor(
        initialPreviews[1],
      );
      expect(descendantDiags, hasLength(1));
      expect(descendantDiags.single.phase, PreviewDiagnosticPhase.build);
      expect(descendantDiags.single.kind, PreviewDiagnosticKind.exception);
      expect(
        descendantDiags.single.summary,
        contains('descendant build failure'),
      );

      final List<PreviewDiagnostic> unconstrainedDiags = controller
          .diagnosticsFor(initialPreviews[2]);
      expect(unconstrainedDiags, hasLength(1));
      expect(unconstrainedDiags.single.phase, PreviewDiagnosticPhase.layout);
      expect(
        unconstrainedDiags.single.kind,
        PreviewDiagnosticKind.unconstrained,
      );

      final List<PreviewDiagnostic> customLayoutDiags = controller
          .diagnosticsFor(initialPreviews[3]);
      expect(customLayoutDiags, hasLength(1));
      expect(customLayoutDiags.single.phase, PreviewDiagnosticPhase.layout);
      expect(customLayoutDiags.single.kind, PreviewDiagnosticKind.exception);
      expect(
        customLayoutDiags.single.summary,
        contains('custom layout failure'),
      );

      // Verify getPreviews() reports hasError: true for all 4 runtime-failing cards,
      // and retains layout/build errors across updateSearchQuery().
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

      // Fix descendant build via ValueNotifier rebuild (without reassemble).
      shouldFailDescendantBuild.value = false;
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(controller.diagnosticsFor(initialPreviews[1]), isEmpty);
      expect(controller.getPreviews().previews[1].hasError, isFalse);
      expect(find.text('Recovered from build failure'), findsOneWidget);

      // Fix remaining sync build and layout errors and perform hot reload (reassemble).
      failSyncBuilder = false;
      failUnconstrainedLayout = false;
      failCustomLayout = false;
      controller.onHotReload();
      unawaited(tester.binding.reassembleApplication());
      await tester.pump();

      expect(tester.takeException(), isNull);
      final List<WidgetPreview> reloadedPreviews = controller.previews.toList();
      expect(controller.diagnosticsFor(reloadedPreviews[0]), isEmpty);
      expect(controller.diagnosticsFor(reloadedPreviews[2]), isEmpty);
      expect(controller.diagnosticsFor(reloadedPreviews[3]), isEmpty);
      expect(find.byType(WidgetPreviewErrorWidget), findsNothing);
      expect(
        controller.getPreviews().previews.every(
          (PreviewEntry e) => !e.hasError,
        ),
        isTrue,
      );
    },
  );
}

// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/widget_previews.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widget_preview_scaffold/src/controls.dart';
import 'package:widget_preview_scaffold/src/widget_preview.dart';
import 'package:widget_preview_scaffold/src/widget_preview_rendering.dart'
    hide PreviewWidget;
import 'package:widget_preview_scaffold/src/widget_preview_scaffold_controller.dart';

import 'utils/widget_preview_scaffold_test_utils.dart';

void main() {
  testWidgets(
    'Help message is displayed with link to documentation when no previews are detected',
    (WidgetTester tester) async {
      final currentPreviews = <WidgetPreview>[];
      final WidgetPreviewScaffoldController controller = await pumpTestScaffold(
        tester,
        disableSelectedFileFilter: true,
        previews: () => currentPreviews,
      );

      final Finder noPreviewDetectedFinder = find.byType(
        NoPreviewsDetectedWidget,
      );
      final Finder groupFinder = find.byType(WidgetPreviewGroupWidget);
      final Finder previewFinder = find.byType(WidgetPreviewWidget);
      final Finder docUrlFinder = find.text(
        NoPreviewsDetectedWidget.documentationUrl.toString(),
      );

      expect(noPreviewDetectedFinder, findsOne);
      expect(docUrlFinder, findsOne);
      expect(groupFinder, findsNothing);
      expect(previewFinder, findsNothing);

      currentPreviews.add(
        WidgetPreview.test(
          builder: () => const Text('Foo'),
          previewData: const Preview(),
        ),
      );
      controller.onHotReload();
      await tester.pumpWidget(
        TestWidgetPreviewScaffold(controller: controller),
      );

      expect(noPreviewDetectedFinder, findsNothing);
      expect(docUrlFinder, findsNothing);
      expect(previewFinder, findsOne);
      expect(groupFinder, findsOne);
    },
  );

  testWidgets(
    'StarterPreviewSnippetCard copies starter @Preview snippet to clipboard',
    (WidgetTester tester) async {
      final ValueGetter<String?> readCopied = mockClipboardCapture(tester);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: NoPreviewsDetectedWidget())),
      );
      await tester.tap(find.byKey(const Key('copy-starter-preview-snippet')));
      await tester.pump();

      expect(readCopied(), equals(kStarterPreviewSnippet));
      expect(find.text('Copied!'), findsOneWidget);
    },
  );
}

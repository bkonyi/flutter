// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widget_preview_scaffold/src/dtd/dtd_services.dart';
import 'package:widget_preview_scaffold/src/dtd/editor_service.dart';
import 'package:widget_preview_scaffold/src/theme/ide_theme.dart';
import 'package:widget_preview_scaffold/src/utils.dart';
import 'package:widget_preview_scaffold/src/utils/url/url.dart';
import 'package:widget_preview_scaffold/src/widget_preview.dart';
import 'package:widget_preview_scaffold/src/widget_preview_rendering.dart';
import 'package:widget_preview_scaffold/src/widget_preview_scaffold_controller.dart';

WidgetPreview makeTestPreview({
  required String functionName,
  required Object? Function() previewFunction,
  Brightness? brightness,
  int column = 1,
  PreviewLocalizationsData Function()? defaultLocalizations,
  String? fileStem,
  String group = 'Default',
  String? libraryUri,
  int line = 10,
  PreviewLocalizationsData Function()? localizations,
  String? name,
  String packageName = 'my_app',
  Preview? rawPreview,
  String? scriptUri,
  Size? size,
  double? textScaleFactor,
  PreviewThemeData Function()? theme,
  Widget Function(Widget)? wrapper,
}) {
  final String stem = fileStem ?? functionName;
  final Preview preview =
      rawPreview ??
      Preview(
        brightness: brightness,
        group: group,
        localizations: localizations,
        name: name,
        size: size,
        textScaleFactor: textScaleFactor,
        theme: theme,
        wrapper: wrapper,
      );
  return buildWidgetPreview(
    column: column,
    defaultLocalizations: defaultLocalizations,
    functionName: functionName,
    libraryUri: libraryUri ?? 'package:$packageName/$stem.dart',
    line: line,
    packageName: packageName,
    previewFunction: previewFunction,
    scriptUri: scriptUri ?? 'file:///project/lib/$stem.dart',
    transformedPreview: preview.transform(),
  );
}

WidgetPreview makeTestErrorPreview({
  required String functionName,
  int column = 1,
  bool dependencyHasErrors = false,
  String? errorMessage,
  String? fileStem,
  String? libraryUri,
  int line = 10,
  String packageName = 'my_app',
  String? scriptUri,
}) {
  final String stem = fileStem ?? functionName;
  return buildWidgetPreviewError(
    column: column,
    dependencyHasErrors: dependencyHasErrors,
    errorMessage: errorMessage,
    functionName: functionName,
    libraryUri: libraryUri ?? 'package:$packageName/$stem.dart',
    line: line,
    packageName: packageName,
    scriptUri: scriptUri ?? 'file:///project/lib/$stem.dart',
  );
}

Future<WidgetPreviewScaffoldController> pumpTestScaffold(
  WidgetTester tester, {
  required PreviewsCallback previews,
  Uri? baseUri,
  bool disableSelectedFileFilter = false,
  FakeWidgetPreviewScaffoldDtdServices? dtdServices,
  String? fragment,
  IdeTheme? ideTheme,
  bool settle = false,
  Duration? stageFrameTimeout,
  Duration? stageHostTimeout,
  Size? viewSize,
}) async {
  if (viewSize != null) {
    tester.view.physicalSize = viewSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }
  if (fragment != null) {
    debugSetUrlFragment(fragment, baseUri: baseUri);
  }
  final controller = WidgetPreviewScaffoldController(
    dtdServicesOverride: dtdServices ?? FakeWidgetPreviewScaffoldDtdServices(),
    previews: previews,
    stageFrameTimeout: stageFrameTimeout ?? const Duration(seconds: 5),
    stageHostTimeout: stageHostTimeout ?? const Duration(seconds: 10),
  );
  addTearDown(controller.dispose);
  if (disableSelectedFileFilter &&
      controller.filterBySelectedFileListenable.value) {
    await controller.toggleFilterBySelectedFile();
  }
  await controller.initialize();
  await tester.pumpWidget(
    ideTheme == null
        ? TestWidgetPreviewScaffold(controller: controller)
        : WidgetPreviewScaffold(
            controller: controller,
            enableWebView: false,
            ideTheme: ideTheme,
          ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return controller;
}

ValueGetter<String?> mockClipboardCapture(WidgetTester tester) {
  String? copied;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments! as Map<Object?, Object?>;
        copied = args['text'] as String?;
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
  return () => copied;
}

Future<void> dragBetweenGlobal(
  WidgetTester tester, {
  required Offset end,
  required Offset start,
  int pointerId = 1,
}) async {
  final TestGesture gesture = await tester.startGesture(
    start,
    pointer: pointerId,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveBy((end - start) / 2.0);
  await tester.pump();
  await gesture.moveTo(end);
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

class WidgetPreviewerWidgetScaffolding extends StatelessWidget {
  WidgetPreviewerWidgetScaffolding({
    super.key,
    this.platformBrightness = Brightness.light,
    required this.child,
  }) {
    WidgetsBinding.instance.debugExcludeRootWidgetInspector = true;
  }

  final Brightness platformBrightness;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(platformBrightness: platformBrightness),
      child: WidgetsApp(
        color: Colors.blue,
        home: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return WidgetPreviewerWindowConstraints(
              constraints: constraints,
              child: child,
            );
          },
        ),
        pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
            PageRouteBuilder<T>(
              settings: settings,
              pageBuilder:
                  (
                    BuildContext context,
                    Animation<double> animation,
                    Animation<double> secondaryAnimation,
                  ) => builder(context),
            ),
      ),
    );
  }
}

class FakeWidgetPreviewScaffoldDtdServices extends Fake
    implements WidgetPreviewScaffoldDtdServices {
  FakeWidgetPreviewScaffoldDtdServices({this.isWindows = false});

  final navigationEvents = <CodeLocation>[];
  final preferences = <String, Object?>{};

  @override
  PreviewListResponse Function({String? fileUri})? onGetPreviews;

  @override
  Future<CapturePreviewResponse> Function(PreviewCaptureRequest request)?
  onCapturePreview;

  @override
  FutureOr<void> Function()? onInPlaceHotReload;

  Uri? lastConnectDtdUri;
  bool? lastConnectReadOnly;

  @override
  Future<void> connect({Uri? dtdUri, bool readOnly = false}) async {
    lastConnectDtdUri = dtdUri;
    lastConnectReadOnly = readOnly;
  }

  @override
  Future<void> dispose() async {
    if (!(lastConnectReadOnly ?? false)) {
      selectedSourceFile.dispose();
      editorServiceAvailable.dispose();
      editorTheme.dispose();
    }
  }

  bool hotRestartInvoked = false;
  var syncViewerReloadCount = 0;

  @override
  Future<void> hotRestartPreviewer() async {
    hotRestartInvoked = true;
  }

  @override
  Future<void> syncViewerReload() async {
    syncViewerReloadCount++;
  }

  @override
  Future<Uri?> resolveUri(Uri uri) async => uri;

  @override
  final bool isWindows;

  @override
  final ValueNotifier<TextDocument?> selectedSourceFile =
      ValueNotifier<TextDocument?>(null);

  @override
  final ValueNotifier<bool> editorServiceAvailable = ValueNotifier<bool>(true);

  @override
  final ValueNotifier<EditorTheme?> editorTheme = ValueNotifier<EditorTheme?>(
    null,
  );

  @override
  Future<void> navigateToCode(CodeLocation location) async {
    navigationEvents.add(location);
  }

  @override
  Future<bool> getFlag(String flag, {bool defaultValue = true}) async =>
      preferences[flag] as bool? ?? defaultValue;

  @override
  Future<void> setPreference(String key, Object? value) async {
    if (value == null) {
      preferences.remove(key);
      return;
    }
    preferences[key] = value;
  }

  @override
  Future<Uri> getDevToolsUri() async => Uri();
}

class TestWidgetPreviewScaffold extends WidgetPreviewScaffold {
  const TestWidgetPreviewScaffold({super.key, required super.controller})
    : super(enableWebView: false);
}

class FakeWidgetPreviewScaffoldController
    extends WidgetPreviewScaffoldController {
  FakeWidgetPreviewScaffoldController({
    WidgetPreviewScaffoldDtdServices? dtdServicesOverride,
    List<WidgetPreview>? previews,
  }) : super(
         previews: () => previews ?? <WidgetPreview>[],
         dtdServicesOverride:
             dtdServicesOverride ?? FakeWidgetPreviewScaffoldDtdServices(),
       );

  @override
  final ValueNotifier<String> searchQueryListenable = ValueNotifier<String>('');

  @override
  void updateSearchQuery(String query) {
    searchQueryListenable.value = query;
  }

  @override
  final ValueNotifier<bool> searchByGroupNameListenable = ValueNotifier<bool>(
    true,
  );

  @override
  bool toggleSearchByGroupName() {
    searchByGroupNameListenable.value = !searchByGroupNameListenable.value;
    return true;
  }

  @override
  final ValueNotifier<bool> searchByPreviewNameListenable = ValueNotifier<bool>(
    true,
  );

  @override
  bool toggleSearchByPreviewName() {
    searchByPreviewNameListenable.value = !searchByPreviewNameListenable.value;
    return true;
  }

  @override
  final ValueNotifier<bool> searchByContainingScriptListenable =
      ValueNotifier<bool>(true);

  @override
  bool toggleSearchByContainingScript() {
    searchByContainingScriptListenable.value =
        !searchByContainingScriptListenable.value;
    return true;
  }

  @override
  final ValueNotifier<bool> searchByContainingPackageListenable =
      ValueNotifier<bool>(true);

  @override
  bool toggleSearchByContainingPackage() {
    searchByContainingPackageListenable.value =
        !searchByContainingPackageListenable.value;
    return true;
  }
}

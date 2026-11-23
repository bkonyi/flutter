// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/widget_previews.dart';
import 'package:material_ui/material_ui.dart';

import 'widget_preview.dart';

const kInvalidPreviewsGroupName = 'Invalid Previews';

Iterable<WidgetPreview> buildMultiWidgetPreview({
  required int column,
  required String functionName,
  required String libraryUri,
  required int line,
  required String packageName,
  required MultiPreview preview,
  required Object? Function() previewFunction,
  required String scriptUri,
  PreviewLocalizationsData Function()? defaultLocalizations,
  String? errorMessage,
  bool hasError = false,
}) {
  return <WidgetPreview>[
    for (final (int index, Preview transformedPreview)
        in preview.transform().indexed)
      buildWidgetPreview(
        column: column,
        defaultLocalizations: defaultLocalizations,
        errorMessage: errorMessage,
        functionName: functionName,
        hasError: hasError,
        libraryUri: libraryUri,
        line: line,
        multiPreviewIndex: index,
        packageName: packageName,
        previewFunction: previewFunction,
        scriptUri: scriptUri,
        transformedPreview: transformedPreview,
      ),
  ];
}

WidgetPreview buildWidgetPreview({
  required int column,
  required String functionName,
  required String libraryUri,
  required int line,
  required String packageName,
  required Object? Function() previewFunction,
  required String scriptUri,
  required Preview transformedPreview,
  PreviewLocalizationsData Function()? defaultLocalizations,
  String? errorMessage,
  bool hasError = false,
  int? multiPreviewIndex,
}) {
  Widget Function() previewBuilder;
  if (previewFunction is WidgetBuilder Function()) {
    previewBuilder = () {
      return Builder(builder: previewFunction());
    };
  } else {
    previewBuilder = previewFunction as Widget Function();
  }
  return WidgetPreview(
    builder: previewBuilder,
    column: column,
    defaultLocalizations: defaultLocalizations,
    errorMessage: errorMessage,
    functionName: functionName,
    hasError: hasError,
    libraryUri: libraryUri,
    line: line,
    multiPreviewIndex: multiPreviewIndex,
    packageName: packageName,
    previewData: transformedPreview,
    scriptUri: scriptUri,
  );
}

WidgetPreview buildWidgetPreviewError({
  required int column,
  required bool dependencyHasErrors,
  required String functionName,
  required String libraryUri,
  required int line,
  required String packageName,
  required String scriptUri,
  String? errorMessage,
  bool hasError = true,
}) {
  var resolvedErrorMessage = errorMessage ?? '$libraryUri has errors!';
  if (errorMessage == null && dependencyHasErrors) {
    resolvedErrorMessage = 'Dependency of $resolvedErrorMessage';
  }
  return WidgetPreview(
    builder: () => Text('$functionName: $resolvedErrorMessage'),
    column: column,
    errorMessage: resolvedErrorMessage,
    functionName: functionName,
    hasError: hasError,
    libraryUri: libraryUri,
    line: line,
    packageName: packageName,
    previewData: const Preview(group: kInvalidPreviewsGroupName),
    scriptUri: scriptUri,
  );
}

/// A basic vertical spacer.
class VerticalSpacer extends StatelessWidget {
  /// Creates a basic vertical spacer.
  const VerticalSpacer({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 10);
  }
}

/// A basic horizontal spacer.
class HorizontalSpacer extends StatelessWidget {
  /// Creates a basic vertical spacer.
  const HorizontalSpacer({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 10);
  }
}

/// A widget that explicitly responds to hot reload events.
///
/// Hot reload will always result in [reassemble] being called.
class HotReloadListener extends StatefulWidget {
  const HotReloadListener({
    super.key,
    required this.onHotReload,
    required this.child,
  });

  final VoidCallback onHotReload;
  final Widget child;

  @override
  HotReloadListenerState createState() => HotReloadListenerState();
}

class HotReloadListenerState extends State<HotReloadListener> {
  @override
  void reassemble() {
    super.reassemble();
    widget.onHotReload();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Wraps [child] in a border with default styling.
///
/// This border can optionally be made non-uniform by setting any of
/// [showTop], [showBottom], [showLeft] or [showRight] to false.
///
/// Originally from DevTools.
final class OutlineDecoration extends StatelessWidget {
  const OutlineDecoration({
    super.key,
    this.child,
    this.showTop = true,
    this.showBottom = true,
    this.showLeft = true,
    this.showRight = true,
  });

  factory OutlineDecoration.onlyBottom({required Widget? child}) =>
      OutlineDecoration(
        showTop: false,
        showLeft: false,
        showRight: false,
        child: child,
      );

  factory OutlineDecoration.onlyTop({required Widget? child}) =>
      OutlineDecoration(
        showBottom: false,
        showLeft: false,
        showRight: false,
        child: child,
      );

  factory OutlineDecoration.onlyLeft({required Widget? child}) =>
      OutlineDecoration(
        showBottom: false,
        showTop: false,
        showRight: false,
        child: child,
      );

  factory OutlineDecoration.onlyRight({required Widget? child}) =>
      OutlineDecoration(
        showBottom: false,
        showTop: false,
        showLeft: false,
        child: child,
      );

  final bool showTop;
  final bool showBottom;
  final bool showLeft;
  final bool showRight;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).focusColor;
    final border = BorderSide(color: color);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: showLeft ? border : BorderSide.none,
          right: showRight ? border : BorderSide.none,
          top: showTop ? border : BorderSide.none,
          bottom: showBottom ? border : BorderSide.none,
        ),
      ),
      child: child,
    );
  }
}

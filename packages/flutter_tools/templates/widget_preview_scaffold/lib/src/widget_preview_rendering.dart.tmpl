// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert'
    show base64Decode, base64Encode, jsonDecode, jsonEncode, utf8;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:json_rpc_2/json_rpc_2.dart';

import 'package:material_ui/material_ui.dart';
import 'package:stack_trace/stack_trace.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:widget_preview_scaffold/src/dtd/dtd_services.dart';
import 'package:widget_preview_scaffold/src/dtd/editor_service.dart';
import 'package:widget_preview_scaffold/src/split.dart';
import 'package:widget_preview_scaffold/src/theme/ide_theme.dart';
import 'package:widget_preview_scaffold/src/theme/theme.dart';

import 'package:widget_preview_scaffold/src/controls.dart';
import 'package:widget_preview_scaffold/src/embed_preview.dart';
import 'package:widget_preview_scaffold/src/generated_preview.dart';
import 'package:widget_preview_scaffold/src/utils.dart';
import 'package:widget_preview_scaffold/src/utils/url/url.dart';
import 'package:widget_preview_scaffold/src/widget_preview.dart';
import 'package:widget_preview_scaffold/src/widget_preview_inspector_service.dart';
import 'package:widget_preview_scaffold/src/widget_preview_scaffold_controller.dart';

/// Displayed when an unhandled exception is thrown when initializing the widget
/// tree for a preview (i.e., before the build phase).
///
/// Provides users with details about the thrown exception, including the exception
/// contents and a scrollable stack trace.
class WidgetPreviewErrorWidget extends StatelessWidget {
  WidgetPreviewErrorWidget({
    super.key,
    required this.controller,
    required this.error,
    required this.size,
    required StackTrace stackTrace,
    this.title = 'Failed to initialize widget tree: ',
  }) : trace = Trace.from(stackTrace).terse;

  final WidgetPreviewScaffoldController controller;

  /// The [Object] that was thrown, resulting in an unhandled exception.
  final Object error;

  /// The size of the error widget.
  final Size size;

  /// The stack trace identifying where [error] was thrown from.
  final Trace trace;

  /// The title displayed before the error message.
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: size.height,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: title, style: theme.boldTextStyle),
                  TextSpan(text: error.toString(), style: theme.fixedFontStyle),
                ],
              ),
            ),
            Text('Stacktrace:', style: theme.boldTextStyle),
            ValueListenableBuilder(
              valueListenable: controller.editorServiceAvailable,
              builder: (context, editorServiceAvailable, child) {
                return SelectableText.rich(
                  TextSpan(
                    children: _formatFrames(
                      theme,
                      trace.frames,
                      editorServiceAvailable,
                    ),
                    style: theme.fixedFontStyle,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  List<TextSpan> _formatFrames(
    ThemeData theme,
    List<Frame> frames,
    bool editorServiceAvailable,
  ) {
    // Figure out the longest path so we know how much to pad.
    final int longest = frames
        .map((frame) => frame.location.length)
        .fold(0, math.max);

    // Print out the stack trace nicely formatted.
    return frames.map<TextSpan>((frame) {
      if (frame is UnparsedFrame) return TextSpan(text: '$frame\n');
      // The Editor.navigateToCode service can't handle Dart core library paths,
      // so don't allow for navigation to them. Also disable navigation if the
      // Editor service isn't available.
      final isLinkable =
          (frame.uri.isScheme('file') || frame.uri.isScheme('package')) &&
          editorServiceAvailable;
      final style = isLinkable
          ? theme.fixedFontLinkStyle
          : theme.fixedFontStyle;
      return TextSpan(
        children: [
          TextSpan(
            text: frame.location,
            style: style,
            recognizer: isLinkable
                ? (TapGestureRecognizer()
                    ..onTap = () async {
                      final resolvedUri = await controller.dtdServices
                          .resolveUri(frame.uri);
                      controller.dtdServices.navigateToCode(
                        CodeLocation(
                          uri: resolvedUri.toString(),
                          line: frame.line,
                          column: frame.column,
                        ),
                      );
                    })
                : null,
          ),
          TextSpan(text: ' ' * (longest - frame.location.length)),
          const TextSpan(text: '  '),
          TextSpan(text: '${frame.member}\n', style: style),
        ],
      );
    }).toList();
  }
}

/// Displayed when no @Preview() annotations are detected in the project.
///
/// Links to documentation.
class NoPreviewsDetectedWidget extends StatelessWidget {
  const NoPreviewsDetectedWidget({super.key});

  static Uri documentationUrl = Uri.https('flutter.dev', 'to/widget-previews');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        children: [
          Text('No previews detected', style: theme.boldTextStyle),
          const VerticalSpacer(),
          Text('Read more about getting started with widget previews at:'),
          Text.rich(
            TextSpan(
              text: documentationUrl.toString(),
              style: theme.linkTextStyle,
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  launchUrl(documentationUrl);
                },
            ),
          ),
          const StarterPreviewSnippetCard(),
        ],
      ),
    );
  }
}

/// A wrapper that serves as the root entry for a single preview in the widget inspector.
class PreviewWidget extends StatelessWidget {
  const PreviewWidget({
    super.key,
    required this.preview,
    required this.child,
    this.onDiagnostic,
    this.suppressFrameworkErrorForwarding = false,
  });

  final WidgetPreview preview;
  final Widget child;
  final ValueChanged<PreviewDiagnostic>? onDiagnostic;
  final bool suppressFrameworkErrorForwarding;

  @override
  StatelessElement createElement() => PreviewWidgetElement(this);

  @override
  Widget build(BuildContext context) {
    return child;
  }

  @override
  String toStringShort() {
    final StringBuffer buffer = StringBuffer(
      '@${preview.previewData.runtimeType}',
    );
    if (preview.name != null) {
      buffer.write('(name: "${preview.name}")');
    }
    return buffer.toString();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    preview.debugFillProperties(properties);
  }
}

/// A custom [StatelessElement] with the sole purpose of simplifying identifying
/// selections of @Preview annotations in the widget inspector and scoping
/// per-preview build diagnostics.
class PreviewWidgetElement extends StatelessElement {
  PreviewWidgetElement(PreviewWidget super.widget);

  /// The [PreviewWidgetElement] currently executing [mount], [update], or
  /// [performRebuild] on the call stack, if any.
  static PreviewWidgetElement? activeBuildingElement;

  PreviewWidget get previewWidget => widget as PreviewWidget;

  void reportDiagnostic(PreviewDiagnostic diagnostic) {
    previewWidget.onDiagnostic?.call(diagnostic);
  }

  @override
  void mount(Element? parent, Object? newSlot) {
    final PreviewWidgetElement? previous = activeBuildingElement;
    activeBuildingElement = this;
    try {
      super.mount(parent, newSlot);
    } finally {
      activeBuildingElement = previous;
    }
  }

  @override
  void update(PreviewWidget newWidget) {
    final PreviewWidgetElement? previous = activeBuildingElement;
    activeBuildingElement = this;
    try {
      super.update(newWidget);
    } finally {
      activeBuildingElement = previous;
    }
  }

  @override
  void performRebuild() {
    final PreviewWidgetElement? previous = activeBuildingElement;
    activeBuildingElement = this;
    try {
      super.performRebuild();
    } finally {
      activeBuildingElement = previous;
    }
  }
}

class WidgetPreviewGroupWidget extends StatefulWidget {
  const WidgetPreviewGroupWidget({
    super.key,
    required this.controller,
    required this.group,
  });

  final WidgetPreviewScaffoldController controller;
  final WidgetPreviewGroup group;

  // Spacing values for the grid layout
  static const _gridSpacing = 8.0;
  static const _gridRunSpacing = 8.0;

  @override
  State<WidgetPreviewGroupWidget> createState() =>
      _WidgetPreviewGroupWidgetState();
}

class _WidgetPreviewGroupWidgetState extends State<WidgetPreviewGroupWidget> {
  final _bucket = PageStorageBucket();

  Widget _buildGridViewFlex(List<WidgetPreview> previews) {
    return Wrap(
      spacing: WidgetPreviewGroupWidget._gridSpacing,
      runSpacing: WidgetPreviewGroupWidget._gridRunSpacing,
      alignment: WrapAlignment.start,
      children: [
        for (final WidgetPreview preview in previews)
          WidgetPreviewWidget(controller: widget.controller, preview: preview),
      ],
    );
  }

  Widget _buildVerticalListView(List<WidgetPreview> previews) {
    return Column(
      children: [
        for (final preview in previews)
          Center(
            child: WidgetPreviewWidget(
              controller: widget.controller,
              preview: preview,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        key: PageStorageKey(widget.group.name),
        title: Text(widget.group.name),
        dense: true,
        initiallyExpanded: true,
        children: [
          // Wrap children in a PageStorage to create a storage boundary.
          // Without this, descendant scrollables (which search ancestor
          // elements for a PageStorageKey when restoring scroll offset)
          // inherit the PageStorageKey from the ExpansionTile and attempt
          // to read the ExpansionTile's boolean expansion state as a double,
          // throwing a TypeError (see https://github.com/flutter/flutter/issues/191242).
          PageStorage(
            bucket: _bucket,
            child: ValueListenableBuilder<LayoutType>(
              valueListenable: widget.controller.layoutTypeListenable,
              builder: (context, selectedLayout, _) {
                return switch (selectedLayout) {
                  LayoutType.gridView => _buildGridViewFlex(
                    widget.group.previews,
                  ),
                  LayoutType.listView => _buildVerticalListView(
                    widget.group.previews,
                  ),
                };
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Thrown when a widget preview fails layout due to unconstrained dimensions.
class UnconstrainedWidgetPreviewException implements Exception {
  const UnconstrainedWidgetPreviewException();

  @override
  String toString() {
    return 'The widget preview has unconstrained dimensions (e.g. infinite width or height).\n'
        'To preview this widget, specify a fixed size constraint via @Preview(size: Size(width, height)) '
        'or wrap the widget in a SizedBox with explicit dimensions.';
  }
}

const _kUnconstrainedErrorPatterns = <String>[
  'forces an infinite width',
  'forces an infinite height',
  'unbounded height',
  'unbounded width',
  'incoming height constraints are unbounded',
  'incoming width constraints are unbounded',
  'was given an infinite size during layout',
  'BoxConstraints(unconstrained)',
];

bool _isUnconstrainedError(Object error) {
  final message = error.toString();
  return _kUnconstrainedErrorPatterns.any(message.contains);
}

bool _isUnconstrainedPreviewError(FlutterErrorDetails details) =>
    _isUnconstrainedError(details.exceptionAsString());

/// Fallback size used when a widget preview fails layout and the previewer
/// surface constraints are unbounded.
const _kFallbackPreviewSize = Size(400, 400);

/// Size of the error card for [constraints], falling back to
/// [_kFallbackPreviewSize] when unbounded.
Size errorPreviewSizeFor(BoxConstraints constraints) =>
    constraints.hasBoundedWidth && constraints.hasBoundedHeight
    ? constraints.biggest
    : _kFallbackPreviewSize;

FlutterErrorDetails _createUnconstrainedPreviewErrorDetails(
  FlutterErrorDetails details,
) {
  return FlutterErrorDetails(
    exception: FlutterError.fromParts(<DiagnosticsNode>[
      ErrorSummary(
        'A widget preview was rendered with unconstrained dimensions.',
      ),
      ErrorDescription(
        'The previewed widget attempted to expand to an infinite size, but widget previews '
        'are unconstrained by default so that self-sizing widgets do not stretch to fill the window.',
      ),
      ErrorHint(
        'To resolve this error, specify a fixed size constraint in your @Preview annotation:\n'
        '  @Preview(size: Size(width, height))\n'
        'or wrap the widget in a widget with explicit dimensions (such as SizedBox or Container).',
      ),
      ErrorDescription('Original error: ${details.exceptionAsString()}'),
    ]),
    stack: details.stack,
    library: 'widget_preview_scaffold',
    context: ErrorDescription('during performLayout() of a widget preview'),
    informationCollector: details.informationCollector,
  );
}

class WidgetPreviewWidget extends StatefulWidget {
  const WidgetPreviewWidget({
    super.key,
    required this.preview,
    required this.controller,
  });

  final WidgetPreview preview;

  final WidgetPreviewScaffoldController controller;

  @override
  State<WidgetPreviewWidget> createState() => WidgetPreviewWidgetState();
}

class WidgetPreviewWidgetState extends State<WidgetPreviewWidget> {
  final transformationController = TransformationController();

  // Set the initial preview brightness based on the platform default or the
  // value explicitly specified for the preview.
  late final brightnessListenable = ValueNotifier<Brightness>(
    widget.preview.brightness ?? MediaQuery.platformBrightnessOf(context),
  );

  final softRestartListenable = ValueNotifier<bool>(false);
  final key = GlobalKey();

  ({Object error, StackTrace stackTrace})? _layoutError;
  bool _previewBuilderThrew = false;

  @override
  void initState() {
    super.initState();
    widget.controller.registerDiagnosticPruner(
      widget.preview,
      _pruneStaleSubtreeDiagnostics,
    );
  }

  @override
  void dispose() {
    widget.controller.unregisterDiagnosticPruner(
      widget.preview,
      _pruneStaleSubtreeDiagnostics,
    );
    super.dispose();
  }

  void _recordDiagnostic(PreviewDiagnostic diagnostic) {
    widget.controller.recordDiagnostic(widget.preview, diagnostic);
  }

  void _pruneStaleSubtreeDiagnostics() {
    if (!mounted) {
      return;
    }
    final RenderObject? rootRenderObject = key.currentContext
        ?.findRenderObject();
    if (!_previewBuilderThrew &&
        (rootRenderObject == null ||
            !_hasDescendantRenderErrorBox(rootRenderObject))) {
      widget.controller.clearPhaseDiagnostics(widget.preview, .build);
    }
    if (rootRenderObject != null &&
        !_hasOverflowingRenderFlex(rootRenderObject)) {
      widget.controller.clearRenderFlexOverflowDiagnostics(widget.preview);
    }
  }

  void _handleLayoutError(Object error, StackTrace stackTrace) {
    final PreviewDiagnosticKind kind =
        error is UnconstrainedWidgetPreviewException ||
            _isUnconstrainedError(error)
        ? .unconstrained
        : .exception;
    _recordDiagnostic(
      PreviewDiagnostic(kind: kind, phase: .layout, summary: error.toString()),
    );
    if (_layoutError != null) {
      return;
    }
    // Assign synchronously outside setState (which cannot be called during
    // layout) so subsequent errors in the same frame are deduplicated.
    _layoutError = (error: error, stackTrace: stackTrace);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _handleLayoutSuccess() {
    widget.controller.clearPhaseDiagnostics(widget.preview, .layout);
  }

  void _handlePaintStart() {
    widget.controller.clearPhaseDiagnostics(
      widget.preview,
      .paint,
      preserveOverflow: true,
    );
  }

  void _clearLayoutError() {
    _layoutError = null;
    _previewBuilderThrew = false;
    widget.controller.clearDiagnosticsFor(widget.preview);
  }

  /// Returns the last size of the previewed widget.
  Size get lastChildSize =>
      (key.currentContext!.findRenderObject() as RenderBox).size;

  @override
  void reassemble() {
    super.reassemble();
    _clearLayoutError();
  }

  @override
  void didUpdateWidget(WidgetPreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller) ||
        oldWidget.preview != widget.preview) {
      oldWidget.controller.unregisterDiagnosticPruner(
        oldWidget.preview,
        _pruneStaleSubtreeDiagnostics,
      );
      widget.controller.registerDiagnosticPruner(
        widget.preview,
        _pruneStaleSubtreeDiagnostics,
      );
    }
    if (oldWidget.preview != widget.preview) {
      _clearLayoutError();
    }

    final previousBrightness = oldWidget.preview.brightness;
    final newBrightness = widget.preview.brightness;
    final currentBrightness = brightnessListenable.value;
    final systemBrightness = MediaQuery.platformBrightnessOf(context);

    // No initial brightness was previously defined.
    if (previousBrightness == null && newBrightness != null) {
      if (currentBrightness == systemBrightness) {
        // If the current brightness is different than the system brightness, the user has manually
        // changed the brightness through the UI, so don't change it automatically.
        brightnessListenable.value = newBrightness;
      }
    }
    // Changing the initial brightness to either a new initial brightness or system brightness.
    else if (previousBrightness != null) {
      // If the current brightness is different than the initial brightness, the user has manually
      // changed the brightness through the UI, so don't change it automatically.
      if (currentBrightness == previousBrightness) {
        brightnessListenable.value = newBrightness ?? systemBrightness;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewerConstraints =
        WidgetPreviewerWindowConstraints.getRootConstraints(context);

    final maxSizeConstraints = previewerConstraints.copyWith(
      minHeight: previewerConstraints.maxHeight / 2.0,
      maxHeight: previewerConstraints.maxHeight / 2.0,
    );

    bool errorThrownDuringTreeConstruction = false;

    Widget preview;
    if (_layoutError case (:final Object error, :final StackTrace stackTrace)) {
      errorThrownDuringTreeConstruction = true;
      preview = WidgetPreviewErrorWidget(
        controller: widget.controller,
        error: error,
        size: errorPreviewSizeFor(maxSizeConstraints),
        stackTrace: stackTrace,
        title: 'Failed to layout widget preview: ',
      );
    } else {
      // Wrap the previewed widget with a ValueListenableBuilder responsible for performing a "soft"
      // restart.
      //
      // A soft restart simply removes the previewed widget from the widget tree for a frame before
      // re-inserting it on the next frame. This has the effect of re-running local initializers in
      // State objects, which normally requires a hot restart to accomplish in a normal application.
      preview = ValueListenableBuilder<bool>(
        valueListenable: softRestartListenable,
        builder: (context, performRestart, _) {
          if (performRestart) {
            _previewBuilderThrew = false;
            widget.controller.clearDiagnosticsFor(widget.preview);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              // Trigger a rebuild on the next frame to re-insert previewWidget.
              softRestartListenable.value = false;
            }, debugLabel: 'Soft Restart');
            return SizedBox.fromSize(size: lastChildSize);
          }
          _previewBuilderThrew = false;
          widget.controller.clearPhaseDiagnostics(widget.preview, .build);
          try {
            final previewWidget = Container(
              key: key,
              child: WidgetPreviewTheming(
                theme: widget.preview.theme,
                child: EnableWidgetInspectorScope(
                  child: PreviewWidget(
                    preview: widget.preview,
                    onDiagnostic: _recordDiagnostic,
                    child: widget.preview.previewBuilder(),
                  ),
                ),
              ),
            );
            return previewWidget;
          } on Object catch (error, stackTrace) {
            // Catch any unhandled exceptions and display an error widget instead of taking
            // down the entire preview environment.
            _previewBuilderThrew = true;
            errorThrownDuringTreeConstruction = true;
            _recordDiagnostic(
              PreviewDiagnostic(
                kind: .exception,
                phase: .build,
                summary: error.toString(),
              ),
            );
            return WidgetPreviewErrorWidget(
              controller: widget.controller,
              error: error,
              size: errorPreviewSizeFor(maxSizeConstraints),
              stackTrace: stackTrace,
            );
          }
        },
      );

      // Add support for selecting only previewed widgets via the widget
      // inspector.
      preview = ValueListenableBuilder(
        valueListenable:
            WidgetsBinding.instance.debugShowWidgetInspectorOverrideNotifier,
        builder: (context, enableWidgetInspector, child) {
          // Don't allow inspecting the error widget.
          if (child is WidgetPreviewErrorWidget || !enableWidgetInspector) {
            return child!;
          }
          return WidgetInspector(
            // TODO(bkonyi): wire up inspector controls for individual previews or
            // the entire preview environment. This currently requires users to
            // to enable widget selection via the Widget Inspector tool in DevTools.

            // These buttons would be rendered on top of the previewed widget, so
            // don't display them.
            exitWidgetSelectionButtonBuilder: null,
            moveExitWidgetSelectionButtonBuilder: null,
            tapBehaviorButtonBuilder: null,
            child: child!,
          );
        },
        child: SizedBox(
          width: widget.preview.finiteWidth,
          height: widget.preview.finiteHeight,
          child: WidgetPreviewWrapper(
            previewerConstraints: maxSizeConstraints,
            onLayoutError: _handleLayoutError,
            onLayoutSuccess: _handleLayoutSuccess,
            onPaintDiagnostic: _recordDiagnostic,
            onPaintStart: _handlePaintStart,
            child: preview,
          ),
        ),
      );

      preview = WidgetPreviewMediaQueryOverride(
        preview: widget.preview,
        brightnessListenable: brightnessListenable,
        child: preview,
      );

      preview = WidgetPreviewLocalizations(
        localizationsData: widget.preview.localizations,
        child: preview,
      );

      // Override the asset resolution behavior to automatically insert
      // 'packages/$packageName/` in front of non-package paths as some previews
      // may reference assets that are within the current project and wouldn't
      // normally require a package specifier.
      // TODO(bkonyi): this doesn't modify the behavior of asset loading logic in
      // the engine implementation. This means that any asset loading done by
      // APIs provided in dart:ui won't work correctly for non-package asset
      // paths (e.g., shaders loaded by `FragmentProgram.fromAsset()`).
      //
      // See https://github.com/flutter/flutter/issues/171284
      preview = DefaultAssetBundle(
        bundle: PreviewAssetBundle(packageName: widget.preview.packageName),
        child: preview,
      );
    }

    final hasName = widget.preview.name != null;
    preview = Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (hasName)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
              widget.preview.name!,
              style: fixBlurryText(
                TextStyle(fontSize: 16, fontWeight: FontWeight.w300),
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(
            // TODO(bkonyi): use theming or define global constants.
            horizontal: 16.0,
          ).add(hasName ? const EdgeInsets.only(top: 8.0) : EdgeInsets.zero),
          decoration: hasName
              ? BoxDecoration(
                  border: Border(top: Divider.createBorderSide(context)),
                )
              : null,
          child: Column(
            children: [
              ZoomablePreviewArea(
                transformationController: transformationController,
                errorThrownDuringTreeConstruction:
                    errorThrownDuringTreeConstruction,
                child: preview,
              ),
              const VerticalSpacer(),
              Builder(
                builder: (context) {
                  return _WidgetPreviewControlRow(
                    transformationController: transformationController,
                    errorThrownDuringTreeConstruction:
                        errorThrownDuringTreeConstruction,
                    brightnessListenable: brightnessListenable,
                    softRestartListenable: softRestartListenable,
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Card.outlined(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: preview,
        ),
      ),
    );
  }
}

class _WidgetPreviewControlRow extends StatelessWidget {
  const _WidgetPreviewControlRow({
    required this.transformationController,
    required this.errorThrownDuringTreeConstruction,
    required this.brightnessListenable,
    required this.softRestartListenable,
  });

  final TransformationController transformationController;
  final bool errorThrownDuringTreeConstruction;
  final ValueNotifier<Brightness> brightnessListenable;
  final ValueNotifier<bool> softRestartListenable;

  @override
  Widget build(BuildContext context) {
    // Don't show controls if an error occurred.
    if (errorThrownDuringTreeConstruction) {
      return Container();
    }
    return Wrap(
      spacing: largeSpacing,
      runSpacing: denseSpacing,
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ZoomControls(transformationController: transformationController),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrightnessToggleButton(brightnessListenable: brightnessListenable),
            const SizedBox(width: intermediateSpacing),
            SoftRestartButton(softRestartListenable: softRestartListenable),
          ],
        ),
      ],
    );
  }
}

/// Applies theming defined in [theme] to [child].
class WidgetPreviewTheming extends StatelessWidget {
  const WidgetPreviewTheming({
    super.key,
    required this.theme,
    required this.child,
  });

  final Widget child;

  /// The set of themes to be applied to [child].
  final PreviewThemeData? theme;

  @override
  Widget build(BuildContext context) {
    final themeData = theme;
    if (themeData == null) {
      return child;
    }
    return themeData.apply(context, child);
  }
}

MediaQueryData _applyPreviewMediaQueryOverrides({
  required MediaQueryData base,
  required Brightness brightness,
  double? height,
  double? pixelRatio,
  double? textScaleFactor,
  double? width,
}) {
  return base.copyWith(
    devicePixelRatio: pixelRatio,
    platformBrightness: brightness,
    size: width != null || height != null
        ? Size(width ?? base.size.width, height ?? base.size.height)
        : null,
    textScaler: textScaleFactor != null
        ? TextScaler.linear(textScaleFactor)
        : null,
  );
}

/// Wraps the previewed [child] with the correct [MediaQueryData] overrides
/// based on [preview] and the current device [Brightness].
class WidgetPreviewMediaQueryOverride extends StatelessWidget {
  const WidgetPreviewMediaQueryOverride({
    super.key,
    required this.preview,
    required this.brightnessListenable,
    required this.child,
  });

  /// The preview specification used to render the preview.
  final WidgetPreview preview;

  /// The currently set brightness for this preview instance.
  final ValueListenable<Brightness> brightnessListenable;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Brightness>(
      valueListenable: brightnessListenable,
      builder: (BuildContext context, Brightness brightness, _) {
        return MediaQuery(
          data: _applyPreviewMediaQueryOverrides(
            base: MediaQuery.of(context),
            brightness: brightness,
            height: preview.finiteHeight,
            textScaleFactor: preview.finiteTextScaleFactor,
            width: preview.finiteWidth,
          ),
          // Use mediaQueryPreview instead of preview to avoid capturing preview
          // and creating an infinite loop.
          child: child,
        );
      },
    );
  }
}

/// Wraps [child] with a [Localizations] with localization data from
/// [localizationsData].
class WidgetPreviewLocalizations extends StatefulWidget {
  const WidgetPreviewLocalizations({
    super.key,
    required this.localizationsData,
    required this.child,
  });

  final PreviewLocalizationsData? localizationsData;
  final Widget child;

  @override
  State<WidgetPreviewLocalizations> createState() =>
      _WidgetPreviewLocalizationsState();
}

class _WidgetPreviewLocalizationsState
    extends State<WidgetPreviewLocalizations> {
  PreviewLocalizationsData get _localizationsData => widget.localizationsData!;
  late final LocalizationsResolver _localizationsResolver =
      LocalizationsResolver(
        supportedLocales: _localizationsData.supportedLocales,
        locale: _localizationsData.locale,
        localeListResolutionCallback:
            _localizationsData.localeListResolutionCallback,
        localeResolutionCallback: _localizationsData.localeResolutionCallback,
        localizationsDelegates: _localizationsData.localizationsDelegates,
      );

  @override
  void didUpdateWidget(WidgetPreviewLocalizations oldWidget) {
    super.didUpdateWidget(oldWidget);
    final PreviewLocalizationsData? localizationsData =
        widget.localizationsData;
    if (localizationsData == null) {
      return;
    }
    _localizationsResolver.update(
      supportedLocales: localizationsData.supportedLocales,
      locale: localizationsData.locale,
      localeListResolutionCallback:
          localizationsData.localeListResolutionCallback,
      localeResolutionCallback: localizationsData.localeResolutionCallback,
      localizationsDelegates: localizationsData.localizationsDelegates,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.localizationsData == null) {
      return widget.child;
    }
    return ListenableBuilder(
      listenable: _localizationsResolver,
      builder: (context, _) {
        return Localizations(
          locale: _localizationsResolver.locale,
          delegates: _localizationsResolver.localizationsDelegates.toList(),
          child: widget.child,
        );
      },
    );
  }
}

/// An [InheritedWidget] that propagates the current size of the
/// WidgetPreviewScaffold.
///
/// This is needed when determining how to put constraints on previewed widgets
/// that would otherwise have infinite constraints.
class WidgetPreviewerWindowConstraints extends InheritedWidget {
  const WidgetPreviewerWindowConstraints({
    super.key,
    required super.child,
    required this.constraints,
  });

  final BoxConstraints constraints;

  static BoxConstraints getRootConstraints(BuildContext context) {
    final result = context
        .dependOnInheritedWidgetOfExactType<WidgetPreviewerWindowConstraints>();
    assert(
      result != null,
      'No WidgetPreviewerWindowConstraints founds in context',
    );
    return result!.constraints;
  }

  @override
  bool updateShouldNotify(WidgetPreviewerWindowConstraints oldWidget) {
    return oldWidget.constraints != constraints;
  }
}

class ZoomablePreviewArea extends StatelessWidget {
  const ZoomablePreviewArea({
    super.key,
    required this.child,
    required this.transformationController,
    required this.errorThrownDuringTreeConstruction,
  });

  final Widget child;
  final TransformationController transformationController;
  final bool errorThrownDuringTreeConstruction;

  void _setScale(double nextScale) {
    transformationController.value = Matrix4.diagonal3Values(
      nextScale,
      nextScale,
      1.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (errorThrownDuringTreeConstruction) {
      return child;
    }
    return ListenableBuilder(
      listenable: transformationController,
      builder: (context, _) {
        final double scale = transformationController.value.entry(0, 0);
        return PreviewPointerScrollZoom(
          zoom: scale,
          onZoomChanged: _setScale,
          child: ScaledScrollablePreview(scale: scale, child: child),
        );
      },
    );
  }
}

/// Wraps [child] in bidirectional [SingleChildScrollView]s around a
/// [ScaledPreviewLayout] at [scale], optionally enforcing [minWidth] and
/// [minHeight] on the scrollable content area.
class ScaledScrollablePreview extends StatelessWidget {
  const ScaledScrollablePreview({
    required this.child,
    required this.scale,
    this.includeVerticalScroll = true,
    this.minHeight = 0.0,
    this.minWidth = 0.0,
    super.key,
  });

  final Widget child;
  final bool includeVerticalScroll;
  final double minHeight;
  final double minWidth;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final Widget scaled = ScaledPreviewLayout(scale: scale, child: child);
    final Widget content = minWidth > 0.0 || minHeight > 0.0
        ? ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: minWidth,
              minHeight: minHeight,
            ),
            child: Center(child: scaled),
          )
        : scaled;
    final horizontalScroll = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: content,
    );
    if (!includeVerticalScroll) {
      return horizontalScroll;
    }
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: horizontalScroll,
    );
  }
}

/// Scales the painted output, hit-test coordinates, and reported layout box of
/// [child] by [scale] without altering [child]'s logical layout constraints.
class ScaledPreviewLayout extends SingleChildRenderObjectWidget {
  const ScaledPreviewLayout({required this.scale, super.child, super.key});

  final double scale;

  @override
  RenderScaledPreviewLayout createRenderObject(BuildContext context) {
    return RenderScaledPreviewLayout(scale: scale);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderScaledPreviewLayout renderObject,
  ) {
    renderObject.scale = scale;
  }
}

/// Render box backing [ScaledPreviewLayout].
class RenderScaledPreviewLayout extends RenderShiftedBox {
  RenderScaledPreviewLayout({required this._scale, RenderBox? child})
    : super(child);

  double _scale;
  double get scale => _scale;
  set scale(double value) {
    if (_scale == value) {
      return;
    }
    _scale = value;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    if (child == null) {
      return 0.0;
    }
    return child!.getMinIntrinsicWidth(height / scale) * scale;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    if (child == null) {
      return 0.0;
    }
    return child!.getMaxIntrinsicWidth(height / scale) * scale;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    if (child == null) {
      return 0.0;
    }
    return child!.getMinIntrinsicHeight(width / scale) * scale;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    if (child == null) {
      return 0.0;
    }
    return child!.getMaxIntrinsicHeight(width / scale) * scale;
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = Size.zero;
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(child.size * scale);

    final BoxParentData childParentData = child.parentData! as BoxParentData;
    childParentData.offset = Offset.zero;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) {
      layer = null;
      return;
    }
    if (scale == 1.0) {
      super.paint(context, offset);
      layer = null;
      return;
    }
    final Matrix4 transform = Matrix4.diagonal3Values(scale, scale, 1.0);
    layer = context.pushTransform(
      needsCompositing,
      offset,
      transform,
      super.paint,
      oldLayer: layer is TransformLayer ? layer as TransformLayer? : null,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (scale != 1.0) {
      transform.scaleByDouble(scale, scale, 1.0, 1.0);
    }
    super.applyPaintTransform(child, transform);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (child == null) {
      return false;
    }
    final Matrix4 transform = Matrix4.diagonal3Values(scale, scale, 1.0);
    return result.addWithPaintTransform(
      transform: transform,
      position: position,
      hitTest: (BoxHitTestResult result, Offset position) {
        return super.hitTestChildren(result, position: position);
      },
    );
  }
}

// TODO(bkonyi): according to goderbauer@, this probably isn't the best approach to ensure we
// handle unconstrained widgets. This should be reworked.
/// Wrapper applying a custom render object to force constraints on
/// unconstrained widgets.
class WidgetPreviewWrapper extends SingleChildRenderObjectWidget {
  const WidgetPreviewWrapper({
    required this.previewerConstraints,
    super.child,
    super.key,
    this.onLayoutError,
    this.onLayoutSuccess,
    this.onPaintDiagnostic,
    this.onPaintStart,
    this.suppressErrorForwarding = false,
  });

  /// The size of the previewer render surface.
  final BoxConstraints previewerConstraints;

  /// Callback invoked when an exception is thrown during child layout.
  final void Function(Object error, StackTrace stackTrace)? onLayoutError;

  /// Callback invoked when child layout completes cleanly.
  final VoidCallback? onLayoutSuccess;

  /// Callback invoked when an overflow or exception is reported during paint.
  final ValueChanged<PreviewDiagnostic>? onPaintDiagnostic;

  /// Callback invoked before painting the child subtree.
  final VoidCallback? onPaintStart;

  /// Whether framework errors captured in this wrapper should omit forwarding
  /// to the outer [FlutterError.onError] handler.
  final bool suppressErrorForwarding;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _WidgetPreviewWrapperBox(
      onLayoutError: onLayoutError,
      onLayoutSuccess: onLayoutSuccess,
      onPaintDiagnostic: onPaintDiagnostic,
      onPaintStart: onPaintStart,
      previewerConstraints: previewerConstraints,
      suppressErrorForwarding: suppressErrorForwarding,
      child: null,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    if (renderObject is! _WidgetPreviewWrapperBox) {
      return;
    }
    renderObject
      ..onLayoutError = onLayoutError
      ..onLayoutSuccess = onLayoutSuccess
      ..onPaintDiagnostic = onPaintDiagnostic
      ..onPaintStart = onPaintStart
      ..suppressErrorForwarding = suppressErrorForwarding
      ..setPreviewerConstraints(previewerConstraints);
  }
}

/// Custom render box that forces constraints onto unconstrained widgets.
class _WidgetPreviewWrapperBox extends RenderShiftedBox {
  _WidgetPreviewWrapperBox({
    required RenderBox? child,
    required this._previewerConstraints,
    this.onLayoutError,
    this.onLayoutSuccess,
    this.onPaintDiagnostic,
    this.onPaintStart,
    this.suppressErrorForwarding = false,
  }) : super(child);

  /// Whether a [_WidgetPreviewWrapperBox] is actively executing [performLayout].
  ///
  /// Used by [_WidgetPreviewScaffoldState._handleFlutterError] to scope layout
  /// error interception to preview subtrees.
  static bool isPerformingPreviewLayout = false;

  /// Whether layout errors captured during the active [performLayout] pass
  /// should omit forwarding to the outer [FlutterError.onError] handler.
  static bool suppressLayoutErrorForwarding = false;

  /// The [_WidgetPreviewWrapperBox] actively executing [paint], if any.
  static _WidgetPreviewWrapperBox? activePaintingBox;

  /// The first error and stack trace reported to [FlutterError.onError] during
  /// the active [performLayout] pass.
  ///
  /// Subsequent cascading layout errors (such as ancestor `RenderBox was not
  /// laid out` assertions) within the same preview layout pass are suppressed,
  /// and this error is forwarded to [onLayoutError] to populate the error card.
  static (Object, StackTrace)? reportedPreviewLayoutError;

  void Function(Object error, StackTrace stackTrace)? onLayoutError;
  VoidCallback? onLayoutSuccess;
  ValueChanged<PreviewDiagnostic>? onPaintDiagnostic;
  VoidCallback? onPaintStart;
  bool suppressErrorForwarding;

  BoxConstraints _constraintOverride = const BoxConstraints();
  BoxConstraints _previewerConstraints;
  bool _hasLayoutError = false;

  bool get _hasValidChild =>
      !_hasLayoutError && child != null && child!.hasSize;

  void setPreviewerConstraints(BoxConstraints previewerConstraints) {
    if (_previewerConstraints == previewerConstraints) {
      return;
    }
    _previewerConstraints = previewerConstraints;
    markNeedsLayout();
  }

  @override
  void layout(Constraints constraints, {bool parentUsesSize = false}) {
    if (child != null && constraints is BoxConstraints) {
      double minInstrinsicHeight;
      try {
        minInstrinsicHeight = child!.getMinIntrinsicHeight(
          constraints.maxWidth,
        );
      } on Object {
        minInstrinsicHeight = 0.0;
      }
      // Determine if the previewed widget is vertically constrained. If the
      // widget has a minimum intrinsic height of zero given the widget's max
      // width, it has an unconstrained height and will cause an overflow in
      // the previewer. In this case, apply finite constraints (e.g., the
      // constraints for the root of the previewer). Otherwise, use the
      // widget's actual constraints.
      _constraintOverride = minInstrinsicHeight == 0
          ? _previewerConstraints
          : const BoxConstraints();
    }
    super.layout(constraints, parentUsesSize: parentUsesSize);
  }

  @override
  void performLayout() {
    _hasLayoutError = false;
    final child = this.child;
    if (child == null) {
      size = Size.zero;
      return;
    }
    final updatedConstraints = _constraintOverride.enforce(constraints);
    final previousIsPerforming = isPerformingPreviewLayout;
    final previousSuppressForwarding = suppressLayoutErrorForwarding;
    final previousReportedError = reportedPreviewLayoutError;
    isPerformingPreviewLayout = true;
    suppressLayoutErrorForwarding = suppressErrorForwarding;
    reportedPreviewLayoutError = null;
    try {
      child.layout(updatedConstraints, parentUsesSize: true);
      if (reportedPreviewLayoutError case (
        final Object error,
        final StackTrace stackTrace,
      )) {
        _hasLayoutError = true;
        size = constraints.constrain(
          errorPreviewSizeFor(_previewerConstraints),
        );
        onLayoutError?.call(error, stackTrace);
      } else {
        size = constraints.constrain(child.size);
        onLayoutSuccess?.call();
      }
    } catch (error, stackTrace) {
      _hasLayoutError = true;
      final (Object layoutError, StackTrace layoutStackTrace) =
          reportedPreviewLayoutError ??
          (
            _isUnconstrainedError(error)
                ? const UnconstrainedWidgetPreviewException()
                : error,
            stackTrace,
          );
      size = constraints.constrain(errorPreviewSizeFor(_previewerConstraints));
      onLayoutError?.call(layoutError, layoutStackTrace);
    } finally {
      isPerformingPreviewLayout = previousIsPerforming;
      suppressLayoutErrorForwarding = previousSuppressForwarding;
      reportedPreviewLayoutError = previousReportedError;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (_hasValidChild) {
      return super.hitTestChildren(result, position: position);
    }
    return false;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_hasValidChild) {
      return;
    }
    onPaintStart?.call();
    final _WidgetPreviewWrapperBox? previousPaintingBox = activePaintingBox;
    activePaintingBox = this;
    try {
      super.paint(context, offset);
    } on Object catch (error, stackTrace) {
      activePaintingBox = previousPaintingBox;
      onPaintDiagnostic?.call(
        PreviewDiagnostic(
          kind: .exception,
          phase: .paint,
          summary: error.toString(),
        ),
      );
      if (!suppressErrorForwarding) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'widget_preview_scaffold',
            context: ErrorDescription('during paint() of a widget preview'),
          ),
        );
      }
    } finally {
      activePaintingBox = previousPaintingBox;
    }
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_hasValidChild) {
      super.visitChildrenForSemantics(visitor);
    }
  }
}

/// Custom [AssetBundle] used to map original asset paths from the parent
/// projects to those in the preview project.
class PreviewAssetBundle extends PlatformAssetBundle {
  PreviewAssetBundle({required this.packageName});

  /// The name of the package in which a preview was defined.
  ///
  /// For example, if a preview is defined in 'package:foo/src/bar.dart', this
  /// will have the value 'foo'.
  final String packageName;

  // Assets shipped via package dependencies have paths that start with
  // 'packages/'.
  static const _kAssetManifestBin = 'AssetManifest.bin';
  static const _kAssetManifestBinJson = 'AssetManifest.bin.json';
  static const _kFontManifestJson = 'FontManifest.json';
  static const _kPackagesPrefix = 'packages/';

  late final String _packageAssetPrefix = '$_kPackagesPrefix$packageName/';

  Map<Object?, Object?> _aliasManifestMap(Map<Object?, Object?> manifest) {
    final aliased = Map<Object?, Object?>.of(manifest);
    for (final MapEntry(:Object? key, :Object? value) in manifest.entries) {
      if (key is String && key.startsWith(_packageAssetPrefix)) {
        aliased.putIfAbsent(
          key.substring(_packageAssetPrefix.length),
          () => value,
        );
      }
    }
    return aliased;
  }

  ByteData _aliasManifestBytes(ByteData bytes) {
    final Object? decoded = const StandardMessageCodec().decodeMessage(bytes);
    if (decoded is! Map<Object?, Object?>) {
      return bytes;
    }
    return const StandardMessageCodec().encodeMessage(
      _aliasManifestMap(decoded),
    )!;
  }

  // TODO(bkonyi): when loading an invalid asset path that doesn't start with
  // 'packages/', this throws a FlutterError referencing the modified key
  // instead of the original. We should catch the error and rethrow one with
  // the original key in the error message.
  @override
  Future<ByteData> load(String key) async {
    if (key == _kAssetManifestBin) {
      return _aliasManifestBytes(await super.load(key));
    }
    if (key == _kAssetManifestBinJson) {
      final ByteData bytes = await super.load(key);
      final Object? encoded = jsonDecode(
        utf8.decode(Uint8List.sublistView(bytes)),
      );
      if (encoded is! String) {
        return bytes;
      }
      final ByteData aliasedBin = _aliasManifestBytes(
        ByteData.sublistView(base64Decode(encoded)),
      );
      final String aliasedJson = jsonEncode(
        base64Encode(Uint8List.sublistView(aliasedBin)),
      );
      return ByteData.sublistView(Uint8List.fromList(utf8.encode(aliasedJson)));
    }
    // These assets are always present or are shipped via a package and aren't
    // actually located in the parent project, meaning their paths did not need
    // to be modified.
    if (key == _kFontManifestJson || key.startsWith(_kPackagesPrefix)) {
      return super.load(key);
    }
    // Other assets are from the parent project. Map their keys to package
    // paths corresponding to the package containing the preview.
    return super.load(_toPackagePath(key));
  }

  @override
  Future<ImmutableBuffer> loadBuffer(String key) async {
    if (kIsWeb) {
      final ByteData bytes = await load(key);
      return ImmutableBuffer.fromUint8List(Uint8List.sublistView(bytes));
    }
    return await ImmutableBuffer.fromAsset(
      key.startsWith(_kPackagesPrefix) ? key : _toPackagePath(key),
    );
  }

  String _toPackagePath(String key) => '$_packageAssetPrefix$key';
}

/// Main entrypoint for the widget previewer.
///
/// We don't actually define this as `main` to avoid copying this file into
/// the preview scaffold project which prevents us from being able to use hot
/// restart to iterate on this file.
Future<void> mainImpl() async {
  final initialEmbedParams = EmbedPreviewParams.fromCurrentUrl();
  final controller = WidgetPreviewScaffoldController(previews: previews);
  try {
    await controller.initialize();
  } on Object {
    if (!initialEmbedParams.isEmbed) {
      rethrow;
    }
  }
  if (!initialEmbedParams.isEmbed) {
    // WARNING: do not move this line. This constructor sets
    // [WidgetInspectorService.instance] to the custom service for the widget
    // previewer. If [WidgetsFlutterBinding.ensureInitialized()] is invoked before
    // the custom service is set, inspector service extensions will be registered
    // against the wrong service.
    WidgetPreviewScaffoldInspectorService(dtdServices: controller.dtdServices);
  }
  final WidgetsBinding binding = WidgetsFlutterBinding.ensureInitialized();
  // Disable the injection of [WidgetInspector] into the widget tree built by
  // [WidgetsApp]. [WidgetInspector] instances will be created for each
  // individual preview so the widget inspector won't allow for users to select
  // widgets that make up the widget preview scaffolding.
  binding.debugExcludeRootWidgetInspector = true;
  runWidget(
    DisableWidgetInspectorScope(
      child: binding.wrapWithDefaultView(
        // Forces the set of previews to be recalculated after a hot reload.
        HotReloadListener(
          onHotReload: controller.onHotReload,
          child: WidgetPreviewScaffold(
            controller: controller,
            ideTheme: getIdeTheme(),
          ),
        ),
      ),
    ),
  );
}

class WidgetPreviewScaffold extends StatefulWidget {
  const WidgetPreviewScaffold({
    super.key,
    required this.controller,
    this.ideTheme = const IdeTheme(),
    this.enableWebView = true,
  });

  final WidgetPreviewScaffoldController controller;
  final IdeTheme ideTheme;
  final bool enableWebView;

  @override
  State<WidgetPreviewScaffold> createState() => _WidgetPreviewScaffoldState();
}

class _WidgetPreviewScaffoldState extends State<WidgetPreviewScaffold>
    with WidgetsBindingObserver {
  static const _kOffscreenStageOffset = -100000.0;
  static const _kMaxCaptureRasterDimension = 4096.0;

  WebViewController? _webViewController;
  FlutterExceptionHandler? _originalOnError;
  late EmbedPreviewParams _embedParams;
  late bool _isEmbedSession;
  StreamSubscription<String>? _fragmentSubscription;
  final _activeStageSession = ValueNotifier<_StageCaptureSession?>(null);
  late final StagePreviewCaptureCallback _stageCaptureHost =
      _captureStagedPreview;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _embedParams = EmbedPreviewParams.fromCurrentUrl();
    _isEmbedSession = _embedParams.isEmbed;
    if (_isEmbedSession) {
      unawaited(SystemNavigator.selectMultiEntryHistory());
    }
    _fragmentSubscription = onUrlFragmentChange.listen((String fragment) {
      _applyEmbedParams(
        EmbedPreviewParams.fromFragment(fragment, baseUri: getBaseUri()),
      );
    });
    _originalOnError = FlutterError.onError;
    FlutterError.onError = _handleFlutterError;
    if (!_isEmbedSession) {
      widget.controller.attachStageCaptureHost(_stageCaptureHost);
      if (widget.enableWebView) {
        if (widget.controller.devToolsUri case final Uri devToolsUri) {
          _webViewController = WebViewController()..loadRequest(devToolsUri);
        }
      }
    }
  }

  @override
  void didUpdateWidget(WidgetPreviewScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.detachStageCaptureHost(_stageCaptureHost);
      if (!_isEmbedSession) {
        widget.controller.attachStageCaptureHost(_stageCaptureHost);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_fragmentSubscription?.cancel());
    _fragmentSubscription = null;
    widget.controller.detachStageCaptureHost(_stageCaptureHost);
    _activeStageSession.dispose();
    if (FlutterError.onError == _handleFlutterError) {
      FlutterError.onError = _originalOnError;
    }
    super.dispose();
  }

  void _checkMountedForCapture() {
    if (!mounted) {
      throw RpcException(
        WidgetPreviewScaffoldDtdServices.kNoValueForKey,
        'WidgetPreviewScaffold is not currently mounted.',
      );
    }
  }

  Future<void> _pumpStageFrame() async {
    final SchedulerBinding scheduler = SchedulerBinding.instance;
    final Duration timeout = widget.controller.stageFrameTimeout;
    try {
      if (scheduler.schedulerPhase == SchedulerPhase.postFrameCallbacks) {
        await Future<void>.value();
      }
      if (scheduler.schedulerPhase != SchedulerPhase.idle) {
        await scheduler.endOfFrame.timeout(timeout);
      }
      final Future<void> frameCompleted = scheduler.endOfFrame;
      scheduler.scheduleWarmUpFrame();
      await frameCompleted.timeout(timeout);
    } on TimeoutException {
      throw RpcException(
        WidgetPreviewScaffoldDtdServices.kNoValueForKey,
        'Timed out waiting for widget preview frame to render.',
      );
    }
  }

  Future<CapturePreviewResponse> _captureStagedPreview({
    required WidgetPreview preview,
    required PreviewCaptureRequest request,
    required double resolvedPixelRatio,
  }) async {
    _checkMountedForCapture();
    final session = _StageCaptureSession(
      preview: preview,
      request: request,
      resolvedPixelRatio: resolvedPixelRatio,
    );
    _activeStageSession.value = session;
    var skipUnmountPump = false;
    try {
      await _pumpStageFrame();
      _checkMountedForCapture();
      RenderRepaintBoundary? boundary =
          session.boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (session.consumePendingFrameRebuild() ||
          (boundary != null &&
              (boundary.debugNeedsLayout || boundary.debugNeedsPaint))) {
        await _pumpStageFrame();
        _checkMountedForCapture();
        boundary =
            session.boundaryKey.currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
      }
      if (request.pumpMs case final int rawPumpMs when rawPumpMs > 0) {
        final int clampedPumpMs = rawPumpMs.clamp(0, kMaxCapturePumpMs);
        await Future<void>.delayed(Duration(milliseconds: clampedPumpMs));
        _checkMountedForCapture();
        await _pumpStageFrame();
        _checkMountedForCapture();
        boundary =
            session.boundaryKey.currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
      }
      final bool hasErrorBox =
          boundary == null || _hasDescendantRenderErrorBox(boundary);
      if (hasErrorBox && !session.hasBuildError && !session.hasLayoutError) {
        session.recordDiagnostic(
          const PreviewDiagnostic(
            kind: .exception,
            phase: .build,
            summary:
                'An unexpected error occurred while building the widget preview.',
          ),
        );
      }
      final bool layoutAndBuildSucceeded =
          !hasErrorBox && !session.hasBuildError && !session.hasLayoutError;
      final double renderedWidth = layoutAndBuildSucceeded && boundary.hasSize
          ? boundary.size.width
          : 0.0;
      final double renderedHeight = layoutAndBuildSucceeded && boundary.hasSize
          ? boundary.size.height
          : 0.0;

      if (layoutAndBuildSucceeded) {
        if (renderedWidth <= 0 || renderedHeight <= 0) {
          session.recordDiagnostic(
            PreviewDiagnostic(
              kind: .zeroSize,
              phase: .layout,
              summary:
                  'Preview rendered with zero size (${renderedWidth}x$renderedHeight).',
            ),
          );
        } else {
          _auditRenderedSubtree(boundary, session);
        }
        if (SchedulerBinding.instance.transientCallbackCount > 0) {
          session.recordDiagnostic(
            const PreviewDiagnostic(
              kind: .pendingFrame,
              phase: .paint,
              severity: .warning,
              summary:
                  'Preview still has an active animation/frame callback after pump; pass pumpMs to settle.',
            ),
          );
        }
      }

      String? imageBase64;
      double reportedPixelRatio = resolvedPixelRatio;
      if (request.includeImage &&
          layoutAndBuildSucceeded &&
          !session.hasPaintException &&
          boundary.hasSize &&
          !boundary.debugNeedsPaint &&
          renderedWidth > 0 &&
          renderedHeight > 0) {
        final double maxDimension = math.max(renderedWidth, renderedHeight);
        final double rasterPixelRatio =
            maxDimension * resolvedPixelRatio > _kMaxCaptureRasterDimension
            ? _kMaxCaptureRasterDimension / maxDimension
            : resolvedPixelRatio;
        try {
          final ui.Image image = await boundary.toImage(
            pixelRatio: rasterPixelRatio,
          );
          try {
            final ByteData? byteData = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            if (byteData != null) {
              imageBase64 = base64Encode(Uint8List.sublistView(byteData));
              reportedPixelRatio = rasterPixelRatio;
            }
          } finally {
            image.dispose();
          }
        } on Object catch (error) {
          session.recordDiagnostic(
            PreviewDiagnostic(
              kind: .exception,
              phase: .paint,
              summary: error.toString(),
            ),
          );
        }
        _checkMountedForCapture();
      }

      final List<PreviewDiagnostic> diagnostics =
          List<PreviewDiagnostic>.unmodifiable(session.diagnostics);
      final bool hasErrors = diagnostics.any(
        (PreviewDiagnostic d) => d.severity == .error,
      );
      return CapturePreviewResponse(
        diagnostics: diagnostics,
        hasErrors: hasErrors,
        imageBase64: imageBase64,
        name: preview.name,
        pixelRatio: reportedPixelRatio,
        previewId: preview.id,
        renderedHeight: renderedHeight,
        renderedWidth: renderedWidth,
      );
    } on RpcException {
      skipUnmountPump = true;
      rethrow;
    } finally {
      if (mounted && identical(_activeStageSession.value, session)) {
        _activeStageSession.value = null;
        if (!skipUnmountPump) {
          await _pumpStageFrame();
        }
      }
    }
  }

  void _handleFlutterError(FlutterErrorDetails details) {
    if (_WidgetPreviewWrapperBox.isPerformingPreviewLayout) {
      if (_WidgetPreviewWrapperBox.reportedPreviewLayoutError != null) {
        return;
      }
      final stackTrace = details.stack ?? StackTrace.current;
      if (_isUnconstrainedPreviewError(details)) {
        _WidgetPreviewWrapperBox.reportedPreviewLayoutError = (
          const UnconstrainedWidgetPreviewException(),
          stackTrace,
        );
        if (!_WidgetPreviewWrapperBox.suppressLayoutErrorForwarding) {
          final customDetails = _createUnconstrainedPreviewErrorDetails(
            details,
          );
          (_originalOnError ?? FlutterError.presentError)(customDetails);
        }
        return;
      }
      _WidgetPreviewWrapperBox.reportedPreviewLayoutError = (
        details.exception,
        stackTrace,
      );
      if (!_WidgetPreviewWrapperBox.suppressLayoutErrorForwarding) {
        (_originalOnError ?? FlutterError.presentError)(details);
      }
      return;
    }

    final String message = details.exceptionAsString();
    final String summary = details.summary.toDescription();
    final String resolvedSummary = summary.isNotEmpty ? summary : message;
    final List<PreviewDiagnostic> overflows = PreviewDiagnostic.parseOverflows(
      message,
      summary: resolvedSummary,
    );
    if (_WidgetPreviewWrapperBox.activePaintingBox
        case final _WidgetPreviewWrapperBox paintingBox) {
      if (overflows.isNotEmpty) {
        for (final PreviewDiagnostic overflow in overflows) {
          paintingBox.onPaintDiagnostic?.call(overflow);
        }
      } else {
        paintingBox.onPaintDiagnostic?.call(
          PreviewDiagnostic(
            kind: .exception,
            phase: .paint,
            summary: resolvedSummary,
          ),
        );
      }
      if (!paintingBox.suppressErrorForwarding) {
        (_originalOnError ?? FlutterError.presentError)(details);
      }
      return;
    }

    if (overflows.isNotEmpty) {
      final PreviewWidgetElement? element = _findEnclosingPreviewElement(
        details,
      );
      if (element != null) {
        for (final PreviewDiagnostic overflow in overflows) {
          element.reportDiagnostic(overflow);
        }
        if (element.previewWidget.suppressFrameworkErrorForwarding) {
          return;
        }
      }
      (_originalOnError ?? FlutterError.presentError)(details);
      return;
    }

    final PreviewWidgetElement? buildingElement =
        PreviewWidgetElement.activeBuildingElement ??
        (_isBuildPhaseError(details)
            ? _findEnclosingPreviewElement(details)
            : null);
    if (buildingElement != null && buildingElement.mounted) {
      buildingElement.reportDiagnostic(
        PreviewDiagnostic(
          kind: .exception,
          phase: .build,
          summary: resolvedSummary,
        ),
      );
      if (buildingElement.previewWidget.suppressFrameworkErrorForwarding) {
        return;
      }
    }

    (_originalOnError ?? FlutterError.presentError)(details);
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) {
    final Uri uri = routeInformation.uri;
    final String fragment = uri.fragment.isNotEmpty
        ? uri.fragment
        : uri.toString();
    final routeParams = EmbedPreviewParams.fromFragment(
      fragment,
      baseUri: getBaseUri(),
    );
    if (routeParams.isEmbed) {
      _applyEmbedParams(routeParams);
      return SynchronousFuture<bool>(true);
    }
    if (_isEmbedSession || _embedParams.isEmbed) {
      return SynchronousFuture<bool>(true);
    }
    return super.didPushRouteInformation(routeInformation);
  }

  void _applyEmbedParams(EmbedPreviewParams updated) {
    if (!mounted || updated == _embedParams) {
      return;
    }
    if (!_isEmbedSession && updated.isEmbed) {
      widget.controller.detachStageCaptureHost(_stageCaptureHost);
      unawaited(SystemNavigator.selectMultiEntryHistory());
    }
    setState(() {
      _embedParams = updated;
      if (updated.isEmbed) {
        _isEmbedSession = true;
      }
    });
  }

  double _readEmbedZoom() =>
      _embedParams.zoom ?? EmbedPreviewParams.kDefaultZoom;

  void _handleEmbedZoomChanged(double zoom) {
    final EmbedPreviewParams updated = _embedParams.withZoom(zoom);
    if (updated == _embedParams) {
      return;
    }
    _applyEmbedParams(updated);
    notifyEmbedZoomChanged(updated.zoom ?? EmbedPreviewParams.kDefaultZoom);
  }

  void _handleEmbedParamsChanged(EmbedPreviewParams updated) {
    if (updated == _embedParams) {
      return;
    }
    _applyEmbedParams(updated);
    replaceEmbedUrl(updated.toFragment(baseUri: getBaseUri()));
  }

  @override
  Widget build(BuildContext context) {
    if (_isEmbedSession || _embedParams.isEmbed) {
      return EmbedPreviewScaffold(
        controller: widget.controller,
        currentZoom: _readEmbedZoom,
        ideTheme: widget.ideTheme,
        onParamsChanged: _handleEmbedParamsChanged,
        onZoomChanged: _handleEmbedZoomChanged,
        params: _embedParams,
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: themeFor(
        isDarkTheme: false,
        ideTheme: widget.ideTheme,
        theme: ThemeData(),
      ),
      darkTheme: themeFor(
        isDarkTheme: true,
        ideTheme: widget.ideTheme,
        theme: ThemeData.dark(),
      ),
      themeMode: widget.ideTheme.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: Material(
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: <Widget>[
            OutlineDecoration.onlyTop(
              child: ValueListenableBuilder(
                valueListenable: widget.controller.widgetInspectorVisible,
                builder: (context, widgetInspectorVisible, previewView) {
                  if (!widgetInspectorVisible) {
                    return previewView!;
                  }
                  return SplitPane(
                    axis: Axis.horizontal,
                    initialFractions: const [0.7, 0.3],
                    children: [
                      OutlineDecoration.onlyRight(child: previewView!),
                      OutlineDecoration.onlyLeft(
                        child:
                            widget.enableWebView && _webViewController != null
                            ? WebViewWidget(controller: _webViewController!)
                            : Container(),
                      ),
                    ],
                  );
                },
                // Display the previewer
                child: Column(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(8.0),
                        child: WidgetPreviews(controller: widget.controller),
                      ),
                    ),
                    WidgetPreviewControls(controller: widget.controller),
                  ],
                ),
              ),
            ),
            Positioned(
              left: _kOffscreenStageOffset,
              top: _kOffscreenStageOffset,
              child: ValueListenableBuilder<_StageCaptureSession?>(
                valueListenable: _activeStageSession,
                builder: (context, session, _) {
                  if (session == null) {
                    return const SizedBox.shrink();
                  }
                  return _StagedPreviewHost(
                    key: ObjectKey(session),
                    session: session,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The set of controls used to control the preview environment.
class WidgetPreviewControls extends StatelessWidget {
  const WidgetPreviewControls({super.key, required this.controller});

  static const _controlsPadding = 20.0;
  static const _compactControlsBreakpoint = 480.0;

  final WidgetPreviewScaffoldController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(
        bottom: _controlsPadding,
        left: _controlsPadding,
        right: _controlsPadding,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < _compactControlsBreakpoint) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PreviewSearchControls(controller: controller),
                const VerticalSpacer(),
                ValueListenableBuilder<bool>(
                  valueListenable: controller.editorServiceAvailable,
                  builder: (context, editorServiceAvailable, _) {
                    return Wrap(
                      spacing: intermediateSpacing,
                      runSpacing: denseSpacing,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Wrap(
                          spacing: intermediateSpacing,
                          runSpacing: denseSpacing,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            LayoutTypeSelector(controller: controller),
                            if (editorServiceAvailable)
                              FilterBySelectedFileToggle(
                                controller: controller,
                              ),
                            WidgetInspectorToggle(controller: controller),
                          ],
                        ),
                        WidgetPreviewerRestartButton(controller: controller),
                      ],
                    );
                  },
                ),
              ],
            );
          }
          return Row(
            children: [
              LayoutTypeSelector(controller: controller),
              ValueListenableBuilder<bool>(
                valueListenable: controller.editorServiceAvailable,
                builder: (context, editorServiceAvailable, _) {
                  if (!editorServiceAvailable) {
                    return const SizedBox.shrink();
                  }
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const HorizontalSpacer(),
                      FilterBySelectedFileToggle(controller: controller),
                    ],
                  );
                },
              ),
              const HorizontalSpacer(),
              Expanded(child: PreviewSearchControls(controller: controller)),
              const HorizontalSpacer(),
              WidgetInspectorToggle(controller: controller),
              const Spacer(),
              WidgetPreviewerRestartButton(controller: controller),
            ],
          );
        },
      ),
    );
  }
}

/// Renders the set of currently selected widget previews.
class WidgetPreviews extends StatelessWidget {
  const WidgetPreviews({super.key, required this.controller});

  final WidgetPreviewScaffoldController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WidgetPreviewGroups>(
      valueListenable: controller.filteredPreviewSetListenable,
      builder: (context, previewGroups, _) {
        if (previewGroups.isEmpty) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [NoPreviewsDetectedWidget()],
          );
        }
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final previewGroupsList = previewGroups.toList();
            return WidgetPreviewerWindowConstraints(
              constraints: constraints,
              child: ListView.builder(
                itemCount: previewGroups.length,
                itemBuilder: (context, index) {
                  return WidgetPreviewGroupWidget(
                    controller: controller,
                    group: previewGroupsList[index],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

/// Suffix appended by Flutter's `DebugOverflowIndicatorMixin` on overflowing
/// `RenderFlex` instances.
const kOverflowingRenderFlexSuffix = ' OVERFLOWING';
const _kBuildingContextPrefix = 'building ';

/// Maximum allowed `pumpMs` delay for off-screen preview capture.
const kMaxCapturePumpMs = 2000;
const _kMaxSubtreeWarnings = 5;
const _kMaxTruncatedTextChars = 40;
const _kMinTapTargetSize = 48.0;

void _auditRenderedSubtree(
  RenderRepaintBoundary root,
  _StageCaptureSession session,
) {
  var truncatedCount = 0;
  var smallTapCount = 0;
  final seenTapBoxes = <Rect>{};
  final bool checkSmallTapTargets =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  void visit(RenderObject node) {
    if (truncatedCount >= _kMaxSubtreeWarnings &&
        (!checkSmallTapTargets || smallTapCount >= _kMaxSubtreeWarnings)) {
      return;
    }
    if (node is RenderParagraph &&
        node.didExceedMaxLines &&
        truncatedCount < _kMaxSubtreeWarnings) {
      truncatedCount++;
      final String plainText = node.text.toPlainText();
      final String snippet = plainText.length > _kMaxTruncatedTextChars
          ? '${plainText.substring(0, _kMaxTruncatedTextChars)}...'
          : plainText;
      session.recordDiagnostic(
        PreviewDiagnostic(
          kind: .textTruncated,
          phase: .layout,
          severity: .warning,
          targetType: 'RenderParagraph',
          summary: 'Text truncated ("$snippet").',
        ),
      );
    } else if (checkSmallTapTargets &&
        node is RenderSemanticsAnnotations &&
        node.hasSize &&
        smallTapCount < _kMaxSubtreeWarnings &&
        (node.properties.onTap != null ||
            node.properties.onLongPress != null)) {
      final Size s = node.size;
      if (s.width.isFinite &&
          s.height.isFinite &&
          s.width > 0 &&
          s.height > 0 &&
          (s.width < _kMinTapTargetSize || s.height < _kMinTapTargetSize)) {
        final Rect rect = MatrixUtils.transformRect(
          node.getTransformTo(root),
          Offset.zero & s,
        );
        if (seenTapBoxes.add(rect)) {
          smallTapCount++;
          session.recordDiagnostic(
            PreviewDiagnostic(
              kind: .smallTapTarget,
              phase: .layout,
              severity: .warning,
              targetType: node.runtimeType.toString(),
              summary:
                  'Tap target ${s.width.round()}x${s.height.round()} is smaller than 48x48dp.',
            ),
          );
        }
      }
    }
    node.visitChildren(visit);
  }

  root.visitChildren(visit);
}

bool _anyRenderObject(RenderObject root, bool Function(RenderObject) test) {
  if (test(root)) {
    return true;
  }
  var found = false;
  root.visitChildren((RenderObject child) {
    if (!found && _anyRenderObject(child, test)) {
      found = true;
    }
  });
  return found;
}

bool _hasDescendantRenderErrorBox(RenderObject root) =>
    _anyRenderObject(root, (RenderObject node) => node is RenderErrorBox);

bool _hasOverflowingRenderFlex(RenderObject root) => _anyRenderObject(
  root,
  (RenderObject node) =>
      node is RenderFlex &&
      node.toStringShort().endsWith(kOverflowingRenderFlexSuffix),
);

bool _isBuildPhaseError(FlutterErrorDetails details) {
  final String? contextDescription = details.context?.toDescription();
  return contextDescription != null &&
      contextDescription.startsWith(_kBuildingContextPrefix);
}

PreviewWidgetElement? _findEnclosingPreviewElement(
  FlutterErrorDetails details,
) {
  final InformationCollector? collector = details.informationCollector;
  if (collector == null) {
    return null;
  }
  for (final DiagnosticsNode node in collector()) {
    if (node is DiagnosticsDebugCreator && node.value is DebugCreator) {
      final Element creatorElement = (node.value! as DebugCreator).element;
      if (!creatorElement.mounted) {
        continue;
      }
      if (creatorElement is PreviewWidgetElement) {
        return creatorElement;
      }
      PreviewWidgetElement? ancestor;
      creatorElement.visitAncestorElements((Element element) {
        if (element is PreviewWidgetElement) {
          ancestor = element;
          return false;
        }
        return true;
      });
      if (ancestor != null && ancestor!.mounted) {
        return ancestor;
      }
    }
  }
  return null;
}

const _kDefaultStageWindowSize = Size(800.0, 600.0);

class _StageCaptureSession {
  _StageCaptureSession({
    required this.preview,
    required this.request,
    required this.resolvedPixelRatio,
  });

  final boundaryKey = GlobalKey();
  final diagnostics = <PreviewDiagnostic>[];
  final WidgetPreview preview;
  final PreviewCaptureRequest request;
  final double resolvedPixelRatio;

  bool hasBuildError = false;
  bool hasLayoutError = false;
  bool hasPaintException = false;
  bool _needsFollowUpFrame = false;

  bool consumePendingFrameRebuild() {
    final bool pending = _needsFollowUpFrame;
    _needsFollowUpFrame = false;
    return pending;
  }

  void recordDiagnostic(PreviewDiagnostic diagnostic) {
    if (hasBuildError &&
        diagnostic.phase == PreviewDiagnosticPhase.paint &&
        diagnostic.kind == PreviewDiagnosticKind.overflow) {
      return;
    }
    if (diagnostic.phase == PreviewDiagnosticPhase.build) {
      hasBuildError = true;
    } else if (diagnostic.phase == PreviewDiagnosticPhase.layout) {
      hasLayoutError = true;
    } else if (diagnostic.phase == PreviewDiagnosticPhase.paint &&
        diagnostic.kind == PreviewDiagnosticKind.exception) {
      hasPaintException = true;
    }
    if (!diagnostics.contains(diagnostic)) {
      diagnostics.add(diagnostic);
    }
  }

  void recordLayoutError(Object error, StackTrace _) {
    final PreviewDiagnosticKind kind =
        error is UnconstrainedWidgetPreviewException ||
            _isUnconstrainedError(error)
        ? .unconstrained
        : .exception;
    recordDiagnostic(
      PreviewDiagnostic(kind: kind, phase: .layout, summary: error.toString()),
    );
    _needsFollowUpFrame = true;
  }
}

/// Wraps [child] with the [DefaultAssetBundle], [MediaQuery], [Theme], and
/// [WidgetPreviewerWindowConstraints] environment for [preview].
class WidgetPreviewEnvironment extends StatelessWidget {
  const WidgetPreviewEnvironment({
    required this.brightness,
    required this.child,
    required this.preview,
    required this.windowConstraints,
    this.height,
    this.pixelRatio,
    this.textScaleFactor,
    this.width,
    super.key,
  });

  final Brightness brightness;
  final Widget child;
  final double? height;
  final double? pixelRatio;
  final WidgetPreview preview;
  final double? textScaleFactor;
  final double? width;
  final BoxConstraints windowConstraints;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mediaQueryData = _applyPreviewMediaQueryOverrides(
      base: MediaQuery.of(context),
      brightness: brightness,
      height: height,
      pixelRatio: pixelRatio,
      textScaleFactor: textScaleFactor,
      width: width,
    );
    final ThemeData baseTheme = brightness == Brightness.dark
        ? ThemeData.dark()
        : ThemeData.light();
    return WidgetPreviewerWindowConstraints(
      constraints: windowConstraints,
      child: DefaultAssetBundle(
        bundle: PreviewAssetBundle(packageName: preview.packageName),
        child: MediaQuery(
          data: mediaQueryData,
          child: Theme(data: baseTheme, child: child),
        ),
      ),
    );
  }
}

class _StagedPreviewHost extends StatelessWidget {
  const _StagedPreviewHost({required this.session, super.key});

  final _StageCaptureSession session;

  @override
  Widget build(BuildContext context) {
    final _StageCaptureSession(
      :GlobalKey boundaryKey,
      :WidgetPreview preview,
      :PreviewCaptureRequest request,
      :double resolvedPixelRatio,
    ) = session;
    final Brightness resolvedBrightness =
        request.brightness ??
        preview.brightness ??
        MediaQuery.platformBrightnessOf(context);
    final double? constrainedWidth = request.width ?? preview.finiteWidth;
    final double? constrainedHeight = request.height ?? preview.finiteHeight;
    final double? resolvedTextScaleFactor = switch (request.textScaleFactor ??
        preview.finiteTextScaleFactor) {
      final double scale when scale.isFinite => scale,
      _ => null,
    };

    final Size windowSize = MediaQuery.sizeOf(context);
    final double fallbackWindowWidth =
        windowSize.width.isFinite && windowSize.width > 0
        ? windowSize.width
        : _kDefaultStageWindowSize.width;
    final double fallbackWindowHeight =
        windowSize.height.isFinite && windowSize.height > 0
        ? windowSize.height
        : _kDefaultStageWindowSize.height;
    final rootWindowConstraints = BoxConstraints.loose(
      Size(
        constrainedWidth ?? fallbackWindowWidth,
        constrainedHeight ?? fallbackWindowHeight,
      ),
    );

    return WidgetPreviewEnvironment(
      brightness: resolvedBrightness,
      height: constrainedHeight,
      pixelRatio: resolvedPixelRatio,
      preview: preview,
      textScaleFactor: resolvedTextScaleFactor,
      width: constrainedWidth,
      windowConstraints: rootWindowConstraints,
      child: ScaffoldMessenger(
        child: ScrollNotificationObserver(
          child: RepaintBoundary(
            key: boundaryKey,
            child: Material(
              type: MaterialType.transparency,
              child: SizedBox(
                width: constrainedWidth,
                height: constrainedHeight,
                child: WidgetPreviewWrapper(
                  onLayoutError: session.recordLayoutError,
                  onPaintDiagnostic: session.recordDiagnostic,
                  previewerConstraints: const BoxConstraints(),
                  suppressErrorForwarding: true,
                  child: EnableWidgetInspectorScope(
                    child: PreviewWidget(
                      onDiagnostic: session.recordDiagnostic,
                      preview: preview,
                      suppressFrameworkErrorForwarding: true,
                      child: _StagedPreviewBuilder(
                        preview: preview,
                        session: session,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StagedPreviewBuilder extends StatelessWidget {
  const _StagedPreviewBuilder({required this.preview, required this.session});

  final WidgetPreview preview;
  final _StageCaptureSession session;

  @override
  Widget build(BuildContext context) {
    try {
      return WidgetPreviewLocalizations(
        localizationsData: preview.localizations,
        child: WidgetPreviewTheming(
          theme: preview.theme,
          child: preview.previewBuilder(),
        ),
      );
    } on Object catch (error) {
      session.recordDiagnostic(
        PreviewDiagnostic(
          kind: .exception,
          phase: .build,
          summary: error.toString(),
        ),
      );
      return const SizedBox.shrink();
    }
  }
}

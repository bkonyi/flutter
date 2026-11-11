// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/widget_previews.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widget_preview_scaffold/src/theme/ide_theme.dart';
import 'package:widget_preview_scaffold/src/utils/url/url.dart';
import 'package:widget_preview_scaffold/src/widget_preview.dart';
import 'package:widget_preview_scaffold/src/widget_preview_rendering.dart';
import 'package:widget_preview_scaffold/src/widget_preview_scaffold_controller.dart';

/// Chromeless single-preview canvas for `#embed=1` mode.
class EmbedPreviewScaffold extends StatelessWidget {
  const EmbedPreviewScaffold({
    required this.controller,
    required this.params,
    this.ideTheme = const IdeTheme(),
    super.key,
  });

  static const _kDefaultWindowSize = Size(800.0, 600.0);
  static const _kMaxStatusCardWidth = 480.0;
  static const _kRootPageKey = ValueKey<String>('embed-preview-root');
  static const _kStatusCardPadding = 16.0;
  static const _kStatusSectionSpacing = 8.0;

  final WidgetPreviewScaffoldController controller;
  final IdeTheme ideTheme;
  final EmbedPreviewParams params;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: controller.previewsRevisionListenable,
      builder: (BuildContext context, int _, Widget? _) {
        final PreviewLookupResult lookup = controller.resolvePreviewMatch(
          params.previewId,
        );
        final WidgetPreview? matchedPreview = switch (lookup) {
          PreviewLookupMatch(:final WidgetPreview preview) => preview,
          PreviewLookupMissing() || PreviewLookupAmbiguous() => null,
        };
        final Brightness? explicitBrightness =
            params.brightness ?? matchedPreview?.brightness;
        final ThemeMode themeMode = switch (explicitBrightness) {
          Brightness.light => ThemeMode.light,
          Brightness.dark => ThemeMode.dark,
          null =>
            ideTheme.ideSpecifiedTheme
                ? (ideTheme.isDarkMode ? ThemeMode.dark : ThemeMode.light)
                : ThemeMode.system,
        };
        // Use builder + Navigator instead of MaterialApp(home: ...) so
        // WidgetsApp._usesNavigator stays false (never enabling
        // SingleEntryBrowserHistory or Navigator.pushNamed on hash changes)
        // while keeping a Navigator/Overlay ancestor for previewed widgets.
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: themeMode,
          title: null,
          builder: (BuildContext context, Widget? _) {
            return Navigator(
              pages: <Page<void>>[
                MaterialPage<void>(
                  key: _kRootPageKey,
                  child: Scaffold(
                    body: LayoutBuilder(
                      builder:
                          (BuildContext context, BoxConstraints constraints) {
                            if (lookup case PreviewLookupMatch(
                              :final WidgetPreview preview,
                            ) when !preview.hasError) {
                              return _buildMatchedPreview(
                                context: context,
                                constraints: constraints,
                                preview: preview,
                              );
                            }
                            return _buildStatusView(
                              context: context,
                              constraints: constraints,
                              lookup: lookup,
                            );
                          },
                    ),
                  ),
                ),
              ],
              onDidRemovePage: (Page<Object?> _) {},
            );
          },
        );
      },
    );
  }

  Widget _buildMatchedPreview({
    required BuildContext context,
    required BoxConstraints constraints,
    required WidgetPreview preview,
  }) {
    final double? previewWidth = switch (preview.size?.width) {
      final double w when w.isFinite => w,
      _ => null,
    };
    final double? previewHeight = switch (preview.size?.height) {
      final double h when h.isFinite => h,
      _ => null,
    };
    final double? resolvedWidth = params.width ?? previewWidth;
    final double? resolvedHeight = params.height ?? previewHeight;
    final Brightness resolvedBrightness =
        params.brightness ?? preview.brightness ?? Theme.of(context).brightness;
    final double? resolvedTextScale = switch (params.textScale ??
        preview.textScaleFactor) {
      final double scale when scale.isFinite && scale > 0 => scale,
      _ => null,
    };

    final double constraintWidth =
        resolvedWidth ??
        (constraints.hasBoundedWidth
            ? constraints.maxWidth
            : _kDefaultWindowSize.width);
    final double constraintHeight =
        resolvedHeight ??
        (constraints.hasBoundedHeight
            ? constraints.maxHeight
            : _kDefaultWindowSize.height);
    final windowConstraints = BoxConstraints.loose(
      Size(constraintWidth, constraintHeight),
    );

    MediaQueryData mediaQueryData = MediaQuery.of(
      context,
    ).copyWith(platformBrightness: resolvedBrightness);
    if (resolvedTextScale != null) {
      mediaQueryData = mediaQueryData.copyWith(
        textScaler: TextScaler.linear(resolvedTextScale),
      );
    }
    if (resolvedWidth != null || resolvedHeight != null) {
      mediaQueryData = mediaQueryData.copyWith(
        size: Size(
          resolvedWidth ?? mediaQueryData.size.width,
          resolvedHeight ?? mediaQueryData.size.height,
        ),
      );
    }

    final ThemeData baseTheme = resolvedBrightness == Brightness.dark
        ? ThemeData.dark()
        : ThemeData.light();

    return WidgetPreviewerWindowConstraints(
      constraints: windowConstraints,
      child: DefaultAssetBundle(
        bundle: PreviewAssetBundle(packageName: preview.packageName),
        child: MediaQuery(
          data: mediaQueryData,
          child: Theme(
            data: baseTheme,
            child: _EmbedPreviewContent(
              key: ValueKey<String>(preview.id),
              controller: controller,
              preview: preview,
              previewerConstraints: windowConstraints,
              resolvedHeight: resolvedHeight,
              resolvedWidth: resolvedWidth,
              viewportConstraints: constraints,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusView({
    required BuildContext context,
    required BoxConstraints constraints,
    required PreviewLookupResult lookup,
  }) {
    final (String title, String message) = switch (lookup) {
      PreviewLookupMatch(:final WidgetPreview preview) => (
        'Preview has errors',
        preview.errorMessage ?? '${preview.libraryUri} has errors!',
      ),
      PreviewLookupAmbiguous(
        :final List<String> candidateIds,
        :final String previewId,
      ) =>
        (
          'Ambiguous preview name',
          'Preview name "$previewId" is ambiguous; specify one of:\n'
              '${candidateIds.join('\n')}',
        ),
      PreviewLookupMissing(
        :final List<String> availableIds,
        :final String? previewId,
      ) =>
        switch (previewId) {
          null => (
            'No preview selected',
            availableIds.isEmpty
                ? 'No widget previews were detected in this project.'
                : 'Specify a previewId in the URL fragment. Available previews:\n'
                      '${availableIds.join('\n')}',
          ),
          final String id => (
            'Preview not found',
            availableIds.isEmpty
                ? 'Preview "$id" was not found.'
                : 'Preview "$id" was not found. Available previews:\n'
                      '${availableIds.join('\n')}',
          ),
        },
    };

    final ThemeData theme = Theme.of(context);
    return WidgetPreviewerWindowConstraints(
      constraints: constraints,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(_kStatusCardPadding),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kMaxStatusCardWidth),
            child: Card.outlined(
              child: Padding(
                padding: const EdgeInsets.all(_kStatusCardPadding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: _kStatusSectionSpacing),
                    SelectableText(message, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmbedPreviewContent extends StatefulWidget {
  const _EmbedPreviewContent({
    required this.controller,
    required this.preview,
    required this.previewerConstraints,
    required this.viewportConstraints,
    this.resolvedHeight,
    this.resolvedWidth,
    super.key,
  });

  final WidgetPreviewScaffoldController controller;
  final WidgetPreview preview;
  final BoxConstraints previewerConstraints;
  final double? resolvedHeight;
  final double? resolvedWidth;
  final BoxConstraints viewportConstraints;

  @override
  State<_EmbedPreviewContent> createState() => _EmbedPreviewContentState();
}

class _EmbedPreviewContentState extends State<_EmbedPreviewContent> {
  ({Object error, StackTrace stackTrace})? _layoutError;

  @override
  void didUpdateWidget(_EmbedPreviewContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preview != widget.preview ||
        oldWidget.resolvedWidth != widget.resolvedWidth ||
        oldWidget.resolvedHeight != widget.resolvedHeight ||
        oldWidget.previewerConstraints != widget.previewerConstraints) {
      _layoutError = null;
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    _layoutError = null;
  }

  void _handleLayoutError(Object error, StackTrace stackTrace) {
    if (_layoutError != null) {
      return;
    }
    _layoutError = (error: error, stackTrace: stackTrace);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Widget _buildSizedPreviewFrame(Widget child) {
    final _EmbedPreviewContent(
      :BoxConstraints previewerConstraints,
      :double? resolvedHeight,
      :double? resolvedWidth,
      :BoxConstraints viewportConstraints,
    ) = widget;
    final wrapped = SizedBox(
      width: resolvedWidth,
      height: resolvedHeight,
      child: WidgetPreviewWrapper(
        previewerConstraints: previewerConstraints,
        onLayoutError: _handleLayoutError,
        child: child,
      ),
    );
    final bool needsHorizontalScroll =
        resolvedWidth != null &&
        viewportConstraints.hasBoundedWidth &&
        resolvedWidth > viewportConstraints.maxWidth;
    final bool needsVerticalScroll =
        resolvedHeight != null &&
        viewportConstraints.hasBoundedHeight &&
        resolvedHeight > viewportConstraints.maxHeight;
    if (needsHorizontalScroll && needsVerticalScroll) {
      return SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: wrapped,
        ),
      );
    }
    if (needsHorizontalScroll) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: viewportConstraints.hasBoundedHeight
                ? viewportConstraints.maxHeight
                : 0.0,
          ),
          child: Center(child: wrapped),
        ),
      );
    }
    if (needsVerticalScroll) {
      return SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: viewportConstraints.hasBoundedWidth
                ? viewportConstraints.maxWidth
                : 0.0,
          ),
          child: Center(child: wrapped),
        ),
      );
    }
    return Center(child: wrapped);
  }

  @override
  Widget build(BuildContext context) {
    final _EmbedPreviewContent(
      :WidgetPreviewScaffoldController controller,
      :WidgetPreview preview,
      :BoxConstraints previewerConstraints,
    ) = widget;
    if (_layoutError case (:final Object error, :final StackTrace stackTrace)) {
      return Center(
        child: WidgetPreviewErrorWidget(
          controller: controller,
          error: error,
          size: errorPreviewSizeFor(previewerConstraints),
          stackTrace: stackTrace,
          title: 'Failed to layout widget preview: ',
        ),
      );
    }
    try {
      final PreviewLocalizationsData? localizationsData = preview.localizations;
      final PreviewThemeData? themeData = preview.theme;
      final previewWidget = EnableWidgetInspectorScope(
        child: PreviewWidget(preview: preview, child: preview.previewBuilder()),
      );
      return WidgetPreviewTheming(
        theme: themeData,
        child: ScrollNotificationObserver(
          child: WidgetPreviewLocalizations(
            localizationsData: localizationsData,
            child: _buildSizedPreviewFrame(previewWidget),
          ),
        ),
      );
    } on Object catch (error, stackTrace) {
      return Center(
        child: WidgetPreviewErrorWidget(
          controller: controller,
          error: error,
          size: errorPreviewSizeFor(previewerConstraints),
          stackTrace: stackTrace,
        ),
      );
    }
  }
}

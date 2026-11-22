// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widget_preview_scaffold/src/controls.dart';
import 'package:widget_preview_scaffold/src/embed_live_controls.dart';
import 'package:widget_preview_scaffold/src/embed_selection.dart';
import 'package:widget_preview_scaffold/src/theme/ide_theme.dart';
import 'package:widget_preview_scaffold/src/utils/url/url.dart';
import 'package:widget_preview_scaffold/src/widget_preview.dart';
import 'package:widget_preview_scaffold/src/widget_preview_rendering.dart';
import 'package:widget_preview_scaffold/src/widget_preview_scaffold_controller.dart';

const _kDarkPreviewSurfaceColor = Color(0xFF18181B);
const _kLightPreviewSurfaceColor = Color(0xFFFAFAFA);

Color _surfaceColorFor(Brightness brightness) => brightness == .dark
    ? _kDarkPreviewSurfaceColor
    : _kLightPreviewSurfaceColor;

/// Chromeless single-preview or all-previews gallery canvas for `#embed=1` mode,
/// or interactive `/live` viewer when [EmbedPreviewParams.showControls] is set.
class EmbedPreviewScaffold extends StatefulWidget {
  const EmbedPreviewScaffold({
    required this.controller,
    required this.currentZoom,
    required this.onZoomChanged,
    required this.params,
    this.ideTheme = const IdeTheme(),
    this.onParamsChanged,
    super.key,
  });

  /// Controller providing discovered previews and DTD services.
  final WidgetPreviewScaffoldController controller;

  /// Returns the current interactive canvas zoom multiplier.
  final ValueGetter<double> currentZoom;

  /// Host IDE theme settings used when no explicit brightness override is set.
  final IdeTheme ideTheme;

  /// Invoked when interactive `/live` controls update [params].
  final ValueChanged<EmbedPreviewParams>? onParamsChanged;

  /// Invoked when keyboard or trackpad zoom controls change zoom.
  final ValueChanged<double> onZoomChanged;

  /// Parsed embed URL fragment parameters governing rendered previews and UI.
  final EmbedPreviewParams params;

  @override
  State<EmbedPreviewScaffold> createState() => _EmbedPreviewScaffoldState();
}

class _EmbedPreviewScaffoldState extends State<EmbedPreviewScaffold> {
  static const _kCardContentPadding = 12.0;
  static const _kCardHeaderChevronSize = 18.0;
  static const _kCardHeaderHoverAlpha = 0.06;
  static const _kCardHeaderVerticalPadding = 8.0;
  static const _kCardSpacing = 12.0;
  static const _kDefaultWindowSize = Size(800.0, 600.0);
  static const _kGalleryPadding = 16.0;
  static const _kGallerySplitSubHeaderVerticalPadding = 6.0;
  static const _kGroupHeaderSpacing = 8.0;
  static const _kGroupSpacing = 24.0;
  static const _kMaxStatusCardWidth = 480.0;
  static const _kMinSplitPaneExtent = 160.0;
  static const _kNoPreviewsMessage =
      'No widget previews were detected in this project.';
  static const _kNoPreviewsTitle = 'No widget previews detected';
  static const _kRootPageKey = ValueKey<String>('embed-preview-root');
  static const _kStatusCardPadding = 16.0;
  static const _kStatusSectionSpacing = 8.0;

  late final _selectionController = EmbedSelectionController(
    initialParams: widget.params,
  );
  var _isSplitBrightness = false;
  var _isSyncing = false;
  var _showBounds = false;
  String? _syncErrorMessage;

  EmbedPreviewParams get _params => widget.params;

  double get _zoom => _params.zoom ?? EmbedPreviewParams.kDefaultZoom;

  @override
  void didUpdateWidget(EmbedPreviewScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.params != widget.params) {
      _selectionController.syncFromParams(widget.params);
    }
  }

  void _handleParamsChanged(EmbedPreviewParams nextParams) {
    if (nextParams != _params) {
      widget.onParamsChanged?.call(nextParams);
    }
  }

  Future<void> _handleSyncPressed() async {
    if (_isSyncing) {
      return;
    }
    setState(() {
      _isSyncing = true;
      _syncErrorMessage = null;
    });
    try {
      final (:bool compileSuccess, :String? errorMessage) =
          await triggerLiveSync();
      if (!mounted) {
        return;
      }
      if (compileSuccess) {
        _selectionController.clearSelections();
        await widget.controller.dtdServices.syncViewerReload();
        if (!mounted) {
          return;
        }
      }
      setState(() {
        _isSyncing = false;
        _syncErrorMessage = compileSuccess
            ? null
            : (errorMessage ?? 'Preview compilation failed.');
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncErrorMessage = error.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _selectionController.dispose();
    super.dispose();
  }

  bool _isEditableTextFocused() {
    final BuildContext? focusContext =
        FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) {
      return false;
    }
    if (focusContext.widget case EditableText(readOnly: false)) {
      return true;
    }
    final EditableTextState? editableState = focusContext
        .findAncestorStateOfType<EditableTextState>();
    return editableState != null && !editableState.widget.readOnly;
  }

  void _emitZoom(double targetZoom) {
    final double clamped = clampPreviewZoom(targetZoom);
    if ((clamped - widget.currentZoom()).abs() > kPreviewZoomEpsilon) {
      widget.onZoomChanged(clamped);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final bool isAltPressed = HardwareKeyboard.instance.isAltPressed;
    final bool isCtrlOrMeta =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final LogicalKeyboardKey key = event.logicalKey;
    if (event is KeyDownEvent &&
        key == LogicalKeyboardKey.escape &&
        !isAltPressed &&
        !isCtrlOrMeta &&
        (_selectionController.selectMode ||
            (!_isEditableTextFocused() &&
                _selectionController.selections.isNotEmpty)) &&
        _selectionController.handleEscapeKey()) {
      return KeyEventResult.handled;
    }
    if (isAltPressed || _isEditableTextFocused()) {
      return KeyEventResult.ignored;
    }
    final FocusNode? primaryFocus = FocusManager.instance.primaryFocus;
    final bool isScopeIdle =
        primaryFocus == null || primaryFocus is FocusScopeNode;
    // When an interactive preview descendant holds primary focus, require
    // Ctrl/Cmd so unmodified keys are never stolen from focused controls.
    if (!isCtrlOrMeta && !isScopeIdle) {
      return KeyEventResult.ignored;
    }
    final bool isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      _emitZoom(widget.currentZoom() + kPreviewZoomStep);
      return KeyEventResult.handled;
    }
    if (!isShiftPressed &&
        (key == LogicalKeyboardKey.minus ||
            key == LogicalKeyboardKey.numpadSubtract)) {
      _emitZoom(widget.currentZoom() - kPreviewZoomStep);
      return KeyEventResult.handled;
    }
    if (!isShiftPressed &&
        (key == LogicalKeyboardKey.digit0 ||
            key == LogicalKeyboardKey.numpad0)) {
      _emitZoom(kDefaultPreviewZoom);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final EmbedPreviewScaffold(
      :WidgetPreviewScaffoldController controller,
      :IdeTheme ideTheme,
      :EmbedPreviewParams params,
    ) = widget;
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _handleKeyEvent,
      child: ValueListenableBuilder<int>(
        valueListenable: controller.previewsRevisionListenable,
        builder: (BuildContext context, int _, Widget? _) {
          final PreviewLookupResult? lookup = params.isAllPreviews
              ? null
              : controller.resolvePreviewMatch(params.previewId);
          final Brightness? explicitBrightness = switch (lookup) {
            PreviewLookupMatch(:final WidgetPreview preview) =>
              params.brightness ?? preview.brightness,
            PreviewLookupMissing() ||
            PreviewLookupAmbiguous() ||
            null => params.brightness,
          };
          final ThemeMode themeMode = switch (explicitBrightness) {
            .light => .light,
            .dark => .dark,
            null =>
              ideTheme.ideSpecifiedTheme
                  ? (ideTheme.isDarkMode ? .dark : .light)
                  : .system,
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
              final Widget previewStage = PreviewPointerScrollZoom(
                zoom: _zoom,
                onZoomChanged: _emitZoom,
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    if (lookup == null) {
                      final List<WidgetPreviewGroup> groups =
                          controller.allPreviewGroups;
                      if (groups.isEmpty) {
                        return _buildStatusView(
                          context: context,
                          constraints: constraints,
                          message: _kNoPreviewsMessage,
                          showStarterSnippet: true,
                          title: _kNoPreviewsTitle,
                        );
                      }
                      return _buildAllPreviewsGallery(
                        context: context,
                        constraints: constraints,
                        groups: groups,
                      );
                    }
                    if (lookup case PreviewLookupMatch(
                      :final WidgetPreview preview,
                    ) when !preview.hasError) {
                      if (_isSplitBrightness) {
                        return _buildSplitBrightnessView(
                          context: context,
                          outerConstraints: constraints,
                          preview: preview,
                        );
                      }
                      final BoxConstraints stageConstraints =
                          params.showControls
                          ? EmbedLiveResizableFrame.deflateStageConstraints(
                              constraints,
                            )
                          : constraints;
                      return _buildPreviewSubtree(
                        context: context,
                        onParamsChanged: params.showControls
                            ? _handleParamsChanged
                            : null,
                        outerConstraints: stageConstraints,
                        params: params,
                        preview: preview,
                        viewportConstraints: stageConstraints,
                      );
                    }
                    final (String title, String message) = _lookupStatusDetails(
                      lookup,
                    );
                    return _buildStatusView(
                      context: context,
                      constraints: constraints,
                      message: message,
                      title: title,
                    );
                  },
                ),
              );
              return Navigator(
                pages: <Page<void>>[
                  MaterialPage<void>(
                    key: _kRootPageKey,
                    child: Scaffold(
                      body: params.showControls
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                EmbedLiveTopBar(
                                  isSplitBrightness: _isSplitBrightness,
                                  isSyncing: _isSyncing,
                                  onBoundsToggled: () => setState(
                                    () => _showBounds = !_showBounds,
                                  ),
                                  onDismissSyncError: () =>
                                      setState(() => _syncErrorMessage = null),
                                  onParamsChanged: _handleParamsChanged,
                                  onSplitBrightnessChanged: (bool enabled) {
                                    if (_isSplitBrightness != enabled) {
                                      setState(
                                        () => _isSplitBrightness = enabled,
                                      );
                                    }
                                  },
                                  onSyncPressed: _handleSyncPressed,
                                  onZoomChanged: _emitZoom,
                                  params: params,
                                  previews: controller.previews.toList(
                                    growable: false,
                                  ),
                                  resolvedPreviewId:
                                      lookup is PreviewLookupMatch
                                      ? lookup.preview.id
                                      : null,
                                  selectionController: _selectionController,
                                  showBounds: _showBounds,
                                  syncErrorMessage: _syncErrorMessage,
                                ),
                                Expanded(child: previewStage),
                                EmbedLiveSelectionBar(
                                  params: params,
                                  selectionController: _selectionController,
                                ),
                              ],
                            )
                          : previewStage,
                    ),
                  ),
                ],
                onDidRemovePage: (Page<Object?> _) {},
              );
            },
          );
        },
      ),
    );
  }

  ({
    Brightness resolvedBrightness,
    double? resolvedHeight,
    double? resolvedTextScale,
    double? resolvedWidth,
  })
  _resolvePreviewSettings(BuildContext context, WidgetPreview preview) {
    final EmbedPreviewParams params = _params;
    final double? candidateScale =
        params.textScale ?? preview.finiteTextScaleFactor;
    return (
      resolvedBrightness:
          params.brightness ??
          preview.brightness ??
          Theme.of(context).brightness,
      resolvedHeight: params.height ?? preview.finiteHeight,
      resolvedTextScale: candidateScale != null && candidateScale > 0
          ? candidateScale
          : null,
      resolvedWidth: params.width ?? preview.finiteWidth,
    );
  }

  (Widget, Widget) _buildLightDarkPanes({
    required Key darkKey,
    required bool expandVertically,
    required Key lightKey,
    required WidgetPreview preview,
    required ThemeData theme,
    String? badgeLabel,
    EdgeInsets bodyPadding = EdgeInsets.zero,
    double? fallbackWindowHeight,
  }) {
    Widget buildOne(Brightness brightness, String label, Key key) {
      final Widget body = ColoredBox(
        color: _surfaceColorFor(brightness),
        child: Padding(
          padding: bodyPadding,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints paneConstraints) =>
                _buildPreviewSubtree(
                  brightnessOverride: brightness,
                  context: context,
                  fallbackWindowHeight: fallbackWindowHeight,
                  outerConstraints: paneConstraints,
                  preview: preview,
                  viewportConstraints: paneConstraints,
                ),
          ),
        ),
      );
      return Card.outlined(
        key: key,
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: Column(
          mainAxisSize: expandVertically ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: _kCardContentPadding,
                vertical: expandVertically
                    ? _kCardHeaderVerticalPadding
                    : _kGallerySplitSubHeaderVerticalPadding,
              ),
              child: Row(
                children: <Widget>[
                  Text(
                    label,
                    style: expandVertically
                        ? theme.textTheme.titleSmall
                        : theme.textTheme.labelMedium,
                  ),
                  if (badgeLabel != null) ...<Widget>[
                    const Spacer(),
                    PreviewInfoBadge(label: badgeLabel),
                  ],
                ],
              ),
            ),
            const Divider(height: 1.0),
            if (expandVertically) Expanded(child: body) else body,
          ],
        ),
      );
    }

    return (
      buildOne(.light, 'Light', lightKey),
      buildOne(.dark, 'Dark', darkKey),
    );
  }

  Widget _buildSplitBrightnessView({
    required BuildContext context,
    required BoxConstraints outerConstraints,
    required WidgetPreview preview,
  }) {
    final double availableWidth =
        (outerConstraints.hasBoundedWidth
            ? outerConstraints.maxWidth
            : _kDefaultWindowSize.width) -
        _kGalleryPadding * 2;
    final double paneHeight = math.max(
      _kMinSplitPaneExtent,
      (outerConstraints.hasBoundedHeight
              ? outerConstraints.maxHeight
              : _kDefaultWindowSize.height) -
          _kGalleryPadding * 2,
    );
    final bool sideBySide =
        availableWidth >= _kMinSplitPaneExtent * 2 + _kCardSpacing;
    final (Widget lightPane, Widget darkPane) = _buildLightDarkPanes(
      badgeLabel: preview.name ?? preview.functionName,
      darkKey: const Key('embed-split-dark'),
      expandVertically: true,
      lightKey: const Key('embed-split-light'),
      preview: preview,
      theme: Theme.of(context),
    );
    final sideBySideRow = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(child: lightPane),
        const SizedBox(width: _kCardSpacing),
        Expanded(child: darkPane),
      ],
    );
    if (sideBySide && outerConstraints.hasBoundedHeight) {
      return Padding(
        padding: const EdgeInsets.all(_kGalleryPadding),
        child: sideBySideRow,
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(_kGalleryPadding),
      child: sideBySide
          ? SizedBox(height: paneHeight, child: sideBySideRow)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(height: paneHeight, child: lightPane),
                const SizedBox(height: _kCardSpacing),
                SizedBox(height: paneHeight, child: darkPane),
              ],
            ),
    );
  }

  Widget _buildPreviewSubtree({
    required BuildContext context,
    required BoxConstraints outerConstraints,
    required WidgetPreview preview,
    required BoxConstraints viewportConstraints,
    Brightness? brightnessOverride,
    double? fallbackWindowHeight,
    ValueChanged<EmbedPreviewParams>? onParamsChanged,
    EmbedPreviewParams? params,
  }) {
    final (
      :Brightness resolvedBrightness,
      :double? resolvedHeight,
      :double? resolvedTextScale,
      :double? resolvedWidth,
    ) = _resolvePreviewSettings(
      context,
      preview,
    );
    final Brightness appliedBrightness =
        brightnessOverride ?? resolvedBrightness;
    final windowConstraints = BoxConstraints.loose(
      Size(
        resolvedWidth ??
            (outerConstraints.hasBoundedWidth
                ? outerConstraints.maxWidth
                : _kDefaultWindowSize.width),
        resolvedHeight ??
            fallbackWindowHeight ??
            (outerConstraints.hasBoundedHeight
                ? outerConstraints.maxHeight
                : _kDefaultWindowSize.height),
      ),
    );

    return WidgetPreviewEnvironment(
      brightness: appliedBrightness,
      height: resolvedHeight,
      preview: preview,
      textScaleFactor: resolvedTextScale,
      width: resolvedWidth,
      windowConstraints: windowConstraints,
      child: _EmbedPreviewContent(
        key: ValueKey<String>(preview.id),
        brightness: appliedBrightness,
        controller: widget.controller,
        onParamsChanged: onParamsChanged,
        params: params,
        preview: preview,
        previewerConstraints: windowConstraints,
        resolvedHeight: resolvedHeight,
        resolvedWidth: resolvedWidth,
        selectionController: _selectionController,
        showBounds: _showBounds,
        textScale:
            resolvedTextScale ?? MediaQuery.textScalerOf(context).scale(1.0),
        viewportConstraints: viewportConstraints,
        zoom: _zoom,
      ),
    );
  }

  Widget _buildAllPreviewsGallery({
    required BuildContext context,
    required BoxConstraints constraints,
    required List<WidgetPreviewGroup> groups,
  }) {
    final ThemeData theme = Theme.of(context);
    final double fallbackWindowHeight =
        (constraints.hasBoundedHeight
            ? constraints.maxHeight
            : _kDefaultWindowSize.height) /
        2;
    final items = <_GalleryItem>[
      for (final (int groupIndex, WidgetPreviewGroup group)
          in groups.indexed) ...<_GalleryItem>[
        _GalleryGroupHeader(
          group: group,
          topSpacing: groupIndex > 0 ? _kGroupSpacing : 0.0,
        ),
        for (final WidgetPreview preview in group.previews)
          _GalleryPreviewItem(preview: preview),
      ],
    ];
    return ListView.builder(
      padding: const EdgeInsets.all(_kGalleryPadding),
      itemCount: items.length,
      itemBuilder: (BuildContext context, int index) {
        return switch (items[index]) {
          _GalleryGroupHeader(
            :final WidgetPreviewGroup group,
            :final double topSpacing,
          ) =>
            Padding(
              padding: EdgeInsets.only(top: topSpacing, bottom: _kCardSpacing),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      group.name,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: _kGroupHeaderSpacing),
                  PreviewInfoBadge(label: '${group.previews.length}'),
                ],
              ),
            ),
          _GalleryPreviewItem(:final WidgetPreview preview) => Padding(
            padding: const EdgeInsets.only(bottom: _kCardSpacing),
            child: _buildGalleryPreviewCard(
              context: context,
              fallbackWindowHeight: fallbackWindowHeight,
              outerConstraints: constraints,
              preview: preview,
            ),
          ),
        };
      },
    );
  }

  Widget _buildGalleryPreviewCard({
    required BuildContext context,
    required double fallbackWindowHeight,
    required BoxConstraints outerConstraints,
    required WidgetPreview preview,
  }) {
    final ThemeData theme = Theme.of(context);
    final (
      resolvedBrightness: _,
      :double? resolvedHeight,
      resolvedTextScale: _,
      :double? resolvedWidth,
    ) = _resolvePreviewSettings(
      context,
      preview,
    );
    final String? sizeLabel = switch ((resolvedWidth, resolvedHeight)) {
      (final double w, final double h) => '${w.toInt()}\u00D7${h.toInt()}',
      (final double w, null) => '${w.toInt()}\u00D7auto',
      (null, final double h) => 'auto\u00D7${h.toInt()}',
      (null, null) => null,
    };

    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          InkWell(
            key: Key('embed-gallery-header-${preview.id}'),
            mouseCursor: SystemMouseCursors.click,
            hoverColor: theme.colorScheme.onSurface.withValues(
              alpha: _kCardHeaderHoverAlpha,
            ),
            onTap: () =>
                _handleParamsChanged(_params.copyWith(previewId: preview.id)),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _kCardContentPadding,
                vertical: _kCardHeaderVerticalPadding,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      preview.name ?? preview.functionName,
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (sizeLabel != null) ...<Widget>[
                    const SizedBox(width: _kGroupHeaderSpacing),
                    PreviewInfoBadge(label: sizeLabel),
                  ],
                  const SizedBox(width: _kGroupHeaderSpacing),
                  Icon(
                    Icons.chevron_right,
                    size: _kCardHeaderChevronSize,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1.0),
          Padding(
            padding: const EdgeInsets.all(_kCardContentPadding),
            child: preview.hasError
                ? SelectableText(
                    preview.errorMessage ?? '${preview.libraryUri} has errors!',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  )
                : LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints cardConstraints) {
                          if (!_isSplitBrightness) {
                            return _buildPreviewSubtree(
                              context: context,
                              fallbackWindowHeight: fallbackWindowHeight,
                              outerConstraints: outerConstraints,
                              preview: preview,
                              viewportConstraints: cardConstraints,
                            );
                          }
                          final (
                            Widget lightPane,
                            Widget darkPane,
                          ) = _buildLightDarkPanes(
                            bodyPadding: const EdgeInsets.all(
                              _kCardContentPadding,
                            ),
                            darkKey: Key(
                              'embed-gallery-split-dark-${preview.id}',
                            ),
                            expandVertically: false,
                            fallbackWindowHeight: fallbackWindowHeight,
                            lightKey: Key(
                              'embed-gallery-split-light-${preview.id}',
                            ),
                            preview: preview,
                            theme: theme,
                          );
                          return cardConstraints.maxWidth <
                                  _kMinSplitPaneExtent * 2 + _kCardSpacing
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    lightPane,
                                    const SizedBox(height: _kCardSpacing),
                                    darkPane,
                                  ],
                                )
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Expanded(child: lightPane),
                                    const SizedBox(width: _kCardSpacing),
                                    Expanded(child: darkPane),
                                  ],
                                );
                        },
                  ),
          ),
        ],
      ),
    );
  }

  (String title, String message) _lookupStatusDetails(
    PreviewLookupResult lookup,
  ) => switch (lookup) {
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
      (
        'Preview not found',
        availableIds.isEmpty
            ? 'Preview "${previewId ?? ''}" was not found.'
            : 'Preview "${previewId ?? ''}" was not found. Available previews:\n'
                  '${availableIds.join('\n')}',
      ),
  };

  Widget _buildStatusView({
    required BuildContext context,
    required BoxConstraints constraints,
    required String message,
    required String title,
    bool showStarterSnippet = false,
  }) {
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
                    if (showStarterSnippet) const StarterPreviewSnippetCard(),
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
    required this.brightness,
    required this.controller,
    required this.preview,
    required this.previewerConstraints,
    required this.selectionController,
    required this.textScale,
    required this.viewportConstraints,
    required this.zoom,
    this.onParamsChanged,
    this.params,
    this.resolvedHeight,
    this.resolvedWidth,
    this.showBounds = false,
    super.key,
  });

  final Brightness brightness;
  final WidgetPreviewScaffoldController controller;
  final ValueChanged<EmbedPreviewParams>? onParamsChanged;
  final EmbedPreviewParams? params;
  final WidgetPreview preview;
  final BoxConstraints previewerConstraints;
  final double? resolvedHeight;
  final double? resolvedWidth;
  final EmbedSelectionController selectionController;
  final bool showBounds;
  final double textScale;
  final BoxConstraints viewportConstraints;
  final double zoom;

  @override
  State<_EmbedPreviewContent> createState() => _EmbedPreviewContentState();
}

class _EmbedPreviewContentState extends State<_EmbedPreviewContent> {
  final _frameBoxKey = GlobalKey();
  final _previewContentKey = GlobalKey();
  ({Object error, StackTrace stackTrace})? _layoutError;

  @override
  void didUpdateWidget(_EmbedPreviewContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preview != widget.preview ||
        oldWidget.brightness != widget.brightness ||
        oldWidget.textScale != widget.textScale ||
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
      :Brightness brightness,
      :ValueChanged<EmbedPreviewParams>? onParamsChanged,
      :EmbedPreviewParams? params,
      :WidgetPreview preview,
      :BoxConstraints previewerConstraints,
      :double? resolvedHeight,
      :double? resolvedWidth,
      :EmbedSelectionController selectionController,
      :double textScale,
      :BoxConstraints viewportConstraints,
      :double zoom,
    ) = widget;
    final constrained = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth:
            resolvedWidth ??
            (viewportConstraints.hasBoundedWidth
                ? viewportConstraints.maxWidth
                : double.infinity),
        maxHeight:
            resolvedHeight ??
            (viewportConstraints.hasBoundedHeight
                ? viewportConstraints.maxHeight
                : double.infinity),
      ),
      child: SizedBox(
        width: resolvedWidth,
        height: resolvedHeight,
        child: WidgetPreviewWrapper(
          previewerConstraints: previewerConstraints,
          onLayoutError: _handleLayoutError,
          child: child,
        ),
      ),
    );
    final selectable = EmbedSelectablePreviewSurface(
      brightness: brightness,
      previewContentKey: _previewContentKey,
      previewId: preview.id,
      previewName: preview.name,
      selectionController: selectionController,
      textScale: textScale,
      zoom: zoom,
      child: KeyedSubtree(
        key: _frameBoxKey,
        child: _PreviewBoundsOverlay(
          key: const Key('embed-bounds-overlay'),
          enabled: widget.showBounds,
          child: constrained,
        ),
      ),
    );
    final double minWidth = viewportConstraints.hasBoundedWidth
        ? viewportConstraints.maxWidth
        : 0.0;
    final double minHeight = viewportConstraints.hasBoundedHeight
        ? viewportConstraints.maxHeight
        : 0.0;
    if (onParamsChanged == null || params == null) {
      return ScaledScrollablePreview(
        scale: zoom,
        includeVerticalScroll: viewportConstraints.hasBoundedHeight,
        minWidth: minWidth,
        minHeight: minHeight,
        child: selectable,
      );
    }
    return EmbedLiveResizableFrame(
      defaultSize: _EmbedPreviewScaffoldState._kDefaultWindowSize,
      includeVerticalScroll: viewportConstraints.hasBoundedHeight,
      logicalFrameKey: _frameBoxKey,
      minHeight: minHeight,
      minWidth: minWidth,
      onParamsChanged: onParamsChanged,
      params: params,
      resolvedHeight: resolvedHeight,
      resolvedWidth: resolvedWidth,
      zoom: zoom,
      child: ScaledPreviewLayout(scale: zoom, child: selectable),
    );
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
      final previewWidget = EnableWidgetInspectorScope(
        child: PreviewWidget(
          preview: preview,
          child: KeyedSubtree(
            key: _previewContentKey,
            child: preview.previewBuilder(),
          ),
        ),
      );
      return WidgetPreviewTheming(
        theme: preview.theme,
        child: ScrollNotificationObserver(
          child: WidgetPreviewLocalizations(
            localizationsData: preview.localizations,
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

sealed class _GalleryItem {
  const _GalleryItem();
}

final class _GalleryGroupHeader extends _GalleryItem {
  const _GalleryGroupHeader({required this.group, required this.topSpacing});

  final WidgetPreviewGroup group;
  final double topSpacing;
}

final class _GalleryPreviewItem extends _GalleryItem {
  const _GalleryPreviewItem({required this.preview});

  final WidgetPreview preview;
}

class _PreviewBoundsOverlay extends SingleChildRenderObjectWidget {
  const _PreviewBoundsOverlay({
    required this.enabled,
    required super.child,
    super.key,
  });

  final bool enabled;

  @override
  _RenderPreviewBoundsOverlay createRenderObject(BuildContext context) =>
      _RenderPreviewBoundsOverlay(enabled: enabled);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPreviewBoundsOverlay renderObject,
  ) {
    renderObject.enabled = enabled;
  }
}

class _RenderPreviewBoundsOverlay extends RenderProxyBox {
  _RenderPreviewBoundsOverlay({required this._enabled});

  static const _boundsStrokeColor = Color(0x993B82F6);
  static const _overflowStrokeColor = Color(0xFFEF4444);

  bool _enabled;

  bool get enabled => _enabled;

  set enabled(bool value) {
    if (_enabled != value) {
      _enabled = value;
      markNeedsPaint();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (!_enabled) {
      return;
    }
    final Canvas canvas = context.canvas;
    final boundsPaint = Paint()
      ..color = _boundsStrokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final overflowPaint = Paint()
      ..color = _overflowStrokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    void visit(RenderObject node) {
      if (node is RenderBox && node.hasSize && !node.size.isEmpty) {
        final Rect rect = MatrixUtils.transformRect(
          node.getTransformTo(this),
          Offset.zero & node.size,
        ).shift(offset);
        final bool isOverflowing =
            node is RenderFlex &&
            node.toStringShort().endsWith(kOverflowingRenderFlexSuffix);
        canvas.drawRect(rect, isOverflowing ? overflowPaint : boundsPaint);
      }
      node.visitChildren(visit);
    }

    visitChildren(visit);
  }
}

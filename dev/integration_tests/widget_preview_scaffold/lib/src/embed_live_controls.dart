// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widget_preview_scaffold/src/controls.dart';
import 'package:widget_preview_scaffold/src/embed_selection.dart';
import 'package:widget_preview_scaffold/src/utils/url/url.dart';
import 'package:widget_preview_scaffold/src/widget_preview.dart';

const _kBarBackgroundColor = Color(0xFF1E1E1E);
const _kBarBorderColor = Color(0xFF333333);
const _kCompactFontSize = 12.0;
const _kCompactLabelFontSize = 11.0;
const _kCopiedResetDelay = Duration(seconds: 2);
const _kDesktopPresetWidth = 1280.0;
const _kDimensionFieldBorderRadius = 6.0;
const _kDimensionFieldPadding = EdgeInsets.all(6);
const _kDimensionFieldWidth = 58.0;
const _kDropdownIconSize = 16.0;
const _kErrorBannerBackground = Color(0xFF451A1A);
const _kErrorBannerBorder = Color(0xFF991B1B);
const _kErrorTextColor = Color(0xFFFCA5A5);
const _kFrameBorderColor = Color(0x33888888);
const _kGripColor = Color(0x99888888);
const _kGripHoverColor = Color(0xFF3B82F6);
const _kInlineControlGap = 4.0;
const _kMenuMaxItemWidth = 320.0;
const _kMinResizeExtent = 120.0;
const _kMobilePresetWidth = 375.0;
const _kPreviewSelectorMaxWidth = 240.0;
const _kResizeCornerIconSize = 10.0;
const _kResizeGripLength = 28.0;
const _kResizeGripRadius = 2.0;
const _kResizeGripThickness = 4.0;
const _kResizeHandleThickness = 12.0;
const _kSelectedAccentColor = Color(0xFF2563EB);
const _kTabletPresetWidth = 768.0;

/// Top toolbar for `/live` and `#live=1` embed mode, providing preview
/// selection, brightness, Light+Dark split, viewport presets, zoom, bounds
/// overlay, select-mode toggle, canonical `previewId` copy, and live reload.
class EmbedLiveTopBar extends StatelessWidget {
  const EmbedLiveTopBar({
    required this.isSplitBrightness,
    required this.isSyncing,
    required this.onBoundsToggled,
    required this.onParamsChanged,
    required this.onSplitBrightnessChanged,
    required this.onSyncPressed,
    required this.onZoomChanged,
    required this.params,
    required this.previews,
    required this.resolvedPreviewId,
    required this.selectionController,
    required this.showBounds,
    this.onDismissSyncError,
    this.syncErrorMessage,
    super.key,
  });

  final bool isSplitBrightness;
  final bool isSyncing;
  final VoidCallback onBoundsToggled;
  final VoidCallback? onDismissSyncError;
  final ValueChanged<EmbedPreviewParams> onParamsChanged;
  final ValueChanged<bool> onSplitBrightnessChanged;
  final VoidCallback onSyncPressed;
  final ValueChanged<double> onZoomChanged;
  final EmbedPreviewParams params;
  final List<WidgetPreview> previews;
  final String? resolvedPreviewId;
  final EmbedSelectionController selectionController;
  final bool showBounds;
  final String? syncErrorMessage;

  void _selectBrightness(Brightness target) {
    final bool clearToAuto = !isSplitBrightness && params.brightness == target;
    if (isSplitBrightness) {
      onSplitBrightnessChanged(false);
    }
    onParamsChanged(
      params.copyWith(brightness: target, clearBrightness: clearToAuto),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double zoom = params.zoom ?? EmbedPreviewParams.kDefaultZoom;
    final bool canZoomOut =
        zoom > EmbedPreviewParams.kMinZoom + EmbedPreviewParams.kZoomEpsilon;
    final bool canZoomIn =
        zoom < EmbedPreviewParams.kMaxZoom - EmbedPreviewParams.kZoomEpsilon;
    final String selectedPreviewValue =
        resolvedPreviewId ?? EmbedPreviewParams.kAllPreviewsValue;
    final bool isResponsive = params.width == null && params.height == null;
    final bool isMobile =
        params.width == _kMobilePresetWidth && params.height == null;
    final bool isTablet =
        params.width == _kTabletPresetWidth && params.height == null;
    final bool isDesktop =
        params.width == _kDesktopPresetWidth && params.height == null;

    return Theme(
      data: ThemeData.dark(),
      child: Material(
        color: _kBarBackgroundColor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _kBarBorderColor)),
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  _buildPreviewSelector(selectedPreviewValue),
                  if (!params.isAllPreviews)
                    OutlinedButton(
                      key: const Key('embed-live-all-previews-button'),
                      onPressed: () => onParamsChanged(
                        params.copyWith(clearPreviewId: true),
                      ),
                      style: _compactButtonStyle(),
                      child: const Text('All Previews'),
                    ),
                  _buildToggleButton(
                    key: const Key('embed-live-brightness-light'),
                    label: 'Light',
                    selected:
                        !isSplitBrightness &&
                        params.brightness == Brightness.light,
                    onPressed: () => _selectBrightness(Brightness.light),
                  ),
                  _buildToggleButton(
                    key: const Key('embed-live-brightness-dark'),
                    label: 'Dark',
                    selected:
                        !isSplitBrightness &&
                        params.brightness == Brightness.dark,
                    onPressed: () => _selectBrightness(Brightness.dark),
                  ),
                  _buildToggleButton(
                    key: const Key('embed-live-split-brightness'),
                    label: 'Light + Dark',
                    selected: isSplitBrightness,
                    onPressed: () =>
                        onSplitBrightnessChanged(!isSplitBrightness),
                  ),
                  _buildToggleButton(
                    key: const Key('embed-live-width-responsive'),
                    label: 'Responsive',
                    selected: isResponsive,
                    onPressed: () => onParamsChanged(
                      params.copyWith(clearWidth: true, clearHeight: true),
                    ),
                  ),
                  _buildToggleButton(
                    key: const Key('embed-live-width-375'),
                    label: '375px',
                    selected: isMobile,
                    onPressed: () => onParamsChanged(
                      params.copyWith(
                        width: _kMobilePresetWidth,
                        clearHeight: true,
                      ),
                    ),
                  ),
                  _buildToggleButton(
                    key: const Key('embed-live-width-768'),
                    label: '768px',
                    selected: isTablet,
                    onPressed: () => onParamsChanged(
                      params.copyWith(
                        width: _kTabletPresetWidth,
                        clearHeight: true,
                      ),
                    ),
                  ),
                  _buildToggleButton(
                    key: const Key('embed-live-width-1280'),
                    label: '1280px',
                    selected: isDesktop,
                    onPressed: () => onParamsChanged(
                      params.copyWith(
                        width: _kDesktopPresetWidth,
                        clearHeight: true,
                      ),
                    ),
                  ),
                  _ViewportSizeInputs(
                    onParamsChanged: onParamsChanged,
                    params: params,
                  ),
                  _buildZoomControls(
                    zoom: zoom,
                    canZoomOut: canZoomOut,
                    canZoomIn: canZoomIn,
                  ),
                  _buildToggleButton(
                    key: const Key('embed-live-bounds-toggle'),
                    label: 'Bounds',
                    selected: showBounds,
                    onPressed: onBoundsToggled,
                  ),
                  ListenableBuilder(
                    listenable: selectionController,
                    builder: (BuildContext context, Widget? _) {
                      return _buildToggleButton(
                        key: const Key('embed-live-select-toggle'),
                        label: 'Select',
                        selected: selectionController.selectMode,
                        onPressed: () => selectionController.setSelectMode(
                          !selectionController.selectMode,
                        ),
                      );
                    },
                  ),
                  if (resolvedPreviewId case final String previewId)
                    CopyFeedbackButton(
                      key: const Key('embed-live-copy-preview-id'),
                      copiedLabel: 'Copied ID!',
                      label: previewId.split('/').last,
                      style: _compactButtonStyle(),
                      textToCopy: previewId,
                    ),
                  OutlinedButton(
                    key: const Key('embed-live-sync-button'),
                    onPressed: isSyncing ? null : onSyncPressed,
                    style: _compactButtonStyle(),
                    child: Text(isSyncing ? 'Syncing...' : 'Reload'),
                  ),
                  Text(
                    isSyncing ? 'Syncing...' : '${previews.length} preview(s)',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
            if (syncErrorMessage case final String error when error.isNotEmpty)
              Container(
                key: const Key('embed-live-error-banner'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: const BoxDecoration(
                  color: _kErrorBannerBackground,
                  border: Border(
                    bottom: BorderSide(color: _kErrorBannerBorder),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        error,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _kErrorTextColor,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('embed-live-error-dismiss'),
                      icon: const Icon(Icons.close, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: onDismissSyncError,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatPreviewLabel(WidgetPreview preview) {
    final String group = preview.previewData.group;
    return '${preview.name ?? preview.functionName}'
        '${group.isNotEmpty ? ' [$group]' : ''}';
  }

  String _selectedPreviewLabel(String selectedValue) {
    if (selectedValue == EmbedPreviewParams.kAllPreviewsValue) {
      return 'All Previews (${previews.length})';
    }
    for (final WidgetPreview preview in previews) {
      if (preview.id == selectedValue) {
        return _formatPreviewLabel(preview);
      }
    }
    return selectedValue;
  }

  Widget _buildPreviewSelector(String selectedValue) {
    final String selectedLabel = _selectedPreviewLabel(selectedValue);
    return MenuAnchor(
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(_kBarBackgroundColor),
        side: WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: _kBarBorderColor),
        ),
      ),
      menuChildren: <Widget>[
        MenuItemButton(
          onPressed: () =>
              onParamsChanged(params.copyWith(clearPreviewId: true)),
          child: Text(
            'All Previews (${previews.length})',
            style: const TextStyle(
              fontSize: _kCompactFontSize,
              color: Colors.white,
            ),
          ),
        ),
        for (final WidgetPreview preview in previews)
          MenuItemButton(
            onPressed: () =>
                onParamsChanged(params.copyWith(previewId: preview.id)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kMenuMaxItemWidth),
              child: Text(
                _formatPreviewLabel(preview),
                style: const TextStyle(
                  fontSize: _kCompactFontSize,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
      builder:
          (BuildContext context, MenuController menuController, Widget? _) {
            return ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: _kPreviewSelectorMaxWidth,
              ),
              child: OutlinedButton(
                key: const Key('embed-live-preview-selector'),
                onPressed: () => menuController.isOpen
                    ? menuController.close()
                    : menuController.open(),
                style: _compactButtonStyle(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        selectedLabel,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: _kInlineControlGap),
                    const Icon(Icons.arrow_drop_down, size: _kDropdownIconSize),
                  ],
                ),
              ),
            );
          },
    );
  }

  Widget _buildZoomControls({
    required double zoom,
    required bool canZoomOut,
    required bool canZoomIn,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        OutlinedButton(
          key: const Key('embed-live-zoom-out'),
          onPressed: canZoomOut
              ? () => onZoomChanged(zoom - EmbedPreviewParams.kZoomStep)
              : null,
          style: _compactButtonStyle(),
          child: const Text('-'),
        ),
        const SizedBox(width: 4),
        OutlinedButton(
          key: const Key('embed-live-zoom-reset'),
          onPressed: () => onZoomChanged(EmbedPreviewParams.kDefaultZoom),
          style: _compactButtonStyle(),
          child: Text('${(zoom * 100).round()}%'),
        ),
        const SizedBox(width: 4),
        OutlinedButton(
          key: const Key('embed-live-zoom-in'),
          onPressed: canZoomIn
              ? () => onZoomChanged(zoom + EmbedPreviewParams.kZoomStep)
              : null,
          style: _compactButtonStyle(),
          child: const Text('+'),
        ),
      ],
    );
  }

  Widget _buildToggleButton({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      key: key,
      onPressed: onPressed,
      style: _compactButtonStyle(selected: selected),
      child: Text(label),
    );
  }
}

/// Bottom selection tray for `/live` and `#live=1`, rendered only when at least
/// one selection is active.
class EmbedLiveSelectionBar extends StatefulWidget {
  const EmbedLiveSelectionBar({
    required this.params,
    required this.selectionController,
    super.key,
  });

  final EmbedPreviewParams params;
  final EmbedSelectionController selectionController;

  @override
  State<EmbedLiveSelectionBar> createState() => _EmbedLiveSelectionBarState();
}

class _EmbedLiveSelectionBarState extends State<EmbedLiveSelectionBar> {
  final _noteController = TextEditingController();
  var _copied = false;
  var _isSending = false;
  String? _sendError;
  Timer? _copiedResetTimer;

  @override
  void initState() {
    super.initState();
    _noteController.addListener(_onNoteChanged);
  }

  @override
  void dispose() {
    _copiedResetTimer?.cancel();
    _noteController
      ..removeListener(_onNoteChanged)
      ..dispose();
    super.dispose();
  }

  void _onNoteChanged() {
    setState(() {
      if (_sendError != null) {
        _sendError = null;
      }
    });
  }

  Future<void> _copyContext(List<EmbedSelectionEntry> selections) async {
    final String text = formatEmbedSelectionContext(selections: selections);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    _copiedResetTimer?.cancel();
    setState(() {
      _copied = true;
    });
    _copiedResetTimer = Timer(_kCopiedResetDelay, () {
      if (mounted) {
        setState(() {
          _copied = false;
        });
      }
    });
  }

  Future<void> _sendToChat(List<EmbedSelectionEntry> selections) async {
    final String message = _noteController.text.trim();
    if (message.isEmpty || _isSending) {
      return;
    }
    setState(() {
      _isSending = true;
      _sendError = null;
    });
    try {
      final EmbedPreviewParams params = widget.params;
      final String? viewport = params.width != null || params.height != null
          ? '${params.width?.round() ?? 'auto'}'
                'x${params.height?.round() ?? 'auto'}'
          : null;
      await sendLiveSelectionToHost(
        message: message,
        selections: widget.selectionController.selectionsJson,
        brightness: params.brightness?.name,
        previewId: params.previewId,
        previewName: selections.isNotEmpty
            ? selections.first.previewName
            : null,
        textScale: params.textScale != null
            ? formatEmbedZoom(params.textScale!)
            : null,
        viewport: viewport,
        zoom: params.zoom != null ? formatEmbedZoom(params.zoom!) : null,
      );
      if (!mounted) {
        return;
      }
      _noteController.clear();
      widget.selectionController.clearSelections();
      setState(() {
        _isSending = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSending = false;
        _sendError = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.selectionController,
      builder: (BuildContext context, Widget? _) {
        final List<EmbedSelectionEntry> selections =
            widget.selectionController.selections;
        if (selections.isEmpty) {
          return const SizedBox.shrink();
        }
        final bool canSubmit =
            _noteController.text.trim().isNotEmpty && !_isSending;

        return Theme(
          data: ThemeData.dark(),
          child: Material(
            color: _kBarBackgroundColor,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _kBarBorderColor)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      for (final EmbedSelectionEntry entry in selections)
                        InputChip(
                          key: Key('embed-live-chip-${entry.id}'),
                          label: Text(
                            '#${entry.index} ${entry.previewName ?? entry.previewId}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          deleteIcon: Icon(
                            Icons.close,
                            key: Key('embed-live-chip-remove-${entry.id}'),
                            size: 14,
                          ),
                          onDeleted: () => widget.selectionController
                              .removeSelectionById(entry.id),
                          visualDensity: VisualDensity.compact,
                        ),
                      OutlinedButton(
                        key: const Key('embed-live-copy-button'),
                        onPressed: () => _copyContext(selections),
                        style: _compactButtonStyle(),
                        child: Text(_copied ? 'Copied!' : 'Copy Context'),
                      ),
                      OutlinedButton(
                        key: const Key('embed-live-clear-button'),
                        onPressed: widget.selectionController.clearSelections,
                        style: _compactButtonStyle(),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                  if (canSendLiveSelection) ...<Widget>[
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            key: const Key('embed-live-note-input'),
                            controller: _noteController,
                            style: const TextStyle(fontSize: 12),
                            decoration: const InputDecoration(
                              hintText: 'Ask about selected region(s)...',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) {
                              if (canSubmit) {
                                unawaited(_sendToChat(selections));
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        FilledButton(
                          key: const Key('embed-live-send-button'),
                          onPressed: canSubmit
                              ? () => _sendToChat(selections)
                              : null,
                          style: _compactButtonStyle(selected: true),
                          child: Text(_isSending ? 'Sending...' : 'Send'),
                        ),
                      ],
                    ),
                    if (_sendError case final String error)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          error,
                          key: const Key('embed-live-send-error'),
                          style: const TextStyle(
                            fontSize: 11,
                            color: _kErrorTextColor,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

ButtonStyle _compactButtonStyle({bool selected = false}) {
  return OutlinedButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: const TextStyle(fontSize: 12),
    backgroundColor: selected ? _kSelectedAccentColor : null,
    foregroundColor: Colors.white,
    side: BorderSide(
      color: selected ? _kSelectedAccentColor : _kBarBorderColor,
    ),
  );
}

class _ViewportSizeInputs extends StatefulWidget {
  const _ViewportSizeInputs({
    required this.onParamsChanged,
    required this.params,
  });

  final ValueChanged<EmbedPreviewParams> onParamsChanged;
  final EmbedPreviewParams params;

  @override
  State<_ViewportSizeInputs> createState() => _ViewportSizeInputsState();
}

class _ViewportSizeInputsState extends State<_ViewportSizeInputs> {
  late final _widthController = TextEditingController(
    text: _formatDimension(widget.params.width),
  );
  late final _heightController = TextEditingController(
    text: _formatDimension(widget.params.height),
  );
  final _widthFocusNode = FocusNode();
  final _heightFocusNode = FocusNode();

  static String _formatDimension(double? value) =>
      value == null ? '' : formatEmbedZoom(value);

  @override
  void initState() {
    super.initState();
    _widthFocusNode.addListener(_handleWidthFocusChanged);
    _heightFocusNode.addListener(_handleHeightFocusChanged);
  }

  @override
  void didUpdateWidget(_ViewportSizeInputs oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController(
      _widthController,
      oldWidget.params.width,
      widget.params.width,
    );
    _syncController(
      _heightController,
      oldWidget.params.height,
      widget.params.height,
    );
  }

  static void _syncController(
    TextEditingController controller,
    double? previous,
    double? current,
  ) {
    if (previous == current) {
      return;
    }
    final String formatted = _formatDimension(current);
    if (controller.text != formatted) {
      controller.text = formatted;
    }
  }

  @override
  void dispose() {
    _widthFocusNode
      ..removeListener(_handleWidthFocusChanged)
      ..dispose();
    _heightFocusNode
      ..removeListener(_handleHeightFocusChanged)
      ..dispose();
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _handleWidthFocusChanged() {
    if (!_widthFocusNode.hasFocus) {
      _commitDimension(isWidth: true);
    }
  }

  void _handleHeightFocusChanged() {
    if (!_heightFocusNode.hasFocus) {
      _commitDimension(isWidth: false);
    }
  }

  void _commitDimension({required bool isWidth}) {
    final TextEditingController controller = isWidth
        ? _widthController
        : _heightController;
    final double? current = isWidth
        ? widget.params.width
        : widget.params.height;
    final String raw = controller.text.trim();
    if (raw.isEmpty) {
      controller.text = '';
      if (current != null) {
        widget.onParamsChanged(
          isWidth
              ? widget.params.copyWith(clearWidth: true)
              : widget.params.copyWith(clearHeight: true),
        );
      }
      return;
    }
    final double? parsed = double.tryParse(raw);
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      controller.text = _formatDimension(current);
      return;
    }
    final String normalized = formatEmbedZoom(parsed);
    if (controller.text != normalized) {
      controller.text = normalized;
    }
    if (current != parsed) {
      widget.onParamsChanged(
        isWidth
            ? widget.params.copyWith(width: parsed)
            : widget.params.copyWith(height: parsed),
      );
    }
  }

  Widget _buildDimensionField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool isWidth,
    required Key key,
  }) {
    final borderRadius = BorderRadius.circular(_kDimensionFieldBorderRadius);
    return SizedBox(
      width: _kDimensionFieldWidth,
      child: TextField(
        key: key,
        controller: controller,
        focusNode: focusNode,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: _kCompactFontSize,
          color: Colors.white,
        ),
        decoration: InputDecoration(
          hintText: 'auto',
          hintStyle: const TextStyle(
            fontSize: _kCompactLabelFontSize,
            color: Colors.white38,
          ),
          isDense: true,
          contentPadding: _kDimensionFieldPadding,
          enabledBorder: OutlineInputBorder(
            borderRadius: borderRadius,
            borderSide: const BorderSide(color: _kBarBorderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: borderRadius,
            borderSide: const BorderSide(color: _kSelectedAccentColor),
          ),
        ),
        onSubmitted: (_) => _commitDimension(isWidth: isWidth),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(
      fontSize: _kCompactLabelFontSize,
      color: Colors.white70,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text('W', style: labelStyle),
        const SizedBox(width: _kInlineControlGap),
        _buildDimensionField(
          controller: _widthController,
          focusNode: _widthFocusNode,
          isWidth: true,
          key: const Key('embed-live-width-input'),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: _kInlineControlGap),
          child: Text(
            '\u00D7',
            style: TextStyle(
              fontSize: _kCompactFontSize,
              color: Colors.white70,
            ),
          ),
        ),
        const Text('H', style: labelStyle),
        const SizedBox(width: _kInlineControlGap),
        _buildDimensionField(
          controller: _heightController,
          focusNode: _heightFocusNode,
          isWidth: false,
          key: const Key('embed-live-height-input'),
        ),
      ],
    );
  }
}

enum _ResizeHandleKind { width, height, corner }

/// Interactive single-preview frame with right, bottom, and corner drag-resize
/// handles for `/live` mode.
class EmbedLiveResizableFrame extends StatefulWidget {
  const EmbedLiveResizableFrame({
    required this.child,
    required this.defaultSize,
    required this.includeVerticalScroll,
    required this.logicalFrameKey,
    required this.minHeight,
    required this.minWidth,
    required this.onParamsChanged,
    required this.params,
    required this.zoom,
    this.resolvedHeight,
    this.resolvedWidth,
    super.key,
  });

  final Widget child;
  final Size defaultSize;
  final bool includeVerticalScroll;
  final GlobalKey logicalFrameKey;
  final double minHeight;
  final double minWidth;
  final ValueChanged<EmbedPreviewParams> onParamsChanged;
  final EmbedPreviewParams params;
  final double? resolvedHeight;
  final double? resolvedWidth;
  final double zoom;

  static BoxConstraints deflateStageConstraints(BoxConstraints constraints) {
    double deflate(double maxExtent) => maxExtent.isFinite
        ? math.max(_kMinResizeExtent, maxExtent - _kResizeHandleThickness)
        : double.infinity;
    return BoxConstraints(
      maxWidth: deflate(constraints.maxWidth),
      maxHeight: deflate(constraints.maxHeight),
    );
  }

  @override
  State<EmbedLiveResizableFrame> createState() =>
      _EmbedLiveResizableFrameState();
}

class _EmbedLiveResizableFrameState extends State<EmbedLiveResizableFrame> {
  _ResizeHandleKind? _activeKind;
  double? _dragHeight;
  double? _dragWidth;
  _ResizeHandleKind? _hoveredKind;

  Size? _currentLogicalFrameSize() {
    final RenderObject? renderObject = widget.logicalFrameKey.currentContext
        ?.findRenderObject();
    if (renderObject is RenderBox &&
        renderObject.attached &&
        renderObject.hasSize) {
      return renderObject.size;
    }
    return null;
  }

  void _startDrag(_ResizeHandleKind kind) {
    final Size? frameSize = _currentLogicalFrameSize();
    setState(() {
      _activeKind = kind;
      if (kind != _ResizeHandleKind.height) {
        _dragWidth =
            widget.resolvedWidth ??
            frameSize?.width ??
            widget.defaultSize.width;
      }
      if (kind != _ResizeHandleKind.width) {
        _dragHeight =
            widget.resolvedHeight ??
            frameSize?.height ??
            widget.defaultSize.height;
      }
    });
  }

  void _updateDrag(_ResizeHandleKind kind, Offset delta) {
    double? clampedWidth;
    double? clampedHeight;
    if (kind != _ResizeHandleKind.height) {
      final double nextWidth = _dragWidth! + delta.dx / widget.zoom;
      _dragWidth = nextWidth;
      clampedWidth = math.max(_kMinResizeExtent, nextWidth).roundToDouble();
    }
    if (kind != _ResizeHandleKind.width) {
      final double nextHeight = _dragHeight! + delta.dy / widget.zoom;
      _dragHeight = nextHeight;
      clampedHeight = math.max(_kMinResizeExtent, nextHeight).roundToDouble();
    }
    widget.onParamsChanged(
      widget.params.copyWith(height: clampedHeight, width: clampedWidth),
    );
  }

  void _endDrag() {
    setState(() {
      _activeKind = null;
      _dragWidth = null;
      _dragHeight = null;
    });
  }

  Widget _buildHandle(_ResizeHandleKind kind) {
    final (Key key, MouseCursor cursor) = switch (kind) {
      _ResizeHandleKind.width => (
        const Key('embed-live-resize-width'),
        SystemMouseCursors.resizeLeftRight,
      ),
      _ResizeHandleKind.height => (
        const Key('embed-live-resize-height'),
        SystemMouseCursors.resizeUpDown,
      ),
      _ResizeHandleKind.corner => (
        const Key('embed-live-resize-corner'),
        SystemMouseCursors.resizeDownRight,
      ),
    };
    final Color color = _hoveredKind == kind || _activeKind == kind
        ? _kGripHoverColor
        : _kGripColor;
    final Widget grip = switch (kind) {
      _ResizeHandleKind.width || _ResizeHandleKind.height => DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(_kResizeGripRadius),
        ),
        child: SizedBox(
          width: kind == _ResizeHandleKind.width
              ? _kResizeGripThickness
              : _kResizeGripLength,
          height: kind == _ResizeHandleKind.width
              ? _kResizeGripLength
              : _kResizeGripThickness,
        ),
      ),
      _ResizeHandleKind.corner => Icon(
        Icons.south_east,
        size: _kResizeCornerIconSize,
        color: color,
      ),
    };
    return MouseRegion(
      key: key,
      cursor: cursor,
      onEnter: (_) => setState(() => _hoveredKind = kind),
      onExit: (_) {
        if (_hoveredKind == kind) {
          setState(() => _hoveredKind = null);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (_) => _startDrag(kind),
        onPanUpdate: (DragUpdateDetails details) =>
            _updateDrag(kind, details.delta),
        onPanEnd: (_) => _endDrag(),
        onPanCancel: _endDrag,
        onDoubleTap: () => widget.onParamsChanged(
          widget.params.copyWith(
            clearHeight: kind != _ResizeHandleKind.width,
            clearWidth: kind != _ResizeHandleKind.height,
          ),
        ),
        child: Center(child: grip),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const double t = _kResizeHandleThickness;
    final Widget frame = Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: t, bottom: t),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: const BoxDecoration(
              border: Border.fromBorderSide(
                BorderSide(color: _kFrameBorderColor),
              ),
            ),
            child: widget.child,
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          bottom: t,
          width: t,
          child: _buildHandle(_ResizeHandleKind.width),
        ),
        Positioned(
          left: 0,
          right: t,
          bottom: 0,
          height: t,
          child: _buildHandle(_ResizeHandleKind.height),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          width: t,
          height: t,
          child: _buildHandle(_ResizeHandleKind.corner),
        ),
      ],
    );
    final Widget horizontalScroll = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: widget.minWidth > 0.0 ? widget.minWidth + t : 0.0,
          minHeight: widget.minHeight > 0.0 ? widget.minHeight + t : 0.0,
        ),
        child: Center(child: frame),
      ),
    );
    return widget.includeVerticalScroll
        ? SingleChildScrollView(child: horizontalScroll)
        : horizontalScroll;
  }
}

// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widget_preview_scaffold/src/embed_selection.dart';
import 'package:widget_preview_scaffold/src/utils/url/url.dart';
import 'package:widget_preview_scaffold/src/widget_preview.dart';

const _kBarBackgroundColor = Color(0xFF1E1E1E);
const _kBarBorderColor = Color(0xFF333333);
const _kCopiedResetDelay = Duration(seconds: 2);
const _kErrorBannerBackground = Color(0xFF451A1A);
const _kErrorBannerBorder = Color(0xFF991B1B);
const _kErrorTextColor = Color(0xFFFCA5A5);
const _kMobilePresetWidth = 375.0;
const _kSelectedAccentColor = Color(0xFF2563EB);
const _kTabletPresetWidth = 768.0;

/// Top toolbar for `/live` and `#live=1` embed mode, providing preview
/// selection, brightness, viewport width presets, zoom, select-mode toggle,
/// and live reload/sync with an optional compile error banner.
class EmbedLiveTopBar extends StatelessWidget {
  const EmbedLiveTopBar({
    required this.isSyncing,
    required this.onParamsChanged,
    required this.onSyncPressed,
    required this.onZoomChanged,
    required this.params,
    required this.previews,
    required this.selectionController,
    this.onDismissSyncError,
    this.syncErrorMessage,
    super.key,
  });

  final bool isSyncing;
  final VoidCallback? onDismissSyncError;
  final ValueChanged<EmbedPreviewParams> onParamsChanged;
  final VoidCallback onSyncPressed;
  final ValueChanged<double> onZoomChanged;
  final EmbedPreviewParams params;
  final List<WidgetPreview> previews;
  final EmbedSelectionController selectionController;
  final String? syncErrorMessage;

  @override
  Widget build(BuildContext context) {
    final double zoom = params.zoom ?? EmbedPreviewParams.kDefaultZoom;
    final bool canZoomOut =
        zoom > EmbedPreviewParams.kMinZoom + EmbedPreviewParams.kZoomEpsilon;
    final bool canZoomIn =
        zoom < EmbedPreviewParams.kMaxZoom - EmbedPreviewParams.kZoomEpsilon;
    final Brightness activeBrightness =
        params.brightness ?? Theme.of(context).brightness;
    final String selectedPreviewValue =
        params.previewId != null &&
            previews.any((WidgetPreview p) => p.id == params.previewId)
        ? params.previewId!
        : EmbedPreviewParams.kAllPreviewsValue;
    final bool isResponsive = params.width == null && params.height == null;
    final bool isMobile =
        params.width == _kMobilePresetWidth && params.height == null;
    final bool isTablet =
        params.width == _kTabletPresetWidth && params.height == null;
    final bool hasCustomViewport = !isResponsive && !isMobile && !isTablet;

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
                  _buildToggleButton(
                    key: const Key('embed-live-brightness-toggle'),
                    label: activeBrightness == Brightness.dark
                        ? 'Dark'
                        : 'Light',
                    selected: params.brightness != null,
                    onPressed: () {
                      final Brightness nextBrightness =
                          activeBrightness == Brightness.dark
                          ? Brightness.light
                          : Brightness.dark;
                      onParamsChanged(
                        params.copyWith(brightness: nextBrightness),
                      );
                    },
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
                  if (hasCustomViewport)
                    Chip(
                      key: const Key('embed-live-custom-viewport'),
                      label: Text(
                        '${params.width?.round() ?? 'auto'}'
                        'x${params.height?.round() ?? 'auto'}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  _buildZoomControls(
                    zoom: zoom,
                    canZoomOut: canZoomOut,
                    canZoomIn: canZoomIn,
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

  Widget _buildPreviewSelector(String selectedValue) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border.all(color: _kBarBorderColor),
          borderRadius: BorderRadius.circular(4),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: const Key('embed-live-preview-selector'),
            value: selectedValue,
            isDense: true,
            isExpanded: true,
            style: const TextStyle(fontSize: 12, color: Colors.white),
            dropdownColor: _kBarBackgroundColor,
            items: <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(
                value: EmbedPreviewParams.kAllPreviewsValue,
                child: Text('All Previews (${previews.length})'),
              ),
              for (final WidgetPreview preview in previews)
                DropdownMenuItem<String>(
                  value: preview.id,
                  child: Text(
                    '${preview.name ?? preview.functionName}'
                    '${preview.previewData.group.isNotEmpty ? ' [${preview.previewData.group}]' : ''}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (String? value) {
              if (value == null) {
                return;
              }
              if (value == EmbedPreviewParams.kAllPreviewsValue) {
                onParamsChanged(params.copyWith(clearPreviewId: true));
              } else {
                onParamsChanged(params.copyWith(previewId: value));
              }
            },
          ),
        ),
      ),
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

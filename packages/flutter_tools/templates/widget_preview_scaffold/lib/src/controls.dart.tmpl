// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'theme/theme.dart';
import 'utils/url/url.dart';
import 'widget_preview_scaffold_controller.dart';

enum _PreviewSearchFilter {
  groupName('Group name'),
  previewName('Preview name'),
  containingScript('Containing script'),
  containingPackage('Containing package');

  const _PreviewSearchFilter(this.label);

  final String label;
}

typedef _SearchFilterEntry = ({
  _PreviewSearchFilter filter,
  ValueListenable<bool> listenable,
  bool Function() onToggle,
});

List<_SearchFilterEntry> _buildSearchFilters(
  WidgetPreviewScaffoldController controller,
) => <_SearchFilterEntry>[
  (
    filter: _PreviewSearchFilter.groupName,
    listenable: controller.searchByGroupNameListenable,
    onToggle: controller.toggleSearchByGroupName,
  ),
  (
    filter: _PreviewSearchFilter.previewName,
    listenable: controller.searchByPreviewNameListenable,
    onToggle: controller.toggleSearchByPreviewName,
  ),
  (
    filter: _PreviewSearchFilter.containingScript,
    listenable: controller.searchByContainingScriptListenable,
    onToggle: controller.toggleSearchByContainingScript,
  ),
  (
    filter: _PreviewSearchFilter.containingPackage,
    listenable: controller.searchByContainingPackageListenable,
    onToggle: controller.toggleSearchByContainingPackage,
  ),
];

/// Minimum supported preview zoom scale (`25%`).
const kMinPreviewZoom = EmbedPreviewParams.kMinZoom;

/// Maximum supported preview zoom scale (`400%`).
const kMaxPreviewZoom = EmbedPreviewParams.kMaxZoom;

/// Default preview zoom scale (`100%`).
const kDefaultPreviewZoom = EmbedPreviewParams.kDefaultZoom;

/// Linear step increment for preview zoom controls and shortcuts (`25%`).
const kPreviewZoomStep = EmbedPreviewParams.kZoomStep;

/// Floating-point tolerance when comparing zoom levels against defaults/bounds.
const kPreviewZoomEpsilon = EmbedPreviewParams.kZoomEpsilon;

/// Clamps [zoom] to `[kMinPreviewZoom, kMaxPreviewZoom]`.
double clampPreviewZoom(double zoom) =>
    zoom.clamp(kMinPreviewZoom, kMaxPreviewZoom);

/// Intercepts `Ctrl`/`Cmd` + scroll-wheel pointer signals via
/// [PointerSignalResolver], accumulating fractional trackpad deltas before
/// stepping [zoom] by [kPreviewZoomStep].
class PreviewPointerScrollZoom extends StatefulWidget {
  const PreviewPointerScrollZoom({
    required this.child,
    required this.onZoomChanged,
    required this.zoom,
    super.key,
  });

  /// Scroll delta threshold (in logical pixels) per discrete [kPreviewZoomStep].
  static const kScrollDeltaPerZoomStep = 20.0;

  /// Preview subtree wrapped by this scroll-zoom interceptor.
  final Widget child;

  /// Invoked with the clamped zoom multiplier whenever zoom changes.
  final ValueChanged<double> onZoomChanged;

  /// Current zoom multiplier.
  final double zoom;

  @override
  State<PreviewPointerScrollZoom> createState() =>
      _PreviewPointerScrollZoomState();
}

class _PreviewPointerScrollZoomState extends State<PreviewPointerScrollZoom> {
  double _accumulatedScrollDy = 0.0;
  late double _currentZoom = widget.zoom;

  @override
  void didUpdateWidget(PreviewPointerScrollZoom oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zoom != widget.zoom) {
      _currentZoom = widget.zoom;
    }
  }

  void _handlePointerScroll(PointerScrollEvent event) {
    final double dy = event.scrollDelta.dy;
    if (dy == 0) {
      return;
    }
    if (!HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed) {
      _accumulatedScrollDy = 0.0;
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      _handleResolvedScroll,
    );
  }

  void _handleResolvedScroll(PointerSignalEvent resolvedEvent) {
    if (!mounted || resolvedEvent is! PointerScrollEvent) {
      return;
    }
    final double dy = resolvedEvent.scrollDelta.dy;
    if (dy * _accumulatedScrollDy < 0) {
      _accumulatedScrollDy = 0.0;
    }
    const double threshold = PreviewPointerScrollZoom.kScrollDeltaPerZoomStep;
    final double stepDelta;
    if (dy.abs() >= threshold) {
      _accumulatedScrollDy = 0.0;
      stepDelta = dy < 0 ? kPreviewZoomStep : -kPreviewZoomStep;
    } else {
      _accumulatedScrollDy += dy;
      if (_accumulatedScrollDy.abs() < threshold) {
        return;
      }
      stepDelta = _accumulatedScrollDy < 0
          ? kPreviewZoomStep
          : -kPreviewZoomStep;
      _accumulatedScrollDy = _accumulatedScrollDy.remainder(threshold);
    }
    final double nextZoom = clampPreviewZoom(_currentZoom + stepDelta);
    if ((nextZoom - _currentZoom).abs() > kPreviewZoomEpsilon) {
      _currentZoom = nextZoom;
      widget.onZoomChanged(nextZoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PointerScrollZoomCatcher(
      onPointerScroll: _handlePointerScroll,
      child: widget.child,
    );
  }
}

class _PointerScrollZoomCatcher extends SingleChildRenderObjectWidget {
  const _PointerScrollZoomCatcher({required this.onPointerScroll, super.child});

  final ValueChanged<PointerScrollEvent> onPointerScroll;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderPointerScrollZoomCatcher(onPointerScroll: onPointerScroll);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPointerScrollZoomCatcher renderObject,
  ) {
    renderObject.onPointerScroll = onPointerScroll;
  }
}

class _RenderPointerScrollZoomCatcher extends RenderProxyBox {
  _RenderPointerScrollZoomCatcher({required this.onPointerScroll});

  ValueChanged<PointerScrollEvent> onPointerScroll;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) {
      return false;
    }
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      // Prepend before hitTestChildren so this box registers first with
      // PointerSignalResolver ahead of both outer and preview-internal Scrollables.
      result.add(BoxHitTestEntry(this, position));
      hitTestChildren(result, position: position);
      return true;
    }
    if (hitTestChildren(result, position: position) || hitTestSelf(position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    if (event is PointerScrollEvent) {
      onPointerScroll(event);
    }
  }
}

/// Provides controls to change the zoom level of a [WidgetPreview].
class ZoomControls extends StatelessWidget {
  const ZoomControls({super.key, required this._transformationController});

  final TransformationController _transformationController;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color onSurface = theme.colorScheme.onSurface;
    final Color disabledColor = onSurface.withValues(alpha: 0.38);
    return _ControlDecorator(
      child: ValueListenableBuilder<Matrix4>(
        valueListenable: _transformationController,
        builder: (BuildContext context, Matrix4 matrix, _) {
          final double scale = matrix.entry(0, 0);
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                tooltip: 'Zoom out',
                style: theme.iconButtonTheme.style,
                onPressed: scale > kMinPreviewZoom + kPreviewZoomEpsilon
                    ? () => _stepScale(-kPreviewZoomStep)
                    : null,
                icon: const Icon(Icons.zoom_out),
                color: onSurface,
                disabledColor: disabledColor,
              ),
              Flexible(
                child: SizedBox(
                  width: 100,
                  height: defaultButtonHeight,
                  child: Slider(
                    min: kMinPreviewZoom,
                    max: kMaxPreviewZoom,
                    value: clampPreviewZoom(scale),
                    onChanged: _setScale,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Zoom in',
                style: theme.iconButtonTheme.style,
                onPressed: scale < kMaxPreviewZoom - kPreviewZoomEpsilon
                    ? () => _stepScale(kPreviewZoomStep)
                    : null,
                icon: const Icon(Icons.zoom_in_sharp),
                color: onSurface,
                disabledColor: disabledColor,
              ),
              IconButton(
                tooltip: 'Reset zoom',
                style: theme.iconButtonTheme.style,
                onPressed:
                    (scale - kDefaultPreviewZoom).abs() > kPreviewZoomEpsilon
                    ? _reset
                    : null,
                icon: const Icon(Icons.zoom_out_map),
                color: onSurface,
                disabledColor: disabledColor,
              ),
              SizedBox(
                width: 36,
                child: Text(
                  '${(scale * 100).toStringAsFixed(0)}%',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _stepScale(double delta) =>
      _setScale(_transformationController.value.entry(0, 0) + delta);

  void _setScale(double scale) {
    final double clampedScale = clampPreviewZoom(scale);
    _transformationController.value = Matrix4.diagonal3Values(
      clampedScale,
      clampedScale,
      1.0,
    );
  }

  void _reset() {
    _transformationController.value = Matrix4.identity();
  }
}

class _ControlDecorator extends StatelessWidget {
  const _ControlDecorator({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(densePadding),
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: defaultBorderRadius,
      ),
      child: child,
    );
  }
}

/// Allows for controlling the grid vs layout view in the preview environment.
class LayoutTypeSelector extends StatelessWidget {
  const LayoutTypeSelector({super.key, required this.controller});

  final WidgetPreviewScaffoldController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return _ControlDecorator(
      child: ValueListenableBuilder<LayoutType>(
        valueListenable: controller.layoutTypeListenable,
        builder: (BuildContext context, LayoutType selectedLayout, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                style: theme.iconButtonTheme.style,
                visualDensity: VisualDensity.compact,
                onPressed: () => controller.layoutType = LayoutType.gridView,
                icon: const Icon(Icons.grid_on),
                color: selectedLayout == LayoutType.gridView
                    ? Colors.blue
                    : Colors.black,
              ),
              IconButton(
                onPressed: () => controller.layoutType = LayoutType.listView,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.view_list),
                color: selectedLayout == LayoutType.listView
                    ? Colors.blue
                    : Colors.black,
              ),
            ],
          );
        },
      ),
    );
  }
}

class WidgetInspectorToggle extends StatelessWidget {
  const WidgetInspectorToggle({super.key, required this.controller});

  final WidgetPreviewScaffoldController controller;

  @override
  Widget build(BuildContext context) {
    return _ControlDecorator(
      child: ValueListenableBuilder<bool>(
        valueListenable: controller.widgetInspectorVisible,
        builder: (BuildContext context, bool widgetInspectorVisible, _) {
          return IconButton(
            style: Theme.of(context).iconButtonTheme.style,
            visualDensity: VisualDensity.compact,
            onPressed: controller.toggleWidgetInspectorVisible,
            // TODO(bkonyi): replace with widget inspector icon.
            icon: const Icon(Icons.image_search),
            color: widgetInspectorVisible ? Colors.blue : Colors.black,
          );
        },
      ),
    );
  }
}

/// A toggle button that enables / disables filtering previews by the currently
/// selected source file.
///
/// This control is hidden if the DTD Editor service isn't available.
class FilterBySelectedFileToggle extends StatelessWidget {
  const FilterBySelectedFileToggle({super.key, required this.controller});

  @visibleForTesting
  static const kTooltip = 'Filter previews by selected file';

  final WidgetPreviewScaffoldController controller;

  @override
  Widget build(BuildContext context) {
    return _ControlDecorator(
      child: ValueListenableBuilder<bool>(
        valueListenable: controller.filterBySelectedFileListenable,
        builder: (BuildContext context, bool value, _) {
          return IconButton(
            onPressed: controller.toggleFilterBySelectedFile,
            icon: const Icon(Icons.file_open),
            color: value ? Colors.blue : Colors.black,
            tooltip: kTooltip,
          );
        },
      ),
    );
  }
}

/// A button that triggers a "soft" restart of a previewed widget.
///
/// A soft restart removes the previewed widget from the widget tree for a frame before
/// re-inserting it on the next frame. This has the effect of re-running local initializers in
/// State objects, which normally requires a hot restart to accomplish in a normal application.
class SoftRestartButton extends StatelessWidget {
  const SoftRestartButton({super.key, required this.softRestartListenable});

  final ValueNotifier<bool> softRestartListenable;

  @override
  Widget build(BuildContext context) {
    return _ControlDecorator(
      child: IconButton(
        tooltip: 'Hot restart',
        onPressed: () => softRestartListenable.value = true,
        icon: const Icon(Icons.refresh),
        color: Colors.black,
      ),
    );
  }
}

/// A button that triggers a restart of the widget previewer through a hot restart request made
/// through DTD.
class WidgetPreviewerRestartButton extends StatelessWidget {
  const WidgetPreviewerRestartButton({super.key, required this.controller});

  final WidgetPreviewScaffoldController controller;

  @override
  Widget build(BuildContext context) {
    return _ControlDecorator(
      child: IconButton(
        tooltip: 'Restart the Widget Previewer',
        onPressed: controller.dtdServices.hotRestartPreviewer,
        icon: const Icon(Icons.restart_alt),
        color: Colors.black,
      ),
    );
  }
}

/// Controls for searching and filtering widget previews.
///
/// This widget combines a text query field with a popup menu for selecting
/// which preview fields are included in search.
class PreviewSearchControls extends StatefulWidget {
  const PreviewSearchControls({super.key, required this.controller});

  final WidgetPreviewScaffoldController controller;

  @override
  State<PreviewSearchControls> createState() => _PreviewSearchControlsState();
}

class _PreviewSearchControlsState extends State<PreviewSearchControls> {
  late final TextEditingController _searchController;
  late List<_SearchFilterEntry> _searchFilters;

  @override
  void initState() {
    super.initState();
    _searchFilters = _buildSearchFilters(widget.controller);
    _searchController = TextEditingController(
      text: widget.controller.searchQueryListenable.value,
    );
    widget.controller.searchQueryListenable.addListener(
      _syncControllerQueryToTextField,
    );
  }

  @override
  void didUpdateWidget(covariant PreviewSearchControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) {
      return;
    }
    oldWidget.controller.searchQueryListenable.removeListener(
      _syncControllerQueryToTextField,
    );
    widget.controller.searchQueryListenable.addListener(
      _syncControllerQueryToTextField,
    );
    _searchFilters = _buildSearchFilters(widget.controller);
    _syncControllerQueryToTextField();
  }

  @override
  void dispose() {
    widget.controller.searchQueryListenable.removeListener(
      _syncControllerQueryToTextField,
    );
    _searchController.dispose();
    super.dispose();
  }

  void _syncControllerQueryToTextField() {
    final String query = widget.controller.searchQueryListenable.value;
    if (_searchController.text == query) {
      return;
    }
    _searchController.value = _searchController.value.copyWith(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
      composing: TextRange.empty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    const iconConstraints = BoxConstraints(
      minWidth: defaultButtonHeight,
      minHeight: defaultButtonHeight,
    );
    return _ControlDecorator(
      child: Row(
        children: <Widget>[
          Expanded(
            child: SizedBox(
              height: defaultButtonHeight,
              child: TextField(
                controller: _searchController,
                style: theme.regularTextStyleWithColor(Colors.black),
                cursorColor: Colors.black,
                textAlignVertical: TextAlignVertical.center,
                onChanged: widget.controller.updateSearchQuery,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search previews',
                  hintStyle: theme.regularTextStyleWithColor(Colors.black54),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: densePadding,
                    horizontal: denseSpacing,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: defaultIconSize,
                    color: Colors.black54,
                  ),
                  prefixIconConstraints: iconConstraints,
                  suffixIcon: _SearchClearButton(controller: widget.controller),
                  suffixIconConstraints: iconConstraints,
                ),
              ),
            ),
          ),
          Container(height: 16, width: 1, color: Colors.black26),
          _SearchFiltersMenuButton(searchFilters: _searchFilters),
        ],
      ),
    );
  }
}

class _SearchClearButton extends StatelessWidget {
  const _SearchClearButton({required this.controller});

  final WidgetPreviewScaffoldController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ValueListenableBuilder<String>(
      valueListenable: controller.searchQueryListenable,
      builder: (BuildContext context, String query, _) {
        if (query.isEmpty) {
          return const SizedBox.shrink();
        }
        return IconButton(
          tooltip: 'Clear search',
          style: theme.iconButtonTheme.style,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.clear, size: defaultIconSize),
          color: Colors.black,
          onPressed: () => controller.updateSearchQuery(''),
        );
      },
    );
  }
}

class _SearchFiltersMenuButton extends StatelessWidget {
  const _SearchFiltersMenuButton({required this.searchFilters});

  final List<_SearchFilterEntry> searchFilters;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        for (final _SearchFilterEntry entry in searchFilters) entry.listenable,
      ]),
      builder: (BuildContext context, _) {
        final bool allFiltersEnabled = searchFilters.every(
          (_SearchFilterEntry entry) => entry.listenable.value,
        );
        return PopupMenuButton<_PreviewSearchFilter>(
          tooltip: 'Search fields',
          style: theme.iconButtonTheme.style,
          iconColor: allFiltersEnabled ? Colors.black : Colors.blue,
          iconSize: defaultIconSize,
          icon: const Icon(Icons.filter_list),
          onSelected: (_PreviewSearchFilter selected) {
            final bool didToggle = searchFilters
                .firstWhere((_SearchFilterEntry e) => e.filter == selected)
                .onToggle();
            if (!didToggle) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(
                    content: Text(
                      'At least one search field must remain enabled.',
                    ),
                  ),
                );
            }
          },
          itemBuilder: (BuildContext context) =>
              <CheckedPopupMenuItem<_PreviewSearchFilter>>[
                for (final _SearchFilterEntry entry in searchFilters)
                  CheckedPopupMenuItem<_PreviewSearchFilter>(
                    value: entry.filter,
                    checked: entry.listenable.value,
                    child: Text(entry.filter.label),
                  ),
              ],
        );
      },
    );
  }
}

extension on Brightness {
  Brightness get invert => isLight ? Brightness.dark : Brightness.light;
  bool get isLight => this == Brightness.light;
}

/// A button that toggles the current theme brightness.
class BrightnessToggleButton extends StatelessWidget {
  const BrightnessToggleButton({super.key, required this.brightnessListenable});

  final ValueNotifier<Brightness> brightnessListenable;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Brightness>(
      valueListenable: brightnessListenable,
      builder: (BuildContext context, Brightness brightness, _) {
        return _ControlDecorator(
          child: IconButton(
            tooltip: 'Switch to ${brightness.isLight ? 'dark' : 'light'} mode',
            onPressed: () =>
                brightnessListenable.value = brightnessListenable.value.invert,
            icon: Icon(brightness.isLight ? Icons.dark_mode : Icons.light_mode),
            color: Colors.black,
          ),
        );
      },
    );
  }
}

/// Compact pill badge displaying [label] on `surfaceContainerHighest`.
class PreviewInfoBadge extends StatelessWidget {
  const PreviewInfoBadge({required this.label, super.key});

  static const _kBorderRadius = 4.0;
  static const _kHorizontalPadding = 6.0;
  static const _kVerticalPadding = 2.0;

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_kBorderRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _kHorizontalPadding,
          vertical: _kVerticalPadding,
        ),
        child: Text(label, style: theme.textTheme.labelSmall),
      ),
    );
  }
}

/// A button that copies [textToCopy] to the clipboard and temporarily displays
/// [copiedLabel] as feedback.
class CopyFeedbackButton extends StatefulWidget {
  const CopyFeedbackButton({
    required this.copiedLabel,
    required this.label,
    required this.textToCopy,
    this.icon,
    this.style,
    super.key,
  });

  /// Temporary label displayed after copying [textToCopy].
  final String copiedLabel;

  /// Optional leading icon displayed before [label].
  final IconData? icon;

  /// Default button label shown before copying.
  final String label;

  /// Optional [ButtonStyle] override for the underlying [OutlinedButton].
  final ButtonStyle? style;

  /// Text written to the system clipboard on tap.
  final String textToCopy;

  @override
  State<CopyFeedbackButton> createState() => _CopyFeedbackButtonState();
}

class _CopyFeedbackButtonState extends State<CopyFeedbackButton> {
  static const _kResetDelay = Duration(seconds: 2);

  var _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.textToCopy));
    if (!mounted) {
      return;
    }
    _resetTimer?.cancel();
    setState(() => _copied = true);
    _resetTimer = Timer(_kResetDelay, () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final String text = _copied ? widget.copiedLabel : widget.label;
    final Widget child = widget.icon != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(_copied ? Icons.check : widget.icon, size: 14),
              const SizedBox(width: 6),
              Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
            ],
          )
        : Text(text);
    return OutlinedButton(onPressed: _copy, style: widget.style, child: child);
  }
}

/// Starter `@Preview` snippet shown in empty-state views.
const kStarterPreviewSnippet = '''
@Preview(name: 'My Widget')
Widget myWidgetPreview() => const Text('Hello Preview');''';

/// Compact copyable starter `@Preview` card for empty-state views.
class StarterPreviewSnippetCard extends StatelessWidget {
  const StarterPreviewSnippetCard({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Add a top-level public @Preview function:',
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                kStarterPreviewSnippet,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 8),
            const CopyFeedbackButton(
              key: Key('copy-starter-preview-snippet'),
              copiedLabel: 'Copied!',
              icon: Icons.copy,
              label: 'Copy @Preview Snippet',
              textToCopy: kStarterPreviewSnippet,
            ),
          ],
        ),
      ),
    );
  }
}

// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widget_preview_scaffold/src/embed_selection_inspector.dart';
import 'package:widget_preview_scaffold/src/utils/url/url.dart';

export 'package:widget_preview_scaffold/src/embed_selection_inspector.dart';

const _kBadgeBackgroundColor = Color(0xFF1D4ED8);
const _kBadgeBorderRadius = 4.0;
const _kBadgeEstimatedWidth = 52.0;
const _kBadgeFontSize = 11.0;
const _kBadgeHeight = 20.0;
const _kBadgeHorizontalPadding = 5.0;
const _kBadgeSpacing = 4.0;
const _kBrightnessKey = 'brightness';
const _kHeightKey = 'height';
const _kIdKey = 'id';
const _kIndexKey = 'index';
const _kKindKey = 'kind';
const _kMinRegionDragDistance = 4.0;
const _kPointCrosshairArm = 7.0;
const _kPointDotRadius = 3.0;
const _kPointOverlayExtent = 16.0;
const _kPreviewHeightKey = 'previewHeight';
const _kPreviewIdKey = 'previewId';
const _kPreviewNameKey = 'previewName';
const _kPreviewWidthKey = 'previewWidth';
const _kSelectionBorderColor = Color(0xFF2563EB);
const _kSelectionBorderWidth = 1.5;
const _kSelectionFillColor = Color(0x242563EB);
const _kSelectionIdPrefix = 'sel-';
const _kTextScaleKey = 'textScale';
const _kWidgetsKey = 'widgets';
const _kWidthKey = 'width';
const _kXKey = 'x';
const _kYKey = 'y';
const _kZoomKey = 'zoom';

/// Single point or region selection recorded on a widget preview surface.
@immutable
class EmbedSelectionEntry {
  const EmbedSelectionEntry({
    required this.brightness,
    required this.height,
    required this.id,
    required this.index,
    required this.kind,
    required this.previewHeight,
    required this.previewId,
    required this.previewWidth,
    required this.textScale,
    required this.widgets,
    required this.width,
    required this.x,
    required this.y,
    required this.zoom,
    this.previewName,
  });

  final Brightness brightness;
  final int height;
  final String id;
  final int index;
  final EmbedSelectionKind kind;
  final int previewHeight;
  final String previewId;
  final String? previewName;
  final int previewWidth;
  final double textScale;
  final List<EmbedSelectedWidgetInfo> widgets;
  final int width;
  final int x;
  final int y;
  final double zoom;

  EmbedSelectionEntry withIndex(int nextIndex) {
    if (nextIndex == index) {
      return this;
    }
    return EmbedSelectionEntry(
      brightness: brightness,
      height: height,
      id: id,
      index: nextIndex,
      kind: kind,
      previewHeight: previewHeight,
      previewId: previewId,
      previewName: previewName,
      previewWidth: previewWidth,
      textScale: textScale,
      widgets: widgets,
      width: width,
      x: x,
      y: y,
      zoom: zoom,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    _kIdKey: id,
    _kIndexKey: index,
    _kKindKey: kind.wireValue,
    _kPreviewIdKey: previewId,
    if (previewName case final String name when name.isNotEmpty)
      _kPreviewNameKey: name,
    _kXKey: x,
    _kYKey: y,
    _kWidthKey: width,
    _kHeightKey: height,
    _kPreviewWidthKey: previewWidth,
    _kPreviewHeightKey: previewHeight,
    _kBrightnessKey: brightness.name,
    _kTextScaleKey: textScale,
    _kZoomKey: zoom,
    _kWidgetsKey: <Map<String, Object?>>[
      for (final EmbedSelectedWidgetInfo item in widgets) item.toJson(),
    ],
  };
}

/// Formats [selections] (with optional [projectRoot]) into a concise
/// human-readable context block suitable for copying to the clipboard.
String formatEmbedSelectionContext({
  required List<EmbedSelectionEntry> selections,
  String? projectRoot,
}) {
  if (selections.isEmpty) {
    return '';
  }
  final lines = <String>[
    'Selected Widget Preview Context (${selections.length}):',
    if (projectRoot case final String root when root.isNotEmpty)
      'Project: $root',
  ];
  for (final EmbedSelectionEntry entry in selections) {
    final String previewLabel =
        entry.previewName != null && entry.previewName!.isNotEmpty
        ? '${entry.previewName} (${entry.previewId})'
        : entry.previewId;
    final String geometry = switch (entry.kind) {
      .point => 'point (${entry.x}, ${entry.y})',
      .region =>
        'region (${entry.x}, ${entry.y}) ${entry.width}x${entry.height}',
    };
    lines.add(
      '#${entry.index} $previewLabel - $geometry in '
      '${entry.previewWidth}x${entry.previewHeight} '
      '[${entry.brightness.name}, textScale=${formatEmbedZoom(entry.textScale)}, '
      'zoom=${formatEmbedZoom(entry.zoom)}]',
    );
    for (final EmbedSelectedWidgetInfo widget in entry.widgets) {
      final parts = <String>[
        widget.widget,
        if (widget.key case final String key when key.isNotEmpty) 'key=$key',
        if (widget.text case final String text when text.isNotEmpty) '"$text"',
        '(${widget.x}, ${widget.y}) ${widget.width}x${widget.height}',
      ];
      lines.add('  - ${parts.join(' ')}');
    }
  }
  return lines.join('\n');
}

/// Coordinates multi-region selection state and URL synchronization across
/// single-preview and gallery embed views.
class EmbedSelectionController extends ChangeNotifier {
  EmbedSelectionController({required EmbedPreviewParams initialParams})
    : _params = initialParams,
      _selectMode = initialParams.selectMode;

  EmbedPreviewParams _params;
  bool _selectMode;
  var _selectionCounter = 0;
  final _selections = <EmbedSelectionEntry>[];

  bool get selectMode => _selectMode;

  List<EmbedSelectionEntry> get selections =>
      List<EmbedSelectionEntry>.unmodifiable(_selections);

  List<Map<String, Object?>> get selectionsJson => <Map<String, Object?>>[
    for (final EmbedSelectionEntry entry in _selections) entry.toJson(),
  ];

  /// Synchronizes [selectMode] when outer URL [EmbedPreviewParams] change.
  void syncFromParams(EmbedPreviewParams nextParams) {
    final bool previousSelectMode = _selectMode;
    _params = nextParams;
    if (previousSelectMode != nextParams.selectMode) {
      _selectMode = nextParams.selectMode;
      notifyListeners();
    }
  }

  /// Updates [selectMode] and optionally syncs the embed URL fragment.
  void setSelectMode(bool active, {bool updateUrl = true}) {
    final bool modeChanged = _selectMode != active;
    _selectMode = active;
    _params = _params.copyWith(selectMode: active);
    if (updateUrl && modeChanged) {
      replaceEmbedUrl(_params.toFragment(baseUri: getBaseUri()));
    }
    if (modeChanged) {
      notifyListeners();
    }
  }

  /// Appends a newly captured selection entry.
  EmbedSelectionEntry addSelection({
    required Brightness brightness,
    required int height,
    required EmbedSelectionKind kind,
    required int previewHeight,
    required String previewId,
    required int previewWidth,
    required double textScale,
    required List<EmbedSelectedWidgetInfo> widgets,
    required int width,
    required int x,
    required int y,
    required double zoom,
    String? previewName,
  }) {
    final entry = EmbedSelectionEntry(
      brightness: brightness,
      height: height,
      id: '$_kSelectionIdPrefix${++_selectionCounter}',
      index: _selections.length + 1,
      kind: kind,
      previewHeight: previewHeight,
      previewId: previewId,
      previewName: previewName,
      previewWidth: previewWidth,
      textScale: textScale,
      widgets: List<EmbedSelectedWidgetInfo>.unmodifiable(widgets),
      width: width,
      x: x,
      y: y,
      zoom: zoom,
    );
    _selections.add(entry);
    notifyListeners();
    return entry;
  }

  /// Removes the selection matching [selectionId] and renumbers remaining
  /// entries `1..K`.
  void removeSelectionById(String selectionId) {
    final int removeIndex = _selections.indexWhere(
      (EmbedSelectionEntry entry) => entry.id == selectionId,
    );
    if (removeIndex < 0) {
      return;
    }
    _selections.removeAt(removeIndex);
    for (var i = 0; i < _selections.length; i++) {
      _selections[i] = _selections[i].withIndex(i + 1);
    }
    notifyListeners();
  }

  /// Clears all active selections.
  void clearSelections() {
    final bool hadSelections = _selections.isNotEmpty;
    _selections.clear();
    if (hadSelections) {
      notifyListeners();
    }
  }

  /// Handles `Escape` key presses: exits [selectMode] first if active, or
  /// clears active [selections] if any exist.
  bool handleEscapeKey() {
    if (_selectMode) {
      setSelectMode(false);
      return true;
    }
    if (_selections.isNotEmpty) {
      clearSelections();
      return true;
    }
    return false;
  }
}

class _EagerSelectionArenaMember implements GestureArenaMember {
  const _EagerSelectionArenaMember();

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {}
}

/// Unzoomed preview surface wrapper placed inside `ScaledPreviewLayout` to
/// capture marquee/point selections and render numbered `#1..#N` overlays.
class EmbedSelectablePreviewSurface extends StatefulWidget {
  const EmbedSelectablePreviewSurface({
    required this.brightness,
    required this.child,
    required this.previewId,
    required this.selectionController,
    required this.textScale,
    required this.zoom,
    this.previewContentKey,
    this.previewName,
    super.key,
  });

  final Brightness brightness;
  final Widget child;
  final GlobalKey? previewContentKey;
  final String previewId;
  final String? previewName;
  final EmbedSelectionController selectionController;
  final double textScale;
  final double zoom;

  @override
  State<EmbedSelectablePreviewSurface> createState() =>
      _EmbedSelectablePreviewSurfaceState();
}

class _EmbedSelectablePreviewSurfaceState
    extends State<EmbedSelectablePreviewSurface> {
  static const _arenaMember = _EagerSelectionArenaMember();

  final _surfaceKey = GlobalKey();
  final _fallbackChildKey = GlobalKey();
  int? _activePointerId;
  Offset? _dragStartLocal;
  Offset? _dragCurrentLocal;

  bool get _isDragging => _activePointerId != null;

  Offset _clampToSurface(Offset localOffset, Size size) {
    return Offset(
      localOffset.dx.clamp(0.0, math.max(0.0, size.width)),
      localOffset.dy.clamp(0.0, math.max(0.0, size.height)),
    );
  }

  RenderBox? _resolveSurfaceBox() {
    final RenderObject? renderObject = _surfaceKey.currentContext
        ?.findRenderObject();
    if (renderObject is RenderBox &&
        renderObject.attached &&
        renderObject.hasSize) {
      return renderObject;
    }
    return null;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_activePointerId != null) {
      return;
    }
    if (event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kPrimaryMouseButton) == 0) {
      return;
    }
    final bool shouldIntercept =
        widget.selectionController.selectMode ||
        HardwareKeyboard.instance.isShiftPressed;
    if (!shouldIntercept) {
      return;
    }
    final RenderBox? surfaceBox = _resolveSurfaceBox();
    if (surfaceBox == null) {
      return;
    }
    GestureBinding.instance.gestureArena
        .add(event.pointer, _arenaMember)
        .resolve(GestureDisposition.accepted);
    final Offset localStart = _clampToSurface(
      surfaceBox.globalToLocal(event.position),
      surfaceBox.size,
    );
    setState(() {
      _activePointerId = event.pointer;
      _dragStartLocal = localStart;
      _dragCurrentLocal = localStart;
    });
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointerId) {
      return;
    }
    final RenderBox? surfaceBox = _resolveSurfaceBox();
    if (surfaceBox == null) {
      return;
    }
    final Offset localCurrent = _clampToSurface(
      surfaceBox.globalToLocal(event.position),
      surfaceBox.size,
    );
    setState(() {
      _dragCurrentLocal = localCurrent;
    });
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointerId) {
      return;
    }
    setState(() {
      _activePointerId = null;
      _dragStartLocal = null;
      _dragCurrentLocal = null;
    });
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointerId) {
      return;
    }
    final RenderBox? surfaceBox = _resolveSurfaceBox();
    final Offset? start = _dragStartLocal;
    setState(() {
      _activePointerId = null;
      _dragStartLocal = null;
      _dragCurrentLocal = null;
    });
    if (surfaceBox == null || start == null) {
      return;
    }
    final Size surfaceSize = surfaceBox.size;
    final Offset end = _clampToSurface(
      surfaceBox.globalToLocal(event.position),
      surfaceSize,
    );
    final int previewWidth = surfaceSize.width.round();
    final int previewHeight = surfaceSize.height.round();
    final double dragDistance = (end - start).distance;

    final EmbedSelectionKind kind;
    final int x;
    final int y;
    final int width;
    final int height;
    if (dragDistance < _kMinRegionDragDistance) {
      kind = .point;
      x = end.dx.round().clamp(0, previewWidth);
      y = end.dy.round().clamp(0, previewHeight);
      width = 0;
      height = 0;
    } else {
      kind = .region;
      final rawRect = Rect.fromPoints(start, end);
      var left = rawRect.left.round().clamp(0, previewWidth);
      var top = rawRect.top.round().clamp(0, previewHeight);
      final int right = rawRect.right.round().clamp(0, previewWidth);
      final int bottom = rawRect.bottom.round().clamp(0, previewHeight);
      if (previewWidth > 0 && left >= previewWidth) {
        left = previewWidth - 1;
      }
      if (previewHeight > 0 && top >= previewHeight) {
        top = previewHeight - 1;
      }
      final int maxAllowedWidth = math.max(1, previewWidth - left);
      final int maxAllowedHeight = math.max(1, previewHeight - top);
      x = left;
      y = top;
      width = math.max(1, right - left).clamp(1, maxAllowedWidth);
      height = math.max(1, bottom - top).clamp(1, maxAllowedHeight);
    }

    final GlobalKey contentKey = widget.previewContentKey ?? _fallbackChildKey;
    final List<EmbedSelectedWidgetInfo> inspectedWidgets =
        inspectPreviewSubtree(
          height: height,
          kind: kind,
          rootContext: contentKey.currentContext,
          surfaceBox: surfaceBox,
          width: width,
          x: x,
          y: y,
        );
    widget.selectionController.addSelection(
      brightness: widget.brightness,
      height: height,
      kind: kind,
      previewHeight: previewHeight,
      previewId: widget.previewId,
      previewName: widget.previewName,
      previewWidth: previewWidth,
      textScale: widget.textScale,
      widgets: inspectedWidgets,
      width: width,
      x: x,
      y: y,
      zoom: widget.zoom,
    );
  }

  @override
  Widget build(BuildContext context) {
    final EmbedSelectablePreviewSurface(
      :Widget child,
      :GlobalKey? previewContentKey,
      :String previewId,
      :EmbedSelectionController selectionController,
    ) = widget;
    return ListenableBuilder(
      listenable: selectionController,
      builder: (BuildContext context, Widget? _) {
        final bool selectMode = selectionController.selectMode;
        final bool suppressChildPointers = selectMode || _isDragging;
        final previewSelections = <EmbedSelectionEntry>[
          for (final EmbedSelectionEntry entry
              in selectionController.selections)
            if (entry.previewId == previewId) entry,
        ];
        final Rect? marqueeRect = switch ((
          _dragStartLocal,
          _dragCurrentLocal,
        )) {
          (final Offset start, final Offset current) => Rect.fromPoints(
            start,
            current,
          ),
          _ => null,
        };

        final Widget wrappedChild = previewContentKey == null
            ? KeyedSubtree(key: _fallbackChildKey, child: child)
            : child;

        return Stack(
          key: _surfaceKey,
          clipBehavior: Clip.none,
          children: <Widget>[
            IgnorePointer(ignoring: suppressChildPointers, child: wrappedChild),
            Positioned.fill(
              child: MouseRegion(
                cursor: suppressChildPointers
                    ? SystemMouseCursors.precise
                    : MouseCursor.defer,
                opaque: false,
                child: Listener(
                  behavior: suppressChildPointers
                      ? HitTestBehavior.opaque
                      : HitTestBehavior.translucent,
                  onPointerDown: _handlePointerDown,
                  onPointerMove: _handlePointerMove,
                  onPointerUp: _handlePointerUp,
                  onPointerCancel: _handlePointerCancel,
                  child: marqueeRect != null
                      ? IgnorePointer(
                          child: CustomPaint(
                            key: ValueKey<String>(
                              'embed-selection-marquee-$previewId',
                            ),
                            painter: _MarqueePainter(rect: marqueeRect),
                          ),
                        )
                      : const SizedBox.expand(),
                ),
              ),
            ),
            for (final EmbedSelectionEntry entry in previewSelections)
              ..._buildSelectionOverlayWidgets(entry),
          ],
        );
      },
    );
  }

  List<Widget> _buildSelectionOverlayWidgets(EmbedSelectionEntry entry) {
    final double maxLeft = math.max(
      0.0,
      entry.previewWidth.toDouble() - _kBadgeEstimatedWidth,
    );
    final double maxTop = math.max(
      0.0,
      entry.previewHeight.toDouble() - _kBadgeHeight,
    );
    final double rawBadgeTop = switch (entry.kind) {
      .region =>
        entry.y >= (_kBadgeHeight + 2.0)
            ? entry.y.toDouble() - _kBadgeHeight - 2.0
            : entry.y.toDouble() + 2.0,
      .point => entry.y.toDouble() - _kBadgeHeight - 4.0,
    };
    final double badgeLeft = entry.x.toDouble().clamp(0.0, maxLeft);
    final double badgeTop = rawBadgeTop.clamp(0.0, maxTop);

    final Widget indicator = switch (entry.kind) {
      .region => Positioned(
        key: ValueKey<String>('embed-selection-overlay-${entry.id}'),
        left: entry.x.toDouble(),
        top: entry.y.toDouble(),
        width: entry.width.toDouble(),
        height: entry.height.toDouble(),
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _kSelectionFillColor,
              border: Border.all(
                color: _kSelectionBorderColor,
                width: _kSelectionBorderWidth,
              ),
            ),
          ),
        ),
      ),
      .point => Positioned(
        key: ValueKey<String>('embed-selection-overlay-${entry.id}'),
        left: entry.x.toDouble() - (_kPointOverlayExtent / 2.0),
        top: entry.y.toDouble() - (_kPointOverlayExtent / 2.0),
        width: _kPointOverlayExtent,
        height: _kPointOverlayExtent,
        child: const IgnorePointer(
          child: CustomPaint(painter: _PointPinPainter()),
        ),
      ),
    };

    final Widget badgeContent = Directionality(
      textDirection: TextDirection.ltr,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _kBadgeBackgroundColor,
          borderRadius: BorderRadius.circular(_kBadgeBorderRadius),
        ),
        child: SizedBox(
          height: _kBadgeHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _kBadgeHorizontalPadding,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IgnorePointer(
                  child: Text(
                    '#${entry.index}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: _kBadgeFontSize,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                    ),
                  ),
                ),
                const SizedBox(width: _kBadgeSpacing),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    key: ValueKey<String>('embed-selection-remove-${entry.id}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.selectionController.removeSelectionById(
                      entry.id,
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 2.0),
                      child: Text(
                        '\u00D7',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13.0,
                          fontWeight: FontWeight.bold,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final Widget badge = Positioned(
      left: badgeLeft,
      top: badgeTop,
      child:
          entry.previewWidth > 0 && entry.previewWidth < _kBadgeEstimatedWidth
          ? ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: entry.previewWidth.toDouble(),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: badgeContent,
              ),
            )
          : badgeContent,
    );

    return <Widget>[indicator, badge];
  }
}

class _MarqueePainter extends CustomPainter {
  const _MarqueePainter({required this.rect});

  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = _kSelectionFillColor
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = _kSelectionBorderColor
      ..strokeWidth = _kSelectionBorderWidth
      ..style = PaintingStyle.stroke;
    canvas
      ..drawRect(rect, fillPaint)
      ..drawRect(rect, borderPaint);
  }

  @override
  bool shouldRepaint(_MarqueePainter oldDelegate) => oldDelegate.rect != rect;
}

class _PointPinPainter extends CustomPainter {
  const _PointPinPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2.0, size.height / 2.0);
    final strokePaint = Paint()
      ..color = _kSelectionBorderColor
      ..strokeWidth = _kSelectionBorderWidth
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = _kSelectionBorderColor
      ..style = PaintingStyle.fill;
    canvas
      ..drawLine(
        Offset(center.dx - _kPointCrosshairArm, center.dy),
        Offset(center.dx + _kPointCrosshairArm, center.dy),
        strokePaint,
      )
      ..drawLine(
        Offset(center.dx, center.dy - _kPointCrosshairArm),
        Offset(center.dx, center.dy + _kPointCrosshairArm),
        strokePaint,
      )
      ..drawCircle(center, _kPointDotRadius, fillPaint);
  }

  @override
  bool shouldRepaint(_PointPinPainter oldDelegate) => false;
}

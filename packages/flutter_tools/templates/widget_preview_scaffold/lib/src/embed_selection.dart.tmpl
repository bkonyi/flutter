// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widget_preview_scaffold/src/utils/url/url.dart';

const _kBadgeBackgroundColor = Color(0xFF1D4ED8);
const _kBadgeBorderRadius = 4.0;
const _kBadgeEstimatedWidth = 52.0;
const _kBadgeFontSize = 11.0;
const _kBadgeHeight = 20.0;
const _kBadgeHorizontalPadding = 5.0;
const _kBadgeOffset = 2.0;
const _kBadgePointOffset = 4.0;
const _kBadgeRemoveFontSize = 13.0;
const _kBadgeSpacing = 4.0;
const _kBrightnessKey = 'brightness';
const _kHeightKey = 'height';
const _kIdKey = 'id';
const _kIndexKey = 'index';
const _kKeyKey = 'key';
const _kKindKey = 'kind';
const _kMaxExtractedTextLength = 80;
const _kMaxInspectedWidgets = 12;
const _kMinRegionDragDistance = 4.0;
const _kPointHitInflation = 2.0;
const _kPointOverlayExtent = 14.0;
const _kPreviewHeightKey = 'previewHeight';
const _kPreviewIdKey = 'previewId';
const _kPreviewNameKey = 'previewName';
const _kPreviewWidthKey = 'previewWidth';
const _kSelectionBorderColor = Color(0xFF2563EB);
const _kSelectionBorderWidth = 1.5;
const _kSelectionFillColor = Color(0x242563EB);
const _kSelectionIdPrefix = 'sel-';
const _kTextKey = 'text';
const _kTextScaleKey = 'textScale';
const _kWidgetKey = 'widget';
const _kWidgetsKey = 'widgets';
const _kWidthKey = 'width';
const _kXKey = 'x';
const _kYKey = 'y';
const _kZoomKey = 'zoom';

const _kSelectionBoxDecoration = BoxDecoration(
  color: _kSelectionFillColor,
  border: Border.fromBorderSide(
    BorderSide(color: _kSelectionBorderColor, width: _kSelectionBorderWidth),
  ),
);

const _kPointPinDecoration = BoxDecoration(
  color: _kSelectionFillColor,
  shape: BoxShape.circle,
  border: Border.fromBorderSide(
    BorderSide(color: _kSelectionBorderColor, width: _kSelectionBorderWidth),
  ),
);

const _kPlumbingWidgetTypes = <String>{
  'AbsorbPointer',
  'Actions',
  'Align',
  'AnimatedDefaultTextStyle',
  'AnimatedPhysicalModel',
  'AnimatedTheme',
  'BlockSemantics',
  'Builder',
  'Center',
  'ClipRRect',
  'ClipRect',
  'ColoredBox',
  'ConstrainedBox',
  'DecoratedBox',
  'DefaultAssetBundle',
  'DefaultTextStyle',
  'Directionality',
  'EnableWidgetInspectorScope',
  'ExcludeSemantics',
  'Focus',
  'FocusScope',
  'FocusTraversalGroup',
  'IconTheme',
  'IgnorePointer',
  'KeyedSubtree',
  'Listener',
  'Localizations',
  'MediaQuery',
  'MergeSemantics',
  'MouseRegion',
  'NotificationListener',
  'Opacity',
  'Padding',
  'PhysicalModel',
  'PreviewWidget',
  'RepaintBoundary',
  'Semantics',
  'Shortcuts',
  'SizedBox',
  'StatefulBuilder',
  'Theme',
  'Transform',
  'WidgetInspector',
  'WidgetPreviewLocalizations',
  'WidgetPreviewTheming',
  'WidgetPreviewWrapper',
  'WidgetPreviewerWindowConstraints',
};

/// Geometry classification for an interactive preview selection.
enum EmbedSelectionKind {
  point('point'),
  region('region');

  const EmbedSelectionKind(this.wireValue);

  final String wireValue;
}

/// Summary of a rendered Flutter widget intersecting a preview selection.
@immutable
class EmbedSelectedWidgetInfo {
  const EmbedSelectedWidgetInfo({
    required this.height,
    required this.widget,
    required this.width,
    required this.x,
    required this.y,
    this.key,
    this.text,
  });

  final int height;
  final String? key;
  final String? text;
  final String widget;
  final int width;
  final int x;
  final int y;

  int get area => width * height;

  Map<String, Object?> toJson() => <String, Object?>{
    _kWidgetKey: widget,
    if (key case final String k when k.isNotEmpty) _kKeyKey: k,
    if (text case final String t when t.isNotEmpty) _kTextKey: t,
    _kXKey: x,
    _kYKey: y,
    _kWidthKey: width,
    _kHeightKey: height,
  };
}

/// Inspects the rendered [Element] subtree rooted at [rootContext] and returns
/// up to [_kMaxInspectedWidgets] rendered [RenderBox] widgets intersecting the
/// selection in [surfaceBox]-local logical pixels.
List<EmbedSelectedWidgetInfo> inspectPreviewSubtree({
  required int height,
  required EmbedSelectionKind kind,
  required BuildContext? rootContext,
  required RenderBox surfaceBox,
  required int width,
  required int x,
  required int y,
}) {
  if (rootContext is! Element || !rootContext.mounted || !surfaceBox.attached) {
    return const <EmbedSelectedWidgetInfo>[];
  }
  final queryRect = Rect.fromLTWH(
    x.toDouble(),
    y.toDouble(),
    width.toDouble(),
    height.toDouble(),
  );
  final pointTarget = Offset(x.toDouble(), y.toDouble());
  final candidates = <({EmbedSelectedWidgetInfo info, int order})>[];
  var traversalCounter = 0;

  void visit(Element element, {required bool insideTextWidget}) {
    if (!element.mounted) {
      return;
    }
    final Widget currentWidget = element.widget;
    final bool isTextWidget = currentWidget is Text;
    final String typeName = currentWidget.runtimeType.toString();
    final int genericIndex = typeName.indexOf('<');
    final String baseType = genericIndex > 0
        ? typeName.substring(0, genericIndex)
        : typeName;
    final bool shouldSkipWidget =
        typeName.startsWith('_') ||
        (currentWidget.key == null &&
            (_kPlumbingWidgetTypes.contains(baseType) ||
                (insideTextWidget && currentWidget is RichText)));

    if (!shouldSkipWidget && element.renderObject is RenderBox) {
      final box = element.renderObject! as RenderBox;
      if (box.attached && box.hasSize && !box.size.isEmpty) {
        final Rect localBounds = MatrixUtils.transformRect(
          box.getTransformTo(surfaceBox),
          Offset.zero & box.size,
        );
        final bool intersects = switch (kind) {
          .region => localBounds.overlaps(queryRect),
          .point =>
            localBounds.inflate(_kPointHitInflation).contains(pointTarget),
        };
        if (intersects) {
          candidates.add((
            info: EmbedSelectedWidgetInfo(
              height: math.max(1, localBounds.height.round()),
              key: currentWidget.key?.toString(),
              text: _extractConciseText(currentWidget),
              widget: typeName,
              width: math.max(1, localBounds.width.round()),
              x: localBounds.left.round(),
              y: localBounds.top.round(),
            ),
            order: traversalCounter++,
          ));
        }
      }
    }

    element.visitChildElements((Element child) {
      visit(child, insideTextWidget: insideTextWidget || isTextWidget);
    });
  }

  rootContext.visitChildElements((Element child) {
    visit(child, insideTextWidget: false);
  });

  int metadataScore(EmbedSelectedWidgetInfo info) =>
      (info.key != null ? 2 : 0) + (info.text != null ? 1 : 0);

  candidates.sort((a, b) {
    final int byArea = a.info.area.compareTo(b.info.area);
    if (byArea != 0) {
      return byArea;
    }
    final int byScore = metadataScore(b.info).compareTo(metadataScore(a.info));
    return byScore != 0 ? byScore : a.order.compareTo(b.order);
  });

  final deduplicated = <EmbedSelectedWidgetInfo>[];
  final seen = <(String, int, int, int, int)>{};
  for (final (:EmbedSelectedWidgetInfo info, order: _) in candidates) {
    if (seen.add((info.widget, info.x, info.y, info.width, info.height))) {
      deduplicated.add(info);
      if (deduplicated.length >= _kMaxInspectedWidgets) {
        break;
      }
    }
  }
  return deduplicated;
}

String? _extractConciseText(Widget widget) {
  final String? raw = switch (widget) {
    Text(:final String? data, :final InlineSpan? textSpan) =>
      data ?? textSpan?.toPlainText(),
    RichText(:final InlineSpan text) => text.toPlainText(),
    EditableText(:final TextEditingController controller) => controller.text,
    _ => null,
  };
  if (raw == null) {
    return null;
  }
  final String collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.isEmpty) {
    return null;
  }
  return collapsed.length <= _kMaxExtractedTextLength
      ? collapsed
      : '${collapsed.substring(0, _kMaxExtractedTextLength - 3)}...';
}

/// Single point or region selection recorded on a widget preview surface.
@immutable
class EmbedSelectionEntry {
  const EmbedSelectionEntry({
    required this.brightness,
    required this.height,
    required this.id,
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

  Map<String, Object?> toJson({required int index}) => <String, Object?>{
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
  for (final (int i, EmbedSelectionEntry entry) in selections.indexed) {
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
      '#${i + 1} $previewLabel - $geometry in '
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
    for (final (int i, EmbedSelectionEntry entry) in _selections.indexed)
      entry.toJson(index: i + 1),
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
    final int previousLength = _selections.length;
    _selections.removeWhere(
      (EmbedSelectionEntry entry) => entry.id == selectionId,
    );
    if (_selections.length != previousLength) {
      notifyListeners();
    }
  }

  /// Clears all active selections.
  void clearSelections() {
    if (_selections.isEmpty) {
      return;
    }
    _selections.clear();
    notifyListeners();
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

  Offset _clampToSurface(Offset localOffset, Size size) => Offset(
    localOffset.dx.clamp(0.0, math.max(0.0, size.width)),
    localOffset.dy.clamp(0.0, math.max(0.0, size.height)),
  );

  RenderBox? _resolveSurfaceBox() {
    final RenderObject? renderObject = _surfaceKey.currentContext
        ?.findRenderObject();
    return renderObject is RenderBox &&
            renderObject.attached &&
            renderObject.hasSize
        ? renderObject
        : null;
  }

  void _clearActiveDrag() {
    setState(() {
      _activePointerId = null;
      _dragStartLocal = null;
      _dragCurrentLocal = null;
    });
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_activePointerId != null ||
        (event.kind == PointerDeviceKind.mouse &&
            (event.buttons & kPrimaryMouseButton) == 0) ||
        (!widget.selectionController.selectMode &&
            !HardwareKeyboard.instance.isShiftPressed)) {
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
    if (_resolveSurfaceBox() case final RenderBox surfaceBox) {
      setState(() {
        _dragCurrentLocal = _clampToSurface(
          surfaceBox.globalToLocal(event.position),
          surfaceBox.size,
        );
      });
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer == _activePointerId) {
      _clearActiveDrag();
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointerId) {
      return;
    }
    final RenderBox? surfaceBox = _resolveSurfaceBox();
    final Offset? start = _dragStartLocal;
    _clearActiveDrag();
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

    final EmbedSelectionKind kind;
    final int x;
    final int y;
    final int width;
    final int height;
    if ((end - start).distance < _kMinRegionDragDistance) {
      kind = .point;
      x = end.dx.round().clamp(0, previewWidth);
      y = end.dy.round().clamp(0, previewHeight);
      width = 0;
      height = 0;
    } else {
      kind = .region;
      final rawRect = Rect.fromPoints(start, end);
      final int maxLeft = math.max(0, previewWidth - 1);
      final int maxTop = math.max(0, previewHeight - 1);
      x = rawRect.left.round().clamp(0, maxLeft);
      y = rawRect.top.round().clamp(0, maxTop);
      width = math
          .max(1, rawRect.right.round().clamp(0, previewWidth) - x)
          .clamp(1, math.max(1, previewWidth - x));
      height = math
          .max(1, rawRect.bottom.round().clamp(0, previewHeight) - y)
          .clamp(1, math.max(1, previewHeight - y));
    }

    final GlobalKey contentKey = widget.previewContentKey ?? _fallbackChildKey;
    widget.selectionController.addSelection(
      brightness: widget.brightness,
      height: height,
      kind: kind,
      previewHeight: previewHeight,
      previewId: widget.previewId,
      previewName: widget.previewName,
      previewWidth: previewWidth,
      textScale: widget.textScale,
      widgets: inspectPreviewSubtree(
        height: height,
        kind: kind,
        rootContext: contentKey.currentContext,
        surfaceBox: surfaceBox,
        width: width,
        x: x,
        y: y,
      ),
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
        final bool suppressChildPointers =
            selectionController.selectMode || _activePointerId != null;
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
        return Stack(
          key: _surfaceKey,
          clipBehavior: Clip.none,
          children: <Widget>[
            IgnorePointer(
              ignoring: suppressChildPointers,
              child: previewContentKey == null
                  ? KeyedSubtree(key: _fallbackChildKey, child: child)
                  : child,
            ),
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
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            if (marqueeRect != null)
              Positioned.fromRect(
                rect: marqueeRect,
                child: IgnorePointer(
                  child: DecoratedBox(
                    key: ValueKey<String>('embed-selection-marquee-$previewId'),
                    decoration: _kSelectionBoxDecoration,
                  ),
                ),
              ),
            for (final (int i, EmbedSelectionEntry entry)
                in selectionController.selections.indexed)
              if (entry.previewId == previewId)
                ..._buildSelectionOverlayWidgets(entry, i + 1),
          ],
        );
      },
    );
  }

  List<Widget> _buildSelectionOverlayWidgets(
    EmbedSelectionEntry entry,
    int displayIndex,
  ) {
    final double rawBadgeTop = switch (entry.kind) {
      .region =>
        entry.y >= (_kBadgeHeight + _kBadgeOffset)
            ? entry.y - _kBadgeHeight - _kBadgeOffset
            : entry.y + _kBadgeOffset,
      .point => entry.y - _kBadgeHeight - _kBadgePointOffset,
    };
    final double badgeLeft = entry.x.toDouble().clamp(
      0.0,
      math.max(0.0, entry.previewWidth - _kBadgeEstimatedWidth),
    );
    final double badgeTop = rawBadgeTop.clamp(
      0.0,
      math.max(0.0, entry.previewHeight - _kBadgeHeight),
    );
    final overlayKey = ValueKey<String>('embed-selection-overlay-${entry.id}');
    final Widget indicator = switch (entry.kind) {
      .region => Positioned(
        key: overlayKey,
        left: entry.x.toDouble(),
        top: entry.y.toDouble(),
        width: entry.width.toDouble(),
        height: entry.height.toDouble(),
        child: const IgnorePointer(
          child: DecoratedBox(decoration: _kSelectionBoxDecoration),
        ),
      ),
      .point => Positioned(
        key: overlayKey,
        left: entry.x - (_kPointOverlayExtent / 2),
        top: entry.y - (_kPointOverlayExtent / 2),
        width: _kPointOverlayExtent,
        height: _kPointOverlayExtent,
        child: const IgnorePointer(
          child: DecoratedBox(decoration: _kPointPinDecoration),
        ),
      ),
    };

    final Widget badge = Positioned(
      left: badgeLeft,
      top: badgeTop,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: entry.previewWidth > 0
              ? entry.previewWidth.toDouble()
              : _kBadgeEstimatedWidth,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Directionality(
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
                          '#$displayIndex',
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
                          key: ValueKey<String>(
                            'embed-selection-remove-${entry.id}',
                          ),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => widget.selectionController
                              .removeSelectionById(entry.id),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: _kBadgeOffset,
                            ),
                            child: Text(
                              '\u00D7',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: _kBadgeRemoveFontSize,
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
          ),
        ),
      ),
    );

    return <Widget>[indicator, badge];
  }
}

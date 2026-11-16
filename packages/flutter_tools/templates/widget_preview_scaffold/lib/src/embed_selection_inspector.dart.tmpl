// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

const _kHeightKey = 'height';
const _kKeyKey = 'key';
const _kMaxExtractedTextLength = 80;
const _kMaxInspectedWidgets = 12;
const _kPointHitInflation = 2.0;
const _kTextKey = 'text';
const _kWidgetKey = 'widget';
const _kWidthKey = 'width';
const _kXKey = 'x';
const _kYKey = 'y';

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
    final bool hasExplicitKey = currentWidget.key != null;
    final bool shouldSkipWidget =
        typeName.startsWith('_') ||
        (!hasExplicitKey &&
            (_isPlumbingType(typeName) ||
                (insideTextWidget && currentWidget is RichText)));

    if (!shouldSkipWidget) {
      final RenderObject? renderObject = element.renderObject;
      if (renderObject is RenderBox &&
          renderObject.attached &&
          renderObject.hasSize &&
          !renderObject.size.isEmpty) {
        final Matrix4 transform = renderObject.getTransformTo(surfaceBox);
        final Rect localBounds = MatrixUtils.transformRect(
          transform,
          Offset.zero & renderObject.size,
        );
        final bool intersects = switch (kind) {
          .region => localBounds.overlaps(queryRect),
          .point =>
            localBounds.inflate(_kPointHitInflation).contains(pointTarget),
        };
        if (intersects) {
          final int boxX = localBounds.left.round();
          final int boxY = localBounds.top.round();
          final int boxWidth = math.max(1, localBounds.width.round());
          final int boxHeight = math.max(1, localBounds.height.round());
          candidates.add((
            info: EmbedSelectedWidgetInfo(
              height: boxHeight,
              key: currentWidget.key?.toString(),
              text: _extractConciseText(currentWidget),
              widget: typeName,
              width: boxWidth,
              x: boxX,
              y: boxY,
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

  candidates.sort((
    ({EmbedSelectedWidgetInfo info, int order}) a,
    ({EmbedSelectedWidgetInfo info, int order}) b,
  ) {
    final int areaComparison = a.info.area.compareTo(b.info.area);
    if (areaComparison != 0) {
      return areaComparison;
    }
    final int aMetadataScore =
        (a.info.key != null ? 2 : 0) + (a.info.text != null ? 1 : 0);
    final int bMetadataScore =
        (b.info.key != null ? 2 : 0) + (b.info.text != null ? 1 : 0);
    if (aMetadataScore != bMetadataScore) {
      return bMetadataScore.compareTo(aMetadataScore);
    }
    return a.order.compareTo(b.order);
  });

  final deduplicated = <EmbedSelectedWidgetInfo>[];
  final seenSignatures = <(String, int, int, int, int)>{};
  for (final (:EmbedSelectedWidgetInfo info, order: _) in candidates) {
    final (String, int, int, int, int) signature = (
      info.widget,
      info.x,
      info.y,
      info.width,
      info.height,
    );
    if (seenSignatures.add(signature)) {
      deduplicated.add(info);
      if (deduplicated.length >= _kMaxInspectedWidgets) {
        break;
      }
    }
  }
  return deduplicated;
}

bool _isPlumbingType(String typeName) {
  final int genericIndex = typeName.indexOf('<');
  final String baseType = genericIndex > 0
      ? typeName.substring(0, genericIndex)
      : typeName;
  return _kPlumbingWidgetTypes.contains(baseType);
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
  if (collapsed.length <= _kMaxExtractedTextLength) {
    return collapsed;
  }
  return '${collapsed.substring(0, _kMaxExtractedTextLength - 3)}...';
}

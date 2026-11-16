// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:dtd/dtd.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:meta/meta.dart';

import '../base/time.dart';
import 'dtd_types.dart';

const _kBrightnessKey = 'brightness';
const _kDarkBrightness = 'dark';
const _kHeightKey = 'height';
const _kIdKey = 'id';
const _kIndexKey = 'index';
const _kKeyKey = 'key';
const _kKindKey = 'kind';
const _kLightBrightness = 'light';
const _kPointKind = 'point';
const _kPreviewHeightKey = 'previewHeight';
const _kPreviewIdKey = 'previewId';
const _kPreviewNameKey = 'previewName';
const _kPreviewWidthKey = 'previewWidth';
const _kRectKindAlias = 'rect';
const _kRegionKind = 'region';
const _kSelectionIdPrefix = 'sel-';
const _kTextKey = 'text';
const _kTextScaleKey = 'textScale';
const _kWidgetKey = 'widget';
const _kWidgetsKey = 'widgets';
const _kWidthKey = 'width';
const _kXKey = 'x';
const _kYKey = 'y';
const _kZoomKey = 'zoom';

const _kAllowedEntryKeys = <String>{
  _kBrightnessKey,
  _kHeightKey,
  _kIdKey,
  _kIndexKey,
  _kKindKey,
  _kPreviewHeightKey,
  _kPreviewIdKey,
  _kPreviewNameKey,
  _kPreviewWidthKey,
  _kTextScaleKey,
  _kWidgetsKey,
  _kWidthKey,
  _kXKey,
  _kYKey,
  _kZoomKey,
};

const _kAllowedWidgetKeys = <String>{
  _kHeightKey,
  _kKeyKey,
  _kTextKey,
  _kWidgetKey,
  _kWidthKey,
  _kXKey,
  _kYKey,
};

/// Geometry classification for an active widget preview selection.
enum PreviewSelectionKind {
  point(_kPointKind),
  region(_kRegionKind);

  const PreviewSelectionKind(this.wireValue);

  final String wireValue;

  static PreviewSelectionKind parse(Object? raw, {required int entryIndex}) {
    return switch (raw) {
      _kPointKind => .point,
      _kRegionKind || _kRectKindAlias => .region,
      _ => throw RpcException.invalidParams(
        'Selection entry $entryIndex field "$_kKindKey" must be "$_kPointKind" or "$_kRegionKind".',
      ),
    };
  }
}

/// Typed wire representation of a rendered widget intersecting a preview selection.
@immutable
class PreviewSelectedWidget {
  const PreviewSelectedWidget({
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

  static PreviewSelectedWidget fromJson(
    Object? raw, {
    required int entryIndex,
    required int widgetIndex,
  }) {
    final context = 'Selection entry $entryIndex widget $widgetIndex';
    final Map<String, Object?> map = _requireAllowedKeyMap(
      raw,
      allowedKeys: _kAllowedWidgetKeys,
      context: context,
    );
    final String? keyValue = _optionalBoundedString(map, _kKeyKey, context: context);
    final String? textValue = _optionalBoundedString(map, _kTextKey, context: context);
    return PreviewSelectedWidget(
      height: _requireNonNegativeInt(map, _kHeightKey, context: context),
      key: keyValue != null && keyValue.isNotEmpty ? keyValue : null,
      text: textValue != null && textValue.isNotEmpty ? textValue : null,
      widget: _requireNonEmptyBoundedString(map, _kWidgetKey, context: context),
      width: _requireNonNegativeInt(map, _kWidthKey, context: context),
      x: _requireInt(map, _kXKey, context: context),
      y: _requireInt(map, _kYKey, context: context),
    );
  }

  Map<String, Object?> toJson() => Map<String, Object?>.unmodifiable(<String, Object?>{
    _kWidgetKey: widget,
    _kKeyKey: ?key,
    _kTextKey: ?text,
    _kXKey: x,
    _kYKey: y,
    _kWidthKey: width,
    _kHeightKey: height,
  });
}

/// Typed wire representation of a point or region selection on a widget preview.
@immutable
class PreviewSelectionEntry {
  const PreviewSelectionEntry({
    required this.id,
    required this.index,
    required this.kind,
    required this.x,
    required this.y,
    this.brightness,
    this.height,
    this.previewHeight,
    this.previewId,
    this.previewName,
    this.previewWidth,
    this.textScale,
    this.widgets,
    this.width,
    this.zoom,
  });

  final String? brightness;
  final int? height;
  final String id;
  final int index;
  final PreviewSelectionKind kind;
  final int? previewHeight;
  final String? previewId;
  final String? previewName;
  final int? previewWidth;
  final double? textScale;
  final List<PreviewSelectedWidget>? widgets;
  final int? width;
  final int x;
  final int y;
  final double? zoom;

  static PreviewSelectionEntry fromJson(Object? raw, {required int fallbackIndex}) {
    final context = 'Selection entry $fallbackIndex';
    final Map<String, Object?> map = _requireAllowedKeyMap(
      raw,
      allowedKeys: _kAllowedEntryKeys,
      context: context,
    );
    final PreviewSelectionKind kind = PreviewSelectionKind.parse(
      map[_kKindKey],
      entryIndex: fallbackIndex,
    );
    final int index = _optionalPositiveInt(map, _kIndexKey, context: context) ?? fallbackIndex;
    final String id =
        _optionalNonEmptyBoundedString(map, _kIdKey, context: context) ??
        '$_kSelectionIdPrefix$index';
    final int? width = _optionalNonNegativeInt(map, _kWidthKey, context: context);
    final int? height = _optionalNonNegativeInt(map, _kHeightKey, context: context);
    if (kind == .region && (width == null || height == null)) {
      throw RpcException.invalidParams(
        '$context with kind "${PreviewSelectionKind.region.wireValue}" requires "$_kWidthKey" and "$_kHeightKey".',
      );
    }
    final String? previewNameValue = _optionalBoundedString(
      map,
      _kPreviewNameKey,
      context: context,
    );
    List<PreviewSelectedWidget>? parsedWidgets;
    if (map.containsKey(_kWidgetsKey) && map[_kWidgetsKey] != null) {
      final Object? rawWidgets = map[_kWidgetsKey];
      if (rawWidgets is! List<Object?>) {
        throw RpcException.invalidParams('$context field "$_kWidgetsKey" must be a JSON list.');
      }
      if (rawWidgets.length > PreviewSelectionStore.kMaxWidgetsPerSelection) {
        throw RpcException.invalidParams(
          '$context field "$_kWidgetsKey" exceeds maximum of '
          '${PreviewSelectionStore.kMaxWidgetsPerSelection} entries.',
        );
      }
      parsedWidgets = List<PreviewSelectedWidget>.unmodifiable(<PreviewSelectedWidget>[
        for (var i = 0; i < rawWidgets.length; i++)
          PreviewSelectedWidget.fromJson(
            rawWidgets[i],
            entryIndex: fallbackIndex,
            widgetIndex: i + 1,
          ),
      ]);
    }
    return PreviewSelectionEntry(
      brightness: _optionalBrightness(map, _kBrightnessKey, context: context),
      height: height,
      id: id,
      index: index,
      kind: kind,
      previewHeight: _optionalNonNegativeInt(map, _kPreviewHeightKey, context: context),
      previewId: _optionalBoundedString(map, _kPreviewIdKey, context: context),
      previewName: previewNameValue != null && previewNameValue.isNotEmpty
          ? previewNameValue
          : null,
      previewWidth: _optionalNonNegativeInt(map, _kPreviewWidthKey, context: context),
      textScale: _optionalPositiveDouble(map, _kTextScaleKey, context: context),
      widgets: parsedWidgets,
      width: width,
      x: _requireInt(map, _kXKey, context: context),
      y: _requireInt(map, _kYKey, context: context),
      zoom: _optionalPositiveDouble(map, _kZoomKey, context: context),
    );
  }

  Map<String, Object?> toJson() => Map<String, Object?>.unmodifiable(<String, Object?>{
    _kIdKey: id,
    _kIndexKey: index,
    _kKindKey: kind.wireValue,
    _kPreviewIdKey: ?previewId,
    _kPreviewNameKey: ?previewName,
    _kXKey: x,
    _kYKey: y,
    _kWidthKey: ?width,
    _kHeightKey: ?height,
    _kPreviewWidthKey: ?previewWidth,
    _kPreviewHeightKey: ?previewHeight,
    _kBrightnessKey: ?brightness,
    _kTextScaleKey: ?textScale,
    _kZoomKey: ?zoom,
    if (widgets case final List<PreviewSelectedWidget> items)
      _kWidgetsKey: List<Map<String, Object?>>.unmodifiable(<Map<String, Object?>>[
        for (final PreviewSelectedWidget item in items) item.toJson(),
      ]),
  });
}

/// In-memory store tracking active widget preview region/point selections for
/// DTD clients and the `/live` HTTP shell.
class PreviewSelectionStore {
  PreviewSelectionStore({required this._clock});

  static const kMaxSelectionBodyBytes = 65_536;
  static const kMaxSelections = 32;
  static const kMaxStringLength = 1024;
  static const kMaxWidgetsPerSelection = 12;

  final SystemClock _clock;

  List<PreviewSelectionEntry> _entries = const <PreviewSelectionEntry>[];
  List<Map<String, Object?>> _selectionsJson = const <Map<String, Object?>>[];
  String? _updatedAt;

  /// Current immutable list of typed selection entries.
  List<PreviewSelectionEntry> get entries => _entries;

  /// Current immutable list of serialized selection JSON maps.
  List<Map<String, Object?>> get selections => _selectionsJson;

  /// Number of active selection entries.
  int get count => _entries.length;

  /// UTC ISO-8601 timestamp of the most recent update, or `null` if untouched.
  String? get updatedAt => _updatedAt;

  /// Validates and parses [rawSelections] into typed [PreviewSelectionEntry]
  /// instances.
  ///
  /// Throws [RpcException.invalidParams] when [rawSelections] violates schema
  /// or size bounds.
  static List<PreviewSelectionEntry> parseSelections(Object? rawSelections) {
    if (rawSelections is! List<Object?>) {
      throw RpcException.invalidParams(
        'Parameter "${WidgetPreviewSelection.kSelections}" must be a JSON list.',
      );
    }
    if (rawSelections.length > kMaxSelections) {
      throw RpcException.invalidParams(
        'Parameter "${WidgetPreviewSelection.kSelections}" exceeds maximum of $kMaxSelections entries.',
      );
    }
    return List<PreviewSelectionEntry>.unmodifiable(<PreviewSelectionEntry>[
      for (var i = 0; i < rawSelections.length; i++)
        PreviewSelectionEntry.fromJson(rawSelections[i], fallbackIndex: i + 1),
    ]);
  }

  /// Validates [rawSelections] and returns canonical JSON maps for RPC forwarding.
  static List<Map<String, Object?>> parseSelectionsToJson(Object? rawSelections) {
    final List<PreviewSelectionEntry> parsed = parseSelections(rawSelections);
    return List<Map<String, Object?>>.unmodifiable(<Map<String, Object?>>[
      for (final PreviewSelectionEntry entry in parsed) entry.toJson(),
    ]);
  }

  /// Validates and stores [rawSelections], updating [updatedAt] to UTC ISO-8601.
  void updateSelections(Object? rawSelections) {
    final List<PreviewSelectionEntry> parsed = parseSelections(rawSelections);
    _entries = parsed;
    _selectionsJson = List<Map<String, Object?>>.unmodifiable(<Map<String, Object?>>[
      for (final PreviewSelectionEntry entry in parsed) entry.toJson(),
    ]);
    _updatedAt = _clock.now().toUtc().toIso8601String();
  }

  /// Clears any active selections, updating [updatedAt] and returning `true`
  /// when at least one selection was cleared.
  bool clear() {
    if (_entries.isEmpty) {
      return false;
    }
    _entries = const <PreviewSelectionEntry>[];
    _selectionsJson = const <Map<String, Object?>>[];
    _updatedAt = _clock.now().toUtc().toIso8601String();
    return true;
  }

  /// Builds the `getSelection` / `GET /__api/selection` JSON payload.
  Map<String, Object?> toResponseJson() {
    return <String, Object?>{
      WidgetPreviewSelection.kType: WidgetPreviewSelection.kTypeName,
      WidgetPreviewSelection.kSelections: _selectionsJson,
      WidgetPreviewSelection.kCount: _entries.length,
      WidgetPreviewSelection.kUpdatedAt: _updatedAt,
    };
  }

  /// Builds the `SelectionUpdated` DTD stream event payload.
  Map<String, Object?> toEventPayload() {
    return <String, Object?>{
      WidgetPreviewSelection.kSelections: _selectionsJson,
      WidgetPreviewSelection.kCount: _entries.length,
      WidgetPreviewSelection.kUpdatedAt: _updatedAt,
    };
  }

  /// Builds the `setSelection` / `POST /__api/selection` mutation acknowledgment.
  Map<String, Object?> toMutationSuccessJson() {
    return <String, Object?>{
      ...const Success().toJson(),
      WidgetPreviewSelection.kCount: _entries.length,
      WidgetPreviewSelection.kUpdatedAt: _updatedAt,
    };
  }
}

Map<String, Object?> _requireAllowedKeyMap(
  Object? raw, {
  required Set<String> allowedKeys,
  required String context,
}) {
  if (raw is! Map<Object?, Object?>) {
    throw RpcException.invalidParams('$context must be a JSON object.');
  }
  final map = <String, Object?>{};
  for (final MapEntry(:Object? key, :Object? value) in raw.entries) {
    if (key is! String) {
      throw RpcException.invalidParams('$context keys must be strings.');
    }
    if (!allowedKeys.contains(key)) {
      throw RpcException.invalidParams('$context contains unsupported field "$key".');
    }
    map[key] = value;
  }
  return map;
}

int _requireInt(Map<String, Object?> map, String key, {required String context}) {
  final Object? raw = map[key];
  if (raw is int) {
    return raw;
  }
  throw RpcException.invalidParams('$context field "$key" must be an integer.');
}

int _requireNonNegativeInt(Map<String, Object?> map, String key, {required String context}) {
  final int value = _requireInt(map, key, context: context);
  if (value < 0) {
    throw RpcException.invalidParams('$context field "$key" must be non-negative.');
  }
  return value;
}

int? _optionalNonNegativeInt(Map<String, Object?> map, String key, {required String context}) {
  final Object? raw = map[key];
  if (raw == null) {
    return null;
  }
  if (raw is! int || raw < 0) {
    throw RpcException.invalidParams('$context field "$key" must be a non-negative integer.');
  }
  return raw;
}

int? _optionalPositiveInt(Map<String, Object?> map, String key, {required String context}) {
  final Object? raw = map[key];
  if (raw == null) {
    return null;
  }
  if (raw is! int || raw < 1) {
    throw RpcException.invalidParams('$context field "$key" must be a positive integer.');
  }
  return raw;
}

double? _optionalPositiveDouble(Map<String, Object?> map, String key, {required String context}) {
  final Object? raw = map[key];
  if (raw == null) {
    return null;
  }
  if (raw is! num || !raw.isFinite || raw <= 0) {
    throw RpcException.invalidParams('$context field "$key" must be a positive finite number.');
  }
  return raw.toDouble();
}

String? _optionalBoundedString(Map<String, Object?> map, String key, {required String context}) {
  final Object? raw = map[key];
  if (raw == null) {
    return null;
  }
  if (raw is! String) {
    throw RpcException.invalidParams('$context field "$key" must be a string.');
  }
  if (raw.length > PreviewSelectionStore.kMaxStringLength) {
    throw RpcException.invalidParams(
      '$context field "$key" exceeds maximum length of ${PreviewSelectionStore.kMaxStringLength}.',
    );
  }
  return raw;
}

String? _optionalNonEmptyBoundedString(
  Map<String, Object?> map,
  String key, {
  required String context,
}) {
  final String? value = _optionalBoundedString(map, key, context: context);
  if (value == null) {
    return null;
  }
  if (value.isEmpty) {
    throw RpcException.invalidParams('$context field "$key" must be non-empty.');
  }
  return value;
}

String _requireNonEmptyBoundedString(
  Map<String, Object?> map,
  String key, {
  required String context,
}) {
  final String? value = _optionalNonEmptyBoundedString(map, key, context: context);
  if (value == null) {
    throw RpcException.invalidParams('$context requires field "$key".');
  }
  return value;
}

String? _optionalBrightness(Map<String, Object?> map, String key, {required String context}) {
  final Object? raw = map[key];
  if (raw == null) {
    return null;
  }
  return switch (raw) {
    _kLightBrightness => _kLightBrightness,
    _kDarkBrightness => _kDarkBrightness,
    _ => throw RpcException.invalidParams(
      '$context field "$key" must be "$_kLightBrightness" or "$_kDarkBrightness".',
    ),
  };
}

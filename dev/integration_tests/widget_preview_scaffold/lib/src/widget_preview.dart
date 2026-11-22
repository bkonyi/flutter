// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert' show json;

import 'package:dtd/dtd.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';
import 'package:json_rpc_2/json_rpc_2.dart';

const _kBrightnessKey = 'brightness';
const _kColumnKey = 'column';
const _kDiagnosticsKey = 'diagnostics';
const _kErrorMessageKey = 'errorMessage';
const _kFunctionNameKey = 'functionName';
const _kGroupKey = 'group';
const _kHasErrorKey = 'hasError';
const _kHasErrorsKey = 'hasErrors';
const _kHeightKey = 'height';
const _kHorizontalAxis = 'horizontal';
const _kIdKey = 'id';
const _kImageBase64Key = 'imageBase64';
const _kLibraryUriKey = 'libraryUri';
const _kLineKey = 'line';
const _kMultiPreviewIndexKey = 'multiPreviewIndex';
const _kNameKey = 'name';
const _kPackageNameKey = 'packageName';
const _kPixelRatioKey = 'pixelRatio';
const _kPreviewIdKey = 'previewId';
const _kPreviewsKey = 'previews';
const _kRenderedHeightKey = 'renderedHeight';
const _kRenderedWidthKey = 'renderedWidth';
const _kScriptUriKey = 'scriptUri';
const _kTextScaleFactorKey = 'textScaleFactor';
const _kTypeKey = 'type';
const _kVerticalAxis = 'vertical';
const _kWidthKey = 'width';

void _expectDtdResponseType(DTDResponse response, String expectedType) {
  if (response.result[_kTypeKey] != expectedType) {
    throw RpcException.invalidParams(
      'Expected $_kTypeKey param to be $expectedType, got: ${response.result[_kTypeKey]}',
    );
  }
}

/// A group of [WidgetPreview] instances sharing the same group name.
class WidgetPreviewGroup {
  const WidgetPreviewGroup({required this.name, required this.previews});

  /// Returns `false` if the group has no previews.
  ///
  /// This can happen if a filter is applied that results in no previews matching
  /// the filter being part of the group.
  bool get hasPreviews => previews.isNotEmpty;

  /// The name of the group, as specified by the 'group' parameter in [Preview].
  final String name;

  /// The set of preview instances which are part of a group with a given [name].
  final List<WidgetPreview> previews;
}

/// Wraps a [Widget], initializing various state and properties to allow for
/// previewing of the [Widget] in the widget previewer.
class WidgetPreview {
  /// Wraps [builder] in a [WidgetPreview] instance that applies some set of
  /// properties.
  const WidgetPreview({
    required this.builder,
    required this.column,
    required this.functionName,
    required this.libraryUri,
    required this.line,
    required this.packageName,
    required this.previewData,
    required this.scriptUri,
    this.defaultLocalizations,
    this.errorMessage,
    this.hasError = false,
    this.multiPreviewIndex,
  });

  @visibleForTesting
  const WidgetPreview.test({
    required this.builder,
    required this.previewData,
    this.column = -1,
    this.defaultLocalizations,
    this.errorMessage,
    this.functionName = '',
    this.hasError = false,
    this.libraryUri = '',
    this.line = -1,
    this.multiPreviewIndex,
    this.packageName = '',
    this.scriptUri = '',
  });

  /// Canonical identifier for this preview instance.
  ///
  /// Uses `'$libraryUri::$functionName'` for single `@Preview` declarations, or
  /// `'$libraryUri::$functionName#$multiPreviewIndex'` for `@MultiPreview`
  /// entries.
  String get id => multiPreviewIndex == null
      ? '$libraryUri::$functionName'
      : '$libraryUri::$functionName#$multiPreviewIndex';

  /// The absolute file:// URI pointing to the script containing this preview.
  ///
  /// This matches the URI format sent by IDEs for active location change events.
  final String scriptUri;

  /// The package: or dart: URI of the library containing this preview.
  final String libraryUri;

  /// The name of the preview function, constructor, or static member.
  final String functionName;

  /// Zero-based index within an expanded [MultiPreview], or `null` for a single
  /// [Preview].
  final int? multiPreviewIndex;

  /// The line at which the Preview annotation was applied.
  final int line;

  /// The column at which the Preview annotation was applied.
  final int column;

  /// The name of the package in which a preview was defined.
  ///
  /// For example, if a preview is defined in 'package:foo/src/bar.dart', this
  /// will have the value 'foo'.
  final String packageName;

  /// Whether this preview failed static analysis or compilation.
  final bool hasError;

  /// Static analysis or compilation error message when [hasError] is `true`.
  final String? errorMessage;

  /// A description to be displayed alongside the preview.
  ///
  /// If not provided, no name will be associated with the preview.
  String? get name => previewData.name;

  /// A callback to build the [Widget] to be rendered in the preview.
  final Widget Function() builder;

  Widget Function() get previewBuilder {
    return switch (previewData) {
      Preview(:final Widget Function(Widget) wrapper) => () => wrapper(
        builder(),
      ),
      _ => builder,
    };
  }

  /// Artificial constraints to be applied to the previewed widget.
  ///
  /// If not provided, the previewed widget will attempt to set its own
  /// constraints.
  ///
  /// If a dimension has a value of `double.infinity`, the previewed widget
  /// will attempt to set its own constraints in the relevant dimension.
  Size? get size => previewData.size;

  /// Finite width constraint from [size], or `null` when unset or infinite.
  double? get finiteWidth => switch (size?.width) {
    final double w when w.isFinite => w,
    _ => null,
  };

  /// Finite height constraint from [size], or `null` when unset or infinite.
  double? get finiteHeight => switch (size?.height) {
    final double h when h.isFinite => h,
    _ => null,
  };

  /// Applies font scaling to text within the [Widget] returned by [builder].
  ///
  /// If not provided, the default text scaling factor provided by [MediaQuery]
  /// will be used.
  double? get textScaleFactor => previewData.textScaleFactor;

  /// Finite [textScaleFactor], or `null` when unset or non-finite.
  double? get finiteTextScaleFactor => switch (textScaleFactor) {
    final double scale when scale.isFinite => scale,
    _ => null,
  };

  /// Material and Cupertino theming data to be applied to the previewed [Widget].
  ///
  /// If not provided, the default theme will be used.
  PreviewThemeData? get theme => previewData.theme?.call();

  /// Sets the initial theme brightness.
  ///
  /// If not provided, the current system default brightness will be used.
  Brightness? get brightness => previewData.brightness;

  /// A callback to return a localization configuration to be applied to the
  /// previewed [Widget].
  ///
  /// Generated previews fall back to an `en_US` default localization
  /// configuration rather than inheriting the host `WidgetsApp` locale, so this
  /// getter is non-null for those previews and [debugFillProperties] will
  /// report those synthesized defaults.
  ///
  /// Note: this must be a reference to a static, public function defined as
  /// either a top-level function or static member in a class.
  PreviewLocalizationsData? get localizations =>
      (previewData.localizations ?? defaultLocalizations)?.call();

  /// Fallback localization callback used when [previewData.localizations] is
  /// `null`.
  final PreviewLocalizationsData Function()? defaultLocalizations;

  final Preview previewData;

  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
      ..add(DiagnosticsProperty<String>('id', id))
      ..add(DiagnosticsProperty<String>('name', name, ifNull: 'not set'))
      ..add(DiagnosticsProperty<String>('group', previewData.group))
      ..add(DiagnosticsProperty<Size>('size', size))
      ..add(DiagnosticsProperty<double>('textScaleFactor', textScaleFactor))
      ..add(DiagnosticsProperty<PreviewThemeData>('theme', theme))
      ..add(DiagnosticsProperty<Brightness>('brightness', brightness))
      ..add(
        DiagnosticsProperty<PreviewLocalizationsData>(
          'localizations',
          localizations,
        ),
      );
  }
}

/// Lifecycle phase in which a [PreviewDiagnostic] was captured.
enum PreviewDiagnosticPhase {
  compile,
  build,
  layout,
  paint;

  static PreviewDiagnosticPhase fromJson(String value) => values.firstWhere(
    (PreviewDiagnosticPhase phase) => phase.name == value,
    orElse: () =>
        throw FormatException('Unknown PreviewDiagnosticPhase: $value'),
  );
}

/// Classification of a [PreviewDiagnostic].
enum PreviewDiagnosticKind {
  compileError('compile_error'),
  exception('exception'),
  unconstrained('unconstrained'),
  overflow('overflow'),
  zeroSize('zero_size'),
  textTruncated('text_truncated'),
  smallTapTarget('small_tap_target'),
  pendingFrame('pending_frame');

  const PreviewDiagnosticKind(this.wireValue);

  final String wireValue;

  static PreviewDiagnosticKind fromJson(String value) => values.firstWhere(
    (PreviewDiagnosticKind kind) => kind.wireValue == value,
    orElse: () =>
        throw FormatException('Unknown PreviewDiagnosticKind: $value'),
  );
}

/// Severity level of a [PreviewDiagnostic].
enum PreviewDiagnosticSeverity {
  error('error'),
  warning('warning');

  const PreviewDiagnosticSeverity(this.wireValue);

  final String wireValue;

  static PreviewDiagnosticSeverity fromJson(String value) => values.firstWhere(
    (PreviewDiagnosticSeverity s) => s.wireValue == value,
    orElse: () =>
        throw FormatException('Unknown PreviewDiagnosticSeverity: $value'),
  );
}

/// Structured diagnostic captured while compiling, building, laying out, or
/// painting a widget preview.
@immutable
class PreviewDiagnostic {
  const PreviewDiagnostic({
    required this.kind,
    required this.phase,
    required this.summary,
    this.overflowAxis,
    this.overflowPixels,
    this.overflowSide,
    this.severity = .error,
    this.targetType,
  });

  static const kKind = 'kind';
  static const kOverflowAxis = 'overflowAxis';
  static const kOverflowPixels = 'overflowPixels';
  static const kOverflowSide = 'overflowSide';
  static const kPhase = 'phase';
  static const kSeverity = 'severity';
  static const kSummary = 'summary';
  static const kTargetType = 'targetType';

  static final _kOverflowHeaderPattern = RegExp(
    r'([A-Za-z0-9_]+) overflowed by ',
    caseSensitive: false,
  );
  static final _kOverflowSidePattern = RegExp(
    r'([0-9.]+(?:e[+-]?[0-9]+)?) pixels on the (right|left|bottom|top|start|end)',
    caseSensitive: false,
  );

  final PreviewDiagnosticKind kind;
  final String? overflowAxis;
  final double? overflowPixels;
  final String? overflowSide;
  final PreviewDiagnosticPhase phase;
  final PreviewDiagnosticSeverity severity;
  final String summary;
  final String? targetType;

  /// Extracts structured [PreviewDiagnostic]s from a `RenderFlex` (or other
  /// `DebugOverflowIndicatorMixin`) overflow error message, or returns an empty
  /// list if [message] is not an overflow report.
  static List<PreviewDiagnostic> parseOverflows(
    String message, {
    String? summary,
  }) {
    final Match? headerMatch = _kOverflowHeaderPattern.firstMatch(message);
    if (headerMatch == null) {
      return const <PreviewDiagnostic>[];
    }
    final String targetType = headerMatch.group(1)!;
    final String resolvedSummary = summary ?? message;
    return <PreviewDiagnostic>[
      for (final RegExpMatch match in _kOverflowSidePattern.allMatches(message))
        PreviewDiagnostic(
          kind: .overflow,
          overflowAxis: switch (match.group(2)!.toLowerCase()) {
            'top' || 'bottom' => _kVerticalAxis,
            _ => _kHorizontalAxis,
          },
          overflowPixels: double.tryParse(match.group(1)!),
          overflowSide: match.group(2)!.toLowerCase(),
          phase: .paint,
          summary: resolvedSummary,
          targetType: targetType,
        ),
    ];
  }

  Object get _equalityKey => (
    kind,
    overflowAxis,
    overflowPixels,
    overflowSide,
    phase,
    severity,
    summary,
    targetType,
  );

  @override
  int get hashCode => _equalityKey.hashCode;

  @override
  bool operator ==(Object other) =>
      other is PreviewDiagnostic && _equalityKey == other._equalityKey;

  Map<String, Object?> toJson() => <String, Object?>{
    kPhase: phase.name,
    kKind: kind.wireValue,
    kSeverity: severity.wireValue,
    kSummary: summary,
    kOverflowPixels: ?overflowPixels,
    kOverflowSide: ?overflowSide,
    kOverflowAxis: ?overflowAxis,
    kTargetType: ?targetType,
  };

  @override
  String toString() => json.encode(toJson());

  static PreviewDiagnostic fromJson(Map<String, Object?> json) =>
      PreviewDiagnostic(
        kind: PreviewDiagnosticKind.fromJson(json[kKind]! as String),
        overflowAxis: json[kOverflowAxis] as String?,
        overflowPixels: (json[kOverflowPixels] as num?)?.toDouble(),
        overflowSide: json[kOverflowSide] as String?,
        phase: PreviewDiagnosticPhase.fromJson(json[kPhase]! as String),
        severity: switch (json[kSeverity]) {
          final String value => PreviewDiagnosticSeverity.fromJson(value),
          _ => .error,
        },
        summary: json[kSummary]! as String,
        targetType: json[kTargetType] as String?,
      );
}

/// Metadata and error summary for a single discovered widget preview instance.
extension type const PreviewEntry.fromJson(Map<String, Object?> _json) {
  factory PreviewEntry({
    required int column,
    required String functionName,
    required String group,
    required bool hasError,
    required String id,
    required String libraryUri,
    required int line,
    required String packageName,
    required String scriptUri,
    String? brightness,
    String? errorMessage,
    double? height,
    int? multiPreviewIndex,
    String? name,
    double? textScaleFactor,
    double? width,
  }) => PreviewEntry.fromJson(<String, Object?>{
    _kIdKey: id,
    _kLibraryUriKey: libraryUri,
    _kScriptUriKey: scriptUri,
    _kPackageNameKey: packageName,
    _kFunctionNameKey: functionName,
    _kMultiPreviewIndexKey: multiPreviewIndex,
    _kLineKey: line,
    _kColumnKey: column,
    _kGroupKey: group,
    _kNameKey: name,
    _kWidthKey: width,
    _kHeightKey: height,
    _kTextScaleFactorKey: textScaleFactor,
    _kBrightnessKey: brightness,
    _kHasErrorKey: hasError,
    _kErrorMessageKey: errorMessage,
  });

  String? get brightness => _json[_kBrightnessKey] as String?;
  int get column => (_json[_kColumnKey]! as num).toInt();
  String? get errorMessage => _json[_kErrorMessageKey] as String?;
  String get functionName => _json[_kFunctionNameKey]! as String;
  String get group => _json[_kGroupKey]! as String;
  bool get hasError => _json[_kHasErrorKey]! as bool;
  double? get height => (_json[_kHeightKey] as num?)?.toDouble();
  String get id => _json[_kIdKey]! as String;
  String get libraryUri => _json[_kLibraryUriKey]! as String;
  int get line => (_json[_kLineKey]! as num).toInt();
  int? get multiPreviewIndex =>
      (_json[_kMultiPreviewIndexKey] as num?)?.toInt();
  String? get name => _json[_kNameKey] as String?;
  String get packageName => _json[_kPackageNameKey]! as String;
  String get scriptUri => _json[_kScriptUriKey]! as String;
  double? get textScaleFactor =>
      (_json[_kTextScaleFactorKey] as num?)?.toDouble();
  double? get width => (_json[_kWidthKey] as num?)?.toDouble();

  Map<String, Object?> toJson() => _json;
}

/// DTD response containing the list of widget previews in the scaffold.
extension type const PreviewListResponse.fromJson(Map<String, Object?> _json) {
  factory PreviewListResponse({required List<PreviewEntry> previews}) =>
      PreviewListResponse.fromJson(<String, Object?>{
        _kTypeKey: kTypeName,
        _kPreviewsKey: <Map<String, Object?>>[
          for (final PreviewEntry preview in previews) preview.toJson(),
        ],
      });

  factory PreviewListResponse.fromDTDResponse(DTDResponse response) {
    _expectDtdResponseType(response, kTypeName);
    return PreviewListResponse.fromJson(response.result);
  }

  static const empty = PreviewListResponse.fromJson(<String, Object?>{
    _kTypeKey: kTypeName,
    _kPreviewsKey: <Map<String, Object?>>[],
  });
  static const kTypeName = 'PreviewListResponse';

  List<PreviewEntry> get previews => <PreviewEntry>[
    for (final Object? item in _json[_kPreviewsKey]! as List<Object?>)
      PreviewEntry.fromJson(item! as Map<String, Object?>),
  ];

  Map<String, Object?> toJson() => _json;
}

/// Parameters for capturing an off-screen snapshot and diagnostics of a single
/// widget preview.
@immutable
class PreviewCaptureRequest {
  const PreviewCaptureRequest({
    required this.previewId,
    this.brightness,
    this.height,
    this.includeImage = true,
    this.pixelRatio,
    this.pumpMs,
    this.textScaleFactor,
    this.width,
  });

  final Brightness? brightness;
  final double? height;
  final bool includeImage;
  final double? pixelRatio;
  final String previewId;
  final int? pumpMs;
  final double? textScaleFactor;
  final double? width;
}

/// DTD response returned by `PreviewScaffold.capturePreview` containing the
/// rendered dimensions, optional base64-encoded PNG snapshot, and structured
/// diagnostics for a single widget preview.
extension type const CapturePreviewResponse.fromJson(
  Map<String, Object?> _json
) {
  factory CapturePreviewResponse({
    required List<PreviewDiagnostic> diagnostics,
    required bool hasErrors,
    required double pixelRatio,
    required String previewId,
    required double renderedHeight,
    required double renderedWidth,
    String? imageBase64,
    String? name,
  }) => CapturePreviewResponse.fromJson(<String, Object?>{
    _kTypeKey: kTypeName,
    _kPreviewIdKey: previewId,
    _kNameKey: name,
    _kRenderedWidthKey: renderedWidth,
    _kRenderedHeightKey: renderedHeight,
    _kPixelRatioKey: pixelRatio,
    _kImageBase64Key: imageBase64,
    _kHasErrorsKey: hasErrors,
    _kDiagnosticsKey: <Map<String, Object?>>[
      for (final PreviewDiagnostic diagnostic in diagnostics)
        diagnostic.toJson(),
    ],
  });

  factory CapturePreviewResponse.fromDTDResponse(DTDResponse response) {
    _expectDtdResponseType(response, kTypeName);
    return CapturePreviewResponse.fromJson(response.result);
  }

  static const kTypeName = 'CapturePreviewResponse';

  List<PreviewDiagnostic> get diagnostics => <PreviewDiagnostic>[
    for (final Object? item in _json[_kDiagnosticsKey]! as List<Object?>)
      PreviewDiagnostic.fromJson(item! as Map<String, Object?>),
  ];
  bool get hasErrors => _json[_kHasErrorsKey]! as bool;
  String? get imageBase64 => _json[_kImageBase64Key] as String?;
  String? get name => _json[_kNameKey] as String?;
  double get pixelRatio => (_json[_kPixelRatioKey]! as num).toDouble();
  String get previewId => _json[_kPreviewIdKey]! as String;
  double get renderedHeight => (_json[_kRenderedHeightKey]! as num).toDouble();
  double get renderedWidth => (_json[_kRenderedWidthKey]! as num).toDouble();

  Map<String, Object?> toJson() => _json;
}

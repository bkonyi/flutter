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
  /// Static analysis or incremental compilation error.
  compile,

  /// Exception thrown during widget build.
  build,

  /// Exception or layout audit warning during render-object layout.
  layout,

  /// Overflow or exception raised during painting.
  paint;

  /// Parses [value] into a [PreviewDiagnosticPhase], throwing a
  /// [FormatException] for unrecognized wire values.
  static PreviewDiagnosticPhase fromJson(String value) => values.firstWhere(
    (PreviewDiagnosticPhase phase) => phase.name == value,
    orElse: () =>
        throw FormatException('Unknown PreviewDiagnosticPhase: $value'),
  );
}

/// Classification of a [PreviewDiagnostic].
enum PreviewDiagnosticKind {
  /// Analyzer or compiler error preventing preview rendering.
  compileError('compile_error'),

  /// Unhandled Dart or Flutter framework exception.
  exception('exception'),

  /// Preview widget attempted to expand infinitely under unbounded constraints.
  unconstrained('unconstrained'),

  /// `RenderFlex` or render-box paint overflow.
  overflow('overflow'),

  /// Preview rendered with zero width or zero height.
  zeroSize('zero_size'),

  /// `RenderParagraph` exceeded `maxLines` and truncated text.
  textTruncated('text_truncated'),

  /// Interactive touch target smaller than 48x48dp on mobile platforms.
  smallTapTarget('small_tap_target'),

  /// Additional layout/paint frame remained scheduled when capture settled.
  pendingFrame('pending_frame');

  const PreviewDiagnosticKind(this.wireValue);

  /// Snake-case wire representation serialized in JSON responses.
  final String wireValue;

  /// Parses [value] from its [wireValue], throwing a [FormatException] for
  /// unrecognized values.
  static PreviewDiagnosticKind fromJson(String value) => values.firstWhere(
    (PreviewDiagnosticKind kind) => kind.wireValue == value,
    orElse: () =>
        throw FormatException('Unknown PreviewDiagnosticKind: $value'),
  );
}

/// Severity level of a [PreviewDiagnostic].
enum PreviewDiagnosticSeverity {
  /// Fatal or blocking diagnostic that marks a snapshot as failed.
  error('error'),

  /// Non-blocking layout or accessibility advisory warning.
  warning('warning');

  const PreviewDiagnosticSeverity(this.wireValue);

  /// Wire string serialized in JSON responses.
  final String wireValue;

  /// Parses [value] from its [wireValue], throwing a [FormatException] for
  /// unrecognized values.
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

  /// Classification of the diagnostic.
  final PreviewDiagnosticKind kind;

  /// Overflow axis (`horizontal` or `vertical`) when [kind] is `.overflow`.
  final String? overflowAxis;

  /// Number of overflowing logical pixels when [kind] is `.overflow`.
  final double? overflowPixels;

  /// Overflowing edge (e.g. `right` or `bottom`) when [kind] is `.overflow`.
  final String? overflowSide;

  /// Lifecycle phase in which the diagnostic occurred.
  final PreviewDiagnosticPhase phase;

  /// Severity of the diagnostic (defaults to `.error`).
  final PreviewDiagnosticSeverity severity;

  /// Concise human-readable description of the diagnostic.
  final String summary;

  /// Runtime type name of the offending render object, if known.
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

  /// Configured brightness override (`light` or `dark`), if set.
  String? get brightness => _json[_kBrightnessKey] as String?;

  /// Zero-based source column of the `@Preview` annotation.
  int get column => (_json[_kColumnKey]! as num).toInt();

  /// Analyzer or compilation error summary when [hasError] is `true`.
  String? get errorMessage => _json[_kErrorMessageKey] as String?;

  /// Name of the preview function, constructor, or static member.
  String get functionName => _json[_kFunctionNameKey]! as String;

  /// Group label assigned to this preview.
  String get group => _json[_kGroupKey]! as String;

  /// Whether static analysis or compilation errors prevent rendering.
  bool get hasError => _json[_kHasErrorKey]! as bool;

  /// Explicit preview height in logical pixels, if constrained.
  double? get height => (_json[_kHeightKey] as num?)?.toDouble();

  /// Canonical preview identifier (`<libraryUri>::<functionName>[#<index>]`).
  String get id => _json[_kIdKey]! as String;

  /// `package:` or `dart:` URI of the declaring library.
  String get libraryUri => _json[_kLibraryUriKey]! as String;

  /// Zero-based source line of the `@Preview` annotation.
  int get line => (_json[_kLineKey]! as num).toInt();

  /// Zero-based index within an expanded `@MultiPreview`, or `null`.
  int? get multiPreviewIndex =>
      (_json[_kMultiPreviewIndexKey] as num?)?.toInt();

  /// Optional display name specified on the `@Preview` annotation.
  String? get name => _json[_kNameKey] as String?;

  /// Name of the Dart package declaring this preview.
  String get packageName => _json[_kPackageNameKey]! as String;

  /// `file://` URI of the source file declaring this preview.
  String get scriptUri => _json[_kScriptUriKey]! as String;

  /// Explicit text scale factor override, if configured.
  double? get textScaleFactor =>
      (_json[_kTextScaleFactorKey] as num?)?.toDouble();

  /// Explicit preview width in logical pixels, if constrained.
  double? get width => (_json[_kWidthKey] as num?)?.toDouble();

  /// Returns the underlying JSON-serializable map representation.
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

  /// Empty [PreviewListResponse] with no preview entries.
  static const empty = PreviewListResponse.fromJson(<String, Object?>{
    _kTypeKey: kTypeName,
    _kPreviewsKey: <Map<String, Object?>>[],
  });

  /// DTD response type discriminator for [PreviewListResponse].
  static const kTypeName = 'PreviewListResponse';

  /// All discovered widget previews included in this response.
  List<PreviewEntry> get previews => <PreviewEntry>[
    for (final Object? item in _json[_kPreviewsKey]! as List<Object?>)
      PreviewEntry.fromJson(item! as Map<String, Object?>),
  ];

  /// Returns the underlying JSON-serializable map representation.
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

  /// Optional theme brightness override applied during capture.
  final Brightness? brightness;

  /// Optional viewport height override in logical pixels.
  final double? height;

  /// Whether to rasterize and return a base64-encoded PNG image.
  final bool includeImage;

  /// Optional device pixel ratio override used during rasterization.
  final double? pixelRatio;

  /// Canonical preview ID or unique shorthand preview name to capture.
  final String previewId;

  /// Optional settle delay in milliseconds before capturing the final frame.
  final int? pumpMs;

  /// Optional text scale factor override applied during capture.
  final double? textScaleFactor;

  /// Optional viewport width override in logical pixels.
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

  /// DTD response type discriminator for [CapturePreviewResponse].
  static const kTypeName = 'CapturePreviewResponse';

  /// Structured compile, build, layout, and paint diagnostics recorded while
  /// capturing this preview.
  List<PreviewDiagnostic> get diagnostics => <PreviewDiagnostic>[
    for (final Object? item in _json[_kDiagnosticsKey]! as List<Object?>)
      PreviewDiagnostic.fromJson(item! as Map<String, Object?>),
  ];

  /// Whether any error-severity diagnostic was recorded during capture.
  bool get hasErrors => _json[_kHasErrorsKey]! as bool;

  /// Base64-encoded PNG image bytes, or `null` when image capture was omitted.
  String? get imageBase64 => _json[_kImageBase64Key] as String?;

  /// Display name of the captured preview, if configured.
  String? get name => _json[_kNameKey] as String?;

  /// Device pixel ratio used to rasterize the captured snapshot.
  double get pixelRatio => (_json[_kPixelRatioKey]! as num).toDouble();

  /// Canonical identifier of the captured preview.
  String get previewId => _json[_kPreviewIdKey]! as String;

  /// Rendered logical height of the captured preview surface.
  double get renderedHeight => (_json[_kRenderedHeightKey]! as num).toDouble();

  /// Rendered logical width of the captured preview surface.
  double get renderedWidth => (_json[_kRenderedWidthKey]! as num).toDouble();

  /// Returns the underlying JSON-serializable map representation.
  Map<String, Object?> toJson() => _json;
}

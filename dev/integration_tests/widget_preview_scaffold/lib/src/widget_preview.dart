// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert' show json;

import 'package:dtd/dtd.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';
import 'package:json_rpc_2/json_rpc_2.dart';

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
    if (previewData.wrapper == null) {
      return builder;
    }
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

  /// Applies font scaling to text within the [Widget] returned by [builder].
  ///
  /// If not provided, the default text scaling factor provided by [MediaQuery]
  /// will be used.
  double? get textScaleFactor => previewData.textScaleFactor;

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

  static PreviewDiagnosticPhase fromJson(String value) => switch (value) {
    'compile' => .compile,
    'build' => .build,
    'layout' => .layout,
    'paint' => .paint,
    _ => throw FormatException('Unknown PreviewDiagnosticPhase: $value'),
  };
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

  static PreviewDiagnosticKind fromJson(String value) => switch (value) {
    'compile_error' => .compileError,
    'exception' => .exception,
    'unconstrained' => .unconstrained,
    'overflow' => .overflow,
    'zero_size' => .zeroSize,
    'text_truncated' => .textTruncated,
    'small_tap_target' => .smallTapTarget,
    'pending_frame' => .pendingFrame,
    _ => throw FormatException('Unknown PreviewDiagnosticKind: $value'),
  };
}

/// Severity level of a [PreviewDiagnostic].
enum PreviewDiagnosticSeverity {
  error('error'),
  warning('warning');

  const PreviewDiagnosticSeverity(this.wireValue);

  final String wireValue;

  static PreviewDiagnosticSeverity fromJson(String value) => switch (value) {
    'error' => .error,
    'warning' => .warning,
    _ => throw FormatException('Unknown PreviewDiagnosticSeverity: $value'),
  };
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
    final Iterable<RegExpMatch> sideMatches = _kOverflowSidePattern.allMatches(
      message,
    );
    if (sideMatches.isEmpty) {
      return const <PreviewDiagnostic>[];
    }
    final String resolvedSummary = summary ?? message;
    return <PreviewDiagnostic>[
      for (final RegExpMatch match in sideMatches)
        _overflowFromMatch(
          match: match,
          summary: resolvedSummary,
          targetType: targetType,
        ),
    ];
  }

  static PreviewDiagnostic _overflowFromMatch({
    required RegExpMatch match,
    required String summary,
    required String targetType,
  }) {
    final String side = match.group(2)!.toLowerCase();
    final String axis = switch (side) {
      'top' || 'bottom' => 'vertical',
      _ => 'horizontal',
    };
    return PreviewDiagnostic(
      kind: .overflow,
      overflowAxis: axis,
      overflowPixels: double.tryParse(match.group(1)!),
      overflowSide: side,
      phase: .paint,
      summary: summary,
      targetType: targetType,
    );
  }

  @override
  int get hashCode => Object.hash(
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
  bool operator ==(Object other) {
    return other is PreviewDiagnostic &&
        other.runtimeType == PreviewDiagnostic &&
        kind == other.kind &&
        overflowAxis == other.overflowAxis &&
        overflowPixels == other.overflowPixels &&
        overflowSide == other.overflowSide &&
        phase == other.phase &&
        severity == other.severity &&
        summary == other.summary &&
        targetType == other.targetType;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      kPhase: phase.name,
      kKind: kind.wireValue,
      kSeverity: severity.wireValue,
      kSummary: summary,
      kOverflowPixels: ?overflowPixels,
      kOverflowSide: ?overflowSide,
      kOverflowAxis: ?overflowAxis,
      kTargetType: ?targetType,
    };
  }

  @override
  String toString() => json.encode(toJson());

  static PreviewDiagnostic fromJson(Map<String, Object?> json) {
    return PreviewDiagnostic(
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
}

/// Metadata and error summary for a single discovered widget preview instance.
@immutable
class PreviewEntry {
  const PreviewEntry({
    required this.column,
    required this.functionName,
    required this.group,
    required this.hasError,
    required this.id,
    required this.libraryUri,
    required this.line,
    required this.packageName,
    required this.scriptUri,
    this.brightness,
    this.errorMessage,
    this.height,
    this.multiPreviewIndex,
    this.name,
    this.textScaleFactor,
    this.width,
  });

  static const kBrightness = 'brightness';
  static const kColumn = 'column';
  static const kErrorMessage = 'errorMessage';
  static const kFunctionName = 'functionName';
  static const kGroup = 'group';
  static const kHasError = 'hasError';
  static const kHeight = 'height';
  static const kId = 'id';
  static const kLibraryUri = 'libraryUri';
  static const kLine = 'line';
  static const kMultiPreviewIndex = 'multiPreviewIndex';
  static const kName = 'name';
  static const kPackageName = 'packageName';
  static const kScriptUri = 'scriptUri';
  static const kTextScaleFactor = 'textScaleFactor';
  static const kWidth = 'width';

  final String? brightness;
  final int column;
  final String? errorMessage;
  final String functionName;
  final String group;
  final bool hasError;
  final double? height;
  final String id;
  final String libraryUri;
  final int line;
  final int? multiPreviewIndex;
  final String? name;
  final String packageName;
  final String scriptUri;
  final double? textScaleFactor;
  final double? width;

  @override
  int get hashCode => Object.hash(
    brightness,
    column,
    errorMessage,
    functionName,
    group,
    hasError,
    height,
    id,
    libraryUri,
    line,
    multiPreviewIndex,
    name,
    packageName,
    scriptUri,
    textScaleFactor,
    width,
  );

  @override
  bool operator ==(Object other) {
    return other is PreviewEntry &&
        other.runtimeType == PreviewEntry &&
        brightness == other.brightness &&
        column == other.column &&
        errorMessage == other.errorMessage &&
        functionName == other.functionName &&
        group == other.group &&
        hasError == other.hasError &&
        height == other.height &&
        id == other.id &&
        libraryUri == other.libraryUri &&
        line == other.line &&
        multiPreviewIndex == other.multiPreviewIndex &&
        name == other.name &&
        packageName == other.packageName &&
        scriptUri == other.scriptUri &&
        textScaleFactor == other.textScaleFactor &&
        width == other.width;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      kId: id,
      kLibraryUri: libraryUri,
      kScriptUri: scriptUri,
      kPackageName: packageName,
      kFunctionName: functionName,
      kMultiPreviewIndex: multiPreviewIndex,
      kLine: line,
      kColumn: column,
      kGroup: group,
      kName: name,
      kWidth: width,
      kHeight: height,
      kTextScaleFactor: textScaleFactor,
      kBrightness: brightness,
      kHasError: hasError,
      kErrorMessage: errorMessage,
    };
  }

  @override
  String toString() => json.encode(toJson());

  static PreviewEntry fromJson(Map<String, Object?> json) {
    return PreviewEntry(
      brightness: json[kBrightness] as String?,
      column: (json[kColumn]! as num).toInt(),
      errorMessage: json[kErrorMessage] as String?,
      functionName: json[kFunctionName]! as String,
      group: json[kGroup]! as String,
      hasError: json[kHasError]! as bool,
      height: (json[kHeight] as num?)?.toDouble(),
      id: json[kId]! as String,
      libraryUri: json[kLibraryUri]! as String,
      line: (json[kLine]! as num).toInt(),
      multiPreviewIndex: (json[kMultiPreviewIndex] as num?)?.toInt(),
      name: json[kName] as String?,
      packageName: json[kPackageName]! as String,
      scriptUri: json[kScriptUri]! as String,
      textScaleFactor: (json[kTextScaleFactor] as num?)?.toDouble(),
      width: (json[kWidth] as num?)?.toDouble(),
    );
  }
}

/// DTD response containing the list of widget previews in the scaffold.
@immutable
class PreviewListResponse {
  const PreviewListResponse({required this.previews});

  factory PreviewListResponse.fromDTDResponse(DTDResponse response) {
    if (response.result[kType] != kTypeName) {
      throw RpcException.invalidParams(
        'Expected $kType param to be $kTypeName, got: ${response.result[kType]}',
      );
    }
    return PreviewListResponse.fromJson(response.result);
  }

  static const kPreviews = 'previews';
  static const kType = 'type';
  static const kTypeName = 'PreviewListResponse';

  final List<PreviewEntry> previews;

  @override
  int get hashCode => Object.hashAll(previews);

  @override
  bool operator ==(Object other) {
    return other is PreviewListResponse &&
        other.runtimeType == PreviewListResponse &&
        listEquals(previews, other.previews);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      kType: kTypeName,
      kPreviews: <Map<String, Object?>>[
        for (final PreviewEntry preview in previews) preview.toJson(),
      ],
    };
  }

  @override
  String toString() => json.encode(toJson());

  static PreviewListResponse fromJson(Map<String, Object?> json) {
    final previewsJson = json[kPreviews]! as List<Object?>;
    return PreviewListResponse(
      previews: <PreviewEntry>[
        for (final Object? item in previewsJson)
          PreviewEntry.fromJson(item! as Map<String, Object?>),
      ],
    );
  }
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
@immutable
class CapturePreviewResponse {
  const CapturePreviewResponse({
    required this.diagnostics,
    required this.hasErrors,
    required this.pixelRatio,
    required this.previewId,
    required this.renderedHeight,
    required this.renderedWidth,
    this.imageBase64,
    this.name,
  });

  factory CapturePreviewResponse.fromDTDResponse(DTDResponse response) {
    if (response.result[kType] != kTypeName) {
      throw RpcException.invalidParams(
        'Expected $kType param to be $kTypeName, got: ${response.result[kType]}',
      );
    }
    return CapturePreviewResponse.fromJson(response.result);
  }

  static const kDiagnostics = 'diagnostics';
  static const kHasErrors = 'hasErrors';
  static const kImageBase64 = 'imageBase64';
  static const kName = 'name';
  static const kPixelRatio = 'pixelRatio';
  static const kPreviewId = 'previewId';
  static const kRenderedHeight = 'renderedHeight';
  static const kRenderedWidth = 'renderedWidth';
  static const kType = 'type';
  static const kTypeName = 'CapturePreviewResponse';

  final List<PreviewDiagnostic> diagnostics;
  final bool hasErrors;
  final String? imageBase64;
  final String? name;
  final double pixelRatio;
  final String previewId;
  final double renderedHeight;
  final double renderedWidth;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(diagnostics),
    hasErrors,
    imageBase64,
    name,
    pixelRatio,
    previewId,
    renderedHeight,
    renderedWidth,
  );

  @override
  bool operator ==(Object other) {
    return other is CapturePreviewResponse &&
        other.runtimeType == CapturePreviewResponse &&
        listEquals(diagnostics, other.diagnostics) &&
        hasErrors == other.hasErrors &&
        imageBase64 == other.imageBase64 &&
        name == other.name &&
        pixelRatio == other.pixelRatio &&
        previewId == other.previewId &&
        renderedHeight == other.renderedHeight &&
        renderedWidth == other.renderedWidth;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      kType: kTypeName,
      kPreviewId: previewId,
      kName: name,
      kRenderedWidth: renderedWidth,
      kRenderedHeight: renderedHeight,
      kPixelRatio: pixelRatio,
      kImageBase64: imageBase64,
      kHasErrors: hasErrors,
      kDiagnostics: <Map<String, Object?>>[
        for (final PreviewDiagnostic diagnostic in diagnostics)
          diagnostic.toJson(),
      ],
    };
  }

  @override
  String toString() => json.encode(toJson());

  static CapturePreviewResponse fromJson(Map<String, Object?> json) {
    final diagnosticsJson = json[kDiagnostics]! as List<Object?>;
    return CapturePreviewResponse(
      diagnostics: <PreviewDiagnostic>[
        for (final Object? item in diagnosticsJson)
          PreviewDiagnostic.fromJson(item! as Map<String, Object?>),
      ],
      hasErrors: json[kHasErrors]! as bool,
      imageBase64: json[kImageBase64] as String?,
      name: json[kName] as String?,
      pixelRatio: (json[kPixelRatio]! as num).toDouble(),
      previewId: json[kPreviewId]! as String,
      renderedHeight: (json[kRenderedHeight]! as num).toDouble(),
      renderedWidth: (json[kRenderedWidth]! as num).toDouble(),
    );
  }
}

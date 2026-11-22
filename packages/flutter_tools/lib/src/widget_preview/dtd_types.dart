// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:collection/collection.dart';
import 'package:dtd/dtd.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:meta/meta.dart';

import '../convert.dart';

const _kTypeKey = 'type';
const _deepEquality = DeepCollectionEquality();

void _expectDtdResponseType(DTDResponse response, String expectedType) {
  if (response.result[_kTypeKey] != expectedType) {
    throw RpcException.invalidParams(
      'Expected $_kTypeKey param to be $expectedType, got: ${response.result[_kTypeKey]}',
    );
  }
}

@immutable
abstract mixin class _JsonValue {
  const _JsonValue();

  Map<String, Object?> toJson();

  @override
  bool operator ==(Object other) =>
      other is _JsonValue &&
      other.runtimeType == runtimeType &&
      _deepEquality.equals(toJson(), other.toJson());

  @override
  int get hashCode => Object.hash(runtimeType, _deepEquality.hash(toJson()));

  @override
  String toString() => json.encode(toJson());
}

/// The set of widget previews defined in a script of an analyzed Flutter
/// project.
@immutable
class FlutterWidgetPreviews with _JsonValue {
  const FlutterWidgetPreviews({
    required this.namespaces,
    required this.previews,
    required this.scriptUris,
  });

  static const _kNamespaces = 'namespaces';
  static const _kPreviews = 'previews';
  static const _kScriptUris = 'scriptUris';

  /// A set of library URIs and the prefixes used for types in
  /// "previewAnnotation" sources.
  final Map<String, String> namespaces;

  /// The current set of previews in the script.
  final List<FlutterWidgetPreviewDetails> previews;

  /// The URI for the updated script.
  final List<Uri> scriptUris;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    _kNamespaces: namespaces,
    _kPreviews: <Map<String, Object?>>[for (final item in previews) item.toJson()],
    _kScriptUris: <String>[for (final uri in scriptUris) uri.toString()],
  };

  static FlutterWidgetPreviews fromJson(Map<String, Object?> json) => FlutterWidgetPreviews(
    namespaces: (json[_kNamespaces]! as Map<Object?, Object?>).map(
      (Object? k, Object? v) => MapEntry<String, String>(k! as String, v! as String),
    ),
    previews: <FlutterWidgetPreviewDetails>[
      for (final Object? item in json[_kPreviews]! as List<Object?>)
        FlutterWidgetPreviewDetails.fromJson(item! as Map<String, Object?>),
    ],
    scriptUris: <Uri>[
      for (final Object? item in json[_kScriptUris]! as List<Object?>) Uri.parse(item! as String),
    ],
  );
}

/// A representation of a widget preview declaration containing all information
/// needed to import the preview into the widget previewer.
@immutable
class FlutterWidgetPreviewDetails with _JsonValue {
  const FlutterWidgetPreviewDetails({
    required this.dependencyHasErrors,
    required this.functionName,
    required this.hasError,
    required this.isBuilder,
    required this.isMultiPreview,
    required this.libraryUri,
    required this.position,
    required this.previewAnnotation,
    required this.scriptUri,
    this.packageName,
  });

  static const _kDependencyHasErrors = 'dependencyHasErrors';
  static const _kFunctionName = 'functionName';
  static const _kHasError = 'hasError';
  static const _kIsBuilder = 'isBuilder';
  static const _kIsMultiPreview = 'isMultiPreview';
  static const _kLibraryUri = 'libraryUri';
  static const _kPackageName = 'packageName';
  static const _kPosition = 'position';
  static const _kPreviewAnnotation = 'previewAnnotation';
  static const _kScriptUri = 'scriptUri';

  /// The name of the function returning the preview.
  final String functionName;

  /// Set to true if there is an error that will prevent this preview from being
  /// rendered.
  final bool hasError;

  /// Set to true if there is an error in a dependency that will prevent this preview from being
  /// rendered.
  final bool dependencyHasErrors;

  /// Set to true if the preview function is returning a `WidgetBuilder` instead
  /// of a `Widget`.
  final bool isBuilder;

  /// Set to true if `previewAnnotation` represents a `MultiPreview`.
  final bool isMultiPreview;

  /// The name of the package in which this annotated preview function was
  /// defined.
  ///
  ///  For example, if this preview is defined in "package:foo/src/bar.dart",
  /// this will have the value "foo".
  ///
  /// This should only be null if the preview is defined in a file that's not
  /// part of a Flutter package (e.g., is defined in a test).
  final String? packageName;

  /// The source location at which the Preview annotation was applied.
  final Position position;

  /// An equivalent Dart expression to the applied preview annotation, with
  /// namespaces applied to individual types and constant values evaluated.
  ///
  /// This can be any object which extends `Preview` or `MultiPreview`.
  final String previewAnnotation;

  /// The file:// URI pointing to the script in which the preview is defined.
  final Uri scriptUri;

  /// The unresolved URI pointing to the library in which the preview is
  /// defined. This is either a package: or dart: URI.
  final Uri libraryUri;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    _kFunctionName: functionName,
    _kHasError: hasError,
    _kDependencyHasErrors: dependencyHasErrors,
    _kIsBuilder: isBuilder,
    _kIsMultiPreview: isMultiPreview,
    _kPackageName: packageName,
    _kPosition: position.toJson(),
    _kPreviewAnnotation: previewAnnotation,
    _kScriptUri: scriptUri.toString(),
    _kLibraryUri: libraryUri.toString(),
  };

  static FlutterWidgetPreviewDetails fromJson(Map<String, Object?> json) =>
      FlutterWidgetPreviewDetails(
        dependencyHasErrors: json[_kDependencyHasErrors]! as bool,
        functionName: json[_kFunctionName]! as String,
        hasError: json[_kHasError]! as bool,
        isBuilder: json[_kIsBuilder]! as bool,
        isMultiPreview: json[_kIsMultiPreview]! as bool,
        libraryUri: Uri.parse(json[_kLibraryUri]! as String),
        packageName: json[_kPackageName] as String?,
        position: Position.fromJson(json[_kPosition]! as Map<String, Object?>),
        previewAnnotation: json[_kPreviewAnnotation]! as String,
        scriptUri: Uri.parse(json[_kScriptUri]! as String),
      );
}

@immutable
class Position with _JsonValue {
  const Position({required this.character, required this.line});

  static const _kCharacter = 'character';
  static const _kLine = 'line';

  /// Character offset on a line in a document (zero-based).
  ///
  /// The meaning of this offset is determined by the negotiated
  /// `PositionEncodingKind`.
  ///
  /// If the character value is greater than the line length it defaults back to
  /// the line length.
  final int character;

  /// Line position in a document (zero-based).
  ///
  /// If a line number is greater than the number of lines in a document, it
  /// defaults back to the number of lines in the document. If a line number is
  /// negative, it defaults to 0.
  final int line;

  @override
  Map<String, Object?> toJson() => <String, Object?>{_kCharacter: character, _kLine: line};

  static Position fromJson(Map<String, Object?> json) =>
      Position(character: json[_kCharacter]! as int, line: json[_kLine]! as int);
}

/// Information about the active web preview HTTP server.
extension type WebPreviewUrlResult._(Map<String, Object?> _json) {
  WebPreviewUrlResult({required String host, required int port, required String url})
    : _json = <String, Object?>{kType: kTypeName, kHost: host, kPort: port, kUrl: url};

  factory WebPreviewUrlResult.fromDTDResponse(DTDResponse response) {
    _expectDtdResponseType(response, kTypeName);
    return WebPreviewUrlResult.fromJson(response.result);
  }

  static const String kType = _kTypeKey;
  static const kTypeName = 'WebPreviewUrlResult';
  static const kHost = 'host';
  static const kPort = 'port';
  static const kUrl = 'url';

  /// The host interface (e.g. `127.0.0.1` or `localhost`).
  String get host => _json[kHost]! as String;

  /// The port the web server is listening on.
  int get port => _json[kPort]! as int;

  /// The full HTTP URL string for embedding or browser navigation.
  String get url => _json[kUrl]! as String;

  Map<String, Object?> toJson() => _json;

  static WebPreviewUrlResult fromJson(Map<String, Object?> json) => WebPreviewUrlResult(
    host: json[kHost]! as String,
    port: json[kPort]! as int,
    url: json[kUrl]! as String,
  );
}

/// Metadata describing the active widget preview service and connected endpoints.
extension type PreviewServiceInfo._(Map<String, Object?> _json) {
  PreviewServiceInfo({
    required String dtdUri,
    required String previewService,
    required String projectRoot,
    required bool scaffoldConnected,
    required String scaffoldService,
    required String scaffoldStream,
    String? webPreviewUri,
  }) : _json = <String, Object?>{
         kType: kTypeName,
         kDtdUri: dtdUri,
         kProjectRoot: projectRoot,
         kPreviewService: previewService,
         kScaffoldService: scaffoldService,
         kScaffoldStream: scaffoldStream,
         kWebPreviewUri: webPreviewUri,
         kScaffoldConnected: scaffoldConnected,
       };

  factory PreviewServiceInfo.fromDTDResponse(DTDResponse response) {
    _expectDtdResponseType(response, kTypeName);
    return PreviewServiceInfo.fromJson(response.result);
  }

  static const String kType = _kTypeKey;
  static const kTypeName = 'PreviewServiceInfo';
  static const kDtdUri = 'dtdUri';
  static const kPreviewService = 'previewService';
  static const kProjectRoot = 'projectRoot';
  static const kScaffoldConnected = 'scaffoldConnected';
  static const kScaffoldService = 'scaffoldService';
  static const kScaffoldStream = 'scaffoldStream';
  static const kWebPreviewUri = 'webPreviewUri';

  /// The WebSocket URI of the Dart Tooling Daemon.
  String get dtdUri => _json[kDtdUri]! as String;

  /// The registered DTD service name for the tool widget preview service.
  String get previewService => _json[kPreviewService]! as String;

  /// The absolute path to the root directory of the previewed Flutter project.
  String get projectRoot => _json[kProjectRoot]! as String;

  /// Whether the widget preview scaffold has connected to DTD.
  bool get scaffoldConnected => _json[kScaffoldConnected]! as bool;

  /// The registered DTD service name for the widget preview scaffold.
  String get scaffoldService => _json[kScaffoldService]! as String;

  /// The DTD stream name posted to by the widget preview scaffold.
  String get scaffoldStream => _json[kScaffoldStream]! as String;

  /// The active web preview HTTP URI, if available.
  String? get webPreviewUri => _json[kWebPreviewUri] as String?;

  Map<String, Object?> toJson() => _json;

  static PreviewServiceInfo fromJson(Map<String, Object?> json) => PreviewServiceInfo(
    dtdUri: json[kDtdUri]! as String,
    previewService: json[kPreviewService]! as String,
    projectRoot: json[kProjectRoot]! as String,
    scaffoldConnected: json[kScaffoldConnected]! as bool,
    scaffoldService: json[kScaffoldService]! as String,
    scaffoldStream: json[kScaffoldStream]! as String,
    webPreviewUri: json[kWebPreviewUri] as String?,
  );
}

/// Result of synchronizing on-disk preview edits and reloading the previewer.
@immutable
class SyncPreviewsResponse with _JsonValue {
  const SyncPreviewsResponse({
    required this.compileSuccess,
    required this.errorPreviewCount,
    required this.fullRestart,
    required this.reloaded,
    this.compileError,
  });

  factory SyncPreviewsResponse.fromDTDResponse(DTDResponse response) {
    _expectDtdResponseType(response, kTypeName);
    return SyncPreviewsResponse.fromJson(response.result);
  }

  static const String kType = _kTypeKey;
  static const kTypeName = 'SyncPreviewsResponse';
  static const kCompileError = 'compileError';
  static const kCompileSuccess = 'compileSuccess';
  static const kErrorPreviewCount = 'errorPreviewCount';
  static const kFullRestart = 'fullRestart';
  static const kReloaded = 'reloaded';

  /// Error message if compilation or reload failed, or `null` on success.
  final String? compileError;

  /// Whether incremental compilation and reload succeeded.
  final bool compileSuccess;

  /// Count of previews in the workspace with analyzer errors.
  final int errorPreviewCount;

  /// Whether a full hot restart was performed.
  final bool fullRestart;

  /// Whether the previewer reloaded cleanly.
  final bool reloaded;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    kType: kTypeName,
    kReloaded: reloaded,
    kFullRestart: fullRestart,
    kCompileSuccess: compileSuccess,
    kCompileError: compileError,
    kErrorPreviewCount: errorPreviewCount,
  };

  static SyncPreviewsResponse fromJson(Map<String, Object?> json) => SyncPreviewsResponse(
    compileError: json[kCompileError] as String?,
    compileSuccess: json[kCompileSuccess]! as bool,
    errorPreviewCount: json[kErrorPreviewCount]! as int,
    fullRestart: json[kFullRestart]! as bool,
    reloaded: json[kReloaded]! as bool,
  );
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
    orElse: () => throw FormatException('Unknown PreviewDiagnosticPhase: $value'),
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
    orElse: () => throw FormatException('Unknown PreviewDiagnosticKind: $value'),
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
    (PreviewDiagnosticSeverity severity) => severity.wireValue == value,
    orElse: () => throw FormatException('Unknown PreviewDiagnosticSeverity: $value'),
  );
}

/// Structured diagnostic captured while compiling, building, laying out, or
/// painting a widget preview.
@immutable
class PreviewDiagnostic with _JsonValue {
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

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    kPhase: phase.name,
    kKind: kind.wireValue,
    kSummary: summary,
    kSeverity: severity.wireValue,
    kOverflowPixels: ?overflowPixels,
    kOverflowSide: ?overflowSide,
    kOverflowAxis: ?overflowAxis,
    kTargetType: ?targetType,
  };

  static PreviewDiagnostic fromJson(Map<String, Object?> json) => PreviewDiagnostic(
    kind: PreviewDiagnosticKind.fromJson(json[kKind]! as String),
    overflowAxis: json[kOverflowAxis] as String?,
    overflowPixels: (json[kOverflowPixels] as num?)?.toDouble(),
    overflowSide: json[kOverflowSide] as String?,
    phase: PreviewDiagnosticPhase.fromJson(json[kPhase]! as String),
    severity: switch (json[kSeverity]) {
      final String raw => PreviewDiagnosticSeverity.fromJson(raw),
      _ => .error,
    },
    summary: json[kSummary]! as String,
    targetType: json[kTargetType] as String?,
  );
}

/// Metadata and error summary for a single discovered widget preview instance.
extension type PreviewEntry._(Map<String, Object?> _json) {
  PreviewEntry({
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
  }) : _json = <String, Object?>{
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

  /// Configured brightness override (`light` or `dark`), if set.
  String? get brightness => _json[kBrightness] as String?;

  /// Zero-based source column of the `@Preview` annotation.
  int get column => (_json[kColumn]! as num).toInt();

  /// Analyzer or compilation error summary when [hasError] is `true`.
  String? get errorMessage => _json[kErrorMessage] as String?;

  /// Name of the preview function, constructor, or static member.
  String get functionName => _json[kFunctionName]! as String;

  /// Group label assigned to this preview.
  String get group => _json[kGroup]! as String;

  /// Whether static analysis or compilation errors prevent rendering.
  bool get hasError => _json[kHasError]! as bool;

  /// Explicit preview height in logical pixels, if constrained.
  double? get height => (_json[kHeight] as num?)?.toDouble();

  /// Canonical preview identifier (`<libraryUri>::<functionName>[#<index>]`).
  String get id => _json[kId]! as String;

  /// `package:` or `dart:` URI of the declaring library.
  String get libraryUri => _json[kLibraryUri]! as String;

  /// Zero-based source line of the `@Preview` annotation.
  int get line => (_json[kLine]! as num).toInt();

  /// Zero-based index within an expanded `@MultiPreview`, or `null`.
  int? get multiPreviewIndex => (_json[kMultiPreviewIndex] as num?)?.toInt();

  /// Optional display name specified on the `@Preview` annotation.
  String? get name => _json[kName] as String?;

  /// Name of the Dart package declaring this preview.
  String get packageName => _json[kPackageName]! as String;

  /// `file://` URI of the source file declaring this preview.
  String get scriptUri => _json[kScriptUri]! as String;

  /// Explicit text scale factor override, if configured.
  double? get textScaleFactor => (_json[kTextScaleFactor] as num?)?.toDouble();

  /// Explicit preview width in logical pixels, if constrained.
  double? get width => (_json[kWidth] as num?)?.toDouble();

  /// Returns the underlying JSON-serializable map representation.
  Map<String, Object?> toJson() => _json;

  static PreviewEntry fromJson(Map<String, Object?> json) => PreviewEntry(
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

/// DTD response containing the list of widget previews in the workspace.
extension type PreviewListResponse._(Map<String, Object?> _json) {
  PreviewListResponse({required List<PreviewEntry> previews})
    : _json = <String, Object?>{
        kType: kTypeName,
        kPreviews: List<PreviewEntry>.unmodifiable(previews),
      };

  factory PreviewListResponse.fromDTDResponse(DTDResponse response) {
    _expectDtdResponseType(response, kTypeName);
    return PreviewListResponse.fromJson(response.result);
  }

  static const kPreviews = 'previews';
  static const String kType = _kTypeKey;
  static const kTypeName = 'PreviewListResponse';

  /// All discovered widget previews included in this response.
  List<PreviewEntry> get previews => _json[kPreviews]! as List<PreviewEntry>;

  /// Returns the underlying JSON-serializable map representation.
  Map<String, Object?> toJson() => _json;

  static PreviewListResponse fromJson(Map<String, Object?> json) => PreviewListResponse(
    previews: <PreviewEntry>[
      for (final Object? item in json[kPreviews]! as List<Object?>)
        PreviewEntry.fromJson(item! as Map<String, Object?>),
    ],
  );
}

/// DTD response returned by `PreviewScaffold.capturePreview` containing the
/// rendered dimensions, optional base64-encoded PNG snapshot, and structured
/// diagnostics for a single widget preview.
@immutable
class CapturePreviewResponse with _JsonValue {
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
    _expectDtdResponseType(response, kTypeName);
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
  static const String kType = _kTypeKey;
  static const kTypeName = 'CapturePreviewResponse';

  /// Structured compile, build, layout, and paint diagnostics recorded while
  /// capturing this preview.
  final List<PreviewDiagnostic> diagnostics;

  /// Whether any error-severity diagnostic was recorded during capture.
  final bool hasErrors;

  /// Base64-encoded PNG image bytes, or `null` when image capture was omitted.
  final String? imageBase64;

  /// Display name of the captured preview, if configured.
  final String? name;

  /// Device pixel ratio used to rasterize the captured snapshot.
  final double pixelRatio;

  /// Canonical identifier of the captured preview.
  final String previewId;

  /// Rendered logical height of the captured preview surface.
  final double renderedHeight;

  /// Rendered logical width of the captured preview surface.
  final double renderedWidth;

  /// Returns a copy of this response with [imageBase64] cleared.
  CapturePreviewResponse withoutImage() => CapturePreviewResponse(
    diagnostics: diagnostics,
    hasErrors: hasErrors,
    name: name,
    pixelRatio: pixelRatio,
    previewId: previewId,
    renderedHeight: renderedHeight,
    renderedWidth: renderedWidth,
  );

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    kType: kTypeName,
    kPreviewId: previewId,
    kName: name,
    kRenderedWidth: renderedWidth,
    kRenderedHeight: renderedHeight,
    kPixelRatio: pixelRatio,
    kImageBase64: imageBase64,
    kHasErrors: hasErrors,
    kDiagnostics: <Map<String, Object?>>[for (final d in diagnostics) d.toJson()],
  };

  static CapturePreviewResponse fromJson(Map<String, Object?> json) => CapturePreviewResponse(
    diagnostics: <PreviewDiagnostic>[
      for (final Object? item in json[kDiagnostics]! as List<Object?>)
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

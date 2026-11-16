// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:collection/collection.dart';
import 'package:dtd/dtd.dart';
import 'package:json_rpc_2/json_rpc_2.dart';

import '../convert.dart';

/// The set of widget previews defined in a script of an analyzed Flutter
/// project.
class FlutterWidgetPreviews {
  const FlutterWidgetPreviews({
    required this.namespaces,
    required this.previews,
    required this.scriptUris,
  });

  /// A set of library URIs and the prefixes used for types in
  /// "previewAnnotation" sources.
  final Map<String, String> namespaces;

  /// The current set of previews in the script.
  final List<FlutterWidgetPreviewDetails> previews;

  /// The URI for the updated script.
  final List<Uri> scriptUris;

  @override
  int get hashCode => Object.hash(
    const DeepCollectionEquality().hash(namespaces),
    const DeepCollectionEquality().hash(previews),
    const DeepCollectionEquality().hash(scriptUris),
  );

  @override
  bool operator ==(Object other) {
    return other is FlutterWidgetPreviews &&
        other.runtimeType == FlutterWidgetPreviews &&
        const DeepCollectionEquality().equals(namespaces, other.namespaces) &&
        const DeepCollectionEquality().equals(previews, other.previews) &&
        const DeepCollectionEquality().equals(scriptUris, other.scriptUris);
  }

  Map<String, Object?> toJson() {
    final result = <String, Object?>{};
    result['namespaces'] = namespaces;
    result['previews'] = previews.map((item) => item.toJson()).toList();
    result['scriptUris'] = scriptUris.map((uri) => uri.toString()).toList();
    return result;
  }

  @override
  String toString() => json.encode(toJson());

  static FlutterWidgetPreviews fromJson(Map<String, Object?> json) {
    final Object? namespacesJson = json['namespaces'];
    final Map<String, String> namespaces = (namespacesJson! as Map<Object, Object?>).map(
      (key, value) => MapEntry(key as String, value! as String),
    );
    final Object? previewsJson = json['previews'];
    final List<FlutterWidgetPreviewDetails> previews = (previewsJson! as List<Object?>)
        .map((item) => FlutterWidgetPreviewDetails.fromJson(item! as Map<String, Object?>))
        .toList();
    final Object? scriptUrisJson = json['scriptUris'];
    final List<Uri> scriptUris = (scriptUrisJson! as List<Object?>)
        .map((item) => Uri.parse(item! as String))
        .toList();
    return FlutterWidgetPreviews(
      namespaces: namespaces,
      previews: previews,
      scriptUris: scriptUris,
    );
  }
}

/// A representation of a widget preview declaration containing all information
/// needed to import the preview into the widget previewer.
class FlutterWidgetPreviewDetails {
  const FlutterWidgetPreviewDetails({
    required this.functionName,
    required this.hasError,
    required this.dependencyHasErrors,
    required this.isBuilder,
    required this.isMultiPreview,
    this.packageName,
    required this.position,
    required this.previewAnnotation,
    required this.scriptUri,
    required this.libraryUri,
  });

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
  int get hashCode => Object.hash(
    functionName,
    hasError,
    dependencyHasErrors,
    isBuilder,
    isMultiPreview,
    packageName,
    position,
    previewAnnotation,
    scriptUri,
    libraryUri,
  );

  @override
  bool operator ==(Object other) {
    return other is FlutterWidgetPreviewDetails &&
        other.runtimeType == FlutterWidgetPreviewDetails &&
        functionName == other.functionName &&
        hasError == other.hasError &&
        dependencyHasErrors == other.dependencyHasErrors &&
        isBuilder == other.isBuilder &&
        isMultiPreview == other.isMultiPreview &&
        packageName == other.packageName &&
        position == other.position &&
        previewAnnotation == other.previewAnnotation &&
        scriptUri == other.scriptUri &&
        libraryUri == other.libraryUri;
  }

  Map<String, Object?> toJson() {
    final result = <String, Object?>{};
    result['functionName'] = functionName;
    result['hasError'] = hasError;
    result['dependencyHasErrors'] = dependencyHasErrors;
    result['isBuilder'] = isBuilder;
    result['isMultiPreview'] = isMultiPreview;
    result['packageName'] = packageName;
    result['position'] = position.toJson();
    result['previewAnnotation'] = previewAnnotation;
    result['scriptUri'] = scriptUri.toString();
    result['libraryUri'] = libraryUri.toString();
    return result;
  }

  @override
  String toString() => json.encode(toJson());

  static FlutterWidgetPreviewDetails fromJson(Map<String, Object?> json) {
    final Object? functionNameJson = json['functionName'];
    final functionName = functionNameJson! as String;
    final Object? hasErrorJson = json['hasError'];
    final hasError = hasErrorJson! as bool;
    final Object? dependencyHasErrorsJson = json['dependencyHasErrors'];
    final dependencyHasErrors = dependencyHasErrorsJson! as bool;
    final Object? isBuilderJson = json['isBuilder'];
    final isBuilder = isBuilderJson! as bool;
    final Object? isMultiPreviewJson = json['isMultiPreview'];
    final isMultiPreview = isMultiPreviewJson! as bool;
    final Object? packageNameJson = json['packageName'];
    final packageName = packageNameJson as String?;
    final Object? positionJson = json['position'];
    final Position position = Position.fromJson(positionJson! as Map<String, Object?>);
    final Object? previewAnnotationJson = json['previewAnnotation'];
    final previewAnnotation = previewAnnotationJson! as String;
    final Object? scriptUriJson = json['scriptUri'];
    final Uri scriptUri = Uri.parse(scriptUriJson! as String);
    final Object? libraryUriJson = json['libraryUri'];
    final Uri libraryUri = Uri.parse(libraryUriJson! as String);
    return FlutterWidgetPreviewDetails(
      functionName: functionName,
      hasError: hasError,
      dependencyHasErrors: dependencyHasErrors,
      isBuilder: isBuilder,
      isMultiPreview: isMultiPreview,
      packageName: packageName,
      position: position,
      previewAnnotation: previewAnnotation,
      scriptUri: scriptUri,
      libraryUri: libraryUri,
    );
  }
}

class Position {
  const Position({required this.character, required this.line});

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
  int get hashCode => Object.hash(character, line);

  @override
  bool operator ==(Object other) {
    return other is Position &&
        other.runtimeType == Position &&
        character == other.character &&
        line == other.line;
  }

  Map<String, Object?> toJson() {
    final result = <String, Object?>{};
    result['character'] = character;
    result['line'] = line;
    return result;
  }

  @override
  String toString() => json.encode(toJson());

  static Position fromJson(Map<String, Object?> json) {
    final Object? characterJson = json['character'];
    final character = characterJson! as int;
    final Object? lineJson = json['line'];
    final line = lineJson! as int;
    return Position(character: character, line: line);
  }
}

/// Information about the active web preview HTTP server.
class WebPreviewUrlResult {
  const WebPreviewUrlResult({required this.host, required this.port, required this.url});

  factory WebPreviewUrlResult.fromDTDResponse(DTDResponse response) {
    if (response.result[kType] != kTypeName) {
      throw RpcException.invalidParams(
        'Expected $kType param to be $kTypeName, got: ${response.result[kType]}',
      );
    }
    return WebPreviewUrlResult.fromJson(response.result);
  }

  static const kType = 'type';
  static const kTypeName = 'WebPreviewUrlResult';
  static const kHost = 'host';
  static const kPort = 'port';
  static const kUrl = 'url';

  /// The host interface (e.g. `127.0.0.1` or `localhost`).
  final String host;

  /// The port the web server is listening on.
  final int port;

  /// The full HTTP URL string for embedding or browser navigation.
  final String url;

  @override
  int get hashCode => Object.hash(host, port, url);

  @override
  bool operator ==(Object other) {
    return other is WebPreviewUrlResult &&
        other.runtimeType == WebPreviewUrlResult &&
        host == other.host &&
        port == other.port &&
        url == other.url;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{kType: kTypeName, kHost: host, kPort: port, kUrl: url};
  }

  @override
  String toString() => json.encode(toJson());

  static WebPreviewUrlResult fromJson(Map<String, Object?> json) {
    final host = json[kHost]! as String;
    final port = json[kPort]! as int;
    final url = json[kUrl]! as String;
    return WebPreviewUrlResult(host: host, port: port, url: url);
  }
}

/// Metadata describing the active widget preview service and connected endpoints.
class PreviewServiceInfo {
  const PreviewServiceInfo({
    required this.dtdUri,
    required this.previewService,
    required this.projectRoot,
    required this.scaffoldConnected,
    required this.scaffoldService,
    required this.scaffoldStream,
    this.webPreviewUri,
  });

  factory PreviewServiceInfo.fromDTDResponse(DTDResponse response) {
    if (response.result[kType] != kTypeName) {
      throw RpcException.invalidParams(
        'Expected $kType param to be $kTypeName, got: ${response.result[kType]}',
      );
    }
    return PreviewServiceInfo.fromJson(response.result);
  }

  static const kType = 'type';
  static const kTypeName = 'PreviewServiceInfo';
  static const kDtdUri = 'dtdUri';
  static const kPreviewService = 'previewService';
  static const kProjectRoot = 'projectRoot';
  static const kScaffoldConnected = 'scaffoldConnected';
  static const kScaffoldService = 'scaffoldService';
  static const kScaffoldStream = 'scaffoldStream';
  static const kWebPreviewUri = 'webPreviewUri';

  /// The WebSocket URI of the Dart Tooling Daemon.
  final String dtdUri;

  /// The registered DTD service name for the tool widget preview service.
  final String previewService;

  /// The absolute path to the root directory of the previewed Flutter project.
  final String projectRoot;

  /// Whether the widget preview scaffold has connected to DTD.
  final bool scaffoldConnected;

  /// The registered DTD service name for the widget preview scaffold.
  final String scaffoldService;

  /// The DTD stream name posted to by the widget preview scaffold.
  final String scaffoldStream;

  /// The active web preview HTTP URI, if available.
  final String? webPreviewUri;

  @override
  int get hashCode => Object.hash(
    dtdUri,
    previewService,
    projectRoot,
    scaffoldConnected,
    scaffoldService,
    scaffoldStream,
    webPreviewUri,
  );

  @override
  bool operator ==(Object other) {
    return other is PreviewServiceInfo &&
        other.runtimeType == PreviewServiceInfo &&
        dtdUri == other.dtdUri &&
        previewService == other.previewService &&
        projectRoot == other.projectRoot &&
        scaffoldConnected == other.scaffoldConnected &&
        scaffoldService == other.scaffoldService &&
        scaffoldStream == other.scaffoldStream &&
        webPreviewUri == other.webPreviewUri;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      kType: kTypeName,
      kDtdUri: dtdUri,
      kProjectRoot: projectRoot,
      kPreviewService: previewService,
      kScaffoldService: scaffoldService,
      kScaffoldStream: scaffoldStream,
      kWebPreviewUri: webPreviewUri,
      kScaffoldConnected: scaffoldConnected,
    };
  }

  @override
  String toString() => json.encode(toJson());

  static PreviewServiceInfo fromJson(Map<String, Object?> json) {
    final dtdUri = json[kDtdUri]! as String;
    final previewService = json[kPreviewService]! as String;
    final projectRoot = json[kProjectRoot]! as String;
    final scaffoldConnected = json[kScaffoldConnected]! as bool;
    final scaffoldService = json[kScaffoldService]! as String;
    final scaffoldStream = json[kScaffoldStream]! as String;
    final webPreviewUri = json[kWebPreviewUri] as String?;
    return PreviewServiceInfo(
      dtdUri: dtdUri,
      previewService: previewService,
      projectRoot: projectRoot,
      scaffoldConnected: scaffoldConnected,
      scaffoldService: scaffoldService,
      scaffoldStream: scaffoldStream,
      webPreviewUri: webPreviewUri,
    );
  }
}

/// Result of synchronizing on-disk preview edits and reloading the previewer.
class SyncPreviewsResponse {
  const SyncPreviewsResponse({
    required this.compileSuccess,
    required this.errorPreviewCount,
    required this.fullRestart,
    required this.reloaded,
    this.compileError,
  });

  factory SyncPreviewsResponse.fromDTDResponse(DTDResponse response) {
    if (response.result[kType] != kTypeName) {
      throw RpcException.invalidParams(
        'Expected $kType param to be $kTypeName, got: ${response.result[kType]}',
      );
    }
    return SyncPreviewsResponse.fromJson(response.result);
  }

  static const kType = 'type';
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
  int get hashCode =>
      Object.hash(compileError, compileSuccess, errorPreviewCount, fullRestart, reloaded);

  @override
  bool operator ==(Object other) {
    return other is SyncPreviewsResponse &&
        other.runtimeType == SyncPreviewsResponse &&
        compileError == other.compileError &&
        compileSuccess == other.compileSuccess &&
        errorPreviewCount == other.errorPreviewCount &&
        fullRestart == other.fullRestart &&
        reloaded == other.reloaded;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      kType: kTypeName,
      kReloaded: reloaded,
      kFullRestart: fullRestart,
      kCompileSuccess: compileSuccess,
      kCompileError: compileError,
      kErrorPreviewCount: errorPreviewCount,
    };
  }

  @override
  String toString() => json.encode(toJson());

  static SyncPreviewsResponse fromJson(Map<String, Object?> json) {
    final compileError = json[kCompileError] as String?;
    final compileSuccess = json[kCompileSuccess]! as bool;
    final errorPreviewCount = json[kErrorPreviewCount]! as int;
    final fullRestart = json[kFullRestart]! as bool;
    final reloaded = json[kReloaded]! as bool;
    return SyncPreviewsResponse(
      compileError: compileError,
      compileSuccess: compileSuccess,
      errorPreviewCount: errorPreviewCount,
      fullRestart: fullRestart,
      reloaded: reloaded,
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
  overflow('overflow');

  const PreviewDiagnosticKind(this.wireValue);

  final String wireValue;

  static PreviewDiagnosticKind fromJson(String value) => switch (value) {
    'compile_error' => .compileError,
    'exception' => .exception,
    'unconstrained' => .unconstrained,
    'overflow' => .overflow,
    _ => throw FormatException('Unknown PreviewDiagnosticKind: $value'),
  };
}

/// Structured diagnostic captured while compiling, building, laying out, or
/// painting a widget preview.
class PreviewDiagnostic {
  const PreviewDiagnostic({
    required this.kind,
    required this.phase,
    required this.summary,
    this.overflowAxis,
    this.overflowPixels,
    this.overflowSide,
    this.targetType,
  });

  static const kKind = 'kind';
  static const kOverflowAxis = 'overflowAxis';
  static const kOverflowPixels = 'overflowPixels';
  static const kOverflowSide = 'overflowSide';
  static const kPhase = 'phase';
  static const kSummary = 'summary';
  static const kTargetType = 'targetType';

  final PreviewDiagnosticKind kind;
  final String? overflowAxis;
  final double? overflowPixels;
  final String? overflowSide;
  final PreviewDiagnosticPhase phase;
  final String summary;
  final String? targetType;

  @override
  int get hashCode =>
      Object.hash(kind, overflowAxis, overflowPixels, overflowSide, phase, summary, targetType);

  @override
  bool operator ==(Object other) {
    return other is PreviewDiagnostic &&
        other.runtimeType == PreviewDiagnostic &&
        kind == other.kind &&
        overflowAxis == other.overflowAxis &&
        overflowPixels == other.overflowPixels &&
        overflowSide == other.overflowSide &&
        phase == other.phase &&
        summary == other.summary &&
        targetType == other.targetType;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      kPhase: phase.name,
      kKind: kind.wireValue,
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
      summary: json[kSummary]! as String,
      targetType: json[kTargetType] as String?,
    );
  }
}

/// Metadata and error summary for a single discovered widget preview instance.
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

/// DTD response containing the list of widget previews in the workspace.
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
  int get hashCode => const ListEquality<PreviewEntry>().hash(previews);

  @override
  bool operator ==(Object other) {
    return other is PreviewListResponse &&
        other.runtimeType == PreviewListResponse &&
        const ListEquality<PreviewEntry>().equals(previews, other.previews);
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

/// DTD response returned by `PreviewScaffold.capturePreview` containing the
/// rendered dimensions, optional base64-encoded PNG snapshot, and structured
/// diagnostics for a single widget preview.
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
    const ListEquality<PreviewDiagnostic>().hash(diagnostics),
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
        const ListEquality<PreviewDiagnostic>().equals(diagnostics, other.diagnostics) &&
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
        for (final PreviewDiagnostic diagnostic in diagnostics) diagnostic.toJson(),
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

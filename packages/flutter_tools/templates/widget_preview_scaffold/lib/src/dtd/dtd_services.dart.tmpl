// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:ui' show Brightness;

import 'package:dtd/dtd.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:widget_preview_scaffold/src/dtd/dtd_connection_info.dart';
import 'package:widget_preview_scaffold/src/dtd/editor_service.dart';
import 'package:widget_preview_scaffold/src/dtd/utils.dart';
import 'package:widget_preview_scaffold/src/widget_preview.dart';

/// Provides services, streams, and RPC invocations to interact with Flutter developer tooling.
class WidgetPreviewScaffoldDtdServices with DtdEditorService {
  WidgetPreviewScaffoldDtdServices({
    this.onCapturePreview,
    this.onGetPreviews,
    this.scaffoldServiceName = kWidgetPreviewScaffoldService,
  });

  // WARNING: Keep these constants and services in sync with those defined in the widget preview
  // scaffold's dtd_services.dart.
  //
  // START KEEP SYNCED

  static const kIsWindows = 'isWindows';
  static const kHotRestartPreviewer = 'hotRestartPreviewer';
  static const kHotReloadPreviewer = 'hotReloadPreviewer';
  static const kResolveUri = 'resolveUri';
  static const kSetPreference = 'setPreference';
  static const kGetPreference = 'getPreference';
  static const kGetDevToolsUri = 'getDevToolsUri';
  static const kGetWebPreviewUrl = 'getWebPreviewUrl';
  static const kGetServiceInfo = 'getServiceInfo';
  static const kSyncPreviews = 'syncPreviews';
  static const kListPreviews = 'listPreviews';
  static const kGetPreviews = 'getPreviews';
  static const kCapturePreview = 'capturePreview';

  static const kWidgetPreviewConnectedEvent = 'Connected';

  /// Error code for [RpcException] thrown when a requested preview ID or name
  /// does not match any registered preview.
  static const kPreviewNotFoundErrorCode = 101;

  /// Error code for [RpcException] thrown when a shorthand preview name
  /// matches more than one registered preview.
  static const kAmbiguousPreviewNameErrorCode = 102;

  /// Error code for RpcException thrown when attempting to load a key from
  /// persistent preferences that doesn't have an entry, or when a requested
  /// resource (such as the web preview URL) is not available.
  static const kNoValueForKey = 200;

  // END KEEP SYNCED

  static const kBrightness = 'brightness';
  static const kFileUri = 'fileUri';
  static const kHeight = 'height';
  static const kIncludeImage = 'includeImage';
  static const kPixelRatio = 'pixelRatio';
  static const kPreviewId = 'previewId';
  static const kTextScaleFactor = 'textScaleFactor';
  static const kUrl = 'url';
  static const kWidth = 'width';

  /// The DTD service name under which scaffold RPC methods are registered.
  final String scaffoldServiceName;

  /// Callback invoked when [kGetPreviews] is requested over DTD.
  PreviewListResponse Function({String? fileUri})? onGetPreviews;

  /// Callback invoked when [kCapturePreview] is requested over DTD.
  Future<CapturePreviewResponse> Function(PreviewCaptureRequest request)?
  onCapturePreview;

  /// Connects to the Dart Tooling Daemon (DTD) specified by the Flutter tool.
  ///
  /// If the connection is successful, the Widget Preview Scaffold will register services and
  /// subscribe to various streams to interact directly with other tooling (e.g., IDEs).
  Future<void> connect({Uri? dtdUri}) async {
    final Uri dtdWsUri = dtdUri ?? Uri.parse(kWidgetPreviewDtdUri);
    dtd = await DartToolingDaemon.connect(dtdWsUri);
    await _determineIfWindows();
    await dtd.registerService(scaffoldServiceName, kGetPreviews, _getPreviews);
    await dtd.registerService(
      scaffoldServiceName,
      kCapturePreview,
      _capturePreview,
    );
    unawaited(
      dtd.postEvent(
        kWidgetPreviewScaffoldStream,
        kWidgetPreviewConnectedEvent,
        const <String, Object?>{},
      ),
    );
    await initializeEditorService(this);
  }

  Future<Map<String, Object?>> _getPreviews(Parameters params) async {
    final String? fileUri =
        params.value == null || params[kFileUri].valueOr(null) == null
        ? null
        : params[kFileUri].asString;
    final PreviewListResponse response =
        onGetPreviews?.call(fileUri: fileUri) ??
        const PreviewListResponse(previews: <PreviewEntry>[]);
    return response.toJson();
  }

  Future<Map<String, Object?>> _capturePreview(Parameters params) async {
    if (params.value == null || params[kPreviewId].valueOr(null) == null) {
      throw RpcException.invalidParams(
        'Missing required parameter "$kPreviewId".',
      );
    }
    final String previewId = params[kPreviewId].asString;
    final double? width = _optionalPositiveDouble(params, kWidth);
    final double? height = _optionalPositiveDouble(params, kHeight);
    final double? pixelRatio = _optionalPositiveDouble(params, kPixelRatio);
    final double? textScaleFactor = _optionalPositiveDouble(
      params,
      kTextScaleFactor,
    );
    final Brightness? brightness =
        params.value == null || params[kBrightness].valueOr(null) == null
        ? null
        : switch (params[kBrightness].asString) {
            'light' => Brightness.light,
            'dark' => Brightness.dark,
            final String other => throw RpcException.invalidParams(
              'Parameter "$kBrightness" must be "light" or "dark", got: "$other".',
            ),
          };
    final bool includeImage =
        params.value == null ||
        params[kIncludeImage].valueOr(null) == null ||
        params[kIncludeImage].asBool;
    final Future<CapturePreviewResponse> Function(PreviewCaptureRequest)?
    captureCallback = onCapturePreview;
    if (captureCallback == null) {
      throw RpcException(
        kNoValueForKey,
        'Preview capture is not currently available.',
      );
    }
    final CapturePreviewResponse response = await captureCallback(
      PreviewCaptureRequest(
        brightness: brightness,
        height: height,
        includeImage: includeImage,
        pixelRatio: pixelRatio,
        previewId: previewId,
        textScaleFactor: textScaleFactor,
        width: width,
      ),
    );
    return response.toJson();
  }

  static double? _optionalPositiveDouble(Parameters params, String key) {
    if (params.value == null || params[key].valueOr(null) == null) {
      return null;
    }
    final double value = params[key].asNum.toDouble();
    if (!value.isFinite || value <= 0) {
      throw RpcException.invalidParams(
        'Parameter "$key" must be a positive finite number, got: $value.',
      );
    }
    return value;
  }

  /// Disposes the DTD connection.
  @override
  Future<void> dispose() async {
    super.dispose();
    await dtd.close();
  }

  Future<DTDResponse?> _call(
    String methodName, {
    Map<String, Object?>? params,
  }) => dtd.safeCall(kWidgetPreviewService, methodName, params: params);

  /// Returns `true` if the operating system is Windows.
  bool get isWindows => _isWindows;
  bool _isWindows = false;

  Future<void> _determineIfWindows() async {
    _isWindows = (BoolResponse.fromDTDResponse(
      (await _call(kIsWindows))!,
    )).value!;
  }

  /// Trigger a hot restart of the widget preview scaffold.
  Future<void> hotRestartPreviewer() => _call(kHotRestartPreviewer);

  /// Trigger a hot reload of the widget preview scaffold.
  Future<void> hotReloadPreviewer() => _call(kHotReloadPreviewer);

  /// Retrieves the active web preview URL from the Flutter tool daemon.
  Future<Uri?> getWebPreviewUrl() async {
    try {
      final response = await _call(kGetWebPreviewUrl);
      if (response == null) {
        return null;
      }
      final urlString = response.result[kUrl] as String?;
      return urlString != null ? Uri.parse(urlString) : null;
    } on RpcException catch (e) {
      if (e.code == kNoValueForKey) {
        return null;
      }
      rethrow;
    }
  }

  /// Retrieves metadata describing the active widget preview service.
  Future<Map<String, Object?>?> getServiceInfo() async {
    final response = await _call(kGetServiceInfo);
    return response?.result;
  }

  /// Resolves a package:// URI to a file:// URI using the package_config.
  ///
  /// Returns null if [uri] can not be resolved.
  Future<Uri?> resolveUri(Uri uri) async {
    final response = await _call(kResolveUri, params: {'uri': uri.toString()});
    if (response == null) {
      return null;
    }
    final result = StringResponse.fromDTDResponse(response).value;
    return result == null ? null : Uri.parse(result);
  }

  /// Retrieves an arbitrary value associated with [key] from the persistent
  /// preferences map.
  ///
  /// Returns null if [key] is not in the map.
  Future<Object?> getPreference(String key) async {
    try {
      final response = await _call(kGetPreference, params: {'key': key});
      return switch (response?.type) {
        'StringResponse' => StringResponse.fromDTDResponse(response!).value,
        'BoolResponse' => BoolResponse.fromDTDResponse(response!).value,
        _ => throw StateError('Unexpected response type: ${response?.type}'),
      };
    } on RpcException catch (e) {
      if (e.code == kNoValueForKey) {
        return null;
      }
      rethrow;
    }
  }

  /// Retrieves the state of flag [key] from the persistent preferences map.
  ///
  /// If [key] is not set, [defaultValue] is returned.
  Future<bool> getFlag(String key, {bool defaultValue = false}) async {
    final result = await getPreference(key) as bool?;
    return result ?? defaultValue;
  }

  /// Sets [key] to [value] in the persistent preferences map.
  Future<void> setPreference(String key, Object? value) async {
    await _call(kSetPreference, params: {'key': key, 'value': value});
  }

  /// Retrieves the DevTools URI for the previewer instance.
  Future<Uri> getDevToolsUri() async {
    final result = StringResponse.fromDTDResponse(
      (await _call(kGetDevToolsUri))!,
    );
    return Uri.parse(result.value!);
  }

  @override
  late final DartToolingDaemon dtd;
}

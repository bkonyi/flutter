// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:dtd/dtd.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:widget_preview_scaffold/src/dtd/dtd_connection_info.dart';
import 'package:widget_preview_scaffold/src/dtd/editor_service.dart';
import 'package:widget_preview_scaffold/src/dtd/utils.dart';
import 'package:widget_preview_scaffold/src/widget_preview.dart';

/// Provides services, streams, and RPC invocations to interact with Flutter developer tooling.
class WidgetPreviewScaffoldDtdServices with DtdEditorService {
  WidgetPreviewScaffoldDtdServices({
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
  static const kPreviewReloadedEvent = 'PreviewReloaded';
  static const kFullRestart = 'fullRestart';

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

  static const kFileUri = 'fileUri';
  static const kUrl = 'url';

  /// The DTD service name under which scaffold RPC methods are registered.
  final String scaffoldServiceName;

  /// Callback invoked when [kGetPreviews] is requested over DTD.
  PreviewListResponse Function({String? fileUri})? onGetPreviews;

  var _disposed = false;
  var _editorServiceInitialized = false;

  /// Connects to the Dart Tooling Daemon (DTD) specified by the Flutter tool.
  Future<void> connect({Uri? dtdUri}) async {
    final Uri dtdWsUri = dtdUri ?? Uri.parse(kWidgetPreviewDtdUri);
    final DartToolingDaemon? previousDtd = _dtd;
    _dtd = null;
    await previousDtd?.close();
    final DartToolingDaemon connectedDtd = await DartToolingDaemon.connect(
      dtdWsUri,
    );
    if (_disposed) {
      await connectedDtd.close();
      return;
    }
    _dtd = connectedDtd;
    await _determineIfWindows();
    await connectedDtd.registerService(
      scaffoldServiceName,
      kGetPreviews,
      _getPreviews,
    );
    unawaited(
      connectedDtd.postEvent(
        kWidgetPreviewScaffoldStream,
        kWidgetPreviewConnectedEvent,
        const <String, Object?>{},
      ),
    );
    _editorServiceInitialized = true;
    await initializeEditorService(this);
  }

  static bool _hasParam(Parameters params, String key) =>
      params.value != null && params[key].valueOr(null) != null;

  Future<Map<String, Object?>> _getPreviews(Parameters params) async {
    final String? fileUri = _hasParam(params, kFileUri)
        ? params[kFileUri].asString
        : null;
    final PreviewListResponse response =
        onGetPreviews?.call(fileUri: fileUri) ?? PreviewListResponse.empty;
    return response.toJson();
  }

  /// Disposes the DTD connection.
  @override
  Future<void> dispose() async {
    _disposed = true;
    if (_editorServiceInitialized) {
      super.dispose();
    }
    final DartToolingDaemon? currentDtd = _dtd;
    _dtd = null;
    if (currentDtd != null) {
      await currentDtd.close();
    }
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

  DartToolingDaemon? _dtd;

  @override
  DartToolingDaemon get dtd => _dtd!;
}

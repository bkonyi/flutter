// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Brightness, VoidCallback;

import 'package:dtd/dtd.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:widget_preview_scaffold/src/dtd/dtd_connection_info.dart';
import 'package:widget_preview_scaffold/src/dtd/editor_service.dart';
import 'package:widget_preview_scaffold/src/dtd/utils.dart';
import 'package:widget_preview_scaffold/src/utils/url/url.dart';
import 'package:widget_preview_scaffold/src/widget_preview.dart';

/// Provides services, streams, and RPC invocations to interact with Flutter developer tooling.
class WidgetPreviewScaffoldDtdServices with DtdEditorService {
  WidgetPreviewScaffoldDtdServices({
    this.onCapturePreview,
    this.onGetPreviews,
    this.onInPlaceHotReload,
    this.onPreviewReloaded,
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

  static const kBrightness = 'brightness';
  static const kFileUri = 'fileUri';
  static const kHeight = 'height';
  static const kIncludeImage = 'includeImage';
  static const kPixelRatio = 'pixelRatio';
  static const kPreviewId = 'previewId';
  static const kPumpMs = 'pumpMs';
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

  /// Callback invoked after changed DDC modules have been hot-reloaded in-place
  /// in viewer-only mode.
  FutureOr<void> Function()? onInPlaceHotReload;

  /// Callback invoked when [kPreviewReloadedEvent] is received on
  /// [kWidgetPreviewScaffoldStream] in viewer-only mode.
  VoidCallback? onPreviewReloaded;

  StreamSubscription<DTDEvent>? _scaffoldStreamSubscription;
  Future<void>? _activeViewerReload;
  int? _liveRevision;
  Timer? _reconnectTimer;
  var _reconnectAttempt = 0;
  var _disposed = false;
  var _editorServiceInitialized = false;
  var _needsViewerCatchUp = false;

  /// Connects to the Dart Tooling Daemon (DTD) specified by the Flutter tool.
  ///
  /// When [readOnly] is `true` (or the current URL fragment sets `embed=1`), the
  /// scaffold connects as a viewer-only client without registering scaffold RPCs
  /// or posting [kWidgetPreviewConnectedEvent], and reloads in-place (falling
  /// back to a page reload) when [kPreviewReloadedEvent] arrives on
  /// [kWidgetPreviewScaffoldStream].
  Future<void> connect({Uri? dtdUri, bool readOnly = false}) async {
    final EmbedPreviewParams embedParams = EmbedPreviewParams.fromCurrentUrl();
    final bool isViewerOnly = readOnly || embedParams.isEmbed;
    final Uri? proxyUri = embedParams.isEmbed
        ? embedParams.resolveDtdProxyUri(getBaseUri())
        : null;
    final Uri dtdWsUri = dtdUri ?? proxyUri ?? Uri.parse(kWidgetPreviewDtdUri);
    if (isViewerOnly && dtdWsUri.toString().isEmpty) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final DartToolingDaemon? previousDtd = _dtd;
    _dtd = null;
    await previousDtd?.close();
    if (isViewerOnly) {
      await _connectViewer(dtdWsUri);
      return;
    }
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
    await connectedDtd.registerService(
      scaffoldServiceName,
      kCapturePreview,
      _capturePreview,
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

  Future<void> _connectViewer(Uri dtdWsUri) async {
    _liveRevision ??= initialLiveRevision;
    final DartToolingDaemon connectedDtd;
    try {
      connectedDtd = await DartToolingDaemon.connect(dtdWsUri);
    } on Exception {
      if (!_disposed) {
        _scheduleViewerReconnect(dtdWsUri);
      }
      return;
    }
    if (_disposed) {
      await connectedDtd.close();
      return;
    }
    _dtd = connectedDtd;
    try {
      await _subscribeToScaffoldReloadEvents();
    } on Exception catch (e) {
      if (identical(_dtd, connectedDtd)) {
        _dtd = null;
      }
      await connectedDtd.close();
      if (_disposed) {
        return;
      }
      if (e is RpcException && e.code == RpcErrorCodes.kMethodNotFound) {
        // The server rejected our compiled scaffold stream UUID, which
        // indicates the preview daemon restarted with a new stream ID.
        if (onPreviewReloaded case final VoidCallback callback) {
          callback();
        } else {
          reloadWindow();
        }
        return;
      }
      _scheduleViewerReconnect(dtdWsUri);
      return;
    }
    if (_disposed) {
      return;
    }
    _reconnectAttempt = 0;
    final bool shouldCatchUp = _needsViewerCatchUp;
    _needsViewerCatchUp = false;
    unawaited(
      connectedDtd.done.whenComplete(() {
        if (!_disposed && identical(_dtd, connectedDtd)) {
          _scheduleViewerReconnect(dtdWsUri);
        }
      }),
    );
    if (shouldCatchUp) {
      unawaited(_enqueueViewerReload(fullRestart: false, onlyIfChanged: true));
    }
  }

  void _scheduleViewerReconnect(Uri dtdWsUri) {
    if (_disposed || _reconnectTimer != null) {
      return;
    }
    _needsViewerCatchUp = true;
    final int delaySeconds = math.min(1 << _reconnectAttempt, 10);
    _reconnectAttempt = math.min(_reconnectAttempt + 1, 4);
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      _reconnectTimer = null;
      if (_disposed) {
        return;
      }
      await connect(dtdUri: dtdWsUri, readOnly: true);
    });
  }

  Future<void> _subscribeToScaffoldReloadEvents() async {
    await _scaffoldStreamSubscription?.cancel();
    _scaffoldStreamSubscription = dtd
        .onEvent(kWidgetPreviewScaffoldStream)
        .listen((DTDEvent event) {
          if (event.kind == kPreviewReloadedEvent) {
            unawaited(
              _enqueueViewerReload(
                fullRestart: event.data[kFullRestart] == true,
              ),
            );
          }
        });
    await dtd.safeStreamListen(kWidgetPreviewScaffoldStream);
  }

  Future<void> _enqueueViewerReload({
    required bool fullRestart,
    bool onlyIfChanged = false,
  }) {
    final Future<void> previous = _activeViewerReload ?? Future<void>.value();
    final Future<void> current = previous.whenComplete(() async {
      if (_disposed) {
        return;
      }
      await _handleViewerReloadEvent(
        fullRestart: fullRestart,
        onlyIfChanged: onlyIfChanged,
      );
    });
    _activeViewerReload = current;
    return current;
  }

  Future<void> _handleViewerReloadEvent({
    required bool fullRestart,
    bool onlyIfChanged = false,
  }) async {
    if (onPreviewReloaded case final VoidCallback callback) {
      if (!onlyIfChanged) {
        callback();
      }
      return;
    }
    final int? sinceRevision = _liveRevision;
    if (onlyIfChanged && sinceRevision == null) {
      return;
    }
    if (!fullRestart && sinceRevision != null) {
      final int? nextRevision = await hotReloadLiveModules(
        sinceRevision: sinceRevision,
      );
      if (nextRevision != null) {
        _liveRevision = nextRevision;
        if (!_disposed && (!onlyIfChanged || nextRevision > sinceRevision)) {
          await onInPlaceHotReload?.call();
        }
        return;
      }
    }
    reloadWindow();
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

  Future<Map<String, Object?>> _capturePreview(Parameters params) async {
    if (!_hasParam(params, kPreviewId)) {
      throw RpcException.invalidParams(
        'Missing required parameter "$kPreviewId".',
      );
    }
    final Brightness? brightness = !_hasParam(params, kBrightness)
        ? null
        : switch (params[kBrightness].asString) {
            'light' => Brightness.light,
            'dark' => Brightness.dark,
            final String other => throw RpcException.invalidParams(
              'Parameter "$kBrightness" must be "light" or "dark", got: "$other".',
            ),
          };
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
        height: _optionalPositiveDouble(params, kHeight),
        includeImage:
            !_hasParam(params, kIncludeImage) || params[kIncludeImage].asBool,
        pixelRatio: _optionalPositiveDouble(params, kPixelRatio),
        previewId: params[kPreviewId].asString,
        pumpMs: _hasParam(params, kPumpMs) ? params[kPumpMs].asInt : null,
        textScaleFactor: _optionalPositiveDouble(params, kTextScaleFactor),
        width: _optionalPositiveDouble(params, kWidth),
      ),
    );
    return response.toJson();
  }

  static double? _optionalPositiveDouble(Parameters params, String key) {
    if (!_hasParam(params, key)) {
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
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (_editorServiceInitialized) {
      super.dispose();
    }
    await _scaffoldStreamSubscription?.cancel();
    _scaffoldStreamSubscription = null;
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

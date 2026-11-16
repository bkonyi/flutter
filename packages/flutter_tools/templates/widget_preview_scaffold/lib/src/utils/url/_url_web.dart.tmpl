// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// NOTE: originally from package:devtools_app_shared

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:web/web.dart';

import 'url.dart';

const _kApiSyncPath = '__api/sync';
const _kBrightnessKey = 'brightness';
const _kCacheNoStore = 'no-store';
const _kCompileSuccessKey = 'compileSuccess';
const _kErrorKey = 'error';
const _kErrorMessageKey = 'errorMessage';
const _kHostKey = 'flutterWidgetPreviewHost';
const _kMessageKey = 'message';
const _kMethodPost = 'POST';
const _kPreviewIdKey = 'previewId';
const _kPreviewNameKey = 'previewName';
const _kSelectionsKey = 'selections';
const _kSendSelectionMethod = 'sendSelection';
const _kTextScaleKey = 'textScale';
const _kViewportKey = 'viewport';
const _kZoomKey = 'zoom';

typedef LiveSyncResult = ({bool compileSuccess, String? errorMessage});
typedef LiveSendSelectionHandler =
    Future<void> Function({
      required String message,
      required List<Map<String, Object?>> selections,
      String? brightness,
      String? previewId,
      String? previewName,
      String? textScale,
      String? viewport,
      String? zoom,
    });

String? _debugUrlFragmentOverride;
Uri? _debugBaseUriOverride;
final _debugFragmentChangeController = StreamController<String>.broadcast(
  sync: true,
);
StreamSubscription<Event>? _webFragmentSubscription;
StreamSubscription<String>? _debugFragmentSubscription;
final StreamController<String> _urlFragmentChangeController =
    StreamController<String>.broadcast(
      sync: true,
      onListen: () {
        _webFragmentSubscription ??= EventStreamProviders.hashChangeEvent
            .forTarget(window)
            .listen((_) => _urlFragmentChangeController.add(getUrlFragment()));
        _debugFragmentSubscription ??= _debugFragmentChangeController.stream
            .listen(_urlFragmentChangeController.add);
      },
      onCancel: () async {
        final StreamSubscription<Event>? webSub = _webFragmentSubscription;
        final StreamSubscription<String>? debugSub = _debugFragmentSubscription;
        _webFragmentSubscription = null;
        _debugFragmentSubscription = null;
        await webSub?.cancel();
        await debugSub?.cancel();
      },
    );
var _debugReloadCount = 0;
VoidCallback? _debugOnReloadCallback;
Future<LiveSyncResult> Function()? _debugTriggerSyncHandler;
LiveSendSelectionHandler? _debugSendSelectionHandler;

Map<String, String> loadQueryParams({String Function(String)? urlModifier}) {
  var url = getWebUrl()!;
  url = urlModifier?.call(url) ?? url;
  return Uri.parse(url).queryParameters;
}

String? getWebUrl() => window.location.toString();

void webRedirect(String url) {
  window.location.replace(url);
}

void updateQueryParameter(String key, String? value, {bool reload = false}) {
  final newQueryParams = Map.of(loadQueryParams());
  if (value == null) {
    newQueryParams.remove(key);
  } else {
    newQueryParams[key] = value;
  }
  final newUri = Uri.parse(
    window.location.toString(),
  ).replace(queryParameters: newQueryParams);
  window.history.replaceState(window.history.state, '', newUri.toString());

  if (reload) {
    window.location.reload();
  }
}

/// Returns the current URL fragment without any leading `'#'`, or a test
/// override set via [debugSetUrlFragment].
String getUrlFragment() {
  if (_debugUrlFragmentOverride case final String override) {
    return override;
  }
  final String hash = window.location.hash;
  if (hash.isNotEmpty) {
    return hash.startsWith('#') ? hash.substring(1) : hash;
  }
  return Uri.base.fragment;
}

/// Returns the current base [Uri] for resolving relative proxy paths.
Uri getBaseUri() =>
    _debugBaseUriOverride ??
    Uri.tryParse(window.location.toString()) ??
    Uri.base;

/// Broadcasts updated URL fragments whenever the browser hash changes.
Stream<String> get onUrlFragmentChange => _urlFragmentChangeController.stream;

/// Reloads the current browser window, preserving the URL fragment.
void reloadWindow() {
  _debugReloadCount++;
  if (_debugOnReloadCallback case final VoidCallback callback) {
    callback();
    return;
  }
  window.location.reload();
}

/// Replaces the current embed URL fragment via `history.replaceState` without
/// adding a browser history entry and notifies [onUrlFragmentChange] listeners.
void replaceEmbedUrl(String fragment) {
  final String normalized = fragment.startsWith('#')
      ? fragment.substring(1)
      : fragment;
  if (_debugUrlFragmentOverride != null) {
    _debugUrlFragmentOverride = normalized;
  }
  window.history.replaceState(null, '', '#$normalized');
  _debugFragmentChangeController.add(normalized);
}

/// Synchronizes interactive embed [zoom] changes with the URL fragment via
/// `history.replaceState`.
void notifyEmbedZoomChanged(double zoom) {
  final String updatedFragment = buildUpdatedZoomFragment(
    getUrlFragment(),
    zoom,
  );
  if (_debugUrlFragmentOverride != null) {
    _debugUrlFragmentOverride = updatedFragment;
  }
  window.history.replaceState(null, '', '#$updatedFragment');
}

JSObject? _resolveHostObject() {
  try {
    final JSObject globalWindow = window as JSObject;
    final JSAny? host = globalWindow.getProperty<JSAny?>(_kHostKey.toJS);
    if (host == null || !host.isA<JSObject>()) {
      return null;
    }
    final hostObj = host as JSObject;
    final JSAny? sendFn = hostObj.getProperty<JSAny?>(
      _kSendSelectionMethod.toJS,
    );
    if (sendFn == null || !sendFn.isA<JSFunction>()) {
      return null;
    }
    return hostObj;
  } on Object {
    return null;
  }
}

/// Whether a host `window.flutterWidgetPreviewHost.sendSelection` callback (or
/// test handler) is available.
bool get canSendLiveSelection =>
    _debugSendSelectionHandler != null || _resolveHostObject() != null;

/// Triggers a preview sync/reload via `POST __api/sync` on the live server.
Future<LiveSyncResult> triggerLiveSync() async {
  if (_debugTriggerSyncHandler case final handler?) {
    return handler();
  }
  final Uri uri = resolveLiveRootUri(getBaseUri()).resolve(_kApiSyncPath);
  final Response response = await window
      .fetch(
        uri.toString().toJS,
        RequestInit(method: _kMethodPost, cache: _kCacheNoStore),
      )
      .toDart;
  final String body = (await response.text().toDart).toDart;
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    decoded = null;
  }
  if (!response.ok) {
    final String? error = decoded is Map<Object?, Object?>
        ? decoded[_kErrorKey] as String? ??
              decoded[_kErrorMessageKey] as String?
        : null;
    return (
      compileSuccess: false,
      errorMessage: error ?? 'Sync failed with status ${response.status}.',
    );
  }
  if (decoded is Map<Object?, Object?>) {
    final bool compileSuccess = decoded[_kCompileSuccessKey] != false;
    final Object? rawError = decoded[_kErrorMessageKey] ?? decoded[_kErrorKey];
    final String? errorMessage = rawError is String && rawError.isNotEmpty
        ? rawError
        : null;
    return (compileSuccess: compileSuccess, errorMessage: errorMessage);
  }
  return (compileSuccess: true, errorMessage: null);
}

/// Sends the active [selections] and user [message] to the host via
/// `window.flutterWidgetPreviewHost.sendSelection`.
Future<void> sendLiveSelectionToHost({
  required String message,
  required List<Map<String, Object?>> selections,
  String? brightness,
  String? previewId,
  String? previewName,
  String? textScale,
  String? viewport,
  String? zoom,
}) async {
  if (_debugSendSelectionHandler case final handler?) {
    await handler(
      message: message,
      selections: selections,
      brightness: brightness,
      previewId: previewId,
      previewName: previewName,
      textScale: textScale,
      viewport: viewport,
      zoom: zoom,
    );
    return;
  }
  final JSObject? hostObj = _resolveHostObject();
  if (hostObj == null) {
    throw StateError('Host selection handler is not available.');
  }
  final payload = <String, Object?>{
    _kMessageKey: message,
    _kSelectionsKey: selections,
    if (previewId != null && previewId.isNotEmpty) _kPreviewIdKey: previewId,
    if (previewName != null && previewName.isNotEmpty)
      _kPreviewNameKey: previewName,
    if (brightness != null && brightness.isNotEmpty)
      _kBrightnessKey: brightness,
    if (viewport != null && viewport.isNotEmpty) _kViewportKey: viewport,
    if (textScale != null && textScale.isNotEmpty) _kTextScaleKey: textScale,
    if (zoom != null && zoom.isNotEmpty) _kZoomKey: zoom,
  };
  final JSAny? result = hostObj.callMethod<JSAny?>(
    _kSendSelectionMethod.toJS,
    payload.jsify(),
  );
  if (result != null && result.isA<JSPromise>()) {
    await (result as JSPromise<JSAny?>).toDart;
  }
}

/// Number of times [reloadWindow] has been invoked in tests.
@visibleForTesting
int get debugReloadCount => _debugReloadCount;

/// Updates the simulated URL fragment (and optional [baseUri]) for tests and
/// notifies [onUrlFragmentChange] listeners.
@visibleForTesting
void debugSetUrlFragment(String fragment, {Uri? baseUri}) {
  _debugUrlFragmentOverride = fragment;
  if (baseUri != null) {
    _debugBaseUriOverride = baseUri;
  }
  _debugFragmentChangeController.add(getUrlFragment());
}

/// Registers an optional callback invoked by [reloadWindow] during tests.
@visibleForTesting
void debugSetReloadHandler(VoidCallback? onReload) {
  _debugOnReloadCallback = onReload;
}

/// Registers an optional test handler for [triggerLiveSync].
@visibleForTesting
void debugSetTriggerSyncHandler(Future<LiveSyncResult> Function()? handler) {
  _debugTriggerSyncHandler = handler;
}

/// Registers an optional test handler for [sendLiveSelectionToHost].
@visibleForTesting
void debugSetSendSelectionHandler(LiveSendSelectionHandler? handler) {
  _debugSendSelectionHandler = handler;
}

/// Resets all URL test overrides and counters.
@visibleForTesting
void debugResetUrlTestState() {
  _debugUrlFragmentOverride = null;
  _debugBaseUriOverride = null;
  _debugReloadCount = 0;
  _debugOnReloadCallback = null;
  _debugTriggerSyncHandler = null;
  _debugSendSelectionHandler = null;
}

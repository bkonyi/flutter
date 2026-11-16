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

const _kApiCapabilitiesPath = '__api/capabilities';
const _kApiSendSelectionPath = '__api/send-selection';
const _kApiSyncPath = '__api/sync';
const _kBrightnessKey = 'brightness';
const _kCacheNoStore = 'no-store';
const _kCanSendToChatKey = 'canSendToChat';
const _kCompileSuccessKey = 'compileSuccess';
const _kContentTypeHeader = 'Content-Type';
const _kContextKey = 'context';
const _kConversationIdKey = 'conversationId';
const _kErrorKey = 'error';
const _kErrorMessageKey = 'errorMessage';
const _kGetConversationIdMethod = 'getConversationId';
const _kJsonContentType = 'application/json';
const _kMessageKey = 'message';
const _kMethodGet = 'GET';
const _kMethodPost = 'POST';
const _kPreviewIdKey = 'previewId';
const _kPreviewNameKey = 'previewName';
const _kProjectRootKey = 'projectRoot';
const _kRootParam = 'root';
const _kSelectionsKey = 'selections';
const _kSidecarKey = 'sidecar';
const _kTextScaleKey = 'textScale';
const _kViewportKey = 'viewport';
const _kZoomKey = 'zoom';

typedef LiveCapabilitiesResult = ({bool canSendToChat, String? projectRoot});
typedef LiveSyncResult = ({bool compileSuccess, String? errorMessage});
typedef LiveSendSelectionHandler =
    Future<void> Function({
      required String message,
      required List<Map<String, Object?>> selections,
      String? brightness,
      String? previewId,
      String? previewName,
      String? projectRoot,
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
Future<LiveCapabilitiesResult> Function()? _debugProbeCapabilitiesHandler;
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

Uri _buildLiveApiUri(String relativePath) {
  final Uri baseUri = getBaseUri();
  final Uri resolved = resolveLiveRootUri(baseUri).resolve(relativePath);
  final queryParams = <String, String>{};
  final String? root = baseUri.queryParameters[_kRootParam];
  if (root != null && root.isNotEmpty) {
    queryParams[_kRootParam] = root;
  }
  final String? conversationId = baseUri.queryParameters[_kConversationIdKey];
  if (conversationId != null && conversationId.isNotEmpty) {
    queryParams[_kConversationIdKey] = conversationId;
  }
  if (queryParams.isEmpty) {
    return resolved;
  }
  return resolved.replace(queryParameters: queryParams);
}

Future<String?> _readSidecarConversationId() async {
  try {
    final JSObject globalWindow = window as JSObject;
    final JSAny? sidecar = globalWindow.getProperty<JSAny?>(_kSidecarKey.toJS);
    if (sidecar == null || !sidecar.isA<JSObject>()) {
      return null;
    }
    final JSAny? context = (sidecar as JSObject).getProperty<JSAny?>(
      _kContextKey.toJS,
    );
    if (context == null || !context.isA<JSObject>()) {
      return null;
    }
    final JSObject contextObj = context as JSObject;
    final JSAny? getConvFn = contextObj.getProperty<JSAny?>(
      _kGetConversationIdMethod.toJS,
    );
    if (getConvFn == null || !getConvFn.isA<JSFunction>()) {
      return null;
    }
    final JSAny? result = contextObj.callMethod<JSAny?>(
      _kGetConversationIdMethod.toJS,
    );
    if (result == null) {
      return null;
    }
    if (result.isA<JSPromise>()) {
      final JSAny? awaited = await (result as JSPromise<JSAny?>).toDart;
      if (awaited != null && awaited.isA<JSString>()) {
        final String value = (awaited as JSString).toDart;
        return value.isEmpty ? null : value;
      }
      return null;
    }
    if (result.isA<JSString>()) {
      final String value = (result as JSString).toDart;
      return value.isEmpty ? null : value;
    }
  } on Object {
    return null;
  }
  return null;
}

/// Probes `__api/capabilities` on the live server to determine whether host
/// chat sending is supported and which project root is active.
Future<LiveCapabilitiesResult> probeLiveCapabilities() async {
  if (_debugProbeCapabilitiesHandler case final handler?) {
    return handler();
  }
  try {
    final Uri uri = _buildLiveApiUri(_kApiCapabilitiesPath);
    final Response response = await window
        .fetch(
          uri.toString().toJS,
          RequestInit(method: _kMethodGet, cache: _kCacheNoStore),
        )
        .toDart;
    if (!response.ok) {
      return (canSendToChat: false, projectRoot: null);
    }
    final String body = (await response.text().toDart).toDart;
    final Object? decoded = jsonDecode(body);
    if (decoded is Map<Object?, Object?>) {
      final bool canSend = decoded[_kCanSendToChatKey] == true;
      final Object? rawRoot = decoded[_kProjectRootKey];
      final String? projectRoot = rawRoot is String && rawRoot.isNotEmpty
          ? rawRoot
          : null;
      return (canSendToChat: canSend, projectRoot: projectRoot);
    }
  } on Object {
    // Fall back to read-only capabilities when the endpoint is unavailable.
  }
  return (canSendToChat: false, projectRoot: null);
}

/// Triggers a preview sync/reload via `POST __api/sync` on the live server.
Future<LiveSyncResult> triggerLiveSync() async {
  if (_debugTriggerSyncHandler case final handler?) {
    return handler();
  }
  final Uri uri = _buildLiveApiUri(_kApiSyncPath);
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

/// Sends the active [selections] and user [message] to the host chat via
/// `POST __api/send-selection`.
Future<void> sendLiveSelectionToChat({
  required String message,
  required List<Map<String, Object?>> selections,
  String? brightness,
  String? previewId,
  String? previewName,
  String? projectRoot,
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
      projectRoot: projectRoot,
      textScale: textScale,
      viewport: viewport,
      zoom: zoom,
    );
    return;
  }
  final Uri baseUri = getBaseUri();
  final String? conversationId =
      await _readSidecarConversationId() ??
      baseUri.queryParameters[_kConversationIdKey];
  final String? resolvedRoot =
      projectRoot ?? baseUri.queryParameters[_kRootParam];
  final payload = <String, Object?>{
    _kMessageKey: message,
    _kSelectionsKey: selections,
    if (conversationId != null && conversationId.isNotEmpty)
      _kConversationIdKey: conversationId,
    if (resolvedRoot != null && resolvedRoot.isNotEmpty)
      _kProjectRootKey: resolvedRoot,
    if (previewId != null && previewId.isNotEmpty) _kPreviewIdKey: previewId,
    if (previewName != null && previewName.isNotEmpty)
      _kPreviewNameKey: previewName,
    if (brightness != null && brightness.isNotEmpty)
      _kBrightnessKey: brightness,
    if (viewport != null && viewport.isNotEmpty) _kViewportKey: viewport,
    if (textScale != null && textScale.isNotEmpty) _kTextScaleKey: textScale,
    if (zoom != null && zoom.isNotEmpty) _kZoomKey: zoom,
  };
  final Uri uri = _buildLiveApiUri(_kApiSendSelectionPath);
  final Response response = await window
      .fetch(
        uri.toString().toJS,
        RequestInit(
          method: _kMethodPost,
          cache: _kCacheNoStore,
          headers:
              <String, String>{_kContentTypeHeader: _kJsonContentType}.jsify()!
                  as HeadersInit,
          body: jsonEncode(payload).toJS,
        ),
      )
      .toDart;
  if (!response.ok) {
    final String body = (await response.text().toDart).toDart;
    String? error;
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is Map<Object?, Object?>) {
        final Object? rawError = decoded[_kErrorKey];
        if (rawError is String && rawError.isNotEmpty) {
          error = rawError;
        }
      }
    } on FormatException {
      error = null;
    }
    throw StateError(
      error ?? 'Failed to send selection (HTTP ${response.status}).',
    );
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

/// Registers an optional test handler for [probeLiveCapabilities].
@visibleForTesting
void debugSetProbeCapabilitiesHandler(
  Future<LiveCapabilitiesResult> Function()? handler,
) {
  _debugProbeCapabilitiesHandler = handler;
}

/// Registers an optional test handler for [triggerLiveSync].
@visibleForTesting
void debugSetTriggerSyncHandler(Future<LiveSyncResult> Function()? handler) {
  _debugTriggerSyncHandler = handler;
}

/// Registers an optional test handler for [sendLiveSelectionToChat].
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
  _debugProbeCapabilitiesHandler = null;
  _debugTriggerSyncHandler = null;
  _debugSendSelectionHandler = null;
}

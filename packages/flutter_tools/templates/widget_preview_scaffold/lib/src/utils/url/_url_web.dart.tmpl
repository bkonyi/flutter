// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// NOTE: originally from package:devtools_app_shared

import 'dart:async';
import 'dart:js_interop';
import 'dart:ui';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:web/web.dart';

import 'url.dart';

const _kActiveKey = 'active';
const _kClearSelectionsMessageType = 'flutter-widget-preview-clear-selections';
const _kIdKey = 'id';
const _kMessageTypeKey = 'type';
const _kSelectionsKey = 'selections';
const _kSelectionsMessageType = 'flutter-widget-preview-selections';
const _kSelectModeKey = 'selectMode';
const _kSetSelectModeMessageType = 'flutter-widget-preview-set-select-mode';
const _kWildcardTargetOrigin = '*';
const _kZoomMessageType = 'flutter-widget-preview-zoom';

typedef _ParentSelectionCommandHandlers = ({
  void Function(String? selectionId) onClearSelections,
  void Function(bool active) onSetSelectMode,
});

var _debugCaptureParentSelections = false;
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
final _debugPostedParentSelections =
    <({bool selectMode, List<Map<String, Object?>> selections})>[];
final _debugSelectionCommandListeners = <_ParentSelectionCommandHandlers>[];

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
/// `history.replaceState` and notifies any embedding parent shell.
void notifyEmbedZoomChanged(double zoom) {
  final String updatedFragment = buildUpdatedZoomFragment(
    getUrlFragment(),
    zoom,
  );
  if (_debugUrlFragmentOverride != null) {
    _debugUrlFragmentOverride = updatedFragment;
  }
  window.history.replaceState(null, '', '#$updatedFragment');
  final CrossOriginWindow? parentWindow = window.parentCrossOrigin;
  if (parentWindow != null && parentWindow.unsafeWindow != window) {
    parentWindow.postMessage(
      <String, Object>{
        _kMessageTypeKey: _kZoomMessageType,
        EmbedPreviewParams.kZoomParam: zoom,
      }.jsify(),
      _kWildcardTargetOrigin.toJS,
    );
  }
}

/// Posts the current [selectMode] and [selections] list to any embedding
/// same-origin parent window.
void notifyParentSelections({
  required List<Map<String, Object?>> selections,
  required bool selectMode,
}) {
  if (_debugCaptureParentSelections) {
    _debugPostedParentSelections.add((
      selectMode: selectMode,
      selections: List<Map<String, Object?>>.unmodifiable(selections),
    ));
  }
  final CrossOriginWindow? parentWindow = window.parentCrossOrigin;
  if (parentWindow != null && parentWindow.unsafeWindow != window) {
    parentWindow.postMessage(
      <String, Object?>{
        _kMessageTypeKey: _kSelectionsMessageType,
        _kSelectModeKey: selectMode,
        _kSelectionsKey: selections,
      }.jsify(),
      window.location.origin.toJS,
    );
  }
}

/// Subscribes to same-origin parent selection commands (`set-select-mode` and
/// `clear-selections`), returning a callback that cancels the listener.
VoidCallback listenToParentSelectionCommands({
  required void Function(String? selectionId) onClearSelections,
  required void Function(bool active) onSetSelectMode,
}) {
  final _ParentSelectionCommandHandlers? debugHandlers =
      _debugCaptureParentSelections
      ? (onClearSelections: onClearSelections, onSetSelectMode: onSetSelectMode)
      : null;
  if (debugHandlers != null) {
    _debugSelectionCommandListeners.add(debugHandlers);
  }
  final StreamSubscription<MessageEvent> subscription = EventStreamProviders
      .messageEvent
      .forTarget(window)
      .listen((MessageEvent event) {
        if (event.origin != window.location.origin) {
          return;
        }
        final Object? dartData = event.data?.dartify();
        if (dartData is! Map<Object?, Object?>) {
          return;
        }
        final Object? messageType = dartData[_kMessageTypeKey];
        if (messageType == _kSetSelectModeMessageType) {
          if (dartData[_kActiveKey] case final bool active) {
            onSetSelectMode(active);
          }
        } else if (messageType == _kClearSelectionsMessageType) {
          final Object? rawId = dartData[_kIdKey];
          final String? selectionId = rawId is String && rawId.isNotEmpty
              ? rawId
              : null;
          onClearSelections(selectionId);
        }
      });
  return () {
    if (debugHandlers != null) {
      _debugSelectionCommandListeners.remove(debugHandlers);
    }
    unawaited(subscription.cancel());
  };
}

/// Number of times [reloadWindow] has been invoked in tests.
@visibleForTesting
int get debugReloadCount => _debugReloadCount;

/// Selection update payloads emitted via [notifyParentSelections] in tests.
@visibleForTesting
List<({bool selectMode, List<Map<String, Object?>> selections})>
get debugPostedParentSelections =>
    List<
      ({bool selectMode, List<Map<String, Object?>> selections})
    >.unmodifiable(_debugPostedParentSelections);

/// Simulates a parent `flutter-widget-preview-set-select-mode` command in tests.
@visibleForTesting
void debugDispatchParentSetSelectMode(bool active) {
  for (final _ParentSelectionCommandHandlers listener
      in List<_ParentSelectionCommandHandlers>.of(
        _debugSelectionCommandListeners,
      )) {
    listener.onSetSelectMode(active);
  }
}

/// Simulates a parent `flutter-widget-preview-clear-selections` command in tests.
@visibleForTesting
void debugDispatchParentClearSelections({String? id}) {
  final String? normalizedId = id != null && id.isNotEmpty ? id : null;
  for (final _ParentSelectionCommandHandlers listener
      in List<_ParentSelectionCommandHandlers>.of(
        _debugSelectionCommandListeners,
      )) {
    listener.onClearSelections(normalizedId);
  }
}

/// Updates the simulated URL fragment (and optional [baseUri]) for tests and
/// notifies [onUrlFragmentChange] listeners.
@visibleForTesting
void debugSetUrlFragment(String fragment, {Uri? baseUri}) {
  _debugCaptureParentSelections = true;
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

/// Resets all URL test overrides and counters.
@visibleForTesting
void debugResetUrlTestState() {
  _debugCaptureParentSelections = false;
  _debugUrlFragmentOverride = null;
  _debugBaseUriOverride = null;
  _debugReloadCount = 0;
  _debugOnReloadCallback = null;
  _debugPostedParentSelections.clear();
  _debugSelectionCommandListeners.clear();
}

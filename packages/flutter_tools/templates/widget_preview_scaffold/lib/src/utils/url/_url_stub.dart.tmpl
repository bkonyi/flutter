// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// NOTE: originally from package:devtools_app_shared

import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'url.dart';

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
var _debugReloadCount = 0;
VoidCallback? _debugOnReloadCallback;
final _debugPostedParentSelections =
    <({bool selectMode, List<Map<String, Object?>> selections})>[];
final _debugSelectionCommandListeners = <_ParentSelectionCommandHandlers>[];

Map<String, String> loadQueryParams() => <String, String>{};

/// Gets the URL from the browser.
///
/// Returns null for non-web platforms.
String? getWebUrl() => null;

/// Performs a web redirect using window.location.replace().
///
/// No-op for non-web platforms.
// Unused parameter lint doesn't make sense for stub files.
void webRedirect(String url) {}

/// Updates the query parameter with [key] to the new [value], and optionally
/// reloads the page when [reload] is true.
///
/// No-op for non-web platforms.
void updateQueryParameter(String key, String? value, {bool reload = false}) {}

/// Returns the current URL fragment without any leading `'#'`, or a test
/// override set via [debugSetUrlFragment].
String getUrlFragment() => _debugUrlFragmentOverride ?? Uri.base.fragment;

/// Returns the current base [Uri] for resolving relative proxy paths.
Uri getBaseUri() => _debugBaseUriOverride ?? Uri.base;

/// Broadcasts updated URL fragments whenever the browser hash changes.
Stream<String> get onUrlFragmentChange => _debugFragmentChangeController.stream;

/// Reloads the current browser window, preserving the URL fragment.
void reloadWindow() {
  _debugReloadCount++;
  _debugOnReloadCallback?.call();
}

/// Replaces the current embed URL fragment without adding a browser history
/// entry and notifies [onUrlFragmentChange] listeners.
void replaceEmbedUrl(String fragment) {
  final String normalized = fragment.startsWith('#')
      ? fragment.substring(1)
      : fragment;
  _debugUrlFragmentOverride = normalized;
  _debugFragmentChangeController.add(normalized);
}

/// Synchronizes interactive embed [zoom] changes with the simulated test URL
/// fragment when active; no-op for non-web platforms otherwise.
void notifyEmbedZoomChanged(double zoom) {
  if (_debugUrlFragmentOverride != null) {
    _debugUrlFragmentOverride = buildUpdatedZoomFragment(
      getUrlFragment(),
      zoom,
    );
  }
}

/// Posts the current [selectMode] and [selections] list to any embedding
/// same-origin parent window, recording payloads when test URL overrides are
/// active.
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
}

/// Subscribes to same-origin parent selection commands (`set-select-mode` and
/// `clear-selections`), returning a callback that removes the listener.
VoidCallback listenToParentSelectionCommands({
  required void Function(String? selectionId) onClearSelections,
  required void Function(bool active) onSetSelectMode,
}) {
  if (!_debugCaptureParentSelections) {
    return () {};
  }
  final _ParentSelectionCommandHandlers handlers = (
    onClearSelections: onClearSelections,
    onSetSelectMode: onSetSelectMode,
  );
  _debugSelectionCommandListeners.add(handlers);
  return () {
    _debugSelectionCommandListeners.remove(handlers);
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

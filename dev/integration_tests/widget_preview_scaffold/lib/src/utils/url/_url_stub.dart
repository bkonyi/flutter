// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// NOTE: originally from package:devtools_app_shared

import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'url.dart';

String? _debugUrlFragmentOverride;
Uri? _debugBaseUriOverride;
final _debugFragmentChangeController = StreamController<String>.broadcast(
  sync: true,
);
var _debugReloadCount = 0;
VoidCallback? _debugOnReloadCallback;

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

/// Resets all URL test overrides and counters.
@visibleForTesting
void debugResetUrlTestState() {
  _debugUrlFragmentOverride = null;
  _debugBaseUriOverride = null;
  _debugReloadCount = 0;
  _debugOnReloadCallback = null;
}

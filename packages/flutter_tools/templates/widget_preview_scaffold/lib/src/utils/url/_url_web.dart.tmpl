// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// NOTE: originally from package:devtools_app_shared

import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:web/web.dart';

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

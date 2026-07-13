// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter_tools_extension/flutter_tools_extension.dart';

import '../base/context.dart';
import '../base/logger.dart';
import '../features.dart';
import 'diagnostics.dart';
import 'extension_discovery.dart';

/// Manages active tool extension isolate connections and exposes capability proxies.
class ExtensionManager {
  /// Creates an [ExtensionManager] targeting the active [hostPlatform].
  ExtensionManager({
    required this.hostPlatform,
    required Logger logger,
    List<ExtensionEntryPoint> entryPoints = const <ExtensionEntryPoint>[],
    ExtensionDiscovery? discovery,
    FeatureFlags? featureFlags,
  }) : _logger = logger,
       _entryPoints = entryPoints,
       _discovery = discovery ?? ExtensionDiscovery(logger: logger),
       _featureFlags = featureFlags ?? context.get<FeatureFlags>()!;

  /// The active host operating system platform (e.g. `'linux'`, `'macos'`, `'windows'`).
  final String hostPlatform;
  final Logger _logger;
  final ExtensionDiscovery _discovery;
  final List<ExtensionEntryPoint> _entryPoints;
  final FeatureFlags _featureFlags;
  Future<void>? _initFuture;

  /// Ensures entrypoints are initialized; idempotent.
  Future<void> ensureInitialized() {
    return _initFuture ??= _doInitialize();
  }

  Future<void> _doInitialize() async {
    if (!_featureFlags.isToolExtensionsEnabled) {
      return;
    }
    if (_entryPoints.isNotEmpty) {
      await initialize(entryPoints: _entryPoints);
    }
  }

  /// Active extension connections compatible with [hostPlatform].
  List<ExtensionConnection> get connections => _discovery.connections;

  /// Spawns entrypoints without host OS checks; disposes any extension that reports
  /// it does not support [hostPlatform].
  Future<void> initialize({
    List<ExtensionEntryPoint> entryPoints = const <ExtensionEntryPoint>[],
  }) async {
    _logger.printTrace(
      'ExtensionManager initializing for platform "$hostPlatform" with ${entryPoints.length} entrypoint(s).',
    );
    for (final entryPoint in entryPoints) {
      final ExtensionConnection connection = await ExtensionConnection.spawn(
        entryPoint,
        logger: _logger,
      );
      if (connection.capabilities.supportsHostPlatform(hostPlatform)) {
        _logger.printTrace(
          'Extension connection supported on host platform "$hostPlatform"; registering.',
        );
        _discovery.registerConnection(connection);
      } else {
        _logger.printTrace(
          'Extension connection does not support host platform "$hostPlatform" '
          '(supported platforms: ${connection.capabilities.supportedPlatforms}); disposing connection.',
        );
        await connection.dispose();
      }
    }
  }

  /// Active [DiagnosticsExtension] proxies for extensions supporting `'diagnostics'`.
  List<DiagnosticsExtension> get diagnosticsExtensions {
    _logger.printTrace('ExtensionManager querying active diagnosticsExtensions.');
    return _discovery.connections
        .where(
          (ExtensionConnection c) =>
              c.capabilities.services.contains(DiagnosticsExtension.serviceNamespace),
        )
        .map<DiagnosticsExtension>(
          (ExtensionConnection c) => DiagnosticsExtensionClient(c, logger: _logger),
        )
        .toList();
  }

  /// Disposes all active extension isolate connections.
  Future<void> dispose() async {
    _logger.printTrace('ExtensionManager disposing all active connections.');
    await _discovery.dispose();
  }
}

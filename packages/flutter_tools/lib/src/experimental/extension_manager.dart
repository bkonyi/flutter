// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter_tools_extension/flutter_tools_extension.dart';

import '../base/file_system.dart';
import '../base/logger.dart';
import '../base/os.dart';
import '../features.dart';
import 'config.dart';
import 'diagnostics.dart';
import 'extension_device_manager.dart';
import 'extension_discovery.dart';
import 'extension_manifest.dart';

/// Manages active tool extension isolate connections and exposes capability proxies.
class ExtensionManager {
  /// Creates an [ExtensionManager] configured with explicit dependencies.
  ExtensionManager({
    required this.hostPlatform,
    required Logger logger,
    required FileSystem fileSystem,
    required FeatureFlags featureFlags,
    List<ExtensionEntryPoint> entryPoints = const <ExtensionEntryPoint>[],
    ExtensionDiscovery? discovery,
    ExtensionManifestFinder? manifestFinder,
  }) : _logger = logger,
       _fs = fileSystem,
       _featureFlags = featureFlags,
       _entryPoints = List<ExtensionEntryPoint>.from(entryPoints),
       _discovery = discovery ?? ExtensionDiscovery(logger: logger),
       _manifestFinder =
           manifestFinder ?? ExtensionManifestFinder(fileSystem: fileSystem, logger: logger);

  /// The active [HostPlatform].
  final HostPlatform hostPlatform;
  final Logger _logger;
  final FileSystem _fs;

  /// The [FileSystem] used by this manager.
  FileSystem get fileSystem => _fs;
  final FeatureFlags _featureFlags;
  final List<ExtensionEntryPoint> _entryPoints;
  final ExtensionDiscovery _discovery;
  final ExtensionManifestFinder _manifestFinder;

  /// The [ExtensionManifestFinder] used to discover extension manifests.
  ExtensionManifestFinder get manifestFinder => _manifestFinder;

  /// Active extension connections compatible with [hostPlatform].
  List<ExtensionConnection> get connections => _discovery.connections;

  /// The operating system name of the host platform (e.g. `'linux'`, `'macos'`, `'windows'`).
  String get hostPlatformName => switch (hostPlatform) {
    HostPlatform.darwin_x64 || HostPlatform.darwin_arm64 => 'macos',
    HostPlatform.linux_x64 || HostPlatform.linux_arm64 || HostPlatform.linux_riscv64 => 'linux',
    HostPlatform.windows_x64 || HostPlatform.windows_arm64 => 'windows',
  };

  final List<DiagnosticsExtension> _diagnosticsExtensions = <DiagnosticsExtension>[];
  final List<ConfigurationExtension> _configurationExtensions = <ConfigurationExtension>[];
  Future<void>? _initFuture;
  bool get isInitialized => _isInitialized;
  bool _isInitialized = false;

  /// Ensures entrypoints are initialized; idempotent.
  Future<void> ensureInitialized() {
    return _initFuture ??= _doInitialize();
  }

  Future<void> _doInitialize() async {
    if (!_featureFlags.isToolExtensionsEnabled) {
      _isInitialized = true;
      return;
    }
    if (_entryPoints.isNotEmpty) {
      await initialize(entryPoints: _entryPoints);
    } else {
      _isInitialized = true;
    }
  }

  /// Spawns entrypoints without host OS checks; disposes any extension that reports
  /// it does not support [hostPlatform].
  Future<void> initialize({
    List<ExtensionEntryPoint> entryPoints = const <ExtensionEntryPoint>[],
  }) async {
    _logger.printTrace(
      'ExtensionManager initializing for platform "$hostPlatformName" with ${entryPoints.length} entrypoint(s).',
    );
    for (final entryPoint in entryPoints) {
      final ExtensionConnection connection = await ExtensionConnection.spawn(
        entryPoint,
        logger: _logger,
      );
      if (connection.capabilities.supportsHostPlatform(hostPlatformName) ||
          connection.capabilities.supportsHostPlatform(hostPlatform.cliName)) {
        _logger.printTrace(
          'Extension connection supported on host platform "$hostPlatformName"; registering.',
        );
        _discovery.registerConnection(connection);
      } else {
        _logger.printTrace(
          'Extension connection does not support host platform "$hostPlatformName" '
          '(supported platforms: ${connection.capabilities.supportedPlatforms}); disposing connection.',
        );
        await connection.dispose();
      }
    }
    _diagnosticsExtensions.clear();
    _configurationExtensions.clear();
    for (final ExtensionConnection connection in _discovery.connections) {
      if (connection.capabilities.services.contains(DiagnosticsExtension.serviceNamespace)) {
        final client = DiagnosticsExtensionClient(connection, logger: _logger);
        await client.fetchTitle();
        _diagnosticsExtensions.add(client);
      }
      if (connection.capabilities.services.contains(ConfigurationExtension.serviceNamespace)) {
        final client = ConfigurationExtensionClient(connection, logger: _logger);
        await client.fetchTitle();
        _configurationExtensions.add(client);
      }
    }
    _isInitialized = true;
  }

  /// Active [DiagnosticsExtension] proxies for extensions supporting `'diagnostics'`.
  List<DiagnosticsExtension> get diagnosticsExtensions {
    assert(
      _isInitialized,
      'ExtensionManager.ensureInitialized() must be called before accessing diagnosticsExtensions.',
    );
    return List<DiagnosticsExtension>.unmodifiable(_diagnosticsExtensions);
  }

  /// Active [ConfigurationExtension] proxies for extensions supporting `'configuration'`.
  List<ConfigurationExtension> get configurationExtensions {
    assert(
      _isInitialized,
      'ExtensionManager.ensureInitialized() must be called before accessing configurationExtensions.',
    );
    return List<ConfigurationExtension>.unmodifiable(_configurationExtensions);
  }

  /// Active [DeviceService] proxies for extensions supporting `'device'`.
  List<DeviceService> get deviceExtensions {
    _logger.printTrace('ExtensionManager querying active deviceExtensions.');
    return _discovery.connections
        .where(
          (ExtensionConnection c) =>
              c.capabilities.services.contains(DeviceService.serviceNamespace),
        )
        .map<DeviceService>((ExtensionConnection c) => ExtensionDeviceClient(c, logger: _logger))
        .toList();
  }

  /// Disposes all active extension isolate connections.
  Future<void> dispose() async {
    _logger.printTrace('ExtensionManager disposing all active connections.');
    _diagnosticsExtensions.clear();
    _configurationExtensions.clear();
    _isInitialized = false;
    _initFuture = null;
    await _discovery.dispose();
  }
}

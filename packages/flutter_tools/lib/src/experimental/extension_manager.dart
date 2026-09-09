// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';

import '../base/file_system.dart';
import '../base/logger.dart';
import '../features.dart';
import 'config.dart';
import 'diagnostics.dart';
import 'extension_cache.dart';
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
    ExtensionCapabilityCacheManager? cacheManager,
    List<ExtensionEntryPoint> entryPoints = const <ExtensionEntryPoint>[],
    ExtensionDiscovery? discovery,
    ExtensionManifestFinder? manifestFinder,
    ExtensionUriSpawner spawner = ExtensionConnection.spawnUri,
  }) : _logger = logger,
       _fs = fileSystem,
       _featureFlags = featureFlags,
       _cacheManager =
           cacheManager ?? ExtensionCapabilityCacheManager(fileSystem: fileSystem, logger: logger),
       _discovery = discovery ?? ExtensionDiscovery(logger: logger),
       _entryPoints = List<ExtensionEntryPoint>.from(entryPoints),
       _manifestFinder =
           manifestFinder ?? ExtensionManifestFinder(fileSystem: fileSystem, logger: logger),
       _spawner = spawner;

  /// The active [HostPlatform].
  final HostPlatform hostPlatform;
  final Logger _logger;
  final FileSystem _fs;

  /// The [FileSystem] used by this manager.
  FileSystem get fileSystem => _fs;
  final FeatureFlags _featureFlags;
  final ExtensionCapabilityCacheManager _cacheManager;
  final ExtensionDiscovery _discovery;
  final List<ExtensionEntryPoint> _entryPoints;
  final ExtensionManifestFinder _manifestFinder;
  final ExtensionUriSpawner _spawner;

  /// The [ExtensionCapabilityCacheManager] managing capability cache on disk.
  ExtensionCapabilityCacheManager get cacheManager => _cacheManager;

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
  final Set<String> _spawnedExtensionNames = <String>{};
  final Set<String> _failedExtensionNames = <String>{};
  bool _entryPointsSpawned = false;
  bool get isInitialized => _isInitialized;
  bool _isInitialized = false;

  /// Ensures entrypoints and discovered extensions are initialized; idempotent per service requirement.
  Future<void> ensureInitialized({Set<String>? requiredServices, Directory? startDir}) async {
    if (!_featureFlags.isToolExtensionsEnabled) {
      _isInitialized = true;
      return;
    }
    await _doInitialize(requiredServices: requiredServices, startDir: startDir);
  }

  Future<void> _doInitialize({Set<String>? requiredServices, Directory? startDir}) async {
    if (_entryPoints.isNotEmpty && !_entryPointsSpawned) {
      _entryPointsSpawned = true;
      await initialize(entryPoints: _entryPoints);
    }

    final List<File> manifestFiles = _manifestFinder.findManifestFiles(startDir);
    if (manifestFiles.isNotEmpty) {
      final Map<String, ({ExtensionDeclaration declaration, File manifestFile})> declarations =
          _manifestFinder.loadMergedDeclarationsWithFiles(manifestFiles);
      final loadedCaches = <Directory, Map<String, ExtensionCapabilityCacheEntry>>{};

      for (final MapEntry(key: extensionName, value: (:declaration, :manifestFile))
          in declarations.entries) {
        if (!declaration.enabled) {
          _logger.printTrace('Extension "$extensionName" is disabled in manifest; skipping.');
          continue;
        }
        if (_failedExtensionNames.contains(extensionName)) {
          _logger.printTrace('Extension "$extensionName" previously failed; skipping.');
          continue;
        }
        if (declaration.supportedPlatforms != null &&
            !declaration.supportedPlatforms!.contains(hostPlatformName) &&
            !declaration.supportedPlatforms!.contains(hostPlatform.cliName)) {
          _logger.printTrace(
            'Extension "$extensionName" does not support host platform "$hostPlatformName"; skipping.',
          );
          continue;
        }
        if (_spawnedExtensionNames.contains(extensionName)) {
          continue;
        }

        final Uri? entrypointUri = _manifestFinder.resolveExtensionEntrypoint(
          declaration,
          manifestFile,
        );
        if (entrypointUri == null) {
          _logger.printTrace(
            'Could not resolve entrypoint for extension "$extensionName"; skipping.',
          );
          continue;
        }

        final File entrypointFile = _fs.file(entrypointUri);
        final Map<String, ExtensionCapabilityCacheEntry> cache = loadedCaches.putIfAbsent(
          manifestFile.parent,
          () => _cacheManager.loadCache(manifestFile.parent),
        );
        final ExtensionCapabilityCacheEntry? cachedEntry = cache[extensionName];
        final bool isCacheValid =
            cachedEntry != null &&
            _cacheManager.isCacheValid(cachedEntry, entrypointFile, manifestFile: manifestFile);

        if (isCacheValid) {
          if (!_supportsPlatform(cachedEntry.capabilities)) {
            _logger.printTrace(
              'Cached extension "$extensionName" does not support host platform "$hostPlatformName"; skipping.',
            );
            continue;
          }
          if (requiredServices != null) {
            final bool providesRequiredService = cachedEntry.capabilities.services.any(
              requiredServices.contains,
            );
            if (!providesRequiredService) {
              _logger.printTrace(
                'Cached extension "$extensionName" does not provide required services $requiredServices; skipping isolate spawn.',
              );
              continue;
            }
          }
        }

        try {
          final File? packageConfigFile = _manifestFinder.findPackageConfig(manifestFile.parent);
          _logger.printTrace(
            'Spawning isolate for extension "$extensionName" at $entrypointUri...',
          );
          final ExtensionConnection connection = await _spawner(
            entrypointUri,
            logger: _logger,
            packageConfigUri: packageConfigFile?.uri,
          );
          _spawnedExtensionNames.add(extensionName);

          final int entrypointModifiedMs = entrypointFile.existsSync()
              ? entrypointFile.statSync().modified.millisecondsSinceEpoch
              : 0;
          final int manifestModifiedMs = manifestFile.existsSync()
              ? manifestFile.statSync().modified.millisecondsSinceEpoch
              : 0;
          _cacheManager.updateEntry(
            ExtensionCapabilityCacheEntry(
              capabilities: connection.capabilities,
              entrypointUri: entrypointUri,
              extensionName: extensionName,
              modifiedTimeMs: entrypointModifiedMs,
              manifestModifiedTimeMs: manifestModifiedMs,
            ),
            manifestFile.parent,
          );

          await _registerOrDisposeConnection(connection, extensionName: extensionName);
        } on TimeoutException {
          _failedExtensionNames.add(extensionName);
          _logger.printWarning(
            'Handshake with tool extension "$extensionName" timed out; disabling for this session.',
          );
        } on Object catch (error, stackTrace) {
          _failedExtensionNames.add(extensionName);
          _logger.printWarning('Failed to spawn tool extension "$extensionName": $error');
          _logger.printTrace('Extension "$extensionName" spawn error details: $error\n$stackTrace');
        }
      }
    }

    _isInitialized = true;
  }

  bool _supportsPlatform(ToolExtensionCapabilities capabilities) {
    return capabilities.supportsHostPlatform(hostPlatformName) ||
        capabilities.supportsHostPlatform(hostPlatform.cliName);
  }

  Future<void> _registerOrDisposeConnection(
    ExtensionConnection connection, {
    String? extensionName,
  }) async {
    if (_supportsPlatform(connection.capabilities)) {
      _logger.printTrace(
        'Extension ${extensionName != null ? '"$extensionName" ' : ''}connection supported on "$hostPlatformName"; registering.',
      );
      _discovery.registerConnection(connection);
      await _registerClientProxies(connection);
    } else {
      _logger.printTrace(
        'Extension ${extensionName != null ? '"$extensionName" ' : ''}does not support "$hostPlatformName" '
        '(supported platforms: ${connection.capabilities.supportedPlatforms}); disposing connection.',
      );
      await connection.dispose();
    }
  }

  Future<void> _registerClientProxies(ExtensionConnection connection) async {
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
      await _registerOrDisposeConnection(connection);
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
    _spawnedExtensionNames.clear();
    _failedExtensionNames.clear();
    _isInitialized = false;
    _entryPointsSpawned = false;
    await _discovery.dispose();
  }
}

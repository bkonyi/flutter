// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';

import '../base/common.dart';
import '../base/file_system.dart';
import '../base/logger.dart';
import '../features.dart';
import 'extension_discovery.dart';
import 'extension_manager.dart';

/// Coordinates querying, downloading, and verifying custom artifacts required by
/// active tool extensions.
base class ExtensionArtifactManager {
  /// Creates an [ExtensionArtifactManager] instance.
  ExtensionArtifactManager({
    required ExtensionManager extensionManager,
    required FeatureFlags featureFlags,
    required FileSystem fileSystem,
    required Logger logger,
  }) : _extensionManager = extensionManager,
       _featureFlags = featureFlags,
       _fileSystem = fileSystem,
       _logger = logger;

  final ExtensionManager _extensionManager;
  final FeatureFlags _featureFlags;
  final FileSystem _fileSystem;
  final Logger _logger;

  /// Resolves the artifact destination directory for the given [extensionName].
  Directory getArtifactDirectory(String extensionName, {Uri? projectRoot}) {
    final Directory rootDir = projectRoot != null
        ? _fileSystem.directory(projectRoot)
        : _fileSystem.currentDirectory;
    return rootDir
        .childDirectory('.dart_tool')
        .childDirectory('flutter_tools')
        .childDirectory('artifacts')
        .childDirectory(extensionName);
  }

  /// Queries all active extension connections supporting [ArtifactService] and
  /// returns a mapping of extension names to their declared artifact dependencies.
  Future<Map<String, Set<ArtifactDependency>>> getArtifactDependencies() async {
    if (!_featureFlags.isToolExtensionsEnabled) {
      return const <String, Set<ArtifactDependency>>{};
    }
    await _extensionManager.ensureInitialized();
    final result = <String, Set<ArtifactDependency>>{};
    for (final ExtensionConnection connection in _extensionManager.connections) {
      if (!connection.capabilities.services.contains(ArtifactService.serviceNamespace)) {
        continue;
      }
      final String extensionName = connection.capabilities.extensionName ?? 'default';
      final client = ArtifactServiceClient(connection.sendRequest);
      try {
        final Set<ArtifactDependency> artifacts = await client.fetchArtifacts();
        result[extensionName] = artifacts;
      } on Object catch (e) {
        _logger.printError('Failed to fetch artifacts from extension "$extensionName": $e');
      }
    }
    return result;
  }

  /// Ensures all artifact dependencies for active extensions are downloaded and verified.
  Future<void> ensureArtifactsDownloaded({
    BuildMode buildMode = BuildMode.debug,
    bool force = false,
    HostPlatform? hostPlatform,
    Uri? projectRoot,
    TargetPlatform? targetPlatform,
  }) async {
    if (!_featureFlags.isToolExtensionsEnabled) {
      return;
    }
    await _extensionManager.ensureInitialized();
    final HostPlatform currentHostPlatform = hostPlatform ?? _extensionManager.hostPlatform;

    for (final ExtensionConnection connection in _extensionManager.connections) {
      if (!connection.capabilities.services.contains(ArtifactService.serviceNamespace)) {
        continue;
      }
      final String extensionName = connection.capabilities.extensionName ?? 'default';
      final client = ArtifactServiceClient(connection.sendRequest);
      final Set<ArtifactDependency> artifacts;
      try {
        artifacts = await client.fetchArtifacts();
      } on Object catch (e) {
        _logger.printError('Failed to query artifacts for extension "$extensionName": $e');
        continue;
      }

      final Directory artifactDir = getArtifactDirectory(extensionName, projectRoot: projectRoot);
      if (!artifactDir.existsSync()) {
        artifactDir.createSync(recursive: true);
      }

      final missingOrStaleArtifacts = <String>{};
      for (final dependency in artifacts) {
        if (targetPlatform != null &&
            dependency.targetPlatform.isNotEmpty &&
            dependency.targetPlatform != targetPlatform.name) {
          continue;
        }

        final File artifactFile = artifactDir.childFile(dependency.name);
        if (force || !artifactFile.existsSync()) {
          missingOrStaleArtifacts.add(dependency.name);
          continue;
        }

        final String? expectedHash =
            dependency.sha256Checksums[currentHostPlatform.cliName] ??
            dependency.sha256Checksums[currentHostPlatform.platformName] ??
            dependency.sha256Checksums[dependency.name] ??
            dependency.sha256Checksums.values.firstOrNull;

        if (expectedHash != null) {
          final List<int> bytes = artifactFile.readAsBytesSync();
          final actualHash = sha256.convert(bytes).toString();
          if (actualHash.toLowerCase() != expectedHash.toLowerCase()) {
            _logger.printTrace(
              'Checksum mismatch for artifact "${dependency.name}" '
              '(expected: $expectedHash, got: $actualHash). Re-downloading.',
            );
            missingOrStaleArtifacts.add(dependency.name);
          }
        }
      }

      if (missingOrStaleArtifacts.isEmpty) {
        _logger.printTrace('All artifacts for extension "$extensionName" are up to date.');
        continue;
      }

      _logger.printStatus(
        'Downloading ${missingOrStaleArtifacts.length} artifact(s) for extension "$extensionName"...',
      );

      final TargetPlatform currentTargetPlatform = targetPlatform ?? TargetPlatform.linux_x64;
      await client.downloadArtifacts(
        missingOrStaleArtifacts,
        buildMode: buildMode,
        destinationDirectory: artifactDir.uri,
        hostPlatform: currentHostPlatform,
        targetPlatform: currentTargetPlatform,
      );

      for (final dependency in artifacts) {
        if (!missingOrStaleArtifacts.contains(dependency.name)) {
          continue;
        }
        final File artifactFile = artifactDir.childFile(dependency.name);
        if (!artifactFile.existsSync()) {
          throwToolExit(
            'Expected artifact "${dependency.name}" was not found after downloading for extension "$extensionName".',
          );
        }
        final String? expectedHash =
            dependency.sha256Checksums[currentHostPlatform.cliName] ??
            dependency.sha256Checksums[currentHostPlatform.platformName] ??
            dependency.sha256Checksums[dependency.name] ??
            dependency.sha256Checksums.values.firstOrNull;

        if (expectedHash != null) {
          final List<int> bytes = artifactFile.readAsBytesSync();
          final actualHash = sha256.convert(bytes).toString();
          if (actualHash.toLowerCase() != expectedHash.toLowerCase()) {
            artifactFile.deleteSync();
            throwToolExit(
              'SHA-256 verification failed for artifact "${dependency.name}" from extension "$extensionName" '
              '(expected: $expectedHash, got: $actualHash).',
            );
          }
        }
      }
    }
  }

  /// Pre-caches artifacts for all active extensions.
  Future<void> precache({
    bool force = false,
    HostPlatform? hostPlatformOverride,
    Uri? projectRoot,
    TargetPlatform? targetPlatformOverride,
  }) async {
    _logger.printTrace('Pre-caching tool extension artifacts...');
    await ensureArtifactsDownloaded(
      force: force,
      hostPlatform: hostPlatformOverride,
      projectRoot: projectRoot,
      targetPlatform: targetPlatformOverride,
    );
  }
}

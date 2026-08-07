// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';

import '../base/logger.dart';
import '../features.dart';
import 'extension_discovery.dart';
import 'extension_manager.dart';

/// Manages querying build targets and running custom builds from extension isolates.
base class ExtensionBuildManager {
  /// Creates an [ExtensionBuildManager] instance.
  ExtensionBuildManager({
    required ExtensionManager extensionManager,
    required Logger logger,
    required FeatureFlags featureFlags,
  }) : _extensionManager = extensionManager,
       _logger = logger,
       _featureFlags = featureFlags;

  final ExtensionManager _extensionManager;
  final Logger _logger;
  final FeatureFlags _featureFlags;

  List<ExtensionBuildTarget>? _cachedTargets;
  final Map<String, ExtensionConnection> _targetToConnection = <String, ExtensionConnection>{};

  /// Retrieve the cached build targets synchronously.
  List<ExtensionBuildTarget> get cachedTargets => _cachedTargets ?? const <ExtensionBuildTarget>[];

  /// Retrieve build targets by routing `build.getBuildTargets` to active tool extensions.
  Future<List<ExtensionBuildTarget>> getBuildTargets() async {
    if (!_featureFlags.isToolExtensionsEnabled) {
      return const <ExtensionBuildTarget>[];
    }
    if (_cachedTargets != null) {
      return _cachedTargets!;
    }

    await _extensionManager.ensureInitialized();

    final targets = <ExtensionBuildTarget>[];
    _targetToConnection.clear();
    final connections = <ExtensionConnection>[
      for (final connection in _extensionManager.connections)
        if (connection.capabilities.services.contains(BuildService.serviceNamespace)) connection,
    ];

    for (final connection in connections) {
      try {
        final rawResult = (await connection
            .sendRequest(BuildService.getBuildTargetsMethod)
            .timeout(const Duration(seconds: 5)))! as List<Object?>;
        for (final Map<String, Object?> targetMap in rawResult.cast<Map<String, Object?>>()) {
          final target = ExtensionBuildTarget.fromJson(targetMap);
          targets.add(target);
          _targetToConnection[target.name] = connection;
        }
      } on Object catch (e) {
        _logger.printError(
          'Failed to get results from extension for ${BuildService.getBuildTargetsMethod}: $e',
        );
      }
    }

    _cachedTargets = targets;
    return targets;
  }

  /// Triggers a custom build for the given [targetName] by routing to the active extension.
  Future<ExtensionBuildResult> build({
    required String targetName,
    required String projectRoot,
    required String mainPath,
    required String buildMode,
    required String outputDir,
    required String buildDir,
    required Map<String, String> resolvedArtifacts,
  }) async {
    if (!_featureFlags.isToolExtensionsEnabled) {
      return const ExtensionBuildResult.failure(message: 'Tool extensions are disabled.');
    }

    await _extensionManager.ensureInitialized();

    if (_cachedTargets == null) {
      await getBuildTargets();
    }

    final ExtensionConnection? connection = _targetToConnection[targetName];
    if (connection == null) {
      return ExtensionBuildResult.failure(
        message: 'No extension found to handle build target $targetName.',
      );
    }

    try {
      final Object? result = await connection
          .sendRequest(BuildService.buildMethod, <String, Object?>{
            'targetName': targetName,
            'projectRoot': projectRoot,
            'mainPath': mainPath,
            'buildMode': buildMode,
            'outputDir': outputDir,
            'buildDir': buildDir,
            'resolvedArtifacts': resolvedArtifacts,
          }, const Duration(minutes: 5));
      return ExtensionBuildResult.fromJson(result! as Map<String, Object?>);
    } on Object catch (e) {
      _logger.printError('Failed to run build from extension: $e');
      return ExtensionBuildResult.failure(message: e.toString());
    }

  }
}

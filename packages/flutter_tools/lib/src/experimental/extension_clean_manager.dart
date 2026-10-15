// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';

import '../base/file_system.dart';
import '../base/logger.dart';
import '../features.dart';
import '../project.dart';
import 'extension_discovery.dart';
import 'extension_manager.dart';

/// Manages delegating project-specific `flutter clean` operations to tool extensions.
class ExtensionCleanManager {
  ExtensionCleanManager({
    required this._extensionManager,
    required this._featureFlags,
    required this._logger,
  });

  final ExtensionManager _extensionManager;
  final FeatureFlags _featureFlags;
  final Logger _logger;

  /// Invokes [CleanService.clean] on all active tool extensions for [project].
  Future<void> cleanProject(FlutterProject project, {Directory? buildDirectory}) async {
    if (!_featureFlags.isToolExtensionsEnabled) {
      return;
    }

    try {
      await _extensionManager.ensureInitialized();
    } on Object catch (e) {
      _logger.printTrace('Failed to initialize extension manager for clean: $e');
      return;
    }

    final cleanExtensions = <ExtensionConnection>[
      for (final ext in _extensionManager.connections)
        if (ext.capabilities.services.contains(CleanService.serviceNamespace)) ext,
    ];

    if (cleanExtensions.isEmpty) {
      return;
    }

    final environment = CleanEnvironment(
      buildDir: (buildDirectory ?? project.buildDirectory).absolute.uri,
      projectRoot: project.directory.absolute.uri,
    );

    for (final ext in cleanExtensions) {
      final Status status = _logger.startProgress(
        'Cleaning artifacts for extension "${ext.extensionName}"...',
      );
      try {
        await ext.sendRequest(
          CleanService.cleanMethod,
          params: <String, Object?>{CleanService.environmentParam: environment.toMap()},
          timeout: null,
        );
      } on Object catch (e) {
        _logger.printError('Failed to clean extension "${ext.extensionName}": $e');
      } finally {
        status.stop();
      }
    }
  }
}

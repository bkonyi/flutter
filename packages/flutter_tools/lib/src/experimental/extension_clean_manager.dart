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

/// Manages invoking custom clean operations provided by active tool extensions.
base class ExtensionCleanManager {
  ExtensionCleanManager({
    required ExtensionManager extensionManager,
    required FeatureFlags featureFlags,
    required Logger logger,
  }) : _extensionManager = extensionManager,
       _featureFlags = featureFlags,
       _logger = logger;

  final ExtensionManager _extensionManager;
  final FeatureFlags _featureFlags;
  final Logger _logger;

  /// Cleans extension-managed artifacts and build directories for the given [project].
  Future<void> cleanProject(FlutterProject project, {Directory? buildDirectory}) async {
    if (!_featureFlags.isToolExtensionsEnabled) {
      return;
    }
    await _extensionManager.ensureInitialized(
      requiredServices: const <String>{CleanService.serviceNamespace},
    );
    final Directory targetBuildDir = buildDirectory ?? project.buildDirectory;
    final environment = CleanEnvironment(
      buildDir: targetBuildDir.uri,
      projectRoot: project.directory.uri,
    );

    for (final ExtensionConnection connection in _extensionManager.connections) {
      if (!connection.capabilities.services.contains(CleanService.serviceNamespace)) {
        continue;
      }
      final String extensionName = connection.capabilities.extensionName ?? 'default';
      final client = CleanServiceClient(connection.sendRequest);
      try {
        _logger.printTrace('Cleaning extension build artifacts for "$extensionName"...');
        await client.clean(environment);
      } on Object catch (e) {
        _logger.printWarning('Extension "$extensionName" failed during clean: $e');
      }
    }
  }
}

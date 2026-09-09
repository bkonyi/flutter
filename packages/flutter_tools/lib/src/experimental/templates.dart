// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';

import '../base/file_system.dart';
import '../base/logger.dart';
import '../cache.dart';
import '../features.dart';
import 'extension_discovery.dart';
import 'extension_manager.dart';

/// Manages querying project templates from extension isolates.
///
/// This manager interacts with active [ExtensionConnection]s to discover custom
/// project templates, resolve their directories on the host, and generate
/// template parameters over the extension protocol RPC.
base class ExtensionTemplateManager extends TemplateService {
  ExtensionTemplateManager({
    required ExtensionManager extensionManager,
    required FileSystem fileSystem,
    required Logger logger,
    required FeatureFlags featureFlags,
  }) : _extensionManager = extensionManager,
       _fileSystem = fileSystem,
       _logger = logger,
       _featureFlags = featureFlags;

  final ExtensionManager _extensionManager;
  final FileSystem _fileSystem;
  final Logger _logger;
  final FeatureFlags _featureFlags;

  List<ProjectTemplate>? _cachedTemplates;

  /// Retrieve the cached templates synchronously.
  ///
  /// Returns the list of project templates cached from the last [getProjectTemplates] call.
  List<ProjectTemplate> get cachedTemplates => _cachedTemplates ?? const <ProjectTemplate>[];

  /// Retrieve templates by routing `template.getProjectTemplates` to active tool extensions.
  ///
  /// Results are cached after the first successful call.
  Future<List<ProjectTemplate>> getProjectTemplates() async {
    if (!_featureFlags.isToolExtensionsEnabled) {
      return const <ProjectTemplate>[];
    }
    if (_cachedTemplates != null) {
      return _cachedTemplates!;
    }

    await _extensionManager.ensureInitialized();

    final templates = <ProjectTemplate>[];
    final List<ExtensionConnection> connections = _extensionManager.connections
        .where(
          (ExtensionConnection c) =>
              c.capabilities.services.contains(TemplateService.serviceNamespace),
        )
        .toList();

    for (final connection in connections) {
      try {
        final Object? rpcResult = await connection
            .sendRequest(TemplateService.getProjectTemplatesMethod)
            .timeout(const Duration(seconds: 5));
        templates.addAll(ExtensionProjectTemplate.listFromJson(rpcResult));
      } on Object catch (e) {
        _logger.printError(
          'Failed to get results from extension for ${TemplateService.getProjectTemplatesMethod}: $e',
        );
      }
    }

    _cachedTemplates = templates;
    return templates;
  }

  /// Resolves a template package URI to a local directory.
  ///
  /// Supports `package:flutter_tools/` and arbitrary `package:<name>/` URIs
  /// resolved relative to the Flutter SDK or workspace packages.
  Directory resolveTemplateDirectory(String templatePath) {
    if (Uri.tryParse(templatePath) case final Uri uri when uri.scheme == 'package') {
      final List<String> segments = uri.pathSegments;
      if (segments.isNotEmpty && Cache.flutterRoot != null) {
        final String packageName = segments.first;
        final String relativePath = segments.skip(1).join('/');
        final String packagePath = switch (packageName) {
          'flutter_tools' => _fileSystem.path.join(
            Cache.flutterRoot!,
            'packages',
            'flutter_tools',
            'lib',
            relativePath,
          ),
          _ => _fileSystem.path.join(
            Cache.flutterRoot!,
            'packages',
            'flutter_tools',
            'packages',
            packageName,
            'lib',
            relativePath,
          ),
        };
        return _fileSystem.directory(packagePath);
      }
    }
    throw ArgumentError('Unsupported template path format: $templatePath');
  }

  /// Request template parameter generation over extension protocol RPC.
  ///
  /// Delegates the parameter generation for [templateName] to the active tool
  /// extension, passing the host's [toolParameters]. Falls back to returning
  /// [toolParameters] unchanged if the extension fails or is not available.
  Future<Map<String, Object?>> generateTemplateParameters(
    String templateName,
    Map<String, Object?> toolParameters,
  ) async {
    if (!_featureFlags.isToolExtensionsEnabled) {
      return toolParameters;
    }

    final List<ExtensionConnection> connections = _extensionManager.connections
        .where(
          (ExtensionConnection c) =>
              c.capabilities.services.contains(TemplateService.serviceNamespace),
        )
        .toList();

    for (final connection in connections) {
      try {
        final Object? result = await connection
            .sendRequest(TemplateService.generateTemplateParametersMethod, <String, Object?>{
              'templateName': templateName,
              'toolParameters': toolParameters,
            })
            .timeout(const Duration(seconds: 5));
        return result! as Map<String, Object?>;
      } on Object catch (e) {
        _logger.printError('Failed to generate template parameters from extension: $e');
      }
    }

    return toolParameters;
  }

  @override
  Set<ProjectTemplate> get projectTemplates => cachedTemplates.toSet();

  @override
  Set<String> get appPlatformTemplates => const <String>{};

  @override
  Set<String> get pluginPlatformTemplates => const <String>{};
}

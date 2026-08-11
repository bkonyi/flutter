// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'protocol_base/service.dart';

/// Context passed to the extension target's [ExtensionTarget.build] method.
class ExtensionBuildContext {
  ExtensionBuildContext({
    required this.projectRoot,
    required this.mainPath,
    required this.buildMode,
    required this.outputDir,
    required this.buildDir,
    required this.resolvedArtifacts,
    required this.plugins,
  });

  /// The absolute path to the root directory of the Flutter project being built.
  final String projectRoot;

  /// The path to the main entrypoint file (typically `lib/main.dart`).
  final String mainPath;

  /// The build mode name (e.g. `'debug'`, `'profile'`, `'release'`).
  final String buildMode;

  /// The directory where final build outputs should be placed.
  final String outputDir;

  /// The directory used for temporary build artifacts.
  final String buildDir;

  /// A map of resolved engine artifact names to their absolute paths on the host.
  ///
  /// Keys correspond to `Artifact` or `HostArtifact` name values.
  final Map<String, String> resolvedArtifacts;

  /// A list of plugins enabled for the build.
  final List<ExtensionPlugin> plugins;
}

/// Abstract target that encapsulates both metadata and build logic.
///
/// Extensions should extend this class to define custom build targets.
abstract class ExtensionTarget extends Target {
  const ExtensionTarget({
    required this.targetPlatform,
    required this.description,
    this.isTopLevel = true,
    this.outputDir = '{BUILD_DIR}',
  });

  @override
  String? get pluginPlatformKey => null;

  /// The output directory pattern for this target.
  ///
  /// Can include placeholders like `{PROJECT_DIR}` or `{BUILD_MODE}` which
  /// will be resolved by the host.
  @override
  final String outputDir;

  /// The target platform string (e.g. `'linux-x64'`, `'android-arm64'`).
  final String targetPlatform;

  /// Description of what this target builds.
  final String description;

  /// Whether this target is a top-level target invokable through `flutter build`.
  ///
  /// Non-top-level targets are typically used as dependencies for other targets
  /// and are not directly exposed to the user.
  final bool isTopLevel;

  /// Performs the actual compilation/build steps in the extension process/isolate.
  ///
  /// Access resolved artifact paths from [ExtensionBuildContext.resolvedArtifacts] using
  /// `Artifact.<name>.name` or `HostArtifact.<name>.name` as keys.
  /// Returns a map of custom build results (e.g. executablePath).
  Future<Map<String, Object?>> build(ExtensionBuildContext context);
}

/// Extension service interface for custom builds.
///
/// Automatically routes build RPC calls to the registered [targets].
abstract base class BuildService extends ToolExtensionService {
  /// Service namespace identifier for custom builds.
  static const String serviceNamespace = 'build';

  /// RPC method identifier to query contributed build targets.
  static const String getBuildTargetsMethod = 'build.getBuildTargets';

  /// RPC method identifier to trigger a custom build.
  static const String buildMethod = 'build.build';

  @override
  String get namespace => serviceNamespace;

  /// Returns the custom build targets contributed by this extension.
  List<ExtensionTarget> get targets;

  @override
  Future<Map<String, ExtensionRpcHandler>> initialize() async {
    return <String, ExtensionRpcHandler>{
      'getBuildTargets': _getBuildTargetsRpc,
      'build': _buildRpc,
    };
  }

  @override
  Future<void> shutdown() async {}

  Future<List<Map<String, Object?>>> _getBuildTargetsRpc(Map<String, Object?> params) async {
    return targets
        .map(
          (ExtensionTarget target) => ExtensionBuildTarget(
            name: target.name,
            targetPlatform: target.targetPlatform,
            description: target.description,
            isTopLevel: target.isTopLevel,
            dependencies: target.dependencies.map((Target d) => d.name).toList(),
            inputs: target.inputs,
            outputs: target.outputs,
            outputDir: target.outputDir,
            pluginPlatformKey: target.pluginPlatformKey,
          ).toMap(),
        )
        .toList();
  }

  Future<Map<String, Object?>> _buildRpc(Map<String, Object?> params) async {
    if (params case {
      'targetName': final String targetName,
      'projectRoot': final String projectRoot,
      'mainPath': final String mainPath,
      'buildMode': final String buildMode,
      'outputDir': final String outputDir,
      'buildDir': final String buildDir,
      'resolvedArtifacts': final Map<Object?, Object?> resolvedArtifactsRaw,
    }) {
      final List<Object?> pluginsRaw = (params['plugins'] as List<Object?>?) ?? <Object?>[];
      ExtensionTarget? target;
      for (final ExtensionTarget t in targets) {
        if (t.name == targetName) {
          target = t;
          break;
        }
      }
      if (target == null) {
        return ExtensionBuildResult.failure(message: 'Unknown target: $targetName').toMap();
      }

      final Map<String, String> resolvedArtifacts = resolvedArtifactsRaw.map(
        (key, value) => MapEntry<String, String>(key.toString(), value.toString()),
      );

      try {
        final List<ExtensionPlugin> plugins = pluginsRaw
            .map((dynamic e) => ExtensionPlugin.fromJson(e as Map<String, Object?>))
            .toList();
        final context = ExtensionBuildContext(
          projectRoot: projectRoot,
          mainPath: mainPath,
          buildMode: buildMode,
          outputDir: outputDir,
          buildDir: buildDir,
          resolvedArtifacts: resolvedArtifacts,
          plugins: plugins,
        );
        final Map<String, Object?> buildResultMap = await target.build(context);
        return <String, Object?>{'success': true, ...buildResultMap};
      } on Object catch (e, stack) {
        return ExtensionBuildResult.failure(message: '$e\n$stack').toMap();
      }
    }
    if (params['targetName'] is! String) {
      throw RpcException.invalidParams('Missing or invalid "targetName" parameter.');
    }
    if (params['projectRoot'] is! String) {
      throw RpcException.invalidParams('Missing or invalid "projectRoot" parameter.');
    }
    if (params['mainPath'] is! String) {
      throw RpcException.invalidParams('Missing or invalid "mainPath" parameter.');
    }
    if (params['buildMode'] is! String) {
      throw RpcException.invalidParams('Missing or invalid "buildMode" parameter.');
    }
    if (params['outputDir'] is! String) {
      throw RpcException.invalidParams('Missing or invalid "outputDir" parameter.');
    }
    if (params['buildDir'] is! String) {
      throw RpcException.invalidParams('Missing or invalid "buildDir" parameter.');
    }
    if (params['resolvedArtifacts'] is! Map) {
      throw RpcException.invalidParams('Missing or invalid "resolvedArtifacts" parameter.');
    }
    if (params['plugins'] is! List) {
      throw RpcException.invalidParams('Missing or invalid "plugins" parameter.');
    }
    throw RpcException.invalidParams('Invalid build parameters.');
  }
}

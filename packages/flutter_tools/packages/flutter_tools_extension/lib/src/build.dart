// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'protocol_base/service.dart';

/// Extension service interface for custom builds.
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
  Future<List<ExtensionBuildTarget>> getBuildTargets();

  /// Triggers a custom build for the given [targetName].
  Future<ExtensionBuildResult> build({
    required String targetName,
    required String projectRoot,
    required String mainPath,
    required String buildMode,
  });

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
    final List<ExtensionBuildTarget> targets = await getBuildTargets();
    return targets.map((ExtensionBuildTarget target) => target.toMap()).toList();
  }

  Future<Map<String, Object?>> _buildRpc(Map<String, Object?> params) async {
    if (params case {
      'targetName': final String targetName,
      'projectRoot': final String projectRoot,
      'mainPath': final String mainPath,
      'buildMode': final String buildMode,
    }) {
      final ExtensionBuildResult result = await build(
        targetName: targetName,
        projectRoot: projectRoot,
        mainPath: mainPath,
        buildMode: buildMode,
      );
      return result.toMap();
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
    throw RpcException.invalidParams('Invalid build parameters.');
  }
}

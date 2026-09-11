// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:json_rpc_2/json_rpc_2.dart';

import 'protocol_base/service.dart';

/// The service responsible for acquiring the necessary files to develop
/// and deploy Flutter applications for a custom target platform.
abstract base class ArtifactService extends ToolExtensionService {
  /// Service namespace identifier for artifacts.
  static const String serviceNamespace = 'artifact';

  /// RPC method identifier to query artifacts.
  static const String getArtifactsMethod = 'artifact.getArtifacts';

  /// RPC method identifier to download artifacts.
  static const String downloadArtifactsMethod = 'artifact.downloadArtifacts';

  @override
  String get namespace => serviceNamespace;

  /// The set of artifacts provided by the extension.
  Set<ArtifactDependency> get artifacts;

  /// Downloads missing artifacts (e.g., custom engine embeddings or
  /// gen_snapshot) for the target platform.
  Future<void> downloadArtifacts(
    Set<String> artifactNames, {
    required BuildMode buildMode,
    required Uri destinationDirectory,
    required HostPlatform hostPlatform,
    required TargetPlatform targetPlatform,
  });

  @override
  Future<Map<String, ExtensionRpcHandler>> initialize() async {
    return <String, ExtensionRpcHandler>{
      'getArtifacts': _getArtifactsRpc,
      'downloadArtifacts': _downloadArtifactsRpc,
    };
  }

  @override
  Future<void> shutdown() async {}

  Future<Object?> _getArtifactsRpc(Map<String, Object?> params) async {
    return artifacts.map((ArtifactDependency a) => a.toJson()).toList();
  }

  Future<Object?> _downloadArtifactsRpc(Map<String, Object?> params) async {
    if (params case {
      'artifactNames': final List<Object?> rawNames,
      'buildMode': final String buildModeName,
      'destinationDirectory': final String destinationDirectoryStr,
      'hostPlatform': final String hostPlatformName,
      'targetPlatform': final String targetPlatformName,
    }) {
      final Set<String> artifactNames = rawNames.whereType<String>().toSet();
      final buildMode = BuildMode.fromCliName(buildModeName);
      final Uri destinationDirectory = Uri.parse(destinationDirectoryStr);
      final HostPlatform hostPlatform = HostPlatform.values.firstWhere(
        (HostPlatform p) => p.cliName == hostPlatformName,
      );
      final targetPlatform = TargetPlatform.fromName(targetPlatformName);
      await downloadArtifacts(
        artifactNames,
        buildMode: buildMode,
        destinationDirectory: destinationDirectory,
        hostPlatform: hostPlatform,
        targetPlatform: targetPlatform,
      );
      return <String, Object?>{'success': true};
    }
    throw RpcException.invalidParams('Invalid downloadArtifacts parameters.');
  }
}

/// Client adapter for [ArtifactService] that communicates via JSON-RPC.
base class ArtifactServiceClient extends ArtifactService {
  ArtifactServiceClient(this._sendRequest, {Set<ArtifactDependency>? initialArtifacts})
    : _cachedArtifacts = initialArtifacts;

  final Future<Object?> Function(String method, [Object? params]) _sendRequest;
  Set<ArtifactDependency>? _cachedArtifacts;

  @override
  Set<ArtifactDependency> get artifacts => _cachedArtifacts ?? const <ArtifactDependency>{};

  /// Fetches the available artifacts from the remote extension isolate.
  Future<Set<ArtifactDependency>> fetchArtifacts() async {
    final Object? rawResult = await _sendRequest(ArtifactService.getArtifactsMethod);
    if (rawResult is List) {
      final Set<ArtifactDependency> list = rawResult
          .whereType<Map<String, Object?>>()
          .map(ArtifactDependency.fromJson)
          .toSet();
      _cachedArtifacts = list;
      return list;
    }
    return const <ArtifactDependency>{};
  }

  @override
  Future<void> downloadArtifacts(
    Set<String> artifactNames, {
    required BuildMode buildMode,
    required Uri destinationDirectory,
    required HostPlatform hostPlatform,
    required TargetPlatform targetPlatform,
  }) async {
    await _sendRequest(ArtifactService.downloadArtifactsMethod, <String, Object?>{
      'artifactNames': artifactNames.toList(),
      'buildMode': buildMode.cliName,
      'destinationDirectory': destinationDirectory.toString(),
      'hostPlatform': hostPlatform.cliName,
      'targetPlatform': targetPlatform.getName(),
    });
  }
}

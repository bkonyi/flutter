// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:json_rpc_2/json_rpc_2.dart';

import 'protocol_base/service.dart';

/// The service responsible for cleaning extension-managed build outputs and
/// temporary artifacts when `flutter clean` is executed.
abstract base class CleanService extends ToolExtensionService {
  /// Service namespace identifier for clean.
  static const String serviceNamespace = 'clean';

  /// RPC method identifier to invoke clean.
  static const String cleanMethod = 'clean.clean';

  @override
  String get namespace => serviceNamespace;

  /// Cleans build outputs and temporary artifacts for the given [environment].
  Future<void> clean(CleanEnvironment environment);

  @override
  Future<Map<String, ExtensionRpcHandler>> initialize() async {
    return <String, ExtensionRpcHandler>{'clean': _cleanRpc};
  }

  @override
  Future<void> shutdown() async {}

  Future<Object?> _cleanRpc(Map<String, Object?> params) async {
    if (params case {
      'buildDir': final String buildDirStr,
      'projectRoot': final String projectRootStr,
    }) {
      final environment = CleanEnvironment(
        buildDir: Uri.parse(buildDirStr),
        projectRoot: Uri.parse(projectRootStr),
      );
      await clean(environment);
      return <String, Object?>{'success': true};
    }
    throw RpcException.invalidParams('Invalid clean parameters.');
  }
}

/// Client adapter for [CleanService] that communicates via JSON-RPC.
base class CleanServiceClient extends CleanService {
  CleanServiceClient(this._sendRequest);

  final Future<Object?> Function(String method, [Object? params]) _sendRequest;

  @override
  Future<void> clean(CleanEnvironment environment) async {
    await _sendRequest(CleanService.cleanMethod, environment.toJson());
  }
}

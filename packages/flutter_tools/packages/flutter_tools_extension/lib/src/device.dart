// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'protocol_base/service.dart';

/// Extension service interface for retrieving target devices.
abstract base class DeviceService extends ToolExtensionService {
  /// Service namespace identifier for device services.
  static const String serviceNamespace = 'device';

  /// RPC method identifier to query contributed target devices.
  static const String getDevicesMethod = 'device.getDevices';

  /// RPC method identifier to launch an application on a target device.
  static const String launchAppMethod = 'device.launchApp';

  /// RPC method identifier to get the VM service URI of a target device.
  static const String getVmServiceUriMethod = 'device.getVmServiceUri';

  /// RPC method identifier to stop an application on a target device.
  static const String stopAppMethod = 'device.stopApp';

  @override
  String get namespace => serviceNamespace;

  /// Returns the target devices contributed by this extension.
  Future<List<TargetDevice>> getDevices();

  /// Launches an application binary on the target device with [deviceId] and [executablePath].
  Future<Map<String, Object?>> launchApp({
    required String deviceId,
    required String executablePath,
    Map<String, Object?>? debuggingOptions,
  });

  /// Returns the VM service URI of a running application on the target device.
  Future<String?> getVmServiceUri({required String deviceId, required String executablePath});

  /// Stops a running application on the target device with [deviceId] and [executablePath].
  Future<bool> stopApp({required String deviceId, required String executablePath});

  @override
  Future<Map<String, ExtensionRpcHandler>> initialize() async {
    return <String, ExtensionRpcHandler>{
      'getDevices': _getDevicesRpc,
      'launchApp': _launchAppRpc,
      'getVmServiceUri': _getVmServiceUriRpc,
      'stopApp': _stopAppRpc,
    };
  }

  @override
  Future<void> shutdown() async {}

  Future<List<Map<String, Object?>>> _getDevicesRpc(Map<String, Object?> params) async {
    final List<TargetDevice> devices = await getDevices();
    return devices.map((TargetDevice device) => device.toMap()).toList();
  }

  Future<Map<String, Object?>> _launchAppRpc(Map<String, Object?> params) async {
    final deviceId = params['deviceId']! as String;
    final executablePath = params['executablePath']! as String;
    final debuggingOptions = params['debuggingOptions'] as Map<String, Object?>?;
    return launchApp(
      deviceId: deviceId,
      executablePath: executablePath,
      debuggingOptions: debuggingOptions,
    );
  }

  Future<String?> _getVmServiceUriRpc(Map<String, Object?> params) async {
    final deviceId = params['deviceId']! as String;
    final executablePath = params['executablePath']! as String;
    return getVmServiceUri(deviceId: deviceId, executablePath: executablePath);
  }

  Future<bool> _stopAppRpc(Map<String, Object?> params) async {
    final deviceId = params['deviceId']! as String;
    final executablePath = params['executablePath']! as String;
    return stopApp(deviceId: deviceId, executablePath: executablePath);
  }
}

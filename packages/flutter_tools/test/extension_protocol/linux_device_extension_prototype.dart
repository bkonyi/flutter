// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:isolate';

import 'package:flutter_tools/extension_protocol.dart';
import 'flutter_tools_extension_mock.dart';

/// Prototype implementation of Device to represent the Linux desktop target.
class LinuxDevice extends Device {
  LinuxDevice({
    required this.id,
    required this.name,
    required this.category,
    required this.onLogReceived,
  });

  final void Function(String message) onLogReceived;

  @override
  final String id;

  @override
  final String name;

  @override
  final String category;

  @override
  bool get isEmulator => false;

  final StreamController<String> _logController = StreamController<String>.broadcast();

  @override
  Future<void> installApp(Uri appBundlePath) async {
    onLogReceived('Installing app bundle ${appBundlePath.toFilePath()}...');
  }

  @override
  Future<void> launchApp(Uri appBundlePath) async {
    onLogReceived('Launching app bundle ${appBundlePath.toFilePath()}...');

    // Emulate background app logging
    Timer.periodic(const Duration(milliseconds: 50), (Timer timer) {
      if (timer.tick > 3) {
        timer.cancel();
        return;
      }
      _logController.add('stdout log line #${timer.tick} from application.');
    });
  }

  @override
  Stream<String> getLogReader() => _logController.stream;

  @override
  Future<Uri> getVmServiceUri() async {
    return Uri.parse('http://127.0.0.1:9090/auth-token-123/');
  }
}

/// Prototype implementation of a DeviceService for Linux support.
final class LinuxDeviceService extends DeviceService {
  LinuxDeviceService({required super.onNotification});

  @override
  Future<List<Device>> discoverDevices() async {
    return <Device>[
      LinuxDevice(
        id: 'linux',
        name: 'Linux Desktop Target',
        category: 'desktop',
        onLogReceived: (String message) {
          onNotification('device.log', <String, Object?>{
            'deviceId': 'linux',
            'message': message,
          });
        },
      ),
    ];
  }

  @override
  Future<void> launchEmulator(String emulatorId) async {}

  @override
  Future<void> shutdown() async {}
}

/// Entrypoint for the Linux device extension isolate.
void linuxDeviceExtensionEntryPoint(SendPort hostSendPort) {
  final provider = ToolExtensionProvider(
    name: 'linux_device_extension',
    sendPort: hostSendPort,
  );

  provider.registerService(
    LinuxDeviceService(
      onNotification: (String method, Map<String, Object?> params) {
        provider.sendNotification(method, params);
      },
    ),
  );
  provider.initialize();
}

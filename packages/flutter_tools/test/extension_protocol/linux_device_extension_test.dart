// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter_tools/extension_protocol.dart';
import 'package:test/test.dart';

import 'linux_device_extension_prototype.dart';

void main() {
  group('Linux Device Extension Prototype', () {
    late ToolExtensionManager manager;

    setUp(() {
      manager = ToolExtensionManager();
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('discover, install, launch and stream logs from Linux target', () async {
      // 1. Spawn the Linux device extension
      final ToolExtension extension = await manager.startExtension(linuxDeviceExtensionEntryPoint);

      // 2. Query capabilities
      final ToolExtensionCapabilities capabilities = await extension.getCapabilities();
      expect(capabilities.services, const <String>['device']);

      // 3. Discover devices
      final Object? devicesResult = await extension.callMethod('device.discoverDevices');
      expect(devicesResult, isA<List<Object?>>());
      final devices = devicesResult! as List<Object?>;
      expect(devices, hasLength(1));

      final Map<String, Object?> device = (devices[0]! as Map<dynamic, dynamic>).cast<String, Object?>();
      expect(device['id'], 'linux');
      expect(device['name'], 'Linux Desktop Target');
      expect(device['category'], 'desktop');

      // 4. Install app
      final logLines = <String>[];
      final logCompleter = Completer<void>();

      final StreamSubscription<Notification> sub = manager.notifications.listen((Notification n) {
        if (n.method == 'device.log') {
          final message = n.params!['message']! as String;
          logLines.add(message);
          if (logLines.length >= 5) {
            if (!logCompleter.isCompleted) {
              logCompleter.complete();
            }
          }
        }
      });
      addTearDown(sub.cancel);

      await extension.callMethod('device.installApp', params: <String, Object?>{
        'deviceId': 'linux',
        'appBundlePath': '/build/linux/x64/debug/bundle',
      });

      // 5. Launch app
      await extension.callMethod('device.launchApp', params: <String, Object?>{
        'deviceId': 'linux',
        'appBundlePath': '/build/linux/x64/debug/bundle',
      });

      // Wait for app logs to be streamed back
      await logCompleter.future.timeout(const Duration(seconds: 3));

      expect(logLines, contains('Installing app bundle /build/linux/x64/debug/bundle...'));
      expect(logLines, contains('Launching app bundle /build/linux/x64/debug/bundle...'));
      expect(logLines, contains('stdout log line #1 from application.'));
      expect(logLines, contains('stdout log line #2 from application.'));
      expect(logLines, contains('stdout log line #3 from application.'));

      // 6. Query VM Service URI
      final Object? vmServiceUri = await extension.callMethod('device.getVmServiceUri', params: <String, Object?>{
        'deviceId': 'linux',
      });
      expect(vmServiceUri, 'http://127.0.0.1:9090/auth-token-123/');
    });
  });
}

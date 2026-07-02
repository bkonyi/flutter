// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../../extension_protocol.dart';
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
  final Completer<Uri> _vmServiceUriCompleter = Completer<Uri>();
  Process? _process;

  @override
  Future<void> installApp(Uri appBundlePath) async {
    onLogReceived('Installing app bundle ${appBundlePath.toFilePath()}...');
  }

  @override
  Future<void> launchApp(Uri appBundlePath, List<String> args) async {
    final String filePath = appBundlePath.toFilePath();
    if (!FileSystemEntity.isFileSync(filePath)) {
      onLogReceived('Launching app bundle $filePath...');
      Timer.periodic(const Duration(milliseconds: 50), (Timer timer) {
        if (timer.tick > 3) {
          timer.cancel();
          return;
        }
        _logController.add('stdout log line #${timer.tick} from application.');
      });
      _vmServiceUriCompleter.complete(Uri.parse('http://127.0.0.1:9090/auth-token-123/'));
      return;
    }

    onLogReceived('Launching app bundle $filePath with args: $args...');

    try {
      final Process process = await Process.start(filePath, args);
      _process = process;

      unawaited(
        process.exitCode.then((int exitCode) {
          if (!_vmServiceUriCompleter.isCompleted) {
            _vmServiceUriCompleter.completeError(
              StateError(
                'The process exited early with exit code $exitCode before VM Service URI was printed.',
              ),
            );
          }
        }),
      );

      process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((String line) {
        _logController.add(line);
        final vmServiceRegExp = RegExp(
          r'The Dart VM service is listening on (http://127.0.0.1:\d+/[^/]+/)',
        );
        final Match? match = vmServiceRegExp.firstMatch(line);
        if (match != null) {
          if (!_vmServiceUriCompleter.isCompleted) {
            _vmServiceUriCompleter.complete(Uri.parse(match.group(1)!));
          }
        }
      });

      process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((String line) {
        _logController.add('ERROR: $line');
      });
    } on Object catch (e) {
      _logController.add('Failed to launch application process: $e');
      _vmServiceUriCompleter.completeError(e);
    }
  }

  @override
  Stream<String> getLogReader() => _logController.stream;

  @override
  Future<Uri> getVmServiceUri() async {
    return _vmServiceUriCompleter.future;
  }

  @override
  Future<void> stopApp() async {
    onLogReceived('Stopping application...');
    _process?.kill();
    _process = null;
  }
}

/// Prototype implementation of a DeviceService for Linux support.
final class LinuxDeviceService extends DeviceService {
  LinuxDeviceService({required super.onNotification});

  @override
  Future<List<Device>> discoverDevices() async {
    return <Device>[
      LinuxDevice(
        id: 'linux-proto-1',
        name: 'Linux Desktop Target',
        category: 'desktop',
        onLogReceived: (String message) {
          onNotification('device.log', <String, Object?>{
            'deviceId': 'linux-proto-1',
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
  final provider = ToolExtensionProvider(name: 'linux_device_extension', sendPort: hostSendPort);

  provider.registerService(
    LinuxDeviceService(
      onNotification: (String method, Map<String, Object?> params) {
        provider.sendNotification(method, params);
      },
    ),
  );
  provider.initialize();
}

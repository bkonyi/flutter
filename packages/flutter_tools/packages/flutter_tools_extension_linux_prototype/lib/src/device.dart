// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';

/// Prototype Linux [DeviceService] implementation.
final class LinuxDeviceService extends DeviceService {
  final Map<String, Process> _runningProcesses = <String, Process>{};
  final Map<String, String> _vmServiceUris = <String, String>{};

  @override
  Future<List<TargetDevice>> getDevices() async {
    return <TargetDevice>[
      const TargetDevice(
        id: 'custom_linux_device',
        name: 'Linux Custom Extension Prototype Device',
        category: 'desktop',
        platformType: 'custom',
        targetPlatform: 'linux-x64',
        sdkNameAndVersion: 'Custom Linux 1.0.0',
        buildTarget: 'custom-linux-build',
        ephemeral: false,
      ),
    ];
  }

  @override
  Future<Map<String, Object?>> launchApp({
    required String deviceId,
    required String executablePath,
    Map<String, Object?>? debuggingOptions,
  }) async {
    final key = '$deviceId:$executablePath';
    final Process? existingProcess = _runningProcesses[key];
    if (existingProcess != null) {
      existingProcess.kill();
      _runningProcesses.remove(key);
      _vmServiceUris.remove(key);
    }

    final file = File(executablePath);
    if (!file.existsSync()) {
      throw Exception(
        'Executable not found at path: $executablePath.\n'
        'Build may have failed or was skipped because no linux/CMakeLists.txt was found.',
      );
    }

    final args = <String>[];
    if (debuggingOptions != null) {
      if (debuggingOptions['startPaused'] == true) {
        args.add('--start-paused');
      }
      final Object? hostVmServicePort = debuggingOptions['hostVmServicePort'];
      if (hostVmServicePort is int) {
        args.add('--observatory-port=$hostVmServicePort');
      } else {
        final Object? deviceVmServicePort = debuggingOptions['deviceVmServicePort'];
        if (deviceVmServicePort is int) {
          args.add('--observatory-port=$deviceVmServicePort');
        }
      }
    }

    stdout.writeln('LinuxDeviceService spawning $executablePath with args $args');
    final Process process = await Process.start(executablePath, args);
    _runningProcesses[key] = process;

    final vmServiceUriCompleter = Completer<String>();

    process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((String line) {
      stdout.writeln('[Device $deviceId stdout] $line');

      final vmServiceRegExp = RegExp(
        r'The Dart VM service is listening on (http://(?:127\.0\.0\.1|localhost|\[::1\]):\d+/[^/]+/)',
      );
      final Match? match = vmServiceRegExp.firstMatch(line);
      if (match != null) {
        final String uri = match.group(1)!;
        _vmServiceUris[key] = uri;
        if (!vmServiceUriCompleter.isCompleted) {
          vmServiceUriCompleter.complete(uri);
        }
      }
    });

    process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((String line) {
      stderr.writeln('[Device $deviceId stderr] $line');
    });

    unawaited(
      process.exitCode.then((int exitCode) {
        stdout.writeln('[Device $deviceId] Process exited with code $exitCode');
        _runningProcesses.remove(key);
        _vmServiceUris.remove(key);
        if (!vmServiceUriCompleter.isCompleted) {
          vmServiceUriCompleter.completeError(
            Exception(
              'Process exited early with exit code $exitCode before VM Service URI was printed.',
            ),
          );
        }
      }),
    );

    String? vmServiceUri;
    if (debuggingOptions != null) {
      try {
        vmServiceUri = await vmServiceUriCompleter.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            stdout.writeln('Timeout waiting for VM Service URI on $deviceId');
            return '';
          },
        );
        if (vmServiceUri.isEmpty) {
          vmServiceUri = null;
        }
      } on Object catch (e) {
        stdout.writeln('Failed to get VM Service URI: $e');
      }
    }

    return <String, Object?>{if (vmServiceUri != null) 'vmServiceUri': vmServiceUri};
  }

  @override
  Future<String?> getVmServiceUri({
    required String deviceId,
    required String executablePath,
  }) async {
    final key = '$deviceId:$executablePath';
    return _vmServiceUris[key];
  }

  @override
  Future<bool> stopApp({required String deviceId, required String executablePath}) async {
    final key = '$deviceId:$executablePath';
    final Process? process = _runningProcesses[key];
    if (process == null) {
      stdout.writeln('LinuxDeviceService.stopApp: No running process found for $key');
      return false;
    }
    stdout.writeln('LinuxDeviceService.stopApp: Killing process for $key');
    final bool killed = process.kill();
    _runningProcesses.remove(key);
    _vmServiceUris.remove(key);
    return killed;
  }

  @override
  Future<void> shutdown() async {
    for (final Process process in _runningProcesses.values) {
      process.kill();
    }
    _runningProcesses.clear();
    _vmServiceUris.clear();
    await super.shutdown();
  }
}

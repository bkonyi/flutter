// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';

import 'package:file/file.dart';
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:vm_service/vm_service.dart' as vm_service;
import 'package:vm_service/vm_service_io.dart';

import '../src/common.dart';
import 'test_utils.dart';

void main() {
  final bool isLinux = const LocalPlatform().isLinux;
  late Directory tempHome;
  late Map<String, String> baseEnv;

  setUpAll(() {
    tempHome = createResolvedTempDirectorySync('tool_extensions_home.');
    baseEnv = <String, String>{
      'HOME': tempHome.path,
      'USERPROFILE': tempHome.path,
      'APPDATA': tempHome.path,
      'BOT': 'true',
    };
  });

  tearDownAll(() {
    tryToDelete(tempHome);
  });

  testWithoutContext('flutter doctor executes extension validators when enabled', () async {
    final ProcessResult result = await processManager.run(
      <String>[flutterBin, 'doctor', '-v'],
      environment: <String, String>{...baseEnv, 'FLUTTER_TOOL_EXTENSIONS': 'true'},
    );

    if (isLinux) {
      expect(result.stdout, contains('[✓] Linux Custom Extension Prototype'));
      expect(result.stdout, contains('Linux custom extension toolchain is operational'));
    } else {
      expect(result.stdout, isNot(contains('Linux Custom Extension Prototype')));
    }
    expect(result.exitCode, 0);
  });

  testWithoutContext('flutter config outputs extension settings when enabled', () async {
    final ProcessResult result = await processManager.run(
      <String>[flutterBin, 'config', '--list'],
      environment: <String, String>{...baseEnv, 'FLUTTER_TOOL_EXTENSIONS': 'true'},
    );

    if (isLinux) {
      expect(result.stdout, contains('Extension Settings:'));
      expect(result.stdout, contains('  Linux Custom Extension Prototype:'));
      expect(result.stdout, contains('    enable-linux-custom-prototype:'));
    } else {
      expect(result.stdout, isNot(contains('Extension Settings:')));
    }
    expect(result.exitCode, 0);
  });

  testWithoutContext('flutter devices outputs custom extension device when enabled', () async {
    final ProcessResult result = await processManager.run(
      <String>[flutterBin, 'devices'],
      environment: <String, String>{...baseEnv, 'FLUTTER_TOOL_EXTENSIONS': 'true'},
    );

    if (isLinux) {
      expect(result.stdout, contains('Linux Custom Extension Prototype Device'));
    } else {
      expect(result.stdout, isNot(contains('Linux Custom Extension Prototype Device')));
    }
    expect(result.exitCode, 0);
  });
  testWithoutContext('tool extensions are disabled by default', () async {
    final ProcessResult doctorResult = await processManager.run(<String>[
      flutterBin,
      'doctor',
      '-v',
    ], environment: baseEnv);
    expect(doctorResult.stdout, isNot(contains('Linux Custom Extension Prototype')));
    expect(doctorResult.exitCode, 0);

    final ProcessResult configResult = await processManager.run(<String>[
      flutterBin,
      'config',
      '--list',
    ], environment: baseEnv);
    expect(configResult.stdout, isNot(contains('Extension Settings:')));
    expect(configResult.exitCode, 0);

    final ProcessResult devicesResult = await processManager.run(<String>[
      flutterBin,
      'devices',
    ], environment: baseEnv);
    expect(devicesResult.stdout, isNot(contains('Linux Custom Extension Prototype Device')));
    expect(devicesResult.exitCode, 0);
  });

  testWithoutContext('flutter create with custom template succeeds when enabled', () async {
    final Directory projectDir = tempHome.childDirectory('custom_app');
    if (projectDir.existsSync()) {
      projectDir.deleteSync(recursive: true);
    }

    final ProcessResult result = await processManager.run(
      <String>[flutterBin, 'create', '--template=custom-linux-app', projectDir.path],
      environment: <String, String>{...baseEnv, 'FLUTTER_TOOL_EXTENSIONS': 'true'},
    );

    expect(result.exitCode, 0, reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
    expect(projectDir.existsSync(), isTrue);
    final File verificationFile = projectDir.childFile('.custom_device_extension_info');
    expect(verificationFile.existsSync(), isTrue);
    expect(
      verificationFile.readAsStringSync().trim(),
      'Custom Linux Device Extension App Template Verified',
    );
  });

  testWithoutContext('flutter create with custom template fails when disabled', () async {
    final Directory projectDir = tempHome.childDirectory('custom_app_disabled');
    if (projectDir.existsSync()) {
      projectDir.deleteSync(recursive: true);
    }

    final ProcessResult result = await processManager.run(
      <String>[flutterBin, 'create', '--template=custom-linux-app', projectDir.path],
      environment: baseEnv, // disabled by default
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('is not an allowed value for option "--template"'));
    expect(projectDir.existsSync(), isFalse);
  });

  testWithoutContext(
    'flutter build and assemble with custom extension targets succeed when enabled',
    () async {
      if (!isLinux) {
        return;
      }
      final Directory projectDir = tempHome.childDirectory('custom_build_app');
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }

      // 1. Create custom project
      final ProcessResult createResult = await processManager.run(
        <String>[flutterBin, 'create', '--template=custom-linux-app', projectDir.path],
        environment: <String, String>{...baseEnv, 'FLUTTER_TOOL_EXTENSIONS': 'true'},
      );
      expect(
        createResult.exitCode,
        0,
        reason: 'create stdout: ${createResult.stdout}\nstderr: ${createResult.stderr}',
      );

      // 2. Test flutter assemble with custom extension target
      final ProcessResult assembleResult = await processManager.run(
        <String>[
          flutterBin,
          'assemble',
          '-dTargetPlatform=linux-x64',
          '-dBuildMode=debug',
          '-o',
          projectDir.childDirectory('build').path,
          'custom-linux-assemble-only-debug',
        ],
        workingDirectory: projectDir.path,
        environment: <String, String>{...baseEnv, 'FLUTTER_TOOL_EXTENSIONS': 'true'},
      );
      expect(
        assembleResult.exitCode,
        0,
        reason: 'assemble stdout: ${assembleResult.stdout}\nstderr: ${assembleResult.stderr}',
      );

      // 3. Test flutter build subcommand registered dynamically by extension
      final ProcessResult buildResult = await processManager.run(
        <String>[flutterBin, 'build', 'custom-linux-build'],
        workingDirectory: projectDir.path,
        environment: <String, String>{...baseEnv, 'FLUTTER_TOOL_EXTENSIONS': 'true'},
      );
      expect(
        buildResult.exitCode,
        0,
        reason: 'build stdout: ${buildResult.stdout}\nstderr: ${buildResult.stderr}',
      );
    },
  );

  testWithoutContext(
    'flutter run targeting custom extension device executes when enabled',
    () async {
      if (!isLinux) {
        return;
      }
      final Directory projectDir = tempHome.childDirectory('custom_run_app');
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }

      // 1. Create custom project
      final ProcessResult createResult = await processManager.run(
        <String>[flutterBin, 'create', '--template=custom-linux-app', projectDir.path],
        environment: <String, String>{...baseEnv, 'FLUTTER_TOOL_EXTENSIONS': 'true'},
      );
      expect(
        createResult.exitCode,
        0,
        reason: 'create stdout: ${createResult.stdout}\nstderr: ${createResult.stderr}',
      );

      // 2. Test flutter run targeting custom extension device
      final Process process = await processManager.start(
        <String>[flutterBin, 'run', '-d', 'custom_linux_device', '--suppress-analytics', '-v'],
        workingDirectory: projectDir.path,
        environment: <String, String>{...baseEnv, 'FLUTTER_TOOL_EXTENSIONS': 'true'},
      );

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();
      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();
      final vmServiceUriCompleter = Completer<Uri>();

      final vmServiceUriRegExp = RegExp(
        r'A Dart VM Service on .* is available at: (http://127.0.0.1:\d+/\S+/)',
      );

      process.stdout.transform(utf8.decoder).listen((String line) {
        stdoutBuffer.write(line);
        final RegExpMatch? match = vmServiceUriRegExp.firstMatch(line);
        if (match != null && !vmServiceUriCompleter.isCompleted) {
          vmServiceUriCompleter.complete(Uri.parse(match.group(1)!));
        }
      }, onDone: stdoutDone.complete);

      process.stderr
          .transform(utf8.decoder)
          .listen(stderrBuffer.write, onDone: stderrDone.complete);

      final Future<void> testFuture = () async {
        final Uri vmServiceUri = await vmServiceUriCompleter.future;
        final Uri wsUri = vmServiceUri.replace(
          scheme: 'ws',
          path: vmServiceUri.path.endsWith('/')
              ? '${vmServiceUri.path}ws'
              : '${vmServiceUri.path}/ws',
        );
        final vm_service.VmService service = await vmServiceConnectUri(wsUri.toString());
        final vm_service.VM vm = await service.getVM();
        expect(vm.version, isNotNull);
        await service.dispose();
        process.stdin.writeln('q');
      }();

      // Wait for process to exit with a 30s timeout
      final int exitCode = await process.exitCode.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          process.kill();
          return -1;
        },
      );

      await stdoutDone.future;
      await stderrDone.future;
      await testFuture;

      final combinedOutput = '$stdoutBuffer\n$stderrBuffer';
      expect(exitCode, 0, reason: 'run exit code: $exitCode. stdout/stderr:\n$combinedOutput');
      expect(
        combinedOutput.contains('Linux Custom Extension Prototype Device') ||
            combinedOutput.contains('custom_linux_device'),
        isTrue,
        reason: 'combined output: $combinedOutput',
      );
    },
  );

  testWithoutContext(
    'flutter run targeting custom extension device hot reloads when enabled',
    () async {
      if (!isLinux) {
        return;
      }
      final Directory projectDir = tempHome.childDirectory('custom_hot_reload_app');
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }

      // 1. Create custom project
      final ProcessResult createResult = await processManager.run(
        <String>[flutterBin, 'create', '--template=custom-linux-app', projectDir.path],
        environment: <String, String>{...baseEnv, 'FLUTTER_TOOL_EXTENSIONS': 'true'},
      );
      expect(createResult.exitCode, 0);

      // 2. Start flutter run targeting custom extension device
      final Process process = await processManager.start(
        <String>[flutterBin, 'run', '-d', 'custom_linux_device', '--suppress-analytics', '-v'],
        workingDirectory: projectDir.path,
        environment: <String, String>{...baseEnv, 'FLUTTER_TOOL_EXTENSIONS': 'true'},
      );

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();
      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();
      final hotReloadDone = Completer<void>();

      var hasTriggeredReload = false;

      process.stdout.transform(utf8.decoder).listen((String line) async {
        stdoutBuffer.write(line);
        if (line.contains('r Hot reload.') && !hasTriggeredReload) {
          hasTriggeredReload = true;
          // Modify a file to trigger actual reload changes.
          final File mainDart = projectDir.childDirectory('lib').childFile('main.dart');
          final String content = mainDart.readAsStringSync();
          mainDart.writeAsStringSync(
            content.replaceAll('Hello, Custom Device!', 'Hello, Hot Reload!'),
          );

          // Trigger hot reload
          process.stdin.writeln('r');
        }
        if (line.contains('Reloaded ')) {
          if (!hotReloadDone.isCompleted) {
            hotReloadDone.complete();
          }
          process.stdin.writeln('q');
        }
        if (line.contains('Try again after fixing the above error(s).')) {
          if (!hotReloadDone.isCompleted) {
            hotReloadDone.completeError(Exception('Hot reload failed!'));
          }
          process.stdin.writeln('q');
        }
      }, onDone: stdoutDone.complete);

      process.stderr
          .transform(utf8.decoder)
          .listen(stderrBuffer.write, onDone: stderrDone.complete);

      // Wait for process to exit with a 45s timeout
      final int exitCode = await process.exitCode.timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          process.kill();
          return -1;
        },
      );

      await stdoutDone.future;
      await stderrDone.future;

      final combinedOutput = '$stdoutBuffer\n$stderrBuffer';
      expect(exitCode, 0, reason: 'run exit code: $exitCode. stdout/stderr:\n$combinedOutput');
      try {
        await expectLater(hotReloadDone.future, completes);
      } catch (e) {
        // ignore: avoid_print
        print('=== TEST RUN OUTPUT ===\n$combinedOutput\n=======================');
        rethrow;
      }
    },
  );
}

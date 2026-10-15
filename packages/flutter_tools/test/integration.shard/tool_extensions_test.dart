// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:file/file.dart';
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/platform.dart';

import '../src/common.dart';
import 'test_utils.dart';

void _seedProjectWithLinuxPrototypeExtension(Directory projectDir) {
  projectDir.createSync(recursive: true);
  final String flutterRoot = getFlutterRoot();
  final Directory flutterToolsDir = fileSystem
      .directory(flutterRoot)
      .childDirectory('packages')
      .childDirectory('flutter_tools');
  final Directory prototypeDir = flutterToolsDir
      .childDirectory('packages')
      .childDirectory('flutter_tools_extension_linux_prototype');

  final File pubspecFile = projectDir.childFile('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    pubspecFile.writeAsStringSync('''
name: test_ext_project
environment:
  sdk: ^3.7.0-0
dev_dependencies:
  flutter_tools_extension_linux_prototype:
    path: ${prototypeDir.path}
''');
  }

  final File sourcePackageConfig = flutterToolsDir
      .childDirectory('.dart_tool')
      .childFile('package_config.json');
  final sourcePackageConfigDirUri = Uri.directory(sourcePackageConfig.parent.absolute.path);
  final decoded = jsonDecode(sourcePackageConfig.readAsStringSync()) as Map<String, Object?>;
  final List<Map<String, Object?>> rawPackages = (decoded['packages']! as List<Object?>)
      .cast<Map<String, Object?>>();

  final rewrittenPackages = <Map<String, Object?>>[
    for (final Map<String, Object?> pkg in rawPackages)
      <String, Object?>{
        ...pkg,
        'rootUri': sourcePackageConfigDirUri
            .resolve(_ensureTrailingSlash(pkg['rootUri']! as String))
            .toString(),
      },
  ];

  projectDir.childDirectory('.dart_tool').childFile('package_config.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      const JsonEncoder.withIndent('  ')
          .convert(<String, Object?>{'configVersion': 2, 'packages': rewrittenPackages}),
    );
}

String _ensureTrailingSlash(String uriStr) => uriStr.endsWith('/') ? uriStr : '$uriStr/';

void main() {
  final bool isLinux = const LocalPlatform().isLinux;
  late Directory tempHome;
  late Directory workspaceProjectDir;
  late Map<String, String> baseEnv;

  setUpAll(() {
    tempHome = createResolvedTempDirectorySync('tool_extensions_home.');
    workspaceProjectDir = tempHome.childDirectory('workspace_project');
    _seedProjectWithLinuxPrototypeExtension(workspaceProjectDir);
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
      workingDirectory: workspaceProjectDir.path,
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
      workingDirectory: workspaceProjectDir.path,
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
      workingDirectory: workspaceProjectDir.path,
      environment: <String, String>{...baseEnv, 'FLUTTER_TOOL_EXTENSIONS': 'true'},
    );

    if (isLinux) {
      expect(result.stdout, contains('Linux Custom Extension Prototype Device'));
    } else {
      expect(result.stdout, isNot(contains('Linux Custom Extension Prototype Device')));
    }
    expect(result.exitCode, 0);
  });

  testWithoutContext('tool extensions are disabled by default and in safe mode', () async {
    final ProcessResult doctorResult = await processManager.run(
      <String>[flutterBin, 'doctor', '-v'],
      workingDirectory: workspaceProjectDir.path,
      environment: baseEnv,
    );
    expect(doctorResult.stdout, isNot(contains('Linux Custom Extension Prototype')));
    expect(doctorResult.exitCode, 0);

    final ProcessResult noExtFlagResult = await processManager.run(
      <String>[flutterBin, '--no-extensions', 'config', '--list'],
      workingDirectory: workspaceProjectDir.path,
      environment: <String, String>{...baseEnv, 'FLUTTER_TOOL_EXTENSIONS': 'true'},
    );
    expect(noExtFlagResult.stdout, isNot(contains('Extension Settings:')));
    expect(noExtFlagResult.exitCode, 0);

    final ProcessResult noExtEnvResult = await processManager.run(
      <String>[flutterBin, 'config', '--list'],
      workingDirectory: workspaceProjectDir.path,
      environment: <String, String>{
        ...baseEnv,
        'FLUTTER_TOOL_EXTENSIONS': 'true',
        'FLUTTER_NO_EXTENSIONS': '1',
      },
    );
    expect(noExtEnvResult.stdout, isNot(contains('Extension Settings:')));
    expect(noExtEnvResult.exitCode, 0);
  });

  testWithoutContext('flutter create with custom template succeeds when enabled', () async {
    final Directory projectDir = tempHome.childDirectory('custom_app');
    if (projectDir.existsSync()) {
      projectDir.deleteSync(recursive: true);
    }
    _seedProjectWithLinuxPrototypeExtension(projectDir);

    final ProcessResult result = await processManager.run(
      <String>[flutterBin, 'create', '--no-pub', '--template=custom-linux-app', projectDir.path],
      workingDirectory: workspaceProjectDir.path,
      environment: <String, String>{...baseEnv, 'FLUTTER_TOOL_EXTENSIONS': 'true'},
    );

    if (isLinux) {
      expect(result.exitCode, 0, reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
      expect(projectDir.existsSync(), isTrue);
      final File verificationFile = projectDir.childFile('.custom_device_extension_info');
      expect(verificationFile.existsSync(), isTrue);
      expect(
        verificationFile.readAsStringSync().trim(),
        'Custom Linux Device Extension App Template Verified',
      );
    } else {
      expect(
        result.exitCode,
        isNot(0),
        reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}',
      );
      expect(result.stderr, contains('custom-linux-app'));
    }
  });

  testWithoutContext('flutter create with custom template fails when disabled', () async {
    final Directory projectDir = tempHome.childDirectory('custom_app_disabled');
    if (projectDir.existsSync()) {
      projectDir.deleteSync(recursive: true);
    }

    final ProcessResult result = await processManager.run(
      <String>[flutterBin, 'create', '--template=custom-linux-app', projectDir.path],
      workingDirectory: workspaceProjectDir.path,
      environment: baseEnv, // disabled by default
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('is not an allowed value for option "--template"'));
    expect(projectDir.existsSync(), isFalse);
  });

  testWithoutContext(
    'in-place flutter create . --platforms=custom_linux succeeds when enabled',
    () async {
      final Directory projectDir = tempHome.childDirectory('in_place_custom_platform_app');
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }
      _seedProjectWithLinuxPrototypeExtension(projectDir);

      final ProcessResult result = await processManager.run(
        <String>[flutterBin, 'create', '--no-pub', '--platforms=custom_linux', '.'],
        workingDirectory: projectDir.path,
        environment: <String, String>{...baseEnv, 'FLUTTER_TOOL_EXTENSIONS': 'true'},
      );

      if (isLinux) {
        expect(result.exitCode, 0, reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
        final File verificationFile = projectDir.childFile('.custom_device_extension_info');
        expect(verificationFile.existsSync(), isTrue);
        expect(
          verificationFile.readAsStringSync().trim(),
          'Custom Linux Device Extension App Template Verified',
        );
      } else {
        expect(result.exitCode, isNot(0));
      }
    },
  );

  testWithoutContext('flutter build with custom target succeeds when enabled', () async {
    if (!isLinux) {
      return;
    }
    final Directory projectDir = tempHome.childDirectory('custom_build_app');
    if (projectDir.existsSync()) {
      projectDir.deleteSync(recursive: true);
    }

    final ProcessResult createResult = await processManager.run(
      <String>[flutterBin, 'create', '--template=custom-linux-app', projectDir.path],
      workingDirectory: workspaceProjectDir.path,
      environment: <String, String>{...baseEnv, 'FLUTTER_TOOL_EXTENSIONS': 'true'},
    );
    expect(
      createResult.exitCode,
      0,
      reason: 'stdout: ${createResult.stdout}\nstderr: ${createResult.stderr}',
    );
    _seedProjectWithLinuxPrototypeExtension(projectDir);

    final ProcessResult buildResult = await processManager.run(
      <String>[flutterBin, 'build', 'custom-linux-build', '--debug'],
      workingDirectory: projectDir.path,
      environment: <String, String>{...baseEnv, 'FLUTTER_TOOL_EXTENSIONS': 'true'},
    );

    expect(
      buildResult.exitCode,
      0,
      reason: 'stdout: ${buildResult.stdout}\nstderr: ${buildResult.stderr}',
    );
    final Directory bundleDir = projectDir
        .childDirectory('build')
        .childDirectory('linux_extension')
        .childDirectory('x64')
        .childDirectory('debug')
        .childDirectory('bundle');
    expect(bundleDir.existsSync(), isTrue);
    expect(bundleDir.childFile('custom_build_app').existsSync(), isTrue);
    expect(
      bundleDir.childDirectory('lib').childFile('libflutter_linux_gtk.so').existsSync(),
      isTrue,
    );
    expect(bundleDir.childDirectory('data').childFile('icudtl.dat').existsSync(), isTrue);
    expect(
      bundleDir
          .childDirectory('data')
          .childDirectory('flutter_assets')
          .childFile('kernel_blob.bin')
          .existsSync(),
      isTrue,
    );
  });

  testWithoutContext(
    'flutter assemble with non-top-level custom target succeeds when enabled',
    () async {
      if (!isLinux) {
        return;
      }
      final Directory projectDir = tempHome.childDirectory('custom_assemble_app');
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }

      final ProcessResult createResult = await processManager.run(
        <String>[flutterBin, 'create', '--template=custom-linux-app', projectDir.path],
        workingDirectory: workspaceProjectDir.path,
        environment: <String, String>{...baseEnv, 'FLUTTER_TOOL_EXTENSIONS': 'true'},
      );
      expect(createResult.exitCode, 0);
      _seedProjectWithLinuxPrototypeExtension(projectDir);

      final Directory outputDir = projectDir.childDirectory('custom_assemble_out');
      final ProcessResult assembleResult = await processManager.run(
        <String>[
          flutterBin,
          'assemble',
          '--output=${outputDir.path}',
          '-dTargetPlatform=linux-x64',
          '-dBuildMode=debug',
          'custom-linux-assemble-only-debug',
        ],
        workingDirectory: projectDir.path,
        environment: <String, String>{...baseEnv, 'FLUTTER_TOOL_EXTENSIONS': 'true'},
      );

      expect(
        assembleResult.exitCode,
        0,
        reason: 'stdout: ${assembleResult.stdout}\nstderr: ${assembleResult.stderr}',
      );
      final Directory bundleDir = outputDir.childDirectory('bundle');
      expect(
        bundleDir.childDirectory('lib').childFile('libflutter_linux_gtk.so').existsSync(),
        isTrue,
      );
      expect(bundleDir.childDirectory('data').childFile('icudtl.dat').existsSync(), isTrue);
      expect(
        bundleDir
            .childDirectory('data')
            .childDirectory('flutter_assets')
            .childFile('kernel_blob.bin')
            .existsSync(),
        isTrue,
      );
    },
  );

  testWithoutContext(
    'flutter run and hot reload on custom extension device succeeds when enabled',
    () async {
      if (!isLinux) {
        return;
      }
      final bool hasXvfb = processManager.canRun('xvfb-run');
      final String? display = const LocalPlatform().environment['DISPLAY'];
      if (!hasXvfb && (display == null || display.isEmpty)) {
        return;
      }

      final Directory projectDir = tempHome.childDirectory('custom_run_app');
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }

      final ProcessResult createResult = await processManager.run(
        <String>[flutterBin, 'create', '--template=custom-linux-app', projectDir.path],
        workingDirectory: workspaceProjectDir.path,
        environment: <String, String>{...baseEnv, 'FLUTTER_TOOL_EXTENSIONS': 'true'},
      );
      expect(createResult.exitCode, 0);
      _seedProjectWithLinuxPrototypeExtension(projectDir);

      final File mainDart = projectDir.childDirectory('lib').childFile('main.dart');
      mainDart.writeAsStringSync('''
import 'package:flutter/material.dart';

void main() {
  print('APP_STARTED_MARKER');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    print('BUILDING_WIDGET_V1');
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('V1')),
      ),
    );
  }
}
''');

      final runCommand = <String>[
        if (hasXvfb) ...<String>['xvfb-run', '-a'],
        flutterBin,
        'run',
        '-d',
        'custom_linux_device',
      ];

      final Process process = await processManager.start(
        runCommand,
        workingDirectory: projectDir.path,
        environment: <String, String>{...baseEnv, 'FLUTTER_TOOL_EXTENSIONS': 'true'},
      );

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();
      final v1BuiltCompleter = Completer<void>();
      final v2BuiltCompleter = Completer<void>();

      process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((String line) {
        stdoutBuffer.writeln(line);
        if (line.contains('BUILDING_WIDGET_V1') && !v1BuiltCompleter.isCompleted) {
          v1BuiltCompleter.complete();
        }
        if (line.contains('BUILDING_WIDGET_V2') && !v2BuiltCompleter.isCompleted) {
          v2BuiltCompleter.complete();
        }
      });

      process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((String line) {
        stderrBuffer.writeln(line);
      });

      try {
        await v1BuiltCompleter.future.timeout(const Duration(seconds: 90));

        // Modify main.dart and trigger hot reload
        mainDart.writeAsStringSync(
          mainDart.readAsStringSync().replaceAll('BUILDING_WIDGET_V1', 'BUILDING_WIDGET_V2'),
        );
        process.stdin.write('r');
        await process.stdin.flush();

        await v2BuiltCompleter.future.timeout(const Duration(seconds: 30));

        // Quit application
        process.stdin.write('q');
        await process.stdin.flush();
        final int exitCode = await process.exitCode.timeout(const Duration(seconds: 15));
        expect(exitCode, 0, reason: 'stdout:\n$stdoutBuffer\nstderr:\n$stderrBuffer');
      } finally {
        process.kill();
      }
    },
  );
}

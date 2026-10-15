// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:isolate';

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/os.dart';
import 'package:flutter_tools/src/experimental/extension_clean_manager.dart';
import 'package:flutter_tools/src/experimental/extension_discovery.dart';
import 'package:flutter_tools/src/experimental/extension_manager.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools_core/flutter_tools_core.dart' hide HostPlatform;
import 'package:flutter_tools_extension/flutter_tools_extension.dart';
import 'package:test/test.dart';

import '../../src/fakes.dart';

final class _FakeCleanService extends CleanService {
  _FakeCleanService(this.onClean);

  final Future<void> Function(CleanEnvironment environment) onClean;

  @override
  Future<void> clean(CleanEnvironment environment) => onClean(environment);
}

void main() {
  group('ExtensionCleanManager', () {
    late MemoryFileSystem fs;
    late BufferLogger logger;

    setUp(() {
      fs = MemoryFileSystem.test();
      logger = BufferLogger.test();
    });

    test('does nothing when tool extensions feature flag is disabled', () async {
      final manager = ExtensionManager(
        hostPlatform: HostPlatform.linux_x64,
        logger: logger,
        featureFlags: TestFeatureFlags(),
      );
      final cleanManager = ExtensionCleanManager(
        extensionManager: manager,
        featureFlags: TestFeatureFlags(),
        logger: logger,
      );

      final Directory projectDir = fs.directory('/project')..createSync(recursive: true);
      projectDir.childFile('pubspec.yaml').writeAsStringSync('name: test_app\n');
      final FlutterProject project = FlutterProject.fromDirectoryTest(projectDir, logger);

      await cleanManager.cleanProject(project);
      await manager.dispose();
    });

    test('invokes clean RPC on active extensions and preserves shared artifact cache', () async {
      final verifyPort = ReceivePort();
      addTearDown(verifyPort.close);
      final SendPort verifySendPort = verifyPort.sendPort;

      void entryPoint(SendPort sendPort) {
        ToolExtensionEntryPoint.run(
          sendPort,
          <ToolExtensionService>[
            _FakeCleanService((CleanEnvironment env) async {
              verifySendPort.send(env.toJson());
            }),
          ],
          extensionName: 'clean_ext',
          supportedPlatforms: const <String>{'linux'},
        );
      }

      final manager = ExtensionManager(
        hostPlatform: HostPlatform.linux_x64,
        logger: logger,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
        entryPoints: <ExtensionEntryPoint>[entryPoint],
      );

      final cleanManager = ExtensionCleanManager(
        extensionManager: manager,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
        logger: logger,
      );

      final Directory sharedArtifactCache = fs.directory(
        '/dart_data/flutter_tool_extensions/artifacts/clean_ext/abc123',
      )..createSync(recursive: true);
      final File cachedArtifact = sharedArtifactCache.childFile('cached_bin')
        ..writeAsStringSync('cached');

      final Directory projectDir = fs.directory('/my_project')..createSync(recursive: true);
      projectDir.childFile('pubspec.yaml').writeAsStringSync('name: test_app\n');
      final FlutterProject project = FlutterProject.fromDirectoryTest(projectDir, logger);

      await cleanManager.cleanProject(project);

      final Object? rawReceived = await verifyPort.first;
      final receivedEnv = CleanEnvironment.fromJson(
        (rawReceived! as Map<Object?, Object?>).cast<String, Object?>(),
      );
      expect(receivedEnv.projectRoot, project.directory.absolute.uri);
      expect(receivedEnv.buildDir, project.buildDirectory.absolute.uri);
      expect(cachedArtifact.existsSync(), isTrue);

      await manager.dispose();
    });

    test('logs error when extension clean RPC throws without failing caller', () async {
      void failingEntryPoint(SendPort sendPort) {
        ToolExtensionEntryPoint.run(
          sendPort,
          <ToolExtensionService>[
            _FakeCleanService((CleanEnvironment _) async {
              throw StateError('Simulated extension clean failure');
            }),
          ],
          extensionName: 'failing_clean_ext',
          supportedPlatforms: const <String>{'linux'},
        );
      }

      final manager = ExtensionManager(
        hostPlatform: HostPlatform.linux_x64,
        logger: logger,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
        entryPoints: <ExtensionEntryPoint>[failingEntryPoint],
      );

      final cleanManager = ExtensionCleanManager(
        extensionManager: manager,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
        logger: logger,
      );

      final Directory projectDir = fs.directory('/my_project')..createSync(recursive: true);
      projectDir.childFile('pubspec.yaml').writeAsStringSync('name: test_app\n');
      final FlutterProject project = FlutterProject.fromDirectoryTest(projectDir, logger);

      await cleanManager.cleanProject(project);
      expect(logger.errorText, contains('Failed to clean extension "failing_clean_ext"'));

      await manager.dispose();
    });
  });
}

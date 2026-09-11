// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:isolate';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/experimental/extension_clean_manager.dart';
import 'package:flutter_tools/src/experimental/extension_discovery.dart';
import 'package:flutter_tools/src/experimental/extension_manager.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';
import 'package:flutter_tools_extension_linux_prototype/flutter_tools_extension_linux_prototype.dart';
import 'package:test/test.dart';

import '../../src/fakes.dart';

final class _ThrowingCleanService extends CleanService {
  @override
  Future<void> clean(CleanEnvironment environment) async {
    throw Exception('Clean failed inside extension isolate');
  }
}

void _throwingExtensionEntryPoint(SendPort sendPort) {
  ToolExtensionEntryPoint.run(
    sendPort,
    <ToolExtensionService>[_ThrowingCleanService()],
    extensionName: 'throwing_extension',
    supportedPlatforms: const <String>{'linux'},
  );
}

void main() {
  group('ExtensionCleanManager', () {
    late FileSystem fileSystem;
    late BufferLogger logger;
    late Directory tempDir;

    setUp(() {
      fileSystem = const LocalFileSystem();
      logger = BufferLogger.test();
      tempDir = fileSystem.systemTempDirectory.createTempSync('clean_manager_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('cleanProject returns early when tool extensions are disabled', () async {
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

      final FlutterProject project = FlutterProject.fromDirectoryTest(tempDir);
      await cleanManager.cleanProject(project);

      expect(logger.traceText, isEmpty);
      expect(logger.warningText, isEmpty);
    });

    test('cleanProject invokes clean on active extension connections', () async {
      final manager = ExtensionManager(
        hostPlatform: HostPlatform.linux_x64,
        logger: logger,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
      );
      await manager.initialize(entryPoints: <ExtensionEntryPoint>[linuxExtensionEntryPoint]);

      final cleanManager = ExtensionCleanManager(
        extensionManager: manager,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
        logger: logger,
      );

      final FlutterProject project = FlutterProject.fromDirectoryTest(tempDir);
      final Directory buildDir = tempDir.childDirectory('build');
      final Directory linuxBuildDir = buildDir.childDirectory('linux')..createSync(recursive: true);
      final File dummyFile = linuxBuildDir.childFile('liboutput.so')..writeAsStringSync('binary');
      expect(dummyFile.existsSync(), isTrue);

      await cleanManager.cleanProject(project);

      expect(linuxBuildDir.existsSync(), isFalse);
      expect(
        logger.traceText,
        contains(
          'Cleaning extension build artifacts for "flutter_tools_extension_linux_prototype"...',
        ),
      );

      await manager.dispose();
    });

    test(
      'cleanProject logs warning and does not crash when extension throws during clean',
      () async {
        final manager = ExtensionManager(
          hostPlatform: HostPlatform.linux_x64,
          logger: logger,
          featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
        );
        await manager.initialize(entryPoints: <ExtensionEntryPoint>[_throwingExtensionEntryPoint]);

        final cleanManager = ExtensionCleanManager(
          extensionManager: manager,
          featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
          logger: logger,
        );

        final FlutterProject project = FlutterProject.fromDirectoryTest(tempDir);
        await cleanManager.cleanProject(project);

        expect(logger.warningText, contains('Extension "throwing_extension" failed during clean:'));

        await manager.dispose();
      },
    );
  });
}

// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' as io;
import 'dart:isolate';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/experimental/extension_artifact_manager.dart';
import 'package:flutter_tools/src/experimental/extension_discovery.dart';
import 'package:flutter_tools/src/experimental/extension_manager.dart';
import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';
import 'package:flutter_tools_extension_linux_prototype/flutter_tools_extension_linux_prototype.dart';
import 'package:test/test.dart';

import '../../src/fakes.dart';

final class _CorruptArtifactService extends ArtifactService {
  @override
  Set<ArtifactDependency> get artifacts => <ArtifactDependency>{
    const ArtifactDependency(
      hostPlatform: 'linux-x64',
      name: 'corrupted-binary',
      sha256Checksums: <String, String>{
        'linux-x64': 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
      },
      targetArchitecture: 'x64',
      targetPlatform: 'linux',
    ),
  };

  @override
  Future<void> downloadArtifacts(
    Set<String> artifactNames, {
    required BuildMode buildMode,
    required Uri destinationDirectory,
    required HostPlatform hostPlatform,
    required TargetPlatform targetPlatform,
  }) async {
    final destinationDir = io.Directory.fromUri(destinationDirectory);
    if (!destinationDir.existsSync()) {
      destinationDir.createSync(recursive: true);
    }
    final file = io.File('${destinationDir.path}/corrupted-binary');
    file.writeAsStringSync('corrupted data\n');
  }
}

final class _FailingDownloadService extends ArtifactService {
  @override
  Set<ArtifactDependency> get artifacts => <ArtifactDependency>{
    const ArtifactDependency(
      hostPlatform: 'linux-x64',
      name: 'missing-binary',
      sha256Checksums: <String, String>{},
      targetArchitecture: 'x64',
      targetPlatform: 'linux',
    ),
  };

  @override
  Future<void> downloadArtifacts(
    Set<String> artifactNames, {
    required BuildMode buildMode,
    required Uri destinationDirectory,
    required HostPlatform hostPlatform,
    required TargetPlatform targetPlatform,
  }) async {
    // Intentionally does not create the file.
  }
}

void _corruptExtensionEntryPoint(SendPort sendPort) {
  ToolExtensionEntryPoint.run(
    sendPort,
    <ToolExtensionService>[_CorruptArtifactService()],
    extensionName: 'corrupt_extension',
    supportedPlatforms: const <String>{'linux'},
  );
}

void _failingExtensionEntryPoint(SendPort sendPort) {
  ToolExtensionEntryPoint.run(
    sendPort,
    <ToolExtensionService>[_FailingDownloadService()],
    extensionName: 'failing_extension',
    supportedPlatforms: const <String>{'linux'},
  );
}

void main() {
  group('ExtensionArtifactManager', () {
    late FileSystem fileSystem;
    late BufferLogger logger;
    late Directory tempDir;

    setUp(() {
      fileSystem = const LocalFileSystem();
      logger = BufferLogger.test();
      tempDir = fileSystem.systemTempDirectory.createTempSync('artifact_manager_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('resolves destination directory in .dart_tool/flutter_tools/artifacts', () {
      final manager = ExtensionManager(
        hostPlatform: HostPlatform.linux_x64,
        logger: logger,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
      );
      final artifactManager = ExtensionArtifactManager(
        extensionManager: manager,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
        fileSystem: fileSystem,
        logger: logger,
      );

      final Directory dir = artifactManager.getArtifactDirectory(
        'test_ext',
        projectRoot: tempDir.uri,
      );
      expect(
        dir.path,
        fileSystem.path.join(tempDir.path, '.dart_tool', 'flutter_tools', 'artifacts', 'test_ext'),
      );
    });

    test('getArtifactDependencies returns empty when feature flags disabled', () async {
      final manager = ExtensionManager(
        hostPlatform: HostPlatform.linux_x64,
        logger: logger,
        featureFlags: TestFeatureFlags(),
      );
      final artifactManager = ExtensionArtifactManager(
        extensionManager: manager,
        featureFlags: TestFeatureFlags(),
        fileSystem: fileSystem,
        logger: logger,
      );

      final Map<String, Set<ArtifactDependency>> dependencies = await artifactManager
          .getArtifactDependencies();
      expect(dependencies, isEmpty);
    });

    test('downloads, verifies SHA-256, and skips re-downloading existing artifacts', () async {
      final manager = ExtensionManager(
        hostPlatform: HostPlatform.linux_x64,
        logger: logger,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
      );
      await manager.initialize(entryPoints: <ExtensionEntryPoint>[linuxExtensionEntryPoint]);

      final artifactManager = ExtensionArtifactManager(
        extensionManager: manager,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
        fileSystem: fileSystem,
        logger: logger,
      );

      final Map<String, Set<ArtifactDependency>> dependencies = await artifactManager
          .getArtifactDependencies();
      expect(dependencies, contains('flutter_tools_extension_linux_prototype'));
      expect(dependencies['flutter_tools_extension_linux_prototype'], hasLength(1));
      expect(dependencies['flutter_tools_extension_linux_prototype']!.first.name, 'linux-headers');

      final Directory artifactDir = artifactManager.getArtifactDirectory(
        'flutter_tools_extension_linux_prototype',
        projectRoot: tempDir.uri,
      );
      expect(artifactDir.existsSync(), isFalse);

      await artifactManager.ensureArtifactsDownloaded(projectRoot: tempDir.uri);

      expect(artifactDir.existsSync(), isTrue);
      final File artifactFile = artifactDir.childFile('linux-headers');
      expect(artifactFile.existsSync(), isTrue);
      expect(artifactFile.readAsStringSync(), 'artifact payload for linux-headers\n');

      logger.clear();
      await artifactManager.ensureArtifactsDownloaded(projectRoot: tempDir.uri);
      expect(
        logger.traceText,
        contains(
          'All artifacts for extension "flutter_tools_extension_linux_prototype" are up to date.',
        ),
      );

      await manager.dispose();
    });

    test('throws ToolExit when downloaded file is missing', () async {
      final manager = ExtensionManager(
        hostPlatform: HostPlatform.linux_x64,
        logger: logger,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
      );
      await manager.initialize(entryPoints: <ExtensionEntryPoint>[_failingExtensionEntryPoint]);

      final artifactManager = ExtensionArtifactManager(
        extensionManager: manager,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
        fileSystem: fileSystem,
        logger: logger,
      );

      await expectLater(
        () => artifactManager.ensureArtifactsDownloaded(projectRoot: tempDir.uri),
        throwsA(
          isA<ToolExit>().having(
            (ToolExit e) => e.message,
            'message',
            contains('Expected artifact "missing-binary" was not found'),
          ),
        ),
      );

      await manager.dispose();
    });

    test('throws ToolExit when SHA-256 checksum verification fails', () async {
      final manager = ExtensionManager(
        hostPlatform: HostPlatform.linux_x64,
        logger: logger,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
      );
      await manager.initialize(entryPoints: <ExtensionEntryPoint>[_corruptExtensionEntryPoint]);

      final artifactManager = ExtensionArtifactManager(
        extensionManager: manager,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
        fileSystem: fileSystem,
        logger: logger,
      );

      await expectLater(
        () => artifactManager.ensureArtifactsDownloaded(projectRoot: tempDir.uri),
        throwsA(
          isA<ToolExit>().having(
            (ToolExit e) => e.message,
            'message',
            contains('SHA-256 verification failed for artifact "corrupted-binary"'),
          ),
        ),
      );

      final Directory artifactDir = artifactManager.getArtifactDirectory(
        'corrupt_extension',
        projectRoot: tempDir.uri,
      );
      expect(artifactDir.childFile('corrupted-binary').existsSync(), isFalse);

      await manager.dispose();
    });

    test('precache triggers ensureArtifactsDownloaded', () async {
      final manager = ExtensionManager(
        hostPlatform: HostPlatform.linux_x64,
        logger: logger,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
      );
      await manager.initialize(entryPoints: <ExtensionEntryPoint>[linuxExtensionEntryPoint]);

      final artifactManager = ExtensionArtifactManager(
        extensionManager: manager,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
        fileSystem: fileSystem,
        logger: logger,
      );

      await artifactManager.precache(projectRoot: tempDir.uri);

      final Directory artifactDir = artifactManager.getArtifactDirectory(
        'flutter_tools_extension_linux_prototype',
        projectRoot: tempDir.uri,
      );
      expect(artifactDir.childFile('linux-headers').existsSync(), isTrue);

      await manager.dispose();
    });
  });
}

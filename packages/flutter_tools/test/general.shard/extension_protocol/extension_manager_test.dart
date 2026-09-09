// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:isolate';

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/os.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/experimental/extension_discovery.dart';
import 'package:flutter_tools/src/experimental/extension_manager.dart';
import 'package:flutter_tools/src/experimental/extension_manifest.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';
import 'package:json_rpc_2/json_rpc_2.dart' as json_rpc;
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

import '../../src/fakes.dart';

ExtensionConnection _createFakeConnection({
  required ToolExtensionCapabilities capabilities,
  required Logger logger,
}) {
  final serverController = StreamController<Object?>();
  final clientController = StreamController<Object?>();
  final serverChannel = StreamChannel<Object?>(clientController.stream, serverController.sink);
  final clientChannel = StreamChannel<Object?>(serverController.stream, clientController.sink);

  final serverPeer = json_rpc.Peer.withoutJson(serverChannel);
  unawaited(serverPeer.listen());

  final clientPeer = json_rpc.Peer.withoutJson(clientChannel);
  unawaited(clientPeer.listen());

  return ExtensionConnection.custom(capabilities: capabilities, peer: clientPeer, logger: logger);
}

void _dummyExtensionEntryPoint(SendPort sendPort) {
  ToolExtensionEntryPoint.run(sendPort, <ToolExtensionService>[]);
}

void _linuxOnlyExtensionEntryPoint(SendPort sendPort) {
  ToolExtensionEntryPoint.run(
    sendPort,
    <ToolExtensionService>[],
    supportedPlatforms: const <String>{'linux'},
  );
}

void main() {
  group('ExtensionManager Integration', () {
    test('ExtensionManager loads extension compatible with hostPlatform', () async {
      final logger = BufferLogger.test();
      final manager = ExtensionManager(
        hostPlatform: HostPlatform.linux_x64,
        logger: logger,
        fileSystem: MemoryFileSystem.test(),
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
      );
      await manager.initialize(entryPoints: <ExtensionEntryPoint>[_dummyExtensionEntryPoint]);

      expect(manager.connections, hasLength(1));
      await manager.dispose();
      expect(manager.connections, isEmpty);
    });

    test('ExtensionManager filters out extension incompatible with hostPlatform', () async {
      final logger = BufferLogger.test();
      final manager = ExtensionManager(
        hostPlatform: HostPlatform.darwin_arm64,
        logger: logger,
        fileSystem: MemoryFileSystem.test(),
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
      );
      await manager.initialize(entryPoints: <ExtensionEntryPoint>[_linuxOnlyExtensionEntryPoint]);

      expect(manager.connections, isEmpty);
      await manager.dispose();
    });

    test('ExtensionManager exposes default and custom manifestFinder', () async {
      final logger = BufferLogger.test();
      final fs = MemoryFileSystem.test();
      final manager = ExtensionManager(
        hostPlatform: HostPlatform.linux_x64,
        logger: logger,
        fileSystem: fs,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
      );

      expect(manager.manifestFinder, isNotNull);

      final customFinder = ExtensionManifestFinder(fileSystem: fs, logger: logger);
      final customManager = ExtensionManager(
        hostPlatform: HostPlatform.linux_x64,
        logger: logger,
        fileSystem: fs,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
        manifestFinder: customFinder,
      );

      expect(customManager.manifestFinder, equals(customFinder));
    });

    test('isSafeMode returns true when FLUTTER_NO_EXTENSIONS is set', () {
      final safePlatforms = <Platform>[
        FakePlatform(environment: <String, String>{'FLUTTER_NO_EXTENSIONS': '1'}),
        FakePlatform(environment: <String, String>{'FLUTTER_NO_EXTENSIONS': 'true'}),
        FakePlatform(environment: <String, String>{'FLUTTER_NO_EXTENSIONS': 'yes'}),
        FakePlatform(environment: <String, String>{'FLUTTER_NO_EXTENSIONS': ' TRUE '}),
      ];

      for (final platform in safePlatforms) {
        final manager = ExtensionManager(
          hostPlatform: HostPlatform.linux_x64,
          logger: BufferLogger.test(),
          fileSystem: MemoryFileSystem.test(),
          platform: platform,
          featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
        );
        expect(manager.isSafeMode, isTrue);
      }
    });

    test('isSafeMode returns false when FLUTTER_NO_EXTENSIONS is not set or false', () {
      final normalPlatforms = <Platform>[
        FakePlatform(),
        FakePlatform(environment: <String, String>{'FLUTTER_NO_EXTENSIONS': '0'}),
        FakePlatform(environment: <String, String>{'FLUTTER_NO_EXTENSIONS': 'false'}),
        FakePlatform(environment: <String, String>{'FLUTTER_NO_EXTENSIONS': 'no'}),
      ];

      for (final platform in normalPlatforms) {
        final manager = ExtensionManager(
          hostPlatform: HostPlatform.linux_x64,
          logger: BufferLogger.test(),
          fileSystem: MemoryFileSystem.test(),
          platform: platform,
          featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
        );
        expect(manager.isSafeMode, isFalse);
      }
    });

    test('ensureInitialized bypasses discovery and isolate spawning in safe mode', () async {
      final logger = BufferLogger.test();
      final manager = ExtensionManager(
        hostPlatform: HostPlatform.linux_x64,
        logger: logger,
        fileSystem: MemoryFileSystem.test(),
        platform: FakePlatform(environment: <String, String>{'FLUTTER_NO_EXTENSIONS': '1'}),
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
      );

      await manager.ensureInitialized();
      expect(manager.connections, isEmpty);
      expect(manager.isInitialized, isTrue);
    });

    test(
      'ExtensionManager initializes cleanly with default empty entryPoints and no manifests',
      () async {
        final logger = BufferLogger.test();
        final manager = ExtensionManager(
          hostPlatform: HostPlatform.linux_x64,
          logger: logger,
          fileSystem: MemoryFileSystem.test(),
          featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
        );

        await manager.ensureInitialized();
        expect(manager.connections, isEmpty);
        expect(manager.isInitialized, isTrue);
        await manager.dispose();
      },
    );

    test(
      'ExtensionManager dynamically discovers manifest and spawns isolate via spawner',
      () async {
        final fs = MemoryFileSystem.test();
        final logger = BufferLogger.test();
        final os = FakeOperatingSystemUtils();
        final Directory projectDir = fs.directory('/project')..createSync();
        fs.currentDirectory = projectDir;
        projectDir.childFile(ExtensionManifestFinder.kManifestFileName).writeAsStringSync('''
extensions:
  dynamic_ext:
    path: packages/dynamic_ext
''');
        final Directory extDir = projectDir.childDirectory('packages').childDirectory('dynamic_ext')
          ..createSync(recursive: true);
        extDir.childDirectory('bin').childFile('dynamic_ext.dart').createSync(recursive: true);

        var spawnerCalled = false;
        final manager = ExtensionManager(
          hostPlatform: os.hostPlatform,
          logger: logger,
          fileSystem: fs,
          featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
          spawner:
              (
                Uri entrypoint, {
                List<String> args = const <String>[],
                required Logger logger,
                Uri? packageConfigUri,
                Duration timeout = ExtensionConnection.defaultHandshakeTimeout,
              }) async {
                spawnerCalled = true;
                return _createFakeConnection(
                  capabilities: const ToolExtensionCapabilities(
                    services: <String>['diagnostics'],
                    supportedPlatforms: <String>{'linux'},
                  ),
                  logger: logger,
                );
              },
        );

        await manager.ensureInitialized(startDir: projectDir);
        expect(spawnerCalled, isTrue);
        expect(manager.connections, hasLength(1));
        expect(manager.isInitialized, isTrue);
        await manager.dispose();
      },
    );

    test('ExtensionManager dynamically skips disabled extension in discovered manifest', () async {
      final fs = MemoryFileSystem.test();
      final logger = BufferLogger.test();
      final os = FakeOperatingSystemUtils();
      final Directory projectDir = fs.directory('/project')..createSync();
      fs.currentDirectory = projectDir;
      projectDir.childFile(ExtensionManifestFinder.kManifestFileName).writeAsStringSync('''
extensions:
  disabled_ext:
    enabled: false
    path: packages/disabled_ext
''');
      final Directory extDir = projectDir.childDirectory('packages').childDirectory('disabled_ext')
        ..createSync(recursive: true);
      extDir.childDirectory('bin').childFile('disabled_ext.dart').createSync(recursive: true);

      var spawnerCalled = false;
      final manager = ExtensionManager(
        hostPlatform: os.hostPlatform,
        logger: logger,
        fileSystem: fs,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
        spawner:
            (
              Uri entrypoint, {
              List<String> args = const <String>[],
              required Logger logger,
              Uri? packageConfigUri,
              Duration timeout = ExtensionConnection.defaultHandshakeTimeout,
            }) async {
              spawnerCalled = true;
              return _createFakeConnection(
                capabilities: const ToolExtensionCapabilities(services: <String>['diagnostics']),
                logger: logger,
              );
            },
      );

      await manager.ensureInitialized(startDir: projectDir);
      expect(spawnerCalled, isFalse);
      expect(manager.connections, isEmpty);
      await manager.dispose();
    });

    test(
      'ExtensionManager dynamically skips extension incompatible with host platform in discovered manifest',
      () async {
        final fs = MemoryFileSystem.test();
        final logger = BufferLogger.test();
        final os = FakeOperatingSystemUtils(hostPlatform: HostPlatform.darwin_arm64);
        final Directory projectDir = fs.directory('/project')..createSync();
        fs.currentDirectory = projectDir;
        projectDir.childFile(ExtensionManifestFinder.kManifestFileName).writeAsStringSync('''
extensions:
  linux_ext:
    path: packages/linux_ext
    supportedPlatforms:
      - linux
''');
        final Directory extDir = projectDir.childDirectory('packages').childDirectory('linux_ext')
          ..createSync(recursive: true);
        extDir.childDirectory('bin').childFile('linux_ext.dart').createSync(recursive: true);

        var spawnerCalled = false;
        final manager = ExtensionManager(
          hostPlatform: os.hostPlatform,
          logger: logger,
          fileSystem: fs,
          featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
          spawner:
              (
                Uri entrypoint, {
                List<String> args = const <String>[],
                required Logger logger,
                Uri? packageConfigUri,
                Duration timeout = ExtensionConnection.defaultHandshakeTimeout,
              }) async {
                spawnerCalled = true;
                return _createFakeConnection(
                  capabilities: const ToolExtensionCapabilities(services: <String>['diagnostics']),
                  logger: logger,
                );
              },
        );

        await manager.ensureInitialized(startDir: projectDir);
        expect(spawnerCalled, isFalse);
        expect(manager.connections, isEmpty);
        await manager.dispose();
      },
    );

    test(
      'ensureInitialized bypasses discovery and isolate spawning when feature flag is disabled',
      () async {
        final logger = BufferLogger.test();
        final manager = ExtensionManager(
          hostPlatform: HostPlatform.linux_x64,
          logger: logger,
          fileSystem: MemoryFileSystem.test(),
          featureFlags: TestFeatureFlags(),
        );

        await manager.ensureInitialized();
        expect(manager.connections, isEmpty);
        expect(manager.isInitialized, isTrue);
      },
    );
  });
}

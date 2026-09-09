// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:isolate';

import 'package:file/memory.dart';

import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/os.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/experimental/extension_discovery.dart';
import 'package:flutter_tools/src/experimental/extension_manager.dart';
import 'package:flutter_tools/src/experimental/extension_manifest.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';
import 'package:test/test.dart';

import '../../src/fakes.dart';

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

// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:args/command_runner.dart';
import 'package:file/file.dart';
import 'package:flutter_tools/src/base/os.dart';
import 'package:flutter_tools/src/base/time.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/commands/config.dart';
import 'package:flutter_tools/src/doctor.dart';
import 'package:flutter_tools/src/experimental/extension_artifact_manager.dart';
import 'package:flutter_tools/src/experimental/extension_clean_manager.dart';
import 'package:flutter_tools/src/experimental/extension_discovery.dart';
import 'package:flutter_tools/src/experimental/extension_manager.dart';
import 'package:flutter_tools/src/features.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools_extension_linux_prototype/flutter_tools_extension_linux_prototype.dart';

import '../../src/context.dart';
import '../../src/fakes.dart';
import '../../src/test_flutter_command_runner.dart';

void main() {
  setUpAll(() {
    Cache.disableLocking();
  });

  group('Tool Extensions Integration - Disabled', () {
    testUsingContext(
      'ExtensionManager.ensureInitialized() is a no-op when feature flag disabled',
      () async {
        final featureFlags = TestFeatureFlags();
        final manager = ExtensionManager(
          hostPlatform: HostPlatform.linux_x64,
          logger: testLogger,
          fileSystem: globals.fs,
          entryPoints: <ExtensionEntryPoint>[linuxExtensionEntryPoint],
          featureFlags: featureFlags,
        );

        await manager.ensureInitialized();
        expect(manager.connections, isEmpty);
        await manager.dispose();
      },
      overrides: <Type, Generator>{FeatureFlags: () => TestFeatureFlags()},
    );

    testUsingContext(
      'ConfigCommand does not output Extension Settings when feature flag disabled',
      () async {
        final featureFlags = TestFeatureFlags();
        final manager = ExtensionManager(
          hostPlatform: HostPlatform.linux_x64,
          logger: testLogger,
          fileSystem: globals.fs,
          entryPoints: <ExtensionEntryPoint>[linuxExtensionEntryPoint],
          featureFlags: featureFlags,
        );
        final configCommand = ConfigCommand(extensionManager: manager);
        final CommandRunner<void> commandRunner = createTestCommandRunner(configCommand);

        await commandRunner.run(<String>['config', '--list']);
        expect(testLogger.statusText, isNot(contains('Extension Settings:')));

        await manager.dispose();
      },
      overrides: <Type, Generator>{FeatureFlags: () => TestFeatureFlags()},
    );

    testUsingContext(
      'Doctor.diagnose does not execute extension validators when feature flag disabled',
      () async {
        final featureFlags = TestFeatureFlags();
        final manager = ExtensionManager(
          hostPlatform: HostPlatform.linux_x64,
          logger: testLogger,
          fileSystem: globals.fs,
          entryPoints: <ExtensionEntryPoint>[linuxExtensionEntryPoint],
          featureFlags: featureFlags,
        );
        final doctor = Doctor(logger: testLogger, clock: const SystemClock());

        await doctor.diagnose(extensionManager: manager);
        expect(testLogger.statusText, isNot(contains('Linux Custom Extension Prototype')));

        await manager.dispose();
      },
      overrides: <Type, Generator>{FeatureFlags: () => TestFeatureFlags()},
    );

    testUsingContext(
      'ExtensionArtifactManager.precache() does not download artifacts when feature flag disabled',
      () async {
        final featureFlags = TestFeatureFlags();
        final manager = ExtensionManager(
          hostPlatform: HostPlatform.linux_x64,
          logger: testLogger,
          fileSystem: globals.fs,
          entryPoints: <ExtensionEntryPoint>[linuxExtensionEntryPoint],
          featureFlags: featureFlags,
        );
        final artifactManager = ExtensionArtifactManager(
          extensionManager: manager,
          featureFlags: featureFlags,
          fileSystem: globals.fs,
          logger: testLogger,
        );

        await artifactManager.precache();
        expect(testLogger.statusText, isNot(contains('Downloading')));

        await manager.dispose();
      },
      overrides: <Type, Generator>{FeatureFlags: () => TestFeatureFlags()},
    );

    testUsingContext(
      'ExtensionCleanManager.cleanProject() does not clean extension build directory when feature flag disabled',
      () async {
        final featureFlags = TestFeatureFlags();
        final manager = ExtensionManager(
          hostPlatform: HostPlatform.linux_x64,
          logger: testLogger,
          fileSystem: globals.fs,
          entryPoints: <ExtensionEntryPoint>[linuxExtensionEntryPoint],
          featureFlags: featureFlags,
        );
        final cleanManager = ExtensionCleanManager(
          extensionManager: manager,
          featureFlags: featureFlags,
          logger: testLogger,
        );
        final Directory projectDir = globals.fs.systemTempDirectory.createTempSync(
          'clean_test_disabled',
        );
        final Directory linuxBuildDir = projectDir.childDirectory('build').childDirectory('linux')
          ..createSync(recursive: true);
        final File dummyFile = linuxBuildDir.childFile('dummy.txt')..writeAsStringSync('dummy');
        final FlutterProject project = FlutterProject.fromDirectory(projectDir);

        await cleanManager.cleanProject(project);
        expect(dummyFile.existsSync(), isTrue);

        await manager.dispose();
      },
      overrides: <Type, Generator>{FeatureFlags: () => TestFeatureFlags()},
    );
  });

  group('Tool Extensions Integration - Enabled', () {
    testUsingContext(
      'ExtensionManager.ensureInitialized() initializes connections when feature flag enabled',
      () async {
        final featureFlags = TestFeatureFlags(isToolExtensionsEnabled: true);
        final manager = ExtensionManager(
          hostPlatform: HostPlatform.linux_x64,
          logger: testLogger,
          fileSystem: globals.fs,
          entryPoints: <ExtensionEntryPoint>[linuxExtensionEntryPoint],
          featureFlags: featureFlags,
        );

        await manager.ensureInitialized();
        expect(manager.connections, isNotEmpty);
        await manager.dispose();
      },
      overrides: <Type, Generator>{
        FeatureFlags: () => TestFeatureFlags(isToolExtensionsEnabled: true),
      },
    );

    testUsingContext(
      'ConfigCommand outputs Extension Settings when feature flag enabled',
      () async {
        final featureFlags = TestFeatureFlags(isToolExtensionsEnabled: true);
        final manager = ExtensionManager(
          hostPlatform: HostPlatform.linux_x64,
          logger: testLogger,
          fileSystem: globals.fs,
          entryPoints: <ExtensionEntryPoint>[linuxExtensionEntryPoint],
          featureFlags: featureFlags,
        );
        final configCommand = ConfigCommand(extensionManager: manager);
        final CommandRunner<void> commandRunner = createTestCommandRunner(configCommand);

        await commandRunner.run(<String>['config', '--list']);
        expect(testLogger.statusText, contains('Extension Settings:'));

        await manager.dispose();
      },
      overrides: <Type, Generator>{
        FeatureFlags: () => TestFeatureFlags(isToolExtensionsEnabled: true),
      },
    );

    testUsingContext(
      'Doctor.diagnose executes extension validators when feature flag enabled',
      () async {
        final featureFlags = TestFeatureFlags(isToolExtensionsEnabled: true);
        final manager = ExtensionManager(
          hostPlatform: HostPlatform.linux_x64,
          logger: testLogger,
          fileSystem: globals.fs,
          entryPoints: <ExtensionEntryPoint>[linuxExtensionEntryPoint],
          featureFlags: featureFlags,
        );
        final doctor = Doctor(logger: testLogger, clock: const SystemClock());

        await doctor.diagnose(extensionManager: manager);
        expect(testLogger.statusText, contains('[✓] Linux Custom Extension Prototype'));

        await manager.dispose();
      },
      overrides: <Type, Generator>{
        FeatureFlags: () => TestFeatureFlags(isToolExtensionsEnabled: true),
      },
    );

    testUsingContext(
      'ExtensionArtifactManager.precache() downloads extension artifacts when feature flag enabled',
      () async {
        final featureFlags = TestFeatureFlags(isToolExtensionsEnabled: true);
        final manager = ExtensionManager(
          hostPlatform: HostPlatform.linux_x64,
          logger: testLogger,
          fileSystem: globals.fs,
          entryPoints: <ExtensionEntryPoint>[linuxExtensionEntryPoint],
          featureFlags: featureFlags,
        );
        final artifactManager = ExtensionArtifactManager(
          extensionManager: manager,
          featureFlags: featureFlags,
          fileSystem: globals.fs,
          logger: testLogger,
        );

        final Directory projectDir = globals.fs.systemTempDirectory.createTempSync(
          'precache_test_enabled',
        );
        await artifactManager.precache(projectRoot: projectDir.uri);

        expect(
          testLogger.statusText,
          contains(
            'Downloading 1 artifact(s) for extension "flutter_tools_extension_linux_prototype"...',
          ),
        );
        final File artifactFile = artifactManager
            .getArtifactDirectory(
              'flutter_tools_extension_linux_prototype',
              projectRoot: projectDir.uri,
            )
            .childFile('linux-headers');
        expect(artifactFile.existsSync(), isTrue);
        expect(artifactFile.readAsStringSync(), contains('artifact payload for linux-headers'));

        await manager.dispose();
      },
      overrides: <Type, Generator>{
        FeatureFlags: () => TestFeatureFlags(isToolExtensionsEnabled: true),
      },
    );

    testUsingContext(
      'ExtensionCleanManager.cleanProject() cleans extension build directory when feature flag enabled',
      () async {
        final featureFlags = TestFeatureFlags(isToolExtensionsEnabled: true);
        final manager = ExtensionManager(
          hostPlatform: HostPlatform.linux_x64,
          logger: testLogger,
          fileSystem: globals.fs,
          entryPoints: <ExtensionEntryPoint>[linuxExtensionEntryPoint],
          featureFlags: featureFlags,
        );
        final cleanManager = ExtensionCleanManager(
          extensionManager: manager,
          featureFlags: featureFlags,
          logger: testLogger,
        );
        final Directory projectDir = globals.fs.systemTempDirectory.createTempSync(
          'clean_test_enabled',
        );
        final Directory linuxBuildDir = projectDir.childDirectory('build').childDirectory('linux')
          ..createSync(recursive: true);
        final File dummyFile = linuxBuildDir.childFile('dummy.txt')..writeAsStringSync('dummy');
        expect(dummyFile.existsSync(), isTrue);
        final FlutterProject project = FlutterProject.fromDirectory(projectDir);

        await cleanManager.cleanProject(project);
        expect(linuxBuildDir.existsSync(), isFalse);

        await manager.dispose();
      },
      overrides: <Type, Generator>{
        FeatureFlags: () => TestFeatureFlags(isToolExtensionsEnabled: true),
      },
    );
  });
}

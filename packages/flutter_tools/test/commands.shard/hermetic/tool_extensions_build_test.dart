// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:args/command_runner.dart';
import 'package:file/memory.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/commands/assemble.dart';
import 'package:flutter_tools/src/commands/build.dart';
import 'package:flutter_tools/src/experimental/extension_build_manager.dart';
import 'package:flutter_tools/src/experimental/extension_discovery.dart';
import 'package:flutter_tools/src/experimental/extension_manager.dart';
import 'package:flutter_tools/src/features.dart';
import 'package:flutter_tools_core/flutter_tools_core.dart'
    hide Artifact, BuildMode, HostArtifact, Target;
import 'package:flutter_tools_extension_linux_prototype/flutter_tools_extension_linux_prototype.dart';

import '../../src/context.dart';
import '../../src/fakes.dart';
import '../../src/test_build_system.dart';
import '../../src/test_flutter_command_runner.dart';

void main() {
  setUpAll(() {
    Cache.disableLocking();
  });

  group('Tool Extensions Build Integration - Disabled', () {
    testUsingContext(
      'ExtensionBuildManager.getBuildTargets() returns empty list when feature flag disabled',
      () async {
        final featureFlags = TestFeatureFlags();
        final manager = ExtensionManager(
          hostPlatform: 'linux',
          logger: testLogger,
          entryPoints: <ExtensionEntryPoint>[linuxExtensionEntryPoint],
          featureFlags: featureFlags,
        );
        final buildManager = ExtensionBuildManager(
          extensionManager: manager,
          logger: testLogger,
          featureFlags: featureFlags,
        );

        final targets = <ExtensionBuildTarget>[...await buildManager.getBuildTargets()];
        expect(targets, isEmpty);

        await manager.dispose();
      },
      overrides: <Type, Generator>{FeatureFlags: () => TestFeatureFlags()},
    );

    testUsingContext(
      'BuildCommand does not include custom subcommands when feature flag disabled',
      () async {
        final featureFlags = TestFeatureFlags();
        final manager = ExtensionManager(
          hostPlatform: 'linux',
          logger: testLogger,
          entryPoints: <ExtensionEntryPoint>[linuxExtensionEntryPoint],
          featureFlags: featureFlags,
        );
        final buildManager = ExtensionBuildManager(
          extensionManager: manager,
          logger: testLogger,
          featureFlags: featureFlags,
        );

        final fs = MemoryFileSystem.test();
        final command = BuildCommand(
          androidSdk: FakeAndroidSdk(),
          buildSystem: TestBuildSystem.all(BuildResult(success: true)),
          fileSystem: fs,
          logger: testLogger,
          osUtils: FakeOperatingSystemUtils(),
          config: FakeConfig(),
          platform: FakePlatform(),
          fileSystemUtils: FakeFileSystemUtils(),
          terminal: FakeTerminal(),
          plistParser: FakePlistParser(),
          processUtils: FakeProcessUtils(),
          processManager: FakeProcessManager.any(),
          templateRenderer: FakeTemplateRenderer(),
          xcode: FakeXcode(),
          artifacts: Artifacts.test(fileSystem: fs),
          cache: FakeCache(),
          flutterVersion: FakeFlutterVersion(),
          extensionBuildManager: buildManager,
        );

        final CommandRunner<void> commandRunner = createTestCommandRunner(command);
        try {
          await commandRunner.run(<String>['build', '-h']);
        } on ToolExit {
          // Expected to exit or print help.
        }

        expect(command.subcommands.containsKey('custom-linux-build'), isFalse);

        await manager.dispose();
      },
      overrides: <Type, Generator>{FeatureFlags: () => TestFeatureFlags()},
    );
  });

  group('Tool Extensions Build Integration - Enabled', () {
    late MemoryFileSystem fs;

    setUp(() {
      fs = MemoryFileSystem.test();
      fs.file('/pubspec.yaml').createSync();
      fs.file('/lib/main.dart').createSync(recursive: true);
    });

    testUsingContext(
      'ExtensionBuildManager.getBuildTargets() returns custom targets when feature flag enabled',
      () async {
        final featureFlags = TestFeatureFlags(isToolExtensionsEnabled: true);
        final manager = ExtensionManager(
          hostPlatform: 'linux',
          logger: testLogger,
          entryPoints: <ExtensionEntryPoint>[linuxExtensionEntryPoint],
          featureFlags: featureFlags,
        );
        final buildManager = ExtensionBuildManager(
          extensionManager: manager,
          logger: testLogger,
          featureFlags: featureFlags,
        );

        final targets = <ExtensionBuildTarget>[...await buildManager.getBuildTargets()];
        expect(targets, hasLength(6));
        expect(targets[0].name, equals('custom-linux-build'));
        expect(targets[0].targetPlatform, equals('linux-x64'));
        expect(targets[0].isTopLevel, isTrue);
        expect(targets[0].dependencies, isEmpty);

        expect(targets[1].name, equals('custom-linux-assemble-only-debug'));
        expect(targets[1].targetPlatform, equals('linux-x64'));
        expect(targets[1].isTopLevel, isFalse);
        expect(targets[1].dependencies, equals(<String>['copy_assets', 'kernel_snapshot_program']));

        expect(targets[2].name, equals('custom-linux-aot-elf-profile'));
        expect(targets[2].targetPlatform, equals('linux-x64'));
        expect(targets[2].isTopLevel, isFalse);
        expect(targets[2].dependencies, isEmpty);

        expect(targets[3].name, equals('custom-linux-assemble-only-profile'));
        expect(targets[3].targetPlatform, equals('linux-x64'));
        expect(targets[3].isTopLevel, isFalse);
        expect(
          targets[3].dependencies,
          equals(<String>['copy_assets', 'custom-linux-aot-elf-profile']),
        );

        expect(targets[4].name, equals('custom-linux-aot-elf-release'));
        expect(targets[4].targetPlatform, equals('linux-x64'));
        expect(targets[4].isTopLevel, isFalse);
        expect(targets[4].dependencies, isEmpty);

        expect(targets[5].name, equals('custom-linux-assemble-only-release'));
        expect(targets[5].targetPlatform, equals('linux-x64'));
        expect(targets[5].isTopLevel, isFalse);
        expect(
          targets[5].dependencies,
          equals(<String>['copy_assets', 'custom-linux-aot-elf-release']),
        );
        await manager.dispose();
      },
      overrides: <Type, Generator>{
        FeatureFlags: () => TestFeatureFlags(isToolExtensionsEnabled: true),
      },
    );

    testUsingContext(
      'BuildCommand includes custom subcommand and can run it when feature flag enabled',
      () async {
        final featureFlags = TestFeatureFlags(isToolExtensionsEnabled: true);
        final manager = ExtensionManager(
          hostPlatform: 'linux',
          logger: testLogger,
          entryPoints: <ExtensionEntryPoint>[linuxExtensionEntryPoint],
          featureFlags: featureFlags,
        );
        final buildManager = ExtensionBuildManager(
          extensionManager: manager,
          logger: testLogger,
          featureFlags: featureFlags,
        );

        final command = BuildCommand(
          androidSdk: FakeAndroidSdk(),
          buildSystem: TestBuildSystem.all(BuildResult(success: true)),
          fileSystem: fs,
          logger: testLogger,
          osUtils: FakeOperatingSystemUtils(),
          config: FakeConfig(),
          platform: FakePlatform(),
          fileSystemUtils: FakeFileSystemUtils(),
          terminal: FakeTerminal(),
          plistParser: FakePlistParser(),
          processUtils: FakeProcessUtils(),
          processManager: FakeProcessManager.any(),
          templateRenderer: FakeTemplateRenderer(),
          xcode: FakeXcode(),
          artifacts: Artifacts.test(fileSystem: fs),
          cache: FakeCache(),
          flutterVersion: FakeFlutterVersion(),
          extensionBuildManager: buildManager,
        );

        final CommandRunner<void> commandRunner = createTestCommandRunner(command);

        await commandRunner.run(<String>['build', 'custom-linux-build', '--no-pub']);

        expect(command.subcommands.containsKey('custom-linux-build'), isTrue);
        expect(command.subcommands.containsKey('custom-linux-assemble-only-debug'), isFalse);

        await manager.dispose();
      },
      overrides: <Type, Generator>{
        FeatureFlags: () => TestFeatureFlags(isToolExtensionsEnabled: true),
        FileSystem: () => fs,
        ProcessManager: () => FakeProcessManager.any(),
      },
    );

    testUsingContext(
      'AssembleCommand includes custom targets and can run them when feature flag enabled',
      () async {
        final featureFlags = TestFeatureFlags(isToolExtensionsEnabled: true);
        final manager = ExtensionManager(
          hostPlatform: 'linux',
          logger: testLogger,
          entryPoints: <ExtensionEntryPoint>[linuxExtensionEntryPoint],
          featureFlags: featureFlags,
        );
        final buildManager = ExtensionBuildManager(
          extensionManager: manager,
          logger: testLogger,
          featureFlags: featureFlags,
        );

        final command = AssembleCommand(
          buildSystem: TestBuildSystem.all(BuildResult(success: true)),
          extensionBuildManager: buildManager,
        );

        final CommandRunner<void> commandRunner = createTestCommandRunner(command);

        await commandRunner.run(<String>[
          'assemble',
          '-o',
          '/out',
          '-d',
          'BuildMode=debug',
          'custom-linux-assemble-only-debug',
        ]);

        // Verify that the targets were created and dependencies can be resolved.
        final List<Target> targets = command.createTargets();
        expect(targets, hasLength(1));
        final Target target = targets.first;
        expect(target.name, equals('custom-linux-assemble-only-debug'));
        expect(target.dependencies, hasLength(2));
        expect(
          target.dependencies.map((Target t) => t.name),
          containsAll(<String>['copy_assets', 'kernel_snapshot_program']),
        );

        await manager.dispose();
      },
      overrides: <Type, Generator>{
        FeatureFlags: () => TestFeatureFlags(isToolExtensionsEnabled: true),
        FileSystem: () => fs,
        ProcessManager: () => FakeProcessManager.any(),
      },
    );

    testUsingContext(
      'BuildCommand includes custom subcommand in help when feature flag enabled',
      () async {
        final featureFlags = TestFeatureFlags(isToolExtensionsEnabled: true);
        final manager = ExtensionManager(
          hostPlatform: 'linux',
          logger: testLogger,
          entryPoints: <ExtensionEntryPoint>[linuxExtensionEntryPoint],
          featureFlags: featureFlags,
        );
        final buildManager = ExtensionBuildManager(
          extensionManager: manager,
          logger: testLogger,
          featureFlags: featureFlags,
        );

        final command = BuildCommand(
          androidSdk: FakeAndroidSdk(),
          buildSystem: TestBuildSystem.all(BuildResult(success: true)),
          fileSystem: fs,
          logger: testLogger,
          osUtils: FakeOperatingSystemUtils(),
          config: FakeConfig(),
          platform: FakePlatform(),
          fileSystemUtils: FakeFileSystemUtils(),
          terminal: FakeTerminal(),
          plistParser: FakePlistParser(),
          processUtils: FakeProcessUtils(),
          processManager: FakeProcessManager.any(),
          templateRenderer: FakeTemplateRenderer(),
          xcode: FakeXcode(),
          artifacts: Artifacts.test(fileSystem: fs),
          cache: FakeCache(),
          flutterVersion: FakeFlutterVersion(),
          extensionBuildManager: buildManager,
        );

        final CommandRunner<void> commandRunner = createTestCommandRunner(command);

        await commandRunner.run(<String>['build', '-h']);

        expect(command.subcommands.containsKey('custom-linux-build'), isTrue);

        await manager.dispose();
      },
      overrides: <Type, Generator>{
        FeatureFlags: () => TestFeatureFlags(isToolExtensionsEnabled: true),
        FileSystem: () => fs,
        ProcessManager: () => FakeProcessManager.any(),
      },
    );
  });
}

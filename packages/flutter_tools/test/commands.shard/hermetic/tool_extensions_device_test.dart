// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:file/memory.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/os.dart';
import 'package:flutter_tools/src/base/signals.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/commands/devices.dart';
import 'package:flutter_tools/src/device.dart';
import 'package:flutter_tools/src/experimental/extension_device_manager.dart';
import 'package:flutter_tools/src/experimental/extension_discovery.dart';
import 'package:flutter_tools/src/experimental/extension_manager.dart';
import 'package:flutter_tools/src/features.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools_core/flutter_tools_core.dart'
    show ExtensionBuildResult, ExtensionFlutterProject, TargetDevice;
import 'package:flutter_tools_extension/flutter_tools_extension.dart';
import 'package:flutter_tools_extension_linux_prototype/flutter_tools_extension_linux_prototype.dart';

import '../../src/common.dart';
import '../../src/context.dart';
import '../../src/fakes.dart';
import '../../src/test_flutter_command_runner.dart';

final class _FakeTestBuildTarget extends ExtensionTarget {
  const _FakeTestBuildTarget()
    : super(description: 'Fake test build target', targetPlatform: 'linux-x64');

  @override
  String get name => 'fake-test-build';

  @override
  Future<ExtensionBuildResult> build(ExtensionBuildContext context) async {
    return const ExtensionBuildResult(success: true, executablePath: '/tmp/fake_bundle/app');
  }
}

final class _FakeTestBuildService extends BuildService {
  @override
  List<ExtensionTarget> get targets => const <ExtensionTarget>[_FakeTestBuildTarget()];
}

final class _FakeTestDeviceService extends DeviceService {
  @override
  Future<List<TargetDevice>> getDevices() async {
    return const <TargetDevice>[
      TargetDevice(
        category: Category.desktop,
        id: 'fake_test_device',
        name: 'Fake Test Extension Device',
        buildTarget: 'fake-test-build',
        ephemeral: false,
        sdkNameAndVersion: 'Fake OS 1.0',
        targetPlatform: 'linux-x64',
      ),
    ];
  }

  @override
  Future<bool> isSupportedForProject({
    required String deviceId,
    required ExtensionFlutterProject project,
  }) async => deviceId == 'fake_test_device';

  @override
  Future<bool> launchApp(
    String deviceId,
    String executablePath, {
    Map<String, Object?>? debuggingOptions,
  }) async => deviceId == 'fake_test_device' && executablePath == '/tmp/fake_bundle/app';

  @override
  Future<String?> getVmServiceUri(String deviceId) async =>
      deviceId == 'fake_test_device' ? 'http://127.0.0.1:8181/abcd/' : null;

  @override
  Future<bool> stopApp(String deviceId) async => deviceId == 'fake_test_device';
}

void _fakeLaunchExtensionEntryPoint(SendPort sendPort) {
  ToolExtensionEntryPoint.run(
    sendPort,
    <ToolExtensionService>[_FakeTestBuildService(), _FakeTestDeviceService()],
    supportedPlatforms: const <String>{'linux'},
  );
}

void main() {
  setUpAll(() {
    Cache.disableLocking();
  });

  group('Tool Extensions Device Integration - Disabled', () {
    testUsingContext(
      'ExtensionDevices returns empty device list when feature flag disabled',
      () async {
        final featureFlags = TestFeatureFlags();
        final manager = ExtensionManager(
          hostPlatform: HostPlatform.linux_x64,
          logger: testLogger,
          entryPoints: <ExtensionEntryPoint>[linuxExtensionEntryPoint],
          featureFlags: featureFlags,
        );
        final discovery = ExtensionDevices(
          artifacts: Artifacts.test(),
          extensionManager: manager,
          fileSystem: MemoryFileSystem.test(),
          logger: testLogger,
        );

        final List<Device> devices = await discovery.devices();
        expect(devices, isEmpty);

        await manager.dispose();
      },
      overrides: <Type, Generator>{FeatureFlags: () => TestFeatureFlags()},
    );

    testUsingContext(
      'DevicesCommand output does not include custom extension devices when feature flag disabled',
      () async {
        final featureFlags = TestFeatureFlags();
        final manager = ExtensionManager(
          hostPlatform: HostPlatform.linux_x64,
          logger: testLogger,
          entryPoints: <ExtensionEntryPoint>[linuxExtensionEntryPoint],
          featureFlags: featureFlags,
        );
        final testDeviceManager = TestDeviceManager(
          discoverers: <DeviceDiscovery>[
            ExtensionDevices(
              artifacts: Artifacts.test(),
              extensionManager: manager,
              fileSystem: MemoryFileSystem.test(),
              logger: testLogger,
            ),
          ],
        );
        final devicesCommand = DevicesCommand(
          deviceManager: testDeviceManager,
          doctor: FakeDoctor(),
          toolContext: FakeToolContext(logger: testLogger),
        );
        final CommandRunner<void> commandRunner = createTestCommandRunner(devicesCommand);

        await commandRunner.run(<String>['devices']);
        expect(testLogger.statusText, isNot(contains('Linux Custom Extension Prototype Device')));

        await manager.dispose();
      },
      overrides: <Type, Generator>{
        FeatureFlags: () => TestFeatureFlags(),
        DeviceManager: () => TestDeviceManager(),
      },
    );
  });

  group('Tool Extensions Device Integration - Enabled', () {
    testUsingContext(
      'FlutterProject.toExtensionProject extracts project and manifest metadata',
      () async {
        final localFs = LocalFileSystem.test(signals: LocalSignals.instance);
        addTearDown(localFs.dispose);
        final Directory tempDir = localFs.systemTempDirectory.createTempSync(
          'flutter_tool_extensions_project_test.',
        );
        tempDir.childFile('pubspec.yaml').writeAsStringSync('''
name: sample_app
version: 2.1.0+5
workspace:
  - packages/sub_pkg
dependencies:
  flutter:
    sdk: flutter
  path: ^1.9.0
flutter:
  module:
    androidX: true
''');

        final projectFactory = FlutterProjectFactory(fileSystem: localFs, logger: testLogger);
        final FlutterProject project = projectFactory.fromDirectory(tempDir);
        final ExtensionFlutterProject extProject = project.toExtensionProject();

        expect(extProject.appName, 'sample_app');
        expect(extProject.appVersion, '2.1.0+5');
        expect(extProject.directory, project.directory.uri);
        expect(extProject.buildDirectory, project.buildDirectory.uri);
        expect(extProject.dependencies, <String>{'flutter', 'path'});
        expect(extProject.isEmpty, isFalse);
        expect(extProject.isModule, isTrue);
        expect(extProject.isPlugin, isFalse);
        expect(extProject.workspace, <String>['packages/sub_pkg']);
        expect(extProject.workspace.runtimeType, <String>[].runtimeType);
        expect(() => jsonEncode(extProject.toMap()), returnsNormally);
      },
    );

    testUsingContext(
      'ExtensionDevices discovers custom device when feature flag enabled',
      () async {
        final localFs = LocalFileSystem.test(signals: LocalSignals.instance);
        addTearDown(localFs.dispose);
        final Directory tempDir = localFs.systemTempDirectory.createTempSync(
          'flutter_tool_extensions_device_test.',
        );

        final projectFactory = FlutterProjectFactory(fileSystem: localFs, logger: testLogger);
        final FlutterProject project = projectFactory.fromDirectory(tempDir);

        final featureFlags = TestFeatureFlags(isToolExtensionsEnabled: true);
        final manager = ExtensionManager(
          hostPlatform: HostPlatform.linux_x64,
          logger: testLogger,
          entryPoints: <ExtensionEntryPoint>[linuxExtensionEntryPoint],
          featureFlags: featureFlags,
        );
        final discovery = ExtensionDevices(
          artifacts: Artifacts.test(),
          extensionManager: manager,
          fileSystem: localFs,
          logger: testLogger,
        );

        final List<Device> devices = await discovery.devices();
        expect(devices, hasLength(1));
        expect(devices.first.id, equals('custom_linux_device'));
        expect(devices.first.name, equals('Linux Custom Extension Prototype Device'));
        expect(devices.first.category, equals(Category.desktop));
        expect(devices.first.platformType, equals(PlatformType.custom));
        expect(await devices.first.targetPlatform, equals(TargetPlatform.linux_x64));
        expect(await devices.first.targetPlatformDisplayName, equals('linux-x64'));
        expect(await devices.first.sdkNameAndVersion, equals('Custom Linux 1.0.0'));
        expect(await devices.first.isSupported(), isTrue);
        expect(await devices.first.isSupportedForProject(project), isFalse);

        tempDir.childDirectory('linux').createSync();
        expect(await devices.first.isSupportedForProject(project), isTrue);

        await manager.dispose();
      },
      overrides: <Type, Generator>{
        FeatureFlags: () => TestFeatureFlags(isToolExtensionsEnabled: true),
      },
    );

    testUsingContext(
      'DevicesCommand output includes custom extension device when feature flag enabled',
      () async {
        final featureFlags = TestFeatureFlags(isToolExtensionsEnabled: true);
        final manager = ExtensionManager(
          hostPlatform: HostPlatform.linux_x64,
          logger: testLogger,
          entryPoints: <ExtensionEntryPoint>[linuxExtensionEntryPoint],
          featureFlags: featureFlags,
        );
        final testDeviceManager = TestDeviceManager(
          discoverers: <DeviceDiscovery>[
            ExtensionDevices(
              artifacts: Artifacts.test(),
              extensionManager: manager,
              fileSystem: MemoryFileSystem.test(),
              logger: testLogger,
            ),
          ],
        );
        final devicesCommand = DevicesCommand(
          deviceManager: testDeviceManager,
          doctor: FakeDoctor(),
          toolContext: FakeToolContext(logger: testLogger),
        );
        final CommandRunner<void> commandRunner = createTestCommandRunner(devicesCommand);

        await commandRunner.run(<String>['devices']);
        expect(testLogger.statusText, contains('Linux Custom Extension Prototype Device'));

        await manager.dispose();
      },
      overrides: <Type, Generator>{
        FeatureFlags: () => TestFeatureFlags(isToolExtensionsEnabled: true),
        DeviceManager: () => TestDeviceManager(),
      },
    );

    testWithoutContext(
      'ExtensionBackedDevice startApp and stopApp delegate build and launch via RPC',
      () async {
        final logger = BufferLogger.test();
        final fileSystem = MemoryFileSystem.test();
        fileSystem.currentDirectory.childFile('pubspec.yaml').writeAsStringSync('name: test_app\n');
        final featureFlags = TestFeatureFlags(isToolExtensionsEnabled: true);
        final manager = ExtensionManager(
          hostPlatform: HostPlatform.linux_x64,
          logger: logger,
          entryPoints: <ExtensionEntryPoint>[_fakeLaunchExtensionEntryPoint],
          featureFlags: featureFlags,
        );
        final discovery = ExtensionDevices(
          artifacts: Artifacts.test(fileSystem: fileSystem),
          extensionManager: manager,
          fileSystem: fileSystem,
          logger: logger,
        );

        final List<Device> devices = await discovery.devices();
        expect(devices, hasLength(1));
        final Device device = devices.first;

        final LaunchResult launchResult = await device.startApp(
          null,
          mainPath: 'lib/main.dart',
          debuggingOptions: DebuggingOptions.enabled(BuildInfo.debug),
        );
        expect(launchResult.started, isTrue);
        expect(launchResult.vmServiceUri, Uri.parse('http://127.0.0.1:8181/abcd/'));

        expect(await device.stopApp(null), isTrue);

        await manager.dispose();
      },
    );
  });
}

class TestDeviceManager extends DeviceManager {
  TestDeviceManager({List<DeviceDiscovery>? discoverers})
    : deviceDiscoverers = discoverers ?? <DeviceDiscovery>[],
      super(logger: testLogger);

  @override
  final List<DeviceDiscovery> deviceDiscoverers;
}

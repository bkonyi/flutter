// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';
import 'package:flutter_tools_extension_linux_prototype/src/build.dart';
import 'package:test/test.dart';

void main() {
  group('LinuxBuildService', () {
    test('targets returns prototype Linux targets', () {
      final service = LinuxBuildService();
      final List<ExtensionTarget> targets = service.targets;

      expect(
        targets.map((ExtensionTarget t) => (t.name, t.isTopLevel, t.pluginPlatformKey)),
        equals(<(String, bool, String?)>[
          (LinuxBuildService.customLinuxBuildTargetName, true, 'linux'),
          ('custom-linux-assemble-only-debug', false, 'linux'),
        ]),
      );
      expect(targets.last.dependencies, contains(BuiltInTargets.installCodeAssets));
    });

    test('initialize registers getBuildTargets and build RPC handlers', () async {
      final service = LinuxBuildService();
      expect(service.namespace, BuildService.serviceNamespace);

      final Map<String, ExtensionRpcHandler> handlers = await service.initialize();
      expect(handlers.keys, containsAll(<String>['getBuildTargets', 'build']));

      final Object? targetsResult = await handlers['getBuildTargets']!(const <String, Object?>{});
      final List<ExtensionBuildTarget> targets = ExtensionBuildTarget.listFromJson(targetsResult);
      expect(targets, hasLength(2));
      expect(targets.first.name, LinuxBuildService.customLinuxBuildTargetName);

      final Object? missingCmakeResultObj = await handlers['build']!(<String, Object?>{
        BuildService.buildDirParam: '/project/.dart_tool/flutter_build',
        BuildService.buildModeParam: 'debug',
        BuildService.mainPathParam: 'lib/main.dart',
        BuildService.outputDirParam: '/project/build/linux_extension/x64/debug',
        BuildService.projectRootParam: '/project',
        BuildService.resolvedArtifactsParam: const <String, String>{},
        BuildService.targetNameParam: LinuxBuildService.customLinuxBuildTargetName,
      });
      final missingCmakeResult = ExtensionBuildResult.fromJson(
        missingCmakeResultObj! as Map<String, Object?>,
      );
      expect(missingCmakeResult.success, isFalse);
      expect(missingCmakeResult.errorMessage, contains('Missing linux/CMakeLists.txt'));

      final Object? unknownTargetResultObj = await handlers['build']!(<String, Object?>{
        BuildService.buildDirParam: '/project/.dart_tool/flutter_build',
        BuildService.buildModeParam: 'debug',
        BuildService.mainPathParam: 'lib/main.dart',
        BuildService.outputDirParam: '/project/build/linux_extension/x64/debug',
        BuildService.projectRootParam: '/project',
        BuildService.resolvedArtifactsParam: const <String, String>{},
        BuildService.targetNameParam: 'unknown-target',
      });
      final unknownResult = ExtensionBuildResult.fromJson(
        unknownTargetResultObj! as Map<String, Object?>,
      );
      expect(unknownResult.success, isFalse);
      expect(unknownResult.errorMessage, contains('Unknown build target: unknown-target'));

      await service.shutdown();
    });

    test('CustomLinuxAssembleOnlyDebug copies artifacts and application binary', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('linux_build_test.');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final buildDir = Directory('${tempDir.path}/build_dir')..createSync(recursive: true);
      final outputDir = Directory('${tempDir.path}/output_dir')..createSync(recursive: true);
      final desktopDir = Directory('${tempDir.path}/desktop')..createSync(recursive: true);
      File('${desktopDir.path}/libflutter_linux_gtk.so').writeAsStringSync('gtk');
      final icuFile = File('${tempDir.path}/icudtl.dat')..writeAsStringSync('icu');
      File('${buildDir.path}/app.dill').writeAsStringSync('dill');
      final assetsDir = Directory('${buildDir.path}/flutter_assets')..createSync(recursive: true);
      File('${assetsDir.path}/AssetManifest.bin').writeAsStringSync('manifest');

      const target = CustomLinuxAssembleOnlyDebug();
      final ExtensionBuildResult result = await target.build(
        ExtensionBuildContext(
          buildDir: buildDir.uri,
          buildMode: .debug,
          mainPath: 'lib/main.dart',
          outputDir: outputDir.uri,
          projectRoot: tempDir.uri,
          resolvedArtifacts: <String, String>{
            LinuxArtifacts.linuxDesktopPath.name: desktopDir.path,
            BuiltInArtifacts.icuData.name: icuFile.path,
          },
        ),
      );

      expect(result.success, isTrue);
      expect(File('${outputDir.path}/bundle/lib/libflutter_linux_gtk.so').existsSync(), isTrue);
      expect(File('${outputDir.path}/bundle/data/icudtl.dat').existsSync(), isTrue);
      expect(
        File('${outputDir.path}/bundle/data/flutter_assets/kernel_blob.bin').existsSync(),
        isTrue,
      );
      expect(
        File('${outputDir.path}/bundle/data/flutter_assets/AssetManifest.bin').existsSync(),
        isTrue,
      );
    });

    test('CustomLinuxAssembleOnlyDebug fails when required artifacts are missing', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('linux_build_test_missing.');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      const target = CustomLinuxAssembleOnlyDebug();
      final ExtensionBuildResult result = await target.build(
        ExtensionBuildContext(
          buildDir: tempDir.uri,
          buildMode: .debug,
          mainPath: 'lib/main.dart',
          outputDir: tempDir.uri,
          projectRoot: tempDir.uri,
          resolvedArtifacts: const <String, String>{},
        ),
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('Missing linuxDesktopPath artifact.'));
    });

    test('writeLinuxPluginFiles writes Linux plugin CMake, registrant, and symlinks', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('linux_plugin_files_test.');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final ephemeralDir = Directory('${tempDir.path}/linux/flutter/ephemeral')
        ..createSync(recursive: true);
      final pluginDir = Directory('${tempDir.path}/my_linux_plugin')..createSync(recursive: true);
      final ffiPluginDir = Directory('${tempDir.path}/my_ffi_plugin')..createSync(recursive: true);

      await writeLinuxPluginFiles(tempDir, ephemeralDir, <ExtensionPlugin>[
        ExtensionPlugin(
          name: 'my_linux_plugin',
          path: pluginDir.path,
          configuration: const <String, Object?>{'pluginClass': 'MyLinuxPlugin'},
        ),
        ExtensionPlugin(
          name: 'my_ffi_plugin',
          path: ffiPluginDir.path,
          configuration: const <String, Object?>{'ffiPlugin': true},
        ),
      ]);

      final cmakeFile = File('${tempDir.path}/linux/flutter/generated_plugins.cmake');
      expect(cmakeFile.existsSync(), isTrue);
      final String cmakeContent = cmakeFile.readAsStringSync();
      expect(cmakeContent, contains('my_linux_plugin'));
      expect(cmakeContent, contains('my_ffi_plugin'));

      final registrantCc = File('${tempDir.path}/linux/flutter/generated_plugin_registrant.cc');
      expect(registrantCc.existsSync(), isTrue);
      final String registrantContent = registrantCc.readAsStringSync();
      expect(registrantContent, contains('#include <my_linux_plugin/my_linux_plugin_plugin.h>'));
      expect(registrantContent, contains('"MyLinuxPlugin"'));

      expect(
        Link('${tempDir.path}/linux/flutter/ephemeral/.plugin_symlinks/my_linux_plugin')
            .existsSync(),
        isTrue,
      );
    });

    group('build RPC parameter validation', () {
      const validParams = <String, Object?>{
        BuildService.targetNameParam: 'custom-linux-build',
        BuildService.projectRootParam: '/project',
        BuildService.mainPathParam: 'lib/main.dart',
        BuildService.buildModeParam: 'debug',
        BuildService.outputDirParam: '/out',
        BuildService.buildDirParam: '/build',
        BuildService.resolvedArtifactsParam: <String, String>{},
      };

      final invalidCases =
          <(String description, Map<String, Object?> overrides, String expectedParam)>[
            (
              'missing targetName',
              <String, Object?>{BuildService.targetNameParam: null},
              BuildService.targetNameParam,
            ),
            (
              'missing projectRoot',
              <String, Object?>{BuildService.projectRootParam: null},
              BuildService.projectRootParam,
            ),
            (
              'relative projectRoot',
              <String, Object?>{BuildService.projectRootParam: 'relative/path'},
              BuildService.projectRootParam,
            ),
            (
              'missing mainPath',
              <String, Object?>{BuildService.mainPathParam: null},
              BuildService.mainPathParam,
            ),
            (
              'missing buildMode',
              <String, Object?>{BuildService.buildModeParam: null},
              BuildService.buildModeParam,
            ),
            (
              'invalid buildMode',
              <String, Object?>{BuildService.buildModeParam: 'invalid_mode'},
              BuildService.buildModeParam,
            ),
            (
              'missing outputDir',
              <String, Object?>{BuildService.outputDirParam: null},
              BuildService.outputDirParam,
            ),
            (
              'relative outputDir',
              <String, Object?>{BuildService.outputDirParam: 'relative/output'},
              BuildService.outputDirParam,
            ),
            (
              'missing buildDir',
              <String, Object?>{BuildService.buildDirParam: null},
              BuildService.buildDirParam,
            ),
            (
              'relative buildDir',
              <String, Object?>{BuildService.buildDirParam: 'relative/build'},
              BuildService.buildDirParam,
            ),
            (
              'missing resolvedArtifacts',
              <String, Object?>{BuildService.resolvedArtifactsParam: null},
              BuildService.resolvedArtifactsParam,
            ),
            (
              'non-string resolvedArtifacts value',
              <String, Object?>{
                BuildService.resolvedArtifactsParam: <String, Object?>{'genSnapshot': 123},
              },
              BuildService.resolvedArtifactsParam,
            ),
          ];

      for (final (String description, Map<String, Object?> overrides, String expectedParam)
          in invalidCases) {
        test('throws RpcException on $description', () async {
          final service = LinuxBuildService();
          final Map<String, ExtensionRpcHandler> handlers = await service.initialize();
          final ExtensionRpcHandler buildHandler = handlers['build']!;

          await expectLater(
            () => buildHandler(<String, Object?>{...validParams, ...overrides}),
            throwsA(
              isA<RpcException>().having(
                (RpcException e) => e.message,
                'message',
                contains('Missing or invalid "$expectedParam" parameter.'),
              ),
            ),
          );
        });
      }
    });
  });
}

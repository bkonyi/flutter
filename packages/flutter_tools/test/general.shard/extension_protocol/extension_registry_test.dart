// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/experimental/extension_discovery.dart';
import 'package:flutter_tools/src/experimental/extension_manager.dart';
import 'package:flutter_tools/src/experimental/extension_registry.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';
import 'package:json_rpc_2/json_rpc_2.dart' as json_rpc;
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

import '../../src/fake_process_manager.dart';
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

void main() {
  group('GlobalExtensionRegistry Directory Resolution', () {
    test('uses customRegistryDir when provided', () {
      final fs = MemoryFileSystem.test();
      final Directory customDir = fs.directory('/custom/registry/dir');
      final registry = GlobalExtensionRegistry(
        fileSystem: fs,
        logger: BufferLogger.test(),
        platform: FakePlatform(),
        processManager: FakeProcessManager.any(),
        customRegistryDir: customDir,
      );

      expect(registry.registryDir.path, equals('/custom/registry/dir'));
      expect(registry.registryFile.path, equals('/custom/registry/dir/extension_registry.json'));
    });

    test('uses DART_DATA_HOME when set', () {
      final fs = MemoryFileSystem.test();
      final platform = FakePlatform(
        environment: <String, String>{'DART_DATA_HOME': '/data/dart_home'},
      );
      final registry = GlobalExtensionRegistry(
        fileSystem: fs,
        logger: BufferLogger.test(),
        platform: platform,
        processManager: FakeProcessManager.any(),
      );

      expect(registry.registryDir.path, equals('/data/dart_home/flutter_tool_extensions'));
      expect(
        registry.registryFile.path,
        equals('/data/dart_home/flutter_tool_extensions/extension_registry.json'),
      );
    });

    test('falls back to HOME/.flutter_tool_extensions on Unix', () {
      final fs = MemoryFileSystem.test();
      final platform = FakePlatform(environment: <String, String>{'HOME': '/users/alice'});
      final registry = GlobalExtensionRegistry(
        fileSystem: fs,
        logger: BufferLogger.test(),
        platform: platform,
        processManager: FakeProcessManager.any(),
      );

      expect(registry.registryDir.path, equals('/users/alice/.flutter_tool_extensions'));
      expect(
        registry.registryFile.path,
        equals('/users/alice/.flutter_tool_extensions/extension_registry.json'),
      );
    });

    test('falls back to USERPROFILE/.flutter_tool_extensions on Windows', () {
      final fs = MemoryFileSystem.test(style: FileSystemStyle.windows);
      final platform = FakePlatform(
        operatingSystem: 'windows',
        environment: <String, String>{r'USERPROFILE': r'C:\Users\Alice'},
      );
      final registry = GlobalExtensionRegistry(
        fileSystem: fs,
        logger: BufferLogger.test(),
        platform: platform,
        processManager: FakeProcessManager.any(),
      );

      expect(registry.registryDir.path, equals(r'C:\Users\Alice\.flutter_tool_extensions'));
      expect(
        registry.registryFile.path,
        equals(r'C:\Users\Alice\.flutter_tool_extensions\extension_registry.json'),
      );
    });
  });

  group('GlobalExtensionEntry serialization', () {
    test('round-trips toJson and fromJson', () {
      const entry = GlobalExtensionEntry(
        capabilities: ToolExtensionCapabilities(
          services: <String>['diagnostics', 'configuration'],
          extensionName: 'my_ext',
          supportedPlatforms: <String>{'linux', 'macos'},
        ),
        dartSdkVersion: '3.5.0',
        enabled: true,
        entrypointPath: '/path/to/entry.dart',
        installDir: '/path/to/install',
        name: 'my_ext',
        snapshotPath: '/path/to/snapshot.jit',
        source: 'path',
        version: '1.2.3',
      );

      final Map<String, Object?> jsonMap = entry.toJson();
      final GlobalExtensionEntry? parsed = GlobalExtensionEntry.fromJson(jsonMap);

      expect(parsed, isNotNull);
      expect(parsed!.name, equals('my_ext'));
      expect(parsed.version, equals('1.2.3'));
      expect(parsed.source, equals('path'));
      expect(parsed.installDir, equals('/path/to/install'));
      expect(parsed.entrypointPath, equals('/path/to/entry.dart'));
      expect(parsed.snapshotPath, equals('/path/to/snapshot.jit'));
      expect(parsed.enabled, isTrue);
      expect(parsed.dartSdkVersion, equals('3.5.0'));
      expect(parsed.capabilities.services, equals(<String>['diagnostics', 'configuration']));
      expect(parsed.capabilities.supportedPlatforms, equals(<String>{'linux', 'macos'}));
    });

    test('copyWith updates specified fields', () {
      const entry = GlobalExtensionEntry(
        capabilities: ToolExtensionCapabilities(services: <String>[]),
        dartSdkVersion: '3.5.0',
        enabled: true,
        entrypointPath: '/entry.dart',
        installDir: '/install',
        name: 'test_ext',
        source: 'pub',
        version: '1.0.0',
      );

      final GlobalExtensionEntry updated = entry.copyWith(
        enabled: false,
        version: '2.0.0',
        snapshotPath: '/new_snapshot.jit',
      );

      expect(updated.name, equals('test_ext'));
      expect(updated.enabled, isFalse);
      expect(updated.version, equals('2.0.0'));
      expect(updated.snapshotPath, equals('/new_snapshot.jit'));
      expect(updated.source, equals('pub'));
    });

    test('fromJson returns null on malformed JSON', () {
      expect(GlobalExtensionEntry.fromJson(<String, Object?>{'name': 'incomplete'}), isNull);
    });
  });

  group('GlobalExtensionRegistry CRUD', () {
    test('loadEntries returns empty map when file does not exist', () {
      final fs = MemoryFileSystem.test();
      final registry = GlobalExtensionRegistry(
        fileSystem: fs,
        logger: BufferLogger.test(),
        platform: FakePlatform(),
        processManager: FakeProcessManager.any(),
        customRegistryDir: fs.directory('/registry'),
      );

      expect(registry.loadEntries(), isEmpty);
    });

    test('register writes entries to disk and loadEntries retrieves them', () {
      final fs = MemoryFileSystem.test();
      final registry = GlobalExtensionRegistry(
        fileSystem: fs,
        logger: BufferLogger.test(),
        platform: FakePlatform(),
        processManager: FakeProcessManager.any(),
        customRegistryDir: fs.directory('/registry'),
      );

      const entry = GlobalExtensionEntry(
        capabilities: ToolExtensionCapabilities(services: <String>['diagnostics']),
        dartSdkVersion: '3.5.0',
        enabled: true,
        entrypointPath: '/entry.dart',
        installDir: '/install',
        name: 'demo_ext',
        source: 'path',
        version: '1.0.0',
      );

      registry.register(entry);

      expect(registry.registryFile.existsSync(), isTrue);
      final Map<String, GlobalExtensionEntry> entries = registry.loadEntries();
      expect(entries.length, equals(1));
      expect(entries['demo_ext']?.name, equals('demo_ext'));
      expect(entries['demo_ext']?.version, equals('1.0.0'));
      expect(registry.getEntry('demo_ext'), isNotNull);
    });

    test('setEnabled, enable, and disable update state', () {
      final fs = MemoryFileSystem.test();
      final registry = GlobalExtensionRegistry(
        fileSystem: fs,
        logger: BufferLogger.test(),
        platform: FakePlatform(),
        processManager: FakeProcessManager.any(),
        customRegistryDir: fs.directory('/registry'),
      );

      const entry = GlobalExtensionEntry(
        capabilities: ToolExtensionCapabilities(services: <String>[]),
        dartSdkVersion: '3.5.0',
        enabled: true,
        entrypointPath: '/entry.dart',
        installDir: '/install',
        name: 'demo_ext',
        source: 'path',
        version: '1.0.0',
      );

      registry.register(entry);
      expect(registry.getEntry('demo_ext')?.enabled, isTrue);

      expect(registry.disable('demo_ext'), isTrue);
      expect(registry.getEntry('demo_ext')?.enabled, isFalse);

      expect(registry.enable('demo_ext'), isTrue);
      expect(registry.getEntry('demo_ext')?.enabled, isTrue);

      expect(registry.enable('non_existent'), isFalse);
    });

    test('unregister removes entry and returns true, or false if not found', () {
      final fs = MemoryFileSystem.test();
      final registry = GlobalExtensionRegistry(
        fileSystem: fs,
        logger: BufferLogger.test(),
        platform: FakePlatform(),
        processManager: FakeProcessManager.any(),
        customRegistryDir: fs.directory('/registry'),
      );

      const entry = GlobalExtensionEntry(
        capabilities: ToolExtensionCapabilities(services: <String>[]),
        dartSdkVersion: '3.5.0',
        enabled: true,
        entrypointPath: '/entry.dart',
        installDir: '/install',
        name: 'demo_ext',
        source: 'path',
        version: '1.0.0',
      );

      registry.register(entry);
      expect(registry.unregister('demo_ext'), isTrue);
      expect(registry.loadEntries(), isEmpty);
      expect(registry.unregister('demo_ext'), isFalse);
    });
  });

  group('GlobalExtensionRegistry install, uninstall, and upgrade', () {
    test('install from local path scaffolds, compiles snapshot, and writes registry', () async {
      final fs = MemoryFileSystem.test();
      final logger = BufferLogger.test();
      final Directory localExtDir = fs.directory('/ext_source')..createSync(recursive: true);
      localExtDir.childFile('pubspec.yaml').writeAsStringSync('''
name: custom_ext
version: 2.1.0
''');
      localExtDir.childDirectory('bin').childFile('custom_ext.dart').createSync(recursive: true);

      final Directory registryDir = fs.directory('/registry');

      final processManager = FakeProcessManager.list(<FakeCommand>[
        const FakeCommand(
          command: <String>['dart', 'pub', 'get'],
          workingDirectory: '/registry/custom_ext',
        ),
        FakeCommand(
          command: const <String>[
            'dart',
            'compile',
            'jit-snapshot',
            '-o',
            '/registry/custom_ext/bin/generated_entrypoint.jit',
            '/registry/custom_ext/bin/generated_entrypoint.dart',
            '--train',
          ],
          workingDirectory: '/registry/custom_ext',
          onRun: (_) {
            fs
                .file('/registry/custom_ext/bin/generated_entrypoint.jit')
                .createSync(recursive: true);
          },
        ),
      ]);

      final registry = GlobalExtensionRegistry(
        fileSystem: fs,
        logger: logger,
        platform: FakePlatform(version: '3.5.0'),
        processManager: processManager,
        customRegistryDir: registryDir,
        spawner:
            (
              Uri uri, {
              required Logger logger,
              List<String> args = const <String>[],
              Uri? packageConfigUri,
              Duration timeout = const Duration(seconds: 2),
            }) async {
              return _createFakeConnection(
                capabilities: const ToolExtensionCapabilities(
                  services: <String>['diagnostics'],
                  extensionName: 'custom_ext',
                ),
                logger: logger,
              );
            },
      );

      final GlobalExtensionEntry entry = await registry.install(source: localExtDir.path);

      expect(entry.name, equals('custom_ext'));
      expect(entry.version, equals('2.1.0'));
      expect(entry.source, equals('path'));
      expect(entry.enabled, isTrue);
      expect(entry.capabilities.services, equals(<String>['diagnostics']));
      expect(fs.file('/registry/custom_ext/pubspec.yaml').existsSync(), isTrue);
      expect(fs.file('/registry/custom_ext/bin/generated_entrypoint.dart').existsSync(), isTrue);
      expect(
        fs.file('/registry/custom_ext/bin/generated_entrypoint.dart').readAsStringSync(),
        contains('--train'),
      );
      expect(registry.getEntry('custom_ext'), isNotNull);
    });

    test('uninstall removes directory and unregisters entry', () async {
      final fs = MemoryFileSystem.test();
      final Directory registryDir = fs.directory('/registry');
      final Directory installDir = registryDir.childDirectory('custom_ext')
        ..createSync(recursive: true);

      final registry = GlobalExtensionRegistry(
        fileSystem: fs,
        logger: BufferLogger.test(),
        platform: FakePlatform(),
        processManager: FakeProcessManager.any(),
        customRegistryDir: registryDir,
      );

      registry.register(
        GlobalExtensionEntry(
          capabilities: const ToolExtensionCapabilities(services: <String>[]),
          dartSdkVersion: '3.5.0',
          enabled: true,
          entrypointPath: installDir.childFile('entry.dart').path,
          installDir: installDir.path,
          name: 'custom_ext',
          source: 'path',
          version: '1.0.0',
        ),
      );

      expect(installDir.existsSync(), isTrue);
      final bool result = await registry.uninstall('custom_ext');
      expect(result, isTrue);
      expect(installDir.existsSync(), isFalse);
      expect(registry.getEntry('custom_ext'), isNull);

      expect(await registry.uninstall('custom_ext'), isFalse);
    });

    test('upgrade runs pub upgrade, recompiles snapshot, and updates registry', () async {
      final fs = MemoryFileSystem.test();
      final logger = BufferLogger.test();
      final Directory registryDir = fs.directory('/registry');
      final Directory installDir = registryDir.childDirectory('custom_ext')
        ..createSync(recursive: true);
      final Directory binDir = installDir.childDirectory('bin')..createSync(recursive: true);
      final File entrypoint = binDir.childFile('generated_entrypoint.dart')..createSync();
      final File snapshot = binDir.childFile('generated_entrypoint.jit')..createSync();

      final processManager = FakeProcessManager.list(<FakeCommand>[
        const FakeCommand(
          command: <String>['dart', 'pub', 'upgrade'],
          workingDirectory: '/registry/custom_ext',
        ),
        FakeCommand(
          command: <String>[
            'dart',
            'compile',
            'jit-snapshot',
            '-o',
            snapshot.path,
            entrypoint.path,
            '--train',
          ],
          workingDirectory: '/registry/custom_ext',
        ),
      ]);

      final registry = GlobalExtensionRegistry(
        fileSystem: fs,
        logger: logger,
        platform: FakePlatform(version: '3.6.0'),
        processManager: processManager,
        customRegistryDir: registryDir,
        spawner:
            (
              Uri uri, {
              required Logger logger,
              List<String> args = const <String>[],
              Uri? packageConfigUri,
              Duration timeout = const Duration(seconds: 2),
            }) async {
              return _createFakeConnection(
                capabilities: const ToolExtensionCapabilities(
                  services: <String>['configuration'],
                  extensionName: 'custom_ext',
                ),
                logger: logger,
              );
            },
      );

      registry.register(
        GlobalExtensionEntry(
          capabilities: const ToolExtensionCapabilities(services: <String>['diagnostics']),
          dartSdkVersion: '3.5.0',
          enabled: true,
          entrypointPath: entrypoint.path,
          installDir: installDir.path,
          name: 'custom_ext',
          snapshotPath: snapshot.path,
          source: 'pub',
          version: '1.0.0',
        ),
      );

      final List<GlobalExtensionEntry> upgraded = await registry.upgrade(name: 'custom_ext');
      expect(upgraded.length, equals(1));
      expect(upgraded.first.capabilities.services, equals(<String>['configuration']));
      expect(upgraded.first.dartSdkVersion, equals('3.6.0'));
      expect(registry.getEntry('custom_ext')?.dartSdkVersion, equals('3.6.0'));
    });
  });

  group('ExtensionManager Integration with GlobalExtensionRegistry', () {
    test('ExtensionManager spawns global extension from valid AppJIT snapshot', () async {
      final fs = MemoryFileSystem.test();
      final logger = BufferLogger.test();
      final os = FakeOperatingSystemUtils();
      final platform = FakePlatform(version: '3.5.0');
      final Directory registryDir = fs.directory('/registry');

      final Directory installDir = registryDir.childDirectory('global_ext')
        ..createSync(recursive: true);
      final Directory binDir = installDir.childDirectory('bin')..createSync(recursive: true);
      final File entrypoint = binDir.childFile('generated_entrypoint.dart')
        ..writeAsStringSync('void main() {}');
      final File snapshot = binDir.childFile('generated_entrypoint.jit')
        ..writeAsStringSync('binary_snapshot_data');

      var spawnedUriString = '';
      final registry = GlobalExtensionRegistry(
        fileSystem: fs,
        logger: logger,
        platform: platform,
        processManager: FakeProcessManager.any(),
        customRegistryDir: registryDir,
      );

      registry.register(
        GlobalExtensionEntry(
          capabilities: const ToolExtensionCapabilities(
            services: <String>['diagnostics'],
            extensionName: 'global_ext',
            supportedPlatforms: <String>{'linux'},
          ),
          dartSdkVersion: '3.5.0',
          enabled: true,
          entrypointPath: entrypoint.path,
          installDir: installDir.path,
          name: 'global_ext',
          snapshotPath: snapshot.path,
          source: 'path',
          version: '1.0.0',
        ),
      );

      final manager = ExtensionManager(
        hostPlatform: os.hostPlatform,
        logger: logger,
        fileSystem: fs,
        platform: platform,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
        globalRegistry: registry,
        spawner:
            (
              Uri uri, {
              required Logger logger,
              List<String> args = const <String>[],
              Uri? packageConfigUri,
              Duration timeout = const Duration(seconds: 2),
            }) async {
              spawnedUriString = uri.toString();
              return _createFakeConnection(
                capabilities: const ToolExtensionCapabilities(
                  services: <String>['diagnostics'],
                  extensionName: 'global_ext',
                  supportedPlatforms: <String>{'linux'},
                ),
                logger: logger,
              );
            },
      );

      await manager.ensureInitialized();
      expect(manager.connections, hasLength(1));
      expect(spawnedUriString, equals(snapshot.uri.toString()));
      await manager.dispose();
    });

    test(
      'ExtensionManager falls back to source entrypoint when snapshot is invalid or SDK mismatch',
      () async {
        final fs = MemoryFileSystem.test();
        final logger = BufferLogger.test();
        final os = FakeOperatingSystemUtils();
        final platform = FakePlatform(version: '3.6.0'); // SDK changed from 3.5.0
        final Directory registryDir = fs.directory('/registry');

        final Directory installDir = registryDir.childDirectory('global_ext')
          ..createSync(recursive: true);
        final Directory binDir = installDir.childDirectory('bin')..createSync(recursive: true);
        final File entrypoint = binDir.childFile('generated_entrypoint.dart')
          ..writeAsStringSync('void main() {}');
        final File snapshot = binDir.childFile('generated_entrypoint.jit')
          ..writeAsStringSync('binary_snapshot_data');

        var spawnedUriString = '';
        final registry = GlobalExtensionRegistry(
          fileSystem: fs,
          logger: logger,
          platform: platform,
          processManager: FakeProcessManager.any(),
          customRegistryDir: registryDir,
        );

        registry.register(
          GlobalExtensionEntry(
            capabilities: const ToolExtensionCapabilities(
              services: <String>['diagnostics'],
              extensionName: 'global_ext',
              supportedPlatforms: <String>{'linux'},
            ),
            dartSdkVersion: '3.5.0', // Mismatch with 3.6.0
            enabled: true,
            entrypointPath: entrypoint.path,
            installDir: installDir.path,
            name: 'global_ext',
            snapshotPath: snapshot.path,
            source: 'path',
            version: '1.0.0',
          ),
        );

        final manager = ExtensionManager(
          hostPlatform: os.hostPlatform,
          logger: logger,
          fileSystem: fs,
          platform: platform,
          featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
          globalRegistry: registry,
          spawner:
              (
                Uri uri, {
                required Logger logger,
                List<String> args = const <String>[],
                Uri? packageConfigUri,
                Duration timeout = const Duration(seconds: 2),
              }) async {
                spawnedUriString = uri.toString();
                return _createFakeConnection(
                  capabilities: const ToolExtensionCapabilities(
                    services: <String>['diagnostics'],
                    extensionName: 'global_ext',
                    supportedPlatforms: <String>{'linux'},
                  ),
                  logger: logger,
                );
              },
        );

        await manager.ensureInitialized();
        expect(manager.connections, hasLength(1));
        expect(spawnedUriString, equals(entrypoint.uri.toString()));
        await manager.dispose();
      },
    );

    test('ExtensionManager skips disabled global extensions', () async {
      final fs = MemoryFileSystem.test();
      final logger = BufferLogger.test();
      final os = FakeOperatingSystemUtils();
      final registry = GlobalExtensionRegistry(
        fileSystem: fs,
        logger: logger,
        platform: FakePlatform(),
        processManager: FakeProcessManager.any(),
        customRegistryDir: fs.directory('/registry'),
      );

      registry.register(
        const GlobalExtensionEntry(
          capabilities: ToolExtensionCapabilities(services: <String>['diagnostics']),
          dartSdkVersion: '3.5.0',
          enabled: false, // Disabled
          entrypointPath: '/entry.dart',
          installDir: '/install',
          name: 'disabled_ext',
          source: 'path',
          version: '1.0.0',
        ),
      );

      var spawnerCalled = false;
      final manager = ExtensionManager(
        hostPlatform: os.hostPlatform,
        logger: logger,
        fileSystem: fs,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
        globalRegistry: registry,
        spawner:
            (
              Uri uri, {
              required Logger logger,
              List<String> args = const <String>[],
              Uri? packageConfigUri,
              Duration timeout = const Duration(seconds: 2),
            }) async {
              spawnerCalled = true;
              return _createFakeConnection(
                capabilities: const ToolExtensionCapabilities(services: <String>[]),
                logger: logger,
              );
            },
      );

      await manager.ensureInitialized();
      expect(spawnerCalled, isFalse);
      expect(manager.connections, isEmpty);
      await manager.dispose();
    });

    test('Workspace manifest overrides global extension with the same name', () async {
      final fs = MemoryFileSystem.test();
      final logger = BufferLogger.test();
      final os = FakeOperatingSystemUtils();
      final Directory projectDir = fs.directory('/project')..createSync();
      fs.currentDirectory = projectDir;

      projectDir.childFile('flutter_extensions.yaml').writeAsStringSync('''
extensions:
  my_ext:
    path: workspace_ext
''');
      final Directory workspaceExtDir = projectDir.childDirectory('workspace_ext')..createSync();
      final File workspaceEntry = workspaceExtDir.childDirectory('bin').childFile('my_ext.dart')
        ..createSync(recursive: true);

      final Directory registryDir = fs.directory('/registry');
      final registry = GlobalExtensionRegistry(
        fileSystem: fs,
        logger: logger,
        platform: FakePlatform(),
        processManager: FakeProcessManager.any(),
        customRegistryDir: registryDir,
      );

      registry.register(
        const GlobalExtensionEntry(
          capabilities: ToolExtensionCapabilities(services: <String>['diagnostics']),
          dartSdkVersion: '3.5.0',
          enabled: true,
          entrypointPath: '/global/entry.dart',
          installDir: '/global/install',
          name: 'my_ext',
          source: 'path',
          version: '1.0.0',
        ),
      );

      final spawnedUris = <Uri>[];
      final manager = ExtensionManager(
        hostPlatform: os.hostPlatform,
        logger: logger,
        fileSystem: fs,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
        globalRegistry: registry,
        spawner:
            (
              Uri uri, {
              required Logger logger,
              List<String> args = const <String>[],
              Uri? packageConfigUri,
              Duration timeout = const Duration(seconds: 2),
            }) async {
              spawnedUris.add(uri);
              return _createFakeConnection(
                capabilities: const ToolExtensionCapabilities(
                  services: <String>['diagnostics'],
                  extensionName: 'my_ext',
                  supportedPlatforms: <String>{'linux'},
                ),
                logger: logger,
              );
            },
      );

      await manager.ensureInitialized();
      expect(spawnedUris, hasLength(1));
      expect(spawnedUris.first, equals(workspaceEntry.uri));
      await manager.dispose();
    });
  });
}

// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/os.dart';
import 'package:flutter_tools/src/experimental/extension_cache.dart';
import 'package:flutter_tools/src/experimental/extension_discovery.dart';
import 'package:flutter_tools/src/experimental/extension_manager.dart';
import 'package:flutter_tools/src/experimental/extension_manifest.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';
import 'package:json_rpc_2/json_rpc_2.dart' as json_rpc;
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

import '../../src/fakes.dart';

ExtensionConnection createFakeConnection({
  required ToolExtensionCapabilities capabilities,
  required Logger logger,
  Map<String, Function>? rpcHandlers,
}) {
  final serverController = StreamController<Object?>();
  final clientController = StreamController<Object?>();
  final serverChannel = StreamChannel<Object?>(clientController.stream, serverController.sink);
  final clientChannel = StreamChannel<Object?>(serverController.stream, clientController.sink);

  final serverPeer = json_rpc.Peer.withoutJson(serverChannel);
  if (rpcHandlers != null) {
    for (final MapEntry(:key, :value) in rpcHandlers.entries) {
      serverPeer.registerMethod(key, value);
    }
  }
  unawaited(serverPeer.listen());

  final clientPeer = json_rpc.Peer.withoutJson(clientChannel);
  unawaited(clientPeer.listen());

  return ExtensionConnection.custom(capabilities: capabilities, peer: clientPeer, logger: logger);
}

void main() {
  group('ExtensionManager Demand-Driven Spawning & Caching (Hermetic)', () {
    late FileSystem fs;
    late BufferLogger logger;
    late ExtensionCapabilityCacheManager cacheManager;
    late Directory projectDir;

    setUp(() {
      fs = MemoryFileSystem.test();
      logger = BufferLogger.test();
      cacheManager = ExtensionCapabilityCacheManager(fileSystem: fs, logger: logger);
      projectDir = fs.directory('/project')..createSync();
    });

    test('cold start: spawns isolate via spawner and saves entry to capabilities cache', () async {
      projectDir.childFile(ExtensionManifestFinder.kManifestFileName).writeAsStringSync('''
extensions:
  diag_ext:
    path: packages/diag_ext
''');
      final Directory extDir = projectDir.childDirectory('packages').childDirectory('diag_ext')
        ..createSync(recursive: true);
      final File entrypoint = extDir.childDirectory('bin').childFile('diag_ext.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('void main() {}');

      var spawnerCalls = 0;
      Future<ExtensionConnection> fakeSpawner(
        Uri entrypointUri, {
        required Logger logger,
        List<String>? args,
        Uri? packageConfigUri,
        Duration? timeout,
      }) async {
        spawnerCalls++;
        return createFakeConnection(
          capabilities: const ToolExtensionCapabilities(
            services: <String>['diagnostics'],
            supportedPlatforms: <String>{'linux', 'macos'},
          ),
          logger: logger,
          rpcHandlers: <String, Function>{'diagnostics.getTitle': () async => 'Diag Extension'},
        );
      }

      final manager = ExtensionManager(
        cacheManager: cacheManager,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
        spawner: fakeSpawner,
        hostPlatform: HostPlatform.linux_x64,
        logger: logger,
        fileSystem: fs,
      );
      addTearDown(manager.dispose);

      await manager.ensureInitialized(startDir: projectDir);

      expect(spawnerCalls, 1);
      expect(manager.connections, hasLength(1));
      expect(manager.diagnosticsExtensions, hasLength(1));
      expect(manager.diagnosticsExtensions.single.title, 'Diag Extension');

      // Cache file must be written to disk with capability entry
      final Map<String, ExtensionCapabilityCacheEntry> cache = cacheManager.loadCache(projectDir);
      expect(cache, contains('diag_ext'));
      expect(cache['diag_ext']!.capabilities.services, <String>['diagnostics']);
      expect(cache['diag_ext']!.entrypointUri, entrypoint.uri);
    });

    test('warm start: matching required services spawns isolate', () async {
      projectDir.childFile(ExtensionManifestFinder.kManifestFileName).writeAsStringSync('''
extensions:
  diag_ext:
    path: packages/diag_ext
''');
      final Directory extDir = projectDir.childDirectory('packages').childDirectory('diag_ext')
        ..createSync(recursive: true);
      final File entrypoint = extDir.childDirectory('bin').childFile('diag_ext.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('void main() {}');

      cacheManager.saveCache(<String, ExtensionCapabilityCacheEntry>{
        'diag_ext': ExtensionCapabilityCacheEntry(
          capabilities: const ToolExtensionCapabilities(
            services: <String>['diagnostics'],
            supportedPlatforms: <String>{'linux'},
          ),
          entrypointUri: entrypoint.uri,
          extensionName: 'diag_ext',
          modifiedTimeMs: entrypoint.statSync().modified.millisecondsSinceEpoch,
        ),
      }, projectDir);

      var spawnerCalls = 0;
      Future<ExtensionConnection> fakeSpawner(
        Uri entrypointUri, {
        required Logger logger,
        List<String>? args,
        Uri? packageConfigUri,
        Duration? timeout,
      }) async {
        spawnerCalls++;
        return createFakeConnection(
          capabilities: const ToolExtensionCapabilities(
            services: <String>['diagnostics'],
            supportedPlatforms: <String>{'linux'},
          ),
          logger: logger,
          rpcHandlers: <String, Function>{'diagnostics.getTitle': () async => 'Diag Extension'},
        );
      }

      final manager = ExtensionManager(
        cacheManager: cacheManager,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
        spawner: fakeSpawner,
        hostPlatform: HostPlatform.linux_x64,
        logger: logger,
        fileSystem: fs,
      );
      addTearDown(manager.dispose);

      await manager.ensureInitialized(
        requiredServices: const <String>{'diagnostics'},
        startDir: projectDir,
      );

      expect(spawnerCalls, 1);
      expect(manager.connections, hasLength(1));
    });

    test(
      'warm start: skipping isolate spawn when cached capability lacks required services',
      () async {
        projectDir.childFile(ExtensionManifestFinder.kManifestFileName).writeAsStringSync('''
extensions:
  diag_ext:
    path: packages/diag_ext
''');
        final Directory extDir = projectDir.childDirectory('packages').childDirectory('diag_ext')
          ..createSync(recursive: true);
        final File entrypoint = extDir.childDirectory('bin').childFile('diag_ext.dart')
          ..createSync(recursive: true)
          ..writeAsStringSync('void main() {}');

        cacheManager.saveCache(<String, ExtensionCapabilityCacheEntry>{
          'diag_ext': ExtensionCapabilityCacheEntry(
            capabilities: const ToolExtensionCapabilities(
              services: <String>['diagnostics'],
              supportedPlatforms: <String>{'linux'},
            ),
            entrypointUri: entrypoint.uri,
            extensionName: 'diag_ext',
            modifiedTimeMs: entrypoint.statSync().modified.millisecondsSinceEpoch,
          ),
        }, projectDir);

        var spawnerCalls = 0;
        Future<ExtensionConnection> fakeSpawner(
          Uri entrypointUri, {
          required Logger logger,
          List<String>? args,
          Uri? packageConfigUri,
          Duration? timeout,
        }) async {
          spawnerCalls++;
          return createFakeConnection(
            capabilities: const ToolExtensionCapabilities(services: <String>['diagnostics']),
            logger: logger,
          );
        }

        final manager = ExtensionManager(
          cacheManager: cacheManager,
          featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
          spawner: fakeSpawner,
          hostPlatform: HostPlatform.linux_x64,
          logger: logger,
          fileSystem: fs,
        );
        addTearDown(manager.dispose);

        await manager.ensureInitialized(
          requiredServices: const <String>{'device'},
          startDir: projectDir,
        );

        expect(spawnerCalls, 0);
        expect(manager.connections, isEmpty);
        expect(logger.traceText, contains('skipping isolate spawn'));
      },
    );

    test('skips extensions that do not support active host platform', () async {
      projectDir.childFile(ExtensionManifestFinder.kManifestFileName).writeAsStringSync('''
extensions:
  macos_only:
    path: packages/macos_only
    supportedPlatforms:
      - macos
''');
      final Directory extDir = projectDir.childDirectory('packages').childDirectory('macos_only')
        ..createSync(recursive: true);
      extDir.childDirectory('bin').childFile('macos_only.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('void main() {}');

      var spawnerCalls = 0;
      final manager = ExtensionManager(
        cacheManager: cacheManager,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
        spawner:
            (
              Uri uri, {
              required Logger logger,
              List<String>? args,
              Uri? packageConfigUri,
              Duration? timeout,
            }) async {
              spawnerCalls++;
              return createFakeConnection(
                capabilities: const ToolExtensionCapabilities(services: <String>[]),
                logger: logger,
              );
            },
        hostPlatform: HostPlatform.linux_x64,
        logger: logger,
        fileSystem: fs,
      );
      addTearDown(manager.dispose);

      await manager.ensureInitialized(startDir: projectDir);

      expect(spawnerCalls, 0);
      expect(manager.connections, isEmpty);
      expect(logger.traceText, contains('does not support host platform "linux"; skipping'));
    });

    test('skips extensions marked disabled in manifest', () async {
      projectDir.childFile(ExtensionManifestFinder.kManifestFileName).writeAsStringSync('''
extensions:
  disabled_ext:
    enabled: false
    path: packages/disabled_ext
''');
      final Directory extDir = projectDir.childDirectory('packages').childDirectory('disabled_ext')
        ..createSync(recursive: true);
      extDir.childDirectory('bin').childFile('disabled_ext.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('void main() {}');

      var spawnerCalls = 0;
      final manager = ExtensionManager(
        cacheManager: cacheManager,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
        spawner:
            (
              Uri uri, {
              required Logger logger,
              List<String>? args,
              Uri? packageConfigUri,
              Duration? timeout,
            }) async {
              spawnerCalls++;
              return createFakeConnection(
                capabilities: const ToolExtensionCapabilities(services: <String>[]),
                logger: logger,
              );
            },
        hostPlatform: HostPlatform.linux_x64,
        logger: logger,
        fileSystem: fs,
      );
      addTearDown(manager.dispose);

      await manager.ensureInitialized(startDir: projectDir);

      expect(spawnerCalls, 0);
      expect(manager.connections, isEmpty);
      expect(logger.traceText, contains('disabled in manifest; skipping'));
    });

    test(
      'timeout marks extension as failed and subsequent initialize does not re-attempt',
      () async {
        projectDir.childFile(ExtensionManifestFinder.kManifestFileName).writeAsStringSync('''
extensions:
  timeout_ext:
    path: packages/timeout_ext
''');
        final Directory extDir = projectDir.childDirectory('packages').childDirectory('timeout_ext')
          ..createSync(recursive: true);
        extDir.childDirectory('bin').childFile('timeout_ext.dart')
          ..createSync(recursive: true)
          ..writeAsStringSync('void main() {}');

        var spawnerCalls = 0;
        final manager = ExtensionManager(
          cacheManager: cacheManager,
          featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
          spawner:
              (
                Uri uri, {
                required Logger logger,
                List<String>? args,
                Uri? packageConfigUri,
                Duration? timeout,
              }) async {
                spawnerCalls++;
                throw TimeoutException('Simulated handshake timeout');
              },
          hostPlatform: HostPlatform.linux_x64,
          logger: logger,
          fileSystem: fs,
        );
        addTearDown(manager.dispose);

        await manager.ensureInitialized(startDir: projectDir);

        expect(spawnerCalls, 1);
        expect(manager.connections, isEmpty);
        expect(
          logger.warningText,
          contains('Handshake with tool extension "timeout_ext" timed out'),
        );

        // Second initialization call: must NOT re-attempt spawner for failed extension
        await manager.ensureInitialized(startDir: projectDir);
        expect(spawnerCalls, 1);
        expect(logger.traceText, contains('Extension "timeout_ext" previously failed; skipping'));
      },
    );

    test('spawn error logs warning and does not crash tool', () async {
      projectDir.childFile(ExtensionManifestFinder.kManifestFileName).writeAsStringSync('''
extensions:
  crash_ext:
    path: packages/crash_ext
''');
      final Directory extDir = projectDir.childDirectory('packages').childDirectory('crash_ext')
        ..createSync(recursive: true);
      extDir.childDirectory('bin').childFile('crash_ext.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('void main() {}');

      var spawnerCalls = 0;
      final manager = ExtensionManager(
        cacheManager: cacheManager,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
        spawner:
            (
              Uri uri, {
              required Logger logger,
              List<String>? args,
              Uri? packageConfigUri,
              Duration? timeout,
            }) async {
              spawnerCalls++;
              throw StateError('Simulated isolate spawn crash');
            },
        hostPlatform: HostPlatform.linux_x64,
        logger: logger,
        fileSystem: fs,
      );
      addTearDown(manager.dispose);

      await manager.ensureInitialized(startDir: projectDir);

      expect(spawnerCalls, 1);
      expect(manager.connections, isEmpty);
      expect(
        logger.warningText,
        contains(
          'Failed to spawn tool extension "crash_ext": Bad state: Simulated isolate spawn crash',
        ),
      );

      // Second call skips
      await manager.ensureInitialized(startDir: projectDir);
      expect(spawnerCalls, 1);
    });

    test('disposes active connections and resets initialization state on dispose', () async {
      final manager = ExtensionManager(
        cacheManager: cacheManager,
        featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
        hostPlatform: HostPlatform.linux_x64,
        logger: logger,
        fileSystem: fs,
      );

      await manager.ensureInitialized();
      expect(manager.isInitialized, isTrue);

      await manager.dispose();
      expect(manager.isInitialized, isFalse);
      expect(manager.connections, isEmpty);
    });
  });
}

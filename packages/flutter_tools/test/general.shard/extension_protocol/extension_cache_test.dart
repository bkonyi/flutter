// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/experimental/extension_cache.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';
import 'package:test/test.dart';

void main() {
  group('ExtensionCapabilityCacheEntry', () {
    test('serializes and deserializes correctly', () {
      final entry = ExtensionCapabilityCacheEntry(
        capabilities: const ToolExtensionCapabilities(
          services: <String>['diagnostics', 'config', 'artifact', 'clean'],
          supportedPlatforms: <String>{'linux', 'macos'},
        ),
        entrypointUri: Uri.parse('file:///path/to/ext.dart'),
        extensionName: 'test_ext',
        modifiedTimeMs: 1234567890,
      );

      final Map<String, Object?> json = entry.toJson();
      final ExtensionCapabilityCacheEntry? parsed = ExtensionCapabilityCacheEntry.fromJson(json);

      expect(parsed, isNotNull);
      expect(parsed!.extensionName, 'test_ext');
      expect(parsed.entrypointUri, Uri.parse('file:///path/to/ext.dart'));
      expect(parsed.modifiedTimeMs, 1234567890);
      expect(parsed.capabilities.services, <String>['diagnostics', 'config', 'artifact', 'clean']);
      expect(parsed.capabilities.supportedPlatforms, <String>{'linux', 'macos'});
      expect(parsed.capabilities.artifactServiceProvided, isTrue);
      expect(parsed.capabilities.cleanServiceProvided, isTrue);
    });

    test('returns null when fromJson receives malformed JSON', () {
      expect(ExtensionCapabilityCacheEntry.fromJson(<String, Object?>{}), isNull);
      expect(
        ExtensionCapabilityCacheEntry.fromJson(<String, Object?>{
          'extensionName': 'ext',
          'entrypointUri': 'not a valid uri ::: %%%',
        }),
        isNull,
      );
    });
  });

  group('ExtensionCapabilityCacheManager', () {
    late FileSystem fs;
    late BufferLogger logger;
    late ExtensionCapabilityCacheManager cacheManager;

    setUp(() {
      fs = MemoryFileSystem.test();
      logger = BufferLogger.test();
      cacheManager = ExtensionCapabilityCacheManager(fileSystem: fs, logger: logger);
    });

    test('getCacheFile resolves to .dart_tool/flutter_tools/extension_capabilities_cache.json', () {
      final Directory projectDir = fs.directory('/project');
      final File cacheFile = cacheManager.getCacheFile(projectDir);

      expect(
        cacheFile.path,
        fs.path.join(
          '/project',
          '.dart_tool',
          'flutter_tools',
          'extension_capabilities_cache.json',
        ),
      );
    });

    test('loadCache returns empty map when file does not exist', () {
      final Directory projectDir = fs.directory('/project');
      final Map<String, ExtensionCapabilityCacheEntry> cache = cacheManager.loadCache(projectDir);

      expect(cache, isEmpty);
    });

    test('saveCache and loadCache round-trip entries correctly', () {
      final Directory projectDir = fs.directory('/project')..createSync();
      final entry1 = ExtensionCapabilityCacheEntry(
        capabilities: const ToolExtensionCapabilities(
          services: <String>['diagnostics'],
          supportedPlatforms: <String>{'linux'},
        ),
        entrypointUri: Uri.parse('file:///project/packages/ext1/bin/ext1.dart'),
        extensionName: 'ext1',
        modifiedTimeMs: 1000,
      );
      final entry2 = ExtensionCapabilityCacheEntry(
        capabilities: const ToolExtensionCapabilities(
          services: <String>['config'],
          supportedPlatforms: <String>{'macos', 'windows'},
        ),
        entrypointUri: Uri.parse('file:///project/packages/ext2/bin/ext2.dart'),
        extensionName: 'ext2',
        modifiedTimeMs: 2000,
      );

      cacheManager.saveCache(<String, ExtensionCapabilityCacheEntry>{
        'ext1': entry1,
        'ext2': entry2,
      }, projectDir);

      final Map<String, ExtensionCapabilityCacheEntry> loaded = cacheManager.loadCache(projectDir);
      expect(loaded, hasLength(2));
      expect(loaded['ext1']?.extensionName, 'ext1');
      expect(loaded['ext1']?.modifiedTimeMs, 1000);
      expect(loaded['ext1']?.capabilities.services, <String>['diagnostics']);
      expect(loaded['ext2']?.extensionName, 'ext2');
      expect(loaded['ext2']?.capabilities.services, <String>['config']);
    });

    test('updateEntry inserts or updates an existing entry', () {
      final Directory projectDir = fs.directory('/project')..createSync();
      final entry = ExtensionCapabilityCacheEntry(
        capabilities: const ToolExtensionCapabilities(services: <String>['diagnostics']),
        entrypointUri: Uri.parse('file:///project/packages/ext1/bin/ext1.dart'),
        extensionName: 'ext1',
        modifiedTimeMs: 1000,
      );

      cacheManager.updateEntry(entry, projectDir);

      Map<String, ExtensionCapabilityCacheEntry> loaded = cacheManager.loadCache(projectDir);
      expect(loaded, hasLength(1));
      expect(loaded['ext1']?.modifiedTimeMs, 1000);

      final updatedEntry = ExtensionCapabilityCacheEntry(
        capabilities: const ToolExtensionCapabilities(services: <String>['diagnostics', 'config']),
        entrypointUri: Uri.parse('file:///project/packages/ext1/bin/ext1.dart'),
        extensionName: 'ext1',
        modifiedTimeMs: 5000,
      );
      cacheManager.updateEntry(updatedEntry, projectDir);

      loaded = cacheManager.loadCache(projectDir);
      expect(loaded, hasLength(1));
      expect(loaded['ext1']?.modifiedTimeMs, 5000);
      expect(loaded['ext1']?.capabilities.services, <String>['diagnostics', 'config']);
    });

    test('isCacheValid validates entrypoint modification time and existence', () {
      final Directory projectDir = fs.directory('/project')..createSync();
      final File entrypoint = projectDir.childFile('ext.dart')..writeAsStringSync('void main() {}');
      final int modifiedMs = entrypoint.statSync().modified.millisecondsSinceEpoch;

      final validEntry = ExtensionCapabilityCacheEntry(
        capabilities: const ToolExtensionCapabilities(services: <String>['diagnostics']),
        entrypointUri: entrypoint.uri,
        extensionName: 'ext',
        modifiedTimeMs: modifiedMs,
      );
      expect(cacheManager.isCacheValid(validEntry, entrypoint), isTrue);

      final staleEntry = ExtensionCapabilityCacheEntry(
        capabilities: const ToolExtensionCapabilities(services: <String>['diagnostics']),
        entrypointUri: entrypoint.uri,
        extensionName: 'ext',
        modifiedTimeMs: modifiedMs - 5000,
      );
      expect(cacheManager.isCacheValid(staleEntry, entrypoint), isFalse);

      final File missingFile = projectDir.childFile('missing.dart');
      expect(cacheManager.isCacheValid(validEntry, missingFile), isFalse);

      final File manifestFile = projectDir.childFile('flutter_extensions.yaml')
        ..writeAsStringSync('extensions: []');
      final int manifestMs = manifestFile.statSync().modified.millisecondsSinceEpoch;

      final validManifestEntry = ExtensionCapabilityCacheEntry(
        capabilities: const ToolExtensionCapabilities(services: <String>['diagnostics']),
        entrypointUri: entrypoint.uri,
        extensionName: 'ext',
        modifiedTimeMs: modifiedMs,
        manifestModifiedTimeMs: manifestMs,
      );
      expect(
        cacheManager.isCacheValid(validManifestEntry, entrypoint, manifestFile: manifestFile),
        isTrue,
      );

      final staleManifestEntry = ExtensionCapabilityCacheEntry(
        capabilities: const ToolExtensionCapabilities(services: <String>['diagnostics']),
        entrypointUri: entrypoint.uri,
        extensionName: 'ext',
        modifiedTimeMs: modifiedMs,
        manifestModifiedTimeMs: manifestMs - 5000,
      );
      expect(
        cacheManager.isCacheValid(staleManifestEntry, entrypoint, manifestFile: manifestFile),
        isFalse,
      );

      final File missingManifest = projectDir.childFile('missing_manifest.yaml');
      expect(
        cacheManager.isCacheValid(validManifestEntry, entrypoint, manifestFile: missingManifest),
        isFalse,
      );
    });

    test('loadCache handles corrupted JSON gracefully', () {
      final Directory projectDir = fs.directory('/project')..createSync();
      final File cacheFile = cacheManager.getCacheFile(projectDir)..createSync(recursive: true);
      cacheFile.writeAsStringSync('{ not valid json ...');

      final Map<String, ExtensionCapabilityCacheEntry> loaded = cacheManager.loadCache(projectDir);
      expect(loaded, isEmpty);
      expect(logger.traceText, contains('Failed to read extension capabilities cache'));
    });

    test('loadCache ignores cache file with incompatible version', () {
      final Directory projectDir = fs.directory('/project')..createSync();
      final File cacheFile = cacheManager.getCacheFile(projectDir)..createSync(recursive: true);
      cacheFile.writeAsStringSync('''
{
  "version": 999,
  "entries": {}
}
''');

      final Map<String, ExtensionCapabilityCacheEntry> loaded = cacheManager.loadCache(projectDir);
      expect(loaded, isEmpty);
    });

    test('invalidate deletes the cache file', () {
      final Directory projectDir = fs.directory('/project')..createSync();
      final entry = ExtensionCapabilityCacheEntry(
        capabilities: const ToolExtensionCapabilities(services: <String>['diagnostics']),
        entrypointUri: Uri.parse('file:///project/ext.dart'),
        extensionName: 'ext',
        modifiedTimeMs: 1000,
      );
      cacheManager.saveCache(<String, ExtensionCapabilityCacheEntry>{'ext': entry}, projectDir);
      final File cacheFile = cacheManager.getCacheFile(projectDir);
      expect(cacheFile.existsSync(), isTrue);

      cacheManager.invalidate(projectDir);
      expect(cacheFile.existsSync(), isFalse);
    });
  });
}

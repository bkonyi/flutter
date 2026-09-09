// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:flutter_tools_extension/flutter_tools_extension.dart';

import '../base/file_system.dart';
import '../base/logger.dart';

const String _kCacheDirName = '.dart_tool';
const String _kSubDirName = 'flutter_tools';
const String _kCacheFileName = 'extension_capabilities_cache.json';
const int _kCurrentCacheVersion = 1;
const String _kVersionKey = 'version';
const String _kEntriesKey = 'entries';
const String _kExtensionNameKey = 'extensionName';
const String _kEntrypointUriKey = 'entrypointUri';
const String _kModifiedTimeMsKey = 'modifiedTimeMs';
const String _kManifestModifiedTimeMsKey = 'manifestModifiedTimeMs';
const String _kCapabilitiesKey = 'capabilities';

/// Represents a cached capability record for a discovered tool extension.
class ExtensionCapabilityCacheEntry {
  const ExtensionCapabilityCacheEntry({
    required this.capabilities,
    required this.entrypointUri,
    required this.extensionName,
    required this.modifiedTimeMs,
    this.manifestModifiedTimeMs,
  });

  /// The capabilities reported by the extension.
  final ToolExtensionCapabilities capabilities;

  /// The URI of the extension entrypoint file.
  final Uri entrypointUri;

  /// The unique name of the extension.
  final String extensionName;

  /// The modification timestamp in milliseconds since epoch of the entrypoint file.
  final int modifiedTimeMs;

  /// The modification timestamp in milliseconds since epoch of the manifest file, if known.
  final int? manifestModifiedTimeMs;

  /// Serializes this cache entry to a JSON map.
  Map<String, Object?> toJson() => <String, Object?>{
    _kExtensionNameKey: extensionName,
    _kEntrypointUriKey: entrypointUri.toString(),
    _kModifiedTimeMsKey: modifiedTimeMs,
    if (manifestModifiedTimeMs != null) _kManifestModifiedTimeMsKey: manifestModifiedTimeMs,
    _kCapabilitiesKey: capabilities.toMap(),
  };

  /// Deserializes an [ExtensionCapabilityCacheEntry] from a JSON map.
  ///
  /// Returns null if the JSON map contains missing or invalid fields.
  static ExtensionCapabilityCacheEntry? fromJson(Map<String, Object?> json) {
    if (json case {
      _kExtensionNameKey: final String extensionName,
      _kEntrypointUriKey: final String entrypointUriStr,
      _kModifiedTimeMsKey: final num modifiedTimeMs,
      _kCapabilitiesKey: final Map<String, Object?> capabilitiesMap,
    }) {
      final Uri? entrypointUri = Uri.tryParse(entrypointUriStr);
      if (entrypointUri == null) {
        return null;
      }
      final int? manifestModifiedTimeMs = switch (json[_kManifestModifiedTimeMsKey]) {
        final num val => val.toInt(),
        _ => null,
      };
      final capabilities = ToolExtensionCapabilities.fromJson(capabilitiesMap);
      return ExtensionCapabilityCacheEntry(
        capabilities: capabilities,
        entrypointUri: entrypointUri,
        extensionName: extensionName,
        modifiedTimeMs: modifiedTimeMs.toInt(),
        manifestModifiedTimeMs: manifestModifiedTimeMs,
      );
    }
    return null;
  }
}

/// Manages caching of tool extension capabilities on disk to enable demand-driven isolate startup.
class ExtensionCapabilityCacheManager {
  ExtensionCapabilityCacheManager({
    required FileSystem fileSystem,
    required Logger logger,
    File? customCacheFile,
  }) : _fs = fileSystem,
       _logger = logger,
       _customCacheFile = customCacheFile;

  final FileSystem _fs;
  final Logger _logger;
  final File? _customCacheFile;

  FileSystem get fileSystem => _fs;
  Logger get logger => _logger;

  /// Resolves the cache file path for the given [directory] (or the current directory if omitted).
  File getCacheFile([Directory? directory]) {
    if (_customCacheFile != null) {
      return _customCacheFile;
    }
    final Directory targetDir = directory ?? _fs.currentDirectory;
    return targetDir
        .childDirectory(_kCacheDirName)
        .childDirectory(_kSubDirName)
        .childFile(_kCacheFileName);
  }

  /// Loads cached capability entries from disk.
  Map<String, ExtensionCapabilityCacheEntry> loadCache([Directory? directory]) {
    final File file = getCacheFile(directory);
    if (!file.existsSync()) {
      return <String, ExtensionCapabilityCacheEntry>{};
    }
    try {
      final String content = file.readAsStringSync();
      final Object? decoded = json.decode(content);
      if (decoded case {
        _kVersionKey: final int version,
        _kEntriesKey: final Map<String, Object?> entriesJson,
      } when version == _kCurrentCacheVersion) {
        return <String, ExtensionCapabilityCacheEntry>{
          for (final MapEntry(:key, :value) in entriesJson.entries)
            if (value is Map<String, Object?>)
              if (ExtensionCapabilityCacheEntry.fromJson(value)
                  case final ExtensionCapabilityCacheEntry entry)
                key: entry,
        };
      }
    } on Object catch (error) {
      _logger.printTrace('Failed to read extension capabilities cache at "${file.path}": $error');
    }
    return <String, ExtensionCapabilityCacheEntry>{};
  }

  /// Saves [cache] entries to disk.
  void saveCache(Map<String, ExtensionCapabilityCacheEntry> cache, [Directory? directory]) {
    final File file = getCacheFile(directory);
    try {
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      final payload = <String, Object?>{
        _kVersionKey: _kCurrentCacheVersion,
        _kEntriesKey: <String, Object?>{
          for (final MapEntry(:key, :value) in cache.entries) key: value.toJson(),
        },
      };
      const encoder = JsonEncoder.withIndent('  ');
      file.writeAsStringSync(encoder.convert(payload), flush: true);
    } on Object catch (error) {
      _logger.printTrace('Failed to write extension capabilities cache to "${file.path}": $error');
    }
  }

  /// Updates or inserts a single capability [entry] in the cache.
  void updateEntry(ExtensionCapabilityCacheEntry entry, [Directory? directory]) {
    final Map<String, ExtensionCapabilityCacheEntry> currentCache = loadCache(directory);
    currentCache[entry.extensionName] = entry;
    saveCache(currentCache, directory);
  }

  /// Checks whether [entry] accurately reflects the modification state of [entrypointFile]
  /// and optional [manifestFile].
  bool isCacheValid(
    ExtensionCapabilityCacheEntry entry,
    File entrypointFile, {
    File? manifestFile,
  }) {
    if (!entrypointFile.existsSync()) {
      return false;
    }
    if (manifestFile != null && !manifestFile.existsSync()) {
      return false;
    }
    try {
      final int modifiedTimeMs = entrypointFile.statSync().modified.millisecondsSinceEpoch;
      if (modifiedTimeMs != entry.modifiedTimeMs || entrypointFile.uri != entry.entrypointUri) {
        return false;
      }
      if (manifestFile != null && entry.manifestModifiedTimeMs != null) {
        final int manifestModifiedMs = manifestFile.statSync().modified.millisecondsSinceEpoch;
        if (manifestModifiedMs != entry.manifestModifiedTimeMs) {
          return false;
        }
      }
      return true;
    } on Object catch (error) {
      _logger.printTrace(
        'Error checking entrypoint file stats for "${entrypointFile.path}": $error',
      );
      return false;
    }
  }

  /// Invalidates the capability cache by deleting the cache file on disk.
  void invalidate([Directory? directory]) {
    final File file = getCacheFile(directory);
    if (file.existsSync()) {
      try {
        file.deleteSync();
      } on Object catch (error) {
        _logger.printTrace(
          'Failed to delete extension capabilities cache at "${file.path}": $error',
        );
      }
    }
  }
}

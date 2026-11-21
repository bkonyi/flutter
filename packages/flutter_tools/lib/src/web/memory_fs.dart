// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';

import '../base/file_system.dart';
import '../base/utils.dart';
import '../convert.dart';

/// A pseudo-filesystem stored in memory.
///
/// To support output to arbitrary multi-root file schemes, the frontend server
/// will output web sources, sourcemaps, and metadata to concatenated single files
/// with an additional manifest file containing the correct offsets.
class WebMemoryFS {
  final metadataFiles = <String, Uint8List>{};
  final files = <String, Uint8List>{};
  final sourcemaps = <String, Uint8List>{};
  final moduleRevisions = <String, int>{};

  String? get mergedMetadata => _mergedMetadata;
  String? _mergedMetadata;

  int get revision => _revision;
  int _revision = 0;

  /// Increments [revision] when an individual file is written outside [write].
  void incrementRevision() {
    _revision++;
  }

  /// Writes [contents] to [filePath] in [files], incrementing [revision] (and
  /// recording [moduleRevisions] for `.js` files) only when [contents] differs
  /// byte-for-byte from any existing entry and [trackRevision] is `true`.
  void writeFileBytes(String filePath, Uint8List contents, {bool trackRevision = true}) {
    final String fileName = filePath.startsWith('/') ? filePath.substring(1) : filePath;
    final Uint8List? existing = files[fileName];
    if (existing != null && listEquals(existing, contents)) {
      return;
    }
    files[fileName] = contents;
    if (trackRevision) {
      _revision++;
      if (fileName.endsWith('.js')) {
        moduleRevisions[fileName] = _revision;
      }
    }
  }

  /// Update the filesystem with the provided source and manifest files.
  ///
  /// Returns the list of updated files.
  List<String> write(File codeFile, File manifestFile, File sourcemapFile, File metadataFile) {
    final modules = <String>[];
    final changedModules = <String>[];
    final Uint8List codeBytes = codeFile.readAsBytesSync();
    final Uint8List sourcemapBytes = sourcemapFile.readAsBytesSync();
    final Uint8List metadataBytes = metadataFile.readAsBytesSync();
    final Map<String, Object?> manifest = castStringKeyedMap(
      json.decode(manifestFile.readAsStringSync()),
    )!;
    var metadataChanged = false;
    for (final MapEntry(key: filePath, value: offsets) in manifest.entries) {
      if (offsets case {
        'code': [final int codeStart, final int codeEnd],
        'sourcemap': [final int sourcemapStart, final int sourcemapEnd],
        'metadata': [final int metadataStart, final int metadataEnd],
      }) {
        if (codeStart < 0 || codeEnd > codeBytes.lengthInBytes) {
          continue;
        }
        final byteView = Uint8List.view(codeBytes.buffer, codeStart, codeEnd - codeStart);
        final String fileName = filePath.startsWith('/') ? filePath.substring(1) : filePath;
        final Uint8List? existingCode = files[fileName];
        if (existingCode == null || !listEquals(existingCode, byteView)) {
          files[fileName] = byteView;
          changedModules.add(fileName);
        }

        if (sourcemapStart < 0 || sourcemapEnd > sourcemapBytes.lengthInBytes) {
          continue;
        }
        final sourcemapView = Uint8List.view(
          sourcemapBytes.buffer,
          sourcemapStart,
          sourcemapEnd - sourcemapStart,
        );
        final sourcemapName = '$fileName.map';
        sourcemaps[sourcemapName] = sourcemapView;

        if (metadataStart < 0 || metadataEnd > metadataBytes.lengthInBytes) {
          continue;
        }
        final metadataView = Uint8List.view(
          metadataBytes.buffer,
          metadataStart,
          metadataEnd - metadataStart,
        );
        final metadataName = '$fileName.metadata';
        final Uint8List? existingMetadata = metadataFiles[metadataName];
        if (existingMetadata == null || !listEquals(existingMetadata, metadataView)) {
          metadataFiles[metadataName] = metadataView;
          metadataChanged = true;
        }

        modules.add(fileName);
      }
    }

    if (metadataChanged || _mergedMetadata == null) {
      _mergedMetadata = metadataFiles.values
          .map((Uint8List encoded) => utf8.decode(encoded))
          .join('\n');
    }
    if (changedModules.isNotEmpty) {
      _revision++;
      for (final fileName in changedModules) {
        moduleRevisions[fileName] = _revision;
      }
    }

    return modules;
  }
}

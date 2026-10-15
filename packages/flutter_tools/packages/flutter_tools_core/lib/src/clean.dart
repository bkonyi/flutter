// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

/// Environment context provided to tool extensions during `flutter clean`.
@immutable
class CleanEnvironment {
  const CleanEnvironment({required this.buildDir, required this.projectRoot});

  /// Deserializes a [CleanEnvironment] from a JSON-serializable map.
  factory CleanEnvironment.fromJson(Map<String, Object?> json) {
    if (json case {
      projectRootKey: final String projectRootStr,
      buildDirKey: final String buildDirStr,
    }) {
      final Uri? projectRootUri = Uri.tryParse(projectRootStr);
      final Uri? buildDirUri = Uri.tryParse(buildDirStr);
      if (projectRootUri != null &&
          projectRootUri.hasAbsolutePath &&
          buildDirUri != null &&
          buildDirUri.hasAbsolutePath) {
        return CleanEnvironment(buildDir: buildDirUri, projectRoot: projectRootUri);
      }
    }
    throw ArgumentError('Invalid CleanEnvironment JSON: $json');
  }

  /// Map key for [buildDir].
  static const String buildDirKey = 'buildDir';

  /// Map key for [projectRoot].
  static const String projectRootKey = 'projectRoot';

  /// The build directory URI of the Flutter project being cleaned.
  final Uri buildDir;

  /// The root directory URI of the Flutter project being cleaned.
  final Uri projectRoot;

  /// Serializes the clean environment to a JSON-serializable map.
  Map<String, Object?> toJson() => <String, Object?>{
    projectRootKey: projectRoot.toString(),
    buildDirKey: buildDir.toString(),
  };

  /// Serializes the clean environment to a JSON-serializable map.
  Map<String, Object?> toMap() => toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is CleanEnvironment &&
            other.projectRoot == projectRoot &&
            other.buildDir == buildDir);
  }

  @override
  int get hashCode => Object.hash(projectRoot, buildDir);

  @override
  String toString() => 'CleanEnvironment(projectRoot: $projectRoot, buildDir: $buildDir)';
}

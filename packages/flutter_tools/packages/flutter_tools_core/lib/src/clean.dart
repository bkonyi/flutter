// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

/// Represents the build environment parameters passed to a clean service.
@immutable
class CleanEnvironment {
  const CleanEnvironment({required this.buildDir, required this.projectRoot});

  /// Deserializes a [CleanEnvironment] from a JSON map.
  factory CleanEnvironment.fromJson(Map<String, Object?> json) {
    return CleanEnvironment(
      buildDir: Uri.parse(json['buildDir']! as String),
      projectRoot: Uri.parse(json['projectRoot']! as String),
    );
  }

  /// The URI of the build output directory for the project.
  final Uri buildDir;

  /// The URI of the root directory of the Flutter project.
  final Uri projectRoot;

  /// Serializes this environment to a JSON map.
  Map<String, Object?> toJson() => <String, Object?>{
    'buildDir': buildDir.toString(),
    'projectRoot': projectRoot.toString(),
  };

  /// Alias for [toJson] to maintain consistency.
  Map<String, Object?> toMap() => toJson();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! CleanEnvironment) {
      return false;
    }
    return other.buildDir == buildDir && other.projectRoot == projectRoot;
  }

  @override
  int get hashCode => Object.hash(buildDir, projectRoot);
}

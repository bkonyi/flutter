// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

/// Representation of a custom build target provided by a tool extension.
@immutable
class ExtensionBuildTarget {
  /// Creates an [ExtensionBuildTarget] definition.
  const ExtensionBuildTarget({
    required this.name,
    required this.targetPlatform,
    required this.description,
  });

  /// Deserializes an [ExtensionBuildTarget] from a JSON-serializable map.
  factory ExtensionBuildTarget.fromJson(Map<String, Object?> json) {
    return ExtensionBuildTarget(
      name: json['name'] as String? ?? '',
      targetPlatform: json['targetPlatform'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }

  /// The name of this build target (e.g. `'custom-apk'`).
  final String name;

  /// The target platform string (e.g. `'android-arm64'`).
  final String targetPlatform;

  /// Description of what this target builds.
  final String description;

  /// Serializes the build target to a JSON-serializable map.
  Map<String, Object?> toMap() => <String, Object?>{
    'name': name,
    'targetPlatform': targetPlatform,
    'description': description,
  };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ExtensionBuildTarget &&
            other.name == name &&
            other.targetPlatform == targetPlatform &&
            other.description == description);
  }

  @override
  int get hashCode => Object.hash(name, targetPlatform, description);
}

/// Representation of a build result returned by a tool extension.
@immutable
class ExtensionBuildResult {
  /// Creates an [ExtensionBuildResult] definition.
  const ExtensionBuildResult({
    required this.success,
    this.errorMessage,
  });

  /// Deserializes an [ExtensionBuildResult] from a JSON-serializable map.
  factory ExtensionBuildResult.fromJson(Map<String, Object?> json) {
    return ExtensionBuildResult(
      success: json['success'] as bool? ?? false,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  /// Whether the build succeeded.
  final bool success;

  /// Optional error message if the build failed.
  final String? errorMessage;

  /// Serializes the build result to a JSON-serializable map.
  Map<String, Object?> toMap() => <String, Object?>{
    'success': success,
    'errorMessage': ?errorMessage,
  };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ExtensionBuildResult &&
            other.success == success &&
            other.errorMessage == errorMessage);
  }

  @override
  int get hashCode => Object.hash(success, errorMessage);
}

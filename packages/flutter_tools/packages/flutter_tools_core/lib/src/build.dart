// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';
import 'build/source.dart';

export 'build/constants.dart';
export 'build/enums.dart';
export 'build/source.dart';
export 'build/target.dart';

/// Representation of a custom build target provided by a tool extension.
@immutable
class ExtensionBuildTarget {
  /// Creates an [ExtensionBuildTarget] definition.
  const ExtensionBuildTarget({
    required this.description,
    required this.name,
    required this.targetPlatform,
    this.dependencies = const <String>[],
    this.inputs = const <Source>[],
    this.isTopLevel = true,
    this.outputs = const <Source>[],
    this.outputDir = '{BUILD_DIR}',
  });

  /// Deserializes an [ExtensionBuildTarget] from a JSON-serializable map.
  factory ExtensionBuildTarget.fromJson(Map<String, Object?> json) {
    return ExtensionBuildTarget(
      description: json['description'] as String? ?? '',
      name: json['name'] as String? ?? '',
      targetPlatform: json['targetPlatform'] as String? ?? '',
      dependencies: (json['dependencies'] as List<Object?>?)?.cast<String>() ?? const <String>[],
      inputs:
          (json['inputs'] as List<Object?>?)
              ?.cast<Map<String, Object?>>()
              .map(Source.fromJson)
              .toList() ??
          const <Source>[],
      isTopLevel: json['isTopLevel'] as bool? ?? true,
      outputs:
          (json['outputs'] as List<Object?>?)
              ?.cast<Map<String, Object?>>()
              .map(Source.fromJson)
              .toList() ??
          const <Source>[],
      outputDir: json['outputDir'] as String? ?? '{BUILD_DIR}',
    );
  }

  /// The name of this build target (e.g. `'custom-apk'`).
  final String name;

  /// The target platform string (e.g. `'android-arm64'`).
  final String targetPlatform;

  /// Description of what this target builds.
  final String description;

  /// Whether this target is a top-level target invokable through `flutter build`.
  final bool isTopLevel;

  /// The names of other targets that this target depends on.
  final List<String> dependencies;

  /// Input file patterns.
  final List<Source> inputs;

  /// Output file patterns.
  final List<Source> outputs;

  /// The output directory pattern.
  final String outputDir;

  /// Serializes the build target to a JSON-serializable map.
  Map<String, Object?> toMap() => <String, Object?>{
    'name': name,
    'targetPlatform': targetPlatform,
    'description': description,
    'isTopLevel': isTopLevel,
    'dependencies': dependencies,
    'inputs': inputs.map((s) => s.toJson()).toList(),
    'outputs': outputs.map((s) => s.toJson()).toList(),
    'outputDir': outputDir,
  };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ExtensionBuildTarget &&
            other.name == name &&
            other.targetPlatform == targetPlatform &&
            other.description == description &&
            other.isTopLevel == isTopLevel &&
            other.outputDir == outputDir &&
            _listEquals(other.dependencies, dependencies) &&
            _listEquals(other.inputs, inputs) &&
            _listEquals(other.outputs, outputs));
  }

  @override
  int get hashCode => Object.hash(
    name,
    targetPlatform,
    description,
    isTopLevel,
    outputDir,
    Object.hashAll(dependencies),
    Object.hashAll(inputs),
    Object.hashAll(outputs),
  );
}

/// Representation of a build result returned by a tool extension.
@immutable
class ExtensionBuildResult {
  const ExtensionBuildResult._({required this.success, this.errorMessage});

  /// Creates a successful build result.
  const ExtensionBuildResult.success() : this._(success: true);

  /// Creates a failed build result with the given [message].
  const ExtensionBuildResult.failure({required String message})
    : this._(success: false, errorMessage: message);

  /// Deserializes an [ExtensionBuildResult] from a JSON-serializable map.
  factory ExtensionBuildResult.fromJson(Map<String, Object?> json) {
    final bool success = json['success'] as bool? ?? false;
    if (success) {
      return const ExtensionBuildResult.success();
    }
    return ExtensionBuildResult.failure(
      message: json['errorMessage'] as String? ?? 'Unknown build error',
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

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

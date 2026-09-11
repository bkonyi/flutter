// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

/// Declares an artifact dependency required by a tool extension.
@immutable
class ArtifactDependency {
  const ArtifactDependency({
    required this.hostPlatform,
    required this.name,
    required this.sha256Checksums,
    required this.targetArchitecture,
    required this.targetPlatform,
  });

  /// Deserializes an [ArtifactDependency] from a JSON map.
  factory ArtifactDependency.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> rawChecksums =
        (json['sha256Checksums'] as Map<Object?, Object?>?)?.cast<String, Object?>() ??
        <String, Object?>{};
    final sha256Checksums = <String, String>{
      for (final MapEntry(:key, :value) in rawChecksums.entries)
        if (value is String) key: value,
    };
    return ArtifactDependency(
      hostPlatform: json['hostPlatform']! as String,
      name: json['name']! as String,
      sha256Checksums: sha256Checksums,
      targetArchitecture: json['targetArchitecture']! as String,
      targetPlatform: json['targetPlatform']! as String,
    );
  }

  /// The target host platform architecture for the compiler (e.g., 'darwin-x64').
  final String hostPlatform;

  /// The name of the required artifact (e.g., 'gen_snapshot').
  final String name;

  /// A mapping of host/target keys to SHA-256 hashes for binary validation.
  final Map<String, String> sha256Checksums;

  /// The target architecture for the device (e.g., 'arm64', 'arm').
  final String targetArchitecture;

  /// The target platform running the embedding (e.g., 'webos', 'tizen', 'linux').
  final String targetPlatform;

  /// Serializes this dependency to a JSON map.
  Map<String, Object?> toJson() => <String, Object?>{
    'hostPlatform': hostPlatform,
    'name': name,
    'sha256Checksums': sha256Checksums,
    'targetArchitecture': targetArchitecture,
    'targetPlatform': targetPlatform,
  };

  /// Alias for [toJson] to maintain consistency across core DTOs.
  Map<String, Object?> toMap() => toJson();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! ArtifactDependency) {
      return false;
    }
    if (other.name != name ||
        other.hostPlatform != hostPlatform ||
        other.targetPlatform != targetPlatform ||
        other.targetArchitecture != targetArchitecture ||
        other.sha256Checksums.length != sha256Checksums.length) {
      return false;
    }
    for (final MapEntry(:key, :value) in sha256Checksums.entries) {
      if (other.sha256Checksums[key] != value) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    hostPlatform,
    name,
    targetArchitecture,
    targetPlatform,
    Object.hashAll(
      sha256Checksums.entries.map((MapEntry<String, String> e) => Object.hash(e.key, e.value)),
    ),
  );
}

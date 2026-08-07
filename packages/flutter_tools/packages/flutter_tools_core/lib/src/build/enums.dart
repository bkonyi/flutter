// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
import 'package:meta/meta.dart';

// Simple string utilities to avoid dependencies.
String _snakeCase(String name) {
  return name
      .replaceAllMapped(RegExp(r'(?<=[a-z0-9])[A-Z]'), (Match m) => '_${m.group(0)}')
      .toLowerCase();
}

String _sentenceCase(String name) {
  if (name.isEmpty) {
    return name;
  }
  return '${name[0].toUpperCase()}${name.substring(1)}';
}

/// The mode in which the application is built.
enum BuildMode {
  /// Built in JIT mode with no optimizations, enabled asserts, and a VM service.
  debug,

  /// Built in AOT mode with some optimizations and a VM service.
  profile,

  /// Built in AOT mode with all optimizations and no VM service.
  release,

  /// Built in JIT mode with all optimizations and no VM service.
  jitRelease;

  factory BuildMode.fromCliName(String value) => values.singleWhere(
    (BuildMode element) => element.cliName == value,
    orElse: () => throw ArgumentError('$value is not a supported build mode'),
  );

  static const releaseModes = <BuildMode>{release, jitRelease};
  static const jitModes = <BuildMode>{debug, jitRelease};

  /// Whether this mode is considered release.
  bool get isRelease => releaseModes.contains(this);

  /// Whether this mode is using the JIT runtime.
  bool get isJit => jitModes.contains(this);

  /// Whether this mode is using the precompiled runtime.
  bool get isPrecompiled => !isJit;

  /// [name] formatted in snake case.
  String get cliName => _snakeCase(name);

  /// [cliName] formatted in sentence case.
  String get uppercaseName => _sentenceCase(cliName);

  /// [cliName] with `_` replaced with a space.
  String get friendlyName => cliName.replaceAll('_', ' ');

  /// [friendlyName] formatted in sentence case.
  String get uppercaseFriendlyName => _sentenceCase(friendlyName);

  @override
  String toString() => cliName;
}

/// Represents an artifact downloaded from the Flutter cache (e.g. engine binaries, frameworks).
///
/// Extensions can reference these artifacts in their target inputs/outputs,
/// and the host will resolve them to physical paths on the host before build execution.
@immutable
class Artifact {
  const Artifact(this.name);

  /// The unique identifying name of this artifact.
  final String name;

  @override
  bool operator ==(Object other) => other is Artifact && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}

/// Represents an artifact used by the host build system (e.g. compilers, tools).
///
/// Extensions can reference these host-side artifacts in their target inputs/outputs,
/// and the host will resolve them to physical paths on the host before build execution.
@immutable
class HostArtifact {
  const HostArtifact(this.name);

  /// The unique identifying name of this host artifact.
  final String name;

  @override
  bool operator ==(Object other) => other is HostArtifact && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}

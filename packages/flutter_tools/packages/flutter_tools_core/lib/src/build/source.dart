// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';
import 'enums.dart';

/// Visitor interface to resolve [Source] objects into files in the host.
abstract class SourceVisitor {
  void visitPattern(String pattern, bool optional);
  void visitArtifact(Artifact artifact, String? platform, BuildMode? mode);
  void visitHostArtifact(HostArtifact artifact);
}

/// A description of an input or output of a Target.
@immutable
abstract class Source {
  const Source();

  /// This source is a file URL which contains some references to magic
  /// environment variables defined in Environment.
  const factory Source.pattern(String pattern, {bool optional}) = _PatternSource;

  /// The source is provided by an [Artifact].
  const factory Source.artifact(Artifact artifact, {String? platform, BuildMode? mode}) =
      _ArtifactSource;

  /// The source is provided by an [HostArtifact].
  const factory Source.hostArtifact(HostArtifact artifact) = _HostArtifactSource;

  /// Deserializes a [Source] from a JSON-serializable map.
  factory Source.fromJson(Map<String, Object?> json) {
    final type = json['type']! as String;
    return switch (type) {
      'pattern' => Source.pattern(
        json['value']! as String,
        optional: json['optional'] as bool? ?? false,
      ),
      'artifact' => Source.artifact(
        Artifact(json['artifact']! as String),
        platform: json['platform'] as String?,
        mode: json['mode'] != null ? BuildMode.fromCliName(json['mode']! as String) : null,
      ),
      'host_artifact' => Source.hostArtifact(HostArtifact(json['artifact']! as String)),
      _ => throw ArgumentError('Unknown Source type in JSON: $type'),
    };
  }

  /// Visit the particular source type.
  void accept(SourceVisitor visitor);

  /// Whether the output source provided can be known before executing the rule.
  bool get implicit;

  /// Serializes the source to a JSON-serializable map.
  Map<String, Object?> toJson();
}

@immutable
class _PatternSource extends Source {
  const _PatternSource(this.value, {this.optional = false});

  final String value;
  final bool optional;

  @override
  void accept(SourceVisitor visitor) => visitor.visitPattern(value, optional);

  @override
  bool get implicit => value.contains('*');

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'pattern',
    'value': value,
    'optional': optional,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _PatternSource && other.value == value && other.optional == optional);

  @override
  int get hashCode => Object.hash(value, optional);
}

@immutable
class _ArtifactSource extends Source {
  const _ArtifactSource(this.artifact, {this.platform, this.mode});

  final Artifact artifact;
  final String? platform;
  final BuildMode? mode;

  @override
  void accept(SourceVisitor visitor) => visitor.visitArtifact(artifact, platform, mode);

  @override
  bool get implicit => false;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'artifact',
    'artifact': artifact.name,
    if (platform != null) 'platform': platform,
    if (mode != null) 'mode': mode!.cliName,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _ArtifactSource &&
          other.artifact == artifact &&
          other.platform == platform &&
          other.mode == mode);

  @override
  int get hashCode => Object.hash(artifact, platform, mode);
}

@immutable
class _HostArtifactSource extends Source {
  const _HostArtifactSource(this.artifact);

  final HostArtifact artifact;

  @override
  void accept(SourceVisitor visitor) => visitor.visitHostArtifact(artifact);

  @override
  bool get implicit => false;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'host_artifact',
    'artifact': artifact.name,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is _HostArtifactSource && other.artifact == artifact);

  @override
  int get hashCode => artifact.hashCode;
}

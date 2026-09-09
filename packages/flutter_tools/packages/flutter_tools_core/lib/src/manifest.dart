// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

/// Declaration of a Flutter tool extension within a manifest file.
@immutable
class ExtensionDeclaration {
  const ExtensionDeclaration({
    required this.name,
    this.description,
    this.enabled = true,
    this.entrypoint,
    this.path,
    this.supportedPlatforms,
  });

  /// Deserializes an [ExtensionDeclaration] from a JSON-serializable map.
  factory ExtensionDeclaration.fromJson(Map<String, Object?> json) {
    if (json case {'name': final String name}) {
      final List<String>? platforms = switch (json['supportedPlatforms']) {
        final List<Object?> list => list.whereType<String>().toList(),
        _ => null,
      };
      return ExtensionDeclaration(
        name: name,
        description: switch (json['description']) {
          final String s => s,
          _ => null,
        },
        enabled: switch (json['enabled']) {
          final bool b => b,
          _ => true,
        },
        entrypoint: switch (json['entrypoint']) {
          final String s => s,
          _ => null,
        },
        path: switch (json['path']) {
          final String s => s,
          _ => null,
        },
        supportedPlatforms: platforms,
      );
    }
    throw FormatException('Invalid extension declaration, missing "name" field: $json');
  }

  /// The unique package or extension identifier.
  final String name;

  /// Optional human-readable description of what this extension provides.
  final String? description;

  /// Whether this extension should be loaded by the Flutter tool.
  final bool enabled;

  /// Relative path to the Dart entrypoint file within the extension package.
  ///
  /// Defaults to `bin/<name>.dart` if omitted.
  final String? entrypoint;

  /// Path to the extension package directory.
  ///
  /// If omitted, the extension is resolved through `.dart_tool/package_config.json`.
  final String? path;

  /// Platforms supported by this extension (e.g. `'linux'`, `'macos'`, `'windows'`).
  final List<String>? supportedPlatforms;

  /// Serializes this declaration to a JSON-serializable map.
  Map<String, Object?> toMap() => <String, Object?>{
    'name': name,
    'description': ?description,
    'enabled': enabled,
    'entrypoint': ?entrypoint,
    'path': ?path,
    'supportedPlatforms': ?supportedPlatforms,
  };

  @override
  String toString() =>
      'ExtensionDeclaration(name: $name, path: $path, entrypoint: $entrypoint, enabled: $enabled, description: $description, supportedPlatforms: $supportedPlatforms)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! ExtensionDeclaration) {
      return false;
    }
    if (other.name != name ||
        other.description != description ||
        other.enabled != enabled ||
        other.entrypoint != entrypoint ||
        other.path != path) {
      return false;
    }
    if (other.supportedPlatforms == null && supportedPlatforms == null) {
      return true;
    }
    if (other.supportedPlatforms == null || supportedPlatforms == null) {
      return false;
    }
    if (other.supportedPlatforms!.length != supportedPlatforms!.length) {
      return false;
    }
    for (var i = 0; i < supportedPlatforms!.length; i++) {
      if (other.supportedPlatforms![i] != supportedPlatforms![i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    name,
    description,
    enabled,
    entrypoint,
    path,
    supportedPlatforms == null ? null : Object.hashAll(supportedPlatforms!),
  );
}

/// A parsed `flutter_extensions.yaml` manifest containing one or more [ExtensionDeclaration]s.
@immutable
class ExtensionManifest {
  const ExtensionManifest({required this.extensions});

  /// Deserializes an [ExtensionManifest] from a JSON-serializable map.
  factory ExtensionManifest.fromJson(Map<String, Object?> json) {
    final List<ExtensionDeclaration> extensionsList = switch (json['extensions']) {
      final List<Object?> list => <ExtensionDeclaration>[
        for (final Object? item in list)
          if (item is Map)
            ExtensionDeclaration.fromJson(item.cast<String, Object?>())
          else
            throw FormatException('Invalid extension declaration entry in list: $item'),
      ],
      final Map<Object?, Object?> map => <ExtensionDeclaration>[
        for (final MapEntry<Object?, Object?>(key: Object? key, value: Object? value)
            in map.entries)
          if (value is Map)
            ExtensionDeclaration.fromJson(<String, Object?>{
              ...value.cast<String, Object?>(),
              if (!value.containsKey('name')) 'name': key.toString(),
            })
          else
            throw FormatException('Invalid extension configuration for "$key": $value'),
      ],
      _ => <ExtensionDeclaration>[],
    };
    return ExtensionManifest(extensions: extensionsList);
  }

  /// The list of extensions declared in the manifest.
  final List<ExtensionDeclaration> extensions;

  /// Serializes this manifest to a JSON-serializable map.
  Map<String, Object?> toMap() => <String, Object?>{
    'extensions': extensions.map((ExtensionDeclaration e) => e.toMap()).toList(),
  };

  @override
  String toString() => 'ExtensionManifest(extensions: $extensions)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! ExtensionManifest) {
      return false;
    }
    if (other.extensions.length != extensions.length) {
      return false;
    }
    for (var i = 0; i < extensions.length; i++) {
      if (other.extensions[i] != extensions[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(extensions);
}

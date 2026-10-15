// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

/// Static metadata parsed from an extension package's
/// `extension/flutter_tools/config.yaml` file.
@immutable
final class ExtensionPackageConfig {
  /// Creates an [ExtensionPackageConfig].
  ExtensionPackageConfig({
    required this.name,
    this.protocolVersion = currentProtocolVersion,
    String? entrypoint,
    Iterable<String> supportedPlatforms = const <String>[],
    Iterable<String> services = const <String>{},
    Iterable<String> buildTargets = const <String>[],
    Iterable<String> templates = const <String>[],
    Iterable<String> platforms = const <String>[],
  }) : entrypoint = entrypoint ?? 'bin/$name.dart',
       supportedPlatforms = List<String>.unmodifiable(
         supportedPlatforms.map((String p) => p.toLowerCase()),
       ),
       services = Set<String>.unmodifiable(services),
       buildTargets = List<String>.unmodifiable(buildTargets),
       templates = List<String>.unmodifiable(templates),
       platforms = List<String>.unmodifiable(platforms);

  /// Parses an [ExtensionPackageConfig] from a decoded YAML or JSON [map].
  ///
  /// Throws a [FormatException] if required fields are missing or invalid.
  factory ExtensionPackageConfig.fromMap(Map<Object?, Object?> map, {String? packageName}) {
    final Object? rawName = map[kNameKey] ?? packageName;
    if (rawName is! String || rawName.trim().isEmpty) {
      throw const FormatException(
        'Extension config.yaml must specify a non-empty string for "$kNameKey".',
      );
    }
    final String name = rawName.trim();

    if (packageName != null && name != packageName) {
      throw FormatException(
        'Extension config.yaml "$kNameKey" ("$name") must match package name ("$packageName").',
      );
    }

    final Object? rawProtocolVersion = map[kProtocolVersionKey] ?? map['protocol_version'];
    final int protocolVersion = switch (rawProtocolVersion) {
      final int v => v,
      null => currentProtocolVersion,
      final Object? other => throw FormatException(
        'Extension config.yaml "$kProtocolVersionKey" must be an int, got: $other.',
      ),
    };

    final String entrypoint = switch (map[kEntrypointKey]) {
      final String e when e.trim().isNotEmpty => e.trim(),
      null => 'bin/$name.dart',
      final Object? other => throw FormatException(
        'Extension config.yaml "$kEntrypointKey" must be a non-empty string, got: $other.',
      ),
    };

    return ExtensionPackageConfig(
      name: name,
      protocolVersion: protocolVersion,
      entrypoint: entrypoint,
      supportedPlatforms: _parseStringList(
        map[kSupportedPlatformsKey] ?? map['supported_platforms'],
        kSupportedPlatformsKey,
      ),
      services: _parseStringList(map[kServicesKey], kServicesKey).toSet(),
      buildTargets: _parseStringList(
        map[kBuildTargetsKey] ?? map['build_targets'],
        kBuildTargetsKey,
      ),
      templates: _parseStringList(map[kTemplatesKey], kTemplatesKey),
      platforms: _parseStringList(map[kPlatformsKey], kPlatformsKey),
    );
  }

  /// Current supported extension protocol version.
  static const int currentProtocolVersion = 1;

  /// Map key for [name].
  static const String kNameKey = 'name';

  /// Map key for [protocolVersion].
  static const String kProtocolVersionKey = 'protocolVersion';

  /// Map key for [entrypoint].
  static const String kEntrypointKey = 'entrypoint';

  /// Map key for [supportedPlatforms].
  static const String kSupportedPlatformsKey = 'supportedPlatforms';

  /// Map key for [services].
  static const String kServicesKey = 'services';

  /// Map key for [buildTargets].
  static const String kBuildTargetsKey = 'buildTargets';

  /// Map key for [templates].
  static const String kTemplatesKey = 'templates';

  /// Map key for [platforms].
  static const String kPlatformsKey = 'platforms';

  /// The Dart package name of the extension.
  final String name;

  /// The extension protocol version targeted by this package.
  final int protocolVersion;

  /// Relative path from the extension package root to the isolate entrypoint script.
  final String entrypoint;

  /// Host platforms supported by this extension (e.g. `['linux', 'macos', 'windows']`).
  ///
  /// If empty, the extension is assumed to support all host platforms.
  final List<String> supportedPlatforms;

  /// Service namespaces provided by this extension (e.g. `{'diagnostics', 'config', 'build'}`).
  final Set<String> services;

  /// Custom build target names provided by this extension.
  final List<String> buildTargets;

  /// Custom project template names provided by this extension.
  final List<String> templates;

  /// Custom target platform names provided by this extension for `--platforms`.
  final List<String> platforms;

  /// Whether this extension supports the given [hostPlatform] (case-insensitive).
  bool supportsHostPlatform(String hostPlatform) {
    if (supportedPlatforms.isEmpty) {
      return true;
    }
    return supportedPlatforms.contains(hostPlatform.toLowerCase());
  }

  /// Serializes this [ExtensionPackageConfig] to a JSON-compatible map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      kNameKey: name,
      kProtocolVersionKey: protocolVersion,
      kEntrypointKey: entrypoint,
      kSupportedPlatformsKey: supportedPlatforms,
      kServicesKey: services.toList(),
      kBuildTargetsKey: buildTargets,
      kTemplatesKey: templates,
      kPlatformsKey: platforms,
    };
  }

  static List<String> _parseStringList(Object? raw, String fieldName) {
    return switch (raw) {
      null => const <String>[],
      final List<Object?> list => <String>[
        for (final Object? item in list)
          if (item is String && item.trim().isNotEmpty)
            item.trim()
          else
            throw FormatException(
              'Extension config.yaml "$fieldName" entries must be non-empty strings, got: $item.',
            ),
      ],
      final Object other => throw FormatException(
        'Extension config.yaml "$fieldName" must be a list of strings, got: $other.',
      ),
    };
  }

  static bool _listEquals(List<String> a, List<String> b) {
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

  static bool _setEquals(Set<String> a, Set<String> b) {
    if (identical(a, b)) {
      return true;
    }
    return a.length == b.length && a.containsAll(b);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ExtensionPackageConfig &&
        other.name == name &&
        other.protocolVersion == protocolVersion &&
        other.entrypoint == entrypoint &&
        _listEquals(other.supportedPlatforms, supportedPlatforms) &&
        _setEquals(other.services, services) &&
        _listEquals(other.buildTargets, buildTargets) &&
        _listEquals(other.templates, templates) &&
        _listEquals(other.platforms, platforms);
  }

  @override
  int get hashCode => Object.hash(
    name,
    protocolVersion,
    entrypoint,
    Object.hashAll(supportedPlatforms),
    Object.hashAllUnordered(services),
    Object.hashAll(buildTargets),
    Object.hashAll(templates),
    Object.hashAll(platforms),
  );

  @override
  String toString() =>
      'ExtensionPackageConfig('
      'name: $name, '
      'protocolVersion: $protocolVersion, '
      'entrypoint: $entrypoint, '
      'supportedPlatforms: $supportedPlatforms, '
      'services: $services, '
      'buildTargets: $buildTargets, '
      'templates: $templates, '
      'platforms: $platforms)';
}

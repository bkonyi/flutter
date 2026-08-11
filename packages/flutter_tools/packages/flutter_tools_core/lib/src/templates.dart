// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

/// A template representation used to generate an entire Flutter project.
///
/// Extensions implement this class to define custom project templates.
abstract base class ProjectTemplate {
  /// The name of this project template.
  String get name;

  /// Whether this template is hidden from help displays.
  bool get hidden;

  /// Dependent template names.
  Set<String> get templateDependencies;

  /// The template source files.
  Set<String> get templateSources;

  /// The package URI string or directory path to the template sources.
  String get templatePath;

  /// Generates the variable mappings for the template.
  Future<Map<String, Object?>> generateTemplateParameters(Map<String, Object?> toolParameters);

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'name': name,
      'hidden': hidden,
      'templateDependencies': templateDependencies.toList(),
      'templateSources': templateSources.toList(),
      'templatePath': templatePath,
    };
  }
}

/// A concrete implementation of [ProjectTemplate] that can be parsed from a JSON map.
///
/// This represents an extension's template on the host side. Its
/// [generateTemplateParameters] method throws an [UnimplementedError] because
/// parameter generation must be delegated to the extension isolate via RPC.
final class ExtensionProjectTemplate extends ProjectTemplate {
  /// Creates an [ExtensionProjectTemplate].
  ExtensionProjectTemplate({
    required this.name,
    required this.hidden,
    required this.templateDependencies,
    required this.templateSources,
    required this.templatePath,
  });

  /// Deserializes an [ExtensionProjectTemplate] from a JSON map.
  factory ExtensionProjectTemplate.fromJson(Map<String, Object?> json) {
    return ExtensionProjectTemplate(
      name: json['name'] as String? ?? '',
      hidden: json['hidden'] as bool? ?? false,
      templateDependencies:
          (json['templateDependencies'] as List<Object?>?)?.cast<String>().toSet() ??
          const <String>{},
      templateSources:
          (json['templateSources'] as List<Object?>?)?.cast<String>().toSet() ?? const <String>{},
      templatePath: json['templatePath'] as String? ?? '',
    );
  }

  @override
  final String name;

  @override
  final bool hidden;

  @override
  final Set<String> templateDependencies;

  @override
  final Set<String> templateSources;

  @override
  final String templatePath;

  @override
  Future<Map<String, Object?>> generateTemplateParameters(
    Map<String, Object?> toolParameters,
  ) async {
    throw UnimplementedError(
      'ExtensionProjectTemplate.generateTemplateParameters should not be called directly on host representation.',
    );
  }

  static List<ExtensionProjectTemplate> listFromJson(Object? rpcResult) {
    final list = rpcResult! as List<Object?>;
    return list.cast<Map<String, Object?>>().map(ExtensionProjectTemplate.fromJson).toList();
  }
}

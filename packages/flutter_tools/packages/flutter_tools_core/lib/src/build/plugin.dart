// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

/// DTO for a resolved plugin for a custom platform extension.
@immutable
class ExtensionPlugin {
  const ExtensionPlugin({required this.name, required this.path, required this.configuration});

  factory ExtensionPlugin.fromJson(Map<String, Object?> json) {
    return ExtensionPlugin(
      name: json['name']! as String,
      path: json['path']! as String,
      configuration: (json['configuration'] as Map<String, Object?>?) ?? const <String, Object?>{},
    );
  }

  final String name;
  final String path;
  final Map<String, Object?> configuration;

  Map<String, Object?> toMap() => <String, Object?>{
    'name': name,
    'path': path,
    'configuration': configuration,
  };

  @override
  bool operator ==(Object other) {
    return other is ExtensionPlugin && other.name == name && other.path == path;
  }

  @override
  int get hashCode => Object.hash(name, path);
}

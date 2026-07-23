// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

/// Representation of a target device provided by a tool extension.
@immutable
class TargetDevice {
  /// Creates a [TargetDevice] definition.
  const TargetDevice({
    required this.id,
    required this.name,
    required this.category,
    required this.platformType,
    this.targetPlatform,
    this.sdkNameAndVersion,
    this.buildTarget,
    this.ephemeral = true,
    this.isSupported = true,
    this.isSupportedForProject = true,
  });

  /// Deserializes a [TargetDevice] from a JSON-serializable map.
  factory TargetDevice.fromJson(Map<String, Object?> json) {
    return TargetDevice(
      id: json['id']! as String,
      name: json['name']! as String,
      category: json['category']! as String,
      platformType: json['platformType']! as String,
      targetPlatform: json['targetPlatform'] as String?,
      buildTarget: json['buildTarget'] as String?,
      sdkNameAndVersion: json['sdkNameAndVersion'] as String?,
      ephemeral: json['ephemeral']! as bool,
      isSupported: json['isSupported']! as bool,
      isSupportedForProject: json['isSupportedForProject']! as bool,
    );
  }

  /// Unique identifier of the device.
  final String id;

  /// Display name of the device.
  final String name;

  /// Device category (e.g. `'desktop'`, `'mobile'`, `'web'`).
  final String category;

  /// Platform type (e.g. `'custom'`, `'linux'`, `'android'`).
  final String platformType;

  /// Target platform identifier string (e.g. `'linux-x64'`, `'linux-arm64'`, `'android-arm64'`).
  final String? targetPlatform;

  /// Operating system SDK name and version string (e.g. `'Custom Linux 1.0.0'`).
  final String? sdkNameAndVersion;

  /// Target build assembly identifier.
  final String? buildTarget;

  /// Whether the device is ephemeral.
  final bool ephemeral;

  /// Whether the device is supported by Flutter tooling on the host platform.
  final bool isSupported;

  /// Whether the device is supported for the current project.
  final bool isSupportedForProject;

  /// Serializes the target device to a JSON-serializable map.
  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'name': name,
    'category': category,
    'platformType': platformType,
    'targetPlatform': ?targetPlatform,
    'buildTarget': ?buildTarget,
    'sdkNameAndVersion': ?sdkNameAndVersion,
    'ephemeral': ephemeral,
    'isSupported': isSupported,
    'isSupportedForProject': isSupportedForProject,
  };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is TargetDevice &&
            other.id == id &&
            other.name == name &&
            other.category == category &&
            other.platformType == platformType &&
            other.targetPlatform == targetPlatform &&
            other.buildTarget == buildTarget &&
            other.sdkNameAndVersion == sdkNameAndVersion &&
            other.ephemeral == ephemeral &&
            other.isSupported == isSupported &&
            other.isSupportedForProject == isSupportedForProject);
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    category,
    platformType,
    targetPlatform,
    sdkNameAndVersion,
    buildTarget,
    ephemeral,
    isSupported,
    isSupportedForProject,
  );
}

// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:meta/meta.dart';

/// Typedef for an extension RPC handler function.
typedef ExtensionRpcHandler = FutureOr<Object?> Function(Map<String, Object?> params);

/// Represents a logical service exposed by a Flutter Tool Extension.
///
/// Extension authors implement this class to group related RPC endpoints under
/// a specific [namespace] (e.g. `diagnostics`, `configuration`, `device`, `build`, `templates`).
abstract class ToolExtensionService {
  /// The namespace string of the service (e.g. `'diagnostics'`).
  String get namespace;

  /// Initializes state needed by the service and returns a map of method handlers.
  ///
  /// The returned map maps method names (without namespace prefix) to handler functions.
  Future<Map<String, ExtensionRpcHandler>> initialize();

  /// Cleans up resources held by the service when the extension is shut down.
  Future<void> shutdown() async {}
}

/// Represents the capabilities and supported service namespaces reported by an extension.
@immutable
class ToolExtensionCapabilities {
  /// Creates [ToolExtensionCapabilities] listing supported [services] and [supportedPlatforms].
  const ToolExtensionCapabilities({
    required this.services,
    this.extensionName,
    this.supportedPlatforms = const <String>{'linux', 'macos', 'windows'},
  });

  /// Deserializes [ToolExtensionCapabilities] from a JSON map payload.
  factory ToolExtensionCapabilities.fromJson(Map<String, Object?> json) {
    final Object? servicesList = json['services'];
    final services = servicesList is Iterable ? List<String>.from(servicesList) : <String>[];
    final Object? platformsList = json['supportedPlatforms'];
    final Set<String> supportedPlatforms = platformsList is Iterable
        ? platformsList.map((Object? p) => p.toString().toLowerCase()).toSet()
        : const <String>{'linux', 'macos', 'windows'};
    final extensionName = json['extensionName'] as String?;
    return ToolExtensionCapabilities(
      services: services,
      supportedPlatforms: supportedPlatforms,
      extensionName: extensionName,
    );
  }

  /// The list of service namespace identifiers supported by the extension.
  final List<String> services;

  /// The unique name of the extension, if reported.
  final String? extensionName;

  /// The set of host operating system platforms supported by the extension in lowercase (e.g., `{'linux'}`).
  final Set<String> supportedPlatforms;

  /// Returns whether the extension supports the given [hostPlatform].
  bool supportsHostPlatform(String hostPlatform) {
    return supportedPlatforms.contains(hostPlatform.toLowerCase());
  }

  /// Whether the extension provides an artifact service.
  bool get artifactServiceProvided => services.contains('artifact');

  /// Whether the extension provides a clean service.
  bool get cleanServiceProvided => services.contains('clean');

  /// Serializes capabilities to a map payload.
  Map<String, Object?> toMap() => <String, Object?>{
    'services': services,
    'supportedPlatforms': supportedPlatforms.toList(),
    if (extensionName != null) 'extensionName': extensionName,
  };
}

/// The representation of a Flutter Tools extension bundle.
abstract base class FlutterToolsExtension {
  FlutterToolsExtension({
    this.artifactService,
    this.buildService,
    this.cleanService,
    this.configurationService,
    this.deviceService,
    this.diagnosticsService,
    this.templateService,
  });

  /// The service responsible for acquiring the necessary files to develop
  /// and deploy Flutter applications for a custom target platform.
  final ToolExtensionService? artifactService;

  /// The primary coordinator between the tool and extension compilation logic.
  final ToolExtensionService? buildService;

  /// The service responsible for cleaning extension-managed build outputs and temporary artifacts.
  final ToolExtensionService? cleanService;

  /// The service responsible for managing custom configuration options for an extension.
  final ToolExtensionService? configurationService;

  /// The service responsible for managing custom hardware and emulators.
  final ToolExtensionService? deviceService;

  /// The service responsible for executing custom diagnostic checks that can be reported via `flutter doctor`.
  final ToolExtensionService? diagnosticsService;

  /// The service responsible for adding custom platform support to `flutter create`.
  final ToolExtensionService? templateService;
}

/// Determines the set of capabilities provided by a [FlutterToolsExtension].
final class FlutterToolExtensionCapabilities extends ToolExtensionCapabilities {
  const FlutterToolExtensionCapabilities({
    required super.services,
    super.extensionName,
    super.supportedPlatforms,
  });

  factory FlutterToolExtensionCapabilities.fromExtension(FlutterToolsExtension ext) {
    final services = <String>[];
    if (ext.artifactService != null) {
      services.add(ext.artifactService!.namespace);
    }
    if (ext.buildService != null) {
      services.add(ext.buildService!.namespace);
    }
    if (ext.cleanService != null) {
      services.add(ext.cleanService!.namespace);
    }
    if (ext.configurationService != null) {
      services.add(ext.configurationService!.namespace);
    }
    if (ext.deviceService != null) {
      services.add(ext.deviceService!.namespace);
    }
    if (ext.diagnosticsService != null) {
      services.add(ext.diagnosticsService!.namespace);
    }
    if (ext.templateService != null) {
      services.add(ext.templateService!.namespace);
    }
    return FlutterToolExtensionCapabilities(services: services);
  }

  factory FlutterToolExtensionCapabilities.fromJson(Map<String, Object?> json) {
    final base = ToolExtensionCapabilities.fromJson(json);
    return FlutterToolExtensionCapabilities(
      services: base.services,
      extensionName: base.extensionName,
      supportedPlatforms: base.supportedPlatforms,
    );
  }
}

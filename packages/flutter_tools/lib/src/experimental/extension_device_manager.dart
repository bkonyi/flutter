// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';

import '../application_package.dart';
import '../artifacts.dart';
import '../base/file_system.dart';
import '../base/logger.dart';
import '../build_info.dart';
import '../build_system/targets/extension.dart';
import '../device.dart';
import '../device_port_forwarder.dart';
import '../flutter_plugins.dart';
import '../plugins.dart';
import '../project.dart';
import 'extension_discovery.dart';
import 'extension_manager.dart';

/// A host-side [DeviceService] client adapter delegating RPC queries to an [ExtensionConnection].
final class ExtensionDeviceClient extends DeviceService {
  /// Creates an [ExtensionDeviceClient] wrapping the host [connection].
  ExtensionDeviceClient(this.connection, {required Logger logger}) : _logger = logger;

  /// The active extension isolate connection.
  final ExtensionConnection connection;
  final Logger _logger;

  @override
  Future<List<TargetDevice>> getDevices() async {
    _logger.printTrace(
      'ExtensionDeviceClient fetching devices via RPC ("${DeviceService.getDevicesMethod}")...',
    );
    final rawResult =
        (await connection.sendRequest(DeviceService.getDevicesMethod))! as List<Object?>;
    final List<TargetDevice> devices = rawResult
        .cast<Map<String, Object?>>()
        .map(TargetDevice.fromJson)
        .toList();
    _logger.printTrace('ExtensionDeviceClient received ${devices.length} device(s) via RPC.');
    return devices;
  }

  @override
  Future<Map<String, Object?>> launchApp({
    required String deviceId,
    required String executablePath,
    Map<String, Object?>? debuggingOptions,
  }) async {
    return (await connection.sendRequest(DeviceService.launchAppMethod, <String, Object?>{
          'deviceId': deviceId,
          'executablePath': executablePath,
          'debuggingOptions': ?debuggingOptions,
        }))!
        as Map<String, Object?>;
  }

  @override
  Future<String?> getVmServiceUri({
    required String deviceId,
    required String executablePath,
  }) async {
    final Object? result = await connection.sendRequest(
      DeviceService.getVmServiceUriMethod,
      <String, Object?>{'deviceId': deviceId, 'executablePath': executablePath},
    );
    return result as String?;
  }
}

/// A host-side [DeviceDiscovery] mechanism that discovers devices registered by active extensions.
class ExtensionDeviceDiscovery extends PollingDeviceDiscovery {
  /// Creates an [ExtensionDeviceDiscovery] instance.
  ExtensionDeviceDiscovery({
    required ExtensionManager extensionManager,
    required Logger logger,
    required FileSystem fileSystem,
    required Artifacts artifacts,
  }) : _extensionManager = extensionManager,
       _logger = logger,
       _fileSystem = fileSystem,
       _artifacts = artifacts,
       super('tool_extension');

  final ExtensionManager _extensionManager;
  final Logger _logger;
  final FileSystem _fileSystem;
  final Artifacts _artifacts;

  @override
  bool get supportsPlatform => true;

  @override
  bool get canListAnything => true;

  @override
  List<String> get wellKnownIds => const <String>[];

  @override
  Future<List<Device>> pollingGetDevices({
    Duration? timeout,
    bool forWirelessDiscovery = false,
  }) async {
    _logger.printTrace('ExtensionDeviceDiscovery polling active tool extension devices...');
    await _extensionManager.ensureInitialized();
    final List<DeviceService> deviceServices = _extensionManager.deviceExtensions;
    if (deviceServices.isEmpty) {
      _logger.printTrace('ExtensionDeviceDiscovery found 0 active device extensions.');
      return <Device>[];
    }

    final List<List<Device>> devicesPerService = await Future.wait(
      deviceServices.whereType<ExtensionDeviceClient>().map((service) async {
        try {
          final List<TargetDevice> devices = await service.getDevices();
          return devices
              .map(
                (targetDevice) => ExtensionBackedDevice(
                  logger: _logger,
                  fileSystem: _fileSystem,
                  targetDevice: targetDevice,
                  connection: service.connection,
                  artifacts: _artifacts,
                ),
              )
              .toList();
        } on Object catch (e, st) {
          _logger.printTrace('Error querying device extension service: $e\n$st');
          return <Device>[];
        }
      }),
    );

    final targetDevices = <Device>[for (final deviceList in devicesPerService) ...deviceList];

    _logger.printTrace(
      'ExtensionDeviceDiscovery retrieved ${targetDevices.length} target device(s).',
    );
    return targetDevices;
  }

  @override
  Future<List<String>> getDiagnostics() async => <String>[];
}

/// A host-side [Device] wrapper representing a target device backed by a tool extension.
class ExtensionBackedDevice extends Device {
  /// Creates an [ExtensionBackedDevice] wrapping a [TargetDevice].
  ExtensionBackedDevice({
    required super.logger,
    required FileSystem fileSystem,
    required TargetDevice targetDevice,
    required this.connection,
    required Artifacts artifacts,
  }) : _targetDevice = targetDevice,
       _logger = logger,
       _fileSystem = fileSystem,
       _artifacts = artifacts,
       super(
         targetDevice.id,
         category: Category.fromString(targetDevice.category) ?? Category.desktop,
         platformType: PlatformType.fromString(targetDevice.platformType) ?? PlatformType.custom,
         ephemeral: targetDevice.ephemeral,
       );

  final TargetDevice _targetDevice;
  final ExtensionConnection connection;
  final Logger _logger;
  final FileSystem _fileSystem;
  final Artifacts _artifacts;

  @override
  String get name => _targetDevice.name;

  @override
  Future<bool> isSupported() async => _targetDevice.isSupported;

  @override
  bool isSupportedForProject(FlutterProject project) => _targetDevice.isSupportedForProject;

  @override
  Future<String> get sdkNameAndVersion async =>
      _targetDevice.sdkNameAndVersion ?? 'Tool Extension Device';

  @override
  Future<String> get targetPlatformDisplayName async => _targetDevice.platformType;

  @override
  Future<TargetPlatform> get targetPlatform async {
    final String? platformName = _targetDevice.targetPlatform;
    if (platformName != null) {
      try {
        return getTargetPlatformForName(platformName);
      } on Object catch (_) {
        // Fall through if unrecognized target platform name supplied.
      }
    }
    try {
      return getTargetPlatformForName(_targetDevice.platformType);
    } on Object catch (_) {
      return TargetPlatform.tester;
    }
  }

  @override
  Future<bool> get isLocalEmulator async => false;

  @override
  Future<CpuArch> get cpuArch async => CpuArch.unknown;

  @override
  Future<String?> get emulatorId async => null;

  @override
  DevicePortForwarder? get portForwarder => null;

  @override
  DeviceLogReader getLogReader({ApplicationPackage? app, bool includePastLogs = false}) =>
      NoOpDeviceLogReader(name);

  @override
  void clearLogs() {}

  @override
  Future<void> dispose() async {}

  @override
  Future<bool> isLatestBuildInstalled(ApplicationPackage app) async => false;

  @override
  Future<bool> installApp(ApplicationPackage app, {String? userIdentifier}) async => true;

  @override
  Future<LaunchResult> startApp(
    ApplicationPackage? package, {
    String? mainPath,
    String? route,
    DebuggingOptions? debuggingOptions,
    Map<String, Object?>? platformArgs,
    bool prebuiltApplication = false,
    bool ipv6 = false,
    String? userIdentifier,
  }) async {
    if (debuggingOptions == null) {
      return LaunchResult.failed();
    }
    try {
      final String? buildTarget = _targetDevice.buildTarget;
      if (buildTarget == null) {
        return LaunchResult.failed();
      }
      String projectDirectory = _fileSystem.currentDirectory.path;
      if (mainPath != null) {
        final Directory? resolvedProjectDir = _findProjectRoot(_fileSystem.file(mainPath));
        if (resolvedProjectDir != null) {
          projectDirectory = resolvedProjectDir.path;
        }
      }

      String? outputDirPattern;
      ExtensionBuildTarget? matchedTarget;
      try {
        final targetsResult =
            (await connection.sendRequest(BuildService.getBuildTargetsMethod))! as List<Object?>;
        for (final Map<String, Object?> targetMap in targetsResult.cast<Map<String, Object?>>()) {
          if (targetMap['name'] == buildTarget) {
            matchedTarget = ExtensionBuildTarget.fromJson(targetMap);
            outputDirPattern = matchedTarget.outputDir;
            break;
          }
        }
      } on Object catch (e) {
        _logger.printTrace('Failed to query build targets from extension: $e');
      }

      outputDirPattern ??=
          '$kProjectDirPlaceholder/build/$kTargetPlatformPlaceholder/$kBuildModePlaceholder';

      final String resolvedOutputDir = _fileSystem.path.normalize(
        outputDirPattern
            .replaceAll(kProjectDirPlaceholder, projectDirectory)
            .replaceAll(kBuildModePlaceholder, debuggingOptions.buildInfo.modeName)
            .replaceAll(kTargetPlatformPlaceholder, _targetDevice.targetPlatform ?? ''),
      );

      final resolvedArtifacts = <String, String>{};
      if (matchedTarget != null) {
        final mode = BuildMode.fromCliName(debuggingOptions.buildInfo.modeName);
        final resolver = ArtifactResolver(
          artifacts: _artifacts,
          targetPlatform: TargetPlatform.fromName(matchedTarget.targetPlatform),
          buildMode: mode,
        );
        for (final Source input in matchedTarget.inputs) {
          input.accept(resolver);
        }
        resolvedArtifacts.addAll(resolver.resolvedArtifacts);
      }

      final FlutterProject project = FlutterProject.fromDirectory(
        _fileSystem.directory(projectDirectory),
      );
      final String platformName = _targetDevice.targetPlatform ?? _targetDevice.platformType;

      final String pluginPlatformKey = matchedTarget?.pluginPlatformKey ?? platformName;
      final plugins = <ExtensionPlugin>[];
      await refreshPluginsList(project);
      final List<Plugin> allPlugins = await findPlugins(project);
      final List<Plugin> resolved = resolvePluginImplementationsForPlatform(
        allPlugins,
        pluginPlatformKey,
      );
      for (final p in resolved) {
        if (p.platforms[pluginPlatformKey] case final platformConfig?) {
          plugins.add(
            ExtensionPlugin(name: p.name, path: p.path, configuration: platformConfig.toMap()),
          );
        }
      }

      final Object? buildResult = await connection
          .sendRequest(BuildService.buildMethod, <String, Object?>{
            'targetName': buildTarget,
            'projectRoot': projectDirectory,
            'mainPath': mainPath ?? 'lib/main.dart',
            'buildMode': debuggingOptions.buildInfo.modeName,
            'outputDir': resolvedOutputDir,
            'buildDir': _fileSystem.path.join(projectDirectory, '.dart_tool', 'flutter_build'),
            'resolvedArtifacts': resolvedArtifacts,
            'plugins': plugins.map((ExtensionPlugin p) => p.toMap()).toList(),
          }, const Duration(minutes: 5));

      final buildResultMap = buildResult! as Map<String, Object?>;
      final executablePath = buildResultMap['executablePath'] as String?;

      if (executablePath == null) {
        return LaunchResult.failed();
      }

      final Object? launchResult = await connection.sendRequest(
        DeviceService.launchAppMethod,
        <String, Object?>{
          'deviceId': _targetDevice.id,
          'executablePath': _fileSystem.path.absolute(executablePath),
          if (debuggingOptions.debuggingEnabled)
            'debuggingOptions': <String, Object?>{
              if (debuggingOptions.buildInfo.isDebug) 'buildInfo.isDebug': true,
              if (debuggingOptions.buildInfo.isProfile) 'buildInfo.isProfile': true,
              if (debuggingOptions.buildInfo.isRelease) 'buildInfo.isRelease': true,
              if (debuggingOptions.dartEntrypointArgs.isNotEmpty)
                'dartEntrypointArgs': debuggingOptions.dartEntrypointArgs,
              'deviceVmServicePort': ?debuggingOptions.deviceVmServicePort,
              if (debuggingOptions.disablePortPublication) 'disablePortPublication': true,
              if (debuggingOptions.disableServiceAuthCodes) 'disableServiceAuthCodes': true,
              if (debuggingOptions.enableDartProfiling) 'enableDartProfiling': true,
              if (debuggingOptions.enableImpeller.name != 'none')
                'enableImpeller': debuggingOptions.enableImpeller.name,
              if (debuggingOptions.enableSoftwareRendering) 'enableSoftwareRendering': true,
              if (debuggingOptions.endlessTraceBuffer) 'endlessTraceBuffer': true,
              'hostVmServicePort': ?debuggingOptions.hostVmServicePort,
              if (debuggingOptions.ipv6) 'ipv6': true,
              if (debuggingOptions.skiaDeterministicRendering) 'skiaDeterministicRendering': true,
              if (debuggingOptions.startPaused) 'startPaused': true,
              'traceAllowlist': ?debuggingOptions.traceAllowlist,
              if (debuggingOptions.traceSkia) 'traceSkia': true,
              'traceSkiaAllowlist': ?debuggingOptions.traceSkiaAllowlist,
              if (debuggingOptions.traceSystrace) 'traceSystrace': true,
              if (debuggingOptions.useTestFonts) 'useTestFonts': true,
              if (debuggingOptions.verboseSystemLogs) 'verboseSystemLogs': true,
            },
        },
      );

      final launchResultMap = launchResult! as Map<String, Object?>;
      final vmServiceUriStringInitial = launchResultMap['vmServiceUri'] as String?;
      final Uri? vmServiceUri = vmServiceUriStringInitial != null
          ? Uri.tryParse(vmServiceUriStringInitial)
          : null;
      if (vmServiceUri != null) {
        _logger.printTrace('Parsed VM Service URI: $vmServiceUri');
      }

      if (debuggingOptions.debuggingEnabled && vmServiceUri == null) {
        _logger.printError('Failed to connect to the VM Service.');
        return LaunchResult.failed();
      }

      return LaunchResult.succeeded(vmServiceUri: vmServiceUri);
    } on Object catch (e, st) {
      _logger.printError('Failed to launch application on device: $e\n$st');
      return LaunchResult.failed();
    }
  }

  Directory? _findProjectRoot(FileSystemEntity entity) {
    Directory parent = entity is Directory ? entity : entity.parent;
    while (true) {
      if (parent.childFile('pubspec.yaml').existsSync()) {
        return parent;
      }
      final Directory next = parent.parent;
      if (next.path == parent.path) {
        break; // Reached filesystem root
      }
      parent = next;
    }
    return null;
  }

  @override
  Future<bool> stopApp(ApplicationPackage? app, {String? userIdentifier}) async => true;

  @override
  Future<bool> uninstallApp(ApplicationPackage app, {String? userIdentifier}) async => true;

  @override
  Future<bool> isAppInstalled(ApplicationPackage app, {String? userIdentifier}) async => false;
}

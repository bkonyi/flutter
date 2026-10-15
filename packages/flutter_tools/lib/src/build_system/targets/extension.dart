// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools_core/flutter_tools_core.dart' hide BuildMode;

import '../../artifacts.dart';
import '../../base/common.dart';
import '../../base/file_system.dart';
import '../../base/logger.dart';
import '../../build_info.dart';
import '../../experimental/extension_build_manager.dart';
import '../../flutter_plugins.dart';
import '../../platform_plugins.dart';
import '../../plugins.dart';
import '../../project.dart';
import '../build_system.dart';
import '../exceptions.dart';
import 'native_assets.dart';

export '../../build_info.dart'
    show
        kExtensionCCompilerAr,
        kExtensionCCompilerCc,
        kExtensionCCompilerEnvScript,
        kExtensionCCompilerEnvScriptArgs,
        kExtensionCCompilerLd,
        kExtensionTargetArch,
        kExtensionTargetOs;

/// Resolves a build target dependency by its [dependency] name.
typedef DependencyResolverCallback = Target Function(String dependency);

/// A build target that delegates to a tool extension.
class ExtensionAssembleTarget extends Target {
  ExtensionAssembleTarget({
    required this._buildManager,
    required this.buildTarget,
    required this._dependencyResolver,
  });

  /// The extension-defined build target.
  final ExtensionBuildTarget buildTarget;

  final ExtensionBuildManager _buildManager;
  final DependencyResolverCallback _dependencyResolver;

  @override
  String get name => buildTarget.name;

  @override
  late final List<Target> dependencies = buildTarget.dependencies.map(_dependencyResolver).toList();

  @override
  late final List<Source> inputs = buildTarget.inputs.map(_toHostSource).toList();

  @override
  late final List<Source> outputs = buildTarget.outputs.map(_toHostSource).toList();

  @override
  ResolvedFiles resolveInputs(Environment environment) {
    applyExtensionTargetDefines(environment.defines, buildTarget);
    return super.resolveInputs(environment);
  }

  @override
  Future<void> build(Environment environment) async {
    applyExtensionTargetDefines(environment.defines, buildTarget);
    final Environment(
      :Artifacts artifacts,
      :Directory buildDir,
      :Map<String, String> defines,
      :FileSystem fileSystem,
      :Logger logger,
      :Directory outputDir,
      :Directory projectDir,
    ) = environment;
    final String mainPath = defines[kTargetFile] ?? fileSystem.path.join('lib', 'main.dart');
    final String? buildMode = defines[kBuildMode];
    if (buildMode == null) {
      throw MissingDefineException(kBuildMode, name);
    }
    final mode = BuildMode.fromCliName(buildMode);

    final File nativeAssetsFile = buildDir.childFile(InstallCodeAssets.nativeAssetsFilename);
    final Directory flutterAssetsDir = buildDir.childDirectory('flutter_assets');
    if (nativeAssetsFile.existsSync() && flutterAssetsDir.existsSync()) {
      final File manifestDest = flutterAssetsDir.childFile('NativeAssetsManifest.json');
      if (!manifestDest.existsSync()) {
        nativeAssetsFile.copySync(manifestDest.path);
      }
    }

    final Map<String, String> resolvedArtifacts = resolveExtensionTargetArtifacts(
      artifacts: artifacts,
      buildMode: mode,
      target: buildTarget,
    );
    final List<ExtensionPlugin> plugins = await resolveExtensionTargetPlugins(
      fileSystem: fileSystem,
      logger: logger,
      projectDir: projectDir,
      target: buildTarget,
    );

    final ExtensionBuildResult result = await _buildManager.build(
      buildDir: buildDir.uri,
      buildMode: mode,
      mainPath: mainPath,
      outputDir: outputDir.uri,
      plugins: plugins,
      projectRoot: projectDir.uri,
      resolvedArtifacts: resolvedArtifacts,
      targetName: buildTarget.name,
    );

    if (!result.success) {
      final String? errorMessage = result.errorMessage;
      throwToolExit(
        errorMessage != null && errorMessage.isNotEmpty
            ? 'Extension build target "${buildTarget.name}" failed: $errorMessage'
            : 'Extension build target "${buildTarget.name}" failed.',
      );
    }
  }
}

/// Populates [defines] with target platform and Dart hooks (`native_assets`)
/// configuration declared on [target] when not already set in [defines].
void applyExtensionTargetDefines(Map<String, String> defines, ExtensionBuildTarget target) {
  if (target.targetPlatform.isNotEmpty) {
    defines.putIfAbsent(kTargetPlatform, () => target.targetPlatform);
  }
  if (target.nativeAssetsConfig case final ExtensionNativeAssetsConfig config) {
    defines.putIfAbsent(kExtensionTargetOs, () => config.targetOs);
    defines.putIfAbsent(kExtensionTargetArch, () => config.targetArchitecture);
    if (config.cc case final String cc) {
      defines.putIfAbsent(kExtensionCCompilerCc, () => cc);
    }
    if (config.ar case final String ar) {
      defines.putIfAbsent(kExtensionCCompilerAr, () => ar);
    }
    if (config.ld case final String ld) {
      defines.putIfAbsent(kExtensionCCompilerLd, () => ld);
    }
    if (config.envScript case final String envScript) {
      defines.putIfAbsent(kExtensionCCompilerEnvScript, () => envScript);
    }
    if (config.envScriptArgs case final List<String> envScriptArgs when envScriptArgs.isNotEmpty) {
      defines.putIfAbsent(kExtensionCCompilerEnvScriptArgs, () => envScriptArgs.join(' '));
    }
  }
}

/// Resolves the Flutter plugins declared in the project at [projectDir] for
/// [target]'s platform (`target.pluginPlatformKey ?? target.targetPlatform`).
Future<List<ExtensionPlugin>> resolveExtensionTargetPlugins({
  required FileSystem fileSystem,
  required Logger logger,
  required Directory projectDir,
  required ExtensionBuildTarget target,
}) async {
  final String platformKey = target.pluginPlatformKey ?? target.targetPlatform;
  if (platformKey.isEmpty) {
    return const <ExtensionPlugin>[];
  }
  final File pubspecFile = projectDir.childFile('pubspec.yaml');
  final File packageConfigFile = projectDir
      .childDirectory('.dart_tool')
      .childFile('package_config.json');
  if (!pubspecFile.existsSync() || !packageConfigFile.existsSync()) {
    return const <ExtensionPlugin>[];
  }
  try {
    final FlutterProject project = FlutterProjectFactory(
      fileSystem: fileSystem,
      logger: logger,
    ).fromDirectory(projectDir);
    final List<Plugin> allPlugins = await findPlugins(project, logger: logger, throwOnError: false);
    final List<Plugin> resolved = resolvePluginImplementationsForPlatform(
      allPlugins,
      platformKey,
      quiet: true,
    );
    return <ExtensionPlugin>[
      for (final Plugin plugin in resolved)
        ExtensionPlugin(
          name: plugin.name,
          path: plugin.path,
          configuration: _pluginConfigurationForPlatform(plugin, platformKey),
        ),
    ];
  } on Exception catch (e) {
    logger.printTrace('Failed to resolve plugins for extension target "${target.name}": $e');
    return const <ExtensionPlugin>[];
  }
}

Map<String, Object?> _pluginConfigurationForPlatform(Plugin plugin, String platformKey) {
  final PluginPlatform? platformPlugin = plugin.platforms[platformKey];
  final config = <String, Object?>{};
  if (platformPlugin is CustomPlatformPlugin) {
    config.addAll(platformPlugin.configuration);
  } else if (platformPlugin != null) {
    final Map<String, Object?> rawMap = platformPlugin.toMap();
    config.addAll(rawMap);
    if (rawMap['class'] case final String pluginClass when !config.containsKey(kPluginClass)) {
      config[kPluginClass] = pluginClass;
    }
  }
  if (plugin.pluginDartClassPlatforms[platformKey] case (
    :final String dartClass,
    :final String dartFileName,
  )) {
    config.putIfAbsent(kDartPluginClass, () => dartClass);
    config.putIfAbsent(kDartFileName, () => dartFileName);
  }
  if (plugin.defaultPackagePlatforms[platformKey] case final String defaultPackage) {
    config.putIfAbsent(kDefaultPackage, () => defaultPackage);
  }
  return config;
}

/// Resolves the output directory for [target] by substituting placeholders
/// (`{PROJECT_DIR}`, `{BUILD_DIR}`, `{BUILD_MODE}`, and `{TARGET_PLATFORM}`).
///
/// Relative paths are resolved relative to [projectDir].
Directory resolveExtensionOutputDir({
  required Directory buildDir,
  required BuildMode buildMode,
  required FileSystem fileSystem,
  required Directory projectDir,
  required ExtensionBuildTarget target,
}) {
  String outputPath = target.outputDir
      .replaceAll(BuiltInPlaceholders.projectDir, projectDir.path)
      .replaceAll(BuiltInPlaceholders.buildDir, buildDir.path)
      .replaceAll(BuiltInPlaceholders.buildMode, buildMode.cliName)
      .replaceAll(BuiltInPlaceholders.targetPlatform, target.targetPlatform);
  if (fileSystem.path.isRelative(outputPath)) {
    outputPath = fileSystem.path.join(projectDir.path, outputPath);
  }
  return fileSystem.directory(fileSystem.path.normalize(outputPath));
}

/// Resolves all engine and host artifact inputs declared on [target] using
/// [artifacts] and [buildMode].
///
/// Throws a [ToolExit] if any artifact platform name or requested artifact
/// name is invalid or unsupported.
Map<String, String> resolveExtensionTargetArtifacts({
  required Artifacts artifacts,
  required BuildMode buildMode,
  required ExtensionBuildTarget target,
}) {
  TargetPlatform? targetPlatform;
  if (target.targetPlatform.isNotEmpty) {
    try {
      targetPlatform = TargetPlatform.fromName(target.targetPlatform);
    } on Exception {
      // Custom extension target platforms do not map to a built-in TargetPlatform.
    }
  }
  final resolvedArtifacts = <String, String>{};
  for (final ExtensionSource input in target.inputs) {
    switch (input) {
      case ExtensionPatternSource():
        continue;
      case ExtensionArtifactSource(
        :final ExtensionArtifact artifact,
        :final String? platform,
        :final BuildMode? mode,
      ):
        final Artifact hostArtifact = _resolveArtifact(artifact);
        final TargetPlatform? resolvedPlatform = _resolveArtifactPlatform(platform, artifact);
        resolvedArtifacts[artifact.name] = artifacts.getArtifactPath(
          hostArtifact,
          platform: resolvedPlatform ?? targetPlatform,
          mode: mode ?? buildMode,
        );
      case ExtensionHostArtifactSource(:final ExtensionHostArtifact artifact):
        final HostArtifact hostArtifact = _resolveHostArtifact(artifact);
        resolvedArtifacts[artifact.name] = artifacts.getHostArtifact(hostArtifact).path;
    }
  }
  return resolvedArtifacts;
}

Source _toHostSource(ExtensionSource source) => switch (source) {
  ExtensionPatternSource(:final String value, :final bool optional) => Source.pattern(
    value,
    optional: optional,
  ),
  ExtensionArtifactSource(
    :final ExtensionArtifact artifact,
    :final String? platform,
    :final BuildMode? mode,
  ) =>
    Source.artifact(
      _resolveArtifact(artifact),
      platform: _resolveArtifactPlatform(platform, artifact),
      mode: mode,
    ),
  ExtensionHostArtifactSource(:final ExtensionHostArtifact artifact) => Source.hostArtifact(
    _resolveHostArtifact(artifact),
  ),
};

Artifact _resolveArtifact(ExtensionArtifact artifact) => switch (artifact.name) {
  'flutterPatchedSdkPath' => Artifact.flutterPatchedSdkPath,
  'genSnapshot' => Artifact.genSnapshot,
  'icuData' => Artifact.icuData,
  'linuxDesktopPath' => Artifact.linuxDesktopPath,
  'linuxHeaders' => Artifact.linuxHeaders,
  final String name => throwToolExit('Unsupported artifact "$name" requested by a tool extension.'),
};

TargetPlatform? _resolveArtifactPlatform(String? platformName, ExtensionArtifact artifact) {
  if (platformName == null) {
    return null;
  }
  try {
    return TargetPlatform.fromName(platformName);
  } on Exception {
    throwToolExit('Invalid platform name "$platformName" for artifact "${artifact.name}".');
  }
}

HostArtifact _resolveHostArtifact(ExtensionHostArtifact artifact) => switch (artifact.name) {
  'impellerc' => HostArtifact.impellerc,
  'libtessellator' => HostArtifact.libtessellator,
  final String name => throwToolExit(
    'Unsupported host artifact "$name" requested by a tool extension.',
  ),
};

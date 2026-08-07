// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools_core/flutter_tools_core.dart' show BuildMode, ExtensionBuildResult, ExtensionBuildTarget, Source;
import 'package:flutter_tools_core/flutter_tools_core.dart' as core;

import '../../artifacts.dart';
import '../../base/common.dart';
import '../../build_info.dart';
import '../../experimental/extension_build_manager.dart';
import '../build_system.dart';

/// A build target that delegates to a tool extension.
class ExtensionAssembleTarget extends Target {
  /// Creates an [ExtensionAssembleTarget] that wraps [buildTarget].
  ExtensionAssembleTarget({
    required ExtensionBuildManager buildManager,
    required this.buildTarget,
    required Target Function(String) dependencyResolver,
  }) : _buildManager = buildManager,
       _dependencyResolver = dependencyResolver;

  /// The extension-defined build target.
  final ExtensionBuildTarget buildTarget;

  final ExtensionBuildManager _buildManager;
  final Target Function(String) _dependencyResolver;

  @override
  String get name => buildTarget.name;

  @override
  List<Target> get dependencies => buildTarget.dependencies.map(_dependencyResolver).toList();

  @override
  List<Source> get inputs => buildTarget.inputs;

  @override
  List<Source> get outputs => buildTarget.outputs;

  @override
  String get outputDir => buildTarget.outputDir;

  @override
  Future<void> build(Environment environment) async {
    final Environment resolvedEnvironment = getResolvedEnvironment(environment);
    final String projectRoot = resolvedEnvironment.projectDir.path;
    final String mainPath =
        resolvedEnvironment.defines[kTargetFile] ??
        resolvedEnvironment.fileSystem.path.join('lib', 'main.dart');
    final String? buildMode = resolvedEnvironment.defines[kBuildMode];

    if (buildMode == null) {
      throwToolExit('BuildMode define is required for extension build target ${buildTarget.name}');
    }
    final mode = BuildMode.fromCliName(buildMode);

    final resolver = ArtifactResolver(
      artifacts: environment.artifacts,
      targetPlatform: TargetPlatform.fromName(buildTarget.targetPlatform),
      buildMode: mode,
    );
    for (final Source input in buildTarget.inputs) {
      input.accept(resolver);
    }

    final ExtensionBuildResult result = await _buildManager.build(
      targetName: buildTarget.name,
      projectRoot: projectRoot,
      mainPath: mainPath,
      buildMode: buildMode,
      outputDir: resolvedEnvironment.outputDir.path,
      buildDir: resolvedEnvironment.buildDir.path,
      resolvedArtifacts: resolver.resolvedArtifacts,
    );

    if (!result.success) {
      throwToolExit(result.errorMessage ?? 'Extension build target ${buildTarget.name} failed.');
    }
  }
}

class ArtifactResolver implements core.SourceVisitor {
  ArtifactResolver({
    required this.artifacts,
    required this.targetPlatform,
    required this.buildMode,
  });

  final Artifacts artifacts;
  final TargetPlatform targetPlatform;
  final BuildMode buildMode;

  final Map<String, String> resolvedArtifacts = <String, String>{};

  @override
  void visitPattern(String pattern, bool optional) {}

  @override
  void visitArtifact(core.Artifact artifact, String? platformName, BuildMode? mode) {
    final Artifact hostArtifact = Artifact.values.firstWhere((e) => e.name == artifact.name);
    final TargetPlatform? platform = platformName != null
        ? TargetPlatform.fromName(platformName)
        : null;

    final String path = artifacts.getArtifactPath(
      hostArtifact,
      platform: platform ?? targetPlatform,
      mode: mode ?? buildMode,
    );
    resolvedArtifacts[artifact.name] = path;
  }

  @override
  void visitHostArtifact(core.HostArtifact artifact) {
    final HostArtifact hostArtifact = HostArtifact.values.firstWhere(
      (e) => e.name == artifact.name,
    );
    final String path = artifacts.getHostArtifact(hostArtifact).path;
    resolvedArtifacts[artifact.name] = path;
  }
}

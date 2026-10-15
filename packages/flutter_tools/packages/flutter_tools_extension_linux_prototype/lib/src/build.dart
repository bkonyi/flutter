// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';
import 'package:meta/meta.dart';

/// Platform-specific [ExtensionArtifact] constants contributed by the Linux extension.
abstract final class LinuxArtifacts {
  /// The directory containing the C++ header files (`flutter_linux`) for the
  /// Flutter Linux embedding, needed to compile the native runner.
  static const ExtensionArtifact linuxHeaders = ExtensionArtifact('linuxHeaders');

  /// The directory containing ephemeral Linux desktop engine libraries (e.g.
  /// `libflutter_linux_gtk.so`) and assets needed to build and run Linux applications.
  static const ExtensionArtifact linuxDesktopPath = ExtensionArtifact('linuxDesktopPath');
}

const String _kLinuxX64Platform = 'linux-x64';
const String _kLinuxPlatformKey = 'linux';
const String _kFlutterAssets = 'flutter_assets';
const String _kLibFlutterLinuxGtk = 'libflutter_linux_gtk.so';
const String _kIcuData = 'icudtl.dat';
const String _kKernelBlob = 'kernel_blob.bin';
const String _kAppDill = 'app.dill';
const String _kGeneratedConfigCmake = 'generated_config.cmake';

/// Top-level Linux build target contributed by the prototype extension.
class CustomLinuxBuildTarget extends ExtensionTarget {
  const CustomLinuxBuildTarget()
    : super(
        description: 'A custom Linux build target from prototype extension.',
        targetPlatform: _kLinuxX64Platform,
        outputDir:
            '${BuiltInPlaceholders.projectDir}/build/linux_extension/x64/${BuiltInPlaceholders.buildMode}',
        pluginPlatformKey: _kLinuxPlatformKey,
      );

  @override
  String get name => LinuxBuildService.customLinuxBuildTargetName;

  @override
  List<ExtensionSource> get inputs => const <ExtensionSource>[
    ExtensionSource.pattern('${BuiltInPlaceholders.projectDir}/pubspec.yaml'),
    ExtensionSource.pattern('${BuiltInPlaceholders.projectDir}/linux/CMakeLists.txt'),
    ExtensionSource.pattern('${BuiltInPlaceholders.projectDir}/lib/main.dart'),
    ExtensionSource.artifact(LinuxArtifacts.linuxHeaders),
    ExtensionSource.artifact(LinuxArtifacts.linuxDesktopPath),
    ExtensionSource.artifact(BuiltInArtifacts.icuData),
  ];

  @override
  List<ExtensionSource> get outputs => const <ExtensionSource>[
    ExtensionSource.pattern('${BuiltInPlaceholders.outputDir}/bundle/*'),
  ];

  @override
  Future<ExtensionBuildResult> build(ExtensionBuildContext context) async {
    final projectDir = Directory.fromUri(context.projectRoot);
    final outputDir = Directory.fromUri(context.outputDir);
    final cmakeFile = File('${projectDir.path}/linux/CMakeLists.txt');
    if (!cmakeFile.existsSync()) {
      return ExtensionBuildResult(
        success: false,
        errorMessage: 'Missing linux/CMakeLists.txt in ${projectDir.path}.',
      );
    }

    final String? flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot == null || flutterRoot.isEmpty) {
      return const ExtensionBuildResult(
        success: false,
        errorMessage: 'FLUTTER_ROOT environment variable is not set.',
      );
    }

    final String? unpackError = _unpackArtifacts(
      projectRoot: projectDir.path,
      resolvedArtifacts: context.resolvedArtifacts,
    );
    if (unpackError != null) {
      return ExtensionBuildResult(success: false, errorMessage: unpackError);
    }

    final ephemeralDir = Directory('${projectDir.path}/linux/flutter/ephemeral');
    if (!ephemeralDir.existsSync()) {
      ephemeralDir.createSync(recursive: true);
    }
    final generatedConfigFile = File('${ephemeralDir.path}/$_kGeneratedConfigCmake');
    await generatedConfigFile.writeAsString('''
# Generated code do not commit.
file(TO_CMAKE_PATH "$flutterRoot" FLUTTER_ROOT)
file(TO_CMAKE_PATH "${projectDir.path}" PROJECT_DIR)

set(FLUTTER_VERSION "1.0.0" PARENT_SCOPE)
set(FLUTTER_VERSION_MAJOR 1 PARENT_SCOPE)
set(FLUTTER_VERSION_MINOR 0 PARENT_SCOPE)
set(FLUTTER_VERSION_PATCH 0 PARENT_SCOPE)
set(FLUTTER_VERSION_BUILD 0 PARENT_SCOPE)

# Environment variables to pass to tool_backend.sh
list(APPEND FLUTTER_TOOL_ENVIRONMENT
  "FLUTTER_ROOT=$flutterRoot"
  "PROJECT_DIR=${projectDir.path}"
  "FLUTTER_TARGET=${context.mainPath}"
  "BUILD_MODE=${context.buildMode.cliName}"
)
''');

    await writeLinuxPluginFiles(projectDir, ephemeralDir, context.plugins);

    if (!outputDir.existsSync()) {
      outputDir.createSync(recursive: true);
    }

    // TODO(bkonyi): Route extension build output through the host logger.
    stdout.writeln('Running cmake...');
    final int cmakeExitCode = await _runProcess(
      'cmake',
      <String>[
        '-G',
        'Ninja',
        '-DCMAKE_BUILD_TYPE=${context.buildMode.uppercaseName}',
        '-DFLUTTER_TARGET_PLATFORM=$_kLinuxX64Platform',
        '${projectDir.path}/linux',
      ],
      workingDirectory: outputDir.path,
      environment: const <String, String>{'CC': 'clang', 'CXX': 'clang++'},
    );
    if (cmakeExitCode != 0) {
      return ExtensionBuildResult(
        success: false,
        errorMessage: 'cmake failed with exit code $cmakeExitCode.',
      );
    }

    // TODO(bkonyi): Route extension build output through the host logger.
    stdout.writeln('Running ninja...');
    final int ninjaExitCode = await _runProcess('ninja', <String>['-C', outputDir.path, 'install']);
    if (ninjaExitCode != 0) {
      return ExtensionBuildResult(
        success: false,
        errorMessage: 'ninja failed with exit code $ninjaExitCode.',
      );
    }

    return const ExtensionBuildResult(success: true);
  }
}

/// Assemble-only Linux debug bundle target contributed by the prototype extension.
class CustomLinuxAssembleOnlyDebug extends ExtensionTarget {
  const CustomLinuxAssembleOnlyDebug()
    : super(
        description: 'A custom Linux assemble-only debug target.',
        targetPlatform: _kLinuxX64Platform,
        isTopLevel: false,
        pluginPlatformKey: _kLinuxPlatformKey,
      );

  @override
  String get name => 'custom-linux-assemble-only-debug';

  @override
  List<String> get dependencies => const <String>[
    BuiltInTargets.copyAssets,
    BuiltInTargets.kernelSnapshot,
    BuiltInTargets.installCodeAssets,
  ];

  @override
  List<ExtensionSource> get inputs => const <ExtensionSource>[
    ExtensionSource.pattern('${BuiltInPlaceholders.buildDir}/$_kAppDill'),
    ExtensionSource.artifact(LinuxArtifacts.linuxHeaders),
    ExtensionSource.artifact(LinuxArtifacts.linuxDesktopPath),
    ExtensionSource.artifact(BuiltInArtifacts.icuData),
    ExtensionSource.pattern('${BuiltInPlaceholders.projectDir}/pubspec.yaml'),
  ];

  @override
  List<ExtensionSource> get outputs => const <ExtensionSource>[
    ExtensionSource.pattern(
      '${BuiltInPlaceholders.outputDir}/bundle/data/$_kFlutterAssets/$_kKernelBlob',
    ),
    ExtensionSource.pattern('${BuiltInPlaceholders.outputDir}/bundle/lib/$_kLibFlutterLinuxGtk'),
    ExtensionSource.pattern('${BuiltInPlaceholders.outputDir}/bundle/data/$_kIcuData'),
  ];

  @override
  Future<ExtensionBuildResult> build(ExtensionBuildContext context) async {
    final outputDir = Directory.fromUri(context.outputDir);
    final buildDir = Directory.fromUri(context.buildDir);

    // 1. Copy assets from buildDir if present
    final srcAssets = Directory('${buildDir.path}/$_kFlutterAssets');
    final destAssets = Directory('${outputDir.path}/bundle/data/$_kFlutterAssets');
    if (srcAssets.existsSync()) {
      _copyDirectory(srcAssets, destAssets);
    }

    // 2. Copy libflutter_linux_gtk.so
    final String? desktopPath = context.resolvedArtifacts[LinuxArtifacts.linuxDesktopPath.name];
    if (desktopPath == null) {
      return const ExtensionBuildResult(
        success: false,
        errorMessage: 'Missing linuxDesktopPath artifact.',
      );
    }
    final srcLib = File('$desktopPath/$_kLibFlutterLinuxGtk');
    if (!srcLib.existsSync()) {
      return ExtensionBuildResult(
        success: false,
        errorMessage: 'Missing $_kLibFlutterLinuxGtk at ${srcLib.path}.',
      );
    }
    _copyFile(srcLib, File('${outputDir.path}/bundle/lib/$_kLibFlutterLinuxGtk'));

    // 3. Copy icudtl.dat
    final String? icuDataPath = context.resolvedArtifacts[BuiltInArtifacts.icuData.name];
    if (icuDataPath == null) {
      return const ExtensionBuildResult(success: false, errorMessage: 'Missing icuData artifact.');
    }
    final srcIcu = File(icuDataPath);
    if (!srcIcu.existsSync()) {
      return ExtensionBuildResult(
        success: false,
        errorMessage: 'Missing $_kIcuData at ${srcIcu.path}.',
      );
    }
    _copyFile(srcIcu, File('${outputDir.path}/bundle/data/$_kIcuData'));

    // 4. Copy application binary
    final srcApp = File('${buildDir.path}/$_kAppDill');
    if (!srcApp.existsSync()) {
      return ExtensionBuildResult(
        success: false,
        errorMessage: 'Missing $_kAppDill at ${srcApp.path}.',
      );
    }
    _copyFile(srcApp, File('${outputDir.path}/bundle/data/$_kFlutterAssets/$_kKernelBlob'));

    return const ExtensionBuildResult(success: true);
  }
}

/// Prototype Linux [BuildService] implementation.
final class LinuxBuildService extends BuildService {
  /// Target name for the prototype Linux build target.
  static const String customLinuxBuildTargetName = 'custom-linux-build';

  @override
  List<ExtensionTarget> get targets => const <ExtensionTarget>[
    CustomLinuxBuildTarget(),
    CustomLinuxAssembleOnlyDebug(),
  ];
}

Future<int> _runProcess(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
  String? workingDirectory,
}) async {
  final Process process = await Process.start(
    executable,
    arguments,
    environment: environment,
    workingDirectory: workingDirectory,
  );
  final (int exitCode, _, _) = await (
    process.exitCode,
    process.stdout.listen(stdout.add).asFuture<void>(),
    process.stderr.listen(stderr.add).asFuture<void>(),
  ).wait;
  return exitCode;
}

void _copyDirectory(Directory source, Directory destination) {
  if (!destination.existsSync()) {
    destination.createSync(recursive: true);
  }
  for (final FileSystemEntity entity in source.listSync()) {
    final String name = entity.uri.pathSegments.lastWhere((String e) => e.isNotEmpty);
    if (entity is Directory) {
      _copyDirectory(entity, Directory('${destination.path}/$name'));
    } else if (entity is File) {
      entity.copySync('${destination.path}/$name');
    }
  }
}

void _copyFile(File source, File destination) {
  if (!destination.parent.existsSync()) {
    destination.parent.createSync(recursive: true);
  }
  source.copySync(destination.path);
}

String? _unpackArtifacts({
  required String projectRoot,
  required Map<String, String> resolvedArtifacts,
}) {
  final ephemeralDir = Directory('$projectRoot/linux/flutter/ephemeral');
  if (!ephemeralDir.existsSync()) {
    ephemeralDir.createSync(recursive: true);
  }

  // 1. Unpack linuxDesktopPath (copy libflutter_linux_gtk.so)
  final String? desktopPath = resolvedArtifacts[LinuxArtifacts.linuxDesktopPath.name];
  if (desktopPath == null) {
    return 'Missing ${LinuxArtifacts.linuxDesktopPath.name} artifact.';
  }
  final srcLib = File('$desktopPath/$_kLibFlutterLinuxGtk');
  if (!srcLib.existsSync()) {
    return 'Missing $_kLibFlutterLinuxGtk at ${srcLib.path}.';
  }
  _copyFile(srcLib, File('${ephemeralDir.path}/$_kLibFlutterLinuxGtk'));

  // 2. Unpack linuxHeaders (copy flutter_linux directory contents)
  final String? headersPath = resolvedArtifacts[LinuxArtifacts.linuxHeaders.name];
  if (headersPath == null) {
    return 'Missing ${LinuxArtifacts.linuxHeaders.name} artifact.';
  }
  final srcHeadersDir = Directory(headersPath);
  if (srcHeadersDir.existsSync()) {
    _copyDirectory(srcHeadersDir, Directory('${ephemeralDir.path}/flutter_linux'));
  }

  // 3. Unpack icuData (copy icudtl.dat)
  final String? icuDataPath = resolvedArtifacts[BuiltInArtifacts.icuData.name];
  if (icuDataPath == null) {
    return 'Missing ${BuiltInArtifacts.icuData.name} artifact.';
  }
  final srcIcu = File(icuDataPath);
  if (!srcIcu.existsSync()) {
    return 'Missing $_kIcuData at ${srcIcu.path}.';
  }
  _copyFile(srcIcu, File('${ephemeralDir.path}/$_kIcuData'));
  return null;
}

@visibleForTesting
Future<void> writeLinuxPluginFiles(
  Directory projectDir,
  Directory ephemeralDir,
  List<ExtensionPlugin> plugins,
) async {
  final symlinksDir = Directory('${ephemeralDir.path}/.plugin_symlinks');
  if (symlinksDir.existsSync()) {
    symlinksDir.deleteSync(recursive: true);
  }
  symlinksDir.createSync(recursive: true);

  final nativePlugins = <ExtensionPlugin>[];
  final ffiPlugins = <ExtensionPlugin>[];

  for (final plugin in plugins) {
    Link('${symlinksDir.path}/${plugin.name}').createSync(plugin.path);
    final Object? pluginClass = plugin.configuration['pluginClass'];
    final Object? ffiPlugin = plugin.configuration['ffiPlugin'];
    if (pluginClass is String && pluginClass.isNotEmpty && pluginClass != 'none') {
      nativePlugins.add(plugin);
    } else if (ffiPlugin == true) {
      ffiPlugins.add(plugin);
    }
  }

  final String pluginEntries = <String>[
    for (final ExtensionPlugin plugin in nativePlugins) '  ${plugin.name}',
  ].join('\n');
  final String ffiPluginEntries = <String>[
    for (final ExtensionPlugin plugin in ffiPlugins) '  ${plugin.name}',
  ].join('\n');

  final cmakeFile = File('${projectDir.path}/linux/flutter/generated_plugins.cmake');
  await cmakeFile.parent.create(recursive: true);
  await cmakeFile.writeAsString('''
#
# Generated file, do not edit.
#

list(APPEND FLUTTER_PLUGIN_LIST
$pluginEntries
)

list(APPEND FLUTTER_FFI_PLUGIN_LIST
$ffiPluginEntries
)

set(PLUGIN_BUNDLED_LIBRARIES)

foreach(plugin \${FLUTTER_PLUGIN_LIST})
  add_subdirectory(flutter/ephemeral/.plugin_symlinks/\${plugin}/linux plugins/\${plugin})
  target_link_libraries(\${BINARY_NAME} PRIVATE \${plugin}_plugin)
  list(APPEND PLUGIN_BUNDLED_LIBRARIES \$<TARGET_FILE:\${plugin}_plugin>)
  list(APPEND PLUGIN_BUNDLED_LIBRARIES \${\${plugin}_bundled_libraries})
endforeach(plugin)

foreach(ffi_plugin \${FLUTTER_FFI_PLUGIN_LIST})
  add_subdirectory(flutter/ephemeral/.plugin_symlinks/\${ffi_plugin}/linux plugins/\${ffi_plugin})
  list(APPEND PLUGIN_BUNDLED_LIBRARIES \${\${ffi_plugin}_bundled_libraries})
endforeach(ffi_plugin)
''');

  final registrantHeader = File('${projectDir.path}/linux/flutter/generated_plugin_registrant.h');
  await registrantHeader.writeAsString('''
//
//  Generated file. Do not edit.
//

// clang-format off

#ifndef GENERATED_PLUGIN_REGISTRANT_
#define GENERATED_PLUGIN_REGISTRANT_

#include <flutter_linux/flutter_linux.h>

// Registers Flutter plugins.
void fl_register_plugins(FlPluginRegistry* registry);

#endif  // GENERATED_PLUGIN_REGISTRANT_
''');

  final String includes = <String>[
    for (final ExtensionPlugin plugin in nativePlugins)
      '#include <${plugin.name}/${plugin.name}_plugin.h>',
  ].join('\n');
  final String registrations = <String>[
    for (final ExtensionPlugin plugin in nativePlugins)
      '''
  g_autoptr(FlPluginRegistrar) ${plugin.name}_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "${plugin.configuration['pluginClass']}");
  ${plugin.name}_plugin_register_with_registrar(${plugin.name}_registrar);''',
  ].join('\n');

  final registrantCc = File('${projectDir.path}/linux/flutter/generated_plugin_registrant.cc');
  await registrantCc.writeAsString('''
//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

$includes

void fl_register_plugins(FlPluginRegistry* registry) {
$registrations
}
''');
}

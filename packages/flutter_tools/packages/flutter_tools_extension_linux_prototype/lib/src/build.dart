// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

// Requirement 1: Removed manual downloads and archive import
import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';

/// Platform-specific [Artifact] constants contributed by the Linux extension.
class LinuxArtifacts {
  /// The directory containing the C++ header files (`flutter_linux`) for the
  /// Flutter Linux embedding, needed to compile the native runner.
  static const Artifact linuxHeaders = Artifact('linuxHeaders');

  /// The directory containing ephemeral Linux desktop engine libraries (e.g.
  /// `libflutter_linux_gtk.so`) and assets needed to build and run Linux applications.
  static const Artifact linuxDesktopPath = Artifact('linuxDesktopPath');
}

const String _kLinuxX64Platform = 'linux-x64';
const String _kFlutterAssets = 'flutter_assets';
const String _kLibFlutterLinuxGtk = 'libflutter_linux_gtk.so';
const String _kIcuData = 'icudtl.dat';
const String _kAppSo = 'app.so';
const String _kLibAppSo = 'libapp.so';
const String _kKernelBlob = 'kernel_blob.bin';
const String _kAppDill = 'app.dill';
const String _kGeneratedConfigCmake = 'generated_config.cmake';

class CustomLinuxBuildTarget extends ExtensionTarget {
  const CustomLinuxBuildTarget()
    : super(
        targetPlatform: _kLinuxX64Platform,
        description: 'A custom Linux build target from prototype extension.',
        outputDir: '$kProjectDirPlaceholder/build/linux_extension/x64/$kBuildModePlaceholder',
      );

  @override
  String get name => 'custom-linux-build';

  @override
  List<Source> get inputs => const <Source>[
    Source.pattern('$kProjectDirPlaceholder/pubspec.yaml'),
    Source.pattern('$kProjectDirPlaceholder/linux/CMakeLists.txt'),
    Source.pattern('$kProjectDirPlaceholder/lib/main.dart'),
    Source.artifact(LinuxArtifacts.linuxHeaders),
    Source.artifact(LinuxArtifacts.linuxDesktopPath),
    Source.artifact(BuiltInArtifacts.icuData),
  ];

  @override
  List<Source> get outputs => const <Source>[Source.pattern('$kOutputDirPlaceholder/bundle/*')];

  @override
  List<Target> get dependencies => const <Target>[];

  @override
  Future<Map<String, Object?>> build(ExtensionBuildContext context) async {
    final String? flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot == null || flutterRoot.isEmpty) {
      throw Exception('FLUTTER_ROOT environment variable is not set.');
    }

    final projectDir = Directory(context.projectRoot);
    final cmakeFile = File('${projectDir.path}/linux/CMakeLists.txt');
    if (!cmakeFile.existsSync()) {
      return <String, Object?>{
        'executablePath': '${context.outputDir}/bundle/custom_linux_app',
      };
    }

    _unpackArtifacts(
      projectRoot: context.projectRoot,
      resolvedArtifacts: context.resolvedArtifacts,
    );

    final ephemeralDir = Directory('${projectDir.path}/linux/flutter/ephemeral');

    // 1. Write generated_config.cmake
    try {
      if (!ephemeralDir.existsSync()) {
        ephemeralDir.createSync(recursive: true);
      }
      final generatedConfigFile = File('${ephemeralDir.path}/$_kGeneratedConfigCmake');

      final String escapedFlutterRoot = flutterRoot;
      final String escapedProjectDir = context.projectRoot;

      final buffer = StringBuffer('''
# Generated code do not commit.
file(TO_CMAKE_PATH "$escapedFlutterRoot" FLUTTER_ROOT)
file(TO_CMAKE_PATH "$escapedProjectDir" PROJECT_DIR)

set(FLUTTER_VERSION "1.0.0" PARENT_SCOPE)
set(FLUTTER_VERSION_MAJOR 1 PARENT_SCOPE)
set(FLUTTER_VERSION_MINOR 0 PARENT_SCOPE)
set(FLUTTER_VERSION_PATCH 0 PARENT_SCOPE)
set(FLUTTER_VERSION_BUILD 0 PARENT_SCOPE)

# Environment variables to pass to tool_backend.sh
list(APPEND FLUTTER_TOOL_ENVIRONMENT
  "FLUTTER_ROOT=$escapedFlutterRoot"
  "PROJECT_DIR=$escapedProjectDir"
  "FLUTTER_TARGET=${context.mainPath}"
  "BUILD_MODE=${context.buildMode}"
)
''');
      await generatedConfigFile.writeAsString(buffer.toString());
    } on Exception catch (e) {
      throw Exception('Failed to write $_kGeneratedConfigCmake: $e');
    }

    // Create plugin symlinks
    final symlinkDirectory = Directory('${ephemeralDir.path}/.plugin_symlinks');
    if (symlinkDirectory.existsSync()) {
      symlinkDirectory.deleteSync(recursive: true);
    }
    symlinkDirectory.createSync(recursive: true);





    final methodChannelPlugins = <Map<String, Object?>>[];
    final ffiPlugins = <Map<String, Object?>>[];



    final generatedPluginsFile = File('${ephemeralDir.path}/generated_plugins.cmake');
    final generatedPluginHeader = File('${ephemeralDir.path}/generated_plugin_registrant.h');
    final generatedPluginSource = File('${ephemeralDir.path}/generated_plugin_registrant.cc');

    // Write generated_plugins.cmake
    final cmakeContent = StringBuffer();
    cmakeContent.writeln('# Generated file, do not edit.');
    cmakeContent.writeln();
    cmakeContent.writeln('list(APPEND FLUTTER_PLUGIN_LIST');
    for (final plugin in methodChannelPlugins) {
      cmakeContent.writeln('  ${plugin["name"]}');
    }
    cmakeContent.writeln(')');
    cmakeContent.writeln();
    cmakeContent.writeln('list(APPEND FLUTTER_FFI_PLUGIN_LIST');
    for (final plugin in ffiPlugins) {
      cmakeContent.writeln('  ${plugin["name"]}');
    }
    cmakeContent.writeln(')');
    cmakeContent.writeln();
    cmakeContent.writeln('set(PLUGIN_BUNDLED_LIBRARIES)');
    cmakeContent.writeln();
    cmakeContent.writeln(r'foreach(plugin ${FLUTTER_PLUGIN_LIST})');
    cmakeContent.writeln(
      r'  add_subdirectory(flutter/ephemeral/.plugin_symlinks/${plugin}/linux plugins/${plugin})',
    );
    cmakeContent.writeln(r'  target_link_libraries(${BINARY_NAME} PRIVATE ${plugin}_plugin)');
    cmakeContent.writeln(
      r'  list(APPEND PLUGIN_BUNDLED_LIBRARIES $<TARGET_FILE:${plugin}_plugin>)',
    );
    cmakeContent.writeln(r'  list(APPEND PLUGIN_BUNDLED_LIBRARIES ${${plugin}_bundled_libraries})');
    cmakeContent.writeln('endforeach(plugin)');
    cmakeContent.writeln();
    cmakeContent.writeln(r'foreach(ffi_plugin ${FLUTTER_FFI_PLUGIN_LIST})');
    cmakeContent.writeln(
      r'  add_subdirectory(flutter/ephemeral/.plugin_symlinks/${ffi_plugin}/linux plugins/${ffi_plugin})',
    );
    cmakeContent.writeln(
      r'  list(APPEND PLUGIN_BUNDLED_LIBRARIES ${${ffi_plugin}_bundled_libraries})',
    );
    cmakeContent.writeln('endforeach(ffi_plugin)');

    generatedPluginsFile.writeAsStringSync(cmakeContent.toString());

    // Write generated_plugin_registrant.h
    final headerContent = StringBuffer();
    headerContent.writeln('// Generated file. Do not edit.');
    headerContent.writeln('#ifndef GENERATED_PLUGIN_REGISTRANT_');
    headerContent.writeln('#define GENERATED_PLUGIN_REGISTRANT_');
    headerContent.writeln();
    headerContent.writeln('#include <flutter_linux/flutter_linux.h>');
    headerContent.writeln();
    headerContent.writeln('// Registers Flutter plugins.');
    headerContent.writeln('void fl_register_plugins(FlPluginRegistry* registry);');
    headerContent.writeln();
    headerContent.writeln('#endif  // GENERATED_PLUGIN_REGISTRANT_');

    generatedPluginHeader.writeAsStringSync(headerContent.toString());

    // Write generated_plugin_registrant.cc
    final sourceContent = StringBuffer();
    sourceContent.writeln('// Generated file. Do not edit.');
    sourceContent.writeln('#include "generated_plugin_registrant.h"');
    sourceContent.writeln();
    for (final plugin in methodChannelPlugins) {
      sourceContent.writeln('#include <${plugin["name"]}/${plugin["filename"]}.h>');
    }
    sourceContent.writeln();
    sourceContent.writeln('void fl_register_plugins(FlPluginRegistry* registry) {');
    for (final plugin in methodChannelPlugins) {
      sourceContent.writeln('  g_autoptr(FlPluginRegistrar) ${plugin["name"]}_registrar =');
      sourceContent.writeln(
        '      fl_plugin_registry_get_registrar_for_plugin(registry, "${plugin["class"]}");',
      );
      sourceContent.writeln(
        '  ${plugin["filename"]}_register_with_registrar(${plugin["name"]}_registrar);',
      );
    }
    sourceContent.writeln('}');

    generatedPluginSource.writeAsStringSync(sourceContent.toString());

    // 2. Run cmake
    final buildDir = Directory(context.outputDir);

    try {
      if (!buildDir.existsSync()) {
        buildDir.createSync(recursive: true);
      }
      final String cmakeBuildType =
          context.buildMode[0].toUpperCase() + context.buildMode.substring(1);

      stdout.writeln('Running cmake...');
      final Process cmakeProcess = await Process.start(
        'cmake',
        <String>[
          '-G',
          'Ninja',
          '-DCMAKE_BUILD_TYPE=$cmakeBuildType',
          '-DFLUTTER_TARGET_PLATFORM=$_kLinuxX64Platform',
          '${projectDir.path}/linux',
        ],
        workingDirectory: buildDir.path,
        environment: <String, String>{'CC': 'clang', 'CXX': 'clang++'},
      );

      cmakeProcess.stdout.listen(stdout.add);
      cmakeProcess.stderr.listen(stderr.add);

      final int cmakeExitCode = await cmakeProcess.exitCode;
      if (cmakeExitCode != 0) {
        throw Exception('cmake failed with exit code $cmakeExitCode');
      }
    } on Exception catch (e) {
      throw Exception('Failed to run cmake: $e');
    }

    // 3. Run ninja
    try {
      stdout.writeln('Running ninja...');
      final Process ninjaProcess = await Process.start('ninja', <String>[
        '-C',
        buildDir.path,
        'install',
      ]);

      ninjaProcess.stdout.listen(stdout.add);
      ninjaProcess.stderr.listen(stderr.add);

      final int ninjaExitCode = await ninjaProcess.exitCode;
      if (ninjaExitCode != 0) {
        throw Exception('ninja failed with exit code $ninjaExitCode');
      }
    } on Exception catch (e) {
      throw Exception('Failed to run ninja: $e');
    }

    // 4. Resolve the executable name from pubspec.yaml
    final pubspec = File('${projectDir.path}/pubspec.yaml');
    var appName = 'app';
    if (pubspec.existsSync()) {
      final String pubspecContent = pubspec.readAsStringSync();
      final nameRegExp = RegExp(r'^name:\s+(\w+)', multiLine: true);
      final Match? match = nameRegExp.firstMatch(pubspecContent);
      if (match != null) {
        appName = match.group(1)!;
      }
    }

    final executablePath = '${buildDir.path}/bundle/$appName';
    return <String, Object?>{'executablePath': File(executablePath).absolute.path};
  }
}

abstract class CustomLinuxAssembleOnlyTarget extends ExtensionTarget {
  const CustomLinuxAssembleOnlyTarget({required this.buildModeName, required super.description})
    : super(
        targetPlatform: _kLinuxX64Platform,
        isTopLevel: false,
        outputDir: '$kProjectDirPlaceholder/build/linux_extension/$kBuildModePlaceholder',
      );

  final String buildModeName;

  /// The name of the application binary/snapshot file to copy from the build directory.
  String get appBinaryName;

  /// The destination path for the application binary relative to the output directory.
  String get appBinaryDestinationPath;

  @override
  List<Source> get inputs => <Source>[
    Source.pattern('$kBuildDirPlaceholder/$appBinaryName'),
    const Source.artifact(LinuxArtifacts.linuxHeaders),
    const Source.artifact(LinuxArtifacts.linuxDesktopPath),
    const Source.artifact(BuiltInArtifacts.icuData),
    const Source.pattern('$kProjectDirPlaceholder/pubspec.yaml'),
  ];

  @override
  List<Source> get outputs => <Source>[
    Source.pattern('$kOutputDirPlaceholder/$appBinaryDestinationPath'),
    const Source.pattern('$kOutputDirPlaceholder/bundle/lib/$_kLibFlutterLinuxGtk'),
    const Source.pattern('$kOutputDirPlaceholder/bundle/data/$_kIcuData'),
  ];

  @override
  Future<Map<String, Object?>> build(ExtensionBuildContext context) async {
    final outputDir = Directory(context.outputDir);

    // 1. Copy assets from buildDir
    final srcAssets = Directory('${context.buildDir}/$_kFlutterAssets');
    final destAssets = Directory('${outputDir.path}/bundle/data/$_kFlutterAssets');
    if (srcAssets.existsSync()) {
      _copyDirectory(srcAssets, destAssets);
    }

    // 2. Copy libflutter_linux_gtk.so
    final String? desktopPath = context.resolvedArtifacts[LinuxArtifacts.linuxDesktopPath.name];
    final srcLib = File('$desktopPath/$_kLibFlutterLinuxGtk');
    final destLib = File('${outputDir.path}/bundle/lib/$_kLibFlutterLinuxGtk');
    if (srcLib.existsSync()) {
      _copyFile(srcLib, destLib);
    }

    // 3. Copy icudtl.dat
    final String? icuDataPath = context.resolvedArtifacts[BuiltInArtifacts.icuData.name];
    final srcIcu = File(icuDataPath!);
    final destIcu = File('${outputDir.path}/bundle/data/$_kIcuData');
    if (srcIcu.existsSync()) {
      _copyFile(srcIcu, destIcu);
    }

    // 4. Copy application binary
    final srcApp = File('${context.buildDir}/$appBinaryName');
    final destApp = File('${outputDir.path}/$appBinaryDestinationPath');
    if (srcApp.existsSync()) {
      _copyFile(srcApp, destApp);
    }
    return <String, Object?>{};
  }
}

class CustomLinuxAssembleOnlyDebug extends CustomLinuxAssembleOnlyTarget {
  const CustomLinuxAssembleOnlyDebug()
    : super(buildModeName: 'debug', description: 'A custom Linux assemble-only debug target.');

  @override
  String get name => 'custom-linux-assemble-only-debug';

  @override
  String get appBinaryName => _kAppDill;

  @override
  String get appBinaryDestinationPath => 'bundle/data/$_kFlutterAssets/$_kKernelBlob';

  @override
  List<Target> get dependencies => const <Target>[
    BuiltInTargets.copyAssets,
    BuiltInTargets.kernelSnapshot,
  ];
}

class CustomLinuxAssembleOnlyProfile extends CustomLinuxAssembleOnlyTarget {
  const CustomLinuxAssembleOnlyProfile()
    : super(buildModeName: 'profile', description: 'A custom Linux assemble-only profile target.');

  @override
  String get name => 'custom-linux-assemble-only-profile';

  @override
  String get appBinaryName => _kAppSo;

  @override
  String get appBinaryDestinationPath => 'bundle/lib/$_kLibAppSo';

  @override
  List<Target> get dependencies => const <Target>[
    BuiltInTargets.copyAssets,
    CustomLinuxAotElfProfile(),
  ];
}

class CustomLinuxAssembleOnlyRelease extends CustomLinuxAssembleOnlyTarget {
  const CustomLinuxAssembleOnlyRelease()
    : super(buildModeName: 'release', description: 'A custom Linux assemble-only release target.');

  @override
  String get name => 'custom-linux-assemble-only-release';

  @override
  String get appBinaryName => _kAppSo;

  @override
  String get appBinaryDestinationPath => 'bundle/lib/$_kLibAppSo';

  @override
  List<Target> get dependencies => const <Target>[
    BuiltInTargets.copyAssets,
    CustomLinuxAotElfRelease(),
  ];
}

/// Prototype Linux [BuildService] implementation.
final class LinuxBuildService extends BuildService {
  @override
  List<ExtensionTarget> get targets => const <ExtensionTarget>[
    CustomLinuxBuildTarget(),
    CustomLinuxAssembleOnlyDebug(),
    CustomLinuxAotElfProfile(),
    CustomLinuxAssembleOnlyProfile(),
    CustomLinuxAotElfRelease(),
    CustomLinuxAssembleOnlyRelease(),
  ];
}

class CustomLinuxAotElfProfile extends CustomLinuxAotElf {
  const CustomLinuxAotElfProfile() : super(buildMode: 'profile');

  @override
  String get name => 'custom-linux-aot-elf-profile';
}

class CustomLinuxAotElfRelease extends CustomLinuxAotElf {
  const CustomLinuxAotElfRelease() : super(buildMode: 'release');

  @override
  String get name => 'custom-linux-aot-elf-release';
}

abstract class CustomLinuxAotElf extends ExtensionTarget {
  const CustomLinuxAotElf({required this.buildMode})
    : super(
        targetPlatform: _kLinuxX64Platform,
        description: 'A custom Linux AOT ELF target.',
        isTopLevel: false,
      );

  final String buildMode;

  @override
  List<Source> get inputs => const <Source>[
    Source.pattern('$kBuildDirPlaceholder/$_kAppDill'),
    Source.artifact(BuiltInArtifacts.genSnapshot),
  ];

  @override
  List<Source> get outputs => const <Source>[Source.pattern('$kBuildDirPlaceholder/$_kAppSo')];

  @override
  List<Target> get dependencies => const <Target>[];

  @override
  Future<Map<String, Object?>> build(ExtensionBuildContext context) async {
    final String? genSnapshotPath = context.resolvedArtifacts[BuiltInArtifacts.genSnapshot.name];
    if (genSnapshotPath == null) {
      throw Exception('Missing genSnapshot artifact');
    }

    final String outputDir = context.buildDir;
    final appDill = '$outputDir/$_kAppDill';
    final appSo = '$outputDir/$_kAppSo';

    final args = <String>['--deterministic', '--snapshot_kind=app-aot-elf', '--elf=$appSo'];

    if (buildMode == BuildMode.release.name || buildMode == BuildMode.profile.name) {
      args.add('--strip');
    }

    args.add(appDill);

    stdout.writeln('Running gen_snapshot...');
    final Process process = await Process.start(genSnapshotPath, args);

    process.stdout.listen(stdout.add);
    process.stderr.listen(stderr.add);

    final int exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw Exception('gen_snapshot failed with exit code $exitCode');
    }
    return <String, Object?>{};
  }
}

void _copyDirectory(Directory source, Directory destination) {
  if (!destination.existsSync()) {
    destination.createSync(recursive: true);
  }
  for (final FileSystemEntity entity in source.listSync()) {
    final String name = entity.path.substring(source.path.length + 1);
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


void _unpackArtifacts({
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
    throw Exception('Missing ${LinuxArtifacts.linuxDesktopPath.name} artifact');
  }
  final srcLib = File('$desktopPath/$_kLibFlutterLinuxGtk');
  final destLib = File('${ephemeralDir.path}/$_kLibFlutterLinuxGtk');
  _copyFile(srcLib, destLib);

  // 2. Unpack linuxHeaders (copy flutter_linux directory contents)
  final String? headersPath = resolvedArtifacts[LinuxArtifacts.linuxHeaders.name];
  if (headersPath == null) {
    throw Exception('Missing ${LinuxArtifacts.linuxHeaders.name} artifact');
  }
  final srcHeadersDir = Directory(headersPath);
  final destHeadersDir = Directory('${ephemeralDir.path}/flutter_linux');
  if (srcHeadersDir.existsSync()) {
    _copyDirectory(srcHeadersDir, destHeadersDir);
  }

  // 3. Unpack icuData (copy icudtl.dat)
  final String? icuDataPath = resolvedArtifacts[BuiltInArtifacts.icuData.name];
  if (icuDataPath == null) {
    throw Exception('Missing ${BuiltInArtifacts.icuData.name} artifact');
  }
  final srcIcu = File(icuDataPath);
  final destIcu = File('${ephemeralDir.path}/$_kIcuData');
  _copyFile(srcIcu, destIcu);
}

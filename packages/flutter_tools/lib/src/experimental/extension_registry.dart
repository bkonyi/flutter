// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';
import 'package:process/process.dart';
import 'package:yaml/yaml.dart';

import '../base/file_system.dart';
import '../base/io.dart';
import '../base/logger.dart';
import '../base/platform.dart';
import 'extension_discovery.dart';
import 'extension_manifest.dart';

/// Represents a globally installed tool extension entry tracked in the global registry.
class GlobalExtensionEntry {
  const GlobalExtensionEntry({
    required this.capabilities,
    required this.dartSdkVersion,
    required this.enabled,
    required this.entrypointPath,
    required this.installDir,
    required this.name,
    required this.source,
    required this.version,
    this.snapshotPath,
  });

  /// The capabilities and supported services of this extension.
  final ToolExtensionCapabilities capabilities;

  /// The Dart SDK version under which this extension's snapshot was compiled.
  final String dartSdkVersion;

  /// Whether this global extension is active.
  final bool enabled;

  /// The path to the Dart entrypoint file for this extension.
  final String entrypointPath;

  /// The directory where this extension is installed and scaffolded.
  final String installDir;

  /// The unique name of this extension.
  final String name;

  /// The path to the compiled AppJIT snapshot, if present.
  final String? snapshotPath;

  /// The source type of the extension (`'path'`, `'pub'`, or `'git'`).
  final String source;

  /// The semantic version string of the extension.
  final String version;

  /// Creates a copy of this entry with optional updated fields.
  GlobalExtensionEntry copyWith({
    ToolExtensionCapabilities? capabilities,
    String? dartSdkVersion,
    bool? enabled,
    String? entrypointPath,
    String? installDir,
    String? name,
    String? snapshotPath,
    String? source,
    String? version,
  }) {
    return GlobalExtensionEntry(
      capabilities: capabilities ?? this.capabilities,
      dartSdkVersion: dartSdkVersion ?? this.dartSdkVersion,
      enabled: enabled ?? this.enabled,
      entrypointPath: entrypointPath ?? this.entrypointPath,
      installDir: installDir ?? this.installDir,
      name: name ?? this.name,
      snapshotPath: snapshotPath ?? this.snapshotPath,
      source: source ?? this.source,
      version: version ?? this.version,
    );
  }

  /// Serializes this entry to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'version': version,
    'source': source,
    'installDir': installDir,
    'entrypointPath': entrypointPath,
    if (snapshotPath != null) 'snapshotPath': snapshotPath,
    'enabled': enabled,
    'capabilities': capabilities.toMap(),
    'dartSdkVersion': dartSdkVersion,
  };

  /// Deserializes a [GlobalExtensionEntry] from a JSON map.
  static GlobalExtensionEntry? fromJson(Map<String, Object?> json) {
    if (json case {
      'name': final String name,
      'version': final String version,
      'source': final String source,
      'installDir': final String installDir,
      'entrypointPath': final String entrypointPath,
      'enabled': final bool enabled,
      'capabilities': final Map<String, Object?> capabilitiesMap,
      'dartSdkVersion': final String dartSdkVersion,
    }) {
      final snapshotPath = json['snapshotPath'] as String?;
      final capabilities = ToolExtensionCapabilities.fromJson(capabilitiesMap);
      return GlobalExtensionEntry(
        capabilities: capabilities,
        dartSdkVersion: dartSdkVersion,
        enabled: enabled,
        entrypointPath: entrypointPath,
        installDir: installDir,
        name: name,
        snapshotPath: snapshotPath,
        source: source,
        version: version,
      );
    }
    return null;
  }
}

/// Manages the global Flutter tool extension registry on disk.
class GlobalExtensionRegistry {
  GlobalExtensionRegistry({
    required FileSystem fileSystem,
    required Logger logger,
    required Platform platform,
    required ProcessManager processManager,
    Directory? customRegistryDir,
    String? dartBinaryPath,
    ExtensionUriSpawner spawner = ExtensionConnection.spawnUri,
  }) : _fs = fileSystem,
       _logger = logger,
       _platform = platform,
       _processManager = processManager,
       _customRegistryDir = customRegistryDir,
       _dartBinaryPath = dartBinaryPath,
       _spawner = spawner;

  final FileSystem _fs;
  final Logger _logger;
  final Platform _platform;
  final ProcessManager _processManager;
  final Directory? _customRegistryDir;
  final String? _dartBinaryPath;
  final ExtensionUriSpawner _spawner;

  static const String kDefaultDirName = 'flutter_tool_extensions';
  static const String kRegistryFileName = 'extension_registry.json';
  static const String kDartDataHomeEnvKey = 'DART_DATA_HOME';

  /// The root directory containing installed extensions and the registry file.
  Directory get registryDir {
    if (_customRegistryDir != null) {
      return _customRegistryDir;
    }
    if (_platform.environment[kDartDataHomeEnvKey] case final String dataHome
        when dataHome.trim().isNotEmpty) {
      return _fs.directory(dataHome.trim()).childDirectory(kDefaultDirName);
    }
    final String? home = _platform.isWindows
        ? (_platform.environment['USERPROFILE'] ?? _platform.environment['HOME'])
        : (_platform.environment['HOME'] ?? _platform.environment['USERPROFILE']);
    if (home != null && home.trim().isNotEmpty) {
      return _fs.directory(home.trim()).childDirectory('.$kDefaultDirName');
    }
    return _fs.systemTempDirectory.childDirectory('.$kDefaultDirName');
  }

  /// The JSON file tracking globally installed extensions.
  File get registryFile => registryDir.childFile(kRegistryFileName);

  String get _dartBinary {
    if (_dartBinaryPath != null) {
      return _dartBinaryPath;
    }
    if (_platform.environment['DART_BINARY'] case final String envDart when envDart.isNotEmpty) {
      return envDart;
    }
    return 'dart';
  }

  /// Loads all installed extension entries from disk.
  Map<String, GlobalExtensionEntry> loadEntries() {
    if (!registryFile.existsSync()) {
      return <String, GlobalExtensionEntry>{};
    }
    try {
      final String content = registryFile.readAsStringSync();
      final Object? decoded = json.decode(content);
      if (decoded case {'extensions': final Map<String, Object?> entriesJson}) {
        return <String, GlobalExtensionEntry>{
          for (final MapEntry(:key, :value) in entriesJson.entries)
            if (value is Map<String, Object?>)
              if (GlobalExtensionEntry.fromJson(value) case final GlobalExtensionEntry entry)
                key: entry,
        };
      } else if (decoded case final Map<String, Object?> entriesJson) {
        return <String, GlobalExtensionEntry>{
          for (final MapEntry(:key, :value) in entriesJson.entries)
            if (value is Map<String, Object?>)
              if (GlobalExtensionEntry.fromJson(value) case final GlobalExtensionEntry entry)
                key: entry,
        };
      }
    } on Object catch (error, stackTrace) {
      _logger.printTrace(
        'Failed to read extension registry at "${registryFile.path}": $error\n$stackTrace',
      );
    }
    return <String, GlobalExtensionEntry>{};
  }

  /// Saves [entries] to disk in [registryFile].
  void saveEntries(Map<String, GlobalExtensionEntry> entries) {
    try {
      if (!registryDir.existsSync()) {
        registryDir.createSync(recursive: true);
      }
      final data = <String, Object?>{
        'version': 1,
        'extensions': <String, Object?>{
          for (final MapEntry(:key, :value) in entries.entries) key: value.toJson(),
        },
      };
      const encoder = JsonEncoder.withIndent('  ');
      registryFile.writeAsStringSync(encoder.convert(data));
    } on Object catch (error, stackTrace) {
      _logger.printError('Failed to save extension registry to "${registryFile.path}": $error');
      _logger.printTrace('$stackTrace');
    }
  }

  /// Retrieves an installed entry by [name], or null if not installed.
  GlobalExtensionEntry? getEntry(String name) => loadEntries()[name];

  /// Retrieves an installed entry by [name], or null if not installed.
  GlobalExtensionEntry? getExtension(String name) => getEntry(name);

  /// Whether an extension with [name] is installed.
  bool hasExtension(String name) => getEntry(name) != null;

  /// Adds or updates [entry] in the registry.
  void register(GlobalExtensionEntry entry) {
    final Map<String, GlobalExtensionEntry> entries = loadEntries();
    entries[entry.name] = entry;
    saveEntries(entries);
  }

  /// Removes an entry by [name] from the registry.
  bool unregister(String name) {
    final Map<String, GlobalExtensionEntry> entries = loadEntries();
    if (!entries.containsKey(name)) {
      return false;
    }
    entries.remove(name);
    saveEntries(entries);
    return true;
  }

  /// Sets the `enabled` state of extension [name].
  bool setEnabled(String name, bool enabled) {
    final Map<String, GlobalExtensionEntry> entries = loadEntries();
    final GlobalExtensionEntry? entry = entries[name];
    if (entry == null) {
      return false;
    }
    entries[name] = entry.copyWith(enabled: enabled);
    saveEntries(entries);
    return true;
  }

  /// Enables extension [name].
  bool enable(String name) => setEnabled(name, true);

  /// Disables extension [name].
  bool disable(String name) => setEnabled(name, false);

  /// Installs an extension from [source] (local path, pub, or git).
  Future<GlobalExtensionEntry> install({
    required String source,
    String? dartBinaryPath,
    String? name,
    String? version,
  }) async {
    final (String sourceType, String sourceResolved) = _detectSource(source);

    String extName = name ?? '';
    String extVersion = version ?? '';
    Uri? resolvedEntrypointUri;

    if (sourceType == 'path') {
      final Directory sourceDir = _fs.directory(sourceResolved);
      final File pubspecFile = sourceDir.childFile('pubspec.yaml');
      String? detectedName;
      String? detectedVersion;
      if (pubspecFile.existsSync()) {
        try {
          final Object? yaml = loadYaml(pubspecFile.readAsStringSync());
          if (yaml is YamlMap) {
            detectedName = yaml['name'] as String?;
            detectedVersion = yaml['version']?.toString();
          }
        } on Object catch (e) {
          _logger.printTrace('Error reading pubspec.yaml at ${pubspecFile.path}: $e');
        }
      }

      extName = name ?? detectedName ?? sourceDir.basename;
      extVersion = version ?? detectedVersion ?? '1.0.0';

      final File manifestFile = sourceDir.childFile('flutter_extensions.yaml');
      if (manifestFile.existsSync()) {
        final manifestFinder = ExtensionManifestFinder(fileSystem: _fs, logger: _logger);
        try {
          final ExtensionManifest manifest = manifestFinder.parseManifest(manifestFile);
          for (final ExtensionDeclaration decl in manifest.extensions) {
            if (decl.name == extName) {
              final Uri? uri = manifestFinder.resolveExtensionEntrypoint(decl, manifestFile);
              if (uri != null) {
                resolvedEntrypointUri = uri;
              }
              break;
            }
          }
        } on Object catch (e) {
          _logger.printTrace('Error reading flutter_extensions.yaml at ${sourceDir.path}: $e');
        }
      }

      if (resolvedEntrypointUri == null) {
        final File binEntrypoint = sourceDir.childDirectory('bin').childFile('$extName.dart');
        if (binEntrypoint.existsSync()) {
          resolvedEntrypointUri = binEntrypoint.uri;
        } else {
          final File libEntrypoint = sourceDir.childDirectory('lib').childFile('$extName.dart');
          if (libEntrypoint.existsSync()) {
            resolvedEntrypointUri = libEntrypoint.uri;
          } else {
            resolvedEntrypointUri = Uri.parse('package:$extName/$extName.dart');
          }
        }
      }
    } else if (sourceType == 'git') {
      String? detectedName;
      final Uri? uri = Uri.tryParse(sourceResolved);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        detectedName = uri.pathSegments.last.replaceAll('.git', '');
      }
      extName = name ?? detectedName ?? 'extension';
      extVersion = version ?? '1.0.0';
      resolvedEntrypointUri = Uri.parse('package:$extName/$extName.dart');
    } else {
      var pkgName = sourceResolved;
      var pkgConstraint = 'any';
      if (sourceResolved.contains(':')) {
        final List<String> parts = sourceResolved.split(':');
        pkgName = parts[0];
        pkgConstraint = parts[1];
      }
      extName = name ?? pkgName;
      extVersion = version ?? pkgConstraint;
      resolvedEntrypointUri = Uri.parse('package:$extName/$extName.dart');
    }

    // Scaffold package under $registryDir/<name>/
    final Directory installDir = registryDir.childDirectory(extName);
    if (installDir.existsSync()) {
      installDir.deleteSync(recursive: true);
    }
    installDir.createSync(recursive: true);

    final File pubspec = installDir.childFile('pubspec.yaml');
    final String depBlock = switch (sourceType) {
      'path' =>
        '''
  $extName:
    path: '${_fs.path.absolute(sourceResolved)}'
''',
      'git' =>
        '''
  $extName:
    git:
      url: '$sourceResolved'
''',
      _ =>
        '''
  $extName: '$extVersion'
''',
    };

    pubspec.writeAsStringSync('''
name: ${extName}_scaffold
description: Scaffolding package for global tool extension $extName.
version: 1.0.0
environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
$depBlock''');

    // Generate bin/generated_entrypoint.dart supporting --train
    final Directory binDir = installDir.childDirectory('bin')..createSync(recursive: true);
    final File entrypointFile = binDir.childFile('generated_entrypoint.dart');
    entrypointFile.writeAsStringSync('''
// Generated by flutter extensions. Do not edit.
import 'dart:isolate';
import '$resolvedEntrypointUri' as extension_entrypoint;

void main(List<String> args, [SendPort? sendPort]) {
  if (args.contains('--train')) {
    return;
  }
  if (sendPort != null) {
    try {
      (extension_entrypoint.main as dynamic)(args, sendPort);
    } on NoSuchMethodError {
      (extension_entrypoint.main as dynamic)(sendPort);
    }
  }
}
''');

    final String dart = dartBinaryPath ?? _dartBinary;

    // Run pub get / dependency resolution
    final ProcessResult pubResult = await _processManager.run(<String>[
      dart,
      'pub',
      'get',
    ], workingDirectory: installDir.path);
    if (pubResult.exitCode != 0) {
      throw ProcessException(
        dart,
        <String>['pub', 'get'],
        'Failed to run "dart pub get" for "$extName":\n${pubResult.stderr}',
        pubResult.exitCode,
      );
    }

    // Compile AppJIT snapshot via dart compile jit-snapshot -o <snapshotPath> <entrypointPath> --train
    final File snapshotFile = binDir.childFile('generated_entrypoint.jit');
    final ProcessResult compileResult = await _processManager.run(<String>[
      dart,
      'compile',
      'jit-snapshot',
      '-o',
      snapshotFile.path,
      entrypointFile.path,
      '--train',
    ], workingDirectory: installDir.path);
    if (compileResult.exitCode != 0) {
      throw ProcessException(
        dart,
        <String>[
          'compile',
          'jit-snapshot',
          '-o',
          snapshotFile.path,
          entrypointFile.path,
          '--train',
        ],
        'Failed to compile AppJIT snapshot for "$extName":\n${compileResult.stderr}',
        compileResult.exitCode,
      );
    }

    // Spawn snapshot once to query capabilities and write entry to extension_registry.json
    final File packageConfigFile = installDir
        .childDirectory('.dart_tool')
        .childFile('package_config.json');
    final Uri? packageConfigUri = packageConfigFile.existsSync() ? packageConfigFile.uri : null;

    final Uri spawnTarget = snapshotFile.existsSync() ? snapshotFile.uri : entrypointFile.uri;

    final ExtensionConnection connection = await _spawner(
      spawnTarget,
      logger: _logger,
      packageConfigUri: packageConfigUri,
    );
    final ToolExtensionCapabilities capabilities = connection.capabilities;
    await connection.dispose();

    final entry = GlobalExtensionEntry(
      capabilities: capabilities,
      dartSdkVersion: _platform.version,
      enabled: true,
      entrypointPath: entrypointFile.path,
      installDir: installDir.path,
      name: extName,
      snapshotPath: snapshotFile.existsSync() ? snapshotFile.path : null,
      source: sourceType,
      version: extVersion,
    );
    register(entry);
    return entry;
  }

  /// Uninstalls an extension by [name], deleting its install directory and removing its registry entry.
  Future<bool> uninstall(String name) async {
    final Map<String, GlobalExtensionEntry> entries = loadEntries();
    final GlobalExtensionEntry? entry = entries[name];
    if (entry == null) {
      return false;
    }
    final Directory dir = _fs.directory(entry.installDir);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
    final Directory defaultDir = registryDir.childDirectory(name);
    if (defaultDir.existsSync()) {
      defaultDir.deleteSync(recursive: true);
    }
    unregister(name);
    return true;
  }

  /// Upgrades installed extensions (or [name] if specified).
  Future<List<GlobalExtensionEntry>> upgrade({String? dartBinaryPath, String? name}) async {
    final Map<String, GlobalExtensionEntry> entries = loadEntries();
    final List<GlobalExtensionEntry> toUpgrade;
    if (name != null) {
      final GlobalExtensionEntry? entry = entries[name];
      if (entry == null) {
        throw StateError('Extension "$name" is not installed.');
      }
      toUpgrade = <GlobalExtensionEntry>[entry];
    } else {
      toUpgrade = entries.values.toList();
    }

    final upgraded = <GlobalExtensionEntry>[];
    final String dart = dartBinaryPath ?? _dartBinary;

    for (final entry in toUpgrade) {
      final Directory installDir = _fs.directory(entry.installDir);
      if (!installDir.existsSync()) {
        _logger.printWarning(
          'Install directory for extension "${entry.name}" does not exist: ${installDir.path}',
        );
        continue;
      }

      final ProcessResult pubResult = await _processManager.run(<String>[
        dart,
        'pub',
        'upgrade',
      ], workingDirectory: installDir.path);
      if (pubResult.exitCode != 0) {
        _logger.printError(
          'Failed to upgrade dependencies for "${entry.name}":\n${pubResult.stderr}',
        );
        continue;
      }

      final String entrypointPath = entry.entrypointPath;
      final String snapshotPath =
          entry.snapshotPath ??
          installDir.childDirectory('bin').childFile('generated_entrypoint.jit').path;

      final ProcessResult compileResult = await _processManager.run(<String>[
        dart,
        'compile',
        'jit-snapshot',
        '-o',
        snapshotPath,
        entrypointPath,
        '--train',
      ], workingDirectory: installDir.path);
      if (compileResult.exitCode != 0) {
        _logger.printError(
          'Failed to recompile snapshot for "${entry.name}":\n${compileResult.stderr}',
        );
        continue;
      }

      ToolExtensionCapabilities capabilities = entry.capabilities;
      try {
        final File packageConfigFile = installDir
            .childDirectory('.dart_tool')
            .childFile('package_config.json');
        final Uri? packageConfigUri = packageConfigFile.existsSync() ? packageConfigFile.uri : null;
        final ExtensionConnection connection = await _spawner(
          _fs.file(snapshotPath).uri,
          logger: _logger,
          packageConfigUri: packageConfigUri,
        );
        capabilities = connection.capabilities;
        await connection.dispose();
      } on Object catch (error) {
        _logger.printTrace(
          'Could not query capabilities after upgrade for "${entry.name}": $error',
        );
      }

      final GlobalExtensionEntry updatedEntry = entry.copyWith(
        capabilities: capabilities,
        dartSdkVersion: _platform.version,
        snapshotPath: snapshotPath,
      );
      register(updatedEntry);
      upgraded.add(updatedEntry);
    }
    return upgraded;
  }

  (String sourceType, String sourceResolved) _detectSource(String source) {
    if (source.startsWith('path:')) {
      return ('path', source.substring('path:'.length));
    }
    if (source.startsWith('git:')) {
      return ('git', source.substring('git:'.length));
    }
    if (source.startsWith('pub:')) {
      return ('pub', source.substring('pub:'.length));
    }
    if (source.startsWith('http://') || source.startsWith('https://') || source.endsWith('.git')) {
      return ('git', source);
    }
    if (_fs.isDirectorySync(source)) {
      return ('path', source);
    }
    final Directory candidateDir = _fs.directory(source);
    if (candidateDir.existsSync()) {
      return ('path', source);
    }
    return ('pub', source);
  }
}

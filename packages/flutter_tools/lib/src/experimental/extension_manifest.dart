// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:yaml/yaml.dart';

import '../base/file_system.dart';
import '../base/logger.dart';

/// Utilities for discovering, parsing, and resolving `flutter_extensions.yaml` manifests.
class ExtensionManifestFinder {
  ExtensionManifestFinder({required FileSystem fileSystem, required Logger logger})
    : _fs = fileSystem,
      _logger = logger;

  final FileSystem _fs;
  final Logger _logger;

  /// The standard file name for extension manifests.
  static const String kManifestFileName = 'flutter_extensions.yaml';

  static const String _kGitDirName = '.git';
  static const String _kPubspecFileName = 'pubspec.yaml';
  static const String _kWorkspaceKey = 'workspace';
  static const String _kDartToolDirName = '.dart_tool';
  static const String _kPackageConfigFileName = 'package_config.json';
  static const String _kDefaultEntrypointDir = 'bin';

  /// Locates all [kManifestFileName] files from [startDir] upwards to the repository
  /// or pub workspace root.
  ///
  /// Returns the files ordered from the root-most directory to [startDir], so that
  /// leaf/project declarations can override root/workspace declarations.
  List<File> findManifestFiles(Directory startDir) {
    final discovered = <File>[];
    Directory current = startDir.absolute;

    while (true) {
      final File manifestCandidate = current.childFile(kManifestFileName);
      if (manifestCandidate.existsSync()) {
        discovered.add(manifestCandidate);
      }

      // Check stop conditions for upward traversal.
      if (_isSentinelRoot(current)) {
        break;
      }

      final Directory parent = current.parent;
      if (parent.path == current.path) {
        // Reached filesystem root.
        break;
      }
      current = parent;
    }

    // Return root-most first, leaf-most last.
    return discovered.reversed.toList();
  }

  /// Determines whether [directory] is a sentinel traversal boundary (e.g. pub workspace
  /// root or git root).
  bool _isSentinelRoot(Directory directory) {
    // 1. Check for .git directory or file (for worktrees/submodules).
    final FileSystemEntityType gitType = _fs.typeSync(_fs.path.join(directory.path, _kGitDirName));
    if (gitType != FileSystemEntityType.notFound) {
      return true;
    }

    // 2. Check for pub workspace root in pubspec.yaml.
    final File pubspec = directory.childFile(_kPubspecFileName);
    if (pubspec.existsSync()) {
      try {
        final Object? yaml = loadYaml(pubspec.readAsStringSync());
        if (yaml is YamlMap && yaml.containsKey(_kWorkspaceKey)) {
          return true;
        }
      } on Exception catch (err) {
        _logger.printTrace('Error checking pubspec.yaml at ${pubspec.path}: $err');
      }
    }

    return false;
  }

  /// Parses a [kManifestFileName] into an [ExtensionManifest], formatting schema
  /// errors with source spans and line numbers.
  ExtensionManifest parseManifest(File file) {
    final String content = file.readAsStringSync();
    final YamlNode rootNode = loadYamlNode(content, sourceUrl: file.uri);

    if (rootNode is! YamlMap) {
      throw FormatException(
        rootNode.span.message('Expected a YAML mapping at the root of "$kManifestFileName".'),
      );
    }

    final YamlNode? extensionsNode = rootNode.nodes['extensions'];
    if (extensionsNode == null) {
      return const ExtensionManifest(extensions: <ExtensionDeclaration>[]);
    }

    final declarations = <ExtensionDeclaration>[];

    if (extensionsNode is YamlList) {
      for (final YamlNode itemNode in extensionsNode.nodes) {
        if (itemNode is! YamlMap) {
          throw FormatException(
            itemNode.span.message(
              'Each extension entry in the extensions list must be a YAML mapping.',
            ),
          );
        }
        declarations.add(_parseDeclarationFromYamlMap(itemNode));
      }
    } else if (extensionsNode is YamlMap) {
      for (final MapEntry<Object?, YamlNode>(:key, :value) in extensionsNode.nodes.entries) {
        final String name = switch (key) {
          final String keyString => keyString,
          YamlScalar(:final String value) => value,
          final YamlNode node => throw FormatException(
            node.span.message('Extension name key must be a string.'),
          ),
          _ => throw FormatException(
            extensionsNode.span.message('Extension name key must be a string.'),
          ),
        };
        if (value is! YamlMap) {
          throw FormatException(
            value.span.message('Extension declaration for "$name" must be a YAML mapping.'),
          );
        }
        declarations.add(_parseDeclarationFromYamlMap(value, defaultName: name));
      }
    } else {
      throw FormatException(
        extensionsNode.span.message('The "extensions" key must be a list or a map.'),
      );
    }

    return ExtensionManifest(extensions: declarations);
  }

  String? _parseOptionalString(YamlMap map, String key) {
    return switch (map.nodes[key]) {
      null => null,
      YamlScalar(:final String value) => value,
      final YamlNode node => throw FormatException(
        node.span.message('Extension "$key" must be a string.'),
      ),
    };
  }

  ExtensionDeclaration _parseDeclarationFromYamlMap(YamlMap map, {String? defaultName}) {
    final YamlNode? nameNode = map.nodes['name'];
    final String name;
    if (nameNode != null) {
      if (nameNode is! YamlScalar || nameNode.value is! String) {
        throw FormatException(nameNode.span.message('Extension "name" must be a string.'));
      }
      name = nameNode.value as String;
    } else if (defaultName != null) {
      name = defaultName;
    } else {
      throw FormatException(
        map.span.message('Extension declaration is missing the required "name" property.'),
      );
    }

    final String? description = _parseOptionalString(map, 'description');

    final YamlNode? enabledNode = map.nodes['enabled'];
    var enabled = true;
    if (enabledNode != null) {
      if (enabledNode is! YamlScalar || enabledNode.value is! bool) {
        throw FormatException(enabledNode.span.message('Extension "enabled" must be a boolean.'));
      }
      enabled = enabledNode.value as bool;
    }

    final String? entrypoint = _parseOptionalString(map, 'entrypoint');
    final String? path = _parseOptionalString(map, 'path');

    final YamlNode? platformsNode = map.nodes['supportedPlatforms'];
    List<String>? supportedPlatforms;
    if (platformsNode != null) {
      if (platformsNode is! YamlList) {
        throw FormatException(
          platformsNode.span.message('Extension "supportedPlatforms" must be a list of strings.'),
        );
      }
      final platforms = <String>[];
      for (final YamlNode platformNode in platformsNode.nodes) {
        if (platformNode is! YamlScalar || platformNode.value is! String) {
          throw FormatException(platformNode.span.message('Platform entry must be a string.'));
        }
        platforms.add(platformNode.value as String);
      }
      supportedPlatforms = platforms;
    }

    return ExtensionDeclaration(
      name: name,
      description: description,
      enabled: enabled,
      entrypoint: entrypoint,
      path: path,
      supportedPlatforms: supportedPlatforms,
    );
  }

  /// Parses and merges declarations from [manifestFiles] in order.
  ///
  /// Later files (e.g. project-level) override earlier files (e.g. workspace-level).
  Map<String, ExtensionDeclaration> loadMergedDeclarations(List<File> manifestFiles) {
    final merged = <String, ExtensionDeclaration>{};
    for (final file in manifestFiles) {
      final ExtensionManifest manifest = parseManifest(file);
      for (final ExtensionDeclaration declaration in manifest.extensions) {
        merged[declaration.name] = declaration;
      }
    }
    return merged;
  }

  /// Resolves the Dart entrypoint [Uri] for [declaration] based on [manifestFile].
  ///
  /// If `declaration.path` is provided, it is resolved relative to the directory
  /// containing [manifestFile].
  ///
  /// If `declaration.path` is omitted, resolution searches for `.dart_tool/package_config.json`
  /// starting from the directory containing [manifestFile] and traversing upward to locate the package root.
  Uri? resolveExtensionEntrypoint(ExtensionDeclaration declaration, File manifestFile) {
    if (declaration.path != null) {
      final String packageDir = _fs.path.normalize(
        _fs.path.join(manifestFile.parent.path, declaration.path),
      );
      final String entrypointRelative =
          declaration.entrypoint ??
          _fs.path.join(_kDefaultEntrypointDir, '${declaration.name}.dart');
      final File entrypointFile = _fs.file(_fs.path.join(packageDir, entrypointRelative));
      if (entrypointFile.existsSync()) {
        return entrypointFile.uri;
      }
      _logger.printTrace(
        'Entrypoint for extension "${declaration.name}" does not exist at: ${entrypointFile.path}',
      );
      return null;
    }

    // Resolve through package_config.json.
    final File? packageConfigFile = _findPackageConfig(manifestFile.parent);
    if (packageConfigFile == null || !packageConfigFile.existsSync()) {
      _logger.printTrace(
        'Could not locate .dart_tool/package_config.json for extension "${declaration.name}".',
      );
      return null;
    }

    try {
      final String configContent = packageConfigFile.readAsStringSync();
      if (json.decode(configContent) case {'packages': final List<Object?> packages}) {
        for (final pkg in packages) {
          if (pkg case {'name': final String pkgName, 'rootUri': final String rootUriStr}) {
            if (pkgName == declaration.name) {
              final normalizedRoot = rootUriStr.endsWith('/') ? rootUriStr : '$rootUriStr/';
              final Uri rootUri = packageConfigFile.parent.uri.resolve(normalizedRoot);
              final String entrypointRelative =
                  (declaration.entrypoint ?? '$_kDefaultEntrypointDir/${declaration.name}.dart')
                      .replaceAll(r'\', '/');
              final Uri entrypointUri = rootUri.resolve(entrypointRelative);
              final File entrypointFile = _fs.file(entrypointUri);
              if (entrypointFile.existsSync()) {
                return entrypointUri;
              }
              _logger.printTrace('Resolved entrypoint file does not exist: ${entrypointFile.path}');
              return null;
            }
          }
        }
      }
    } on Object catch (err) {
      _logger.printTrace('Error reading package_config.json at "${packageConfigFile.path}": $err');
    }

    return null;
  }

  File? _findPackageConfig(Directory directory) {
    Directory current = directory.absolute;
    while (true) {
      final File configCandidate = current
          .childDirectory(_kDartToolDirName)
          .childFile(_kPackageConfigFileName);
      if (configCandidate.existsSync()) {
        return configCandidate;
      }
      if (_isSentinelRoot(current)) {
        break;
      }
      final Directory parent = current.parent;
      if (parent.path == current.path) {
        break;
      }
      current = parent;
    }
    return null;
  }
}

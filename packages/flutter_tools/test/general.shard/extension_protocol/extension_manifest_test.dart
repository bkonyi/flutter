// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/experimental/extension_manifest.dart';
import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:test/test.dart';

void main() {
  group('ExtensionManifestFinder', () {
    late FileSystem fs;
    late BufferLogger logger;
    late ExtensionManifestFinder finder;

    setUp(() {
      fs = MemoryFileSystem.test();
      logger = BufferLogger.test();
      finder = ExtensionManifestFinder(fileSystem: fs, logger: logger);
    });

    test('finds manifest files traversing upwards and stops at pub workspace root', () {
      final Directory workspaceRoot = fs.directory('/workspace')..createSync();
      workspaceRoot.childFile('pubspec.yaml').writeAsStringSync('''
name: my_workspace
workspace:
  - app
''');
      final File rootManifest = workspaceRoot.childFile(ExtensionManifestFinder.kManifestFileName)
        ..writeAsStringSync('''
extensions:
  root_ext:
    path: packages/root_ext
''');

      final Directory appDir = workspaceRoot.childDirectory('app')..createSync();
      appDir.childFile('pubspec.yaml').writeAsStringSync('''
name: my_app
''');
      final File appManifest = appDir.childFile(ExtensionManifestFinder.kManifestFileName)
        ..writeAsStringSync('''
extensions:
  app_ext:
    path: packages/app_ext
''');

      final List<File> manifests = finder.findManifestFiles(appDir);
      expect(manifests, hasLength(2));
      // Root-most first, leaf-most last.
      expect(manifests.first.path, rootManifest.path);
      expect(manifests.last.path, appManifest.path);
    });

    test('finds manifest files traversing upwards and stops at .git root', () {
      final Directory gitRoot = fs.directory('/repo')..createSync();
      gitRoot.childDirectory('.git').createSync();
      final File rootManifest = gitRoot.childFile(ExtensionManifestFinder.kManifestFileName)
        ..writeAsStringSync('extensions: []');

      final Directory nestedDir = gitRoot.childDirectory('packages').childDirectory('sub')
        ..createSync(recursive: true);
      final File nestedManifest = nestedDir.childFile(ExtensionManifestFinder.kManifestFileName)
        ..writeAsStringSync('extensions: []');

      final List<File> manifests = finder.findManifestFiles(nestedDir);
      expect(manifests, hasLength(2));
      expect(manifests.first.path, rootManifest.path);
      expect(manifests.last.path, nestedManifest.path);
    });

    test('parses list-based extensions schema in manifest', () {
      final File manifestFile = fs.file('/flutter_extensions.yaml')
        ..writeAsStringSync('''
extensions:
  - name: linux_custom
    description: Custom Linux support
    enabled: true
    entrypoint: bin/custom_linux.dart
    path: ../linux_custom
    supportedPlatforms:
      - linux
''');

      final ExtensionManifest manifest = finder.parseManifest(manifestFile);
      expect(manifest.extensions, hasLength(1));
      final ExtensionDeclaration decl = manifest.extensions.first;
      expect(decl.name, 'linux_custom');
      expect(decl.description, 'Custom Linux support');
      expect(decl.enabled, isTrue);
      expect(decl.entrypoint, 'bin/custom_linux.dart');
      expect(decl.path, '../linux_custom');
      expect(decl.supportedPlatforms, <String>['linux']);
    });

    test('parses map-based extensions schema in manifest', () {
      final File manifestFile = fs.file('/flutter_extensions.yaml')
        ..writeAsStringSync('''
extensions:
  embedded_device:
    description: Embedded target support
    path: packages/embedded
    supportedPlatforms:
      - linux
      - windows
''');

      final ExtensionManifest manifest = finder.parseManifest(manifestFile);
      expect(manifest.extensions, hasLength(1));
      final ExtensionDeclaration decl = manifest.extensions.first;
      expect(decl.name, 'embedded_device');
      expect(decl.description, 'Embedded target support');
      expect(decl.path, 'packages/embedded');
      expect(decl.supportedPlatforms, <String>['linux', 'windows']);
      expect(decl.enabled, isTrue);
    });

    test('merges declarations with leaf overriding root', () {
      final File rootFile = fs.file('/workspace/flutter_extensions.yaml')
        ..createSync(recursive: true);
      rootFile.writeAsStringSync('''
extensions:
  shared_ext:
    description: Workspace level
    enabled: false
  root_only_ext:
    description: Root only
''');

      final File leafFile = fs.file('/workspace/app/flutter_extensions.yaml')
        ..createSync(recursive: true);
      leafFile.writeAsStringSync('''
extensions:
  shared_ext:
    description: Project level override
    enabled: true
  leaf_only_ext:
    description: Leaf only
''');

      final Map<String, ExtensionDeclaration> merged = finder.loadMergedDeclarations(<File>[
        rootFile,
        leafFile,
      ]);

      expect(merged, hasLength(3));
      expect(merged['shared_ext']!.description, 'Project level override');
      expect(merged['shared_ext']!.enabled, isTrue);
      expect(merged['root_only_ext']!.description, 'Root only');
      expect(merged['leaf_only_ext']!.description, 'Leaf only');
    });

    test('throws FormatException with SourceSpan on invalid root node', () {
      final File manifestFile = fs.file('/flutter_extensions.yaml')
        ..writeAsStringSync('- not-a-map');

      expect(
        () => finder.parseManifest(manifestFile),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Expected a YAML mapping at the root'),
          ),
        ),
      );
    });

    test('throws FormatException with SourceSpan on missing name in list', () {
      final File manifestFile = fs.file('/flutter_extensions.yaml')
        ..writeAsStringSync('''
extensions:
  - description: missing name property
''');

      expect(
        () => finder.parseManifest(manifestFile),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('missing the required "name" property'),
          ),
        ),
      );
    });

    test('resolves entrypoint path relative to manifest when path specified', () {
      final Directory projectDir = fs.directory('/project')..createSync();
      final File manifestFile = projectDir.childFile('flutter_extensions.yaml')
        ..writeAsStringSync('''
extensions:
  local_plugin:
    path: custom_plugin
''');
      final File entrypointFile =
          projectDir
              .childDirectory('custom_plugin')
              .childDirectory('bin')
              .childFile('local_plugin.dart')
            ..createSync(recursive: true);

      const decl = ExtensionDeclaration(name: 'local_plugin', path: 'custom_plugin');

      final Uri? resolvedUri = finder.resolveExtensionEntrypoint(decl, manifestFile);
      expect(resolvedUri, equals(entrypointFile.uri));
    });

    test('resolves entrypoint via package_config.json when path omitted', () {
      final Directory workspaceDir = fs.directory('/workspace')..createSync();
      final Directory appDir = workspaceDir.childDirectory('app')..createSync();
      final File manifestFile = appDir.childFile('flutter_extensions.yaml')
        ..writeAsStringSync('''
extensions:
  external_pkg:
    enabled: true
''');

      final Directory externalPkgDir = fs.directory('/cache/hosted/pub.dev/external_pkg-1.0.0')
        ..createSync(recursive: true);
      final File entrypointFile =
          externalPkgDir.childDirectory('bin').childFile('external_pkg.dart')
            ..createSync(recursive: true);

      // Setup package_config.json at workspaceDir
      final File packageConfigFile =
          workspaceDir.childDirectory('.dart_tool').childFile('package_config.json')
            ..createSync(recursive: true);
      packageConfigFile.writeAsStringSync('''
{
  "configVersion": 2,
  "packages": [
    {
      "name": "external_pkg",
      "rootUri": "${externalPkgDir.uri}",
      "packageUri": "lib/",
      "languageVersion": "3.5"
    }
  ]
}
''');

      const decl = ExtensionDeclaration(name: 'external_pkg');
      final Uri? resolvedUri = finder.resolveExtensionEntrypoint(decl, manifestFile);
      expect(resolvedUri, equals(entrypointFile.uri));
    });

    test('resolves entrypoint via package_config.json when rootUri lacks trailing slash', () {
      final Directory workspaceDir = fs.directory('/workspace_no_slash')..createSync();
      final Directory appDir = workspaceDir.childDirectory('app')..createSync();
      final File manifestFile = appDir.childFile('flutter_extensions.yaml')
        ..writeAsStringSync('''
extensions:
  external_pkg:
    enabled: true
''');

      final Directory externalPkgDir = fs.directory('/cache/hosted/pub.dev/external_pkg-1.0.0')
        ..createSync(recursive: true);
      final File entrypointFile =
          externalPkgDir.childDirectory('bin').childFile('external_pkg.dart')
            ..createSync(recursive: true);

      // rootUri string WITHOUT trailing slash
      final String rootUriWithoutTrailingSlash = externalPkgDir.uri.toString().replaceAll(
        RegExp(r'/+$'),
        '',
      );

      final File packageConfigFile =
          workspaceDir.childDirectory('.dart_tool').childFile('package_config.json')
            ..createSync(recursive: true);
      packageConfigFile.writeAsStringSync('''
{
  "configVersion": 2,
  "packages": [
    {
      "name": "external_pkg",
      "rootUri": "$rootUriWithoutTrailingSlash",
      "packageUri": "lib/",
      "languageVersion": "3.5"
    }
  ]
}
''');

      const decl = ExtensionDeclaration(name: 'external_pkg');
      final Uri? resolvedUri = finder.resolveExtensionEntrypoint(decl, manifestFile);
      expect(resolvedUri, equals(entrypointFile.uri));
    });

    test('normalizes Windows backslashes in entrypoint path', () {
      final Directory workspaceDir = fs.directory('/workspace_win')..createSync();
      final Directory appDir = workspaceDir.childDirectory('app')..createSync();
      final File manifestFile = appDir.childFile('flutter_extensions.yaml')
        ..writeAsStringSync(r'''
extensions:
  win_pkg:
    entrypoint: bin\custom_entry.dart
''');

      final Directory pkgDir = fs.directory('/packages/win_pkg')..createSync(recursive: true);
      final File entrypointFile = pkgDir.childDirectory('bin').childFile('custom_entry.dart')
        ..createSync(recursive: true);

      final File packageConfigFile =
          workspaceDir.childDirectory('.dart_tool').childFile('package_config.json')
            ..createSync(recursive: true);
      packageConfigFile.writeAsStringSync('''
{
  "configVersion": 2,
  "packages": [
    {
      "name": "win_pkg",
      "rootUri": "${pkgDir.uri}",
      "packageUri": "lib/",
      "languageVersion": "3.5"
    }
  ]
}
''');

      const decl = ExtensionDeclaration(name: 'win_pkg', entrypoint: r'bin\custom_entry.dart');
      final Uri? resolvedUri = finder.resolveExtensionEntrypoint(decl, manifestFile);
      expect(resolvedUri, equals(entrypointFile.uri));
    });

    test('findManifestFiles handles relative startDir safely without infinite loop', () {
      final Directory relativeDir = fs.directory('relative_proj');
      relativeDir.createSync(recursive: true);
      relativeDir.childFile('.git').createSync();
      relativeDir.childFile('flutter_extensions.yaml').writeAsStringSync('extensions: []');

      final List<File> files = finder.findManifestFiles(relativeDir);
      expect(files, hasLength(1));
    });

    test('returns null when entrypoint file does not exist', () {
      final Directory projectDir = fs.directory('/missing_entrypoint_proj')..createSync();
      final File manifestFile = projectDir.childFile('flutter_extensions.yaml')
        ..writeAsStringSync('''
extensions:
  missing_entry:
    path: some_pkg
''');

      const decl = ExtensionDeclaration(name: 'missing_entry', path: 'some_pkg');
      final Uri? resolvedUri = finder.resolveExtensionEntrypoint(decl, manifestFile);
      expect(resolvedUri, isNull);
    });

    test('returns null when package is missing in package_config.json', () {
      final Directory workspaceDir = fs.directory('/missing_pkg_workspace')..createSync();
      final File manifestFile = workspaceDir.childFile('flutter_extensions.yaml')
        ..writeAsStringSync('''
extensions:
  absent_pkg:
    enabled: true
''');

      final File packageConfigFile =
          workspaceDir.childDirectory('.dart_tool').childFile('package_config.json')
            ..createSync(recursive: true);
      packageConfigFile.writeAsStringSync('''
{
  "configVersion": 2,
  "packages": []
}
''');

      const decl = ExtensionDeclaration(name: 'absent_pkg');
      final Uri? resolvedUri = finder.resolveExtensionEntrypoint(decl, manifestFile);
      expect(resolvedUri, isNull);
    });

    test('throws FormatException with SourceSpan on non-string scalar name key in map schema', () {
      final File manifestFile = fs.file('/invalid_key_manifest.yaml')
        ..writeAsStringSync('''
extensions:
  123:
    enabled: true
''');

      expect(
        () => finder.parseManifest(manifestFile),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Extension name key must be a string'),
          ),
        ),
      );
    });

    test('throws FormatException with SourceSpan on invalid enabled type', () {
      final File manifestFile = fs.file('/invalid_enabled_manifest.yaml')
        ..writeAsStringSync('''
extensions:
  my_pkg:
    enabled: "true"
''');

      expect(
        () => finder.parseManifest(manifestFile),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Extension "enabled" must be a boolean'),
          ),
        ),
      );
    });

    test('throws FormatException with SourceSpan on invalid supportedPlatforms item', () {
      final File manifestFile = fs.file('/invalid_platforms_manifest.yaml')
        ..writeAsStringSync('''
extensions:
  my_pkg:
    supportedPlatforms:
      - 123
''');

      expect(
        () => finder.parseManifest(manifestFile),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Platform entry must be a string'),
          ),
        ),
      );
    });

    test('normalizes supportedPlatforms to lowercase', () {
      final File manifestFile = fs.file('/case_platforms_manifest.yaml')
        ..writeAsStringSync('''
extensions:
  my_pkg:
    supportedPlatforms:
      - Linux
      - MacOS
      - Windows
''');

      final ExtensionManifest manifest = finder.parseManifest(manifestFile);
      expect(manifest.extensions.single.supportedPlatforms, <String>['linux', 'macos', 'windows']);
    });

    test('findPackageConfig traverses upward and stops at sentinel boundaries', () {
      final Directory workspaceDir = fs.directory('/boundary_test')..createSync();
      workspaceDir.childFile('.git').createSync();
      final Directory subDir = workspaceDir.childDirectory('sub').childDirectory('inner')
        ..createSync(recursive: true);

      // No package_config.json yet: returns null when reaching .git
      expect(finder.findPackageConfig(subDir), isNull);

      // Create package_config.json at workspace root
      final File packageConfigFile =
          workspaceDir.childDirectory('.dart_tool').childFile('package_config.json')
            ..createSync(recursive: true);
      packageConfigFile.writeAsStringSync('{"configVersion": 2, "packages": []}');

      expect(finder.findPackageConfig(subDir)?.path, equals(packageConfigFile.path));
    });

    test('findPackageConfig stops at pub workspace root', () {
      final Directory rootDir = fs.directory('/ws_root')..createSync();
      rootDir.childFile('pubspec.yaml').writeAsStringSync('workspace:\n  - pkg_a\n');
      final Directory childDir = rootDir.childDirectory('pkg_a')..createSync();

      expect(finder.findPackageConfig(childDir), isNull);

      final File packageConfigFile =
          rootDir.childDirectory('.dart_tool').childFile('package_config.json')
            ..createSync(recursive: true);
      packageConfigFile.writeAsStringSync('{"configVersion": 2, "packages": []}');

      expect(finder.findPackageConfig(childDir)?.path, equals(packageConfigFile.path));
    });

    test('findPackageConfig handles relative paths', () {
      final Directory relDir = fs.directory('rel_pkg_test')..createSync(recursive: true);
      final File pkgConfigFile =
          relDir.childDirectory('.dart_tool').childFile('package_config.json')
            ..createSync(recursive: true);
      pkgConfigFile.writeAsStringSync('{"configVersion": 2, "packages": []}');

      expect(finder.findPackageConfig(relDir)?.path, equals(pkgConfigFile.absolute.path));
    });

    test('loadMergedDeclarationsWithFiles associates each declaration with originating file', () {
      final Directory wsDir = fs.directory('/merge_files_ws')..createSync();
      final File rootManifest = wsDir.childFile('flutter_extensions.yaml')
        ..writeAsStringSync('''
extensions:
  ext_root_only:
    entrypoint: bin/root.dart
  ext_shared:
    entrypoint: bin/shared_root.dart
''');

      final Directory appDir = wsDir.childDirectory('app')..createSync();
      final File leafManifest = appDir.childFile('flutter_extensions.yaml')
        ..writeAsStringSync('''
extensions:
  ext_shared:
    entrypoint: bin/shared_leaf.dart
  ext_leaf_only:
    entrypoint: bin/leaf.dart
''');

      final Map<String, ({ExtensionDeclaration declaration, File manifestFile})> merged = finder
          .loadMergedDeclarationsWithFiles(<File>[rootManifest, leafManifest]);

      expect(merged.keys, containsAll(<String>['ext_root_only', 'ext_shared', 'ext_leaf_only']));
      expect(merged['ext_root_only']!.manifestFile.path, equals(rootManifest.path));
      expect(merged['ext_leaf_only']!.manifestFile.path, equals(leafManifest.path));
      // Leaf overrides root
      expect(merged['ext_shared']!.manifestFile.path, equals(leafManifest.path));
      expect(merged['ext_shared']!.declaration.entrypoint, equals('bin/shared_leaf.dart'));
    });
  });
}

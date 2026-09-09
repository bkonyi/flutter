// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:test/test.dart';

void main() {
  group('Manifest Core Models', () {
    test('ExtensionDeclaration serializes and deserializes correctly', () {
      const declaration = ExtensionDeclaration(
        name: 'custom_device_extension',
        description: 'Custom device support for Flutter',
        entrypoint: 'bin/custom_device.dart',
        path: '../packages/custom_device',
        supportedPlatforms: <String>['linux', 'macos'],
      );

      final Map<String, Object?> map = declaration.toMap();
      expect(map['name'], 'custom_device_extension');
      expect(map['description'], 'Custom device support for Flutter');
      expect(map['enabled'], isTrue);
      expect(map['entrypoint'], 'bin/custom_device.dart');
      expect(map['path'], '../packages/custom_device');
      expect(map['supportedPlatforms'], <String>['linux', 'macos']);

      final parsed = ExtensionDeclaration.fromJson(map);
      expect(parsed, equals(declaration));
    });

    test('ExtensionDeclaration applies default values', () {
      final json = <String, Object?>{'name': 'minimal_ext'};
      final declaration = ExtensionDeclaration.fromJson(json);

      expect(declaration.name, 'minimal_ext');
      expect(declaration.description, isNull);
      expect(declaration.enabled, isTrue);
      expect(declaration.entrypoint, isNull);
      expect(declaration.path, isNull);
      expect(declaration.supportedPlatforms, isNull);
    });

    test('ExtensionDeclaration throws on missing name', () {
      expect(() => ExtensionDeclaration.fromJson(const <String, Object?>{}), throwsFormatException);
    });

    test('ExtensionManifest serializes and deserializes list of declarations', () {
      const manifest = ExtensionManifest(
        extensions: <ExtensionDeclaration>[
          ExtensionDeclaration(name: 'ext1', entrypoint: 'bin/ext1.dart'),
          ExtensionDeclaration(name: 'ext2', enabled: false),
        ],
      );

      final Map<String, Object?> map = manifest.toMap();
      expect(map['extensions'], isA<List<Object?>>());

      final parsed = ExtensionManifest.fromJson(map);
      expect(parsed, equals(manifest));
    });

    test('ExtensionManifest parses map representation with key as extension name', () {
      final json = <String, Object?>{
        'extensions': <String, Object?>{
          'linux_custom': <String, Object?>{
            'path': '../linux_custom',
            'entrypoint': 'bin/main.dart',
          },
        },
      };

      final manifest = ExtensionManifest.fromJson(json);
      expect(manifest.extensions, hasLength(1));
      final ExtensionDeclaration declaration = manifest.extensions.first;
      expect(declaration.name, 'linux_custom');
      expect(declaration.path, '../linux_custom');
      expect(declaration.entrypoint, 'bin/main.dart');
      expect(declaration.enabled, isTrue);
    });

    test('ExtensionManifest throws on invalid list entry', () {
      final json = <String, Object?>{
        'extensions': <Object?>['not_a_map'],
      };
      expect(() => ExtensionManifest.fromJson(json), throwsFormatException);
    });

    test('ExtensionDeclaration and ExtensionManifest equality and hashCode', () {
      const decl1 = ExtensionDeclaration(
        name: 'ext',
        description: 'desc',
        supportedPlatforms: <String>['linux'],
      );
      const decl2 = ExtensionDeclaration(
        name: 'ext',
        description: 'desc',
        supportedPlatforms: <String>['linux'],
      );
      const decl3 = ExtensionDeclaration(
        name: 'ext',
        description: 'desc',
        supportedPlatforms: <String>['macos'],
      );

      expect(decl1, equals(decl2));
      expect(decl1.hashCode, equals(decl2.hashCode));
      expect(decl1, isNot(equals(decl3)));

      const manifest1 = ExtensionManifest(extensions: <ExtensionDeclaration>[decl1]);
      const manifest2 = ExtensionManifest(extensions: <ExtensionDeclaration>[decl2]);
      const manifest3 = ExtensionManifest(extensions: <ExtensionDeclaration>[decl3]);

      expect(manifest1, equals(manifest2));
      expect(manifest1.hashCode, equals(manifest2.hashCode));
      expect(manifest1, isNot(equals(manifest3)));
    });
  });
}

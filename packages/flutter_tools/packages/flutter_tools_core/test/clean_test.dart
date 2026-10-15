// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:test/test.dart';

void main() {
  group('CleanEnvironment', () {
    test('serializes and deserializes correctly', () {
      final env = CleanEnvironment(
        buildDir: Uri.directory('/path/to/project/build'),
        projectRoot: Uri.directory('/path/to/project'),
      );

      final Map<String, Object?> json = env.toMap();
      expect(json, <String, Object?>{
        'projectRoot': 'file:///path/to/project/',
        'buildDir': 'file:///path/to/project/build/',
      });

      final deserialized = CleanEnvironment.fromJson(json);
      expect(deserialized, equals(env));
      expect(deserialized.hashCode, equals(env.hashCode));
      expect(
        deserialized.toString(),
        'CleanEnvironment(projectRoot: file:///path/to/project/, '
        'buildDir: file:///path/to/project/build/)',
      );
    });

    test('throws ArgumentError on missing or relative paths', () {
      expect(() => CleanEnvironment.fromJson(const <String, Object?>{}), throwsArgumentError);
      expect(
        () =>
            CleanEnvironment.fromJson(const <String, Object?>{'projectRoot': 'file:///only/root'}),
        throwsArgumentError,
      );
      expect(
        () => CleanEnvironment.fromJson(const <String, Object?>{
          'projectRoot': 'relative/path',
          'buildDir': 'file:///path/to/project/build/',
        }),
        throwsArgumentError,
      );
    });
  });
}

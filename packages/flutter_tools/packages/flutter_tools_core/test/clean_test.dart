// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:test/test.dart';

void main() {
  group('CleanEnvironment', () {
    test('serializes and deserializes correctly', () {
      final environment = CleanEnvironment(
        buildDir: Uri.parse('file:///workspace/project/build'),
        projectRoot: Uri.parse('file:///workspace/project'),
      );

      final Map<String, Object?> json = environment.toJson();
      expect(json['buildDir'], 'file:///workspace/project/build');
      expect(json['projectRoot'], 'file:///workspace/project');

      final parsed = CleanEnvironment.fromJson(json);
      expect(parsed, equals(environment));
      expect(parsed.hashCode, equals(environment.hashCode));
      expect(parsed.toMap(), equals(json));
    });

    test('equality respects all fields', () {
      final a = CleanEnvironment(
        buildDir: Uri.parse('file:///workspace/project/build'),
        projectRoot: Uri.parse('file:///workspace/project'),
      );
      final b = CleanEnvironment(
        buildDir: Uri.parse('file:///workspace/project/build'),
        projectRoot: Uri.parse('file:///workspace/project'),
      );
      final c = CleanEnvironment(
        buildDir: Uri.parse('file:///workspace/other/build'),
        projectRoot: Uri.parse('file:///workspace/project'),
      );
      final d = CleanEnvironment(
        buildDir: Uri.parse('file:///workspace/project/build'),
        projectRoot: Uri.parse('file:///workspace/other'),
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
    });
  });
}

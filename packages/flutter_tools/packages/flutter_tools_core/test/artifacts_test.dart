// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:test/test.dart';

void main() {
  group('ArtifactDependency', () {
    test('serializes and deserializes correctly', () {
      const dependency = ArtifactDependency(
        hostPlatform: 'linux-x64',
        name: 'custom_engine.so',
        sha256Checksums: <String, String>{
          'linux-x64': '6be7a016b110e53a35b1df4000305a41bfd1ff394503cecfec742617d526eef4',
        },
        targetArchitecture: 'x64',
        targetPlatform: 'linux',
      );

      final Map<String, Object?> json = dependency.toJson();
      expect(json['hostPlatform'], 'linux-x64');
      expect(json['name'], 'custom_engine.so');
      expect(json['targetArchitecture'], 'x64');
      expect(json['targetPlatform'], 'linux');
      expect(json['sha256Checksums'], <String, String>{
        'linux-x64': '6be7a016b110e53a35b1df4000305a41bfd1ff394503cecfec742617d526eef4',
      });

      final parsed = ArtifactDependency.fromJson(json);
      expect(parsed, equals(dependency));
      expect(parsed.hashCode, equals(dependency.hashCode));
    });

    test('equality respects all fields', () {
      const a = ArtifactDependency(
        hostPlatform: 'linux-x64',
        name: 'engine.so',
        sha256Checksums: <String, String>{'linux-x64': 'hash1'},
        targetArchitecture: 'x64',
        targetPlatform: 'linux',
      );
      const b = ArtifactDependency(
        hostPlatform: 'linux-x64',
        name: 'engine.so',
        sha256Checksums: <String, String>{'linux-x64': 'hash1'},
        targetArchitecture: 'x64',
        targetPlatform: 'linux',
      );
      const c = ArtifactDependency(
        hostPlatform: 'darwin-arm64',
        name: 'engine.so',
        sha256Checksums: <String, String>{'linux-x64': 'hash1'},
        targetArchitecture: 'x64',
        targetPlatform: 'linux',
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}

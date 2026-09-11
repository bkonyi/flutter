// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';
import 'package:flutter_tools_extension_linux_prototype/src/clean.dart';
import 'package:json_rpc_2/error_code.dart' as error_code;
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:test/test.dart';

final class _TestCleanService extends CleanService {
  CleanEnvironment? lastEnvironment;

  @override
  Future<void> clean(CleanEnvironment environment) async {
    lastEnvironment = environment;
  }
}

void main() {
  group('CleanService', () {
    test('initializes RPC handlers and serves clean', () async {
      final service = _TestCleanService();
      final Map<String, ExtensionRpcHandler> handlers = await service.initialize();

      expect(service.namespace, 'clean');
      expect(handlers.keys, contains('clean'));

      final Object? result = await handlers['clean']!(<String, Object?>{
        'buildDir': 'file:///workspace/build/',
        'projectRoot': 'file:///workspace/',
      });

      expect(result, <String, Object?>{'success': true});
      expect(service.lastEnvironment, isNotNull);
      expect(service.lastEnvironment!.buildDir, Uri.parse('file:///workspace/build/'));
      expect(service.lastEnvironment!.projectRoot, Uri.parse('file:///workspace/'));
    });

    test('throws RpcException when clean receives invalid parameters', () async {
      final service = _TestCleanService();
      final Map<String, ExtensionRpcHandler> handlers = await service.initialize();

      await expectLater(
        handlers['clean']!(<String, Object?>{'buildDir': 123}),
        throwsA(
          isA<RpcException>().having(
            (RpcException e) => e.code,
            'code',
            equals(error_code.INVALID_PARAMS),
          ),
        ),
      );
    });
  });

  group('CleanServiceClient', () {
    test('clean sends clean.clean request with serialized parameters', () async {
      final requests = <Map<String, Object?>>[];
      final client = CleanServiceClient((String method, [Object? params]) async {
        requests.add(<String, Object?>{'method': method, 'params': params});
        return <String, Object?>{'success': true};
      });

      final environment = CleanEnvironment(
        buildDir: Uri.parse('file:///workspace/build/'),
        projectRoot: Uri.parse('file:///workspace/'),
      );

      await client.clean(environment);

      expect(requests, hasLength(1));
      expect(requests.first['method'], CleanService.cleanMethod);
      final params = requests.first['params']! as Map<String, Object?>;
      expect(params['buildDir'], 'file:///workspace/build/');
      expect(params['projectRoot'], 'file:///workspace/');
    });
  });

  group('LinuxCleanService', () {
    test('clean removes linux subdirectory inside build directory', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('linux_clean_test_');
      try {
        final Directory buildDir = tempDir.createTempSync('build_');
        final linuxBuildDir = Directory('${buildDir.path}/linux')..createSync(recursive: true);
        final dummyFile = File('${linuxBuildDir.path}/output.bin')..writeAsStringSync('data');
        expect(dummyFile.existsSync(), isTrue);

        final service = LinuxCleanService();
        final environment = CleanEnvironment(buildDir: buildDir.uri, projectRoot: tempDir.uri);

        await service.clean(environment);

        expect(linuxBuildDir.existsSync(), isFalse);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}

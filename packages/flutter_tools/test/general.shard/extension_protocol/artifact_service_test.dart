// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';
import 'package:flutter_tools_extension_linux_prototype/src/artifact.dart';
import 'package:json_rpc_2/error_code.dart' as error_code;
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:test/test.dart';

final class _TestArtifactService extends ArtifactService {
  _TestArtifactService({this.artifacts = const <ArtifactDependency>{}});

  @override
  final Set<ArtifactDependency> artifacts;

  final downloadedArtifacts = <String>{};
  BuildMode? lastBuildMode;
  Uri? lastDestinationDirectory;
  HostPlatform? lastHostPlatform;
  TargetPlatform? lastTargetPlatform;

  @override
  Future<void> downloadArtifacts(
    Set<String> artifactNames, {
    required BuildMode buildMode,
    required Uri destinationDirectory,
    required HostPlatform hostPlatform,
    required TargetPlatform targetPlatform,
  }) async {
    downloadedArtifacts.addAll(artifactNames);
    lastBuildMode = buildMode;
    lastDestinationDirectory = destinationDirectory;
    lastHostPlatform = hostPlatform;
    lastTargetPlatform = targetPlatform;
  }
}

void main() {
  group('ArtifactService', () {
    test('initializes RPC handlers and serves getArtifacts', () async {
      const dependency = ArtifactDependency(
        hostPlatform: 'linux-x64',
        name: 'custom-engine.so',
        sha256Checksums: <String, String>{'linux-x64': 'hash123'},
        targetArchitecture: 'x64',
        targetPlatform: 'linux',
      );
      final service = _TestArtifactService(artifacts: <ArtifactDependency>{dependency});
      final Map<String, ExtensionRpcHandler> handlers = await service.initialize();

      expect(service.namespace, 'artifact');
      expect(handlers.keys, containsAll(<String>['getArtifacts', 'downloadArtifacts']));

      final Object? result = await handlers['getArtifacts']!(<String, Object?>{});
      expect(result, isA<List<Object?>>());
      final list = result! as List<Object?>;
      expect(list, hasLength(1));
      expect((list.first! as Map<String, Object?>)['name'], 'custom-engine.so');
    });

    test('serves downloadArtifacts RPC with valid parameters', () async {
      final service = _TestArtifactService();
      final Map<String, ExtensionRpcHandler> handlers = await service.initialize();

      final Object? response = await handlers['downloadArtifacts']!(<String, Object?>{
        'artifactNames': <String>['fileA', 'fileB'],
        'buildMode': 'debug',
        'destinationDirectory': 'file:///tmp/artifacts/',
        'hostPlatform': 'linux-x64',
        'targetPlatform': 'linux-x64',
      });

      expect(response, <String, Object?>{'success': true});
      expect(service.downloadedArtifacts, <String>{'fileA', 'fileB'});
      expect(service.lastBuildMode, BuildMode.debug);
      expect(service.lastDestinationDirectory, Uri.parse('file:///tmp/artifacts/'));
      expect(service.lastHostPlatform, HostPlatform.linux_x64);
      expect(service.lastTargetPlatform, TargetPlatform.linux_x64);
    });

    test('throws RpcException when downloadArtifacts receives invalid parameters', () async {
      final service = _TestArtifactService();
      final Map<String, ExtensionRpcHandler> handlers = await service.initialize();

      await expectLater(
        handlers['downloadArtifacts']!(<String, Object?>{'artifactNames': 'invalid'}),
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

  group('ArtifactServiceClient', () {
    test('fetchArtifacts requests artifact.getArtifacts and deserializes dependencies', () async {
      final requestedMethods = <String>[];
      final client = ArtifactServiceClient((String method, [Object? params]) async {
        requestedMethods.add(method);
        return <Map<String, Object?>>[
          <String, Object?>{
            'hostPlatform': 'linux-x64',
            'name': 'libtest.so',
            'sha256Checksums': <String, String>{'linux-x64': 'hashabc'},
            'targetArchitecture': 'x64',
            'targetPlatform': 'linux',
          },
        ];
      });

      final Set<ArtifactDependency> artifacts = await client.fetchArtifacts();
      expect(requestedMethods, <String>[ArtifactService.getArtifactsMethod]);
      expect(artifacts, hasLength(1));
      expect(artifacts.first.name, 'libtest.so');
      expect(client.artifacts, equals(artifacts));
    });

    test(
      'downloadArtifacts sends artifact.downloadArtifacts request with serialized parameters',
      () async {
        final requests = <Map<String, Object?>>[];
        final client = ArtifactServiceClient((String method, [Object? params]) async {
          requests.add(<String, Object?>{'method': method, 'params': params});
          return <String, Object?>{'success': true};
        });

        await client.downloadArtifacts(
          <String>{'libtest.so'},
          buildMode: BuildMode.release,
          destinationDirectory: Uri.parse('file:///tmp/dest/'),
          hostPlatform: HostPlatform.linux_x64,
          targetPlatform: TargetPlatform.linux_x64,
        );

        expect(requests, hasLength(1));
        expect(requests.first['method'], ArtifactService.downloadArtifactsMethod);
        final params = requests.first['params']! as Map<String, Object?>;
        expect(params['artifactNames'], <String>['libtest.so']);
        expect(params['buildMode'], 'release');
        expect(params['destinationDirectory'], 'file:///tmp/dest/');
        expect(params['hostPlatform'], 'linux-x64');
        expect(params['targetPlatform'], 'linux-x64');
      },
    );
  });

  group('LinuxArtifactService', () {
    test('declares linux-headers artifact dependency', () {
      final service = LinuxArtifactService();
      expect(service.artifacts, hasLength(1));
      final ArtifactDependency dependency = service.artifacts.first;
      expect(dependency.name, 'linux-headers');
      expect(dependency.hostPlatform, 'linux-x64');
      expect(dependency.targetPlatform, 'linux');
      expect(dependency.sha256Checksums, contains('linux-x64'));
    });

    test('downloadArtifacts writes artifact files into destination directory', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('linux_artifact_test_');
      try {
        final service = LinuxArtifactService();
        await service.downloadArtifacts(
          <String>{'linux-headers'},
          buildMode: BuildMode.debug,
          destinationDirectory: tempDir.uri,
          hostPlatform: HostPlatform.linux_x64,
          targetPlatform: TargetPlatform.linux_x64,
        );

        final file = File('${tempDir.path}/linux-headers');
        expect(file.existsSync(), isTrue);
        expect(file.readAsStringSync(), 'artifact payload for linux-headers\n');
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}

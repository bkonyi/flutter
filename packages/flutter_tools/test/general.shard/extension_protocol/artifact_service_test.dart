// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';
import 'package:flutter_tools_extension_linux_prototype/src/artifact.dart';
import 'package:json_rpc_2/json_rpc_2.dart' as json_rpc;
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

final class _TestArtifactService extends ArtifactService {
  @override
  Future<List<ArtifactDependency>> downloadArtifacts({
    required HostPlatform hostPlatform,
    String? targetPlatform,
  }) async {
    return <ArtifactDependency>[
      ArtifactDependency(
        name: 'test-artifact-${hostPlatform.cliName}',
        sha256: 'deadbeef',
        url: Uri.parse('https://example.com/${hostPlatform.cliName}/artifact.zip'),
        hostPlatform: hostPlatform,
        targetPlatform: targetPlatform,
      ),
    ];
  }
}

void main() {
  group('ArtifactService & ArtifactServiceClient', () {
    late StreamController<Object?> clientToServer;
    late StreamController<Object?> serverToClient;
    late json_rpc.Peer clientPeer;
    late json_rpc.Peer serverPeer;

    setUp(() {
      clientToServer = StreamController<Object?>();
      serverToClient = StreamController<Object?>();

      final clientChannel = StreamChannel<Object?>(serverToClient.stream, clientToServer.sink);
      final serverChannel = StreamChannel<Object?>(clientToServer.stream, serverToClient.sink);

      clientPeer = json_rpc.Peer.withoutJson(clientChannel);
      serverPeer = json_rpc.Peer.withoutJson(serverChannel);
    });

    tearDown(() async {
      await clientPeer.close();
      await serverPeer.close();
    });

    test('registers artifact capability and handles downloadArtifacts RPC', () async {
      final extension = FlutterToolsExtension(
        extensionName: 'test_artifact_ext',
        services: <ToolExtensionService>[_TestArtifactService()],
      );
      await extension.register(serverPeer);

      unawaited(serverPeer.listen());
      unawaited(clientPeer.listen());

      final Object? rawCaps = await clientPeer.sendRequest('extension.getCapabilities');
      final capabilities = FlutterToolExtensionCapabilities.fromJson(
        (rawCaps! as Map<Object?, Object?>).cast<String, Object?>(),
      );
      expect(capabilities.services, contains(ArtifactService.serviceNamespace));
      expect(capabilities.extensionName, 'test_artifact_ext');

      final client = ArtifactServiceClient(
        (String method, [Map<String, Object?>? params]) => clientPeer.sendRequest(method, params),
      );

      final List<ArtifactDependency> deps = await client.downloadArtifacts(
        hostPlatform: HostPlatform.linux_x64,
        targetPlatform: 'linux-x64',
      );

      expect(deps, hasLength(1));
      expect(deps.first.name, 'test-artifact-linux-x64');
      expect(deps.first.url, Uri.parse('https://example.com/linux-x64/artifact.zip'));
      expect(deps.first.sha256, 'deadbeef');
      expect(deps.first.hostPlatform, HostPlatform.linux_x64);
      expect(deps.first.targetPlatform, 'linux-x64');
    });

    test('throws RpcException on missing or invalid hostPlatform', () async {
      final extension = FlutterToolsExtension(
        services: <ToolExtensionService>[_TestArtifactService()],
      );
      await extension.register(serverPeer);

      unawaited(serverPeer.listen());
      unawaited(clientPeer.listen());

      await expectLater(
        clientPeer.sendRequest(ArtifactService.downloadArtifactsMethod, const <String, Object?>{}),
        throwsA(isA<json_rpc.RpcException>()),
      );

      await expectLater(
        clientPeer.sendRequest(ArtifactService.downloadArtifactsMethod, const <String, Object?>{
          ArtifactService.hostPlatformParam: 'invalid-host',
        }),
        throwsA(isA<json_rpc.RpcException>()),
      );

      await expectLater(
        clientPeer.sendRequest(ArtifactService.downloadArtifactsMethod, const <String, Object?>{
          ArtifactService.hostPlatformParam: 'linux-x64',
          ArtifactService.targetPlatformParam: 123,
        }),
        throwsA(isA<json_rpc.RpcException>()),
      );
    });

    test('LinuxArtifactService returns expected default Linux artifact over RPC', () async {
      final extension = FlutterToolsExtension(
        extensionName: 'flutter_tools_extension_linux_prototype',
        services: <ToolExtensionService>[LinuxArtifactService()],
      );
      await extension.register(serverPeer);

      unawaited(serverPeer.listen());
      unawaited(clientPeer.listen());

      final client = ArtifactServiceClient(
        (String method, [Map<String, Object?>? params]) => clientPeer.sendRequest(method, params),
      );

      final List<ArtifactDependency> linuxDeps = await client.downloadArtifacts(
        hostPlatform: HostPlatform.linux_x64,
        targetPlatform: 'linux-x64',
      );
      expect(linuxDeps, hasLength(1));
      expect(linuxDeps.first.name, 'linux-x64-custom-artifact');
      expect(linuxDeps.first.hostPlatform, HostPlatform.linux_x64);
      expect(linuxDeps.first.targetPlatform, 'linux-x64');

      final List<ArtifactDependency> macosDeps = await client.downloadArtifacts(
        hostPlatform: HostPlatform.darwin_x64,
      );
      expect(macosDeps, isEmpty);
    });
  });
}

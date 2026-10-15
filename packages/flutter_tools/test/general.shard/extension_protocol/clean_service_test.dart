// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';
import 'package:flutter_tools_extension_linux_prototype/src/clean.dart';
import 'package:json_rpc_2/json_rpc_2.dart' as json_rpc;
import 'package:path/path.dart' as p;
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

final class _TestCleanService extends CleanService {
  CleanEnvironment? lastCleanedEnvironment;

  @override
  Future<void> clean(CleanEnvironment environment) async {
    lastCleanedEnvironment = environment;
  }
}

void main() {
  group('CleanService & CleanServiceClient', () {
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

    test('registers clean capability and handles clean RPC', () async {
      final service = _TestCleanService();
      final extension = FlutterToolsExtension(
        extensionName: 'test_clean_ext',
        services: <ToolExtensionService>[service],
      );
      await extension.register(serverPeer);

      unawaited(serverPeer.listen());
      unawaited(clientPeer.listen());

      final Object? rawCaps = await clientPeer.sendRequest('extension.getCapabilities');
      final capabilities = FlutterToolExtensionCapabilities.fromJson(
        (rawCaps! as Map<Object?, Object?>).cast<String, Object?>(),
      );
      expect(capabilities.services, contains(CleanService.serviceNamespace));

      final client = CleanServiceClient(
        (String method, [Map<String, Object?>? params]) => clientPeer.sendRequest(method, params),
      );

      final env = CleanEnvironment(
        buildDir: Uri.directory('/tmp/project/build'),
        projectRoot: Uri.directory('/tmp/project'),
      );
      await client.clean(env);

      expect(service.lastCleanedEnvironment, equals(env));
    });

    test('throws RpcException on missing or invalid environment parameter', () async {
      final extension = FlutterToolsExtension(
        services: <ToolExtensionService>[_TestCleanService()],
      );
      await extension.register(serverPeer);

      unawaited(serverPeer.listen());
      unawaited(clientPeer.listen());

      await expectLater(
        clientPeer.sendRequest(CleanService.cleanMethod, const <String, Object?>{}),
        throwsA(isA<json_rpc.RpcException>()),
      );

      await expectLater(
        clientPeer.sendRequest(CleanService.cleanMethod, const <String, Object?>{
          CleanService.environmentParam: <String, Object?>{'projectRoot': 'relative/path'},
        }),
        throwsA(isA<json_rpc.RpcException>()),
      );
    });

    test('LinuxCleanService deletes linux build and ephemeral directories over RPC', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('flutter_linux_clean_test.');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final buildDir = Directory(p.join(tempDir.path, 'build'))..createSync(recursive: true);
      final linuxBuildDir = Directory(p.join(buildDir.path, 'linux'))..createSync(recursive: true);
      File(p.join(linuxBuildDir.path, 'app.so')).writeAsStringSync('binary');

      final linuxEphemeralDir = Directory(p.join(tempDir.path, 'linux', 'flutter', 'ephemeral'))
        ..createSync(recursive: true);
      File(p.join(linuxEphemeralDir.path, 'generated_config.cmake')).writeAsStringSync('cmake');

      final extension = FlutterToolsExtension(
        extensionName: 'flutter_tools_extension_linux_prototype',
        services: <ToolExtensionService>[LinuxCleanService()],
      );
      await extension.register(serverPeer);

      unawaited(serverPeer.listen());
      unawaited(clientPeer.listen());

      final client = CleanServiceClient(
        (String method, [Map<String, Object?>? params]) => clientPeer.sendRequest(method, params),
      );

      await client.clean(CleanEnvironment(buildDir: buildDir.uri, projectRoot: tempDir.uri));

      expect(linuxBuildDir.existsSync(), isFalse);
      expect(linuxEphemeralDir.existsSync(), isFalse);
      expect(buildDir.existsSync(), isTrue);
    });
  });
}

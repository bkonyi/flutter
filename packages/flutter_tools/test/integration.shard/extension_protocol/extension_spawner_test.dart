// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/base/signals.dart';
import 'package:flutter_tools/src/experimental/extension_discovery.dart';
import 'package:test/test.dart';

void main() {
  group('ExtensionConnection.spawnUri (integration)', () {
    late Directory tempDir;
    late BufferLogger logger;
    late Uri packageConfigUri;
    late FileSystem localFs;

    setUp(() {
      localFs = LocalFileSystem.test(signals: Signals.test(shutdownHooks: ShutdownHooks()));
      tempDir = localFs.systemTempDirectory.createTempSync('spawn_uri_integration_test_');
      logger = BufferLogger.test();
      final File packageConfigFile = localFs.currentDirectory
          .childDirectory('.dart_tool')
          .childFile('package_config.json');
      packageConfigUri = packageConfigFile.uri;
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } on Object {
        // Best effort cleanup.
      }
    });

    test('spawns isolate from URI and exchanges capabilities over RPC', () async {
      final File scriptFile = tempDir.childFile('valid_extension.dart');
      scriptFile.writeAsStringSync(r'''
import 'dart:isolate';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';

class _EchoService extends ToolExtensionService {
  @override
  String get namespace => 'echo';

  @override
  Future<Map<String, ExtensionRpcHandler>> initialize() async {
    return <String, ExtensionRpcHandler>{
      'ping': (Map<String, Object?> params) async => 'pong',
    };
  }
}

void main(List<String> args, Object? message) {
  ToolExtensionEntryPoint.runMain(
    args,
    message,
    <ToolExtensionService>[_EchoService()],
    supportedPlatforms: <String>{'linux', 'macos', 'windows'},
  );
}
''');

      final ExtensionConnection connection = await ExtensionConnection.spawnUri(
        scriptFile.uri,
        logger: logger,
        packageConfigUri: packageConfigUri,
      );
      addTearDown(connection.dispose);

      expect(connection.capabilities.services, contains('echo'));
      expect(connection.capabilities.supportsHostPlatform('linux'), isTrue);

      final Object? response = await connection.sendRequest('echo.ping');
      expect(response, 'pong');
    });

    test('throws TimeoutException and cleans up when handshake times out', () async {
      final File hangingScript = tempDir.childFile('hanging_extension.dart');
      hangingScript.writeAsStringSync(r'''
import 'dart:async';

void main(List<String> args, Object? message) {
  // Deliberately never connects handshake port.
  Timer(const Duration(minutes: 10), () {});
}
''');

      expect(
        () => ExtensionConnection.spawnUri(
          hangingScript.uri,
          logger: logger,
          packageConfigUri: packageConfigUri,
          timeout: const Duration(milliseconds: 200),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('throws StateError when spawned isolate fails during startup', () async {
      final File failingScript = tempDir.childFile('failing_extension.dart');
      failingScript.writeAsStringSync(r'''
void main(List<String> args, Object? message) {
  throw StateError('Intentional crash on isolate start');
}
''');

      expect(
        () => ExtensionConnection.spawnUri(
          failingScript.uri,
          logger: logger,
          packageConfigUri: packageConfigUri,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}

// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/commands/extensions.dart';
import 'package:flutter_tools/src/experimental/extension_discovery.dart';
import 'package:flutter_tools/src/experimental/extension_registry.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';
import 'package:json_rpc_2/json_rpc_2.dart' as json_rpc;
import 'package:stream_channel/stream_channel.dart';

import '../../src/context.dart';
import '../../src/test_flutter_command_runner.dart';

ExtensionConnection _createFakeConnection({
  required ToolExtensionCapabilities capabilities,
  required Logger logger,
}) {
  final serverController = StreamController<Object?>();
  final clientController = StreamController<Object?>();
  final serverChannel = StreamChannel<Object?>(clientController.stream, serverController.sink);
  final clientChannel = StreamChannel<Object?>(serverController.stream, clientController.sink);

  final serverPeer = json_rpc.Peer.withoutJson(serverChannel);
  unawaited(serverPeer.listen());

  final clientPeer = json_rpc.Peer.withoutJson(clientChannel);
  unawaited(clientPeer.listen());

  return ExtensionConnection.custom(capabilities: capabilities, peer: clientPeer, logger: logger);
}

void main() {
  late MemoryFileSystem fileSystem;
  late BufferLogger logger;
  late FakePlatform platform;
  late FakeProcessManager processManager;
  late GlobalExtensionRegistry registry;
  late ExtensionsCommand command;
  late CommandRunner<void> runner;

  setUp(() {
    fileSystem = MemoryFileSystem.test();
    logger = BufferLogger.test();
    platform = FakePlatform(
      environment: <String, String>{'DART_DATA_HOME': '/dart_data_home'},
      version: '3.3.0',
    );
    processManager = FakeProcessManager.list(<FakeCommand>[]);
    registry = GlobalExtensionRegistry(
      fileSystem: fileSystem,
      logger: logger,
      platform: platform,
      processManager: processManager,
      spawner:
          (
            Uri uri, {
            required Logger logger,
            List<String> args = const <String>[],
            Uri? packageConfigUri,
            Duration timeout = const Duration(seconds: 2),
          }) async {
            return _createFakeConnection(
              capabilities: const ToolExtensionCapabilities(
                services: <String>['custom-command'],
                extensionName: 'my_extension',
              ),
              logger: logger,
            );
          },
    );
    command = ExtensionsCommand(extensionRegistry: registry, logger: logger);
    runner = createTestCommandRunner(command);
  });

  group('ExtensionsCommand', () {
    testUsingContext('has correct name and description', () {
      expect(command.name, 'extensions');
      expect(command.description, contains('Manage global Flutter tool extensions.'));
      expect(
        command.subcommands.keys,
        unorderedEquals(<String>['list', 'install', 'uninstall', 'enable', 'disable', 'upgrade']),
      );
    });
  });

  group('extensions list', () {
    testUsingContext('prints message when no extensions installed', () async {
      await runner.run(<String>['extensions', 'list']);

      expect(logger.statusText, contains('No global extensions installed.'));
    });

    testUsingContext('prints entries when extensions installed', () async {
      registry.register(
        const GlobalExtensionEntry(
          name: 'test_ext',
          version: '1.2.3',
          source: 'path:/path/to/test_ext',
          installDir: '/dart_data_home/flutter_tool_extensions/test_ext',
          entrypointPath:
              '/dart_data_home/flutter_tool_extensions/test_ext/bin/generated_entrypoint.dart',
          snapshotPath: '/dart_data_home/flutter_tool_extensions/test_ext/snapshot.jit',
          enabled: true,
          capabilities: ToolExtensionCapabilities(services: <String>['custom-command', 'doctor']),
          dartSdkVersion: '3.3.0',
        ),
      );

      await runner.run(<String>['extensions', 'list']);

      expect(logger.statusText, contains('Installed global extensions:'));
      expect(logger.statusText, contains('test_ext'));
      expect(logger.statusText, contains('1.2.3'));
      expect(logger.statusText, contains('[enabled]'));
      expect(logger.statusText, contains('Capabilities: custom-command, doctor'));
    });

    testUsingContext('prints JSON output with --machine', () async {
      registry.register(
        const GlobalExtensionEntry(
          name: 'test_ext',
          version: '1.2.3',
          source: 'path:/path/to/test_ext',
          installDir: '/dart_data_home/flutter_tool_extensions/test_ext',
          entrypointPath:
              '/dart_data_home/flutter_tool_extensions/test_ext/bin/generated_entrypoint.dart',
          snapshotPath: '/dart_data_home/flutter_tool_extensions/test_ext/snapshot.jit',
          enabled: true,
          capabilities: ToolExtensionCapabilities(services: <String>['custom-command']),
          dartSdkVersion: '3.3.0',
        ),
      );

      await runner.run(<String>['extensions', 'list', '--machine']);

      final dynamic decoded = jsonDecode(logger.statusText);
      expect(decoded, isA<List<dynamic>>());
      final list = decoded as List<dynamic>;
      expect(list, hasLength(1));
      final first = list.first as Map<String, dynamic>;
      expect(first['name'], 'test_ext');
      expect(first['version'], '1.2.3');
      expect(first['enabled'], isTrue);
      expect((first['capabilities'] as Map<String, dynamic>)['services'], <dynamic>[
        'custom-command',
      ]);
    });
  });

  group('extensions install', () {
    testUsingContext('fails when source argument is missing', () async {
      await expectLater(
        runner.run(<String>['extensions', 'install']),
        throwsA(
          isA<ToolExit>().having(
            (ToolExit e) => e.message,
            'message',
            contains('A source must be specified for "install".'),
          ),
        ),
      );
    });

    testUsingContext('installs path-based extension successfully', () async {
      final Directory sourceDir = fileSystem.directory('/source/my_extension')
        ..createSync(recursive: true);
      sourceDir.childFile('pubspec.yaml').writeAsStringSync('''
name: my_extension
version: 0.1.0
''');
      sourceDir.childDirectory('bin').createSync(recursive: true);
      sourceDir.childDirectory('bin').childFile('my_extension.dart').writeAsStringSync('''
void main(List<String> args) {}
''');

      processManager.addCommands(<FakeCommand>[
        const FakeCommand(
          command: <String>['dart', 'pub', 'get'],
          workingDirectory: '/dart_data_home/flutter_tool_extensions/my_extension',
        ),
        FakeCommand(
          command: const <String>[
            'dart',
            'compile',
            'jit-snapshot',
            '-o',
            '/dart_data_home/flutter_tool_extensions/my_extension/bin/generated_entrypoint.jit',
            '/dart_data_home/flutter_tool_extensions/my_extension/bin/generated_entrypoint.dart',
            '--train',
          ],
          workingDirectory: '/dart_data_home/flutter_tool_extensions/my_extension',
          onRun: (_) {
            fileSystem.file(
                '/dart_data_home/flutter_tool_extensions/my_extension/bin/generated_entrypoint.jit',
              )
              ..createSync(recursive: true)
              ..writeAsStringSync('dummy_snapshot');
          },
        ),
      ]);

      await runner.run(<String>['extensions', 'install', sourceDir.path]);

      expect(logger.statusText, contains('Successfully installed extension "my_extension"'));
      expect(registry.hasExtension('my_extension'), isTrue);
    });
  });

  group('extensions uninstall', () {
    testUsingContext('fails when name argument is missing', () async {
      await expectLater(
        runner.run(<String>['extensions', 'uninstall']),
        throwsA(
          isA<ToolExit>().having(
            (ToolExit e) => e.message,
            'message',
            contains('An extension name must be specified for "uninstall".'),
          ),
        ),
      );
    });

    testUsingContext('fails when extension not found', () async {
      await expectLater(
        runner.run(<String>['extensions', 'uninstall', 'non_existent']),
        throwsA(
          isA<ToolExit>().having(
            (ToolExit e) => e.message,
            'message',
            contains('Extension "non_existent" is not installed.'),
          ),
        ),
      );
    });

    testUsingContext('uninstalls extension successfully', () async {
      final Directory extDir = fileSystem.directory(
        '/dart_data_home/flutter_tool_extensions/my_extension',
      )..createSync(recursive: true);
      extDir.childFile('test.txt').writeAsStringSync('content');

      registry.register(
        GlobalExtensionEntry(
          name: 'my_extension',
          version: '1.0.0',
          source: 'path:/source',
          installDir: extDir.path,
          entrypointPath: extDir.childFile('entry.dart').path,
          snapshotPath: extDir.childFile('snap.jit').path,
          enabled: true,
          capabilities: const ToolExtensionCapabilities(services: <String>[]),
          dartSdkVersion: '3.3.0',
        ),
      );

      await runner.run(<String>['extensions', 'uninstall', 'my_extension']);

      expect(logger.statusText, contains('Successfully uninstalled extension "my_extension"'));
      expect(registry.hasExtension('my_extension'), isFalse);
      expect(extDir.existsSync(), isFalse);
    });
  });

  group('extensions enable', () {
    testUsingContext('fails when name argument is missing', () async {
      await expectLater(
        runner.run(<String>['extensions', 'enable']),
        throwsA(
          isA<ToolExit>().having(
            (ToolExit e) => e.message,
            'message',
            contains('An extension name must be specified for "enable".'),
          ),
        ),
      );
    });

    testUsingContext('fails when extension not found', () async {
      await expectLater(
        runner.run(<String>['extensions', 'enable', 'non_existent']),
        throwsA(
          isA<ToolExit>().having(
            (ToolExit e) => e.message,
            'message',
            contains('Extension "non_existent" is not installed.'),
          ),
        ),
      );
    });

    testUsingContext('enables disabled extension successfully', () async {
      registry.register(
        const GlobalExtensionEntry(
          name: 'my_extension',
          version: '1.0.0',
          source: 'path:/source',
          installDir: '/dart_data_home/flutter_tool_extensions/my_extension',
          entrypointPath: '/dart_data_home/flutter_tool_extensions/my_extension/entry.dart',
          snapshotPath: '/dart_data_home/flutter_tool_extensions/my_extension/snap.jit',
          enabled: false,
          capabilities: ToolExtensionCapabilities(services: <String>[]),
          dartSdkVersion: '3.3.0',
        ),
      );

      await runner.run(<String>['extensions', 'enable', 'my_extension']);

      expect(logger.statusText, contains('Enabled extension "my_extension"'));
      expect(registry.getExtension('my_extension')?.enabled, isTrue);
    });
  });

  group('extensions disable', () {
    testUsingContext('fails when name argument is missing', () async {
      await expectLater(
        runner.run(<String>['extensions', 'disable']),
        throwsA(
          isA<ToolExit>().having(
            (ToolExit e) => e.message,
            'message',
            contains('An extension name must be specified for "disable".'),
          ),
        ),
      );
    });

    testUsingContext('fails when extension not found', () async {
      await expectLater(
        runner.run(<String>['extensions', 'disable', 'non_existent']),
        throwsA(
          isA<ToolExit>().having(
            (ToolExit e) => e.message,
            'message',
            contains('Extension "non_existent" is not installed.'),
          ),
        ),
      );
    });

    testUsingContext('disables enabled extension successfully', () async {
      registry.register(
        const GlobalExtensionEntry(
          name: 'my_extension',
          version: '1.0.0',
          source: 'path:/source',
          installDir: '/dart_data_home/flutter_tool_extensions/my_extension',
          entrypointPath: '/dart_data_home/flutter_tool_extensions/my_extension/entry.dart',
          snapshotPath: '/dart_data_home/flutter_tool_extensions/my_extension/snap.jit',
          enabled: true,
          capabilities: ToolExtensionCapabilities(services: <String>[]),
          dartSdkVersion: '3.3.0',
        ),
      );

      await runner.run(<String>['extensions', 'disable', 'my_extension']);

      expect(logger.statusText, contains('Disabled extension "my_extension"'));
      expect(registry.getExtension('my_extension')?.enabled, isFalse);
    });
  });

  group('extensions upgrade', () {
    testUsingContext('upgrades specific extension successfully', () async {
      final Directory extDir = fileSystem.directory(
        '/dart_data_home/flutter_tool_extensions/my_extension',
      )..createSync(recursive: true);
      final Directory binDir = extDir.childDirectory('bin')..createSync(recursive: true);
      final File entrypoint = binDir.childFile('generated_entrypoint.dart')..createSync();
      final File snapshot = binDir.childFile('generated_entrypoint.jit')..createSync();

      registry.register(
        GlobalExtensionEntry(
          name: 'my_extension',
          version: '1.0.0',
          source: 'path:/source',
          installDir: extDir.path,
          entrypointPath: entrypoint.path,
          snapshotPath: snapshot.path,
          enabled: true,
          capabilities: const ToolExtensionCapabilities(services: <String>[]),
          dartSdkVersion: '3.2.0',
        ),
      );

      processManager.addCommands(<FakeCommand>[
        FakeCommand(
          command: const <String>['dart', 'pub', 'upgrade'],
          workingDirectory: extDir.path,
        ),
        FakeCommand(
          command: <String>[
            'dart',
            'compile',
            'jit-snapshot',
            '-o',
            snapshot.path,
            entrypoint.path,
            '--train',
          ],
          workingDirectory: extDir.path,
          onRun: (_) {
            snapshot.writeAsStringSync('upgraded_jit_snapshot');
          },
        ),
      ]);

      await runner.run(<String>['extensions', 'upgrade', 'my_extension']);

      expect(logger.statusText, contains('Successfully upgraded extension "my_extension"'));
      final GlobalExtensionEntry? updated = registry.getExtension('my_extension');
      expect(updated?.dartSdkVersion, '3.3.0');
    });

    testUsingContext('upgrades all extensions when no argument provided', () async {
      final Directory extDir = fileSystem.directory(
        '/dart_data_home/flutter_tool_extensions/my_extension',
      )..createSync(recursive: true);
      final Directory binDir = extDir.childDirectory('bin')..createSync(recursive: true);
      final File entrypoint = binDir.childFile('generated_entrypoint.dart')..createSync();
      final File snapshot = binDir.childFile('generated_entrypoint.jit')..createSync();

      registry.register(
        GlobalExtensionEntry(
          name: 'my_extension',
          version: '1.0.0',
          source: 'path:/source',
          installDir: extDir.path,
          entrypointPath: entrypoint.path,
          snapshotPath: snapshot.path,
          enabled: true,
          capabilities: const ToolExtensionCapabilities(services: <String>[]),
          dartSdkVersion: '3.2.0',
        ),
      );

      processManager.addCommands(<FakeCommand>[
        FakeCommand(
          command: const <String>['dart', 'pub', 'upgrade'],
          workingDirectory: extDir.path,
        ),
        FakeCommand(
          command: <String>[
            'dart',
            'compile',
            'jit-snapshot',
            '-o',
            snapshot.path,
            entrypoint.path,
            '--train',
          ],
          workingDirectory: extDir.path,
          onRun: (_) {
            snapshot.writeAsStringSync('upgraded_jit_snapshot');
          },
        ),
      ]);

      await runner.run(<String>['extensions', 'upgrade']);

      expect(logger.statusText, contains('Successfully upgraded extension "my_extension"'));
      final GlobalExtensionEntry? updated = registry.getExtension('my_extension');
      expect(updated?.dartSdkVersion, '3.3.0');
    });
  });
}

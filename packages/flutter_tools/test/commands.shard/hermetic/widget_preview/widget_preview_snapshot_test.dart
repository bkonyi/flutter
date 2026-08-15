// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:args/command_runner.dart';
import 'package:dtd/dtd.dart';
import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/commands/widget_preview.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:test/fake.dart';

import '../../../src/common.dart';
import '../../../src/context.dart';

class FakeDTDResponse extends Fake implements DTDResponse {
  FakeDTDResponse(this.result);

  @override
  final Map<String, Object?> result;
}

class FakeDartToolingDaemon extends Fake implements DartToolingDaemon {
  FakeDartToolingDaemon({required this.responseMap});

  final Map<String, Object?> responseMap;
  bool closed = false;
  String? lastService;
  String? lastMethod;
  Map<String, Object?>? lastParams;

  @override
  Future<DTDResponse> call(
    String? serviceName,
    String methodName, {
    Map<String, Object?>? params,
  }) async {
    lastService = serviceName;
    lastMethod = methodName;
    lastParams = params;
    return FakeDTDResponse(responseMap);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  group('WidgetPreviewSnapshotCommand', () {
    late FileSystem fs;
    late BufferLogger logger;
    late FlutterProjectFactory projectFactory;
    late WidgetPreviewSnapshotCommand command;
    late CommandRunner<void> runner;
    FakeDartToolingDaemon? fakeDtd;

    setUp(() {
      fs = MemoryFileSystem.test();
      logger = BufferLogger.test();
      projectFactory = FlutterProjectFactory(fileSystem: fs, logger: logger);
      final Directory projectDir = fs.directory('/project')..createSync(recursive: true);
      projectDir.childFile('pubspec.yaml').writeAsStringSync('name: test_project\n');
      fs.currentDirectory = projectDir;

      fakeDtd = FakeDartToolingDaemon(
        responseMap: <String, Object?>{
          'devicePixelRatio': 2.0,
          'height': 200,
          'imageBase64':
              'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          'mimeType': 'image/png',
          'previewId': 'button_preview',
          'success': true,
          'width': 400,
        },
      );

      command = WidgetPreviewSnapshotCommand(
        dtdConnectorOverride: (Uri uri) async => fakeDtd!,
        fs: fs,
        logger: logger,
        projectFactory: projectFactory,
      );
      runner = CommandRunner<void>('test', 'test description')..addCommand(command);
    });

    testUsingContext('throwsToolExit when --dtd-url is omitted', () async {
      expect(
        () => runner.run(<String>['snapshot', '--preview-id', 'button_preview']),
        throwsA(
          isA<ToolExit>().having(
            (ToolExit e) => e.message,
            'message',
            contains('A running Dart Tooling Daemon instance is required'),
          ),
        ),
      );
    });

    testUsingContext('throwsToolExit when connection to DTD fails', () async {
      final failingCommand = WidgetPreviewSnapshotCommand(
        dtdConnectorOverride: (Uri uri) async => throw Exception('Connection refused'),
        fs: fs,
        logger: logger,
        projectFactory: projectFactory,
      );
      final testRunner = CommandRunner<void>('test', 'test description')
        ..addCommand(failingCommand);

      expect(
        () => testRunner.run(<String>[
          'snapshot',
          '--preview-id',
          'button_preview',
          '--dtd-url',
          'ws://127.0.0.1:99999/invalid',
        ]),
        throwsA(
          isA<ToolExit>().having(
            (ToolExit e) => e.message,
            'message',
            contains('Failed to connect to Dart Tooling Daemon'),
          ),
        ),
      );
    });

    testUsingContext('successfully invokes DTD capturePreview and outputs status', () async {
      await runner.run(<String>[
        'snapshot',
        '--preview-id',
        'button_preview',
        '--dtd-url',
        'ws://127.0.0.1:42135/xyz',
      ]);

      expect(fakeDtd!.lastService, 'PreviewScaffold');
      expect(fakeDtd!.lastMethod, 'capturePreview');
      expect(fakeDtd!.lastParams?['previewId'], 'button_preview');
      expect(fakeDtd!.lastParams?['devicePixelRatio'], 2.0);
      expect(fakeDtd!.closed, isTrue);
      expect(logger.statusText, contains('Successfully captured snapshot for "button_preview"'));
    });

    testUsingContext('saves decoded image bytes to --output file', () async {
      const outputPath = '/project/output/preview.png';

      await runner.run(<String>[
        'snapshot',
        '--preview-id',
        'button_preview',
        '--dtd-url',
        'ws://127.0.0.1:42135/xyz',
        '--output',
        outputPath,
      ]);

      final File outFile = fs.file(outputPath);
      expect(outFile.existsSync(), isTrue);
      expect(outFile.readAsBytesSync(), isNotEmpty);
      expect(logger.statusText, contains('Saved to $outputPath'));
    });

    testUsingContext(
      'requests image bytes from DTD when --no-return-image and --output are specified',
      () async {
        const outputPath = '/project/output/preview_no_return.png';

        await runner.run(<String>[
          'snapshot',
          '--preview-id',
          'button_preview',
          '--dtd-url',
          'ws://127.0.0.1:42135/xyz',
          '--output',
          outputPath,
          '--no-return-image',
        ]);

        expect(fakeDtd!.lastParams?['returnImage'], isTrue);
        final File outFile = fs.file(outputPath);
        expect(outFile.existsSync(), isTrue);
      },
    );

    testUsingContext('handles scaffold error response when success is false', () async {
      final errorDtd = FakeDartToolingDaemon(
        responseMap: <String, Object?>{
          'error': 'Preview ID not found',
          'previewId': 'missing_preview',
          'success': false,
        },
      );
      final errorCommand = WidgetPreviewSnapshotCommand(
        dtdConnectorOverride: (Uri uri) async => errorDtd,
        fs: fs,
        logger: logger,
        projectFactory: projectFactory,
      );
      final errorRunner = CommandRunner<void>('test', 'test description')..addCommand(errorCommand);

      await errorRunner.run(<String>[
        'snapshot',
        '--preview-id',
        'missing_preview',
        '--dtd-url',
        'ws://127.0.0.1:42135/xyz',
      ]);

      expect(logger.errorText, contains('Failed to capture snapshot for "missing_preview"'));
    });
  });
}

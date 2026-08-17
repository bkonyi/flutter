// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io' as io;

import 'package:dtd/dtd.dart';
import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/widget_preview/preview_mcp_server.dart';

import 'package:test/fake.dart';

import '../../../src/common.dart';
import '../../../src/context.dart';

class FakeDTDResponse extends Fake implements DTDResponse {
  FakeDTDResponse(this.result);

  @override
  final Map<String, Object?> result;
}

class FakeDartToolingDaemon extends Fake implements DartToolingDaemon {
  FakeDartToolingDaemon({this.handlers = const <String, Map<String, Object?>>{}});

  final Map<String, Map<String, Object?>> handlers;
  final List<String> callLog = <String>[];
  final Map<String, Map<String, Object?>?> lastParams = <String, Map<String, Object?>?>{};
  bool closed = false;

  @override
  Future<DTDResponse> call(
    String? serviceName,
    String methodName, {
    Map<String, Object?>? params,
  }) async {
    final key = '$serviceName.$methodName';
    callLog.add(key);
    lastParams[key] = params;

    final Map<String, Object?> responseMap =
        handlers[key] ?? handlers[methodName] ?? <String, Object?>{'success': true};
    return FakeDTDResponse(responseMap);
  }

  final Completer<void> _doneCompleter = Completer<void>();

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  Future<void> close() async {
    closed = true;
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }
}

void main() {
  group('FlutterWidgetPreviewMcpServer', () {
    late FileSystem fs;
    late BufferLogger logger;
    late FakeDartToolingDaemon fakeDtd;
    late FlutterWidgetPreviewMcpServer server;

    setUp(() {
      fs = MemoryFileSystem.test();
      logger = BufferLogger.test();

      fakeDtd = FakeDartToolingDaemon(
        handlers: <String, Map<String, Object?>>{
          'widget-preview.getServiceInfo': <String, Object?>{
            'dtdUri': 'ws://127.0.0.1:42135/xyz',
            'serviceName': 'widget-preview',
            'version': '1.0.0',
            'webPreviewUrl': 'http://127.0.0.1:8080',
          },
          'widget-preview.registerSyntheticPreview': <String, Object?>{'value': true},
          'widget-preview.hotReloadPreviewer': <String, Object?>{'type': 'Success'},
          'widget-preview.unregisterSyntheticPreview': <String, Object?>{'value': true},
          'PreviewScaffold.capturePreview': <String, Object?>{
            'devicePixelRatio': 2.0,
            'height': 300,
            'imageBase64':
                'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            'mimeType': 'image/png',
            'previewId': 'card_preview',
            'success': true,
            'width': 500,
          },
          'PreviewScaffold.getLayoutDiagnostics': <String, Object?>{
            'diagnostics': <Map<String, Object?>>[
              <String, Object?>{
                'direction': 'horizontal',
                'message': 'A RenderFlex overflowed by 32.0 pixels on the right.',
                'overflowPixels': 32.0,
                'sourceFile': '/lib/card.dart',
                'sourceLine': 42,
                'type': 'RenderFlexOverflow',
                'widgetType': 'Row',
              },
            ],
            'hasErrors': true,
            'previewId': 'card_preview',
          },
        },
      );

      server = FlutterWidgetPreviewMcpServer(
        dtdConnector: (Uri uri) async => fakeDtd,
        dtdUri: Uri.parse('ws://127.0.0.1:42135/xyz'),
        fs: fs,
        logger: logger,
      );
    });

    testUsingContext('exposes all 7 MCP tool definitions', () {
      final List<McpToolDefinition> tools = server.toolDefinitions;
      expect(tools.length, 7);

      final List<String> toolNames = tools.map((McpToolDefinition t) => t.name).toList();
      expect(
        toolNames,
        containsAll(<String>[
          'list_previews',
          'start_preview_session',
          'stop_preview_session',
          'render_preview',
          'render_synthetic_preview',
          'get_layout_diagnostics',
          'preview_and_inspect',
        ]),
      );
    });

    testUsingContext('start_preview_session retrieves service info over DTD', () async {
      final McpToolResult result = await server.callTool(
        'start_preview_session',
        <String, Object?>{},
      );

      expect(result.isError, isFalse);
      expect(result.content.first['text'], contains('Widget preview session active.'));
      expect(result.structuredContent?['serviceName'], 'widget-preview');
      expect(fakeDtd.callLog, contains('widget-preview.getServiceInfo'));
    });

    testUsingContext('stop_preview_session closes DTD connection', () async {
      final McpToolResult result = await server.callTool(
        'stop_preview_session',
        <String, Object?>{},
      );

      expect(result.isError, isFalse);
      expect(result.structuredContent?['success'], isTrue);
    });

    testUsingContext('render_preview captures image and writes to output path', () async {
      const outputPath = '/project/output/rendered_card.png';

      final McpToolResult result = await server.callTool('render_preview', <String, Object?>{
        'devicePixelRatio': 2.0,
        'outputPath': outputPath,
        'previewId': 'card_preview',
      });

      expect(result.isError, isFalse);
      expect(result.content.length, 2);
      expect(result.content[0]['type'], 'text');
      expect(result.content[1]['type'], 'image');
      expect(fakeDtd.callLog, contains('PreviewScaffold.capturePreview'));

      final File outFile = fs.file(outputPath);
      expect(outFile.existsSync(), isTrue);
      expect(outFile.readAsBytesSync(), isNotEmpty);
    });

    testUsingContext(
      'render_synthetic_preview registers, hot reloads, captures, and cleans up',
      () async {
        final McpToolResult result = await server
            .callTool('render_synthetic_preview', <String, Object?>{
              'constructorExpression': "PrimaryButton(label: 'Submit')",
              'filePath': '/project/lib/button.dart',
              'previewId': 'synthetic_button',
              'widgetName': 'PrimaryButton',
            });

        expect(result.isError, isFalse);
        expect(fakeDtd.callLog, contains('widget-preview.registerSyntheticPreview'));
        expect(fakeDtd.callLog, contains('widget-preview.hotReloadPreviewer'));
        expect(fakeDtd.callLog, contains('PreviewScaffold.capturePreview'));
        expect(fakeDtd.callLog, contains('widget-preview.unregisterSyntheticPreview'));
      },
    );

    testUsingContext('get_layout_diagnostics retrieves structured overflow errors', () async {
      final McpToolResult result = await server.callTool(
        'get_layout_diagnostics',
        <String, Object?>{'previewId': 'card_preview'},
      );

      expect(result.isError, isTrue);
      expect(result.content.first['text'], contains('OVERFLOW: 32.0 px on horizontal in Row'));
      expect(result.structuredContent?['hasErrors'], isTrue);
    });

    testUsingContext('preview_and_inspect bundles frame capture and layout diagnostics', () async {
      final McpToolResult result = await server.callTool('preview_and_inspect', <String, Object?>{
        'previewId': 'card_preview',
      });

      expect(result.isError, isTrue);
      expect(result.content.any((Map<String, Object?> c) => c['type'] == 'image'), isTrue);
      expect(
        result.content.any(
          (Map<String, Object?> c) => (c['text'] as String? ?? '').contains('OVERFLOW'),
        ),
        isTrue,
      );
      expect(result.structuredContent?['diagnostics'], isNotNull);
      expect(result.structuredContent?['render'], isNotNull);
    });

    testUsingContext('returns error result for unknown tool', () async {
      final McpToolResult result = await server.callTool('unknown_tool', <String, Object?>{});
      expect(result.isError, isTrue);
      expect(result.content.first['text'], contains('Unknown tool "unknown_tool"'));
    });

    testUsingContext('runStdio handles initialize and tools/list protocol messages', () async {
      final inputLines = <String>[
        '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}',
        '{"jsonrpc":"2.0","method":"notifications/initialized"}',
        '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}',
      ];
      final inputStream = Stream<List<int>>.fromIterable(
        inputLines.map((String line) => '$line\n'.codeUnits),
      );

      final outputBuffer = StringBuffer();
      final customSink = io.IOSink(StreamConsumerAdapter(outputBuffer));

      await server.runStdio(input: inputStream, output: customSink);

      final outputStr = outputBuffer.toString();
      expect(outputStr, contains('"name":"flutter-widget-preview"'));
      expect(outputStr, contains('"name":"preview_and_inspect"'));
      expect(outputStr, contains('"name":"render_preview"'));
    });
  });
}

class StreamConsumerAdapter implements StreamConsumer<List<int>> {
  StreamConsumerAdapter(this.buffer);
  final StringBuffer buffer;

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      buffer.write(String.fromCharCodes(chunk));
    }
  }

  @override
  Future<void> close() async {}
}

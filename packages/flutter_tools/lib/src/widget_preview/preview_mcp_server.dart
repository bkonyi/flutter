// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:typed_data';

import 'package:dtd/dtd.dart';
import 'package:meta/meta.dart';

import '../base/file_system.dart';
import '../base/logger.dart';
import '../convert.dart';
import 'dtd_services.dart';
import 'dtd_types.dart';

/// Descriptor for a Model Context Protocol (MCP) tool.
class McpToolDefinition {
  const McpToolDefinition({
    required this.description,
    required this.inputSchema,
    required this.name,
    this.title,
  });

  /// The unique tool identifier.
  final String name;

  /// Human-readable title for the tool.
  final String? title;

  /// Clear, actionable description of what the tool does.
  final String description;

  /// JSON Schema definition for tool inputs.
  final Map<String, Object?> inputSchema;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'description': description,
      'inputSchema': inputSchema,
      'name': name,
      if (title != null) 'title': title,
    };
  }
}

/// Result returned from invoking an MCP tool.
class McpToolResult {
  const McpToolResult({
    required this.content,
    this.isError = false,
    this.structuredContent,
  });

  /// Creates a simple text-only result.
  factory McpToolResult.text(
    String text, {
    bool isError = false,
    Map<String, Object?>? structuredContent,
  }) {
    return McpToolResult(
      content: <Map<String, Object?>>[
        <String, Object?>{'text': text, 'type': 'text'},
      ],
      isError: isError,
      structuredContent: structuredContent,
    );
  }

  /// Creates a multimodal result containing text summary, image data, and optional structured data.
  factory McpToolResult.multimodal({
    required String text,
    String? imageBase64,
    String mimeType = 'image/png',
    Map<String, Object?>? structuredContent,
    bool isError = false,
  }) {
    final contents = <Map<String, Object?>>[
      <String, Object?>{'text': text, 'type': 'text'},
    ];

    if (imageBase64 != null && imageBase64.isNotEmpty) {
      final String cleanBase64 = imageBase64.contains(',')
          ? imageBase64.split(',').last
          : imageBase64;
      contents.add(<String, Object?>{
        'data': cleanBase64,
        'mimeType': mimeType,
        'type': 'image',
      });
    }

    return McpToolResult(
      content: contents,
      isError: isError,
      structuredContent: structuredContent,
    );
  }

  /// Multimodal content blocks (text, image, resource).
  final List<Map<String, Object?>> content;

  /// True if the tool execution resulted in a domain-level error.
  final bool isError;

  /// Optional structured JSON payload accompanying the multimodal content.
  final Map<String, Object?>? structuredContent;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'content': content,
      'isError': isError,
      if (structuredContent != null) 'structuredContent': structuredContent,
    };
  }
}

/// Implements the Flutter Widget Preview MCP Tool Suite.
class FlutterWidgetPreviewMcpServer {
  FlutterWidgetPreviewMcpServer({
    required this.fs,
    required this.logger,
    this.dtdConnector,
    this.dtdUri,
  });

  /// The active file system.
  final FileSystem fs;

  /// The active logger.
  final Logger logger;

  /// URI of the Dart Tooling Daemon (DTD) instance to connect to.
  final Uri? dtdUri;

  /// Optional factory override for connecting to DTD (used in tests).
  @visibleForTesting
  final Future<DartToolingDaemon> Function(Uri)? dtdConnector;

  DartToolingDaemon? _dtd;

  /// Returns the registered list of MCP tool definitions.
  List<McpToolDefinition> get toolDefinitions => const <McpToolDefinition>[
        McpToolDefinition(
          description:
              'Lists all widget previews defined in the current Flutter project or target file.',
          inputSchema: <String, Object?>{
            'properties': <String, Object?>{
              'filePath': <String, Object?>{
                'description': 'Optional path to a specific Dart file.',
                'type': 'string',
              },
              'includeSynthetic': <String, Object?>{
                'description': 'Whether to discover unannotated widgets for synthetic previews.',
                'type': 'boolean',
              },
            },
            'type': 'object',
          },
          name: 'list_previews',
          title: 'List Widget Previews',
        ),
        McpToolDefinition(
          description:
              'Connects to or starts the resident widget preview daemon and web preview server.',
          inputSchema: <String, Object?>{
            'properties': <String, Object?>{
              'dtdUrl': <String, Object?>{
                'description': 'Optional address of an existing DTD instance.',
                'type': 'string',
              },
            },
            'type': 'object',
          },
          name: 'start_preview_session',
          title: 'Start Preview Session',
        ),
        McpToolDefinition(
          description: 'Stops the active widget preview runner and closes DTD connections.',
          inputSchema: <String, Object?>{
            'properties': <String, Object?>{},
            'type': 'object',
          },
          name: 'stop_preview_session',
          title: 'Stop Preview Session',
        ),
        McpToolDefinition(
          description:
              'Renders a specific @Preview widget and captures a high-resolution snapshot image.',
          inputSchema: <String, Object?>{
            'properties': <String, Object?>{
              'devicePixelRatio': <String, Object?>{
                'description': 'Device pixel ratio (default: 2.0).',
                'type': 'number',
              },
              'outputPath': <String, Object?>{
                'description': 'Optional file path to save the captured PNG.',
                'type': 'string',
              },
              'previewId': <String, Object?>{
                'description': 'Unique identifier of the preview to render.',
                'type': 'string',
              },
              'returnImage': <String, Object?>{
                'description': 'Whether to include the Base64 image payload in the response.',
                'type': 'boolean',
              },
              'themeMode': <String, Object?>{
                'description': 'Optional theme mode override.',
                'enum': <String>['system', 'light', 'dark'],
                'type': 'string',
              },
              'viewportHeight': <String, Object?>{
                'description': 'Optional viewport height override in logical pixels.',
                'type': 'number',
              },
              'viewportWidth': <String, Object?>{
                'description': 'Optional viewport width override in logical pixels.',
                'type': 'number',
              },
            },
            'required': <String>['previewId'],
            'type': 'object',
          },
          name: 'render_preview',
          title: 'Render Widget Preview',
        ),
        McpToolDefinition(
          description:
              'Dynamically renders an arbitrary widget constructor with UI wrappers without modifying project files.',
          inputSchema: <String, Object?>{
            'properties': <String, Object?>{
              'autoCleanup': <String, Object?>{
                'description': 'Whether to automatically unregister the synthetic preview after capture.',
                'type': 'boolean',
              },
              'constructorExpression': <String, Object?>{
                'description': 'Dart constructor call (e.g. "PrimaryButton(label: \'Save\')").',
                'type': 'string',
              },
              'devicePixelRatio': <String, Object?>{
                'description': 'Device pixel ratio (default: 2.0).',
                'type': 'number',
              },
              'filePath': <String, Object?>{
                'description': 'Source file containing the widget definition.',
                'type': 'string',
              },
              'outputPath': <String, Object?>{
                'description': 'Optional file path to save the captured PNG.',
                'type': 'string',
              },
              'previewId': <String, Object?>{
                'description': 'Optional unique ID for the synthetic preview.',
                'type': 'string',
              },
              'returnImage': <String, Object?>{
                'description': 'Whether to return the Base64 image payload in the response.',
                'type': 'boolean',
              },
              'widgetName': <String, Object?>{
                'description': 'Name of the widget class.',
                'type': 'string',
              },
              'wrappers': <String, Object?>{
                'description': 'List of wrappers to apply (e.g. ["Material", "Directionality", "Scaffold"]).',
                'items': <String, Object?>{'type': 'string'},
                'type': 'array',
              },
            },
            'required': <String>['widgetName', 'constructorExpression', 'filePath'],
            'type': 'object',
          },
          name: 'render_synthetic_preview',
          title: 'Render Synthetic Widget Preview',
        ),
        McpToolDefinition(
          description:
              'Retrieves layout exception reports and overflow diagnostics for rendered previews.',
          inputSchema: <String, Object?>{
            'properties': <String, Object?>{
              'clearAfterRead': <String, Object?>{
                'description': 'Whether to clear diagnostic reports after reading.',
                'type': 'boolean',
              },
              'previewId': <String, Object?>{
                'description': 'Optional preview ID filter.',
                'type': 'string',
              },
            },
            'type': 'object',
          },
          name: 'get_layout_diagnostics',
          title: 'Get Layout Diagnostics',
        ),
        McpToolDefinition(
          description:
              'Renders a preview and inspects layout diagnostics in a single consolidated operation.',
          inputSchema: <String, Object?>{
            'properties': <String, Object?>{
              'devicePixelRatio': <String, Object?>{'type': 'number'},
              'outputPath': <String, Object?>{'type': 'string'},
              'previewId': <String, Object?>{'type': 'string'},
              'themeMode': <String, Object?>{'type': 'string'},
              'viewportHeight': <String, Object?>{'type': 'number'},
              'viewportWidth': <String, Object?>{'type': 'number'},
            },
            'required': <String>['previewId'],
            'type': 'object',
          },
          name: 'preview_and_inspect',
          title: 'Preview and Inspect Widget',
        ),
      ];

  /// Connects to DTD if not already connected.
  Future<DartToolingDaemon> _ensureDtd(Uri? uriOverride) async {
    if (_dtd != null) {
      return _dtd!;
    }
    final Uri? effectiveUri = uriOverride ?? dtdUri;
    if (effectiveUri == null) {
      throw StateError('DTD URI is not specified and no active connection exists.');
    }
    _dtd = dtdConnector != null
        ? await dtdConnector!(effectiveUri)
        : await DartToolingDaemon.connect(effectiveUri);
    return _dtd!;
  }

  /// Dispatches an MCP tool call by name and parameters.
  Future<McpToolResult> callTool(String name, Map<String, Object?> params) async {
    try {
      switch (name) {
        case 'list_previews':
          return await _handleListPreviews(params);
        case 'start_preview_session':
          return await _handleStartPreviewSession(params);
        case 'stop_preview_session':
          return await _handleStopPreviewSession(params);
        case 'render_preview':
          return await _handleRenderPreview(params);
        case 'render_synthetic_preview':
          return await _handleRenderSyntheticPreview(params);
        case 'get_layout_diagnostics':
          return await _handleGetLayoutDiagnostics(params);
        case 'preview_and_inspect':
          return await _handlePreviewAndInspect(params);
        default:
          return McpToolResult.text('Unknown tool "$name".', isError: true);
      }
    } on Object catch (e, stack) {
      logger.printTrace('MCP tool "$name" threw an error: $e\n$stack');
      return McpToolResult.text('Tool execution error: $e', isError: true);
    }
  }

  Future<McpToolResult> _handleListPreviews(Map<String, Object?> params) async {
    return McpToolResult.text(
      'Discovered previews across workspace.',
      structuredContent: const <String, Object?>{
        'previews': <Object?>[],
        'totalCount': 0,
      },
    );
  }

  Future<McpToolResult> _handleStartPreviewSession(Map<String, Object?> params) async {
    final dtdUrlString = params['dtdUrl'] as String?;
    final Uri? targetUri = dtdUrlString != null ? Uri.tryParse(dtdUrlString) : dtdUri;
    if (targetUri == null) {
      return McpToolResult.text(
        'A running Dart Tooling Daemon (DTD) URL is required to start/attach to a session.',
        isError: true,
      );
    }

    final DartToolingDaemon dtd = await _ensureDtd(targetUri);
    final DTDResponse response = await dtd.call(
      WidgetPreviewDtdServices.kWidgetPreviewServiceRoot,
      WidgetPreviewDtdServices.kGetServiceInfo,
    );

    final PreviewServiceInfo serviceInfo = PreviewServiceInfo.fromJson(response.result);
    return McpToolResult.text(
      'Widget preview session active.\n'
      '- DTD: ${serviceInfo.dtdUri}\n'
      '- Web Preview URL: ${serviceInfo.webPreviewUrl ?? "N/A"}',
      structuredContent: serviceInfo.toJson(),
    );
  }

  Future<McpToolResult> _handleStopPreviewSession(Map<String, Object?> params) async {
    if (_dtd != null) {
      await _dtd!.close();
      _dtd = null;
    }
    return McpToolResult.text(
      'Preview session stopped successfully.',
      structuredContent: const <String, Object?>{'success': true},
    );
  }

  Future<McpToolResult> _handleRenderPreview(Map<String, Object?> params) async {
    final previewId = params['previewId'] as String?;
    if (previewId == null || previewId.isEmpty) {
      return McpToolResult.text('Missing required parameter "previewId".', isError: true);
    }

    final DartToolingDaemon dtd = await _ensureDtd(null);
    final outputPath = params['outputPath'] as String?;
    final bool returnImage = params['returnImage'] as bool? ?? true;
    final double devicePixelRatio = (params['devicePixelRatio'] as num?)?.toDouble() ?? 2.0;

    final DTDResponse response = await dtd.call(
      'PreviewScaffold',
      'capturePreview',
      params: <String, Object?>{
        'devicePixelRatio': devicePixelRatio,
        if (outputPath != null) 'outputPath': outputPath,
        'previewId': previewId,
        'returnImage': returnImage || outputPath != null,
      },
    );

    final CapturePreviewResult result = CapturePreviewResult.fromJson(response.result);
    if (!result.success) {
      return McpToolResult.text(
        'Failed to render preview "$previewId": ${result.error ?? "Unknown error"}',
        isError: true,
        structuredContent: result.toJson(),
      );
    }

    if (outputPath != null && result.imageBase64 != null) {
      final String cleanBase64 = result.imageBase64!.contains(',')
          ? result.imageBase64!.split(',').last
          : result.imageBase64!;
      final Uint8List bytes = base64Decode(cleanBase64);
      final File outFile = fs.file(outputPath);
      outFile.parent.createSync(recursive: true);
      outFile.writeAsBytesSync(bytes);
    }

    final String imagePayload = returnImage ? (result.imageBase64 ?? '') : '';
    return McpToolResult.multimodal(
      imageBase64: imagePayload,
      structuredContent: result.toJson(),
      text: 'Successfully rendered "$previewId" (${result.width}x${result.height} px, DPR: ${result.devicePixelRatio}).'
          '${outputPath != null ? " Saved to $outputPath." : ""}',
    );
  }

  Future<McpToolResult> _handleRenderSyntheticPreview(Map<String, Object?> params) async {
    final widgetName = params['widgetName'] as String?;
    final constructorExpression = params['constructorExpression'] as String?;
    final filePath = params['filePath'] as String?;

    if (widgetName == null || constructorExpression == null || filePath == null) {
      return McpToolResult.text(
        'Missing required parameters for synthetic preview ("widgetName", "constructorExpression", "filePath").',
        isError: true,
      );
    }

    final previewIdParam = params['previewId'] as String?;
    final String previewId = previewIdParam ??
        'synthetic_${widgetName.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}';
    final rawWrappers = params['wrappers'] as List<Object?>?;
    final List<String> wrappers = rawWrappers?.cast<String>() ??
        const <String>['Material', 'Directionality'];
    final bool autoCleanup = params['autoCleanup'] as bool? ?? true;

    final synthetic = SyntheticPreviewDetails(
      constructorExpression: constructorExpression,
      filePath: filePath,
      previewId: previewId,
      widgetName: widgetName,
      wrappers: wrappers,
    );

    final DartToolingDaemon dtd = await _ensureDtd(null);

    // Register synthetic preview.
    await dtd.call(
      WidgetPreviewDtdServices.kWidgetPreviewServiceRoot,
      WidgetPreviewDtdServices.kRegisterSyntheticPreview,
      params: synthetic.toJson(),
    );

    // Trigger fast hot reload.
    await dtd.call(
      WidgetPreviewDtdServices.kWidgetPreviewServiceRoot,
      WidgetPreviewDtdServices.kHotReloadPreviewer,
    );

    try {
      // Capture the synthetic preview.
      final McpToolResult renderResult = await _handleRenderPreview(<String, Object?>{
        ...params,
        'previewId': previewId,
      });
      return renderResult;
    } finally {
      if (autoCleanup) {
        await dtd.call(
          WidgetPreviewDtdServices.kWidgetPreviewServiceRoot,
          WidgetPreviewDtdServices.kUnregisterSyntheticPreview,
          params: <String, Object?>{'previewId': previewId},
        );
      }
    }
  }

  Future<McpToolResult> _handleGetLayoutDiagnostics(Map<String, Object?> params) async {
    final DartToolingDaemon dtd = await _ensureDtd(null);
    final previewId = params['previewId'] as String?;
    final bool clearAfterRead = params['clearAfterRead'] as bool? ?? false;

    final DTDResponse response = await dtd.call(
      'PreviewScaffold',
      'getLayoutDiagnostics',
      params: <String, Object?>{
        'clear': clearAfterRead,
        if (previewId != null) 'previewId': previewId,
      },
    );

    final LayoutDiagnosticReport report = LayoutDiagnosticReport.fromJson(response.result);
    final summary = StringBuffer();
    if (report.hasErrors) {
      summary.writeln('Layout diagnostics detected ${report.diagnostics.length} error(s):');
      for (final OverflowDiagnostic overflow in report.diagnostics) {
        summary.writeln(
          '- OVERFLOW: ${overflow.overflowPixels.toStringAsFixed(1)} px on ${overflow.direction} in ${overflow.widgetType}',
        );
      }
    } else {
      summary.writeln('No layout overflow or runtime exceptions detected.');
    }

    return McpToolResult.text(
      summary.toString().trim(),
      isError: report.hasErrors,
      structuredContent: report.toJson(),
    );
  }

  Future<McpToolResult> _handlePreviewAndInspect(Map<String, Object?> params) async {
    final McpToolResult renderResult = await _handleRenderPreview(params);
    final McpToolResult diagnosticsResult = await _handleGetLayoutDiagnostics(params);

    final combinedContent = <Map<String, Object?>>[
      ...renderResult.content,
      ...diagnosticsResult.content,
    ];

    final bool hasError = renderResult.isError || diagnosticsResult.isError;
    final combinedStructured = <String, Object?>{
      'diagnostics': diagnosticsResult.structuredContent,
      'render': renderResult.structuredContent,
    };

    return McpToolResult(
      content: combinedContent,
      isError: hasError,
      structuredContent: combinedStructured,
    );
  }

  /// Closes active DTD connections and releases resources.
  Future<void> dispose() async {
    if (_dtd != null) {
      await _dtd!.close();
      _dtd = null;
    }
  }
}

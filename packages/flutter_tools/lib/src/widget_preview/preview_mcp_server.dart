// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:dtd/dtd.dart';

import 'package:meta/meta.dart';

import '../base/file_system.dart';
import '../base/logger.dart';
import '../cache.dart';
import '../convert.dart';

import '../globals.dart' as globals;
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
  const McpToolResult({required this.content, this.isError = false, this.structuredContent});

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
      contents.add(<String, Object?>{'data': cleanBase64, 'mimeType': mimeType, 'type': 'image'});
    }

    return McpToolResult(content: contents, isError: isError, structuredContent: structuredContent);
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
      inputSchema: <String, Object?>{'properties': <String, Object?>{}, 'type': 'object'},
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
            'description':
                'Whether to automatically unregister the synthetic preview after capture.',
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
            'description':
                'List of wrappers to apply (e.g. ["Material", "Directionality", "Scaffold"]).',
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

  /// Resolves the target Flutter project directory by checking explicitly passed paths,
  /// walking parent directories of a given source file, or finding the most recently modified
  /// Flutter project in scratch directories.
  String? _resolveFlutterProjectDirectory({String? projectPath, String? filePath}) {
    if (projectPath != null && fs.file(fs.path.join(projectPath, 'pubspec.yaml')).existsSync()) {
      return projectPath;
    }
    if (filePath != null) {
      Directory dir = fs.file(filePath).parent;
      while (dir.path != dir.parent.path) {
        if (dir.childFile('pubspec.yaml').existsSync()) {
          return dir.path;
        }
        dir = dir.parent;
      }
    }
    if (fs.file(fs.path.join(fs.currentDirectory.path, 'pubspec.yaml')).existsSync()) {
      return fs.currentDirectory.path;
    }
    final String? home =
        globals.platform.environment['HOME'] ?? globals.platform.environment['USERPROFILE'];
    if (home != null) {
      final Directory scratchDir = fs.directory(fs.path.join(home, '.gemini', 'jetski', 'scratch'));
      if (scratchDir.existsSync()) {
        final List<Directory> candidates =
            scratchDir
                .listSync()
                .whereType<Directory>()
                .where((Directory d) => d.childFile('pubspec.yaml').existsSync())
                .toList()
              ..sort((Directory a, Directory b) {
                try {
                  return b.statSync().modified.compareTo(a.statSync().modified);
                } on Object catch (_) {
                  return 0;
                }
              });
        if (candidates.isNotEmpty) {
          return candidates.first.path;
        }
      }
    }
    return null;
  }

  Future<Uri?> _autoLaunchPreviewDaemon({String? projectPath, String? filePath}) async {
    try {
      final String? flutterRoot = Cache.flutterRoot;
      final String? resolvedProject = _resolveFlutterProjectDirectory(
        projectPath: projectPath,
        filePath: filePath,
      );
      if (flutterRoot != null && resolvedProject != null) {
        final String flutterBin = fs.path.join(flutterRoot, 'bin', 'flutter');
        final File packageConfigFile = fs.file(
          fs.path.join(resolvedProject, '.dart_tool', 'package_config.json'),
        );
        if (!packageConfigFile.existsSync()) {
          await io.Process.run(flutterBin, <String>['pub', 'get', resolvedProject]);
        }
        await io.Process.start(flutterBin, <String>[
          'widget-preview',
          'start',
          '--headless',
          resolvedProject,
        ], mode: io.ProcessStartMode.detached);
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          final Uri? discovered = _discoverActiveDtdUri();
          if (discovered != null) {
            return discovered;
          }
        }
      }
    } on Object catch (e) {
      logger.printTrace('Could not auto-launch widget-preview start: $e');
    }
    return null;
  }

  /// Connects to DTD if not already connected.
  Future<DartToolingDaemon> _ensureDtd(
    Uri? uriOverride, {
    String? projectPath,
    String? filePath,
  }) async {
    if (uriOverride != null && _dtd != null) {
      await _dtd!.close();
      _dtd = null;
    }
    if (_dtd != null) {
      return _dtd!;
    }
    final Uri? discovered = uriOverride ?? dtdUri ?? _discoverActiveDtdUri();
    Uri? effectiveUri =
        discovered ?? await _autoLaunchPreviewDaemon(projectPath: projectPath, filePath: filePath);

    if (effectiveUri == null) {
      throw StateError('DTD URI is not specified and no active connection exists.');
    }

    _dtd = dtdConnector != null
        ? await dtdConnector!(effectiveUri)
        : await DartToolingDaemon.connect(effectiveUri);

    try {
      final RegisteredServicesResponse registeredServices = await _dtd!.getRegisteredServices();
      final bool hasWidgetPreview =
          registeredServices.dtdServices.any(
            (String s) =>
                s == WidgetPreviewDtdServices.kWidgetPreviewServiceRoot ||
                s.startsWith('${WidgetPreviewDtdServices.kWidgetPreviewServiceRoot}-'),
          ) ||
          registeredServices.clientServices.any((s) {
            final String name = s.name;
            return name == WidgetPreviewDtdServices.kWidgetPreviewServiceRoot ||
                name.startsWith('${WidgetPreviewDtdServices.kWidgetPreviewServiceRoot}-');
          });

      if (!hasWidgetPreview && uriOverride == null) {
        await _dtd!.close();
        _dtd = null;

        effectiveUri = await _autoLaunchPreviewDaemon(projectPath: projectPath, filePath: filePath);

        if (effectiveUri == null) {
          throw StateError('DTD URI is not specified and no active connection exists.');
        }

        _dtd = dtdConnector != null
            ? await dtdConnector!(effectiveUri)
            : await DartToolingDaemon.connect(effectiveUri);
      }
    } on Object catch (e) {
      logger.printTrace('Error verifying DTD services: $e');
    }

    try {
      unawaited(
        _dtd?.done.whenComplete(() {
          _dtd = null;
        }),
      );
    } on Object catch (_) {}
    return _dtd!;
  }

  Uri? _discoverActiveDtdUri() {
    final String? home =
        globals.platform.environment['HOME'] ?? globals.platform.environment['USERPROFILE'];
    if (home != null) {
      final Directory dtdDir = fs.directory(fs.path.join(home, '.dart_tooling_daemon'));
      if (dtdDir.existsSync()) {
        final List<FileSystemEntity> entities = dtdDir.listSync()
          ..sort((a, b) {
            try {
              return b.statSync().modified.compareTo(a.statSync().modified);
            } on Object catch (_) {
              return 0;
            }
          });
        for (final entity in entities) {
          if (entity is File && entity.path.endsWith('.json')) {
            try {
              final content = jsonDecode(entity.readAsStringSync()) as Map<String, dynamic>;
              if (content['ws_uri'] is String) {
                return Uri.parse(content['ws_uri'] as String);
              }
            } on Object catch (_) {}
          }
        }
      }
    }
    return null;
  }

  Future<void> _ensureScaffoldMounted(DartToolingDaemon dtd, String previewId) async {
    try {
      final RegisteredServicesResponse services = await dtd.getRegisteredServices();
      final bool hasScaffold = services.clientServices.any(
        (service) => service.name.startsWith('PreviewScaffold'),
      );
      if (!hasScaffold) {
        final DTDResponse webUrlResp = await dtd.call(
          WidgetPreviewDtdServices.kWidgetPreviewServiceRoot,
          WidgetPreviewDtdServices.kGetWebPreviewUrl,
        );
        final webUrl = webUrlResp.result['url'] as String?;
        if (webUrl != null) {
          final previewParam = previewId.isNotEmpty
              ? '/?previewId=${Uri.encodeComponent(previewId)}'
              : '/';
          final targetUrl = '$webUrl$previewParam';
          await io.Process.start('google-chrome', <String>[
            '--headless=new',
            '--disable-gpu',
            '--no-sandbox',
            targetUrl,
          ]);
          for (var i = 0; i < 20; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
            final RegisteredServicesResponse updated = await dtd.getRegisteredServices();
            if (updated.clientServices.any(
              (service) => service.name.startsWith('PreviewScaffold'),
            )) {
              break;
            }
          }
        }
      }
    } on Object catch (e) {
      logger.printTrace('Could not auto-mount preview in headless browser: $e');
    }
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
      _dtd = null;
      return McpToolResult.text('Tool execution error: $e', isError: true);
    }
  }

  Future<McpToolResult> _handleListPreviews(Map<String, Object?> params) async {
    final filePath = params['filePath'] as String?;
    final previews = <Map<String, Object?>>[];

    if (_dtd != null) {
      try {
        final DTDResponse result = await _dtd!.call(
          'Lsp',
          filePath != null
              ? 'dart/textDocument/getFlutterWidgetPreviews'
              : 'dart/workspace/getFlutterWidgetPreviews',
          params: filePath != null ? {'uri': Uri.file(filePath).toString()} : null,
        );
        final rawPreviews = result.result['result'] as Map<String, Object?>?;
        if (rawPreviews != null && rawPreviews['previews'] is List) {
          for (final item in rawPreviews['previews']! as List) {
            if (item is Map) {
              final map = Map<String, Object?>.from(item);
              final previewAnnotation = map['previewAnnotation'] as String?;
              final functionName = map['functionName'] as String?;
              final scriptUriStr = map['scriptUri'] as String?;

              // Extract name from previewAnnotation or direct map fields
              String? name;
              if (previewAnnotation != null) {
                final RegExpMatch? match = RegExp(
                  r'''name:\s*['"]([^'"]+)['"]''',
                ).firstMatch(previewAnnotation);
                name = match?.group(1);
              }

              name ??= map['name'] as String? ?? map['title'] as String?;

              final String previewId = name ?? functionName ?? (map['id'] as String?) ?? 'preview';
              final String? parsedFilePath = scriptUriStr != null
                  ? Uri.tryParse(scriptUriStr)?.toFilePath()
                  : (map['filePath'] as String? ?? map['path'] as String?);

              previews.add(<String, Object?>{
                ...map,
                'name': name,
                'previewId': previewId,
                'filePath': parsedFilePath ?? filePath,
              });
            }
          }
        }
      } on Object catch (e) {
        logger.printTrace('Error querying LSP for previews over DTD: $e');
      }
    }

    if (filePath != null) {
      final File file = fs.file(filePath);
      if (file.existsSync()) {
        try {
          final String content = file.readAsStringSync();
          final Iterable<RegExpMatch> previewMatches = RegExp(
            r'''@Preview\s*\((?:[^)]*name:\s*['"]([^'"]+)['"])?[^)]*\)''',
          ).allMatches(content);

          for (final match in previewMatches) {
            final String? name = match.group(1);
            final String previewId = name ?? 'preview';
            if (!previews.any((p) => p['previewId'] == previewId)) {
              previews.add(<String, Object?>{
                'filePath': file.path,
                'name': name,
                'previewId': previewId,
              });
            }
          }
        } on Object catch (e) {
          logger.printTrace('Error scanning file ${file.path} for previews: $e');
        }
      }
    }

    if (previews.isEmpty) {
      final Directory libDir = fs.directory(fs.path.join(fs.currentDirectory.path, 'lib'));
      final List<File> filesToScan = filePath != null
          ? <File>[fs.file(filePath)]
          : (libDir.existsSync()
                ? libDir
                      .listSync(recursive: true)
                      .whereType<File>()
                      .where((File f) => f.path.endsWith('.dart'))
                      .toList()
                : <File>[]);

      for (final file in filesToScan) {
        if (!file.existsSync()) {
          continue;
        }
        try {
          final String content = file.readAsStringSync();
          final Iterable<RegExpMatch> previewMatches = RegExp(
            r'''@Preview\s*\((?:[^)]*name:\s*['"]([^'"]+)['"])?[^)]*\)''',
          ).allMatches(content);

          for (final match in previewMatches) {
            final String? name = match.group(1);
            final String previewId = name ?? 'preview';
            previews.add(<String, Object?>{
              'filePath': file.path,
              'name': name,
              'previewId': previewId,
            });
          }
        } on Object catch (e) {
          logger.printTrace('Error scanning file ${file.path} for previews: $e');
        }
      }
    }

    final summary = previews.isEmpty
        ? 'No widget previews discovered.'
        : 'Discovered ${previews.length} widget preview(s):\n'
              '${previews.map((p) => '- **${p["name"] ?? p["previewId"]}** (previewId: `${p["previewId"] ?? p["name"]}`, file: `${p["filePath"] ?? "N/A"}`)').join('\n')}';

    return McpToolResult.text(
      summary,
      structuredContent: <String, Object?>{'previews': previews, 'totalCount': previews.length},
    );
  }

  Future<String> _findWidgetPreviewService(DartToolingDaemon dtd) async {
    for (var i = 0; i < 10; i++) {
      try {
        final RegisteredServicesResponse registered = await dtd.getRegisteredServices();
        final String? found =
            registered.dtdServices.firstWhereOrNull(
              (String s) =>
                  s == WidgetPreviewDtdServices.kWidgetPreviewServiceRoot ||
                  s.startsWith('${WidgetPreviewDtdServices.kWidgetPreviewServiceRoot}-'),
            ) ??
            registered.clientServices
                .map((dynamic s) {
                  try {
                    return (s as dynamic).name as String?;
                  } on Object catch (_) {
                    return s.toString();
                  }
                })
                .firstWhereOrNull(
                  (String? s) =>
                      s != null &&
                      (s == WidgetPreviewDtdServices.kWidgetPreviewServiceRoot ||
                          s.startsWith('${WidgetPreviewDtdServices.kWidgetPreviewServiceRoot}-')),
                );
        if (found != null) {
          return found;
        }
      } on Object catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return WidgetPreviewDtdServices.kWidgetPreviewServiceRoot;
  }

  Future<String> _findPreviewScaffoldService(DartToolingDaemon dtd) async {
    for (var i = 0; i < 20; i++) {
      try {
        final RegisteredServicesResponse registered = await dtd.getRegisteredServices();
        final String? found =
            registered.dtdServices.firstWhereOrNull(
              (String s) => s == 'PreviewScaffold' || s.startsWith('PreviewScaffold-'),
            ) ??
            registered.clientServices
                .map((dynamic s) {
                  try {
                    return (s as dynamic).name as String?;
                  } on Object catch (_) {
                    return s.toString();
                  }
                })
                .firstWhereOrNull(
                  (String? s) =>
                      s != null && (s == 'PreviewScaffold' || s.startsWith('PreviewScaffold-')),
                );
        if (found != null) {
          return found;
        }
      } on Object catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return 'PreviewScaffold';
  }

  Future<McpToolResult> _handleStartPreviewSession(Map<String, Object?> params) async {
    final dtdUrlString = params['dtdUrl'] as String?;
    final projectPath = params['projectPath'] as String?;
    final Uri? targetUri = dtdUrlString != null && dtdUrlString.isNotEmpty
        ? Uri.tryParse(dtdUrlString)
        : null;

    DartToolingDaemon dtd;
    try {
      dtd = await _ensureDtd(targetUri, projectPath: projectPath);
    } on Object catch (e) {
      return McpToolResult.text(
        'Could not connect to Dart Tooling Daemon (DTD): $e. '
        'Ensure a widget preview session or DTD instance is running, or provide "dtdUrl".',
        isError: true,
      );
    }

    final String serviceName = await _findWidgetPreviewService(dtd);
    final DTDResponse response = await dtd.call(
      serviceName,
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

    final filePath = params['filePath'] as String?;
    final projectPath = params['projectPath'] as String?;
    final DartToolingDaemon dtd = await _ensureDtd(
      null,
      projectPath: projectPath,
      filePath: filePath,
    );

    final outputPath = params['outputPath'] as String?;
    final bool returnImage = params['returnImage'] as bool? ?? true;
    final double devicePixelRatio = (params['devicePixelRatio'] as num?)?.toDouble() ?? 2.0;

    await _ensureScaffoldMounted(dtd, previewId);

    final String scaffoldService = await _findPreviewScaffoldService(dtd);
    final DTDResponse response = await dtd.call(
      scaffoldService,
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
      text:
          'Successfully rendered "$previewId" (${result.width}x${result.height} px, DPR: ${result.devicePixelRatio}).'
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
    final String previewId =
        previewIdParam ??
        'synthetic_${widgetName.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}';
    final rawWrappers = params['wrappers'] as List<Object?>?;
    final List<String> wrappers =
        rawWrappers?.cast<String>() ?? const <String>['Material', 'Directionality'];
    final bool autoCleanup = params['autoCleanup'] as bool? ?? true;

    final synthetic = SyntheticPreviewDetails(
      constructorExpression: constructorExpression,
      filePath: filePath,
      previewId: previewId,
      widgetName: widgetName,
      wrappers: wrappers,
    );

    final DartToolingDaemon dtd = await _ensureDtd(null, filePath: filePath);
    final String serviceName = await _findWidgetPreviewService(dtd);

    // Register synthetic preview.
    await dtd.call(
      serviceName,
      WidgetPreviewDtdServices.kRegisterSyntheticPreview,
      params: synthetic.toJson(),
    );

    // Trigger fast hot reload.
    await dtd.call(serviceName, WidgetPreviewDtdServices.kHotReloadPreviewer);

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
          serviceName,
          WidgetPreviewDtdServices.kUnregisterSyntheticPreview,
          params: <String, Object?>{'previewId': previewId},
        );
      }
    }
  }

  Future<McpToolResult> _handleGetLayoutDiagnostics(Map<String, Object?> params) async {
    final filePath = params['filePath'] as String?;
    final DartToolingDaemon dtd = await _ensureDtd(null, filePath: filePath);

    final previewId = params['previewId'] as String?;
    final bool clearAfterRead = params['clearAfterRead'] as bool? ?? false;

    final String scaffoldService = await _findPreviewScaffoldService(dtd);
    final DTDResponse response = await dtd.call(
      scaffoldService,
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

  /// Starts the Model Context Protocol (MCP) server listening for JSON-RPC 2.0 requests over stdio.
  Future<void> runStdio({Stream<List<int>>? input, io.IOSink? output}) async {
    final Stream<String> lines = (input ?? globals.stdio.stdin)
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    final io.IOSink sink = output ?? globals.stdio.stdout;

    await for (final String line in lines) {
      if (line.trim().isEmpty) {
        continue;
      }
      try {
        if (jsonDecode(line) case final Map<String, Object?> request) {
          final Object? id = request['id'];
          final method = request['method'] as String?;
          final Map<String, Object?> params =
              (request['params'] as Map?)?.cast<String, Object?>() ?? <String, Object?>{};

          if (method == 'initialize') {
            final response = <String, Object?>{
              'jsonrpc': '2.0',
              if (id != null) 'id': id,
              'result': <String, Object?>{
                'protocolVersion': '2024-11-05',
                'capabilities': <String, Object?>{'tools': <String, Object?>{}},
                'serverInfo': <String, Object?>{
                  'name': 'flutter-widget-preview',
                  'version': '1.0.0',
                },
              },
            };
            sink.writeln(jsonEncode(response));
          } else if (method == 'notifications/initialized') {
            // No-op for initialized notification
          } else if (method == 'tools/list') {
            final response = <String, Object?>{
              'jsonrpc': '2.0',
              if (id != null) 'id': id,
              'result': <String, Object?>{'tools': toolDefinitions.map((t) => t.toJson()).toList()},
            };
            sink.writeln(jsonEncode(response));
          } else if (method == 'tools/call') {
            final String toolName = params['name'] as String? ?? '';
            final Map<String, Object?> arguments =
                (params['arguments'] as Map?)?.cast<String, Object?>() ?? <String, Object?>{};
            final McpToolResult toolResult = await callTool(toolName, arguments);
            final response = <String, Object?>{
              'jsonrpc': '2.0',
              if (id != null) 'id': id,
              'result': <String, Object?>{
                'content': toolResult.content,
                'isError': toolResult.isError,
                if (toolResult.structuredContent != null)
                  'structuredContent': toolResult.structuredContent,
              },
            };
            sink.writeln(jsonEncode(response));
          } else if (method == 'ping') {
            sink.writeln(
              jsonEncode(<String, Object?>{
                'jsonrpc': '2.0',
                if (id != null) 'id': id,
                'result': <String, Object?>{},
              }),
            );
          } else {
            if (id != null) {
              sink.writeln(
                jsonEncode(<String, Object?>{
                  'jsonrpc': '2.0',
                  'id': id,
                  'error': <String, Object?>{
                    'code': -32601,
                    'message': 'Method not found: $method',
                  },
                }),
              );
            }
          }
        }
      } on Object catch (e) {
        logger.printTrace('MCP stdio parsing/execution error: $e');
      }
    }
  }

  /// Closes active DTD connections and releases resources.
  Future<void> dispose() async {
    if (_dtd != null) {
      await _dtd!.close();
      _dtd = null;
    }
  }
}

// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:meta/meta.dart';

import '../base/common.dart';
import '../base/file_system.dart';
import '../base/io.dart';
import '../base/logger.dart';
import '../base/process.dart';
import '../context/tool_context.dart';
import '../convert.dart';
import '../project.dart';
import '../runner/flutter_command.dart';
import '../web/web_options.dart';
import 'dtd_types.dart';
import 'preview_session_client.dart';
import 'utils.dart';

abstract base class _WidgetPreviewCliSubCommand extends FlutterCommand {
  _WidgetPreviewCliSubCommand({
    required super.toolContext,
    @visibleForTesting this.sessionClientOverride,
  });

  static const kBrightness = 'brightness';
  static const kDtdUrl = 'dtd-url';
  static const kFile = 'file';
  static const kHeight = 'height';
  static const kImage = 'image';
  static const kOutput = 'output';
  static const kPixelRatio = 'pixel-ratio';
  static const kSync = 'sync';
  static const kTextScaleFactor = 'text-scale-factor';
  static const kWidth = 'width';

  static const _kCodeKey = 'code';
  static const _kDarkBrightness = 'dark';
  static const _kDefaultCommandFailedMessage = 'Command failed.';
  static const _kErrorKey = 'error';
  static const _kLightBrightness = 'light';
  static const _kPreviewIdKey = 'previewId';

  static const fileOption = StringOptionDescriptor(
    name: kFile,
    help:
        'Filter listed widget previews to those defined in the specified file '
        'path or package URI.',
  );

  static const dtdUrlOption = StringOptionDescriptor(
    name: kDtdUrl,
    help: 'The address of an existing Dart Tooling Daemon instance to connect to.',
    verboseOnly: true,
  );

  static const syncOption = FlagOptionDescriptor(
    name: kSync,
    defaultsTo: true,
    help:
        'Synchronize on-disk edits and reload the previewer before querying '
        'previews.',
  );

  static const widthOption = StringOptionDescriptor(
    name: kWidth,
    help: 'Override the width of the preview in logical pixels.',
  );

  static const heightOption = StringOptionDescriptor(
    name: kHeight,
    help: 'Override the height of the preview in logical pixels.',
  );

  static const brightnessOption = StringOptionDescriptor(
    name: kBrightness,
    help: 'Override the theme brightness ("light" or "dark").',
  );

  static const pixelRatioOption = StringOptionDescriptor(
    name: kPixelRatio,
    help: 'Override the device pixel ratio used when rendering the snapshot.',
  );

  static const textScaleFactorOption = StringOptionDescriptor(
    name: kTextScaleFactor,
    help: 'Override the text scale factor used when rendering the preview.',
  );

  static const imageOption = FlagOptionDescriptor(
    name: kImage,
    defaultsTo: true,
    help: 'Whether to include the rendered PNG image in the output.',
  );

  static const outputOption = StringOptionDescriptor(
    name: kOutput,
    abbr: 'o',
    help: 'Write the captured PNG image to the specified file path.',
  );

  static const listOptions = <OptionDescriptor<Object?>>[
    CommonOptions.machine,
    fileOption,
    dtdUrlOption,
    syncOption,
    WidgetPreviewOptions.buildHooksOption,
    WebOptions.webBrowserFlags,
  ];

  static const snapshotOptions = <OptionDescriptor<Object?>>[
    CommonOptions.machine,
    dtdUrlOption,
    widthOption,
    heightOption,
    brightnessOption,
    pixelRatioOption,
    textScaleFactorOption,
    imageOption,
    syncOption,
    outputOption,
    WidgetPreviewOptions.buildHooksOption,
    WebOptions.webBrowserFlags,
  ];

  @visibleForTesting
  final WidgetPreviewSessionClient? sessionClientOverride;

  WidgetPreviewSessionClient _createOrGetClient() =>
      sessionClientOverride ?? WidgetPreviewSessionClient(toolContext: toolContext);

  FlutterCommandResult? _lastCommandResult;

  /// The most recent [FlutterCommandResult] produced by [verifyThenRunCommand].
  @visibleForTesting
  FlutterCommandResult? get lastCommandResult => _lastCommandResult;

  String? get _machineErrorPreviewId => null;

  @override
  bool get shouldUpdateCache => false;

  @override
  Future<FlutterCommandResult> verifyThenRunCommand(String? commandPath) async {
    try {
      final FlutterCommandResult result = await super.verifyThenRunCommand(commandPath);
      _lastCommandResult = result;
      return result;
    } on ToolExit catch (error) {
      if (getValue(CommonOptions.machine)) {
        _writeMachineError(
          toolContext.stdio,
          message: error.message ?? _kDefaultCommandFailedMessage,
          previewId: _machineErrorPreviewId,
        );
        final failResult = FlutterCommandResult.fail();
        _lastCommandResult = failResult;
        return failResult;
      }
      rethrow;
    }
  }

  @override
  Future<void> run() async {
    _lastCommandResult = null;
    await super.run();
    if (_lastCommandResult?.exitStatus == ExitStatus.fail) {
      throw ProcessExit(1);
    }
  }

  static double? _parsePositiveDoubleOption(
    FlutterCommand command,
    StringOptionDescriptor descriptor,
  ) {
    final String? raw = command.getValue(descriptor);
    if (raw == null) {
      return null;
    }
    final double? parsed = double.tryParse(raw);
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      throwToolExit(
        'Invalid value for "--${descriptor.name}": "$raw". '
        'Must be a positive finite number.',
      );
    }
    return parsed;
  }

  static String? _parseBrightnessOption(FlutterCommand command) {
    final String? raw = command.getValue(brightnessOption);
    if (raw == null) {
      return null;
    }
    if (raw != _kLightBrightness && raw != _kDarkBrightness) {
      throwToolExit(
        'Invalid value for "--$kBrightness": "$raw". '
        'Allowed values are "$_kLightBrightness" and "$_kDarkBrightness".',
      );
    }
    return raw;
  }

  static void _writeMachineError(
    Stdio stdio, {
    required String message,
    int? code,
    String? previewId,
  }) {
    stdio.stdout.writeln(
      jsonEncode(<String, Object?>{
        _kErrorKey: message,
        _kCodeKey: ?code,
        _kPreviewIdKey: ?previewId,
      }),
    );
  }
}

/// Lists discovered widget previews in the current Flutter project.
final class WidgetPreviewListCommand extends _WidgetPreviewCliSubCommand {
  WidgetPreviewListCommand({
    required super.toolContext,
    @visibleForTesting super.sessionClientOverride,
    bool verbose = false,
  }) {
    argParser.addDescriptors(_WidgetPreviewCliSubCommand.listOptions, verboseHelp: verbose);
  }

  static const kList = 'list';

  @override
  String get description => 'Lists widget previews in the current project.';

  @override
  String get name => kList;

  @override
  Future<FlutterCommandResult> runCommand() async {
    final bool machine = getValue(CommonOptions.machine);
    final ToolContext(:Logger logger, :Stdio stdio) = toolContext;
    final WidgetPreviewSessionClient client = _createOrGetClient();
    try {
      final (:Directory? explicitProjectDirectory, :FlutterProject rootProject) = client
          .resolveRootProject(this, allowPositionalDirectory: true);
      final String? rawFile = getValue(_WidgetPreviewCliSubCommand.fileOption);
      final String? dtdUrl = getValue(_WidgetPreviewCliSubCommand.dtdUrlOption);
      final bool sync = getValue(_WidgetPreviewCliSubCommand.syncOption);
      final bool buildHooks = getValue(WidgetPreviewOptions.buildHooksOption);
      final List<String> webBrowserFlags = getValue(WebOptions.webBrowserFlags);
      final String? fileUri = client.resolveFileFilter(
        rawFile,
        explicitProjectDirectory: explicitProjectDirectory,
      );

      final PreviewListResponse response = await client.withSession(
        buildHooks: buildHooks,
        dtdUrl: dtdUrl,
        rootProject: rootProject,
        webBrowserFlags: webBrowserFlags,
        action: (WidgetPreviewActiveSession session) =>
            client.listPreviews(session: session, fileUri: fileUri, sync: sync),
      );

      if (machine) {
        stdio.stdout.writeln(jsonEncode(response.toJson()));
      } else {
        _printHumanPreviewList(logger, response);
      }
      return FlutterCommandResult.success();
    } on RpcException catch (error) {
      if (machine) {
        _WidgetPreviewCliSubCommand._writeMachineError(
          stdio,
          code: error.code,
          message: error.message,
        );
        return FlutterCommandResult.fail();
      }
      throwToolExit(error.message.isNotEmpty ? error.message : error.toString());
    } on ToolExit catch (error) {
      if (machine) {
        _WidgetPreviewCliSubCommand._writeMachineError(
          stdio,
          message: error.message ?? _WidgetPreviewCliSubCommand._kDefaultCommandFailedMessage,
        );
        return FlutterCommandResult.fail();
      }
      rethrow;
    }
  }

  static void _printHumanPreviewList(Logger logger, PreviewListResponse response) {
    final List<PreviewEntry> previews = response.previews;
    if (previews.isEmpty) {
      logger.printStatus('No widget previews found.');
      return;
    }
    logger.printStatus('Found ${previews.length} widget preview(s):');
    for (final entry in previews) {
      final namePart = entry.name != null ? ' "${entry.name}"' : '';
      final sizePart = (entry.width != null || entry.height != null)
          ? ' (${entry.width ?? '?'}x${entry.height ?? '?'})'
          : '';
      final statusPart = entry.hasError ? ' [ERROR: ${entry.errorMessage ?? 'invalid'}]' : '';
      logger.printStatus('  - ${entry.id} [${entry.group}]$namePart$sizePart$statusPart');
    }
  }
}

/// Captures an off-screen rendered snapshot and structured diagnostics for a
/// single widget preview.
final class WidgetPreviewSnapshotCommand extends _WidgetPreviewCliSubCommand {
  WidgetPreviewSnapshotCommand({
    required super.toolContext,
    @visibleForTesting super.sessionClientOverride,
    bool verbose = false,
  }) {
    argParser.addDescriptors(_WidgetPreviewCliSubCommand.snapshotOptions, verboseHelp: verbose);
  }

  static const kSnapshot = 'snapshot';

  @override
  String? get _machineErrorPreviewId => argResults?.rest.firstOrNull;

  @override
  String get description => 'Captures a snapshot and diagnostics for a widget preview.';

  @override
  String get name => kSnapshot;

  @override
  Future<FlutterCommandResult> runCommand() async {
    final bool machine = getValue(CommonOptions.machine);
    final ToolContext(:FileSystem fs, :Logger logger, :Stdio stdio) = toolContext;
    final List<String> rest = argResults?.rest ?? const <String>[];
    final String? previewIdCandidate = rest.firstOrNull;
    final WidgetPreviewSessionClient client = _createOrGetClient();

    try {
      if (rest.isEmpty) {
        throwToolExit('A preview ID or name must be provided.');
      }
      if (rest.length > 1) {
        throwToolExit('Only one preview ID should be provided.');
      }
      final String previewId = rest.single;
      final double? width = _WidgetPreviewCliSubCommand._parsePositiveDoubleOption(
        this,
        _WidgetPreviewCliSubCommand.widthOption,
      );
      final double? height = _WidgetPreviewCliSubCommand._parsePositiveDoubleOption(
        this,
        _WidgetPreviewCliSubCommand.heightOption,
      );
      final double? pixelRatio = _WidgetPreviewCliSubCommand._parsePositiveDoubleOption(
        this,
        _WidgetPreviewCliSubCommand.pixelRatioOption,
      );
      final double? textScaleFactor = _WidgetPreviewCliSubCommand._parsePositiveDoubleOption(
        this,
        _WidgetPreviewCliSubCommand.textScaleFactorOption,
      );
      final String? brightness = _WidgetPreviewCliSubCommand._parseBrightnessOption(this);
      final String? dtdUrl = getValue(_WidgetPreviewCliSubCommand.dtdUrlOption);
      final bool sync = getValue(_WidgetPreviewCliSubCommand.syncOption);
      final bool buildHooks = getValue(WidgetPreviewOptions.buildHooksOption);
      final List<String> webBrowserFlags = getValue(WebOptions.webBrowserFlags);
      final bool includeImageInStdout = getValue(_WidgetPreviewCliSubCommand.imageOption);
      final String? outputPath = getValue(_WidgetPreviewCliSubCommand.outputOption);
      final bool hasOutputFile = outputPath != null && outputPath.isNotEmpty;
      final bool requestImageFromScaffold = includeImageInStdout || hasOutputFile;

      final (explicitProjectDirectory: _, :FlutterProject rootProject) = client.resolveRootProject(
        this,
        allowPositionalDirectory: false,
      );

      final CapturePreviewResponse response = await client.withSession(
        buildHooks: buildHooks,
        dtdUrl: dtdUrl,
        rootProject: rootProject,
        webBrowserFlags: webBrowserFlags,
        action: (WidgetPreviewActiveSession session) => client.capturePreview(
          brightness: brightness,
          height: height,
          includeImage: requestImageFromScaffold,
          pixelRatio: pixelRatio,
          previewId: previewId,
          session: session,
          sync: sync,
          textScaleFactor: textScaleFactor,
          width: width,
        ),
      );

      if (hasOutputFile && response.imageBase64 != null) {
        final File outputFile = fs.file(outputPath);
        outputFile.parent.createSync(recursive: true);
        outputFile.writeAsBytesSync(base64.decode(response.imageBase64!));
      }

      final outputResponse = includeImageInStdout
          ? response
          : CapturePreviewResponse(
              diagnostics: response.diagnostics,
              hasErrors: response.hasErrors,
              name: response.name,
              pixelRatio: response.pixelRatio,
              previewId: response.previewId,
              renderedHeight: response.renderedHeight,
              renderedWidth: response.renderedWidth,
            );

      if (machine) {
        stdio.stdout.writeln(jsonEncode(outputResponse.toJson()));
      } else {
        _printHumanSnapshot(
          logger,
          outputPath: hasOutputFile && response.imageBase64 != null ? outputPath : null,
          response: outputResponse,
        );
      }

      return outputResponse.hasErrors
          ? FlutterCommandResult.fail()
          : FlutterCommandResult.success();
    } on RpcException catch (error) {
      if (machine) {
        _WidgetPreviewCliSubCommand._writeMachineError(
          stdio,
          code: error.code,
          message: error.message,
          previewId: previewIdCandidate,
        );
        return FlutterCommandResult.fail();
      }
      throwToolExit(error.message.isNotEmpty ? error.message : error.toString());
    } on ToolExit catch (error) {
      if (machine) {
        _WidgetPreviewCliSubCommand._writeMachineError(
          stdio,
          message: error.message ?? _WidgetPreviewCliSubCommand._kDefaultCommandFailedMessage,
          previewId: previewIdCandidate,
        );
        return FlutterCommandResult.fail();
      }
      rethrow;
    }
  }

  static void _printHumanSnapshot(
    Logger logger, {
    required CapturePreviewResponse response,
    String? outputPath,
  }) {
    final nameSuffix = response.name != null ? ' (${response.name})' : '';
    logger.printStatus(
      'Captured preview ${response.previewId}$nameSuffix '
      '(${response.renderedWidth}x${response.renderedHeight} @ '
      '${response.pixelRatio}x).',
    );
    if (outputPath != null) {
      logger.printStatus('Saved snapshot to $outputPath.');
    }
    for (final PreviewDiagnostic diagnostic in response.diagnostics) {
      logger.printError(
        '[${diagnostic.phase.name}/${diagnostic.kind.wireValue}] '
        '${diagnostic.summary}',
      );
    }
  }
}

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
import 'analytics.dart';
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
  static const kPumpMs = 'pump-ms';
  static const kSync = 'sync';
  static const kTextScaleFactor = 'text-scale-factor';
  static const kWidth = 'width';

  static const _kMaxPumpMs = 2000;
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

  static const pumpMsOption = StringOptionDescriptor(
    name: kPumpMs,
    help: 'Optional settle delay in milliseconds (0-2000) before capturing the snapshot.',
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
  ];

  static const snapshotOptions = <OptionDescriptor<Object?>>[
    CommonOptions.machine,
    dtdUrlOption,
    widthOption,
    heightOption,
    brightnessOption,
    pixelRatioOption,
    pumpMsOption,
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
      return _lastCommandResult = await super.verifyThenRunCommand(commandPath);
    } on ToolExit catch (error) {
      if (getValue(CommonOptions.machine)) {
        _writeMachineError(
          message: error.message ?? _kDefaultCommandFailedMessage,
          previewId: _machineErrorPreviewId,
        );
        return _lastCommandResult = FlutterCommandResult.fail();
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

  Future<FlutterCommandResult> _runWithMachineErrorHandling(
    Future<FlutterCommandResult> Function() action,
  ) async {
    final bool machine = getValue(CommonOptions.machine);
    try {
      return await action();
    } on RpcException catch (error) {
      if (machine) {
        _writeMachineError(
          code: error.code,
          message: error.message,
          previewId: _machineErrorPreviewId,
        );
        return FlutterCommandResult.fail();
      }
      throwToolExit(error.message.isNotEmpty ? error.message : error.toString());
    } on ToolExit catch (error) {
      if (machine) {
        _writeMachineError(
          message: error.message ?? _kDefaultCommandFailedMessage,
          previewId: _machineErrorPreviewId,
        );
        return FlutterCommandResult.fail();
      }
      rethrow;
    }
  }

  double? _parsePositiveDoubleOption(StringOptionDescriptor descriptor) {
    final String? raw = getValue(descriptor);
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

  int? _parsePumpMsOption() {
    final String? raw = getValue(pumpMsOption);
    if (raw == null) {
      return null;
    }
    final int? parsed = int.tryParse(raw);
    if (parsed == null || parsed < 0 || parsed > _kMaxPumpMs) {
      throwToolExit(
        'Invalid value for "--$kPumpMs": "$raw". '
        'Must be an integer between 0 and $_kMaxPumpMs.',
      );
    }
    return parsed;
  }

  String? _parseBrightnessOption() {
    final String? raw = getValue(brightnessOption);
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

  void _writeMachineError({required String message, int? code, String? previewId}) {
    toolContext.stdio.stdout.writeln(
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

  /// Subcommand name for `flutter widget-preview list`.
  static const kList = 'list';

  @override
  String get description => 'Lists widget previews in the current project.';

  @override
  String get name => kList;

  @override
  Future<FlutterCommandResult> runCommand() => _runWithMachineErrorHandling(() async {
    final ToolContext(:Logger logger, :Stdio stdio) = toolContext;
    final WidgetPreviewSessionClient client = _createOrGetClient();
    final stopwatch = Stopwatch()..start();
    final (:Directory? explicitProjectDirectory, :FlutterProject rootProject) = client
        .resolveRootProject(this, allowPositionalDirectory: true);
    final String? fileUri = client.resolveFileFilter(
      getValue(_WidgetPreviewCliSubCommand.fileOption),
      explicitProjectDirectory: explicitProjectDirectory,
    );
    final PreviewListResponse response = await client.listPreviewsForProject(
      dtdUrl: getValue(_WidgetPreviewCliSubCommand.dtdUrlOption),
      fileUri: fileUri,
      rootProject: rootProject,
      sync: getValue(_WidgetPreviewCliSubCommand.syncOption),
    );
    WidgetPreviewAnalytics(analytics: analytics).reportListCompleted(
      elapsedMilliseconds: stopwatch.elapsedMilliseconds,
      previewCount: response.previews.length,
    );

    if (getValue(CommonOptions.machine)) {
      stdio.stdout.writeln(jsonEncode(response.toJson()));
    } else {
      _printHumanPreviewList(logger, response);
    }
    return FlutterCommandResult.success();
  });

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

  /// Subcommand name for `flutter widget-preview snapshot`.
  static const kSnapshot = 'snapshot';

  @override
  String? get _machineErrorPreviewId => argResults?.rest.firstOrNull;

  @override
  String get description => 'Captures a snapshot and diagnostics for a widget preview.';

  @override
  String get name => kSnapshot;

  @override
  Future<FlutterCommandResult> runCommand() => _runWithMachineErrorHandling(() async {
    final ToolContext(:FileSystem fs, :Logger logger, :Stdio stdio) = toolContext;
    final String previewId = switch (argResults?.rest) {
      <String>[final String id] => id,
      <String>[_, _, ...] => throwToolExit('Only one preview ID should be provided.'),
      _ => throwToolExit('A preview ID or name must be provided.'),
    };
    final WidgetPreviewSessionClient client = _createOrGetClient();
    final stopwatch = Stopwatch()..start();
    final double? width = _parsePositiveDoubleOption(_WidgetPreviewCliSubCommand.widthOption);
    final double? height = _parsePositiveDoubleOption(_WidgetPreviewCliSubCommand.heightOption);
    final double? pixelRatio = _parsePositiveDoubleOption(
      _WidgetPreviewCliSubCommand.pixelRatioOption,
    );
    final int? pumpMs = _parsePumpMsOption();
    final double? textScaleFactor = _parsePositiveDoubleOption(
      _WidgetPreviewCliSubCommand.textScaleFactorOption,
    );
    final String? brightness = _parseBrightnessOption();
    final bool includeImageInStdout = getValue(_WidgetPreviewCliSubCommand.imageOption);
    final String? outputPath = getValue(_WidgetPreviewCliSubCommand.outputOption);
    final bool hasOutputFile = outputPath != null && outputPath.isNotEmpty;

    final (explicitProjectDirectory: _, :FlutterProject rootProject) = client.resolveRootProject(
      this,
      allowPositionalDirectory: false,
    );

    final CapturePreviewResponse response = await client.withSession(
      buildHooks: getValue(WidgetPreviewOptions.buildHooksOption),
      dtdUrl: getValue(_WidgetPreviewCliSubCommand.dtdUrlOption),
      rootProject: rootProject,
      webBrowserFlags: getValue(WebOptions.webBrowserFlags),
      action: (WidgetPreviewActiveSession session) => client.capturePreview(
        brightness: brightness,
        height: height,
        includeImage: includeImageInStdout || hasOutputFile,
        pixelRatio: pixelRatio,
        previewId: previewId,
        pumpMs: pumpMs,
        session: session,
        sync: getValue(_WidgetPreviewCliSubCommand.syncOption),
        textScaleFactor: textScaleFactor,
        width: width,
      ),
    );

    if (hasOutputFile && response.imageBase64 != null) {
      final File outputFile = fs.file(outputPath);
      outputFile.parent.createSync(recursive: true);
      outputFile.writeAsBytesSync(base64.decode(response.imageBase64!));
    }

    final CapturePreviewResponse outputResponse = includeImageInStdout
        ? response
        : response.withoutImage();

    if (getValue(CommonOptions.machine)) {
      stdio.stdout.writeln(jsonEncode(outputResponse.toJson()));
    } else {
      _printHumanSnapshot(
        logger,
        outputPath: hasOutputFile && response.imageBase64 != null ? outputPath : null,
        response: outputResponse,
      );
    }

    WidgetPreviewAnalytics(analytics: analytics).reportSnapshotCompleted(
      elapsedMilliseconds: stopwatch.elapsedMilliseconds,
      hasErrors: outputResponse.hasErrors,
    );

    return outputResponse.hasErrors ? FlutterCommandResult.fail() : FlutterCommandResult.success();
  });

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

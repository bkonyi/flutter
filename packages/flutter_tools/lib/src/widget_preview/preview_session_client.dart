// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:dtd/dtd.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:meta/meta.dart';
import 'package:process/process.dart';

import '../artifacts.dart';
import '../base/common.dart';
import '../base/file_system.dart';
import '../base/io.dart';
import '../base/logger.dart';
import '../base/platform.dart';
import '../base/process.dart';
import '../cache.dart';
import '../context/tool_context.dart';
import '../convert.dart';
import '../project.dart';
import '../runner/flutter_command.dart';
import '../runner/flutter_command_runner.dart';
import 'dtd_services.dart';
import 'dtd_types.dart';
import 'utils.dart';

export 'preview_cli_commands.dart';

/// Callback signature for establishing a connection to a [DartToolingDaemon]
/// instance at [uri].
typedef DtdConnector = Future<DartToolingDaemon> Function(Uri uri);

/// Represents an active connection to a running widget preview DTD session.
class WidgetPreviewActiveSession {
  const WidgetPreviewActiveSession({
    required this.dtd,
    required this.info,
    required this.isEphemeral,
  });

  /// The connected [DartToolingDaemon] client.
  final DartToolingDaemon dtd;

  /// Metadata describing the connected widget preview service and scaffold.
  final PreviewServiceInfo info;

  /// Whether this session was spawned as a one-shot headless child process for
  /// a single CLI invocation.
  final bool isEphemeral;
}

/// Discovers or launches a widget preview DTD session and executes
/// `flutter widget-preview list` and `flutter widget-preview snapshot` RPCs.
class WidgetPreviewSessionClient {
  WidgetPreviewSessionClient({
    required this._toolContext,
    @visibleForTesting this._dtdConnector = DartToolingDaemon.connect,
    @visibleForTesting this._headlessStartupTimeout = kDefaultHeadlessStartupTimeout,
    @visibleForTesting this._processExitTimeout = kDefaultProcessExitTimeout,
    @visibleForTesting
    this._scaffoldReadyTimeout = const Duration(
      milliseconds: WidgetPreviewDtdServices.kDefaultSyncTimeoutMs,
    ),
  });

  static const kDtdUrl = 'dtd-url';
  static const kDefaultHeadlessStartupTimeout = Duration(minutes: 2);
  static const kDefaultProcessExitTimeout = Duration(seconds: 5);

  static const _kAppDataEnv = 'APPDATA';
  static const _kClosedPeerExactMessage = 'The client is closed.';
  static const _kClosedPeerMessagePrefix = 'The client closed';
  static const _kClosedSinkMessageFragment = 'Cannot add event after closing';
  static const _kDartDataHomeEnv = 'DART_DATA_HOME';
  static const _kDtdSubdir = 'dtd';
  static const _kErrorKey = 'error';
  static const _kEventKey = 'event';
  static const _kHeadlessFlag = 'headless';
  static const _kHomeEnv = 'HOME';
  static const _kIncludeImageKey = 'includeImage';
  static const _kInitializingEventName = 'widget_preview.initializing';
  static const _kLevelKey = 'level';
  static const _kLocalAppDataEnv = 'LOCALAPPDATA';
  static const _kLogMessageEventName = 'widget_preview.logMessage';
  static const _kMaxCapturedErrorLines = 50;
  static const _kMessageKey = 'message';
  static const _kParamsKey = 'params';
  static const _kPidKey = 'pid';
  static const _kStartSubcommand = 'start';
  static const _kStartedEventName = 'widget_preview.started';
  static const _kTaskkillBinary = 'taskkill';
  static const _kToolingDaemonCommand = 'tooling-daemon';
  static const _kToolingDaemonListFlag = '--list';
  static const _kUriKey = 'uri';
  static const _kWidgetPreviewCommandName = 'widget-preview';
  static const _kWsUriKey = 'wsUri';
  static const _kXdgDataHomeEnv = 'XDG_DATA_HOME';

  /// Matches WebSocket DTD URIs (`ws://` or `wss://`) in plain-text
  /// `dart tooling-daemon --list` output and daemon metadata files, stopping
  /// before whitespace or JSON/bracket delimiters so URIs can be extracted
  /// regardless of output formatting across SDK versions.
  static final _wsUriPattern = RegExp(r'''wss?://[^\s"'\],}]+''');

  final ToolContext _toolContext;
  final DtdConnector _dtdConnector;
  final Duration _headlessStartupTimeout;
  final Duration _processExitTimeout;
  final Duration _scaffoldReadyTimeout;

  /// Connects to an existing or ephemeral headless widget preview session for
  /// [rootProject] and executes [action].
  Future<T> withSession<T>({
    required Future<T> Function(WidgetPreviewActiveSession session) action,
    required FlutterProject rootProject,
    bool buildHooks = true,
    String? dtdUrl,
    List<String> webBrowserFlags = const <String>[],
  }) async {
    final String targetProjectRoot = _normalizeProjectRoot(rootProject.directory);
    final bool hasExistingScaffold = rootProject.widgetPreviewScaffold.existsSync();

    if (dtdUrl != null && dtdUrl.isNotEmpty) {
      final Uri? parsedUri = Uri.tryParse(dtdUrl);
      if (parsedUri == null || !parsedUri.hasScheme || parsedUri.host.isEmpty) {
        throwToolExit('Invalid value for "--$kDtdUrl": "$dtdUrl".');
      }
      final DartToolingDaemon dtd = await _connectToDtd(parsedUri);
      try {
        final PreviewServiceInfo? info;
        try {
          info = await _findMatchingServiceOnDtd(
            allowSingleServiceFallback: true,
            dtd: dtd,
            dtdUri: parsedUri,
            hasExistingScaffold: hasExistingScaffold,
            targetProjectRoot: targetProjectRoot,
          );
        } on StateError catch (error) {
          if (!_isClosedPeerStateError(error)) {
            rethrow;
          }
          throwToolExit(
            'DTD connection at $parsedUri closed while querying widget preview '
            'services: ${error.message}',
          );
        }
        if (info == null) {
          throwToolExit(
            'No active widget preview service for "$targetProjectRoot" found '
            'on DTD at $parsedUri.',
          );
        }
        return await action(WidgetPreviewActiveSession(dtd: dtd, info: info, isEphemeral: false));
      } finally {
        await _closeDtdQuietly(dtd);
      }
    }

    final List<Uri> candidateUris = await _discoverActiveDtdUris();
    for (final candidateUri in candidateUris) {
      DartToolingDaemon? dtd;
      try {
        dtd = await _dtdConnector(candidateUri);
      } on ToolExit {
        rethrow;
      } on Exception {
        continue;
      } on StateError catch (error) {
        if (!_isClosedPeerStateError(error)) {
          rethrow;
        }
        continue;
      }
      PreviewServiceInfo? matchingInfo;
      try {
        matchingInfo = await _findMatchingServiceOnDtd(
          allowSingleServiceFallback: false,
          dtd: dtd,
          dtdUri: candidateUri,
          hasExistingScaffold: hasExistingScaffold,
          targetProjectRoot: targetProjectRoot,
        );
      } on ToolExit {
        await _closeDtdQuietly(dtd);
        rethrow;
      } on Exception {
        await _closeDtdQuietly(dtd);
        continue;
      } on StateError catch (error) {
        await _closeDtdQuietly(dtd);
        if (!_isClosedPeerStateError(error)) {
          rethrow;
        }
        continue;
      }
      if (matchingInfo == null) {
        await _closeDtdQuietly(dtd);
        continue;
      }
      try {
        return await action(
          WidgetPreviewActiveSession(dtd: dtd, info: matchingInfo, isEphemeral: false),
        );
      } finally {
        await _closeDtdQuietly(dtd);
      }
    }

    return _withEphemeralHeadlessSession(
      action: action,
      buildHooks: buildHooks,
      rootProject: rootProject,
      targetProjectRoot: targetProjectRoot,
      webBrowserFlags: webBrowserFlags,
    );
  }

  /// Invokes `listPreviews` on [session].
  Future<PreviewListResponse> listPreviews({
    required WidgetPreviewActiveSession session,
    required bool sync,
    String? fileUri,
  }) async {
    final DTDResponse response = await _callDtd(
      session.dtd,
      session.info.previewService,
      WidgetPreviewDtdServices.kListPreviews,
      params: <String, Object?>{
        WidgetPreviewDtdServices.kSync: sync,
        if (fileUri != null && fileUri.isNotEmpty) WidgetPreviewDtdServices.kFileUri: fileUri,
      },
    );
    return PreviewListResponse.fromDTDResponse(response);
  }

  /// Synchronizes previews on [session] (when [sync] is `true`) and invokes
  /// `capturePreview` on the preview scaffold service.
  Future<CapturePreviewResponse> capturePreview({
    required bool includeImage,
    required String previewId,
    required WidgetPreviewActiveSession session,
    required bool sync,
    String? brightness,
    double? height,
    double? pixelRatio,
    double? textScaleFactor,
    double? width,
  }) async {
    if (sync) {
      final DTDResponse syncDtdResponse = await _callDtd(
        session.dtd,
        session.info.previewService,
        WidgetPreviewDtdServices.kSyncPreviews,
      );
      final syncResponse = SyncPreviewsResponse.fromDTDResponse(syncDtdResponse);
      if (!syncResponse.compileSuccess) {
        throwToolExit(syncResponse.compileError ?? 'Failed to synchronize widget previews.');
      }
    } else if (!session.info.scaffoldConnected) {
      await _waitForScaffoldReady(session);
    }

    final DTDResponse captureDtdResponse = await _callDtd(
      session.dtd,
      session.info.scaffoldService,
      WidgetPreviewDtdServices.kCapturePreview,
      params: <String, Object?>{
        CapturePreviewResponse.kPreviewId: previewId,
        _kIncludeImageKey: includeImage,
        PreviewEntry.kWidth: ?width,
        PreviewEntry.kHeight: ?height,
        CapturePreviewResponse.kPixelRatio: ?pixelRatio,
        PreviewEntry.kBrightness: ?brightness,
        PreviewEntry.kTextScaleFactor: ?textScaleFactor,
      },
    );
    return CapturePreviewResponse.fromDTDResponse(captureDtdResponse);
  }

  /// Resolves the Flutter workspace root project (and optional positional
  /// directory argument) for [command].
  ({Directory? explicitProjectDirectory, FlutterProject rootProject}) resolveRootProject(
    FlutterCommand command, {
    required bool allowPositionalDirectory,
  }) {
    final ToolContext(:FileSystem fs, :Logger logger, :FlutterProjectFactory projectFactory) =
        _toolContext;
    Directory? explicitProjectDirectory;
    final Directory projectDir;
    if (allowPositionalDirectory) {
      final List<String> rest = command.argResults?.rest ?? const <String>[];
      if (rest case <String>[final String directory]) {
        projectDir = fs.directory(directory);
        if (!projectDir.existsSync()) {
          throwToolExit('Could not find ${projectDir.path}.');
        }
        explicitProjectDirectory = projectDir;
      } else if (rest.length > 1) {
        throwToolExit('Only one directory should be provided.');
      } else {
        projectDir = fs.currentDirectory;
      }
    } else {
      projectDir = fs.currentDirectory;
    }
    logger.printTrace('Verifying that ${projectDir.path} is a Flutter project.');
    final FlutterProject flutterProject = projectFactory.fromDirectory(projectDir);
    if (!flutterProject.pubspecFile.existsSync()) {
      throwToolExit('${flutterProject.directory.path} is not a valid Flutter project.');
    }
    final FlutterProject? workspaceRoot = flutterProject.workspaceRoot;
    if (workspaceRoot != null) {
      logger.printTrace('Found workspace root at ${workspaceRoot.directory.path}');
      return (explicitProjectDirectory: explicitProjectDirectory, rootProject: workspaceRoot);
    }
    return (explicitProjectDirectory: explicitProjectDirectory, rootProject: flutterProject);
  }

  /// Normalizes a `--file` filter argument against [FileSystem.currentDirectory]
  /// (falling back to [explicitProjectDirectory] when provided).
  String? resolveFileFilter(String? rawFile, {Directory? explicitProjectDirectory}) {
    if (rawFile == null || rawFile.isEmpty) {
      return null;
    }
    if (rawFile.startsWith('package:') || rawFile.startsWith('dart:')) {
      return rawFile;
    }
    final FileSystem fs = _toolContext.fs;
    if (rawFile.startsWith('file:')) {
      final Uri? parsedUri = Uri.tryParse(rawFile);
      if (parsedUri != null && parsedUri.isScheme('file')) {
        return fs.file(fs.path.normalize(fs.path.fromUri(parsedUri))).uri.toString();
      }
      return rawFile;
    }
    final String resolvedPath;
    if (fs.path.isAbsolute(rawFile)) {
      resolvedPath = fs.path.normalize(rawFile);
    } else {
      final String cwdCandidate = fs.path.normalize(
        fs.path.join(fs.currentDirectory.path, rawFile),
      );
      if (explicitProjectDirectory != null && !fs.file(cwdCandidate).existsSync()) {
        resolvedPath = fs.path.normalize(
          fs.path.join(explicitProjectDirectory.absolute.path, rawFile),
        );
      } else {
        resolvedPath = cwdCandidate;
      }
    }
    return fs.file(resolvedPath).uri.toString();
  }

  Future<void> _waitForScaffoldReady(WidgetPreviewActiveSession session) async {
    final completer = Completer<void>();
    completer.future.ignore();
    var waitingForScaffold = true;
    final StreamSubscription<DTDEvent> subscription = session.dtd
        .onEvent(session.info.scaffoldStream)
        .listen((DTDEvent event) {
          if (!completer.isCompleted &&
              event.kind == WidgetPreviewDtdServices.kWidgetPreviewConnectedEvent) {
            completer.complete();
          }
        });
    unawaited(
      session.dtd.done.then<void>(
        (_) {
          if (waitingForScaffold && !completer.isCompleted) {
            completer.completeWithToolExit(
              'Connection to DTD closed before the widget preview scaffold became ready.',
            );
          }
        },
        onError: (Object error) {
          if (waitingForScaffold && !completer.isCompleted) {
            completer.completeWithToolExit(
              'Connection to DTD closed before the widget preview scaffold became ready: $error',
            );
          }
        },
      ),
    );
    try {
      await _streamListenDtd(session.dtd, session.info.scaffoldStream);
      final DTDResponse infoResponse = await _callDtd(
        session.dtd,
        session.info.previewService,
        WidgetPreviewDtdServices.kGetServiceInfo,
      );
      final latestInfo = PreviewServiceInfo.fromDTDResponse(infoResponse);
      if (latestInfo.scaffoldConnected) {
        return;
      }
      try {
        await completer.future.timeout(_scaffoldReadyTimeout);
      } on TimeoutException {
        throwToolExit(
          'Timed out waiting for the widget preview scaffold to connect after '
          '${_scaffoldReadyTimeout.inMilliseconds}ms.',
        );
      }
    } finally {
      waitingForScaffold = false;
      await subscription.cancel();
    }
  }

  static Future<DTDResponse> _callDtd(
    DartToolingDaemon dtd,
    String serviceName,
    String methodName, {
    Map<String, Object?>? params,
  }) async {
    try {
      return await dtd.call(serviceName, methodName, params: params);
    } on StateError catch (error) {
      if (!_isClosedPeerStateError(error)) {
        rethrow;
      }
      throwToolExit(
        'DTD connection closed while invoking "$serviceName.$methodName": '
        '${error.message}',
      );
    }
  }

  static Future<void> _streamListenDtd(DartToolingDaemon dtd, String streamId) async {
    try {
      await dtd.streamListen(streamId);
    } on RpcException catch (error) {
      if (error.code != RpcErrorCodes.kStreamAlreadySubscribed) {
        rethrow;
      }
    } on StateError catch (error) {
      if (!_isClosedPeerStateError(error)) {
        rethrow;
      }
      throwToolExit(
        'DTD connection closed while subscribing to "$streamId": '
        '${error.message}',
      );
    }
  }

  static Future<void> _closeDtdQuietly(DartToolingDaemon? dtd) async {
    if (dtd == null) {
      return;
    }
    try {
      await dtd.close();
    } on Exception {
      // Ignore transport errors from underlying WebSocket channels on close.
    } on StateError catch (error) {
      if (!_isClosedPeerStateError(error)) {
        rethrow;
      }
    }
  }

  static bool _isClosedPeerStateError(StateError error) {
    final String message = error.message;
    return message.startsWith(_kClosedPeerMessagePrefix) ||
        message == _kClosedPeerExactMessage ||
        message.contains(_kClosedSinkMessageFragment);
  }

  Future<DartToolingDaemon> _connectToDtd(Uri uri) async {
    try {
      return await _dtdConnector(uri);
    } on ToolExit {
      rethrow;
    } on Exception catch (error) {
      throwToolExit('Failed to connect to DTD at $uri: $error');
    } on StateError catch (error) {
      if (!_isClosedPeerStateError(error)) {
        rethrow;
      }
      throwToolExit('Failed to connect to DTD at $uri: $error');
    }
  }

  Future<PreviewServiceInfo?> _findMatchingServiceOnDtd({
    required bool allowSingleServiceFallback,
    required DartToolingDaemon dtd,
    required Uri dtdUri,
    required bool hasExistingScaffold,
    required String targetProjectRoot,
  }) async {
    final RegisteredServicesResponse registered = await dtd.getRegisteredServices();
    final candidateNames = <String>[
      for (final service in registered.clientServices)
        if (_isWidgetPreviewServiceName(service.name)) service.name,
    ];
    if (candidateNames.isEmpty && allowSingleServiceFallback) {
      candidateNames.add(WidgetPreviewDtdServices.kWidgetPreviewServiceRoot);
    }

    final fallbackInfos = <PreviewServiceInfo>[];
    for (final serviceName in candidateNames) {
      final PreviewServiceInfo info;
      try {
        final DTDResponse response = await dtd.call(
          serviceName,
          WidgetPreviewDtdServices.kGetServiceInfo,
        );
        final parsed = PreviewServiceInfo.fromDTDResponse(response);
        info = parsed.dtdUri.isNotEmpty
            ? parsed
            : PreviewServiceInfo(
                dtdUri: dtdUri.toString(),
                previewService: parsed.previewService,
                projectRoot: parsed.projectRoot,
                scaffoldConnected: parsed.scaffoldConnected,
                scaffoldService: parsed.scaffoldService,
                scaffoldStream: parsed.scaffoldStream,
                webPreviewUri: parsed.webPreviewUri,
              );
      } on RpcException catch (error) {
        if (error.code == RpcErrorCodes.kMethodNotFound) {
          final RegisteredServicesResponse refreshed = await dtd.getRegisteredServices();
          final bool stillRegistered = refreshed.clientServices.any(
            (service) => service.name == serviceName,
          );
          if (stillRegistered && (hasExistingScaffold || allowSingleServiceFallback)) {
            throwToolExit(
              'An incompatible older widget-preview session (Flutter < 3.50) is active on DTD '
              'at $dtdUri (service "$serviceName" does not support '
              '"${WidgetPreviewDtdServices.kGetServiceInfo}"). Stop the existing widget-preview '
              'session or upgrade Flutter before running headless commands.',
            );
          }
        }
        continue;
      }
      if (_projectRootsMatch(info.projectRoot, targetProjectRoot)) {
        return info;
      }
      fallbackInfos.add(info);
    }

    if (allowSingleServiceFallback) {
      if (fallbackInfos.length == 1) {
        return fallbackInfos.single;
      }
      if (fallbackInfos.length > 1) {
        throwToolExit(
          'Multiple widget preview services are registered on DTD at $dtdUri, '
          'and none match project root "$targetProjectRoot".',
        );
      }
    }
    return null;
  }

  static bool _isWidgetPreviewServiceName(String name) =>
      name == WidgetPreviewDtdServices.kWidgetPreviewServiceRoot ||
      name.startsWith('${WidgetPreviewDtdServices.kWidgetPreviewServiceRoot}-');

  Future<List<Uri>> _discoverActiveDtdUris() async {
    final ToolContext(
      :Artifacts artifacts,
      :FileSystem fs,
      :Platform platform,
      :ProcessManager processManager,
    ) = _toolContext;
    final discovered = <String, Uri>{};

    void recordUrisFromText(String text) {
      _extractDtdUrisFromText(text, discovered);
    }

    final String dartBinary = artifacts.getArtifactPath(Artifact.engineDartBinary);
    if (processManager.canRun(dartBinary)) {
      try {
        final ProcessResult result = await processManager.run(<String>[
          dartBinary,
          _kToolingDaemonCommand,
          _kToolingDaemonListFlag,
        ]);
        if (result.exitCode == 0 && result.stdout is String) {
          recordUrisFromText(result.stdout as String);
        }
      } on ProcessException {
        // Ignore failures when probing active tooling daemons.
      }
    }

    for (final Directory dir in _dtdMetadataDirectories(fs, platform)) {
      if (!dir.existsSync()) {
        continue;
      }
      try {
        for (final FileSystemEntity entity in dir.listSync()) {
          if (entity is File) {
            try {
              recordUrisFromText(entity.readAsStringSync());
            } on FileSystemException {
              continue;
            }
          }
        }
      } on FileSystemException {
        continue;
      }
    }

    return discovered.values.toList();
  }

  List<Directory> _dtdMetadataDirectories(FileSystem fs, Platform platform) {
    final directories = <Directory>[];
    final Map<String, String> env = platform.environment;
    if (env[_kDartDataHomeEnv] case final String dataHome when dataHome.isNotEmpty) {
      final Directory baseDir = fs.directory(dataHome);
      directories
        ..add(baseDir.childDirectory(_kDtdSubdir))
        ..add(baseDir);
    }
    if (platform.isWindows) {
      if (env[_kLocalAppDataEnv] case final String localAppData when localAppData.isNotEmpty) {
        directories.add(
          fs.directory(localAppData).childDirectory('Dart').childDirectory(_kDtdSubdir),
        );
      }
      if (env[_kAppDataEnv] case final String appData when appData.isNotEmpty) {
        directories.add(fs.directory(appData).childDirectory('Dart').childDirectory(_kDtdSubdir));
      }
    } else {
      if (env[_kXdgDataHomeEnv] case final String xdgDataHome when xdgDataHome.isNotEmpty) {
        directories
          ..add(fs.directory(xdgDataHome).childDirectory('dart').childDirectory(_kDtdSubdir))
          ..add(fs.directory(xdgDataHome).childDirectory(_kDtdSubdir));
      }
      if (env[_kHomeEnv] case final String home when home.isNotEmpty) {
        final Directory homeDir = fs.directory(home);
        if (platform.isMacOS) {
          directories.add(
            homeDir
                .childDirectory('Library')
                .childDirectory('Application Support')
                .childDirectory('Dart')
                .childDirectory(_kDtdSubdir),
          );
        }
        directories
          ..add(
            homeDir
                .childDirectory('.local')
                .childDirectory('share')
                .childDirectory('dart')
                .childDirectory(_kDtdSubdir),
          )
          ..add(homeDir.childDirectory('.dart').childDirectory(_kDtdSubdir));
      }
    }
    return directories;
  }

  static void _extractDtdUrisFromText(String text, Map<String, Uri> discovered) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    try {
      final Object? decoded = jsonDecode(trimmed);
      _extractDtdUrisFromJsonObject(decoded, discovered);
    } on FormatException {
      // Fall through to line-by-line and regex extraction.
    }
    for (final RegExpMatch match in _wsUriPattern.allMatches(trimmed)) {
      final String? rawUri = match.group(0);
      if (rawUri != null) {
        _tryAddDtdUri(rawUri, discovered);
      }
    }
  }

  static void _extractDtdUrisFromJsonObject(Object? node, Map<String, Uri> discovered) {
    switch (node) {
      case final Map<String, Object?> map:
        for (final MapEntry(:String key, :Object? value) in map.entries) {
          if ((key == _kUriKey || key == PreviewServiceInfo.kDtdUri || key == _kWsUriKey) &&
              value is String) {
            _tryAddDtdUri(value, discovered);
          } else {
            _extractDtdUrisFromJsonObject(value, discovered);
          }
        }
      case final List<Object?> list:
        for (final item in list) {
          _extractDtdUrisFromJsonObject(item, discovered);
        }
    }
  }

  static void _tryAddDtdUri(String rawUri, Map<String, Uri> discovered) {
    final Uri? uri = Uri.tryParse(rawUri);
    if (uri != null && (uri.isScheme('ws') || uri.isScheme('wss')) && uri.host.isNotEmpty) {
      discovered.putIfAbsent(uri.toString(), () => uri);
    }
  }

  Future<T> _withEphemeralHeadlessSession<T>({
    required Future<T> Function(WidgetPreviewActiveSession session) action,
    required bool buildHooks,
    required FlutterProject rootProject,
    required String targetProjectRoot,
    required List<String> webBrowserFlags,
  }) async {
    final ToolContext(
      :Cache cache,
      :FileSystem fs,
      :Platform platform,
      :ProcessManager processManager,
      :ShutdownHooks shutdownHooks,
    ) = _toolContext;

    final String flutterBinary = fs.path.join(
      cache.flutterRoot,
      'bin',
      platform.isWindows ? 'flutter.bat' : 'flutter',
    );
    final Process process;
    try {
      process = await processManager.start(<String>[
        flutterBinary,
        _kWidgetPreviewCommandName,
        _kStartSubcommand,
        '--$_kHeadlessFlag',
        '--${FlutterGlobalOptions.kMachineFlag}',
        if (!buildHooks) '--no-${WidgetPreviewOptions.kBuildHooks}',
        for (final String flag in webBrowserFlags) '--${FlutterOptions.kWebBrowserFlag}=$flag',
      ], workingDirectory: rootProject.directory.path);
    } on ProcessException catch (error) {
      throwToolExit('Failed to launch headless widget preview session: $error');
    }

    int? initializingPid;
    var processExited = false;
    var sessionAborted = false;
    Future<void>? terminationFuture;

    Future<void> terminateProcessImpl() async {
      if (processExited && initializingPid == null) {
        await process.exitCode;
        return;
      }
      var killedWithTaskkill = false;
      if (platform.isWindows && processManager.canRun(_kTaskkillBinary)) {
        final int targetPid = !processExited ? process.pid : initializingPid!;
        try {
          final ProcessResult result = await processManager.run(<String>[
            _kTaskkillBinary,
            '/F',
            '/T',
            '/PID',
            '$targetPid',
          ]);
          killedWithTaskkill = result.exitCode == 0;
        } on ProcessException {
          killedWithTaskkill = false;
        }
      }
      if (!killedWithTaskkill) {
        if (!processExited && !processManager.killPid(process.pid)) {
          process.kill();
        }
        if (initializingPid case final int vmPid when vmPid != process.pid) {
          processManager.killPid(vmPid);
        }
      } else if (initializingPid case final int vmPid when vmPid != process.pid) {
        processManager.killPid(vmPid);
      }
      if (!processExited) {
        await process.exitCode.timeout(
          _processExitTimeout,
          onTimeout: () async {
            if (!platform.isWindows) {
              ProcessSignal.sigkill.kill(process);
            } else {
              process.kill();
            }
            if (initializingPid case final int vmPid when vmPid != process.pid) {
              processManager.killPid(vmPid);
            }
            return process.exitCode.timeout(_processExitTimeout, onTimeout: () => -1);
          },
        );
      }
    }

    Future<void> terminateProcess() => terminationFuture ??= terminateProcessImpl();

    shutdownHooks.addShutdownHook(() async {
      sessionAborted = true;
      await terminateProcess();
    });

    final startedCompleter = Completer<PreviewServiceInfo>();
    startedCompleter.future.ignore();
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();
    final errorLines = <String>[];

    void completeStdoutDone([Object? _]) {
      if (!stdoutDone.isCompleted) {
        stdoutDone.complete();
      }
    }

    void completeStderrDone([Object? _]) {
      if (!stderrDone.isCompleted) {
        stderrDone.complete();
      }
    }

    void recordErrorLine(String line) {
      final String trimmed = line.trim();
      if (trimmed.isEmpty) {
        return;
      }
      if (errorLines.length >= _kMaxCapturedErrorLines) {
        errorLines.removeAt(0);
      }
      errorLines.add(trimmed);
    }

    final StreamSubscription<String> stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (String line) {
            final (
              :String? fatalError,
              :int? parsedInitializingPid,
              :PreviewServiceInfo? started,
            ) = _tryParseStartedEvent(
              line,
              onErrorMessage: recordErrorLine,
              targetProjectRoot: targetProjectRoot,
            );
            if (parsedInitializingPid != null) {
              initializingPid = parsedInitializingPid;
            }
            if (!startedCompleter.isCompleted) {
              if (fatalError != null) {
                startedCompleter.completeWithToolExit(fatalError);
              } else if (started != null) {
                startedCompleter.complete(started);
              }
            }
          },
          onDone: completeStdoutDone,
          onError: completeStdoutDone,
        );

    final StreamSubscription<String> stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(recordErrorLine, onDone: completeStderrDone, onError: completeStderrDone);

    unawaited(
      process.exitCode.then((int exitCode) async {
        processExited = true;
        await Future.wait<void>(<Future<void>>[stdoutDone.future, stderrDone.future]);
        if (!sessionAborted && !startedCompleter.isCompleted) {
          final details = errorLines.isEmpty ? '' : ' Details: ${errorLines.join(' | ')}';
          startedCompleter.completeWithToolExit(
            'Headless widget preview exited prematurely with code '
            '$exitCode.$details',
            exitCode: exitCode,
          );
        }
      }),
    );

    DartToolingDaemon? dtd;
    try {
      final PreviewServiceInfo startedInfo;
      try {
        startedInfo = await startedCompleter.future.timeout(_headlessStartupTimeout);
      } on TimeoutException {
        final details = errorLines.isEmpty ? '' : ' Details: ${errorLines.join(' | ')}';
        throwToolExit(
          'Timed out waiting for headless widget preview to start after '
          '${_headlessStartupTimeout.inMilliseconds}ms.$details',
        );
      }
      dtd = await _connectToDtd(Uri.parse(startedInfo.dtdUri));
      return await action(
        WidgetPreviewActiveSession(dtd: dtd, info: startedInfo, isEphemeral: true),
      );
    } finally {
      sessionAborted = true;
      await _closeDtdQuietly(dtd);
      await terminateProcess();
      await stdoutSub.cancel();
      await stderrSub.cancel();
      completeStdoutDone();
      completeStderrDone();
    }
  }

  static ({String? fatalError, int? parsedInitializingPid, PreviewServiceInfo? started})
  _tryParseStartedEvent(
    String line, {
    required void Function(String message) onErrorMessage,
    required String targetProjectRoot,
  }) {
    final String trimmed = line.trim();
    if (!trimmed.startsWith('[') && !trimmed.startsWith('{')) {
      return (fatalError: null, parsedInitializingPid: null, started: null);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException {
      return (fatalError: null, parsedInitializingPid: null, started: null);
    }
    final Iterable<Object?> events = switch (decoded) {
      final List<Object?> list => list,
      final Map<String, Object?> map => <Object?>[map],
      _ => const <Object?>[],
    };
    int? parsedInitializingPid;
    PreviewServiceInfo? started;
    String? fatalError;
    for (final entry in events) {
      if (entry is! Map<String, Object?>) {
        continue;
      }
      final Object? eventName = entry[_kEventKey];
      final Object? params = entry[_kParamsKey];
      if (params is! Map<String, Object?>) {
        continue;
      }
      if (eventName == _kInitializingEventName) {
        if (params[_kPidKey] case final int pid) {
          parsedInitializingPid = pid;
        }
        continue;
      }
      if (eventName == _kLogMessageEventName &&
          params[_kLevelKey] == _kErrorKey &&
          params[_kMessageKey] is String) {
        onErrorMessage(params[_kMessageKey]! as String);
        continue;
      }
      if (eventName == _kStartedEventName && started == null && fatalError == null) {
        final String? dtdUri = switch (params[PreviewServiceInfo.kDtdUri]) {
          final String value when value.isNotEmpty => value,
          _ => null,
        };
        final String? previewService = switch (params[PreviewServiceInfo.kPreviewService]) {
          final String value when value.isNotEmpty => value,
          _ => null,
        };
        final String? scaffoldService = switch (params[PreviewServiceInfo.kScaffoldService]) {
          final String value when value.isNotEmpty => value,
          _ => null,
        };
        if (dtdUri == null || previewService == null || scaffoldService == null) {
          fatalError =
              'Headless widget preview started without required DTD metadata '
              '(dtdUri, previewService, scaffoldService) in "$_kStartedEventName". '
              'This usually indicates an incompatible Flutter < 3.50 installation.';
          continue;
        }
        final String projectRoot = switch (params[PreviewServiceInfo.kProjectRoot]) {
          final String value when value.isNotEmpty => value,
          _ => targetProjectRoot,
        };
        final String? webPreviewUri = switch (params[WebPreviewUrlResult.kUrl]) {
          final String value when value.isNotEmpty => value,
          _ => null,
        };
        final String scaffoldStream = _deriveScaffoldStreamName(scaffoldService);
        started = PreviewServiceInfo(
          dtdUri: dtdUri,
          previewService: previewService,
          projectRoot: projectRoot,
          scaffoldConnected: false,
          scaffoldService: scaffoldService,
          scaffoldStream: scaffoldStream,
          webPreviewUri: webPreviewUri,
        );
      }
    }
    return (fatalError: fatalError, parsedInitializingPid: parsedInitializingPid, started: started);
  }

  static String _deriveScaffoldStreamName(String scaffoldService) {
    const prefix = '${WidgetPreviewDtdServices.kWidgetPreviewScaffoldServiceRoot}-';
    if (scaffoldService.startsWith(prefix)) {
      final String uuid = scaffoldService.substring(prefix.length);
      return '${WidgetPreviewDtdServices.kWidgetPreviewScaffoldStreamRoot}-$uuid';
    }
    return WidgetPreviewDtdServices.kWidgetPreviewScaffoldStreamRoot;
  }

  String _normalizeProjectRoot(Directory directory) {
    final FileSystem fs = _toolContext.fs;
    final String rawPath = directory.existsSync()
        ? directory.resolveSymbolicLinksSync()
        : directory.absolute.path;
    return fs.path.normalize(rawPath);
  }

  bool _projectRootsMatch(String candidateRoot, String targetRoot) {
    final FileSystem fs = _toolContext.fs;
    final Directory candidateDir = fs.directory(candidateRoot);
    final String normalizedCandidate = candidateDir.existsSync()
        ? fs.path.normalize(candidateDir.resolveSymbolicLinksSync())
        : fs.path.normalize(candidateRoot);
    return fs.path.equals(normalizedCandidate, targetRoot);
  }
}

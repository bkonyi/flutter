// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:args/args.dart';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:package_config/package_config.dart';
import 'package:process/process.dart';
import 'package:watcher/watcher.dart';

import '../artifacts.dart';
import '../base/common.dart';
import '../base/file_system.dart';
import '../base/logger.dart';
import '../base/platform.dart';
import '../base/process.dart';
import '../base/terminal.dart';
import '../build_info.dart';
import '../build_system/build_system.dart';
import '../build_system/build_targets.dart';
import '../cache.dart';
import '../dart/analysis.dart';
import '../devfs.dart';
import '../device.dart';
import '../features.dart';
import '../isolated/devfs_web.dart';
import '../isolated/resident_web_runner.dart';
import '../isolated/widget_preview_live_server.dart';
import '../migrations/widget_preview_gitignore_migration.dart';
import '../project.dart';
import '../resident_runner.dart';
import '../run_hot.dart';
import '../runner/flutter_command.dart';
import '../web/chrome.dart';
import '../web/web_device.dart';
import '../web/web_options.dart';
import '../widget_preview/analytics.dart';
import '../widget_preview/dependency_graph.dart';
import '../widget_preview/dtd_services.dart';
import '../widget_preview/dtd_types.dart';
import '../widget_preview/lsp_preview_detector.dart';
import '../widget_preview/preview_code_generator.dart';
import '../widget_preview/preview_detector.dart' hide WatcherBuilder;
import '../widget_preview/preview_git_exclude.dart';
import '../widget_preview/preview_machine_logger.dart';
import '../widget_preview/preview_manifest.dart';
import '../widget_preview/preview_pubspec_builder.dart';
import '../widget_preview/preview_session_client.dart';
import '../widget_preview/utils.dart';
import 'create_base.dart';

export '../widget_preview/preview_machine_logger.dart' show WidgetPreviewMachineAwareLogger;
export '../widget_preview/preview_session_client.dart'
    show WidgetPreviewListCommand, WidgetPreviewSnapshotCommand;

typedef FlutterDeviceFactory = Future<FlutterDevice> Function(
  Device device, {
  required BuildInfo buildInfo,
  required String target,
});

typedef ResidentRunnerFactory = ResidentRunner Function(
  FlutterDevice device, {
  required DebuggingOptions debuggingOptions,
  required FlutterProject flutterProject,
  required String projectRootPath,
  required String target,
});

class WidgetPreviewCommand extends FlutterCommand {
  WidgetPreviewCommand({
    required BuildSystem buildSystem,
    required BuildTargets buildTargets,
    required super.toolContext,
    @visibleForTesting Future<AnalysisServer> Function()? analysisServerFactoryOverride,
    @visibleForTesting WidgetPreviewDtdServices? dtdServicesOverride,
    @visibleForTesting FlutterDeviceFactory? flutterDeviceFactoryOverride,
    @visibleForTesting ResidentRunnerFactory? residentRunnerFactoryOverride,
    @visibleForTesting WatcherBuilder? watcherBuilderOverride,
    bool verboseHelp = false,
  }) {
    addSubcommand(
      WidgetPreviewStartCommand(
        buildSystem: buildSystem,
        buildTargets: buildTargets,
        toolContext: toolContext,
        analysisServerFactoryOverride: analysisServerFactoryOverride,
        dtdServicesOverride: dtdServicesOverride,
        flutterDeviceFactoryOverride: flutterDeviceFactoryOverride,
        residentRunnerFactoryOverride: residentRunnerFactoryOverride,
        watcherBuilderOverride: watcherBuilderOverride,
        verbose: verboseHelp,
      ),
    );
    addSubcommand(WidgetPreviewCleanCommand(toolContext: toolContext));
    addSubcommand(WidgetPreviewListCommand(toolContext: toolContext, verbose: verboseHelp));
    addSubcommand(WidgetPreviewSnapshotCommand(toolContext: toolContext, verbose: verboseHelp));
  }

  @override
  String get description => 'Manage the widget preview environment.';

  @override
  String get name => kWidgetPreview;
  static const kWidgetPreview = 'widget-preview';

  @override
  String get category => FlutterCommandCategory.tools;

  @override
  Future<FlutterCommandResult> runCommand() async => FlutterCommandResult.fail();
}

abstract base class WidgetPreviewSubCommandBase extends FlutterCommand {
  WidgetPreviewSubCommandBase({required super.toolContext});

  FileSystem get fs => toolContext.fs;
  Logger get logger => toolContext.logger;
  FlutterProjectFactory get projectFactory => toolContext.projectFactory;

  FlutterProject getRootProject() {
    final ArgResults? results = argResults;
    final List<String> rest = results?.rest ?? const <String>[];
    final Directory projectDir;
    if (rest case <String>[final String directory]) {
      projectDir = fs.directory(directory);
      if (!projectDir.existsSync()) {
        throwToolExit('Could not find ${projectDir.path}.');
      }
    } else if (rest.length > 1) {
      throwToolExit('Only one directory should be provided.');
    } else {
      projectDir = fs.currentDirectory;
    }
    final FlutterProject project = validateFlutterProjectForPreview(projectDir);
    final FlutterProject? workspaceRoot = project.workspaceRoot;
    if (workspaceRoot != null) {
      logger.printTrace('Found workspace root at ${workspaceRoot.directory.path}');
      return workspaceRoot;
    }
    return project;
  }

  FlutterProject validateFlutterProjectForPreview(Directory directory) {
    logger.printTrace('Verifying that ${directory.path} is a Flutter project.');
    final FlutterProject flutterProject = projectFactory.fromDirectory(directory);
    if (!flutterProject.pubspecFile.existsSync()) {
      throwToolExit('${flutterProject.directory.path} is not a valid Flutter project.');
    }
    return flutterProject;
  }
}

/// The type of reload operation queued to run once [WidgetPreviewStartCommand._reloadMutex]
/// is available.
enum _PendingReload {
  /// Perform a hot reload via [WidgetPreviewStartCommand.handleReload], which
  /// falls back to a hot restart if the reload is rejected.
  hotReload,

  /// Perform a full hot restart (`restart(fullRestart: true)`).
  hotRestart,
}

final class WidgetPreviewStartCommand extends WidgetPreviewSubCommandBase with CreateBase {
  WidgetPreviewStartCommand({
    required this._buildSystem,
    required this._buildTargets,
    required super.toolContext,
    @visibleForTesting Future<AnalysisServer> Function()? analysisServerFactoryOverride,
    @visibleForTesting WidgetPreviewDtdServices? dtdServicesOverride,
    @visibleForTesting this._flutterDeviceFactoryOverride,
    @visibleForTesting this._previewPubspecBuilderOverride,
    @visibleForTesting this._residentRunnerFactoryOverride,
    @visibleForTesting WatcherBuilder? watcherBuilderOverride,
    this.verbose = false,
  }) {
    if (dtdServicesOverride != null) {
      _dtdService = dtdServicesOverride;
    }
    _analysisServerFactoryOverride = analysisServerFactoryOverride;
    _watcherBuilderOverride = watcherBuilderOverride;
    addPubOptions();
    argParser.addDescriptors(const <OptionDescriptor<Object?>>[
      CommonOptions.machine,
      DebuggingOptionDescriptors.enableDevTools,
      DebuggingOptionDescriptors.devToolsServerAddress,
      WidgetPreviewOptions.buildHooksOption,
      WebOptions.webBrowserFlags,
    ], verboseHelp: verbose);
    argParser
      ..addFlag(
        kWebServer,
        help:
            'Serve the widget preview environment using the web-server device instead of the '
            'browser.',
      )
      ..addOption(
        kDtdUrl,
        help: 'The address of an existing Dart Tooling Daemon instance to be used by the Flutter CLI.',
        hide: !verbose,
      )
      ..addFlag(
        kLaunchPreviewer,
        defaultsTo: true,
        help: 'Launches the widget preview environment.',
        // Should only be used for testing.
        hide: !verbose,
      )
      ..addFlag(kHeadless, help: 'Launches Chrome in headless mode for testing.', hide: !verbose)
      ..addOption(
        kWidgetPreviewScaffoldOutputDir,
        help:
            'Generated the widget preview environment scaffolding at a given location '
            'for testing purposes.',
        hide: !verbose,
      )
      ..addFlag(
        kDisableDtdServiceUuid,
        help: 'Disables the addition of a UUID to the widget preview DTD service and stream.',
        hide: !verbose,
      )
      ..addFlag(
        kLegacyPreviewDetection,
        help:
            'Enables the legacy preview detection mechanism that uses '
            'package:analyzer instead of LSP.',
        hide: !verbose,
      )
      ..addMultiOption(
        kWebAllowOrigin,
        help:
            'Additional Origin values allowed for fetch and WebSocket requests to the widget '
            'preview live server (classic <script> loads omit Origin and require Host to be '
            'loopback or the configured hostname).',
        hide: !verbose,
      );
  }

  static const kStart = 'start';
  static const kDtdUrl = 'dtd-url';
  static const kWidgetPreviewScaffoldName = 'widget_preview_scaffold';
  static const kLaunchPreviewer = 'launch-previewer';
  static const kHeadless = 'headless';
  static const kWebServer = 'web-server';
  static const kWebAllowOrigin = 'web-allow-origin';
  static const kWidgetPreviewScaffoldOutputDir = 'scaffold-output-dir';
  static const kDisableDtdServiceUuid = 'disable-dtd-service-uuid';
  static const kLegacyPreviewDetection = 'legacy-preview-detection';

  @visibleForTesting
  static const kBrowserNotFoundErrorMessage =
      'Failed to locate browser. Make sure you are using an up-to-date Chrome or Edge. '
      'Otherwise, consider running with --$kWebServer instead.';

  @visibleForTesting
  static const kHeadlessBrowserNotFoundErrorMessage =
      'Failed to locate a headless browser (Google Chrome or Chromium). '
      'Install Google Chrome or Chromium, or set the $kChromeEnvironment environment variable '
      'to the browser binary path.';

  @visibleForTesting
  static const kHotReloadRejectedMessage = 'Performing hot restart instead...';

  @override
  Future<Set<DevelopmentArtifact>> get requiredArtifacts async => const <DevelopmentArtifact>{
    // Ensure the Flutter Web SDK is installed.
    DevelopmentArtifact.web,
  };

  @override
  String get description => 'Starts the widget preview environment.';

  @override
  String get name => kStart;

  final bool verbose;

  final BuildSystem _buildSystem;
  final BuildTargets _buildTargets;

  @override
  WidgetPreviewMachineAwareLogger get logger =>
      toolContext.logger as WidgetPreviewMachineAwareLogger;

  Cache get cache => toolContext.cache;

  Platform get platform => toolContext.platform;

  ShutdownHooks get shutdownHooks => toolContext.shutdownHooks;

  ProcessManager get processManager => toolContext.processManager;

  Artifacts get artifacts => toolContext.artifacts;

  Terminal get terminal => toolContext.terminal;

  late final previewAnalytics = WidgetPreviewAnalytics(analytics: analytics);

  late final FlutterProject rootProject = getRootProject();

  late final PreviewPubspecBuilder _previewPubspecBuilder =
      _previewPubspecBuilderOverride ??
      PreviewPubspecBuilder(
        logger: logger,
        verbose: verbose,
        offline: offline,
        rootProject: rootProject,
        previewManifest: _previewManifest,
      );

  late final _previewDetector = PreviewDetector(
    artifacts: artifacts,
    platform: platform,
    previewAnalytics: previewAnalytics,
    project: rootProject,
    logger: logger,
    fs: fs,
    onChangeDetected: onLegacyChangeDetected,
    onPubspecChangeDetected: onPubspecChangeDetected,
    onNonDartFileChangeDetected: _onNonDartFileChangeDetected,
  );

  late final _lspPreviewDetector = LspPreviewDetector(
    dtd: _dtdService,
    onChangeDetected: onChangeDetected,
    onPubspecChangeDetected: onPubspecChangeDetected,
    previewAnalytics: previewAnalytics,
    project: rootProject,
    suppressAnalytics: !analytics.okToSend,
    toolContext: toolContext,
    analysisServerFactory: _analysisServerFactoryOverride,
    onNonDartFileChangeDetected: _onNonDartFileChangeDetected,
    watcherBuilder: _watcherBuilderOverride ?? Watcher.new,
  );

  late final Future<AnalysisServer> Function()? _analysisServerFactoryOverride;
  final FlutterDeviceFactory? _flutterDeviceFactoryOverride;
  final PreviewPubspecBuilder? _previewPubspecBuilderOverride;
  late final WatcherBuilder? _watcherBuilderOverride;
  final ResidentRunnerFactory? _residentRunnerFactoryOverride;

  late PreviewCodeGenerator _previewCodeGenerator;

  @visibleForTesting
  PreviewCodeGenerator get previewCodeGenerator => _previewCodeGenerator;

  @visibleForTesting
  set previewCodeGenerator(PreviewCodeGenerator value) => _previewCodeGenerator = value;

  late final _previewManifest = PreviewManifest(
    logger: logger,
    rootProject: rootProject,
    fs: fs,
    cache: cache,
  );

  String get _resolvedProjectRootPath => rootProject.directory.existsSync()
      ? rootProject.directory.resolveSymbolicLinksSync()
      : rootProject.directory.absolute.path;

  late var _dtdService = WidgetPreviewDtdServices(
    addUuidToServiceName: !(argResults != null && boolArg(kDisableDtdServiceUuid)),
    dtdLauncher: DtdLauncher(logger: logger, artifacts: artifacts, processManager: processManager),
    fs: fs,
    logger: logger,
    lspPreviewsProvider: () => _lastGeneratedPreviews,
    onHotReloadPreviewer: onHotReloadRequest,
    onHotRestartPreviewerRequest: onHotRestartRequest,
    onSyncPreviews: syncPreviews,
    previewAnalytics: previewAnalytics,
    project: rootProject.widgetPreviewScaffoldProject,
    projectRootPath: _resolvedProjectRootPath,
    shutdownHooks: shutdownHooks,
    webPreviewUriProvider: () => webPreviewUri,
  );

  @visibleForTesting
  WidgetPreviewDtdServices get dtdService => _dtdService;

  /// The HTTP URI where the web preview scaffold is currently served.
  @visibleForTesting
  Uri? webPreviewUri;

  FlutterWidgetPreviews? _lastGeneratedPreviews;

  /// The currently running instance of the widget preview scaffold.
  ResidentRunner? _widgetPreviewApp;

  @visibleForTesting
  ResidentRunner? get widgetPreviewApp => _widgetPreviewApp;

  @visibleForTesting
  set widgetPreviewApp(ResidentRunner? value) => _widgetPreviewApp = value;

  /// Serializes initial preview scaffold startup and subsequent hot reload / hot
  /// restart operations so reloads cannot execute before the debug connection is
  /// established or overlap with an in-flight reload.
  final _reloadMutex = PreviewDetectorMutex();

  /// Tracks a coalesced reload or restart request waiting to acquire
  /// [_reloadMutex].
  ///
  /// When non-null, a task is already queued on [_reloadMutex] to execute the
  /// pending reload once the current startup or in-flight reload completes.
  /// Additional requests that arrive before that queued task acquires the lock
  /// update this field in place (upgrading [_PendingReload.hotReload] to
  /// [_PendingReload.hotRestart] if a full restart is requested) without
  /// queueing duplicate tasks on [_reloadMutex].
  _PendingReload? _pendingReload;

  @override
  Future<FlutterCommandResult> runCommand() async {
    assert(toolContext.logger is WidgetPreviewMachineAwareLogger);

    // Start the timer tracking how long it takes to launch the preview environment.
    previewAnalytics.initializeLaunchStopwatch();
    logger.sendInitializingEvent();

    if (boolArg(kHeadless)) {
      ensureWidgetPreviewGitExclude(projectDirectory: rootProject.directory, logger: logger);
    } else {
      await WidgetPreviewGitignoreMigration(rootProject, logger).migrate();
    }

    final String? customPreviewScaffoldOutput = stringArg(kWidgetPreviewScaffoldOutputDir);
    final Directory widgetPreviewScaffold = customPreviewScaffoldOutput != null
        ? fs.directory(customPreviewScaffoldOutput)
        : rootProject.widgetPreviewScaffold;

    // Check to see if a preview scaffold has already been generated. If not,
    // generate one.
    final bool generateScaffoldProject =
        customPreviewScaffoldOutput != null || _previewManifest.shouldGenerateProject();
    widgetPreviewScaffold.createSync(recursive: true);

    if (generateScaffoldProject) {
      // WARNING: this log message is used by test/integration.shard/widget_preview_test.dart
      logger.printStatus(
        'Creating widget preview scaffolding at: ${widgetPreviewScaffold.absolute.path}',
      );
      await generateApp(
        <String>['app', kWidgetPreviewScaffoldName],
        widgetPreviewScaffold,
        createTemplateContext(
          organization: 'flutter',
          projectName: kWidgetPreviewScaffoldName,
          titleCaseProjectName: 'Widget Preview Scaffold',
          flutterRoot: cache.flutterRoot,
          dartSdkVersionBounds: '^${cache.dartSdkBuild}',
          web: true,
        ),
        overwrite: true,
        generateMetadata: false,
        printStatusWhenWriting: verbose,
      );
      if (customPreviewScaffoldOutput != null) {
        _copyHostWebDirToScaffold(widgetPreviewScaffold);
        return FlutterCommandResult.success();
      }
      _previewManifest.generate();

      // Make the analytics instance aware that we generated the widget preview scaffold as part of
      // launching the previewer.
      previewAnalytics.generatedProject();
    }

    // WARNING: this access of widgetPreviewScaffoldProject needs to happen
    // after we generate the scaffold project as invoking the getter triggers
    // lazy initialization of the preview scaffold's FlutterManifest before
    // the scaffold project's pubspec has been generated.
    final FlutterProject widgetPreviewScaffoldProject = rootProject.widgetPreviewScaffoldProject;
    _previewCodeGenerator = PreviewCodeGenerator(
      widgetPreviewScaffoldProject: widgetPreviewScaffoldProject,
      fs: fs,
    );

    if (generateScaffoldProject || _previewManifest.shouldRegeneratePubspec()) {
      if (!generateScaffoldProject) {
        logger.printStatus(
          'Detected changes in pubspec.yaml. Regenerating pubspec.yaml for the '
          'widget preview scaffold.',
        );
      }
      await _previewPubspecBuilder.populatePreviewPubspec(rootProject: rootProject);
    }

    _copyHostWebDirToScaffold(widgetPreviewScaffold);

    if (!widgetPreviewScaffoldProject.dartTool.existsSync()) {
      await _previewPubspecBuilder.generatePackageConfig(
        widgetPreviewScaffoldProject: widgetPreviewScaffoldProject,
      );
    }

    final bool legacyDetection = boolArg('legacy-preview-detection');

    shutdownHooks.addShutdownHook(() async {
      // Clear the runner reference before exiting so any queued or late reload
      // callbacks become no-ops during shutdown.
      final ResidentRunner? app = _widgetPreviewApp;
      _widgetPreviewApp = null;
      webPreviewUri = null;
      await app?.exitApp();
      if (legacyDetection) {
        await _previewDetector.dispose();
      } else {
        await _lspPreviewDetector.dispose();
      }
    });

    if (legacyDetection) {
      final PreviewDependencyGraph graph = await _previewDetector.initialize();
      _previewCodeGenerator.populatePreviewsInGeneratedPreviewScaffold(graph);
    } else {
      await configureDtd();

      await _lspPreviewDetector.initialize();

      final FlutterWidgetPreviews originalPreviews;
      try {
        // Wait for the initial analysis to complete to ensure the analysis server
        // has registered the widget preview RPC methods.
        await _lspPreviewDetector.waitForAnalysis();

        _previewCodeGenerator.populateDtdConnectionInfo(
          dtdUri: _dtdService.dtdUri!,
          projectRootPath: _resolvedProjectRootPath,
          widgetPreviewScaffoldServiceName: _dtdService.widgetPreviewScaffoldService,
          widgetPreviewScaffoldStreamName: _dtdService.widgetPreviewScaffoldStream,
          widgetPreviewServiceName: _dtdService.widgetPreviewService,
        );

        originalPreviews = await _dtdService.getFlutterWidgetPreviews();
      } on Exception catch (e) {
        throwToolExit(
          'Failed to retrieve widget previews from the Dart Tooling Daemon (DTD). '
          'Ensure that the analysis server is running and reachable. Details: $e',
        );
      } on StateError catch (e) {
        throwToolExit(
          'Failed to retrieve widget previews from the Dart Tooling Daemon (DTD). '
          'Ensure that the analysis server is running and reachable. Details: $e',
        );
      }
      _lastGeneratedPreviews = originalPreviews;
      _previewCodeGenerator.populatePreviewsInGeneratedPreviewScaffoldLsp(originalPreviews);
    }

    final int result = await runPreviewEnvironment(
      widgetPreviewScaffoldProject: widgetPreviewScaffoldProject,
    );
    if (result != 0) {
      throwToolExit('Failed to launch the widget previewer.', exitCode: result);
    }

    return FlutterCommandResult.success();
  }

  void _copyHostWebDirToScaffold(Directory scaffoldDirectory) {
    final Directory hostWebDir = rootProject.directory.childDirectory('web');
    if (hostWebDir.existsSync()) {
      final Directory scaffoldWebDir = scaffoldDirectory.childDirectory('web');
      if (scaffoldWebDir.existsSync()) {
        logger.printTrace('Deleting scaffold web directory: ${scaffoldWebDir.path}');
        scaffoldWebDir.deleteSync(recursive: true);
      }
      logger.printTrace(
        'Copying host web directory to scaffold web directory: ${hostWebDir.path} -> ${scaffoldWebDir.path}',
      );
      copyDirectory(hostWebDir, scaffoldWebDir);
    }
  }

  static const _kDefaultCompileErrorMessage = 'Failed to reload widget preview.';
  static const _kSafeMtimeMargin = Duration(milliseconds: 1100);

  WebDevFS? get _webDevFS {
    final ResidentRunner? app = _widgetPreviewApp;
    if (app == null) {
      return null;
    }
    for (final FlutterDevice? device in app.flutterDevices) {
      if (device?.devFS case final WebDevFS webDevFS) {
        return webDevFS;
      }
    }
    return null;
  }

  bool _assetBundleNeedsBuild(ResidentRunner app) {
    if (app is! ResidentWebRunner) {
      return false;
    }
    return app.assetBundle.needsBuild(manifestPath: app.flutterProject.pubspecFile.path);
  }

  Future<bool> _hasNoInvalidatedInputs() async {
    final ResidentRunner? app = _widgetPreviewApp;
    if (app is! ResidentWebRunner || !_dtdService.scaffoldConnected) {
      return false;
    }
    final WebDevFS? webDevFS = _webDevFS;
    final DateTime? lastCompiled = webDevFS?.lastCompiled;
    if (webDevFS == null ||
        lastCompiled == null ||
        DateTime.now().difference(lastCompiled) < _kSafeMtimeMargin) {
      return false;
    }
    if (_assetBundleNeedsBuild(app)) {
      return false;
    }
    final PackageConfig packageConfig =
        webDevFS.lastPackageConfig ?? app.debuggingOptions.buildInfo.packageConfig;
    final invalidator = ProjectFileInvalidator(fileSystem: fs, platform: platform, logger: logger);
    final InvalidationResult invalidation = await invalidator.findInvalidated(
      lastCompiled: lastCompiled,
      urisToMonitor: webDevFS.sources,
      packagesPath: app.packagesFilePath,
      packageConfig: packageConfig,
    );
    return invalidation.uris?.isEmpty ?? false;
  }

  Future<OperationResult?> _performFullRestart() async {
    final ResidentRunner? app = _widgetPreviewApp;
    if (app == null || shutdownHooks.isShuttingDown) {
      return null;
    }
    final bool wasConnected = _dtdService.scaffoldConnected;
    _dtdService.markScaffoldDisconnected();
    OperationResult? result;
    try {
      result = await app.restart(fullRestart: true);
      if (result.isOk) {
        _webDevFS?.webAssetServer.liveServer?.prewarmBundle();
      }
      return result;
    } finally {
      if (wasConnected &&
          (result == null || !result.isOk) &&
          _widgetPreviewApp != null &&
          !shutdownHooks.isShuttingDown) {
        _dtdService.markScaffoldConnected();
      }
    }
  }

  Future<({OperationResult? result, bool fullRestart, bool didChange})> _performReload() async {
    final ResidentRunner? app = _widgetPreviewApp;
    if (app == null) {
      return (result: null, fullRestart: false, didChange: false);
    }
    final WebDevFS? webDevFS = _webDevFS;
    final int? revisionBefore = webDevFS?.webAssetServer.webMemoryFS.revision;
    final bool assetChanged = _assetBundleNeedsBuild(app);
    final OperationResult result = await app.restart();
    if (result case OperationResult(
      isOk: false,
      updateFSReport: UpdateFSReport(hotReloadRejected: true),
    )) {
      logger.printStatus(kHotReloadRejectedMessage);
      final OperationResult? restartResult = await _performFullRestart();
      return (
        result: restartResult,
        fullRestart: restartResult != null,
        didChange: restartResult != null && restartResult.isOk,
      );
    }
    if (result.isOk) {
      webDevFS?.webAssetServer.liveServer?.prewarmBundle();
    }
    final int? revisionAfter = webDevFS?.webAssetServer.webMemoryFS.revision;
    final bool didChange =
        result.isOk && (revisionBefore == null || revisionAfter != revisionBefore || assetChanged);
    return (result: result, fullRestart: false, didChange: didChange);
  }

  /// Hot reloads the previewer, falling back to a hot restart if the reload is
  /// rejected due to unsupported changes.
  @visibleForTesting
  Future<OperationResult?> handleReload() async {
    final (:OperationResult? result, :bool fullRestart, :bool didChange) = await _performReload();
    if (result != null && result.isOk && didChange && !shutdownHooks.isShuttingDown) {
      await _dtdService.postPreviewReloaded(fullRestart: fullRestart);
    }
    return result;
  }

  Completer<void>? _pendingReloadCompleter;

  Future<void> _triggerReload(_PendingReload requested) async {
    // Record the requested reload type. If a task is already queued waiting for
    // [_reloadMutex], merge this request into the pending one (upgrading a
    // queued hot reload to a full hot restart if needed, and never downgrading
    // a queued hot restart) and await its completion rather than queueing
    // duplicate reload tasks on the mutex.
    final _PendingReload? queued = _pendingReload;
    _pendingReload = queued == .hotRestart ? .hotRestart : requested;
    if (queued != null) {
      await _pendingReloadCompleter?.future;
      return;
    }
    final reloadCompleter = Completer<void>();
    _pendingReloadCompleter = reloadCompleter;
    try {
      await _reloadMutex.runGuarded(() async {
        final _PendingReload? pending = _pendingReload;
        _pendingReload = null;
        if (pending == null || shutdownHooks.isShuttingDown) {
          return;
        }
        try {
          switch (pending) {
            case .hotReload:
              await handleReload();
            case .hotRestart:
              final OperationResult? result = await _performFullRestart();
              if (result != null && result.isOk && !shutdownHooks.isShuttingDown) {
                await _dtdService.postPreviewReloaded(fullRestart: true);
              }
          }
        } on Object catch (e, st) {
          logger.printTrace('Error during widget preview reload: $e\n$st');
        }
      });
    } finally {
      if (identical(_pendingReloadCompleter, reloadCompleter)) {
        _pendingReloadCompleter = null;
      }
      reloadCompleter.complete();
    }
  }

  /// Synchronizes workspace preview declarations from LSP, triggers an
  /// incremental reload (or fallback hot restart), and waits for the scaffold
  /// to connect if a full restart occurred or the scaffold is not yet live.
  @visibleForTesting
  Future<SyncPreviewsResponse> syncPreviews({
    Duration timeout = const Duration(milliseconds: WidgetPreviewDtdServices.kDefaultSyncTimeoutMs),
  }) async {
    if (shutdownHooks.isShuttingDown || _widgetPreviewApp == null) {
      return const SyncPreviewsResponse(
        compileSuccess: true,
        errorPreviewCount: 0,
        fullRestart: false,
        reloaded: false,
      );
    }

    var errorPreviewCount = 0;
    var didUpdateGeneratedPreviews = false;
    final bool legacyDetection = argResults != null && boolArg(kLegacyPreviewDetection);
    if (!legacyDetection) {
      final FlutterWidgetPreviews? latestPreviews = await _lspPreviewDetector.syncPreviews();
      if (latestPreviews == null || shutdownHooks.isShuttingDown || _widgetPreviewApp == null) {
        return const SyncPreviewsResponse(
          compileSuccess: true,
          errorPreviewCount: 0,
          fullRestart: false,
          reloaded: false,
        );
      }
      errorPreviewCount = latestPreviews.previews
          .where(
            (FlutterWidgetPreviewDetails p) =>
                p.packageName != null && (p.hasError || p.dependencyHasErrors),
          )
          .length;
      if (latestPreviews != _lastGeneratedPreviews) {
        didUpdateGeneratedPreviews = true;
        _lastGeneratedPreviews = latestPreviews;
        _previewCodeGenerator.populatePreviewsInGeneratedPreviewScaffoldLsp(latestPreviews);
      }
    }

    final (
      :OperationResult? reloadResult,
      :bool fullRestart,
      :bool didChange,
    ) = await _reloadMutex.runGuarded(() async {
      final _PendingReload? pending = _pendingReload;
      _pendingReload = null;
      if (shutdownHooks.isShuttingDown || _widgetPreviewApp == null) {
        return (reloadResult: null, fullRestart: false, didChange: false);
      }
      if (pending == .hotRestart) {
        final OperationResult? restartResult = await _performFullRestart();
        return (
          reloadResult: restartResult,
          fullRestart: restartResult != null,
          didChange: restartResult != null && restartResult.isOk,
        );
      }
      if (pending == null && !didUpdateGeneratedPreviews && await _hasNoInvalidatedInputs()) {
        return (reloadResult: OperationResult.ok, fullRestart: false, didChange: false);
      }
      final (:OperationResult? result, :bool fullRestart, :bool didChange) = await _performReload();
      return (
        reloadResult: result,
        fullRestart: fullRestart,
        didChange: didChange || (result != null && result.isOk && didUpdateGeneratedPreviews),
      );
    });

    if (reloadResult == null) {
      return SyncPreviewsResponse(
        compileSuccess: true,
        errorPreviewCount: errorPreviewCount,
        fullRestart: fullRestart,
        reloaded: false,
      );
    }

    final bool compileSuccess = reloadResult.isOk;
    final String? compileError = compileSuccess
        ? null
        : (reloadResult.message.isNotEmpty ? reloadResult.message : _kDefaultCompileErrorMessage);

    if (compileSuccess && (fullRestart || !_dtdService.scaffoldConnected)) {
      if (shutdownHooks.isShuttingDown || _widgetPreviewApp == null) {
        return SyncPreviewsResponse(
          compileSuccess: true,
          errorPreviewCount: errorPreviewCount,
          fullRestart: fullRestart,
          reloaded: false,
        );
      }
      await _dtdService.waitForScaffoldConnected(timeout: timeout);
    }

    if (compileSuccess && didChange) {
      if (shutdownHooks.isShuttingDown || _widgetPreviewApp == null) {
        return SyncPreviewsResponse(
          compileSuccess: true,
          errorPreviewCount: errorPreviewCount,
          fullRestart: fullRestart,
          reloaded: false,
        );
      }
      await _dtdService.postPreviewReloaded(fullRestart: fullRestart);
    }

    return SyncPreviewsResponse(
      compileError: compileError,
      compileSuccess: compileSuccess,
      errorPreviewCount: errorPreviewCount,
      fullRestart: fullRestart,
      reloaded: compileSuccess && didChange,
    );
  }

  void onLegacyChangeDetected(PreviewDependencyGraph previews) {
    _previewCodeGenerator.populatePreviewsInGeneratedPreviewScaffold(previews);
    logger.printStatus('Triggering reload based on change to preview set: $previews');
    unawaited(_triggerReload(.hotReload));
  }

  @visibleForTesting
  Future<void> onHotReloadRequest() async {
    logger.printStatus('Triggering reload based on request from preview environment.');
    await _triggerReload(.hotReload);
  }

  void onHotRestartRequest() {
    logger.printStatus('Triggering restart based on request from preview environment.');
    unawaited(_triggerReload(.hotRestart));
  }

  @visibleForTesting
  Future<void> onPubspecChangeDetected(String path) async {
    logger.printStatus('Triggering restart based on update to pubspec.yaml: $path');
    await _previewPubspecBuilder.populatePreviewPubspec(
      rootProject: rootProject,
      updatedPubspecPath: path,
    );
    await _triggerReload(.hotRestart);
  }

  void onChangeDetected(FlutterWidgetPreviews update) {
    _lastGeneratedPreviews = update;
    _previewCodeGenerator.populatePreviewsInGeneratedPreviewScaffoldLsp(update);
    logger.printStatus('Triggering reload based on update to script: ${update.scriptUris}');
    unawaited(_triggerReload(.hotReload));
  }

  void _onNonDartFileChangeDetected(String path) {
    if (_widgetPreviewApp?.assetBundle.needsBuild() ?? false) {
      logger.printStatus('Triggering reload based on update to asset: $path');
      unawaited(_triggerReload(.hotReload));
    }
  }

  /// Configures the Dart Tooling Daemon connection.
  ///
  /// If --dtd-uri is provided, the existing DTD instance will be used. If the tool fails to
  /// connect to this URI, it will start its own DTD instance.
  ///
  /// If --dtd-uri is not provided, a DTD instance managed by the tool will be started.
  Future<void> configureDtd() async {
    final String? existingDtdUriStr = stringArg(kDtdUrl);
    Uri? existingDtdUri;
    try {
      if (existingDtdUriStr != null) {
        existingDtdUri = Uri.parse(existingDtdUriStr);
      }
    } on FormatException {
      logger.printWarning('Failed to parse value of --dtd-uri: $existingDtdUriStr.');
    }
    if (existingDtdUri != null) {
      logger.printTrace('Connecting to existing DTD instance at: $existingDtdUri...');
      try {
        await _dtdService.connect(dtdWsUri: existingDtdUri);
      } on Exception catch (error) {
        logger.printWarning(
          'Failed to connect to existing DTD instance at $existingDtdUri: $error. '
          'Starting a new DTD instance instead.',
        );
      }
    }
  }

  Future<int> runPreviewEnvironment({required FlutterProject widgetPreviewScaffoldProject}) async {
    try {
      // Hold [_reloadMutex] during startup so any reload or restart requests
      // triggered while the preview scaffold is launching and establishing its
      // debug connection are gated until the previewer is ready.
      await _reloadMutex.runGuarded(() async {
        // In the rare case that Flutter Web is disabled, the device manager will not return any web
        // devices which will cause us to crash.
        if (!(runner?.featureFlags ?? featureFlags).isWebEnabled) {
          throwToolExit(
            'Widget Previews requires Flutter Web to be enabled. Please run '
            "'flutter config --enable-web' to enable Flutter Web and try again.",
          );
        }
        final DeviceManager resolvedDeviceManager = (runner?.deviceManager ?? deviceManager)!;
        final Device device;
        if (boolArg(kWebServer)) {
          final List<Device> devices;
          try {
            // The web-server device is hidden by default, make it visible before trying to look it up.
            WebServerDevice.showWebServerDevice = true;
            devices = await resolvedDeviceManager.getDevicesById(
              WebServerDevice.kWebServerDeviceId,
            );
          } finally {
            // Reset the flag to false to avoid affecting other commands.
            WebServerDevice.showWebServerDevice = false;
          }
          assert(devices.length == 1);
          device = devices.single;
        } else {
          // Since the only target supported by the widget preview scaffold is the web
          // device, only a single web device should be returned.
          final List<Device> devices = await resolvedDeviceManager.getDevices(
            filter: DeviceDiscoveryFilter(
              supportFilter:
                  DeviceDiscoverySupportFilter.excludeDevicesUnsupportedByFlutterOrProject(
                    flutterProject: widgetPreviewScaffoldProject,
                  ),
              deviceConnectionInterface: DeviceConnectionInterface.attached,
            ),
          );

          if (devices.isEmpty) {
            throwToolExit(
              boolArg(kHeadless)
                  ? kHeadlessBrowserNotFoundErrorMessage
                  : kBrowserNotFoundErrorMessage,
            );
          }
          if (devices.length > 1) {
            // Prefer Google Chrome as the target browser.
            device =
                devices.firstWhereOrNull((device) => device is GoogleChromeDevice) ?? devices.first;

            logger.printTrace(
              'Detected ${devices.length} web devices (${devices.map((e) => e.displayName).join(', ')}). '
              'Defaulting to ${device.displayName}.',
            );
          } else {
            device = devices.single;
          }
        }

        // WARNING: this log message is used by test/integration.shard/widget_preview_test.dart
        logger.printStatus('Launching the Widget Preview Scaffold on ${device.displayName}...');

        final debuggingOptions = DebuggingOptions.enabled(
          BuildInfo(
            BuildMode.debug,
            null,
            treeShakeIcons: false,
            packageConfigPath: widgetPreviewScaffoldProject.packageConfig.path,
            packageConfig: PackageConfig.parseBytes(
              widgetPreviewScaffoldProject.packageConfig.readAsBytesSync(),
              widgetPreviewScaffoldProject.packageConfig.uri,
            ),
            trackWidgetCreation: true,
            buildNativeAssets: boolArg(WidgetPreviewOptions.kBuildHooks),
            // Don't try and download canvaskit from the CDN.
            useLocalCanvasKit: true,
            includeUnsupportedPlatformLibraryStubs: true,
          ),
          webConfig: WebDebugConfig(
            browserFlags: stringsArg(FlutterOptions.kWebBrowserFlag),
            enableExpressionEvaluation: true,
            runHeadless: boolArg(kHeadless),
          ),
          devToolsServerAddress: devToolsServerAddress,
        );
        final String target = widgetPreviewScaffoldProject.directory
            .childDirectory('lib')
            .childFile('main.dart')
            .absolute
            .path;
        final FlutterDevice flutterDevice = _flutterDeviceFactoryOverride != null
            ? await _flutterDeviceFactoryOverride(
                device,
                buildInfo: debuggingOptions.buildInfo,
                target: target,
              )
            : await FlutterDevice.create(
                device,
                toolContext: toolContext,
                buildInfo: debuggingOptions.buildInfo,
                target: target,
              );

        if (boolArg(kLaunchPreviewer)) {
          final appStarted = Completer<void>();
          final connectionInfo = Completer<DebugConnectionInfo>();
          _widgetPreviewApp = _residentRunnerFactoryOverride != null
              ? _residentRunnerFactoryOverride(
                  flutterDevice,
                  target: target,
                  debuggingOptions: debuggingOptions,
                  flutterProject: widgetPreviewScaffoldProject,
                  projectRootPath: widgetPreviewScaffoldProject.directory.absolute.path,
                )
              : ResidentWebRunner(
                  flutterDevice,
                  buildSystem: _buildSystem,
                  buildTargets: _buildTargets,
                  toolContext: toolContext,
                  target: target,
                  debuggingOptions: debuggingOptions,
                  analytics: analytics,
                  flutterProject: widgetPreviewScaffoldProject,
                  // Explicitly provide the project root path rather than relying on the current directory
                  // as the current directory exists within $TMP. At least on MacOS, when setting the
                  // current directory to the widget_preview_scaffold project created under
                  // `/var/folders/...`, the underlying chdir call actually changes the directory to
                  // `/private/var/folders/...`. These directories are identical, but confuse the package
                  // config resolution logic.
                  // TODO(bkonyi): consider removing if we stop placing the scaffold in $TMP.
                  // See https://github.com/flutter/flutter/issues/179036
                  projectRootPath: widgetPreviewScaffoldProject.directory.absolute.path,
                  widgetPreviewLiveConfig: WidgetPreviewLiveConfig(
                    dtdServices: _dtdService,
                    allowedOrigins: stringsArg(kWebAllowOrigin),
                  ),
                );
          unawaited(
            _widgetPreviewApp!.run(
              appStartedCompleter: appStarted,
              connectionInfoCompleter: connectionInfo,
            ),
          );
          await appStarted.future;
          final Uri applicationUrl = flutterDevice.devFS!.baseUri!;
          webPreviewUri = applicationUrl;
          final bool legacyDetection = boolArg(kLegacyPreviewDetection);
          logger.sendStartedEvent(
            applicationUrl: applicationUrl,
            dtdUri: legacyDetection ? null : _dtdService.dtdUri,
            previewService: legacyDetection ? null : _dtdService.widgetPreviewService,
            projectRoot: _resolvedProjectRootPath,
            scaffoldService: legacyDetection ? null : _dtdService.widgetPreviewScaffoldService,
          );
          final DebugConnectionInfo debugConnection = await connectionInfo.future;
          final Uri? devToolsUri = devToolsServerAddress ?? debugConnection.devToolsUri;
          if (devToolsUri == null) {
            throwToolExit('Could not determine DevTools server address for the widget inspector.');
          }
          _dtdService.setDevToolsServerAddress(
            devToolsServerAddress: devToolsServerAddress ?? debugConnection.devToolsUri!,
            applicationUri: debugConnection.wsUri!,
          );
        }
      });
    } on Exception catch (error) {
      // Clear the runner reference so any queued reload callbacks become no-ops,
      // then tear down a partially started previewer since the shutdown hook will
      // no longer see it.
      final ResidentRunner? app = _widgetPreviewApp;
      _widgetPreviewApp = null;
      webPreviewUri = null;
      await app?.exitApp();
      throwToolExit(error.toString());
    }

    // WARNING: this log message is used by test/integration.shard/widget_preview_test.dart
    logger.printStatus('Done loading previews.');

    // Send an analytics event reporting how long it took for the widget previewer to start.
    final WidgetPreviewLaunchMode launchMode = boolArg(kHeadless)
        ? .headless
        : (boolArg(kWebServer) ? .webServer : .interactive);
    previewAnalytics
      ..reportLaunchTiming()
      ..reportLaunchMode(launchMode);

    // If _widgetPreviewApp is null --no-launch-previewer was provided so return success.
    if (_widgetPreviewApp == null) {
      return 0;
    }
    final int exitCode = await _widgetPreviewApp!.waitForAppToFinish();
    // Clear the runner reference so any reload callbacks triggered after the
    // previewer exits become no-ops.
    _widgetPreviewApp = null;
    webPreviewUri = null;
    return exitCode;
  }
}

final class WidgetPreviewCleanCommand extends WidgetPreviewSubCommandBase {
  WidgetPreviewCleanCommand({required super.toolContext});

  @override
  String get description => 'Cleans up widget preview state.';

  @override
  String get name => 'clean';

  @override
  Future<FlutterCommandResult> runCommand() async {
    final Directory widgetPreviewScaffold = getRootProject().widgetPreviewScaffold;
    if (widgetPreviewScaffold.existsSync()) {
      final String scaffoldPath = widgetPreviewScaffold.path;
      logger.printStatus('Deleting widget preview scaffold at $scaffoldPath.');
      widgetPreviewScaffold.deleteSync(recursive: true);
    } else {
      logger.printStatus('Nothing to clean up.');
    }
    return FlutterCommandResult.success();
  }
}

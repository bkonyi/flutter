// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:dtd/dtd.dart';
import 'package:file/memory.dart';
import 'package:file_testing/file_testing.dart';
import 'package:flutter_tools/executable.dart';
import 'package:flutter_tools/src/application_package.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/base/terminal.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/commands/daemon.dart';
import 'package:flutter_tools/src/commands/widget_preview.dart';
import 'package:flutter_tools/src/convert.dart';
import 'package:flutter_tools/src/dart/analysis.dart';
import 'package:flutter_tools/src/devfs.dart';
import 'package:flutter_tools/src/device.dart';
import 'package:flutter_tools/src/isolated/build_targets.dart';
import 'package:flutter_tools/src/isolated/devfs_web.dart';
import 'package:flutter_tools/src/isolated/web_asset_server.dart';
import 'package:flutter_tools/src/isolated/widget_preview_live_server.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/resident_runner.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:flutter_tools/src/web/memory_fs.dart';
import 'package:flutter_tools/src/widget_preview/analytics.dart';
import 'package:flutter_tools/src/widget_preview/dtd_services.dart';
import 'package:flutter_tools/src/widget_preview/dtd_types.dart';
import 'package:flutter_tools/src/widget_preview/preview_code_generator.dart';
import 'package:flutter_tools/src/widget_preview/preview_git_exclude.dart';
import 'package:flutter_tools/src/widget_preview/preview_manifest.dart';
import 'package:flutter_tools/src/widget_preview/preview_pubspec_builder.dart';
import 'package:flutter_tools/src/widget_preview/preview_session_client.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:process/process.dart';
import 'package:test/fake.dart';
import 'package:watcher/watcher.dart';

import '../../../src/common.dart';
import '../../../src/context.dart' show FakeDeviceManager, FakeSignals;
import '../../../src/fake_process_manager.dart'
    show FakeCommand, FakeProcess, FakeProcessManager, hasNoRemainingExpectations;
import '../../../src/fakes.dart' hide FakeProcess;
import '../../../src/test_build_system.dart';
import '../../../src/test_flutter_command_runner.dart';

const _kFailedRecompileMessage = 'Failed to recompile application.';
const _kProjectRootPath = '/project';
const _kMainDartPath = '/project/lib/main.dart';

class FakeWidgetPreviewDtdServices extends Fake implements WidgetPreviewDtdServices {
  @override
  Uri? dtdUri = Uri.parse('ws://127.0.0.1:54322/secret');

  @override
  String widgetPreviewService = 'widget-preview-uuid';

  @override
  String widgetPreviewScaffoldService = 'PreviewScaffold-uuid';

  @override
  String widgetPreviewScaffoldStream = 'WidgetPreviewScaffold-uuid';

  @override
  bool scaffoldConnected = true;

  int markScaffoldConnectedCount = 0;
  int markScaffoldDisconnectedCount = 0;
  int waitForScaffoldConnectedCount = 0;
  int waitForAnalysisCount = 0;
  Duration? lastWaitForScaffoldTimeout;
  Completer<void>? scaffoldConnectedCompleter;
  FlutterWidgetPreviews? nextPreviews;
  final postedReloadedEvents = <bool>[];

  @override
  Future<void> postPreviewReloaded({required bool fullRestart}) async {
    postedReloadedEvents.add(fullRestart);
  }

  @override
  void markScaffoldConnected() {
    markScaffoldConnectedCount++;
    scaffoldConnected = true;
    if (scaffoldConnectedCompleter case final Completer<void> completer
        when !completer.isCompleted) {
      completer.complete();
    }
    scaffoldConnectedCompleter = null;
  }

  @override
  void markScaffoldDisconnected() {
    markScaffoldDisconnectedCount++;
    scaffoldConnected = false;
  }

  @override
  Future<void> waitForScaffoldConnected({
    Duration timeout = const Duration(milliseconds: WidgetPreviewDtdServices.kDefaultSyncTimeoutMs),
  }) async {
    waitForScaffoldConnectedCount++;
    lastWaitForScaffoldTimeout = timeout;
    if (scaffoldConnectedCompleter != null) {
      await scaffoldConnectedCompleter!.future.timeout(timeout);
    }
    scaffoldConnected = true;
  }

  @override
  Future<void> launchAndConnect({required AnalysisServer analysisServer}) async {}

  @override
  Future<void> waitForAnalysis({Duration delay = const Duration(milliseconds: 100)}) async {
    waitForAnalysisCount++;
  }

  @override
  Future<FlutterWidgetPreviews> getFlutterWidgetPreviews() async {
    return nextPreviews ??
        const FlutterWidgetPreviews(
          namespaces: <String, String>{},
          previews: <FlutterWidgetPreviewDetails>[],
          scriptUris: <Uri>[],
        );
  }
}

class FakeResidentRunner extends Fake implements ResidentRunner {
  FakeResidentRunner({
    this.currentRestartCompleter,
    this.flutterDevices = const <FlutterDevice>[],
    this.onRestart,
  });

  @override
  final List<FlutterDevice> flutterDevices;

  final OperationResult Function(bool fullRestart)? onRestart;
  Completer<OperationResult>? currentRestartCompleter;
  int restartCount = 0;
  int concurrentRestarts = 0;
  int maxConcurrentRestarts = 0;
  final fullRestartRequests = <bool>[];

  @override
  Future<OperationResult> restart({
    bool fullRestart = false,
    bool? pause = false,
    String? reason,
    bool benchmarkMode = false,
  }) async {
    restartCount++;
    fullRestartRequests.add(fullRestart);
    concurrentRestarts++;
    if (concurrentRestarts > maxConcurrentRestarts) {
      maxConcurrentRestarts = concurrentRestarts;
    }
    if (currentRestartCompleter != null) {
      await currentRestartCompleter!.future;
    }
    concurrentRestarts--;
    return onRestart?.call(fullRestart) ?? OperationResult.ok;
  }
}

void main() {
  // Regression tests for https://github.com/flutter/flutter/issues/192697.
  group('$WidgetPreviewStartCommand reload handling', () {
    late MemoryFileSystem fs;
    late BufferLogger bufferLogger;
    late WidgetPreviewMachineAwareLogger logger;
    late FlutterProject scaffoldProject;
    late FlutterWidgetPreviews emptyPreviewUpdate;

    late FakeWidgetPreviewDtdServices fakeDtdServices;

    setUp(() {
      fs = MemoryFileSystem.test();
      bufferLogger = BufferLogger.test();
      logger = WidgetPreviewMachineAwareLogger(
        bufferLogger,
        machine: false,
        stdio: FakeStdio(),
        verbose: false,
      );
      fakeDtdServices = FakeWidgetPreviewDtdServices();
      final Directory rootDir = fs.directory(_kProjectRootPath)..createSync(recursive: true);
      fs.currentDirectory = rootDir;
      rootDir.childFile('pubspec.yaml').writeAsStringSync('''
name: my_app
environment:
  sdk: ^3.7.0
''');
      final Directory scaffoldDir = rootDir
          .childDirectory('.dart_tool')
          .childDirectory('widget_preview_scaffold');
      scaffoldDir.childDirectory('lib').childDirectory('src').createSync(recursive: true);
      scaffoldDir.childFile('pubspec.yaml').writeAsStringSync('''
name: widget_preview_scaffold
environment:
  sdk: ^3.7.0
''');
      scaffoldProject = FlutterProject.fromDirectoryTest(scaffoldDir, logger);
      emptyPreviewUpdate = FlutterWidgetPreviews(
        namespaces: const <String, String>{},
        previews: const <FlutterWidgetPreviewDetails>[],
        scriptUris: <Uri>[fs.file(_kMainDartPath).uri],
      );
    });

    WidgetPreviewStartCommand createStartCommand(FakeResidentRunner runner) {
      final command = WidgetPreviewCommand(
        buildSystem: TestBuildSystem.all(BuildResult(success: true)),
        buildTargets: const BuildTargetsImpl(),
        toolContext: FakeToolContext(
          artifacts: Artifacts.test(),
          fs: fs,
          logger: logger,
          platform: FakePlatform(),
          processManager: FakeProcessManager.empty(),
          shutdownHooks: ShutdownHooks(),
          signals: FakeSignals(),
        ),
        dtdServicesOverride: fakeDtdServices,
      );
      return (command.subcommands['start']! as WidgetPreviewStartCommand)
        ..previewCodeGenerator = PreviewCodeGenerator(
          widgetPreviewScaffoldProject: scaffoldProject,
          fs: fs,
        )
        ..widgetPreviewApp = runner;
    }

    testWithoutContext(
      'onChangeDetected triggers hot restart under reload mutex when hot reload is rejected',
      () async {
        var rejectNextHotReload = true;
        final rejectedReloadCompleter = Completer<OperationResult>();
        final fakeResidentRunner = FakeResidentRunner(
          currentRestartCompleter: rejectedReloadCompleter,
          onRestart: (bool fullRestart) {
            if (!fullRestart && rejectNextHotReload) {
              rejectNextHotReload = false;
              return OperationResult(
                1,
                _kFailedRecompileMessage,
                updateFSReport: UpdateFSReport(hotReloadRejected: true),
              );
            }
            return OperationResult.ok;
          },
        );
        final WidgetPreviewStartCommand startCommand = createStartCommand(fakeResidentRunner);

        // Start a reload that will be rejected, then queue a follow-up change while the
        // rejected reload is still in flight.
        startCommand.onChangeDetected(emptyPreviewUpdate);
        await pumpEventQueue();
        expect(fakeResidentRunner.restartCount, 1);
        expect(fakeResidentRunner.concurrentRestarts, 1);

        startCommand.onChangeDetected(emptyPreviewUpdate);

        fakeResidentRunner.currentRestartCompleter = null;
        rejectedReloadCompleter.complete(OperationResult.ok);
        await pumpEventQueue();

        // The fallback hot restart must complete inside _reloadMutex before the queued
        // follow-up hot reload executes, with zero overlapping restart calls.
        expect(fakeResidentRunner.maxConcurrentRestarts, 1);
        expect(fakeResidentRunner.fullRestartRequests, <bool>[false, true, false]);
        expect(
          bufferLogger.statusText,
          contains(WidgetPreviewStartCommand.kHotReloadRejectedMessage),
        );
        expect(
          scaffoldProject.directory
              .childDirectory('lib')
              .childDirectory('src')
              .childFile('generated_preview.dart'),
          exists,
        );
      },
    );

    testWithoutContext(
      'onChangeDetected does not trigger hot restart when hot reload fails without rejection',
      () async {
        final fakeResidentRunner = FakeResidentRunner(
          onRestart: (bool fullRestart) {
            return OperationResult(1, _kFailedRecompileMessage, updateFSReport: UpdateFSReport());
          },
        );
        final WidgetPreviewStartCommand startCommand = createStartCommand(fakeResidentRunner);

        startCommand.onChangeDetected(emptyPreviewUpdate);
        await pumpEventQueue();

        expect(fakeResidentRunner.fullRestartRequests, <bool>[false]);
        expect(
          bufferLogger.statusText,
          isNot(contains(WidgetPreviewStartCommand.kHotReloadRejectedMessage)),
        );
      },
    );

    testWithoutContext(
      'onChangeDetected does not trigger hot restart when hot reload succeeds',
      () async {
        final fakeResidentRunner = FakeResidentRunner(
          onRestart: (bool fullRestart) {
            return OperationResult(
              0,
              '',
              updateFSReport: UpdateFSReport(success: true, hotReloadRejected: true),
            );
          },
        );
        final WidgetPreviewStartCommand startCommand = createStartCommand(fakeResidentRunner);

        startCommand.onChangeDetected(emptyPreviewUpdate);
        await pumpEventQueue();

        expect(fakeResidentRunner.fullRestartRequests, <bool>[false]);
        expect(
          bufferLogger.statusText,
          isNot(contains(WidgetPreviewStartCommand.kHotReloadRejectedMessage)),
        );
      },
    );

    testWithoutContext('handleReload returns fallback hot restart result when rejected', () async {
      final fakeResidentRunner = FakeResidentRunner(
        onRestart: (bool fullRestart) {
          if (!fullRestart) {
            return OperationResult(
              1,
              _kFailedRecompileMessage,
              updateFSReport: UpdateFSReport(hotReloadRejected: true),
            );
          }
          return OperationResult.ok;
        },
      );
      final WidgetPreviewStartCommand startCommand = createStartCommand(fakeResidentRunner);

      final OperationResult? result = await startCommand.handleReload();

      expect(fakeResidentRunner.fullRestartRequests, <bool>[false, true]);
      expect(result?.isOk, isTrue);
      expect(
        bufferLogger.statusText,
        contains(WidgetPreviewStartCommand.kHotReloadRejectedMessage),
      );
    });

    testWithoutContext(
      'handleReload returns failed result when hot reload fails for other reasons',
      () async {
        final fakeResidentRunner = FakeResidentRunner(
          onRestart: (bool fullRestart) {
            return OperationResult(1, _kFailedRecompileMessage, updateFSReport: UpdateFSReport());
          },
        );
        final WidgetPreviewStartCommand startCommand = createStartCommand(fakeResidentRunner);

        final OperationResult? result = await startCommand.handleReload();

        expect(fakeResidentRunner.fullRestartRequests, <bool>[false]);
        expect(fakeDtdServices.markScaffoldDisconnectedCount, 0);
        expect(result?.isOk, isFalse);
        expect(
          bufferLogger.statusText,
          isNot(contains(WidgetPreviewStartCommand.kHotReloadRejectedMessage)),
        );
      },
    );

    testWithoutContext('syncPreviews regenerates previews when changed, reloads, and waits for scaffold when disconnected', () async {
      final fakeResidentRunner = FakeResidentRunner();
      fakeDtdServices.scaffoldConnected = false;
      fakeDtdServices.nextPreviews = FlutterWidgetPreviews(
        namespaces: const <String, String>{
          'widget_preview.dart': '_i1',
          'utils.dart': '_i2',
          'package:my_app/main.dart': '_i3',
          'package:flutter/src/widget_previews/widget_previews.dart': '_i4',
        },
        previews: <FlutterWidgetPreviewDetails>[
          FlutterWidgetPreviewDetails(
            functionName: 'okPreview',
            hasError: false,
            dependencyHasErrors: false,
            isBuilder: false,
            isMultiPreview: false,
            packageName: 'my_app',
            position: const Position(character: 0, line: 10),
            previewAnnotation: "const _i4.Preview(name: 'OK')",
            scriptUri: fs.file(_kMainDartPath).uri,
            libraryUri: Uri.parse('package:my_app/main.dart'),
          ),
          FlutterWidgetPreviewDetails(
            functionName: 'brokenPreview',
            hasError: true,
            dependencyHasErrors: false,
            isBuilder: false,
            isMultiPreview: false,
            packageName: 'my_app',
            position: const Position(character: 0, line: 20),
            previewAnnotation: "const _i4.Preview(name: 'Broken')",
            scriptUri: fs.file(_kMainDartPath).uri,
            libraryUri: Uri.parse('package:my_app/main.dart'),
          ),
        ],
        scriptUris: <Uri>[fs.file(_kMainDartPath).uri],
      );

      final WidgetPreviewStartCommand startCommand = createStartCommand(fakeResidentRunner);
      final File generatedFile = scaffoldProject.directory
          .childDirectory('lib')
          .childDirectory('src')
          .childFile('generated_preview.dart');
      expect(generatedFile, isNot(exists));

      final SyncPreviewsResponse response = await startCommand.syncPreviews(
        timeout: const Duration(seconds: 12),
      );

      expect(generatedFile, exists);
      expect(generatedFile.readAsStringSync(), contains('okPreview'));
      expect(fakeDtdServices.waitForAnalysisCount, 1);
      expect(fakeDtdServices.waitForScaffoldConnectedCount, 1);
      expect(fakeDtdServices.lastWaitForScaffoldTimeout, const Duration(seconds: 12));
      expect(fakeResidentRunner.fullRestartRequests, <bool>[false]);
      expect(
        response,
        equals(
          const SyncPreviewsResponse(
            compileSuccess: true,
            errorPreviewCount: 1,
            fullRestart: false,
            reloaded: true,
          ),
        ),
      );

      // Second sync with unchanged preview metadata still triggers an incremental
      // reload (capturing widget body edits), without waiting for Connected again.
      generatedFile.writeAsStringSync('// sentinel');
      final SyncPreviewsResponse secondResponse = await startCommand.syncPreviews();

      expect(generatedFile.readAsStringSync(), '// sentinel');
      expect(fakeResidentRunner.fullRestartRequests, <bool>[false, false]);
      expect(fakeDtdServices.waitForScaffoldConnectedCount, 1);
      expect(secondResponse.reloaded, isTrue);
      expect(secondResponse.fullRestart, isFalse);
    });

    testWithoutContext('syncPreviews marks scaffold disconnected before fallback hot restart and waits for reconnect', () async {
      var scaffoldWasMarkedDisconnectedBeforeRestart = false;
      final fakeResidentRunner = FakeResidentRunner(
        onRestart: (bool fullRestart) {
          if (!fullRestart) {
            return OperationResult(
              1,
              _kFailedRecompileMessage,
              updateFSReport: UpdateFSReport(hotReloadRejected: true),
            );
          }
          scaffoldWasMarkedDisconnectedBeforeRestart = !fakeDtdServices.scaffoldConnected;
          return OperationResult.ok;
        },
      );
      final WidgetPreviewStartCommand startCommand = createStartCommand(fakeResidentRunner);

      final SyncPreviewsResponse response = await startCommand.syncPreviews();

      expect(scaffoldWasMarkedDisconnectedBeforeRestart, isTrue);
      expect(fakeDtdServices.markScaffoldDisconnectedCount, 1);
      expect(fakeDtdServices.waitForScaffoldConnectedCount, 1);
      expect(fakeResidentRunner.fullRestartRequests, <bool>[false, true]);
      expect(
        response,
        equals(
          const SyncPreviewsResponse(
            compileSuccess: true,
            errorPreviewCount: 0,
            fullRestart: true,
            reloaded: true,
          ),
        ),
      );
    });

    testWithoutContext(
      'syncPreviews returns compileError immediately without hanging when compile fails',
      () async {
        fakeDtdServices.scaffoldConnected = false;
        final fakeResidentRunner = FakeResidentRunner(
          onRestart: (bool fullRestart) {
            return OperationResult(1, _kFailedRecompileMessage, updateFSReport: UpdateFSReport());
          },
        );
        final WidgetPreviewStartCommand startCommand = createStartCommand(fakeResidentRunner);

        final SyncPreviewsResponse response = await startCommand.syncPreviews();

        expect(fakeDtdServices.waitForScaffoldConnectedCount, 0);
        expect(
          response,
          equals(
            const SyncPreviewsResponse(
              compileError: _kFailedRecompileMessage,
              compileSuccess: false,
              errorPreviewCount: 0,
              fullRestart: false,
              reloaded: false,
            ),
          ),
        );
      },
    );

    testWithoutContext('restores scaffoldConnected when full restart fails compilation so subsequent incremental syncPreviews does not hang', () async {
      // Uncompleted completer models a running browser scaffold isolate that
      // will not emit a new Connected event when fullRestart fails before
      // hotRestart is sent to the browser.
      fakeDtdServices.scaffoldConnected = true;
      fakeDtdServices.scaffoldConnectedCompleter = Completer<void>();

      var failCompilation = true;
      var rejectHotReload = true;
      var disconnectedDuringFullRestart = false;
      final fakeResidentRunner = FakeResidentRunner(
        onRestart: (bool fullRestart) {
          if (fullRestart) {
            disconnectedDuringFullRestart = !fakeDtdServices.scaffoldConnected;
          }
          if (!fullRestart && rejectHotReload) {
            rejectHotReload = false;
            return OperationResult(
              1,
              _kFailedRecompileMessage,
              updateFSReport: UpdateFSReport(hotReloadRejected: true),
            );
          }
          if (failCompilation) {
            return OperationResult(1, _kFailedRecompileMessage, updateFSReport: UpdateFSReport());
          }
          return OperationResult.ok;
        },
      );
      final WidgetPreviewStartCommand startCommand = createStartCommand(fakeResidentRunner);

      // 1. Rejected hot reload falls back to fullRestart, which fails to compile.
      final SyncPreviewsResponse failedFallbackResponse = await startCommand.syncPreviews(
        timeout: const Duration(milliseconds: 10),
      );
      expect(disconnectedDuringFullRestart, isTrue);
      expect(fakeDtdServices.markScaffoldDisconnectedCount, 1);
      expect(fakeDtdServices.markScaffoldConnectedCount, 1);
      expect(fakeDtdServices.scaffoldConnected, isTrue);
      expect(fakeDtdServices.waitForScaffoldConnectedCount, 0);
      expect(
        failedFallbackResponse,
        equals(
          const SyncPreviewsResponse(
            compileError: _kFailedRecompileMessage,
            compileSuccess: false,
            errorPreviewCount: 0,
            fullRestart: true,
            reloaded: false,
          ),
        ),
      );

      // 2. Subsequent incremental syncPreviews succeeds without hanging on Connected.
      failCompilation = false;
      fakeDtdServices.scaffoldConnectedCompleter = Completer<void>();
      final SyncPreviewsResponse recoveredResponse = await startCommand.syncPreviews(
        timeout: const Duration(milliseconds: 10),
      );
      expect(fakeDtdServices.waitForScaffoldConnectedCount, 0);
      expect(
        recoveredResponse,
        equals(
          const SyncPreviewsResponse(
            compileSuccess: true,
            errorPreviewCount: 0,
            fullRestart: false,
            reloaded: true,
          ),
        ),
      );

      // 3. Explicit hot restart request failing compilation also restores scaffoldConnected.
      failCompilation = true;
      startCommand.onHotRestartRequest();
      await pumpEventQueue();
      expect(fakeDtdServices.markScaffoldDisconnectedCount, 2);
      expect(fakeDtdServices.markScaffoldConnectedCount, 2);
      expect(fakeDtdServices.scaffoldConnected, isTrue);

      // 4. When scaffold was never connected, a failed fullRestart keeps scaffoldConnected false.
      fakeDtdServices.scaffoldConnected = false;
      startCommand.onHotRestartRequest();
      await pumpEventQueue();
      expect(fakeDtdServices.markScaffoldDisconnectedCount, 3);
      expect(fakeDtdServices.markScaffoldConnectedCount, 2);
      expect(fakeDtdServices.scaffoldConnected, isFalse);
    });

    testWithoutContext('syncPreviews returns reloaded false without throwing before startup initialization or during shutdown', () async {
      final shutdownHooks = ShutdownHooks();
      final command = WidgetPreviewCommand(
        buildSystem: TestBuildSystem.all(BuildResult(success: true)),
        buildTargets: const BuildTargetsImpl(),
        toolContext: FakeToolContext(
          artifacts: Artifacts.test(),
          fs: fs,
          logger: logger,
          platform: FakePlatform(),
          processManager: FakeProcessManager.empty(),
          shutdownHooks: shutdownHooks,
          signals: FakeSignals(),
        ),
        dtdServicesOverride: fakeDtdServices,
      );
      // Neither previewCodeGenerator nor widgetPreviewApp is initialized yet.
      final uninitializedStartCommand = command.subcommands['start']! as WidgetPreviewStartCommand;

      final SyncPreviewsResponse preInitResponse = await uninitializedStartCommand.syncPreviews();
      expect(fakeDtdServices.waitForAnalysisCount, 0);
      expect(
        preInitResponse,
        equals(
          const SyncPreviewsResponse(
            compileSuccess: true,
            errorPreviewCount: 0,
            fullRestart: false,
            reloaded: false,
          ),
        ),
      );

      final fakeResidentRunner = FakeResidentRunner();
      uninitializedStartCommand
        ..previewCodeGenerator = PreviewCodeGenerator(
          widgetPreviewScaffoldProject: scaffoldProject,
          fs: fs,
        )
        ..widgetPreviewApp = fakeResidentRunner;

      await shutdownHooks.runShutdownHooks(logger);
      final SyncPreviewsResponse shutdownResponse = await uninitializedStartCommand.syncPreviews();
      expect(fakeDtdServices.waitForAnalysisCount, 0);
      expect(fakeResidentRunner.restartCount, 0);
      expect(
        shutdownResponse,
        equals(
          const SyncPreviewsResponse(
            compileSuccess: true,
            errorPreviewCount: 0,
            fullRestart: false,
            reloaded: false,
          ),
        ),
      );
    });

    testWithoutContext(
      'onHotReloadRequest reloads and onHotRestartRequest marks scaffold disconnected',
      () async {
        final fakeResidentRunner = FakeResidentRunner();
        final WidgetPreviewStartCommand startCommand = createStartCommand(fakeResidentRunner);

        await startCommand.onHotReloadRequest();
        expect(fakeResidentRunner.fullRestartRequests, <bool>[false]);
        expect(fakeDtdServices.markScaffoldDisconnectedCount, 0);

        startCommand.onHotRestartRequest();
        await pumpEventQueue();
        expect(fakeResidentRunner.fullRestartRequests, <bool>[false, true]);
        expect(fakeDtdServices.markScaffoldDisconnectedCount, 1);
      },
    );

    testWithoutContext(
      'wires DTD RPC callbacks and emits machine started event with DTD metadata',
      () async {
        final fakeStdio = FakeStdio();
        final machineLogger = WidgetPreviewMachineAwareLogger(
          BufferLogger.test(),
          machine: true,
          stdio: fakeStdio,
          verbose: false,
        );
        final fakeResidentRunner = FakeResidentRunner();
        fs.directory(_kProjectRootPath)
          ..childDirectory('.widget_preview').childFile('pubspec.yaml').createSync(recursive: true)
          ..childDirectory('.widget_preview')
              .childFile('pubspec.yaml')
              .writeAsStringSync('name: widget_preview_scaffold\n');

        final command = WidgetPreviewCommand(
          buildSystem: TestBuildSystem.all(BuildResult(success: true)),
          buildTargets: const BuildTargetsImpl(),
          toolContext: FakeToolContext(
            artifacts: Artifacts.test(),
            fs: fs,
            logger: machineLogger,
            platform: FakePlatform(),
            processManager: FakeProcessManager.empty(),
            shutdownHooks: ShutdownHooks(),
            signals: FakeSignals(),
          ),
        );
        // Verify WidgetPreviewMachineAwareLogger.sendStartedEvent wire schema.
        machineLogger.sendStartedEvent(
          applicationUrl: Uri.parse('http://localhost:54321'),
          dtdUri: Uri.parse('ws://127.0.0.1:54322/secret'),
          previewService: 'widget-preview-abc',
          projectRoot: _kProjectRootPath,
          scaffoldService: 'PreviewScaffold-abc',
        );

        final String emittedLine = fakeStdio.writtenToStdout.single.trim();
        final decoded = json.decode(emittedLine) as List<Object?>;
        expect(
          decoded,
          equals(<Object?>[
            <String, Object?>{
              'event': 'widget_preview.started',
              'params': <String, Object?>{
                'url': 'http://localhost:54321',
                'dtdUri': 'ws://127.0.0.1:54322/secret',
                'previewService': 'widget-preview-abc',
                'scaffoldService': 'PreviewScaffold-abc',
                'projectRoot': _kProjectRootPath,
              },
            },
          ]),
        );

        // Verify the real WidgetPreviewDtdServices instance constructed and wired by
        // WidgetPreviewStartCommand itself (no dtdServicesOverride).
        final wiredStartCommand = (command.subcommands['start']! as WidgetPreviewStartCommand)
          ..previewCodeGenerator = PreviewCodeGenerator(
            widgetPreviewScaffoldProject: scaffoldProject,
            fs: fs,
          )
          ..widgetPreviewApp = fakeResidentRunner
          ..webPreviewUri = Uri.parse('http://localhost:54321');
        final WidgetPreviewDtdServices dtdServices = wiredStartCommand.dtdService;
        final String uuid = dtdServices.serviceUuid;

        DTDServiceCallback callbackFor(String method) {
          for (final (String name, DTDServiceCallback cb) in dtdServices.services) {
            if (name == method) {
              return cb;
            }
          }
          fail('Missing $method');
        }

        final Map<String, Object?> infoJson = await callbackFor(
          WidgetPreviewDtdServices.kGetServiceInfo,
        )(Parameters('getServiceInfo', <String, Object?>{}));
        expect(infoJson[PreviewServiceInfo.kType], PreviewServiceInfo.kTypeName);
        expect(infoJson[PreviewServiceInfo.kProjectRoot], _kProjectRootPath);
        expect(infoJson[PreviewServiceInfo.kPreviewService], 'widget-preview-$uuid');
        expect(infoJson[PreviewServiceInfo.kScaffoldService], 'PreviewScaffold-$uuid');
        expect(infoJson[PreviewServiceInfo.kScaffoldStream], 'WidgetPreviewScaffold-$uuid');
        expect(infoJson[PreviewServiceInfo.kWebPreviewUri], 'http://localhost:54321');

        final Map<String, Object?> urlJson = await callbackFor(
          WidgetPreviewDtdServices.kGetWebPreviewUrl,
        )(Parameters('getWebPreviewUrl', <String, Object?>{}));
        expect(urlJson[WebPreviewUrlResult.kType], WebPreviewUrlResult.kTypeName);
        expect(urlJson[WebPreviewUrlResult.kUrl], 'http://localhost:54321');

        final Map<String, Object?> reloadJson = await callbackFor(
          WidgetPreviewDtdServices.kHotReloadPreviewer,
        )(Parameters('hotReloadPreviewer', <String, Object?>{}));
        expect(reloadJson, equals(const Success().toJson()));
        expect(fakeResidentRunner.restartCount, 1);

        // Verify listPreviews is wired on the command's dtdService and falls back to
        // _lastGeneratedPreviews when scaffold is disconnected.
        wiredStartCommand.onChangeDetected(
          FlutterWidgetPreviews(
            namespaces: const <String, String>{
              'widget_preview.dart': '_i1',
              'utils.dart': '_i2',
              'package:my_app/main.dart': '_i3',
              'package:flutter/src/widget_previews/widget_previews.dart': '_i4',
            },
            previews: <FlutterWidgetPreviewDetails>[
              FlutterWidgetPreviewDetails(
                functionName: 'wiredPreview',
                hasError: false,
                dependencyHasErrors: false,
                isBuilder: false,
                isMultiPreview: false,
                packageName: 'my_app',
                position: const Position(character: 2, line: 8),
                previewAnnotation: "const _i4.Preview(name: 'Wired')",
                scriptUri: fs.file(_kMainDartPath).uri,
                libraryUri: Uri.parse('package:my_app/main.dart'),
              ),
            ],
            scriptUris: <Uri>[fs.file(_kMainDartPath).uri],
          ),
        );
        await pumpEventQueue();

        final Map<String, Object?> listJson = await callbackFor(
          WidgetPreviewDtdServices.kListPreviews,
        )(Parameters('listPreviews', <String, Object?>{'sync': false}));
        final PreviewListResponse parsedList = PreviewListResponse.fromJson(listJson);
        expect(parsedList.previews, hasLength(1));
        expect(parsedList.previews.single.id, 'package:my_app/main.dart::wiredPreview');
        expect(parsedList.previews.single.name, 'Wired');
      },
    );

    testWithoutContext('broadcasts PreviewReloaded with fullRestart payload on successful syncPreviews, handleReload, and _triggerReload, and skips on failure', () async {
      // 1. syncPreviews incremental reload, fallback hot restart, and failure.
      var mode = 'ok';
      final fakeResidentRunner = FakeResidentRunner(
        onRestart: (bool fullRestart) {
          if (mode == 'reject_then_ok') {
            return fullRestart
                ? OperationResult.ok
                : OperationResult(
                    1,
                    _kFailedRecompileMessage,
                    updateFSReport: UpdateFSReport(hotReloadRejected: true),
                  );
          }
          if (mode == 'fail') {
            return OperationResult(1, _kFailedRecompileMessage, updateFSReport: UpdateFSReport());
          }
          return OperationResult.ok;
        },
      );
      final WidgetPreviewStartCommand startCommand = createStartCommand(fakeResidentRunner);

      final SyncPreviewsResponse incrementalSync = await startCommand.syncPreviews();
      expect(incrementalSync.compileSuccess, isTrue);
      expect(incrementalSync.reloaded, isTrue);
      expect(incrementalSync.fullRestart, isFalse);
      expect(fakeDtdServices.postedReloadedEvents, <bool>[false]);

      mode = 'reject_then_ok';
      final SyncPreviewsResponse fallbackSync = await startCommand.syncPreviews();
      expect(fallbackSync.compileSuccess, isTrue);
      expect(fallbackSync.reloaded, isTrue);
      expect(fallbackSync.fullRestart, isTrue);
      expect(fakeDtdServices.postedReloadedEvents, <bool>[false, true]);

      mode = 'fail';
      final SyncPreviewsResponse failedSync = await startCommand.syncPreviews();
      expect(failedSync.compileSuccess, isFalse);
      expect(failedSync.reloaded, isFalse);
      expect(fakeDtdServices.postedReloadedEvents, <bool>[false, true]);

      // 2. File-watcher _triggerReload (via onChangeDetected) and onHotRestartRequest.
      mode = 'ok';
      startCommand.onChangeDetected(emptyPreviewUpdate);
      await pumpEventQueue();
      expect(fakeDtdServices.postedReloadedEvents, <bool>[false, true, false]);

      mode = 'reject_then_ok';
      startCommand.onChangeDetected(emptyPreviewUpdate);
      await pumpEventQueue();
      expect(fakeDtdServices.postedReloadedEvents, <bool>[false, true, false, true]);

      mode = 'fail';
      startCommand.onChangeDetected(emptyPreviewUpdate);
      await pumpEventQueue();
      expect(fakeDtdServices.postedReloadedEvents, <bool>[false, true, false, true]);

      mode = 'ok';
      startCommand.onHotRestartRequest();
      await pumpEventQueue();
      expect(fakeDtdServices.postedReloadedEvents, <bool>[false, true, false, true, true]);

      mode = 'fail';
      startCommand.onHotRestartRequest();
      await pumpEventQueue();
      expect(fakeDtdServices.postedReloadedEvents, <bool>[false, true, false, true, true]);

      // 3. Verify real WidgetPreviewDtdServices posts PreviewReloaded on
      // widgetPreviewScaffoldStream through DartToolingDaemon.
      final recordingDtd = _RecordingBroadcastDtd();
      addTearDown(recordingDtd.close);
      final realDtdServices = WidgetPreviewDtdServices(
        addUuidToServiceName: false,
        dtd: recordingDtd,
        dtdLauncher: DtdLauncher(
          artifacts: Artifacts.test(),
          logger: logger,
          processManager: FakeProcessManager.empty(),
        ),
        fs: fs,
        logger: logger,
        onHotRestartPreviewerRequest: () {},
        previewAnalytics: WidgetPreviewAnalytics(
          analytics: getInitializedFakeAnalyticsInstance(
            fs: fs,
            fakeFlutterVersion: FakeFlutterVersion(),
          ),
        ),
        project: scaffoldProject,
        shutdownHooks: ShutdownHooks(),
      );
      await realDtdServices.connect(dtdWsUri: Uri.parse('ws://127.0.0.1:54322/secret'));
      final wiredCommand = WidgetPreviewCommand(
        buildSystem: TestBuildSystem.all(BuildResult(success: true)),
        buildTargets: const BuildTargetsImpl(),
        toolContext: FakeToolContext(
          artifacts: Artifacts.test(),
          fs: fs,
          logger: logger,
          platform: FakePlatform(),
          processManager: FakeProcessManager.empty(),
          shutdownHooks: ShutdownHooks(),
          signals: FakeSignals(),
        ),
        dtdServicesOverride: realDtdServices,
      );
      final wiredStart = (wiredCommand.subcommands['start']! as WidgetPreviewStartCommand)
        ..previewCodeGenerator = PreviewCodeGenerator(
          widgetPreviewScaffoldProject: scaffoldProject,
          fs: fs,
        )
        ..widgetPreviewApp = FakeResidentRunner();

      wiredStart.onChangeDetected(emptyPreviewUpdate);
      await pumpEventQueue();
      expect(recordingDtd.postedEvents, hasLength(1));
      expect(
        recordingDtd.postedEvents.single.streamId,
        WidgetPreviewDtdServices.kWidgetPreviewScaffoldStreamRoot,
      );
      expect(
        recordingDtd.postedEvents.single.eventKind,
        WidgetPreviewDtdServices.kPreviewReloadedEvent,
      );
      expect(
        recordingDtd.postedEvents.single.eventData,
        equals(const <String, Object?>{WidgetPreviewDtdServices.kFullRestart: false}),
      );
    });

    testWithoutContext('skips postPreviewReloaded on no-op syncPreviews and handleReload when WebMemoryFS revision is unchanged', () async {
      final webMemoryFS = WebMemoryFS()
        ..writeFileBytes('packages/my_app/main.dart.lib.js', Uint8List.fromList(<int>[1, 2, 3]));
      final fakeLiveServer = _FakePrewarmLiveServer();
      final fakeAssetServer = _FakeWebAssetServer(
        liveServer: fakeLiveServer,
        webMemoryFS: webMemoryFS,
      );
      final fakeDevice = _FakeFlutterDevice(devFS: _FakeWebDevFS(webAssetServer: fakeAssetServer));
      var advanceRevisionOnRestart = false;
      var rejectHotReload = false;
      final fakeResidentRunner = FakeResidentRunner(
        flutterDevices: <FlutterDevice>[fakeDevice],
        onRestart: (bool fullRestart) {
          if (!fullRestart && rejectHotReload) {
            return OperationResult(
              1,
              _kFailedRecompileMessage,
              updateFSReport: UpdateFSReport(hotReloadRejected: true),
            );
          }
          if (advanceRevisionOnRestart) {
            webMemoryFS.incrementRevision();
          }
          return OperationResult.ok;
        },
      );
      final WidgetPreviewStartCommand startCommand = createStartCommand(fakeResidentRunner);

      // First sync updates _lastGeneratedPreviews (from null to empty), so it reloads once.
      final SyncPreviewsResponse initialSync = await startCommand.syncPreviews();
      expect(initialSync.reloaded, isTrue);
      expect(fakeDtdServices.postedReloadedEvents, <bool>[false]);
      expect(fakeLiveServer.prewarmCount, 1);

      // Subsequent no-op sync with unchanged previews and unchanged WebMemoryFS.revision
      // does not broadcast PreviewReloaded.
      final SyncPreviewsResponse noopSync = await startCommand.syncPreviews();
      expect(noopSync.compileSuccess, isTrue);
      expect(noopSync.reloaded, isFalse);
      expect(fakeDtdServices.postedReloadedEvents, <bool>[false]);
      expect(fakeLiveServer.prewarmCount, 2);

      // No-op handleReload with unchanged WebMemoryFS.revision also skips PreviewReloaded.
      final OperationResult? noopReload = await startCommand.handleReload();
      expect(noopReload?.isOk, isTrue);
      expect(fakeDtdServices.postedReloadedEvents, <bool>[false]);
      expect(fakeLiveServer.prewarmCount, 3);

      // Advancing WebMemoryFS.revision broadcasts PreviewReloaded(fullRestart: false)
      // and prewarms the live DDC bundle.
      advanceRevisionOnRestart = true;
      final SyncPreviewsResponse changedSync = await startCommand.syncPreviews();
      expect(changedSync.compileSuccess, isTrue);
      expect(changedSync.reloaded, isTrue);
      expect(changedSync.fullRestart, isFalse);
      expect(fakeDtdServices.postedReloadedEvents, <bool>[false, false]);
      expect(fakeLiveServer.prewarmCount, 4);

      // Fallback fullRestart broadcasts PreviewReloaded(fullRestart: true) even if
      // revision only advances during fullRestart.
      rejectHotReload = true;
      final SyncPreviewsResponse restartSync = await startCommand.syncPreviews();
      expect(restartSync.compileSuccess, isTrue);
      expect(restartSync.reloaded, isTrue);
      expect(restartSync.fullRestart, isTrue);
      expect(fakeDtdServices.postedReloadedEvents, <bool>[false, false, true]);
      expect(fakeLiveServer.prewarmCount, 5);
    });
  });

  group('$WidgetPreviewSessionClient, $WidgetPreviewListCommand, and $WidgetPreviewSnapshotCommand', () {
    const kDtdWsUri1 = 'ws://127.0.0.1:54321/secret1';
    const kDtdWsUri2 = 'ws://127.0.0.1:54322/secret2';
    const kPreviewServiceUuid = 'widget-preview-111';
    const kScaffoldServiceUuid = 'PreviewScaffold-111';
    const kScaffoldStreamUuid = 'WidgetPreviewScaffold-111';
    const kPreviewId = 'package:my_app/card.dart::cardPreview';
    // Standard 8-byte PNG file signature (\x89PNG\r\n\x1a\n).
    const kFakePngBytes = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    final String kFakePngBase64 = base64.encode(kFakePngBytes);

    late MemoryFileSystem fs;
    late BufferLogger bufferLogger;
    late FakeStdio fakeStdio;
    late Logger machineLogger;
    late Logger humanLogger;
    late Directory projectDir;

    setUp(() {
      fs = MemoryFileSystem.test();
      bufferLogger = BufferLogger.test();
      fakeStdio = FakeStdio();
      machineLogger =
          LoggerFactory(
            outputPreferences: OutputPreferences.test(),
            stdio: fakeStdio,
            terminal: Terminal.test(),
          ).createLogger(
            daemon: false,
            machine: true,
            prefixedErrors: false,
            verbose: false,
            widgetPreviews: false,
            windows: false,
          );
      humanLogger = bufferLogger;
      projectDir = fs.directory(_kProjectRootPath)..createSync(recursive: true);
      fs.currentDirectory = projectDir;
      projectDir.childFile('pubspec.yaml').writeAsStringSync('''
name: my_app
environment:
  sdk: ^3.7.0
''');
    });

    PreviewServiceInfo createServiceInfo({
      String dtdUri = kDtdWsUri1,
      String previewService = kPreviewServiceUuid,
      String projectRoot = _kProjectRootPath,
      bool scaffoldConnected = true,
      String scaffoldService = kScaffoldServiceUuid,
      String scaffoldStream = kScaffoldStreamUuid,
      String? webPreviewUri = 'http://localhost:8080',
    }) {
      return PreviewServiceInfo(
        dtdUri: dtdUri,
        previewService: previewService,
        projectRoot: projectRoot,
        scaffoldConnected: scaffoldConnected,
        scaffoldService: scaffoldService,
        scaffoldStream: scaffoldStream,
        webPreviewUri: webPreviewUri,
      );
    }

    PreviewEntry createSampleEntry({
      String id = kPreviewId,
      String? name = 'Mobile Light',
      bool hasError = false,
      String? errorMessage,
    }) {
      return PreviewEntry(
        brightness: 'light',
        column: 4,
        errorMessage: errorMessage,
        functionName: 'cardPreview',
        group: 'Cards',
        hasError: hasError,
        height: 220.0,
        id: id,
        libraryUri: 'package:my_app/card.dart',
        line: 12,
        name: name,
        packageName: 'my_app',
        scriptUri: 'file:///project/lib/card.dart',
        width: 375.0,
      );
    }

    Future<({FlutterCommandResult? commandResult, int exitCode})> runSubcommand({
      required List<String> args,
      required WidgetPreviewSessionClient client,
      required bool isSnapshot,
      required bool machine,
      FileSystem? fileSystem,
      Logger? loggerOverride,
      Platform? platform,
    }) async {
      final FileSystem activeFs = fileSystem ?? fs;
      final Logger activeLogger = loggerOverride ?? (machine ? machineLogger : humanLogger);
      final toolContext = FakeToolContext(
        artifacts: Artifacts.test(),
        fs: activeFs,
        logger: activeLogger,
        platform: platform ?? FakePlatform(),
        processManager: FakeProcessManager.empty(),
        shutdownHooks: ShutdownHooks(),
        signals: FakeSignals(),
        stdio: fakeStdio,
      );
      final parent = WidgetPreviewCommand(
        buildSystem: TestBuildSystem.all(BuildResult(success: true)),
        buildTargets: const BuildTargetsImpl(),
        toolContext: toolContext,
      );
      expect(parent.subcommands['list'], isA<WidgetPreviewListCommand>());
      expect(parent.subcommands['snapshot'], isA<WidgetPreviewSnapshotCommand>());

      final FlutterCommand subcommand = isSnapshot
          ? WidgetPreviewSnapshotCommand(toolContext: toolContext, sessionClientOverride: client)
          : WidgetPreviewListCommand(toolContext: toolContext, sessionClientOverride: client);
      final runner = TestFlutterCommandRunner(toolContext: toolContext)..addCommand(subcommand);
      var exitCode = 0;
      try {
        await runner.run(<String>[subcommand.name, ...args]);
      } on ProcessExit catch (error) {
        exitCode = error.exitCode;
      }
      final FlutterCommandResult? commandResult = switch (subcommand) {
        WidgetPreviewSnapshotCommand(:final FlutterCommandResult? lastCommandResult) =>
          lastCommandResult,
        WidgetPreviewListCommand(:final FlutterCommandResult? lastCommandResult) =>
          lastCommandResult,
        _ => null,
      };
      return (commandResult: commandResult, exitCode: exitCode);
    }

    testWithoutContext('connects via explicit --dtd-url, matches projectRoot or single-service fallback, and closes DTD', () async {
      final fakeDtd = _FakeCliDartToolingDaemon(
        serviceNames: <String>[kPreviewServiceUuid],
        serviceInfos: <String, PreviewServiceInfo>{
          kPreviewServiceUuid: createServiceInfo(projectRoot: '/other/project'),
        },
        listPreviewsResponse: PreviewListResponse(previews: <PreviewEntry>[createSampleEntry()]),
      );
      final connectedUris = <Uri>[];
      final toolContext = FakeToolContext(
        artifacts: Artifacts.test(),
        fs: fs,
        logger: machineLogger,
        platform: FakePlatform(),
        processManager: FakeProcessManager.empty(),
        shutdownHooks: ShutdownHooks(),
        signals: FakeSignals(),
        stdio: fakeStdio,
      );
      final client = WidgetPreviewSessionClient(
        toolContext: toolContext,
        dtdConnector: (Uri uri) async {
          connectedUris.add(uri);
          return fakeDtd;
        },
      );

      final (:FlutterCommandResult? commandResult, :int exitCode) = await runSubcommand(
        args: <String>['--dtd-url=$kDtdWsUri1', '--machine'],
        client: client,
        isSnapshot: false,
        machine: true,
      );

      expect(commandResult?.exitStatus, ExitStatus.success);
      expect(exitCode, 0);
      expect(connectedUris, <Uri>[Uri.parse(kDtdWsUri1)]);
      expect(fakeDtd.closed, isTrue);
      expect(
        fakeDtd.calls,
        contains(
          equals(<String, Object?>{
            'service': kPreviewServiceUuid,
            'method': WidgetPreviewDtdServices.kListPreviews,
            'params': <String, Object?>{'sync': true},
          }),
        ),
      );
      final decoded = jsonDecode(fakeStdio.writtenToStdout.single.trim()) as Map<String, Object?>;
      final PreviewListResponse parsed = PreviewListResponse.fromJson(decoded);
      expect(parsed.previews, hasLength(1));
      expect(parsed.previews.single.id, kPreviewId);
    });

    testWithoutContext('auto-discovers active DTD via dart tooling-daemon --list and DART_DATA_HOME/dtd matching projectRoot', () async {
      final Directory dtdDataDir = fs.directory('/dart_data/dtd')..createSync(recursive: true);
      dtdDataDir
          .childFile('session_matching.json')
          .writeAsStringSync(
            jsonEncode(<String, Object?>{
              'tooling_daemon_details': <String, Object?>{'uri': kDtdWsUri2},
            }),
          );

      final otherDtd = _FakeCliDartToolingDaemon(
        serviceNames: <String>['widget-preview-other'],
        serviceInfos: <String, PreviewServiceInfo>{
          'widget-preview-other': createServiceInfo(
            previewService: 'widget-preview-other',
            projectRoot: '/unrelated/project',
          ),
        },
      );
      final matchingDtd = _FakeCliDartToolingDaemon(
        serviceNames: <String>[kPreviewServiceUuid],
        serviceInfos: <String, PreviewServiceInfo>{
          kPreviewServiceUuid: createServiceInfo(dtdUri: kDtdWsUri2),
        },
        listPreviewsResponse: PreviewListResponse(previews: <PreviewEntry>[createSampleEntry()]),
      );

      final artifacts = Artifacts.test();
      final String dartBinary = artifacts.getArtifactPath(Artifact.engineDartBinary);
      final processManager = FakeProcessManager.list(<FakeCommand>[
        FakeCommand(
          command: <String>[dartBinary, 'tooling-daemon', '--list'],
          stdout: 'Active DTD: $kDtdWsUri1\n',
        ),
      ]);
      final toolContext = FakeToolContext(
        artifacts: artifacts,
        fs: fs,
        logger: humanLogger,
        platform: FakePlatform(environment: <String, String>{'DART_DATA_HOME': '/dart_data'}),
        processManager: processManager,
        shutdownHooks: ShutdownHooks(),
        signals: FakeSignals(),
        stdio: fakeStdio,
      );
      final client = WidgetPreviewSessionClient(
        toolContext: toolContext,
        dtdConnector: (Uri uri) async {
          return switch (uri.toString()) {
            kDtdWsUri1 => otherDtd,
            kDtdWsUri2 => matchingDtd,
            _ => fail('Unexpected DTD URI: $uri'),
          };
        },
      );

      final (:FlutterCommandResult? commandResult, :int exitCode) = await runSubcommand(
        args: <String>['--no-sync', '--file=lib/card.dart'],
        client: client,
        isSnapshot: false,
        machine: false,
      );

      expect(commandResult?.exitStatus, ExitStatus.success);
      expect(exitCode, 0);
      expect(processManager, hasNoRemainingExpectations);
      expect(otherDtd.closed, isTrue);
      expect(matchingDtd.closed, isTrue);
      expect(
        matchingDtd.calls,
        contains(
          equals(<String, Object?>{
            'service': kPreviewServiceUuid,
            'method': WidgetPreviewDtdServices.kListPreviews,
            'params': <String, Object?>{'sync': false, 'fileUri': 'file:///project/lib/card.dart'},
          }),
        ),
      );
      expect(bufferLogger.statusText, contains('Found 1 widget preview(s):'));
      expect(bufferLogger.statusText, contains(kPreviewId));
      expect(bufferLogger.statusText, contains('"Mobile Light"'));
    });

    testWithoutContext('falls back to one-shot headless widget-preview start --headless --machine and terminates child process in finally', () async {
      final fakeDtd = _FakeCliDartToolingDaemon(
        serviceNames: <String>[kPreviewServiceUuid],
        serviceInfos: <String, PreviewServiceInfo>{kPreviewServiceUuid: createServiceInfo()},
        listPreviewsResponse: const PreviewListResponse(previews: <PreviewEntry>[]),
      );
      final processCompleter = Completer<void>();
      final String startedEventLine = jsonEncode(<Map<String, Object?>>[
        <String, Object?>{
          'event': 'widget_preview.initializing',
          'params': <String, Object?>{'pid': 4321},
        },
        <String, Object?>{
          'event': 'widget_preview.started',
          'params': <String, Object?>{
            'url': 'http://localhost:54321',
            'dtdUri': kDtdWsUri1,
            'previewService': kPreviewServiceUuid,
            'scaffoldService': kScaffoldServiceUuid,
            'projectRoot': _kProjectRootPath,
          },
        },
      ]);
      final fakeHeadlessProcess = FakeProcess(
        completer: processCompleter,
        stdout: utf8.encode('$startedEventLine\n'),
      );
      final artifacts = Artifacts.test();
      final String dartBinary = artifacts.getArtifactPath(Artifact.engineDartBinary);
      final cache = FakeCache(fileSystem: fs, flutterRoot: '/flutter');
      final processManager = FakeProcessManager.list(<FakeCommand>[
        FakeCommand(command: <String>[dartBinary, 'tooling-daemon', '--list'], exitCode: 1),
        FakeCommand(
          command: const <String>[
            '/flutter/bin/flutter',
            'widget-preview',
            'start',
            '--headless',
            '--machine',
          ],
          workingDirectory: _kProjectRootPath,
          process: fakeHeadlessProcess,
        ),
      ]);
      final shutdownHooks = ShutdownHooks();
      final toolContext = FakeToolContext(
        artifacts: artifacts,
        cache: cache,
        fs: fs,
        logger: humanLogger,
        platform: FakePlatform(),
        processManager: processManager,
        shutdownHooks: shutdownHooks,
        signals: FakeSignals(),
        stdio: fakeStdio,
      );
      final client = WidgetPreviewSessionClient(
        toolContext: toolContext,
        dtdConnector: (Uri uri) async {
          expect(uri.toString(), kDtdWsUri1);
          return fakeDtd;
        },
      );

      final (:FlutterCommandResult? commandResult, :int exitCode) = await runSubcommand(
        args: const <String>['--no-image', kPreviewId],
        client: client,
        isSnapshot: true,
        machine: false,
      );

      expect(commandResult?.exitStatus, ExitStatus.success);
      expect(exitCode, 0);
      expect(processManager, hasNoRemainingExpectations);
      expect(fakeHeadlessProcess.signals, <io.ProcessSignal>[io.ProcessSignal.sigterm]);
      expect(processCompleter.isCompleted, isTrue);
      expect(fakeDtd.closed, isTrue);
      expect(bufferLogger.statusText, contains('Captured preview default'));

      // Running shutdown hooks afterwards must be idempotent and not re-signal
      // an already terminated process.
      await shutdownHooks.runShutdownHooks(bufferLogger);
      expect(fakeHeadlessProcess.signals, <io.ProcessSignal>[io.ProcessSignal.sigterm]);
    });

    testWithoutContext('list skips ephemeral session when no active DTD exists', () async {
      final artifacts = Artifacts.test();
      final String dartBinary = artifacts.getArtifactPath(Artifact.engineDartBinary);
      final processManager = FakeProcessManager.list(<FakeCommand>[
        FakeCommand(command: <String>[dartBinary, 'tooling-daemon', '--list'], exitCode: 1),
      ]);
      final toolContext = FakeToolContext(
        artifacts: artifacts,
        cache: FakeCache(fileSystem: fs, flutterRoot: '/flutter'),
        fs: fs,
        logger: humanLogger,
        platform: FakePlatform(),
        processManager: processManager,
        shutdownHooks: ShutdownHooks(),
        signals: FakeSignals(),
        stdio: fakeStdio,
      );
      var detectCalled = false;
      final client = WidgetPreviewSessionClient(
        toolContext: toolContext,
        detectPreviewsOverride: (FlutterProject project, {String? fileUri}) async {
          detectCalled = true;
          return const PreviewListResponse(previews: <PreviewEntry>[]);
        },
      );

      final (:FlutterCommandResult? commandResult, :int exitCode) = await runSubcommand(
        args: const <String>['--machine'],
        client: client,
        isSnapshot: false,
        machine: true,
      );

      expect(commandResult?.exitStatus, ExitStatus.success);
      expect(exitCode, 0);
      expect(detectCalled, isTrue);
      expect(processManager, hasNoRemainingExpectations);
      expect(jsonDecode(fakeStdio.writtenToStdout.single), <String, Object?>{
        'type': 'PreviewListResponse',
        'previews': <Object?>[],
      });
    });

    testWithoutContext(
      'reports captured error details when ephemeral headless child exits prematurely',
      () async {
        final String errorEventLine = jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'event': 'widget_preview.logMessage',
            'params': <String, Object?>{
              'level': 'error',
              'message': 'Failed to locate Chrome binary.',
            },
          },
        ]);
        final fakeHeadlessProcess = FakeProcess(
          exitCode: 1,
          stdout: utf8.encode('$errorEventLine\n'),
          stderr: utf8.encode('Fatal browser launch error.\n'),
        );
        final artifacts = Artifacts.test();
        final String dartBinary = artifacts.getArtifactPath(Artifact.engineDartBinary);
        final cache = FakeCache(fileSystem: fs, flutterRoot: '/flutter');
        final processManager = FakeProcessManager.list(<FakeCommand>[
          FakeCommand(command: <String>[dartBinary, 'tooling-daemon', '--list'], exitCode: 1),
          FakeCommand(
            command: const <String>[
              '/flutter/bin/flutter',
              'widget-preview',
              'start',
              '--headless',
              '--machine',
            ],
            workingDirectory: _kProjectRootPath,
            process: fakeHeadlessProcess,
          ),
        ]);
        final toolContext = FakeToolContext(
          artifacts: artifacts,
          cache: cache,
          fs: fs,
          logger: machineLogger,
          platform: FakePlatform(),
          processManager: processManager,
          shutdownHooks: ShutdownHooks(),
          signals: FakeSignals(),
          stdio: fakeStdio,
        );
        final client = WidgetPreviewSessionClient(
          toolContext: toolContext,
          dtdConnector: (Uri uri) => fail('Should not connect to DTD: $uri'),
        );

        final (:FlutterCommandResult? commandResult, :int exitCode) = await runSubcommand(
          args: const <String>['--no-image', kPreviewId, '--machine'],
          client: client,
          isSnapshot: true,
          machine: true,
        );

        expect(commandResult?.exitStatus, ExitStatus.fail);
        expect(exitCode, 1);
        expect(processManager, hasNoRemainingExpectations);
        final errorJson =
            jsonDecode(fakeStdio.writtenToStdout.single.trim()) as Map<String, Object?>;
        expect(
          errorJson['error'],
          allOf(
            contains('Headless widget preview exited prematurely with code 1.'),
            contains('Failed to locate Chrome binary.'),
            contains('Fatal browser launch error.'),
          ),
        );
      },
    );

    testWithoutContext('snapshot syncs previews, captures snapshot with overrides, forces includeImage when --output and --no-image are combined, and omits imageBase64 from stdout JSON', () async {
      final fakeDtd = _FakeCliDartToolingDaemon(
        serviceNames: <String>[kPreviewServiceUuid],
        serviceInfos: <String, PreviewServiceInfo>{kPreviewServiceUuid: createServiceInfo()},
        captureResponse: CapturePreviewResponse(
          diagnostics: const <PreviewDiagnostic>[],
          hasErrors: false,
          imageBase64: kFakePngBase64,
          name: 'Mobile Dark',
          pixelRatio: 2.0,
          previewId: kPreviewId,
          renderedHeight: 640.0,
          renderedWidth: 360.0,
        ),
      );
      final toolContext = FakeToolContext(
        artifacts: Artifacts.test(),
        fs: fs,
        logger: machineLogger,
        platform: FakePlatform(),
        processManager: FakeProcessManager.empty(),
        shutdownHooks: ShutdownHooks(),
        signals: FakeSignals(),
        stdio: fakeStdio,
      );
      final client = WidgetPreviewSessionClient(
        toolContext: toolContext,
        dtdConnector: (Uri _) async => fakeDtd,
      );

      const outputPath = '/project/snapshots/card.png';
      final (:FlutterCommandResult? commandResult, :int exitCode) = await runSubcommand(
        args: <String>[
          kPreviewId,
          '--dtd-url=$kDtdWsUri1',
          '--width=360',
          '--height=640',
          '--brightness=dark',
          '--pixel-ratio=2.0',
          '--pump-ms=250',
          '--text-scale-factor=1.25',
          '--no-image',
          '--output=$outputPath',
          '--machine',
        ],
        client: client,
        isSnapshot: true,
        machine: true,
      );

      expect(commandResult?.exitStatus, ExitStatus.success);
      expect(exitCode, 0);
      // Verify syncPreviews ran before capturePreview, and includeImage was forced to true
      // on the RPC so --output could be written to disk despite --no-image.
      expect(
        fakeDtd.calls,
        equals(<Map<String, Object?>>[
          <String, Object?>{
            'service': kPreviewServiceUuid,
            'method': WidgetPreviewDtdServices.kGetServiceInfo,
            'params': null,
          },
          <String, Object?>{
            'service': kPreviewServiceUuid,
            'method': WidgetPreviewDtdServices.kSyncPreviews,
            'params': null,
          },
          <String, Object?>{
            'service': kScaffoldServiceUuid,
            'method': WidgetPreviewDtdServices.kCapturePreview,
            'params': <String, Object?>{
              'previewId': kPreviewId,
              'includeImage': true,
              'width': 360.0,
              'height': 640.0,
              'pixelRatio': 2.0,
              'pumpMs': 250,
              'brightness': 'dark',
              'textScaleFactor': 1.25,
            },
          },
        ]),
      );

      final File savedFile = fs.file(outputPath);
      expect(savedFile, exists);
      expect(savedFile.readAsBytesSync(), equals(kFakePngBytes));

      // Verify stdout is raw CapturePreviewResponse JSON (not wrapped in WidgetPreviewMachineAwareLogger
      // event array) and imageBase64 is omitted (null) because --no-image was passed.
      final String stdoutText = fakeStdio.writtenToStdout.single.trim();
      expect(stdoutText.startsWith('{'), isTrue);
      final decoded = jsonDecode(stdoutText) as Map<String, Object?>;
      final CapturePreviewResponse parsed = CapturePreviewResponse.fromJson(decoded);
      expect(parsed.previewId, kPreviewId);
      expect(parsed.imageBase64, isNull);
      expect(parsed.hasErrors, isFalse);
    });

    testWithoutContext('snapshot returns failed FlutterCommandResult and non-zero exit code when hasErrors is true while still writing --output PNG and full diagnostics', () async {
      const overflowDiag = PreviewDiagnostic(
        kind: .overflow,
        overflowAxis: 'horizontal',
        overflowPixels: 48.0,
        overflowSide: 'right',
        phase: .paint,
        summary: 'A RenderFlex overflowed by 48 pixels on the right.',
        targetType: 'RenderFlex',
      );
      final fakeDtd = _FakeCliDartToolingDaemon(
        serviceNames: <String>[kPreviewServiceUuid],
        serviceInfos: <String, PreviewServiceInfo>{kPreviewServiceUuid: createServiceInfo()},
        captureResponse: CapturePreviewResponse(
          diagnostics: const <PreviewDiagnostic>[overflowDiag],
          hasErrors: true,
          imageBase64: kFakePngBase64,
          name: 'Overflowing Card',
          pixelRatio: 1.0,
          previewId: kPreviewId,
          renderedHeight: 220.0,
          renderedWidth: 375.0,
        ),
      );
      final toolContext = FakeToolContext(
        artifacts: Artifacts.test(),
        fs: fs,
        logger: machineLogger,
        platform: FakePlatform(),
        processManager: FakeProcessManager.empty(),
        shutdownHooks: ShutdownHooks(),
        signals: FakeSignals(),
        stdio: fakeStdio,
      );
      final client = WidgetPreviewSessionClient(
        toolContext: toolContext,
        dtdConnector: (Uri _) async => fakeDtd,
      );

      const outputPath = '/project/snapshots/overflow.png';
      final (:FlutterCommandResult? commandResult, :int exitCode) = await runSubcommand(
        args: <String>[
          kPreviewId,
          '--dtd-url=$kDtdWsUri1',
          '--no-sync',
          '--output=$outputPath',
          '--machine',
        ],
        client: client,
        isSnapshot: true,
        machine: true,
      );

      expect(commandResult?.exitStatus, ExitStatus.fail);
      expect(exitCode, 1);
      expect(fs.file(outputPath), exists);
      expect(fs.file(outputPath).readAsBytesSync(), equals(kFakePngBytes));

      final decoded = jsonDecode(fakeStdio.writtenToStdout.single.trim()) as Map<String, Object?>;
      final CapturePreviewResponse parsed = CapturePreviewResponse.fromJson(decoded);
      expect(parsed.hasErrors, isTrue);
      expect(parsed.imageBase64, kFakePngBase64);
      expect(parsed.diagnostics, equals(const <PreviewDiagnostic>[overflowDiag]));
    });

    testWithoutContext(
      'snapshot --no-sync waits for Connected event when scaffoldConnected is initially false',
      () async {
        final fakeDtd = _FakeCliDartToolingDaemon(
          serviceNames: <String>[kPreviewServiceUuid],
          serviceInfos: <String, PreviewServiceInfo>{
            kPreviewServiceUuid: createServiceInfo(scaffoldConnected: false),
          },
          captureResponse: const CapturePreviewResponse(
            diagnostics: <PreviewDiagnostic>[],
            hasErrors: false,
            name: 'Mobile Light',
            pixelRatio: 1.0,
            previewId: kPreviewId,
            renderedHeight: 220.0,
            renderedWidth: 375.0,
          ),
        );
        fakeDtd.onStreamSubscribed = (String streamId) {
          if (streamId == kScaffoldStreamUuid) {
            scheduleMicrotask(() {
              fakeDtd.emitEvent(
                kScaffoldStreamUuid,
                WidgetPreviewDtdServices.kWidgetPreviewConnectedEvent,
              );
            });
          }
        };
        final toolContext = FakeToolContext(
          artifacts: Artifacts.test(),
          fs: fs,
          logger: humanLogger,
          platform: FakePlatform(),
          processManager: FakeProcessManager.empty(),
          shutdownHooks: ShutdownHooks(),
          signals: FakeSignals(),
          stdio: fakeStdio,
        );
        final client = WidgetPreviewSessionClient(
          toolContext: toolContext,
          dtdConnector: (Uri _) async => fakeDtd,
        );

        final (:FlutterCommandResult? commandResult, :int exitCode) = await runSubcommand(
          args: <String>[kPreviewId, '--dtd-url=$kDtdWsUri1', '--no-sync', '--no-image'],
          client: client,
          isSnapshot: true,
          machine: false,
        );

        expect(commandResult?.exitStatus, ExitStatus.success);
        expect(exitCode, 0);
        expect(bufferLogger.statusText, contains('Captured preview $kPreviewId'));
      },
    );

    testWithoutContext('formats RpcException, compile failure, and validation errors as structured JSON in --machine mode and throws ToolExit in human mode', () async {
      final fakeDtd = _FakeCliDartToolingDaemon(
        serviceNames: <String>[kPreviewServiceUuid],
        serviceInfos: <String, PreviewServiceInfo>{kPreviewServiceUuid: createServiceInfo()},
        captureError: RpcException(
          WidgetPreviewDtdServices.kPreviewNotFoundErrorCode,
          'Preview "missingPreview" not found.',
        ),
      );
      final toolContext = FakeToolContext(
        artifacts: Artifacts.test(),
        fs: fs,
        logger: machineLogger,
        platform: FakePlatform(),
        processManager: FakeProcessManager.empty(),
        shutdownHooks: ShutdownHooks(),
        signals: FakeSignals(),
        stdio: fakeStdio,
      );
      final client = WidgetPreviewSessionClient(
        toolContext: toolContext,
        dtdConnector: (Uri _) async => fakeDtd,
      );

      // 1. RpcException (preview not found) in --machine mode.
      final (
        commandResult: FlutterCommandResult? rpcCommandResult,
        exitCode: int rpcExitCode,
      ) = await runSubcommand(
        args: <String>['missingPreview', '--dtd-url=$kDtdWsUri1', '--machine'],
        client: client,
        isSnapshot: true,
        machine: true,
      );
      expect(rpcCommandResult?.exitStatus, ExitStatus.fail);
      expect(rpcExitCode, 1);
      final rpcErrorJson =
          jsonDecode(fakeStdio.writtenToStdout.single.trim()) as Map<String, Object?>;
      expect(rpcErrorJson['error'], 'Preview "missingPreview" not found.');
      expect(rpcErrorJson['code'], WidgetPreviewDtdServices.kPreviewNotFoundErrorCode);
      expect(rpcErrorJson['previewId'], 'missingPreview');
      expect(fakeStdio.writtenToStderr, isEmpty);

      // 2. Invalid --brightness option in --machine mode.
      fakeStdio.stdout.writes.clear();
      final (
        commandResult: FlutterCommandResult? brightnessCommandResult,
        exitCode: int brightnessExitCode,
      ) = await runSubcommand(
        args: <String>[kPreviewId, '--brightness=sepia', '--machine'],
        client: client,
        isSnapshot: true,
        machine: true,
      );
      expect(brightnessCommandResult?.exitStatus, ExitStatus.fail);
      expect(brightnessExitCode, 1);
      final brightnessErrorJson =
          jsonDecode(fakeStdio.writtenToStdout.single.trim()) as Map<String, Object?>;
      expect(brightnessErrorJson['error'], contains('Invalid value for "--brightness"'));
      expect(brightnessErrorJson['previewId'], kPreviewId);

      // 3. Compile failure during syncPreviews in --machine mode vs human mode.
      fakeStdio.stdout.writes.clear();
      fakeDtd
        ..captureError = null
        ..syncResponse = const SyncPreviewsResponse(
          compileError: _kFailedRecompileMessage,
          compileSuccess: false,
          errorPreviewCount: 1,
          fullRestart: false,
          reloaded: false,
        );
      final (
        commandResult: FlutterCommandResult? compileCommandResult,
        exitCode: int compileExitCode,
      ) = await runSubcommand(
        args: <String>[kPreviewId, '--dtd-url=$kDtdWsUri1', '--machine'],
        client: client,
        isSnapshot: true,
        machine: true,
      );
      expect(compileCommandResult?.exitStatus, ExitStatus.fail);
      expect(compileExitCode, 1);
      final compileErrorJson =
          jsonDecode(fakeStdio.writtenToStdout.single.trim()) as Map<String, Object?>;
      expect(compileErrorJson['error'], _kFailedRecompileMessage);
      expect(compileErrorJson['previewId'], kPreviewId);

      await expectLater(
        runSubcommand(
          args: <String>[kPreviewId, '--dtd-url=$kDtdWsUri1'],
          client: client,
          isSnapshot: true,
          machine: false,
        ),
        throwsToolExit(message: _kFailedRecompileMessage),
      );
    });

    testWithoutContext('times out ephemeral headless startup, signals initializing VM pid, and escalates to sigkill on hung process exit', () async {
      final String initOnlyLine = jsonEncode(<Map<String, Object?>>[
        <String, Object?>{
          'event': 'widget_preview.initializing',
          'params': <String, Object?>{'pid': 4321},
        },
      ]);
      final hungProcess = _StubbornExitProcess(
        exitCompleter: Completer<void>(),
        stdoutBytes: utf8.encode('$initOnlyLine\n'),
      );
      final artifacts = Artifacts.test();
      final String dartBinary = artifacts.getArtifactPath(Artifact.engineDartBinary);
      final cache = FakeCache(fileSystem: fs, flutterRoot: '/flutter');
      final killedPids = <int>[];
      final processManager = _PidTrackingFakeProcessManager(
        commands: <FakeCommand>[
          FakeCommand(command: <String>[dartBinary, 'tooling-daemon', '--list'], exitCode: 1),
          FakeCommand(
            command: const <String>[
              '/flutter/bin/flutter',
              'widget-preview',
              'start',
              '--headless',
              '--machine',
            ],
            workingDirectory: _kProjectRootPath,
            process: hungProcess,
          ),
        ],
        onKillPid: (int pid, io.ProcessSignal signal) {
          killedPids.add(pid);
          return false;
        },
      );
      final toolContext = FakeToolContext(
        artifacts: artifacts,
        cache: cache,
        fs: fs,
        logger: machineLogger,
        platform: FakePlatform(),
        processManager: processManager,
        shutdownHooks: ShutdownHooks(),
        signals: FakeSignals(),
        stdio: fakeStdio,
      );
      final client = WidgetPreviewSessionClient(
        toolContext: toolContext,
        dtdConnector: (Uri uri) => fail('Should not connect to DTD: $uri'),
        headlessStartupTimeout: const Duration(milliseconds: 20),
        processExitTimeout: const Duration(milliseconds: 15),
      );

      final (:FlutterCommandResult? commandResult, :int exitCode) = await runSubcommand(
        args: const <String>['--no-image', kPreviewId, '--machine'],
        client: client,
        isSnapshot: true,
        machine: true,
      );

      expect(commandResult?.exitStatus, ExitStatus.fail);
      expect(exitCode, 1);
      expect(processManager.base, hasNoRemainingExpectations);
      // Verify both the wrapper pid (1234) and initializing VM pid (4321) were targeted,
      // and sigterm escalated to sigkill when exitCode did not complete within processExitTimeout.
      expect(killedPids, containsAll(<int>[1234, 4321]));
      expect(
        hungProcess.signals,
        equals(<io.ProcessSignal>[io.ProcessSignal.sigterm, io.ProcessSignal.sigkill]),
      );
      expect(hungProcess.exited, isTrue);
      final errorJson = jsonDecode(fakeStdio.writtenToStdout.single.trim()) as Map<String, Object?>;
      expect(
        errorJson['error'],
        contains('Timed out waiting for headless widget preview to start'),
      );
    });

    testWithoutContext('snapshot --no-sync fails promptly when session.dtd.done completes early or scaffoldReadyTimeout expires', () async {
      // 1. Early DTD disconnect before Connected event arrives.
      final disconnectingDtd = _FakeCliDartToolingDaemon(
        serviceNames: <String>[kPreviewServiceUuid],
        serviceInfos: <String, PreviewServiceInfo>{
          kPreviewServiceUuid: createServiceInfo(scaffoldConnected: false),
        },
      );
      disconnectingDtd.onStreamSubscribed = (String streamId) {
        if (streamId == kScaffoldStreamUuid) {
          scheduleMicrotask(disconnectingDtd.simulateUnexpectedDisconnect);
        }
      };
      final toolContext = FakeToolContext(
        artifacts: Artifacts.test(),
        fs: fs,
        logger: humanLogger,
        platform: FakePlatform(),
        processManager: FakeProcessManager.empty(),
        shutdownHooks: ShutdownHooks(),
        signals: FakeSignals(),
        stdio: fakeStdio,
      );
      final disconnectClient = WidgetPreviewSessionClient(
        toolContext: toolContext,
        dtdConnector: (Uri _) async => disconnectingDtd,
      );
      await expectLater(
        runSubcommand(
          args: <String>[kPreviewId, '--dtd-url=$kDtdWsUri1', '--no-sync', '--no-image'],
          client: disconnectClient,
          isSnapshot: true,
          machine: false,
        ),
        throwsToolExit(
          message: 'Connection to DTD closed before the widget preview scaffold became ready.',
        ),
      );

      // 2. Bounded timeout when scaffold never connects and DTD stays open.
      final silentScaffoldDtd = _FakeCliDartToolingDaemon(
        serviceNames: <String>[kPreviewServiceUuid],
        serviceInfos: <String, PreviewServiceInfo>{
          kPreviewServiceUuid: createServiceInfo(scaffoldConnected: false),
        },
      );
      final timeoutClient = WidgetPreviewSessionClient(
        toolContext: toolContext,
        dtdConnector: (Uri _) async => silentScaffoldDtd,
        scaffoldReadyTimeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        runSubcommand(
          args: <String>[kPreviewId, '--dtd-url=$kDtdWsUri1', '--no-sync', '--no-image'],
          client: timeoutClient,
          isSnapshot: true,
          machine: false,
        ),
        throwsToolExit(message: 'Timed out waiting for the widget preview scaffold to connect'),
      );
    });

    testWithoutContext('restricts WidgetPreviewMachineAwareLogger to start and keeps list/snapshot --machine stdout clean under warnings, progress, and -v', () async {
      expect(
        findCommandAndSubcommandName(<String>[
          '-v',
          'widget-preview',
          'start',
          '--headless',
          '--machine',
        ]),
        equals((commandName: 'widget-preview', subcommandName: 'start')),
      );
      expect(
        findCommandAndSubcommandName(<String>['-v', 'widget-preview', 'list', '--machine']),
        equals((commandName: 'widget-preview', subcommandName: 'list')),
      );
      expect(
        findCommandAndSubcommandName(<String>[
          'widget-preview',
          '-v',
          'snapshot',
          kPreviewId,
          '--machine',
        ]),
        equals((commandName: 'widget-preview', subcommandName: 'snapshot')),
      );
      expect(
        findCommandAndSubcommandName(<String>['widget-preview', 'clean']),
        equals((commandName: 'widget-preview', subcommandName: 'clean')),
      );

      final factory = LoggerFactory(
        outputPreferences: OutputPreferences.test(),
        stdio: fakeStdio,
        terminal: Terminal.test(),
      );
      final Logger startMachineLogger = factory.createLogger(
        daemon: false,
        machine: true,
        prefixedErrors: false,
        verbose: true,
        widgetPreviews: true,
        windows: false,
      );
      expect(startMachineLogger, isA<WidgetPreviewMachineAwareLogger>());

      // For list/snapshot --machine (even with -v), executable.dart sets
      // widgetPreviews: false and mutes verbose stdout logging.
      final Logger cliMachineLogger = factory.createLogger(
        daemon: false,
        machine: true,
        prefixedErrors: false,
        verbose: false,
        widgetPreviews: false,
        windows: false,
      );
      expect(cliMachineLogger, isA<MachineOutputLogger>());
      expect(cliMachineLogger, isNot(isA<WidgetPreviewMachineAwareLogger>()));

      // Simulate cache.lock() progress, warnings, and trace logs before and during list --machine.
      final Status lockProgress = cliMachineLogger.startProgress(
        'Waiting for another flutter command to release the startup lock...',
      );
      lockProgress.stop();
      cliMachineLogger.printWarning('Non-fatal pub warning');
      cliMachineLogger.printTrace('Verbose trace message');

      final fakeDtd = _FakeCliDartToolingDaemon(
        serviceNames: <String>[kPreviewServiceUuid],
        serviceInfos: <String, PreviewServiceInfo>{kPreviewServiceUuid: createServiceInfo()},
        listPreviewsResponse: PreviewListResponse(previews: <PreviewEntry>[createSampleEntry()]),
      );
      final toolContext = FakeToolContext(
        artifacts: Artifacts.test(),
        fs: fs,
        logger: cliMachineLogger,
        platform: FakePlatform(),
        processManager: FakeProcessManager.empty(),
        shutdownHooks: ShutdownHooks(),
        signals: FakeSignals(),
        stdio: fakeStdio,
      );
      final client = WidgetPreviewSessionClient(
        toolContext: toolContext,
        dtdConnector: (Uri _) async => fakeDtd,
      );

      final (:FlutterCommandResult? commandResult, :int exitCode) = await runSubcommand(
        args: <String>['--dtd-url=$kDtdWsUri1', '--machine'],
        client: client,
        isSnapshot: false,
        loggerOverride: cliMachineLogger,
        machine: true,
      );

      expect(commandResult?.exitStatus, ExitStatus.success);
      expect(exitCode, 0);
      // Stdout must contain strictly the single PreviewListResponse JSON object,
      // with zero widget_preview.logMessage event arrays, progress text, or warnings.
      final String fullStdout = fakeStdio.writtenToStdout.join();
      expect(fullStdout, isNot(contains('widget_preview.logMessage')));
      expect(fullStdout, isNot(contains('startup lock')));
      final decoded = jsonDecode(fullStdout.trim()) as Map<String, Object?>;
      expect(PreviewListResponse.fromJson(decoded).previews.single.id, kPreviewId);
      expect(fakeStdio.writtenToStderr.join(), contains('Non-fatal pub warning'));
    });

    testWithoutContext('converts closed-peer StateError to ToolExit, swallows dtd.close errors, and never swallows TestFailure or non-peer Errors', () async {
      // 1. Closed JSON-RPC peer StateError + WebSocket close exception in finally.
      final closingPeerDtd = _FakeCliDartToolingDaemon(
        serviceNames: <String>[kPreviewServiceUuid],
        serviceInfos: <String, PreviewServiceInfo>{kPreviewServiceUuid: createServiceInfo()},
        callStateError: StateError(
          'The client closed with pending request "$kPreviewServiceUuid.listPreviews".',
        ),
        closeError: const FormatException('WebSocket closed abnormally'),
      );
      final toolContext = FakeToolContext(
        artifacts: Artifacts.test(),
        fs: fs,
        logger: machineLogger,
        platform: FakePlatform(),
        processManager: FakeProcessManager.empty(),
        shutdownHooks: ShutdownHooks(),
        signals: FakeSignals(),
        stdio: fakeStdio,
      );
      final closingClient = WidgetPreviewSessionClient(
        toolContext: toolContext,
        dtdConnector: (Uri _) async => closingPeerDtd,
      );

      final (:FlutterCommandResult? commandResult, :int exitCode) = await runSubcommand(
        args: <String>['--dtd-url=$kDtdWsUri1', '--machine'],
        client: closingClient,
        isSnapshot: false,
        machine: true,
      );
      expect(commandResult?.exitStatus, ExitStatus.fail);
      expect(exitCode, 1);
      expect(closingPeerDtd.closed, isTrue);
      final errorJson = jsonDecode(fakeStdio.writtenToStdout.single.trim()) as Map<String, Object?>;
      expect(errorJson['error'], contains('DTD connection closed while invoking'));

      // 2. TestFailure / non-peer Error thrown in dtdConnector during auto-discovery or
      // explicit --dtd-url MUST NOT be swallowed as a connection failure.
      final artifacts = Artifacts.test();
      final String dartBinary = artifacts.getArtifactPath(Artifact.engineDartBinary);
      final discoveryToolContext = FakeToolContext(
        artifacts: artifacts,
        fs: fs,
        logger: humanLogger,
        platform: FakePlatform(),
        processManager: FakeProcessManager.list(<FakeCommand>[
          FakeCommand(
            command: <String>[dartBinary, 'tooling-daemon', '--list'],
            stdout: 'Active DTD: $kDtdWsUri1\n',
          ),
        ]),
        shutdownHooks: ShutdownHooks(),
        signals: FakeSignals(),
        stdio: fakeStdio,
      );
      final failingConnectorClient = WidgetPreviewSessionClient(
        toolContext: discoveryToolContext,
        dtdConnector: (Uri uri) => fail('Unexpected DTD URI: $uri'),
      );

      await expectLater(
        runSubcommand(
          args: const <String>['--no-image', kPreviewId],
          client: failingConnectorClient,
          isSnapshot: true,
          machine: false,
        ),
        throwsA(isA<TestFailure>()),
      );

      final nonPeerStateErrorDtd = _FakeCliDartToolingDaemon(
        serviceNames: <String>[kPreviewServiceUuid],
        serviceInfos: <String, PreviewServiceInfo>{kPreviewServiceUuid: createServiceInfo()},
        callStateError: StateError('Bad state: No element'),
      );
      final nonPeerErrorClient = WidgetPreviewSessionClient(
        toolContext: toolContext,
        dtdConnector: (Uri _) async => nonPeerStateErrorDtd,
      );
      await expectLater(
        runSubcommand(
          args: <String>['--dtd-url=$kDtdWsUri1', '--no-image', kPreviewId],
          client: nonPeerErrorClient,
          isSnapshot: true,
          machine: false,
        ),
        throwsStateError,
      );
    });

    testWithoutContext('resolves relative --file against fs.currentDirectory inside pub workspace member and falls back to positional projectDir', () async {
      final Directory workspaceDir = fs.directory('/workspace')..createSync(recursive: true);
      workspaceDir.childFile('pubspec.yaml').writeAsStringSync('''
name: my_workspace
environment:
  sdk: ^3.7.0
workspace:
  - packages/card_pkg
''');
      final Directory memberDir = workspaceDir.childDirectory('packages').childDirectory('card_pkg')
        ..createSync(recursive: true);
      memberDir.childFile('pubspec.yaml').writeAsStringSync('''
name: card_pkg
resolution: workspace
environment:
  sdk: ^3.7.0
''');
      memberDir.childDirectory('lib').childFile('card.dart').createSync(recursive: true);

      final fakeDtd = _FakeCliDartToolingDaemon(
        serviceNames: <String>[kPreviewServiceUuid],
        serviceInfos: <String, PreviewServiceInfo>{
          kPreviewServiceUuid: createServiceInfo(projectRoot: '/workspace'),
        },
        listPreviewsResponse: PreviewListResponse(previews: <PreviewEntry>[createSampleEntry()]),
      );

      // 1. Invoked from inside workspace member directory without positional dir.
      fs.currentDirectory = memberDir;
      final memberToolContext = FakeToolContext(
        artifacts: Artifacts.test(),
        fs: fs,
        logger: humanLogger,
        platform: FakePlatform(),
        processManager: FakeProcessManager.empty(),
        shutdownHooks: ShutdownHooks(),
        signals: FakeSignals(),
        stdio: fakeStdio,
      );
      final memberClient = WidgetPreviewSessionClient(
        toolContext: memberToolContext,
        dtdConnector: (Uri _) async => fakeDtd,
      );
      final (
        commandResult: FlutterCommandResult? memberResult,
        exitCode: int memberExitCode,
      ) = await runSubcommand(
        args: <String>['--dtd-url=$kDtdWsUri1', '--no-sync', '--file=lib/card.dart'],
        client: memberClient,
        isSnapshot: false,
        machine: false,
      );
      expect(memberResult?.exitStatus, ExitStatus.success);
      expect(memberExitCode, 0);
      expect(
        fakeDtd.calls.last,
        equals(<String, Object?>{
          'service': kPreviewServiceUuid,
          'method': WidgetPreviewDtdServices.kListPreviews,
          'params': <String, Object?>{
            'sync': false,
            'fileUri': 'file:///workspace/packages/card_pkg/lib/card.dart',
          },
        }),
      );

      // 2. Invoked from an external directory with positional member directory argument.
      fakeDtd.calls.clear();
      final Directory outsideDir = fs.directory('/outside')..createSync(recursive: true);
      fs.currentDirectory = outsideDir;
      final (
        commandResult: FlutterCommandResult? positionalResult,
        exitCode: int positionalExitCode,
      ) = await runSubcommand(
        args: <String>[
          '--dtd-url=$kDtdWsUri1',
          '--no-sync',
          '--file=lib/card.dart',
          memberDir.path,
        ],
        client: memberClient,
        isSnapshot: false,
        machine: false,
      );
      expect(positionalResult?.exitStatus, ExitStatus.success);
      expect(positionalExitCode, 0);
      expect(
        fakeDtd.calls.last,
        equals(<String, Object?>{
          'service': kPreviewServiceUuid,
          'method': WidgetPreviewDtdServices.kListPreviews,
          'params': <String, Object?>{
            'sync': false,
            'fileUri': 'file:///workspace/packages/card_pkg/lib/card.dart',
          },
        }),
      );
    });

    testWithoutContext('supports Windows LOCALAPPDATA DTD discovery, Windows --file URI normalization, and flutter.bat / taskkill teardown', () async {
      const windowsProjectRoot = r'C:\src\my_app';
      const windowsLocalAppData = r'C:\Users\dev\AppData\Local';
      const windowsFlutterRoot = r'C:\flutter';
      final windowsFs = MemoryFileSystem.test(style: FileSystemStyle.windows);
      final Directory winProjectDir = windowsFs.directory(windowsProjectRoot)
        ..createSync(recursive: true);
      windowsFs.currentDirectory = winProjectDir;
      winProjectDir.childFile('pubspec.yaml').writeAsStringSync('''
name: my_app
environment:
  sdk: ^3.7.0
''');
      winProjectDir.childDirectory('lib').childFile('card.dart').createSync(recursive: true);

      final windowsPlatform = FakePlatform(
        operatingSystem: 'windows',
        environment: <String, String>{'LOCALAPPDATA': windowsLocalAppData},
      );

      // 1. LOCALAPPDATA\Dart\dtd discovery + Windows backslash --file normalization.
      final File dtdMetaFile = windowsFs.file(r'C:\Users\dev\AppData\Local\Dart\dtd\daemon.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode(<String, Object?>{'uri': kDtdWsUri1}));
      final discoveryDtd = _FakeCliDartToolingDaemon(
        serviceNames: <String>[kPreviewServiceUuid],
        serviceInfos: <String, PreviewServiceInfo>{
          kPreviewServiceUuid: createServiceInfo(projectRoot: windowsProjectRoot),
        },
        listPreviewsResponse: PreviewListResponse(previews: <PreviewEntry>[createSampleEntry()]),
      );
      final artifacts = Artifacts.test();
      final String dartBinary = artifacts.getArtifactPath(Artifact.engineDartBinary);
      final discoveryProcessManager = FakeProcessManager.list(<FakeCommand>[
        FakeCommand(command: <String>[dartBinary, 'tooling-daemon', '--list'], exitCode: 1),
      ]);
      final discoveryContext = FakeToolContext(
        artifacts: artifacts,
        cache: FakeCache(fileSystem: windowsFs, flutterRoot: windowsFlutterRoot),
        fs: windowsFs,
        logger: humanLogger,
        platform: windowsPlatform,
        processManager: discoveryProcessManager,
        shutdownHooks: ShutdownHooks(),
        signals: FakeSignals(),
        stdio: fakeStdio,
      );
      final discoveryClient = WidgetPreviewSessionClient(
        toolContext: discoveryContext,
        dtdConnector: (Uri uri) async {
          expect(uri.toString(), kDtdWsUri1);
          return discoveryDtd;
        },
      );

      final (
        commandResult: FlutterCommandResult? winListResult,
        exitCode: int winListExitCode,
      ) = await runSubcommand(
        args: const <String>[r'--file=lib\card.dart', '--no-sync'],
        client: discoveryClient,
        fileSystem: windowsFs,
        isSnapshot: false,
        machine: false,
        platform: windowsPlatform,
      );
      expect(winListResult?.exitStatus, ExitStatus.success);
      expect(winListExitCode, 0);
      expect(discoveryProcessManager, hasNoRemainingExpectations);
      expect(
        discoveryDtd.calls.last,
        equals(<String, Object?>{
          'service': kPreviewServiceUuid,
          'method': WidgetPreviewDtdServices.kListPreviews,
          'params': <String, Object?>{
            'sync': false,
            'fileUri': 'file:///C:/src/my_app/lib/card.dart',
          },
        }),
      );

      // 2. Ephemeral headless fallback on Windows spawns flutter.bat and tears down with taskkill /F /T /PID.
      dtdMetaFile.deleteSync();
      final winProcessCompleter = Completer<void>();
      final String winStartedLine = jsonEncode(<Map<String, Object?>>[
        <String, Object?>{
          'event': 'widget_preview.initializing',
          'params': <String, Object?>{'pid': 4321},
        },
        <String, Object?>{
          'event': 'widget_preview.started',
          'params': <String, Object?>{
            'url': 'http://localhost:54321',
            'dtdUri': kDtdWsUri2,
            'previewService': kPreviewServiceUuid,
            'scaffoldService': kScaffoldServiceUuid,
            'projectRoot': windowsProjectRoot,
          },
        },
      ]);
      final winHeadlessProcess = FakeProcess(
        completer: winProcessCompleter,
        stdout: utf8.encode('$winStartedLine\n'),
      );
      final ephemeralDtd = _FakeCliDartToolingDaemon(
        serviceNames: <String>[kPreviewServiceUuid],
        serviceInfos: <String, PreviewServiceInfo>{
          kPreviewServiceUuid: createServiceInfo(
            dtdUri: kDtdWsUri2,
            projectRoot: windowsProjectRoot,
          ),
        },
        listPreviewsResponse: const PreviewListResponse(previews: <PreviewEntry>[]),
      );
      final killedWinPids = <int>[];
      final ephemeralProcessManager = _PidTrackingFakeProcessManager(
        commands: <FakeCommand>[
          FakeCommand(command: <String>[dartBinary, 'tooling-daemon', '--list'], exitCode: 1),
          FakeCommand(
            command: const <String>[
              r'C:\flutter\bin\flutter.bat',
              'widget-preview',
              'start',
              '--headless',
              '--machine',
            ],
            workingDirectory: windowsProjectRoot,
            process: winHeadlessProcess,
          ),
          FakeCommand(
            command: const <String>['taskkill', '/F', '/T', '/PID', '1234'],
            onRun: (_) {
              if (!winProcessCompleter.isCompleted) {
                winProcessCompleter.complete();
              }
            },
          ),
        ],
        onKillPid: (int pid, io.ProcessSignal signal) {
          killedWinPids.add(pid);
          return true;
        },
      );
      final ephemeralContext = FakeToolContext(
        artifacts: artifacts,
        cache: FakeCache(fileSystem: windowsFs, flutterRoot: windowsFlutterRoot),
        fs: windowsFs,
        logger: humanLogger,
        platform: windowsPlatform,
        processManager: ephemeralProcessManager,
        shutdownHooks: ShutdownHooks(),
        signals: FakeSignals(),
        stdio: fakeStdio,
      );
      final ephemeralClient = WidgetPreviewSessionClient(
        toolContext: ephemeralContext,
        dtdConnector: (Uri uri) async {
          expect(uri.toString(), kDtdWsUri2);
          return ephemeralDtd;
        },
      );

      final (
        commandResult: FlutterCommandResult? winHeadlessResult,
        exitCode: int winHeadlessExitCode,
      ) = await runSubcommand(
        args: const <String>['--no-image', kPreviewId],
        client: ephemeralClient,
        fileSystem: windowsFs,
        isSnapshot: true,
        machine: false,
        platform: windowsPlatform,
      );
      expect(winHeadlessResult?.exitStatus, ExitStatus.success);
      expect(winHeadlessExitCode, 0);
      expect(ephemeralProcessManager.base, hasNoRemainingExpectations);
      expect(winProcessCompleter.isCompleted, isTrue);
      expect(killedWinPids, contains(4321));
      expect(ephemeralDtd.closed, isTrue);
    });

    testWithoutContext('forwards --no-build-hooks and --web-browser-flag to ephemeral headless session on list and snapshot', () async {
      final FileSystem testFs = MemoryFileSystem.test();
      final Directory projectDir = testFs.directory(_kProjectRootPath)..createSync(recursive: true);
      testFs.currentDirectory = projectDir;
      projectDir.childFile('pubspec.yaml').writeAsStringSync('name: my_app\n');

      final artifacts = Artifacts.test();
      final String dartBinary = artifacts.getArtifactPath(Artifact.engineDartBinary);
      final cache = FakeCache(fileSystem: testFs, flutterRoot: '/flutter');

      Future<void> verifyForwarding({required bool isSnapshot}) async {
        final processCompleter = Completer<void>();
        final String startedEventLine = jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'event': 'widget_preview.started',
            'params': <String, Object?>{
              'url': 'http://localhost:54321',
              'dtdUri': kDtdWsUri1,
              'previewService': kPreviewServiceUuid,
              'scaffoldService': kScaffoldServiceUuid,
              'projectRoot': _kProjectRootPath,
            },
          },
        ]);
        final fakeProcess = FakeProcess(
          completer: processCompleter,
          stdout: utf8.encode('$startedEventLine\n'),
        );
        final processManager = FakeProcessManager.list(<FakeCommand>[
          FakeCommand(command: <String>[dartBinary, 'tooling-daemon', '--list'], exitCode: 1),
          FakeCommand(
            command: const <String>[
              '/flutter/bin/flutter',
              'widget-preview',
              'start',
              '--headless',
              '--machine',
              '--no-build-hooks',
              '--web-browser-flag=--disable-gpu',
              '--web-browser-flag=--no-sandbox',
            ],
            completer: processCompleter,
            process: fakeProcess,
          ),
        ]);
        final fakeDtd = _FakeCliDartToolingDaemon(
          serviceNames: <String>[kPreviewServiceUuid],
          serviceInfos: <String, PreviewServiceInfo>{kPreviewServiceUuid: createServiceInfo()},
          listPreviewsResponse: PreviewListResponse(previews: <PreviewEntry>[createSampleEntry()]),
        );
        final context = FakeToolContext(
          artifacts: artifacts,
          cache: cache,
          fs: testFs,
          logger: machineLogger,
          platform: FakePlatform(),
          processManager: processManager,
          shutdownHooks: ShutdownHooks(),
          signals: FakeSignals(),
          stdio: fakeStdio,
        );
        final client = WidgetPreviewSessionClient(
          toolContext: context,
          dtdConnector: (_) async => fakeDtd,
        );

        final (
          commandResult: FlutterCommandResult? result,
          exitCode: int exitCode,
        ) = await runSubcommand(
          args: <String>[
            if (isSnapshot) kPreviewId,
            '--no-build-hooks',
            '--web-browser-flag=--disable-gpu',
            '--web-browser-flag=--no-sandbox',
            '--machine',
          ],
          client: client,
          fileSystem: testFs,
          isSnapshot: isSnapshot,
          machine: true,
        );

        expect(result?.exitStatus, ExitStatus.success);
        expect(exitCode, 0);
        expect(processManager, hasNoRemainingExpectations);
      }

      await verifyForwarding(isSnapshot: true);
    });

    testWithoutContext(
      'fails fast on active < 3.50 DTD widget-preview session when .widget_preview exists',
      () async {
        final FileSystem testFs = MemoryFileSystem.test();
        final Directory projectDir = testFs.directory(_kProjectRootPath)
          ..createSync(recursive: true);
        projectDir.childFile('pubspec.yaml').writeAsStringSync('name: my_app\n');
        testFs.currentDirectory = projectDir;
        projectDir.childDirectory('.widget_preview').createSync();

        final artifacts = Artifacts.test();
        final String dartBinary = artifacts.getArtifactPath(Artifact.engineDartBinary);
        final processManager = FakeProcessManager.list(<FakeCommand>[
          FakeCommand(
            command: <String>[dartBinary, 'tooling-daemon', '--list'],
            stdout: '$kDtdWsUri1\n',
          ),
        ]);
        final legacyDtd = _FakeCliDartToolingDaemon(
          serviceNames: const <String>['widget-preview'],
          serviceInfos: const <String, PreviewServiceInfo>{},
        );
        final context = FakeToolContext(
          artifacts: artifacts,
          fs: testFs,
          logger: humanLogger,
          platform: FakePlatform(),
          processManager: processManager,
          shutdownHooks: ShutdownHooks(),
          signals: FakeSignals(),
          stdio: fakeStdio,
        );
        final client = WidgetPreviewSessionClient(
          toolContext: context,
          dtdConnector: (_) async => legacyDtd,
        );
        final FlutterProject rootProject = FlutterProject.fromDirectoryTest(projectDir);

        await expectLater(
          client.withSession<void>(rootProject: rootProject, action: (_) async {}),
          throwsToolExit(message: 'Flutter < 3.50'),
        );
        expect(processManager, hasNoRemainingExpectations);
        expect(legacyDtd.closed, isTrue);
      },
    );

    testWithoutContext('ignores < 3.50 DTD session when .widget_preview does not exist or service unregistered mid-call', () async {
      final FileSystem testFs = MemoryFileSystem.test();
      final Directory projectDir = testFs.directory(_kProjectRootPath)..createSync(recursive: true);
      testFs.currentDirectory = projectDir;
      projectDir.childFile('pubspec.yaml').writeAsStringSync('name: my_app\n');

      final artifacts = Artifacts.test();
      final String dartBinary = artifacts.getArtifactPath(Artifact.engineDartBinary);
      final cache = FakeCache(fileSystem: testFs, flutterRoot: '/flutter');

      Future<void> verifyFallsBackToEphemeral({
        required bool createScaffoldDir,
        required bool unregisterMidCall,
      }) async {
        if (createScaffoldDir) {
          projectDir.childDirectory('.widget_preview').createSync();
        } else if (projectDir.childDirectory('.widget_preview').existsSync()) {
          projectDir.childDirectory('.widget_preview').deleteSync(recursive: true);
        }

        final processCompleter = Completer<void>();
        final String startedEventLine = jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'event': 'widget_preview.started',
            'params': <String, Object?>{
              'url': 'http://localhost:54321',
              'dtdUri': kDtdWsUri2,
              'previewService': kPreviewServiceUuid,
              'scaffoldService': kScaffoldServiceUuid,
              'projectRoot': _kProjectRootPath,
            },
          },
        ]);
        final fakeProcess = FakeProcess(
          completer: processCompleter,
          stdout: utf8.encode('$startedEventLine\n'),
        );
        final processManager = FakeProcessManager.list(<FakeCommand>[
          FakeCommand(
            command: <String>[dartBinary, 'tooling-daemon', '--list'],
            stdout: '$kDtdWsUri1\n',
          ),
          FakeCommand(
            command: const <String>[
              '/flutter/bin/flutter',
              'widget-preview',
              'start',
              '--headless',
              '--machine',
            ],
            completer: processCompleter,
            process: fakeProcess,
          ),
        ]);
        late final _FakeCliDartToolingDaemon legacyDtd;
        legacyDtd = _FakeCliDartToolingDaemon(
          serviceNames: <String>['widget-preview'],
          serviceInfos: const <String, PreviewServiceInfo>{},
          onGetServiceInfo: unregisterMidCall ? (_) => legacyDtd.serviceNames.clear() : null,
        );
        final ephemeralDtd = _FakeCliDartToolingDaemon(
          serviceNames: <String>[kPreviewServiceUuid],
          serviceInfos: <String, PreviewServiceInfo>{
            kPreviewServiceUuid: createServiceInfo(dtdUri: kDtdWsUri2),
          },
        );
        final context = FakeToolContext(
          artifacts: artifacts,
          cache: cache,
          fs: testFs,
          logger: humanLogger,
          platform: FakePlatform(),
          processManager: processManager,
          shutdownHooks: ShutdownHooks(),
          signals: FakeSignals(),
          stdio: fakeStdio,
        );
        final client = WidgetPreviewSessionClient(
          toolContext: context,
          dtdConnector: (Uri uri) async => uri.toString() == kDtdWsUri1 ? legacyDtd : ephemeralDtd,
        );
        final FlutterProject rootProject = FlutterProject.fromDirectoryTest(projectDir);

        var actionCalled = false;
        await client.withSession<void>(
          rootProject: rootProject,
          action: (WidgetPreviewActiveSession session) async {
            actionCalled = true;
            expect(session.isEphemeral, isTrue);
          },
        );
        expect(actionCalled, isTrue);
        expect(processManager, hasNoRemainingExpectations);
      }

      // Unrelated < 3.50 session in another project when .widget_preview/ is absent.
      await verifyFallsBackToEphemeral(createScaffoldDir: false, unregisterMidCall: false);
      // Service unregistered mid-call even though .widget_preview/ exists.
      await verifyFallsBackToEphemeral(createScaffoldDir: true, unregisterMidCall: true);
    });

    testWithoutContext(
      'terminates child and throws < 3.50 error when widget_preview.started lacks service metadata',
      () async {
        final FileSystem testFs = MemoryFileSystem.test();
        final Directory projectDir = testFs.directory(_kProjectRootPath)
          ..createSync(recursive: true);
        projectDir.childFile('pubspec.yaml').writeAsStringSync('name: my_app\n');
        testFs.currentDirectory = projectDir;

        final processCompleter = Completer<void>();
        final String legacyStartedLine = jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'event': 'widget_preview.started',
            'params': <String, Object?>{'url': 'http://localhost:54321', 'dtdUri': kDtdWsUri1},
          },
        ]);
        final fakeProcess = FakeProcess(
          completer: processCompleter,
          stdout: utf8.encode('$legacyStartedLine\n'),
        );
        final artifacts = Artifacts.test();
        final String dartBinary = artifacts.getArtifactPath(Artifact.engineDartBinary);
        final processManager = FakeProcessManager.list(<FakeCommand>[
          FakeCommand(command: <String>[dartBinary, 'tooling-daemon', '--list'], exitCode: 1),
          FakeCommand(
            command: const <String>[
              '/flutter/bin/flutter',
              'widget-preview',
              'start',
              '--headless',
              '--machine',
            ],
            completer: processCompleter,
            process: fakeProcess,
          ),
        ]);
        final context = FakeToolContext(
          artifacts: artifacts,
          cache: FakeCache(fileSystem: testFs, flutterRoot: '/flutter'),
          fs: testFs,
          logger: humanLogger,
          platform: FakePlatform(),
          processManager: processManager,
          shutdownHooks: ShutdownHooks(),
          signals: FakeSignals(),
          stdio: fakeStdio,
        );
        final client = WidgetPreviewSessionClient(toolContext: context);
        final FlutterProject rootProject = FlutterProject.fromDirectoryTest(projectDir);

        await expectLater(
          client.withSession<void>(rootProject: rootProject, action: (_) async {}),
          throwsToolExit(message: 'Flutter < 3.50'),
        );
        expect(processCompleter.isCompleted, isTrue);
        expect(processManager, hasNoRemainingExpectations);
      },
    );
  });

  group('Headless widget preview CLI options, diagnostics, and git exclude', () {
    testWithoutContext('ensureWidgetPreviewGitExclude updates .git/info/exclude idempotently', () {
      final FileSystem fs = MemoryFileSystem.test();
      final logger = BufferLogger.test();
      final Directory repoRoot = fs.directory('/repo')..createSync();
      repoRoot.childDirectory('.git').createSync();
      final Directory packageDir = repoRoot.childDirectory('packages/app')
        ..createSync(recursive: true);

      ensureWidgetPreviewGitExclude(projectDirectory: packageDir, logger: logger);
      final File excludeFile = repoRoot.childDirectory('.git/info').childFile('exclude');
      expect(excludeFile, exists);
      expect(excludeFile.readAsStringSync(), '.widget_preview/\n');

      // Calling a second time is idempotent.
      ensureWidgetPreviewGitExclude(projectDirectory: packageDir, logger: logger);
      expect(excludeFile.readAsStringSync(), '.widget_preview/\n');

      // Existing entries with leading '/' or without trailing '/' are recognized.
      excludeFile.writeAsStringSync('/.widget_preview/\n');
      ensureWidgetPreviewGitExclude(projectDirectory: packageDir, logger: logger);
      expect(excludeFile.readAsStringSync(), '/.widget_preview/\n');

      excludeFile.writeAsStringSync('.widget_preview\n');
      ensureWidgetPreviewGitExclude(projectDirectory: packageDir, logger: logger);
      expect(excludeFile.readAsStringSync(), '.widget_preview\n');
    });

    testWithoutContext('ensureWidgetPreviewGitExclude resolves linked git worktree commondir', () {
      final FileSystem fs = MemoryFileSystem.test();
      final logger = BufferLogger.test();
      final Directory mainGitDir = fs.directory('/main/.git')..createSync(recursive: true);
      final Directory worktreeGitDir = mainGitDir.childDirectory('worktrees/wt1')
        ..createSync(recursive: true);
      worktreeGitDir.childFile('commondir').writeAsStringSync('../..\n');

      final Directory worktreeRoot = fs.directory('/wt1')..createSync();
      worktreeRoot.childFile('.git').writeAsStringSync('gitdir: ${worktreeGitDir.path}\n');
      final Directory packageDir = worktreeRoot.childDirectory('app')..createSync();

      ensureWidgetPreviewGitExclude(projectDirectory: packageDir, logger: logger);
      final File excludeFile = mainGitDir.childDirectory('info').childFile('exclude');
      expect(excludeFile, exists);
      expect(excludeFile.readAsStringSync(), '.widget_preview/\n');
    });

    testWithoutContext('WidgetPreviewStartCommand --headless skips .gitignore and throws headless browser error when no devices found', () async {
      final FileSystem fs = MemoryFileSystem.test();
      final Directory projectDir = fs.directory(_kProjectRootPath)..createSync(recursive: true);
      fs.currentDirectory = projectDir;
      projectDir.childDirectory('.git').createSync();
      projectDir.childFile('.gitignore').writeAsStringSync('build/\n');
      projectDir.childFile('pubspec.yaml').writeAsStringSync('name: my_app\n');
      projectDir.childFile('lib/main.dart').createSync(recursive: true);
      projectDir.childDirectory('.widget_preview/.dart_tool').createSync(recursive: true);
      projectDir.childDirectory('.widget_preview/lib/src/dtd').createSync(recursive: true);
      projectDir
          .childFile('.widget_preview/.dart_tool/package_config.json')
          .writeAsStringSync('{"configVersion":2,"packages":[]}');
      projectDir
          .childFile('.widget_preview/pubspec.yaml')
          .writeAsStringSync('name: widget_preview_scaffold\n');

      final stdio = FakeStdio();
      final logger = WidgetPreviewMachineAwareLogger(
        BufferLogger.test(),
        machine: false,
        stdio: stdio,
        verbose: false,
      );
      final Cache cache = _FakeCacheWithSdkVersion(fileSystem: fs, flutterRoot: '/flutter');
      PreviewManifest(
        logger: logger,
        rootProject: FlutterProject.fromDirectoryTest(projectDir),
        fs: fs,
        cache: cache,
      ).generate();
      final shutdownHooks = ShutdownHooks();
      addTearDown(() => shutdownHooks.runShutdownHooks(logger));
      final toolContext = FakeToolContext(
        artifacts: Artifacts.test(),
        cache: cache,
        fs: fs,
        logger: logger,
        platform: FakePlatform(),
        processManager: FakeProcessManager.empty(),
        shutdownHooks: shutdownHooks,
        signals: FakeSignals(),
        stdio: stdio,
      );
      final command = WidgetPreviewCommand(
        analysisServerFactoryOverride: () async => _FakeAnalysisServer(),
        buildSystem: TestBuildSystem.all(BuildResult(success: true)),
        buildTargets: const BuildTargetsImpl(),
        dtdServicesOverride: FakeWidgetPreviewDtdServices(),
        toolContext: toolContext,
        watcherBuilderOverride: (_) => _FakeWatcher(),
      );
      final runner = TestFlutterCommandRunner(
        deviceManager: FakeDeviceManager(),
        featureFlags: TestFeatureFlags(isWebEnabled: true),
        toolContext: toolContext,
      )..addCommand(command);

      await expectLater(
        runner.run(const <String>['widget-preview', 'start', '--headless']),
        throwsToolExit(message: WidgetPreviewStartCommand.kHeadlessBrowserNotFoundErrorMessage),
      );

      expect(projectDir.childFile('.gitignore').readAsStringSync(), 'build/\n');
      expect(
        projectDir.childDirectory('.git/info').childFile('exclude').readAsStringSync(),
        '.widget_preview/\n',
      );
    });

    testWithoutContext('WidgetPreviewStartCommand plumbs --no-build-hooks and --web-browser-flag into DebuggingOptions', () async {
      final FileSystem fs = MemoryFileSystem.test();
      final Directory projectDir = fs.directory(_kProjectRootPath)..createSync(recursive: true);
      fs.currentDirectory = projectDir;
      projectDir.childFile('pubspec.yaml').writeAsStringSync('name: my_app\n');
      projectDir.childFile('lib/main.dart').createSync(recursive: true);
      projectDir.childDirectory('.widget_preview/.dart_tool').createSync(recursive: true);
      projectDir.childDirectory('.widget_preview/lib/src/dtd').createSync(recursive: true);
      projectDir
          .childFile('.widget_preview/.dart_tool/package_config.json')
          .writeAsStringSync('{"configVersion":2,"packages":[]}');
      projectDir
          .childFile('.widget_preview/pubspec.yaml')
          .writeAsStringSync('name: widget_preview_scaffold\n');

      final stdio = FakeStdio();
      final logger = WidgetPreviewMachineAwareLogger(
        BufferLogger.test(),
        machine: false,
        stdio: stdio,
        verbose: false,
      );
      final Cache cache = _FakeCacheWithSdkVersion(fileSystem: fs, flutterRoot: '/flutter');
      PreviewManifest(
        logger: logger,
        rootProject: FlutterProject.fromDirectoryTest(projectDir),
        fs: fs,
        cache: cache,
      ).generate();
      final shutdownHooks = ShutdownHooks();
      addTearDown(() => shutdownHooks.runShutdownHooks(logger));
      final toolContext = FakeToolContext(
        artifacts: Artifacts.test(),
        cache: cache,
        fs: fs,
        logger: logger,
        platform: FakePlatform(),
        processManager: FakeProcessManager.empty(),
        shutdownHooks: shutdownHooks,
        signals: FakeSignals(),
        stdio: stdio,
      );
      DebuggingOptions? capturedOptions;
      final command = WidgetPreviewCommand(
        analysisServerFactoryOverride: () async => _FakeAnalysisServer(),
        buildSystem: TestBuildSystem.all(BuildResult(success: true)),
        buildTargets: const BuildTargetsImpl(),
        dtdServicesOverride: FakeWidgetPreviewDtdServices(),
        flutterDeviceFactoryOverride: (_, {required buildInfo, required target}) async =>
            _FakeFlutterDevice(),
        residentRunnerFactoryOverride:
            (
              FlutterDevice device, {
              required DebuggingOptions debuggingOptions,
              required FlutterProject flutterProject,
              required String projectRootPath,
              required String target,
            }) {
              capturedOptions = debuggingOptions;
              throw StateError('captured');
            },
        toolContext: toolContext,
        watcherBuilderOverride: (_) => _FakeWatcher(),
      );
      final runner = TestFlutterCommandRunner(
        deviceManager: FakeDeviceManager()..attachedDevices = <Device>[_FakeWebPreviewDevice()],
        featureFlags: TestFeatureFlags(isWebEnabled: true),
        toolContext: toolContext,
      )..addCommand(command);

      await expectLater(
        runner.run(const <String>[
          'widget-preview',
          'start',
          '--headless',
          '--no-build-hooks',
          '--web-browser-flag=--disable-gpu',
          '--web-browser-flag=--no-sandbox',
        ]),
        throwsA(isA<StateError>()),
      );

      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.buildInfo.buildNativeAssets, isFalse);
      expect(capturedOptions!.webConfig.runHeadless, isTrue);
      expect(
        capturedOptions!.webConfig.browserFlags,
        equals(<String>['--disable-gpu', '--no-sandbox']),
      );
    });

    testWithoutContext('resolveFileFilter prefers explicitProjectDirectory over cwd', () {
      final FileSystem fs = MemoryFileSystem.test();
      final Directory cwdDir = fs.directory('/cwd')..createSync(recursive: true);
      final Directory targetDir = fs.directory('/target')..createSync(recursive: true);
      cwdDir.childDirectory('lib').childFile('foo.dart').createSync(recursive: true);
      targetDir.childDirectory('lib').childFile('foo.dart').createSync(recursive: true);
      fs.currentDirectory = cwdDir;

      final toolContext = FakeToolContext(
        artifacts: Artifacts.test(),
        fs: fs,
        logger: BufferLogger.test(),
        processManager: FakeProcessManager.empty(),
      );
      final client = WidgetPreviewSessionClient(toolContext: toolContext);
      final String? resolved = client.resolveFileFilter(
        'lib/foo.dart',
        explicitProjectDirectory: targetDir,
      );
      expect(resolved, targetDir.childDirectory('lib').childFile('foo.dart').uri.toString());
    });

    ({
      BufferLogger bufferLogger,
      WidgetPreviewStartCommand command,
      Directory projectDir,
      TestFlutterCommandRunner runner,
      Directory scaffoldDir,
    })
    setUpStartCommand({
      required FileSystem fs,
      required WidgetPreviewDtdServices dtdServices,
      Directory? cwdDir,
      PreviewPubspecBuilder? previewPubspecBuilderOverride,
      String projectPath = '/project',
    }) {
      final Directory projectDir = fs.directory(projectPath)..createSync(recursive: true);
      projectDir.childFile('pubspec.yaml').writeAsStringSync('name: test_app\n');
      projectDir.childDirectory('.dart_tool').createSync(recursive: true);
      final Directory scaffoldDir = projectDir.childDirectory('.widget_preview')
        ..childDirectory('.dart_tool').createSync(recursive: true)
        ..childDirectory('lib')
            .childDirectory('src')
            .childDirectory('dtd')
            .createSync(recursive: true);
      scaffoldDir
          .childDirectory('.dart_tool')
          .childFile('package_config.json')
          .writeAsStringSync('{"configVersion":2,"packages":[]}');
      scaffoldDir.childFile('pubspec.yaml').writeAsStringSync('name: widget_preview_scaffold\n');
      final bufferLogger = BufferLogger.test();
      final String pubspecHash = FlutterProject.fromDirectoryTest(projectDir)
          .computeManifestMD5Hash(logger: bufferLogger, fs: fs);
      scaffoldDir
          .childFile('preview_manifest.json')
          .writeAsStringSync(
            jsonEncode(<String, Object?>{
              'version': '0.0.2',
              'sdk-version': '0.0.0',
              'pubspec-hashes': <String, String>{
                projectDir.childFile('pubspec.yaml').absolute.path: pubspecHash,
              },
            }),
          );
      fs.currentDirectory = cwdDir ?? projectDir;

      final machineLogger = WidgetPreviewMachineAwareLogger(
        bufferLogger,
        machine: false,
        stdio: FakeStdio(),
        verbose: false,
      );
      final commandToolContext = FakeToolContext(
        artifacts: Artifacts.test(),
        cache: _FakeCacheWithSdkVersion(fileSystem: fs, flutterRoot: '/flutter'),
        fs: fs,
        logger: machineLogger,
        processManager: FakeProcessManager.empty(),
      );
      final command = WidgetPreviewStartCommand(
        analysisServerFactoryOverride: () async => _FakeAnalysisServer(),
        buildSystem: TestBuildSystem.all(BuildResult(success: true)),
        buildTargets: const BuildTargetsImpl(),
        dtdServicesOverride: dtdServices,
        flutterDeviceFactoryOverride: (
          Device _, {
          required BuildInfo buildInfo,
          required String target,
        }) async => _FakeFlutterDevice(),
        previewPubspecBuilderOverride: previewPubspecBuilderOverride,
        toolContext: commandToolContext,
        watcherBuilderOverride: (_) => _FakeWatcher(),
      );
      final runner = TestFlutterCommandRunner(
        deviceManager: FakeDeviceManager()..attachedDevices = <Device>[_FakeWebPreviewDevice()],
        featureFlags: TestFeatureFlags(isWebEnabled: true),
        toolContext: commandToolContext,
      )..addCommand(command);
      return (
        bufferLogger: bufferLogger,
        command: command,
        projectDir: projectDir,
        runner: runner,
        scaffoldDir: scaffoldDir,
      );
    }

    testWithoutContext(
      'configureDtd logs warning and falls back to launching DTD when --dtd-url fails',
      () async {
        final FileSystem fs = MemoryFileSystem.test();
        final dtdServices = _FallbackConnectDtdServices();
        final (
          :BufferLogger bufferLogger,
          command: _,
          projectDir: _,
          :TestFlutterCommandRunner runner,
          scaffoldDir: _,
        ) = setUpStartCommand(
          fs: fs,
          dtdServices: dtdServices,
        );

        await runner.run(const <String>[
          'start',
          '--dtd-url=ws://127.0.0.1:1',
          '--no-launch-previewer',
        ]);

        expect(bufferLogger.warningText, contains('Failed to connect to existing DTD instance'));
        expect(dtdServices.launchAndConnectCalled, isTrue);
      },
    );

    testWithoutContext(
      'withSession times out hung DTD probe and connects to next candidate',
      () async {
        final FileSystem fs = MemoryFileSystem.test();
        final Directory projectDir = fs.directory('/project')..createSync(recursive: true);
        projectDir.childFile('pubspec.yaml').writeAsStringSync('name: test_app\n');
        final Directory dtdDir = fs.directory('/home/.dart/dtd')..createSync(recursive: true);
        dtdDir
            .childFile('dtd_1.json')
            .writeAsStringSync(jsonEncode(<String, Object?>{'uri': 'ws://127.0.0.1:1111/a'}));
        dtdDir
            .childFile('dtd_2.json')
            .writeAsStringSync(jsonEncode(<String, Object?>{'uri': 'ws://127.0.0.1:2222/b'}));

        final secondDtd = _FakeCliDartToolingDaemon(
          serviceNames: const <String>['widget-preview-1'],
          serviceInfos: <String, PreviewServiceInfo>{
            'widget-preview-1': PreviewServiceInfo(
              dtdUri: 'ws://127.0.0.1:2222/b',
              previewService: 'widget-preview-1',
              projectRoot: projectDir.path,
              scaffoldConnected: true,
              scaffoldService: 'PreviewScaffold-1',
              scaffoldStream: 'WidgetPreviewScaffold-1',
            ),
          },
        );
        final client = WidgetPreviewSessionClient(
          dtdProbeTimeout: const Duration(milliseconds: 20),
          dtdConnector: (Uri uri) {
            if (uri.port == 1111) {
              return Completer<DartToolingDaemon>().future;
            }
            return Future<DartToolingDaemon>.value(secondDtd);
          },
          toolContext: FakeToolContext(
            artifacts: Artifacts.test(),
            fs: fs,
            logger: BufferLogger.test(),
            platform: FakePlatform(environment: const <String, String>{'HOME': '/home'}),
            processManager: FakeProcessManager.any(),
          ),
        );

        final String matchedUri = await client.withSession<String>(
          rootProject: FlutterProject.fromDirectoryTest(projectDir),
          action: (WidgetPreviewActiveSession session) async => session.info.dtdUri,
        );
        expect(matchedUri, 'ws://127.0.0.1:2222/b');
      },
    );

    testWithoutContext(
      'onPubspecChangeDetected updates rootProject rather than cwd project',
      () async {
        final FileSystem fs = MemoryFileSystem.test();
        final Directory cwdDir = fs.directory('/cwd')..createSync(recursive: true);
        cwdDir.childFile('pubspec.yaml').writeAsStringSync('name: cwd_app\n');
        final pubspecBuilder = _FakePreviewPubspecBuilder();
        final (
          bufferLogger: _,
          :WidgetPreviewStartCommand command,
          :Directory projectDir,
          :TestFlutterCommandRunner runner,
          :Directory scaffoldDir,
        ) = setUpStartCommand(
          fs: fs,
          dtdServices: FakeWidgetPreviewDtdServices(),
          cwdDir: cwdDir,
          previewPubspecBuilderOverride: pubspecBuilder,
          projectPath: '/root_app',
        );

        await runner.run(<String>['start', '--no-launch-previewer', projectDir.path]);

        await command.onPubspecChangeDetected(projectDir.childFile('pubspec.yaml').path);
        expect(pubspecBuilder.lastRootProject?.directory.path, projectDir.path);
        expect(
          scaffoldDir.childFile('pubspec.yaml').readAsStringSync(),
          contains('name: test_app_scaffold'),
        );
        expect(cwdDir.childDirectory('.widget_preview').existsSync(), isFalse);
      },
    );
  });
}

class _FakePreviewPubspecBuilder extends Fake implements PreviewPubspecBuilder {
  FlutterProject? lastRootProject;

  @override
  Future<void> populatePreviewPubspec({
    required FlutterProject rootProject,
    String? updatedPubspecPath,
  }) async {
    lastRootProject = rootProject;
    rootProject.widgetPreviewScaffold
        .childFile('pubspec.yaml')
        .writeAsStringSync('name: ${rootProject.manifest.appName}_scaffold\n');
  }
}

class _FallbackConnectDtdServices extends FakeWidgetPreviewDtdServices {
  _FallbackConnectDtdServices() {
    dtdUri = null;
  }

  bool launchAndConnectCalled = false;

  @override
  Future<void> connect({required Uri dtdWsUri}) async {
    throw const io.SocketException('Connection refused');
  }

  @override
  Future<void> launchAndConnect({required AnalysisServer analysisServer}) async {
    launchAndConnectCalled = true;
    dtdUri = Uri.parse('ws://127.0.0.1:54322/secret');
  }
}

class _StubbornExitProcess extends FakeProcess {
  _StubbornExitProcess({required this._exitCompleter, required List<int> stdoutBytes})
    : super(completer: _exitCompleter, stdout: stdoutBytes);

  final Completer<void> _exitCompleter;
  bool exited = false;

  @override
  bool kill([io.ProcessSignal signal = io.ProcessSignal.sigterm]) {
    super.kill(signal);
    if (signal == io.ProcessSignal.sigkill && !_exitCompleter.isCompleted) {
      exited = true;
      _exitCompleter.complete();
    }
    return true;
  }
}

class _PidTrackingFakeProcessManager extends Fake implements ProcessManager {
  _PidTrackingFakeProcessManager({required List<FakeCommand> commands, required this.onKillPid})
    : base = FakeProcessManager.list(commands);

  final FakeProcessManager base;
  final bool Function(int pid, io.ProcessSignal signal) onKillPid;

  @override
  bool canRun(Object? executable, {String? workingDirectory}) =>
      base.canRun(executable, workingDirectory: workingDirectory);

  @override
  Future<io.Process> start(
    List<Object> command, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    io.ProcessStartMode mode = io.ProcessStartMode.normal,
  }) {
    return base.start(
      command,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: runInShell,
      mode: mode,
    );
  }

  @override
  Future<io.ProcessResult> run(
    List<Object> command, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding = io.systemEncoding,
    Encoding? stderrEncoding = io.systemEncoding,
  }) {
    return base.run(
      command,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: runInShell,
      stdoutEncoding: stdoutEncoding,
      stderrEncoding: stderrEncoding,
    );
  }

  @override
  bool killPid(int pid, [io.ProcessSignal signal = io.ProcessSignal.sigterm]) =>
      onKillPid(pid, signal);
}

class _FakeCliDartToolingDaemon extends Fake implements DartToolingDaemon {
  _FakeCliDartToolingDaemon({
    required this.serviceInfos,
    required this.serviceNames,
    this.callStateError,
    this.captureError,
    this.captureResponse,
    this.closeError,
    this.listPreviewsResponse,
    this.onGetServiceInfo,
  });

  final List<String> serviceNames;
  final Map<String, PreviewServiceInfo> serviceInfos;
  final void Function(String? serviceName)? onGetServiceInfo;
  PreviewListResponse? listPreviewsResponse;
  SyncPreviewsResponse syncResponse = const SyncPreviewsResponse(
    compileSuccess: true,
    errorPreviewCount: 0,
    fullRestart: false,
    reloaded: true,
  );
  CapturePreviewResponse? captureResponse;
  RpcException? captureError;
  StateError? callStateError;
  Exception? closeError;
  void Function(String streamId)? onStreamSubscribed;
  final _eventControllers = <String, StreamController<DTDEvent>>{};
  final _doneCompleter = Completer<void>();
  final calls = <Map<String, Object?>>[];
  bool closed = false;

  @override
  bool get isClosed => closed;

  @override
  Future<void> get done => _doneCompleter.future;

  void simulateUnexpectedDisconnect() {
    closed = true;
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }

  void emitEvent(String streamId, String kind) {
    _eventControllers[streamId]?.add(DTDEvent(streamId, kind, const <String, Object?>{}, 0));
  }

  @override
  Stream<DTDEvent> onEvent(String streamId) {
    return _eventControllers.putIfAbsent(streamId, StreamController<DTDEvent>.broadcast).stream;
  }

  @override
  Future<void> streamListen(String streamId) async {
    onStreamSubscribed?.call(streamId);
  }

  @override
  Future<RegisteredServicesResponse> getRegisteredServices() async {
    return RegisteredServicesResponse.fromDTDResponse(
      DTDResponse('1', RegisteredServicesResponse.type, <String, Object?>{
        'type': RegisteredServicesResponse.type,
        'dtdServices': <String>[],
        'clientServices': <Map<String, Object?>>[
          for (final String name in serviceNames)
            <String, Object?>{'name': name, 'methods': <Map<String, Object?>>[]},
        ],
      }),
    );
  }

  @override
  Future<DTDResponse> call(
    String? serviceName,
    String methodName, {
    Map<String, Object?>? params,
  }) async {
    calls.add(<String, Object?>{'service': serviceName, 'method': methodName, 'params': params});
    if (methodName != WidgetPreviewDtdServices.kGetServiceInfo) {
      if (callStateError case final StateError error) {
        throw error;
      }
    }
    switch (methodName) {
      case WidgetPreviewDtdServices.kGetServiceInfo:
        onGetServiceInfo?.call(serviceName);
        final PreviewServiceInfo? info = serviceInfos[serviceName];
        if (info == null) {
          throw RpcException(RpcErrorCodes.kMethodNotFound, 'Unknown service $serviceName');
        }
        return DTDResponse('1', PreviewServiceInfo.kTypeName, info.toJson());
      case WidgetPreviewDtdServices.kListPreviews:
        final PreviewListResponse response =
            listPreviewsResponse ?? const PreviewListResponse(previews: <PreviewEntry>[]);
        return DTDResponse('1', PreviewListResponse.kTypeName, response.toJson());
      case WidgetPreviewDtdServices.kSyncPreviews:
        return DTDResponse('1', SyncPreviewsResponse.kTypeName, syncResponse.toJson());
      case WidgetPreviewDtdServices.kCapturePreview:
        if (captureError case final RpcException error) {
          throw error;
        }
        final CapturePreviewResponse response =
            captureResponse ??
            const CapturePreviewResponse(
              diagnostics: <PreviewDiagnostic>[],
              hasErrors: false,
              pixelRatio: 1.0,
              previewId: 'default',
              renderedHeight: 100.0,
              renderedWidth: 100.0,
            );
        return DTDResponse('1', CapturePreviewResponse.kTypeName, response.toJson());
      default:
        throw UnimplementedError('Unexpected DTD call: $serviceName.$methodName');
    }
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
    for (final StreamController<DTDEvent> controller in _eventControllers.values) {
      await controller.close();
    }
    if (closeError case final Exception error) {
      throw error;
    }
  }
}

class _RecordingBroadcastDtd extends Fake implements DartToolingDaemon {
  final postedEvents = <({String streamId, String eventKind, Map<String, Object?> eventData})>[];
  final _controllers = <String, StreamController<DTDEvent>>{};

  @override
  Future<RegisteredServicesResponse> getRegisteredServices() async =>
      RegisteredServicesResponse.fromDTDResponse(
        DTDResponse('1', RegisteredServicesResponse.type, <String, Object?>{
          'type': RegisteredServicesResponse.type,
          'dtdServices': <String>[],
          'clientServices': <Map<String, Object?>>[],
        }),
      );

  @override
  Future<void> registerService(
    String service,
    String method,
    DTDServiceCallback callback, {
    Map<String, Object?>? capabilities,
  }) async {}

  @override
  Future<void> streamListen(String streamId) async {}

  @override
  Stream<DTDEvent> onEvent(String streamId) =>
      _controllers.putIfAbsent(streamId, StreamController<DTDEvent>.broadcast).stream;

  @override
  Future<void> postEvent(String streamId, String eventKind, Map<String, Object?> eventData) async {
    postedEvents.add((streamId: streamId, eventKind: eventKind, eventData: eventData));
  }

  @override
  Future<void> close() async {
    for (final StreamController<DTDEvent> controller in _controllers.values) {
      await controller.close();
    }
  }
}

class _FakeWebPreviewDevice extends Fake implements Device {
  @override
  String get id => 'chrome';

  @override
  String get name => 'Chrome';

  @override
  String get displayName => 'Chrome';

  @override
  Future<TargetPlatform> get targetPlatform async => TargetPlatform.web_javascript;

  @override
  Future<bool> get isLocalEmulator async => false;

  @override
  DevFSWriter createDevFSWriter(ApplicationPackage? app, String? userIdentifier) =>
      throw UnimplementedError();
}

class _FakeCacheWithSdkVersion extends FakeCache {
  _FakeCacheWithSdkVersion({required super.fileSystem, required super.flutterRoot});

  @override
  String get dartSdkVersion => '0.0.0';
}

class _FakeAnalysisServer extends Fake implements AnalysisServer {
  @override
  Future<void> start() async {}

  @override
  Future<void> connectToDtd({required Uri dtdUri}) async {}

  @override
  Future<bool?> dispose() async => true;

  @override
  Future<void> waitForAnalysis({Duration delay = const Duration(milliseconds: 100)}) async {}
}

class _FakeWatcher extends Fake implements Watcher {
  @override
  Stream<WatchEvent> get events => const Stream<WatchEvent>.empty();

  @override
  Future<void> get ready => Future<void>.value();
}

class _FakeFlutterDevice extends Fake implements FlutterDevice {
  _FakeFlutterDevice({this.devFS});

  @override
  DevFS? devFS;
}

class _FakePrewarmLiveServer extends Fake implements WidgetPreviewLiveServer {
  int prewarmCount = 0;

  @override
  void prewarmBundle() {
    prewarmCount++;
  }
}

class _FakeWebAssetServer extends Fake implements WebAssetServer {
  _FakeWebAssetServer({required this.liveServer, required this.webMemoryFS});

  @override
  final WidgetPreviewLiveServer? liveServer;

  @override
  final WebMemoryFS webMemoryFS;
}

class _FakeWebDevFS extends Fake implements WebDevFS {
  _FakeWebDevFS({required this.webAssetServer});

  @override
  late WebAssetServer webAssetServer;
}

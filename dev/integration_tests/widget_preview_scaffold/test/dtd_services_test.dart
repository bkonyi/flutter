// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io'
    show
        HttpRequest,
        HttpServer,
        HttpStatus,
        Process,
        ProcessStartMode,
        WebSocket,
        WebSocketTransformer;

import 'package:dtd/dtd.dart';
import 'package:file/memory.dart';
import 'package:flutter/widgets.dart'
    show Brightness, Size, SizedBox, WidgetsFlutterBinding;
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/convert.dart';
import 'package:flutter_tools/src/dart/analysis.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/widget_preview/analytics.dart';
import 'package:flutter_tools/src/widget_preview/dtd_services.dart';
import 'package:flutter_tools/src/widget_preview/dtd_types.dart';
import 'package:flutter_tools/src/widget_preview/persistent_preferences.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:path/path.dart' as path;
import 'package:test/fake.dart';
import 'package:widget_preview_scaffold/src/dtd/dtd_services.dart';
import 'package:widget_preview_scaffold/src/utils/url/url.dart';
import 'package:widget_preview_scaffold/src/widget_preview.dart'
    as scaffold_preview;
import 'package:widget_preview_scaffold/src/widget_preview_scaffold_controller.dart';

import '../../../../packages/flutter_tools/test/src/common.dart';
import '../../../../packages/flutter_tools/test/src/fake_process_manager.dart'
    show ProcessManager;
import '../../../../packages/flutter_tools/test/src/fakes.dart';
import 'utils/widget_preview_scaffold_test_utils.dart'
    show makeTestErrorPreview, makeTestPreview;

const _kProjectRootPath = '/project';

class _LocalProcessManager extends Fake implements ProcessManager {
  @override
  Future<Process> start(
    List<Object> command, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) => Process.start(
    command.first.toString(),
    <String>[for (final Object arg in command.skip(1)) arg.toString()],
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
    runInShell: runInShell,
    mode: mode,
  );
}

class FakeFlutterProject extends Fake implements FlutterProject {}

class FakeAnalysisServer extends Fake implements AnalysisServer {
  @override
  Future<void> connectToDtd({required Uri dtdUri}) async {}
}

class _FakeDtdArtifacts extends Fake implements Artifacts {
  _FakeDtdArtifacts({required this.dartBinaryPath});

  final String dartBinaryPath;

  @override
  String getArtifactPath(
    Artifact artifact, {
    TargetPlatform? platform,
    BuildMode? mode,
    EnvironmentType? environmentType,
  }) {
    if (artifact == Artifact.engineDartBinary) {
      return dartBinaryPath;
    }
    throw UnimplementedError('Unexpected artifact: $artifact');
  }
}

String _resolveDartBinaryPath() {
  const Platform platform = LocalPlatform();
  final String flutterRoot = switch (platform.environment['FLUTTER_ROOT']) {
    final String root when root.isNotEmpty => root,
    _ => path.normalize(path.absolute('..', '..', '..')),
  };
  return path.join(
    flutterRoot,
    'bin',
    'cache',
    'dart-sdk',
    'bin',
    platform.isWindows ? 'dart.exe' : 'dart',
  );
}

void _stubDevToolsAddress(WidgetPreviewDtdServices server) {
  server.setDevToolsServerAddress(
    devToolsServerAddress: Uri.http('localhost:8282', 'devtools'),
    applicationUri: Uri(scheme: 'ws', host: 'localhost', port: 1234),
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  late WidgetPreviewDtdServices dtdServer;
  late Logger logger;
  WidgetPreviewScaffoldDtdServices? scaffoldDtd;

  setUp(() {
    logger = BufferLogger.test();
  });

  tearDown(() async {
    debugResetUrlTestState();
    await scaffoldDtd?.dtd.close();
    scaffoldDtd = null;
    await dtdServer.shutdownHooks.runShutdownHooks(logger);
  });

  Future<WidgetPreviewDtdServices> launchDtdServer({
    Future<void> Function()? onHotReloadPreviewer,
    void Function()? onHotRestartPreviewerRequest,
    Future<SyncPreviewsResponse> Function({required Duration timeout})?
    onSyncPreviews,
    Uri? Function()? webPreviewUriProvider,
  }) async {
    final server = WidgetPreviewDtdServices(
      addUuidToServiceName: false,
      dtdLauncher: DtdLauncher(
        artifacts: _FakeDtdArtifacts(dartBinaryPath: _resolveDartBinaryPath()),
        logger: logger,
        processManager: _LocalProcessManager(),
      ),
      fs: MemoryFileSystem.test(),
      logger: logger,
      onHotReloadPreviewer: onHotReloadPreviewer,
      onHotRestartPreviewerRequest: onHotRestartPreviewerRequest ?? () {},
      onSyncPreviews: onSyncPreviews,
      previewAnalytics: WidgetPreviewAnalytics(
        analytics: getInitializedFakeAnalyticsInstance(
          fs: MemoryFileSystem.test(),
          fakeFlutterVersion: FakeFlutterVersion(),
        ),
      ),
      project: FakeFlutterProject(),
      projectRootPath: _kProjectRootPath,
      shutdownHooks: ShutdownHooks(),
      webPreviewUriProvider: webPreviewUriProvider,
    );
    await server.launchAndConnect(analysisServer: FakeAnalysisServer());
    return server;
  }

  Future<WidgetPreviewScaffoldDtdServices> connectPrimaryScaffold() async {
    final dtd = WidgetPreviewScaffoldDtdServices();
    scaffoldDtd = dtd;
    await dtd.connect(dtdUri: dtdServer.dtdUri);
    return dtd;
  }

  group('$WidgetPreviewDtdServices', () {
    testWithoutContext(
      'handles ${WidgetPreviewDtdServices.kHotRestartPreviewer} and '
      '${WidgetPreviewDtdServices.kHotReloadPreviewer} invocations',
      () async {
        final hotRestartCompleter = Completer<void>();
        final hotReloadCompleter = Completer<void>();
        dtdServer = await launchDtdServer(
          onHotReloadPreviewer: () async => hotReloadCompleter.complete(),
          onHotRestartPreviewerRequest: hotRestartCompleter.complete,
        );

        final WidgetPreviewScaffoldDtdServices dtd =
            await connectPrimaryScaffold();
        expect(
          dtd.scaffoldServiceName,
          WidgetPreviewDtdServices.kWidgetPreviewScaffoldServiceRoot,
        );
        await dtd.hotRestartPreviewer();
        await hotRestartCompleter.future;
        await dtd.hotReloadPreviewer();
        await hotReloadCompleter.future;
      },
    );

    testWithoutContext(
      'handles ${WidgetPreviewDtdServices.kGetWebPreviewUrl} and '
      '${WidgetPreviewDtdServices.kGetServiceInfo} invocations',
      () async {
        Uri? currentWebUri;
        dtdServer = await launchDtdServer(
          webPreviewUriProvider: () => currentWebUri,
        );
        final WidgetPreviewScaffoldDtdServices dtd =
            await connectPrimaryScaffold();
        await dtdServer.waitForScaffoldConnected();

        expect(await dtd.getWebPreviewUrl(), isNull);

        final expectedWebUri = Uri.parse('http://127.0.0.1:8080');
        currentWebUri = expectedWebUri;
        expect(await dtd.getWebPreviewUrl(), expectedWebUri);

        final Map<String, Object?> info = (await dtd.getServiceInfo())!;
        expect(info[PreviewServiceInfo.kType], PreviewServiceInfo.kTypeName);
        expect(info[PreviewServiceInfo.kDtdUri], dtdServer.dtdUri.toString());
        expect(info[PreviewServiceInfo.kProjectRoot], _kProjectRootPath);
        expect(
          info[PreviewServiceInfo.kPreviewService],
          WidgetPreviewDtdServices.kWidgetPreviewServiceRoot,
        );
        expect(
          info[PreviewServiceInfo.kScaffoldService],
          WidgetPreviewDtdServices.kWidgetPreviewScaffoldServiceRoot,
        );
        expect(
          info[PreviewServiceInfo.kScaffoldStream],
          WidgetPreviewDtdServices.kWidgetPreviewScaffoldStreamRoot,
        );
        expect(
          info[PreviewServiceInfo.kWebPreviewUri],
          expectedWebUri.toString(),
        );
        expect(info[PreviewServiceInfo.kScaffoldConnected], isTrue);
      },
    );

    testWithoutContext(
      'handles ${WidgetPreviewDtdServices.kGetDevToolsUri} invocation',
      () async {
        dtdServer = await launchDtdServer();
        final WidgetPreviewScaffoldDtdServices dtd =
            await connectPrimaryScaffold();
        final Future<Uri> devToolsUriFuture = dtd.getDevToolsUri();
        _stubDevToolsAddress(dtdServer);
        expect(await devToolsUriFuture, await dtdServer.devToolsServerAddress);
      },
    );

    testWithoutContext(
      'can set and retrieve values from $PersistentPreferences',
      () async {
        dtdServer = await launchDtdServer();
        final File preferencesFile = dtdServer.preferences.file;
        expect(preferencesFile.existsSync(), isTrue);

        final WidgetPreviewScaffoldDtdServices dtd =
            await connectPrimaryScaffold();
        const kTestKey = 'myKey';
        const kFlagKey = 'flag';

        expect(await dtd.getPreference(kTestKey), isNull);
        expect(preferencesFile.readAsStringSync(), isEmpty);

        for (final String val in const <String>['foo', 'bar']) {
          await dtd.setPreference(kTestKey, val);
          expect(await dtd.getPreference(kTestKey), val);
          expect(
            json.decode(preferencesFile.readAsStringSync()),
            <String, Object?>{kTestKey: val},
          );
        }

        await dtd.setPreference(kFlagKey, true);
        expect(await dtd.getFlag(kFlagKey), isTrue);

        await dtd.setPreference(kTestKey, null);
        expect(await dtd.getPreference(kTestKey), isNull);
        expect(
          json.decode(preferencesFile.readAsStringSync()),
          <String, Object?>{kFlagKey: true},
        );
      },
    );

    testWithoutContext(
      'registers ${WidgetPreviewScaffoldDtdServices.kGetPreviews} on scaffold '
      'service and delegates ${WidgetPreviewDtdServices.kListPreviews} end-to-end',
      () async {
        var syncCalls = 0;
        dtdServer = await launchDtdServer(
          onSyncPreviews: ({required Duration timeout}) async {
            syncCalls++;
            return const SyncPreviewsResponse(
              compileSuccess: true,
              errorPreviewCount: 0,
              fullRestart: false,
              reloaded: true,
            );
          },
        );
        _stubDevToolsAddress(dtdServer);

        final dtd = WidgetPreviewScaffoldDtdServices();
        scaffoldDtd = dtd;
        final controller = WidgetPreviewScaffoldController(
          dtdServicesOverride: dtd,
          previews: () => <scaffold_preview.WidgetPreview>[
            makeTestPreview(
              brightness: Brightness.light,
              column: 5,
              fileStem: 'card',
              functionName: 'cardPreview',
              group: 'Cards',
              line: 12,
              name: 'Mobile Light',
              previewFunction: () => const SizedBox(),
              size: const Size(375, 667),
            ),
            makeTestErrorPreview(
              fileStem: 'broken',
              functionName: 'brokenPreview',
              line: 20,
            ),
          ],
        );

        await dtd.connect(dtdUri: dtdServer.dtdUri);
        await dtdServer.waitForScaffoldConnected();
        expect(controller.filterBySelectedFileListenable.value, isTrue);

        final PreviewListResponse allPreviews =
            PreviewListResponse.fromDTDResponse(
              await dtd.dtd.call(
                dtd.scaffoldServiceName,
                WidgetPreviewScaffoldDtdServices.kGetPreviews,
              ),
            );
        expect(allPreviews.previews, hasLength(2));
        expect(
          allPreviews.previews.first.id,
          'package:my_app/card.dart::cardPreview',
        );
        expect(allPreviews.previews.first.hasError, isFalse);
        expect(
          allPreviews.previews.last.id,
          'package:my_app/broken.dart::brokenPreview',
        );
        expect(allPreviews.previews.last.hasError, isTrue);
        expect(
          allPreviews.previews.last.errorMessage,
          'package:my_app/broken.dart has errors!',
        );

        final PreviewListResponse filteredList =
            PreviewListResponse.fromDTDResponse(
              await dtd.dtd.call(
                WidgetPreviewDtdServices.kWidgetPreviewServiceRoot,
                WidgetPreviewDtdServices.kListPreviews,
                params: <String, Object?>{
                  'fileUri': 'package:my_app/card.dart',
                },
              ),
            );
        expect(syncCalls, 1);
        expect(filteredList.previews, hasLength(1));
        expect(
          filteredList.previews.single.id,
          'package:my_app/card.dart::cardPreview',
        );
        expect(filteredList.previews.single.width, 375.0);
        expect(filteredList.previews.single.height, 667.0);
        expect(filteredList.previews.single.brightness, 'light');

        await dtd.dtd.call(
          WidgetPreviewDtdServices.kWidgetPreviewServiceRoot,
          WidgetPreviewDtdServices.kListPreviews,
          params: <String, Object?>{'sync': false},
        );
        expect(syncCalls, 1);
      },
    );

    testWithoutContext(
      'registers ${WidgetPreviewScaffoldDtdServices.kCapturePreview} on scaffold '
      'service and enforces wire schema and error codes over DTD',
      () async {
        dtdServer = await launchDtdServer();
        _stubDevToolsAddress(dtdServer);

        final dtd = WidgetPreviewScaffoldDtdServices();
        scaffoldDtd = dtd;
        final controller = WidgetPreviewScaffoldController(
          dtdServicesOverride: dtd,
          previews: () => <scaffold_preview.WidgetPreview>[
            makeTestPreview(
              fileStem: 'card',
              functionName: 'cardPreview',
              name: 'Mobile Light',
              previewFunction: () => const SizedBox(),
            ),
            makeTestPreview(
              fileStem: 'a',
              functionName: 'dupOne',
              name: 'Shared',
              previewFunction: () => const SizedBox(),
            ),
            makeTestPreview(
              fileStem: 'b',
              functionName: 'dupTwo',
              name: 'Shared',
              previewFunction: () => const SizedBox(),
            ),
            makeTestErrorPreview(
              fileStem: 'broken',
              functionName: 'brokenPreview',
            ),
          ],
        );

        scaffold_preview.PreviewCaptureRequest? lastRequest;
        controller.attachStageCaptureHost(({
          required scaffold_preview.WidgetPreview preview,
          required scaffold_preview.PreviewCaptureRequest request,
          required double resolvedPixelRatio,
        }) async {
          lastRequest = request;
          return scaffold_preview.CapturePreviewResponse(
            diagnostics: const <scaffold_preview.PreviewDiagnostic>[
              scaffold_preview.PreviewDiagnostic(
                kind: .overflow,
                overflowAxis: 'horizontal',
                overflowPixels: 48.0,
                overflowSide: 'right',
                phase: .paint,
                summary: 'A RenderFlex overflowed by 48 pixels on the right.',
                targetType: 'RenderFlex',
              ),
            ],
            hasErrors: true,
            imageBase64: request.includeImage ? 'iVBORw0KGgo=' : null,
            name: preview.name,
            pixelRatio: resolvedPixelRatio,
            previewId: preview.id,
            renderedHeight: request.height ?? 220.0,
            renderedWidth: request.width ?? 375.0,
          );
        });

        await dtd.connect(dtdUri: dtdServer.dtdUri);
        await dtdServer.waitForScaffoldConnected();

        final CapturePreviewResponse parsed =
            CapturePreviewResponse.fromDTDResponse(
              await dtd.dtd.call(
                dtd.scaffoldServiceName,
                WidgetPreviewScaffoldDtdServices.kCapturePreview,
                params: <String, Object?>{
                  'previewId': 'Mobile Light',
                  'width': 375,
                  'height': null,
                  'pixelRatio': null,
                  'brightness': 'dark',
                  'textScaleFactor': 1.5,
                  'includeImage': null,
                },
              ),
            );
        expect(parsed.previewId, 'package:my_app/card.dart::cardPreview');
        expect(parsed.name, 'Mobile Light');
        expect(parsed.renderedWidth, 375.0);
        expect(parsed.renderedHeight, 220.0);
        expect(parsed.pixelRatio, 1.0);
        expect(parsed.imageBase64, 'iVBORw0KGgo=');
        expect(parsed.hasErrors, isTrue);
        expect(
          parsed.diagnostics,
          equals(<PreviewDiagnostic>[
            const PreviewDiagnostic(
              kind: .overflow,
              overflowAxis: 'horizontal',
              overflowPixels: 48.0,
              overflowSide: 'right',
              phase: .paint,
              summary: 'A RenderFlex overflowed by 48 pixels on the right.',
              targetType: 'RenderFlex',
            ),
          ]),
        );
        expect(lastRequest!.brightness, Brightness.dark);
        expect(lastRequest!.textScaleFactor, 1.5);
        expect(lastRequest!.includeImage, isTrue);

        final CapturePreviewResponse brokenResponse =
            CapturePreviewResponse.fromDTDResponse(
              await dtd.dtd.call(
                dtd.scaffoldServiceName,
                WidgetPreviewScaffoldDtdServices.kCapturePreview,
                params: <String, Object?>{
                  'previewId': 'package:my_app/broken.dart::brokenPreview',
                },
              ),
            );
        expect(brokenResponse.hasErrors, isTrue);
        expect(brokenResponse.imageBase64, isNull);
        expect(
          brokenResponse.diagnostics.single.kind,
          PreviewDiagnosticKind.compileError,
        );

        for (final (Map<String, Object?> params, int expectedCode)
            in <(Map<String, Object?>, int)>[
              (
                <String, Object?>{'previewId': 'Unknown'},
                WidgetPreviewDtdServices.kPreviewNotFoundErrorCode,
              ),
              (
                <String, Object?>{'previewId': 'Shared'},
                WidgetPreviewDtdServices.kAmbiguousPreviewNameErrorCode,
              ),
              (
                <String, Object?>{
                  'previewId': 'Mobile Light',
                  'brightness': 'sepia',
                },
                RpcErrorCodes.kInvalidParams,
              ),
              (
                <String, Object?>{'previewId': 'Mobile Light', 'width': 0},
                RpcErrorCodes.kInvalidParams,
              ),
            ]) {
          await expectLater(
            dtd.dtd.call(
              dtd.scaffoldServiceName,
              WidgetPreviewScaffoldDtdServices.kCapturePreview,
              params: params,
            ),
            throwsA(
              isA<RpcException>().having(
                (RpcException e) => e.code,
                'code',
                expectedCode,
              ),
            ),
          );
        }
      },
    );

    testWithoutContext(
      'viewer-only readOnly connect skips service registration and Connected, and reloads on PreviewReloaded',
      () async {
        dtdServer = await launchDtdServer();
        _stubDevToolsAddress(dtdServer);

        final observerDtd = await DartToolingDaemon.connect(dtdServer.dtdUri!);
        addTearDown(observerDtd.close);
        final observedEvents = <DTDEvent>[];
        final StreamSubscription<DTDEvent> observerSub = observerDtd
            .onEvent(WidgetPreviewDtdServices.kWidgetPreviewScaffoldStreamRoot)
            .listen(observedEvents.add);
        addTearDown(observerSub.cancel);
        await observerDtd.streamListen(
          WidgetPreviewDtdServices.kWidgetPreviewScaffoldStreamRoot,
        );

        final primaryDtd = WidgetPreviewScaffoldDtdServices();
        scaffoldDtd = primaryDtd;
        WidgetPreviewScaffoldController(
          dtdServicesOverride: primaryDtd,
          previews: () => <scaffold_preview.WidgetPreview>[
            makeTestPreview(
              fileStem: 'card',
              functionName: 'primaryCard',
              name: 'Primary',
              previewFunction: () => const SizedBox(),
            ),
          ],
        );
        await primaryDtd.connect(dtdUri: dtdServer.dtdUri);
        await dtdServer.waitForScaffoldConnected();
        await pumpEventQueue();

        int countConnectedEvents() => observedEvents
            .where(
              (DTDEvent e) =>
                  e.kind ==
                  WidgetPreviewDtdServices.kWidgetPreviewConnectedEvent,
            )
            .length;
        expect(countConnectedEvents(), 1);

        debugSetUrlFragment(
          'embed=1&previewId=Primary&dtdProxy=/dtd_ws',
          baseUri: Uri.parse('https://preview.proxy.example:8443/'),
        );
        expect(
          EmbedPreviewParams.fromCurrentUrl().resolveDtdProxyUri(getBaseUri()),
          Uri.parse('wss://preview.proxy.example:8443/dtd_ws'),
        );

        var viewerReloadCallbacks = 0;
        final viewerDtd = WidgetPreviewScaffoldDtdServices(
          onPreviewReloaded: () => viewerReloadCallbacks++,
        );
        addTearDown(viewerDtd.dispose);
        await viewerDtd.connect(dtdUri: dtdServer.dtdUri, readOnly: true);
        await pumpEventQueue();
        expect(countConnectedEvents(), 1);

        final DTDResponse primaryList = await observerDtd.call(
          primaryDtd.scaffoldServiceName,
          WidgetPreviewScaffoldDtdServices.kGetPreviews,
        );
        expect(
          PreviewListResponse.fromDTDResponse(primaryList).previews,
          hasLength(1),
        );

        await dtdServer.postPreviewReloaded(fullRestart: false);
        await pumpEventQueue();
        expect(viewerReloadCallbacks, 1);

        final defaultViewerDtd = WidgetPreviewScaffoldDtdServices();
        addTearDown(defaultViewerDtd.dispose);
        await defaultViewerDtd.connect(dtdUri: dtdServer.dtdUri);
        await dtdServer.postPreviewReloaded(fullRestart: true);
        await pumpEventQueue();
        expect(viewerReloadCallbacks, 2);
        expect(debugReloadCount, 1);

        final List<DTDEvent> reloadedEvents = observedEvents
            .where(
              (DTDEvent e) =>
                  e.kind == WidgetPreviewDtdServices.kPreviewReloadedEvent,
            )
            .toList();
        expect(reloadedEvents, hasLength(2));
        expect(
          reloadedEvents.first.data[WidgetPreviewDtdServices.kFullRestart],
          isFalse,
        );
        expect(
          reloadedEvents.last.data[WidgetPreviewDtdServices.kFullRestart],
          isTrue,
        );

        await viewerDtd.dispose();
        await defaultViewerDtd.dispose();
        await dtdServer.postPreviewReloaded(fullRestart: false);
        await pumpEventQueue();
        expect(viewerReloadCallbacks, 2);
        expect(debugReloadCount, 1);
      },
    );

    testWithoutContext(
      'viewer-only mode hot-reloads modules in-place and refreshes controller without reloadWindow, falling back on fullRestart or error',
      () async {
        dtdServer = await launchDtdServer();
        _stubDevToolsAddress(dtdServer);

        debugSetUrlFragment(
          'embed=1&previewId=*',
          baseUri: Uri.parse('http://localhost:8080/live'),
        );
        var currentTitle = 'Before Reload';
        var serverRevision = 4;
        var shouldFailHotReload = false;
        final observedSinceRevisions = <int>[];

        debugSetInitialLiveRevision(serverRevision);
        debugSetHotReloadHandler((int sinceRevision) async {
          observedSinceRevisions.add(sinceRevision);
          return shouldFailHotReload ? null : serverRevision;
        });

        final viewerDtd = WidgetPreviewScaffoldDtdServices();
        addTearDown(viewerDtd.dispose);
        final controller = WidgetPreviewScaffoldController(
          dtdServicesOverride: viewerDtd,
          previews: () => <scaffold_preview.WidgetPreview>[
            makeTestPreview(
              fileStem: 'card',
              functionName: 'liveCard',
              name: currentTitle,
              previewFunction: () => const SizedBox(),
            ),
          ],
        );

        await viewerDtd.connect(dtdUri: dtdServer.dtdUri, readOnly: true);
        expect(controller.previews.single.name, 'Before Reload');

        for (final (String nextTitle, int nextRev, int expectedRevCount)
            in const <(String, int, int)>[
              ('After In-Place Reload', 5, 1),
              ('Second In-Place Reload', 6, 2),
            ]) {
          currentTitle = nextTitle;
          serverRevision = nextRev;
          await dtdServer.postPreviewReloaded(fullRestart: false);
          await pumpEventQueue();
          expect(debugHotReloadCount, expectedRevCount);
          expect(debugReloadCount, 0);
          expect(controller.previewsRevisionListenable.value, expectedRevCount);
          expect(controller.previews.single.name, nextTitle);
        }
        expect(observedSinceRevisions, <int>[4, 5]);

        await dtdServer.postPreviewReloaded(fullRestart: true);
        await pumpEventQueue();
        expect(debugHotReloadCount, 2);
        expect(debugReloadCount, 1);

        shouldFailHotReload = true;
        await dtdServer.postPreviewReloaded(fullRestart: false);
        await pumpEventQueue();
        expect(observedSinceRevisions, <int>[4, 5, 6]);
        expect(debugHotReloadCount, 3);
        expect(debugReloadCount, 2);
      },
    );

    test('viewer-only mode reconnects when DTD connection drops', () async {
      final fakeDtd = await _startFakeDtdServer();
      final viewerDtd = WidgetPreviewScaffoldDtdServices();
      addTearDown(viewerDtd.dispose);
      await viewerDtd.connect(dtdUri: fakeDtd.uri, readOnly: true);
      await fakeDtd.firstSocket()!.close();
      await fakeDtd.secondConnected.future.timeout(const Duration(seconds: 5));
      expect(fakeDtd.connectionCount(), 2);
      expect(debugReloadCount, 0);
    });

    test(
      'viewer-only mode catches up missed revisions on reconnect without reloading when unchanged',
      () async {
        final fakeDtd = await _startFakeDtdServer();
        var serverRevision = 4;
        var inPlaceHotReloads = 0;
        final observedSinceRevisions = <int>[];
        debugSetInitialLiveRevision(serverRevision);
        debugSetHotReloadHandler((int sinceRevision) async {
          observedSinceRevisions.add(sinceRevision);
          return serverRevision;
        });

        final viewerDtd = WidgetPreviewScaffoldDtdServices(
          onInPlaceHotReload: () => inPlaceHotReloads++,
        );
        addTearDown(viewerDtd.dispose);
        await viewerDtd.connect(dtdUri: fakeDtd.uri, readOnly: true);

        // Simulate edits happening while the WebSocket was disconnected.
        serverRevision = 6;
        await fakeDtd.latestSocket()!.close();
        await fakeDtd.secondConnected.future.timeout(
          const Duration(seconds: 5),
        );
        await pumpEventQueue();
        expect(observedSinceRevisions, <int>[4]);
        expect(inPlaceHotReloads, 1);
        expect(debugReloadCount, 0);

        // A reconnect with no missed revisions is a no-op (no reassemble/reload).
        final thirdConnected = Completer<void>();
        fakeDtd.setOnConnection(() {
          if (fakeDtd.connectionCount() == 3 && !thirdConnected.isCompleted) {
            thirdConnected.complete();
          }
        });
        await fakeDtd.latestSocket()!.close();
        await thirdConnected.future.timeout(const Duration(seconds: 5));
        await pumpEventQueue();
        expect(observedSinceRevisions, <int>[4, 6]);
        expect(inPlaceHotReloads, 1);
        expect(debugReloadCount, 0);
      },
    );

    test(
      'viewer-only mode reloads window instead of looping when streamListen is rejected after daemon restart',
      () async {
        var rejectStreamListen = false;
        final fakeDtd = await _startFakeDtdServer(
          shouldRejectStreamListen: () => rejectStreamListen,
        );
        final reloadTriggered = Completer<void>();
        debugSetReloadHandler(() {
          if (!reloadTriggered.isCompleted) {
            reloadTriggered.complete();
          }
        });
        final viewerDtd = WidgetPreviewScaffoldDtdServices();
        addTearDown(viewerDtd.dispose);
        await viewerDtd.connect(dtdUri: fakeDtd.uri, readOnly: true);

        rejectStreamListen = true;
        await fakeDtd.firstSocket()!.close();
        await reloadTriggered.future.timeout(const Duration(seconds: 5));
        expect(debugReloadCount, 1);
        expect(fakeDtd.connectionCount(), 2);

        // Wait past the 1s initial backoff to confirm no reconnect loop runs.
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        expect(fakeDtd.connectionCount(), 2);
      },
    );

    test(
      'viewer-only mode schedules reconnect when initial connect fails transiently',
      () async {
        var rejectNextConnect = true;
        final fakeDtd = await _startFakeDtdServer(
          shouldRejectUpgrade: () => rejectNextConnect,
        );
        final connected = Completer<void>();
        fakeDtd.setOnConnection(() {
          if (!connected.isCompleted) {
            connected.complete();
          }
        });
        final viewerDtd = WidgetPreviewScaffoldDtdServices();
        addTearDown(viewerDtd.dispose);

        await viewerDtd.connect(dtdUri: fakeDtd.uri, readOnly: true);
        expect(fakeDtd.connectionCount(), 0);

        rejectNextConnect = false;
        await connected.future.timeout(const Duration(seconds: 5));
        expect(fakeDtd.connectionCount(), 1);
      },
    );

    test('dispose cancels pending viewer-only reconnect timer', () async {
      final fakeDtd = await _startFakeDtdServer();
      final viewerDtd = WidgetPreviewScaffoldDtdServices();
      await viewerDtd.connect(dtdUri: fakeDtd.uri, readOnly: true);
      await fakeDtd.firstSocket()!.close();
      await pumpEventQueue();
      await viewerDtd.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(fakeDtd.connectionCount(), 1);
    });
  });
}

Future<
  ({
    Uri uri,
    WebSocket? Function() firstSocket,
    WebSocket? Function() latestSocket,
    int Function() connectionCount,
    Completer<void> secondConnected,
    void Function(void Function()? callback) setOnConnection,
  })
>
_startFakeDtdServer({
  bool Function()? shouldRejectStreamListen,
  bool Function()? shouldRejectUpgrade,
}) async {
  var connections = 0;
  final secondConnected = Completer<void>();
  WebSocket? firstSocket;
  WebSocket? latestSocket;
  void Function()? onConnection;
  final HttpServer server = await HttpServer.bind('127.0.0.1', 0);
  addTearDown(() async {
    await firstSocket?.close();
    await latestSocket?.close();
    await server.close(force: true);
  });
  server.listen((HttpRequest request) async {
    if (shouldRejectUpgrade?.call() ?? false) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }
    final WebSocket ws = await WebSocketTransformer.upgrade(request);
    connections++;
    if (connections == 1) {
      firstSocket = ws;
    } else if (!secondConnected.isCompleted) {
      secondConnected.complete();
    }
    latestSocket = ws;
    onConnection?.call();
    ws.listen((Object? raw) {
      final Object? decoded = jsonDecode(raw! as String);
      if (decoded is Map<String, Object?> && decoded.containsKey('id')) {
        if ((shouldRejectStreamListen?.call() ?? false) &&
            decoded['method'] == 'streamListen') {
          ws.add(
            jsonEncode(<String, Object?>{
              'jsonrpc': '2.0',
              'id': decoded['id'],
              'error': <String, Object?>{
                'code': RpcErrorCodes.kMethodNotFound,
                'message':
                    'Stream "streamListen" is not allowed on this endpoint.',
              },
            }),
          );
          return;
        }
        ws.add(
          jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': decoded['id'],
            'result': <String, Object?>{'type': 'Success'},
          }),
        );
      }
    });
  });
  return (
    uri: Uri.parse('ws://127.0.0.1:${server.port}'),
    firstSocket: () => firstSocket,
    latestSocket: () => latestSocket,
    connectionCount: () => connections,
    secondConnected: secondConnected,
    setOnConnection: (void Function()? callback) => onConnection = callback,
  );
}

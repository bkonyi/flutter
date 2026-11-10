// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io' show Process, ProcessStartMode;

import 'package:dtd/dtd.dart';
import 'package:file/memory.dart';
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
import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart' show Brightness, Size, SizedBox;
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:path/path.dart' as path;
import 'package:test/fake.dart';
import 'package:widget_preview_scaffold/src/dtd/dtd_services.dart';
import 'package:widget_preview_scaffold/src/utils.dart';
import 'package:widget_preview_scaffold/src/utils/url/url.dart';
import 'package:widget_preview_scaffold/src/widget_preview.dart'
    as scaffold_preview;
import 'package:widget_preview_scaffold/src/widget_preview_scaffold_controller.dart';

import '../../../../packages/flutter_tools/test/src/common.dart';
import '../../../../packages/flutter_tools/test/src/fake_process_manager.dart'
    show ProcessManager;
import '../../../../packages/flutter_tools/test/src/fakes.dart';

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
  }) {
    return Process.start(
      command.first.toString(),
      <String>[for (final Object arg in command.skip(1)) arg.toString()],
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: runInShell,
      mode: mode,
    );
  }
}

class FakeFlutterProject extends Fake implements FlutterProject {
  FakeFlutterProject();
}

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
  final String dartBinaryName = platform.isWindows ? 'dart.exe' : 'dart';
  return path.join(
    flutterRoot,
    'bin',
    'cache',
    'dart-sdk',
    'bin',
    dartBinaryName,
  );
}

void main() {
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
          // We don't care about anything written to the file system by analytics, so we're safe
          // to use a different file system here.
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

  group('$WidgetPreviewDtdServices', () {
    testWithoutContext(
      'handles ${WidgetPreviewDtdServices.kHotRestartPreviewer} and '
      '${WidgetPreviewDtdServices.kHotReloadPreviewer} invocations',
      () async {
        final hotRestartRequestCompleter = Completer<void>();
        final hotReloadRequestCompleter = Completer<void>();
        dtdServer = await launchDtdServer(
          onHotReloadPreviewer: () async {
            hotReloadRequestCompleter.complete();
          },
          onHotRestartPreviewerRequest: hotRestartRequestCompleter.complete,
        );

        final dtd = WidgetPreviewScaffoldDtdServices();
        scaffoldDtd = dtd;
        expect(
          dtd.scaffoldServiceName,
          WidgetPreviewDtdServices.kWidgetPreviewScaffoldServiceRoot,
        );
        await dtd.connect(dtdUri: dtdServer.dtdUri);

        await dtd.hotRestartPreviewer();
        await hotRestartRequestCompleter.future;

        await dtd.hotReloadPreviewer();
        await hotReloadRequestCompleter.future;
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

        final dtd = WidgetPreviewScaffoldDtdServices();
        scaffoldDtd = dtd;
        await dtd.connect(dtdUri: dtdServer.dtdUri);
        await dtdServer.waitForScaffoldConnected();

        // Returns null when web preview URL is unavailable (kNoValueForKey).
        expect(await dtd.getWebPreviewUrl(), isNull);

        // Returns active web preview Uri once available.
        final expectedWebUri = Uri.parse('http://127.0.0.1:8080');
        currentWebUri = expectedWebUri;
        expect(await dtd.getWebPreviewUrl(), expectedWebUri);

        final Map<String, Object?>? info = await dtd.getServiceInfo();
        expect(info, isNotNull);
        expect(info![PreviewServiceInfo.kType], PreviewServiceInfo.kTypeName);
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
        // Start DTD and register the widget preview DTD services.
        dtdServer = await launchDtdServer();

        // Connect to the DTD instance and invoke the getDevToolsUri endpoint.
        final dtd = WidgetPreviewScaffoldDtdServices();
        scaffoldDtd = dtd;
        await dtd.connect(dtdUri: dtdServer.dtdUri);

        final Future<Uri> devToolsUriResponseFuture = dtd.getDevToolsUri();

        dtdServer.setDevToolsServerAddress(
          devToolsServerAddress: Uri.http('localhost:8282', 'devtools'),
          applicationUri: Uri(scheme: 'ws', host: 'localhost', port: 1234),
        );
        final Uri actualDevToolsUri = await dtdServer.devToolsServerAddress;
        expect(await devToolsUriResponseFuture, actualDevToolsUri);
      },
    );

    testWithoutContext(
      'can set and retrieve values from $PersistentPreferences',
      () async {
        dtdServer = await launchDtdServer();

        // The properties file should be created by the PersistentProperties constructor.
        final File preferencesFile = dtdServer.preferences.file;
        expect(preferencesFile.existsSync(), true);

        // Connect to the DTD instance.
        final dtd = WidgetPreviewScaffoldDtdServices();
        scaffoldDtd = dtd;
        await dtd.connect(dtdUri: dtdServer.dtdUri);

        const kTestKey = 'myKey';

        // The preferences file should be empty.
        expect(await dtd.getPreference(kTestKey), null);
        expect(preferencesFile.readAsStringSync(), isEmpty);

        // Set a preference and ensure it's read back.
        const kFirstValue = 'foo';
        await dtd.setPreference(kTestKey, kFirstValue);
        expect(await dtd.getPreference(kTestKey), kFirstValue);
        expect(
          json.decode(preferencesFile.readAsStringSync()),
          <String, Object?>{kTestKey: kFirstValue},
        );

        // Overwrite kTestKey and ensure it's read back.
        const kSecondValue = 'bar';
        await dtd.setPreference(kTestKey, kSecondValue);
        expect(await dtd.getPreference(kTestKey), kSecondValue);
        expect(
          json.decode(preferencesFile.readAsStringSync()),
          <String, Object?>{kTestKey: kSecondValue},
        );

        // Write a flag.
        const kFlagKey = 'flag';
        await dtd.setPreference(kFlagKey, true);
        expect(await dtd.getFlag(kFlagKey), true);
        expect(
          json.decode(preferencesFile.readAsStringSync()),
          <String, Object?>{kFlagKey: true, kTestKey: kSecondValue},
        );

        // Remove an entry.
        await dtd.setPreference(kTestKey, null);
        expect(await dtd.getPreference(kTestKey), null);
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
        dtdServer.setDevToolsServerAddress(
          devToolsServerAddress: Uri.http('localhost:8282', 'devtools'),
          applicationUri: Uri(scheme: 'ws', host: 'localhost', port: 1234),
        );

        final dtd = WidgetPreviewScaffoldDtdServices();
        scaffoldDtd = dtd;
        final controller = WidgetPreviewScaffoldController(
          dtdServicesOverride: dtd,
          previews: () => <scaffold_preview.WidgetPreview>[
            buildWidgetPreview(
              column: 5,
              functionName: 'cardPreview',
              libraryUri: 'package:my_app/card.dart',
              line: 12,
              packageName: 'my_app',
              previewFunction: () => const SizedBox(),
              scriptUri: 'file:///project/lib/card.dart',
              transformedPreview: const Preview(
                brightness: Brightness.light,
                group: 'Cards',
                name: 'Mobile Light',
                size: Size(375, 667),
              ),
            ),
            buildWidgetPreviewError(
              column: 1,
              dependencyHasErrors: false,
              functionName: 'brokenPreview',
              libraryUri: 'package:my_app/broken.dart',
              line: 20,
              packageName: 'my_app',
              scriptUri: 'file:///project/lib/broken.dart',
            ),
          ],
        );

        await dtd.connect(dtdUri: dtdServer.dtdUri);
        await dtdServer.waitForScaffoldConnected();

        // Direct scaffold getPreviews call over DTD (ignoring UI selected-file filter).
        expect(controller.filterBySelectedFileListenable.value, isTrue);
        final scaffoldResponse = await dtd.dtd.call(
          dtd.scaffoldServiceName,
          WidgetPreviewScaffoldDtdServices.kGetPreviews,
        );
        final allPreviews = PreviewListResponse.fromDTDResponse(
          scaffoldResponse,
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

        // Tool listPreviews call over DTD (syncs by default and forwards fileUri).
        final filteredToolResponse = await dtd.dtd.call(
          WidgetPreviewDtdServices.kWidgetPreviewServiceRoot,
          WidgetPreviewDtdServices.kListPreviews,
          params: <String, Object?>{'fileUri': 'package:my_app/card.dart'},
        );
        expect(syncCalls, 1);
        final filteredList = PreviewListResponse.fromDTDResponse(
          filteredToolResponse,
        );
        expect(filteredList.previews, hasLength(1));
        expect(
          filteredList.previews.single.id,
          'package:my_app/card.dart::cardPreview',
        );
        expect(filteredList.previews.single.width, 375.0);
        expect(filteredList.previews.single.height, 667.0);
        expect(filteredList.previews.single.brightness, 'light');

        // sync: false skips onSyncPreviews.
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
        dtdServer.setDevToolsServerAddress(
          devToolsServerAddress: Uri.http('localhost:8282', 'devtools'),
          applicationUri: Uri(scheme: 'ws', host: 'localhost', port: 1234),
        );

        final dtd = WidgetPreviewScaffoldDtdServices();
        scaffoldDtd = dtd;
        final controller = WidgetPreviewScaffoldController(
          dtdServicesOverride: dtd,
          previews: () => <scaffold_preview.WidgetPreview>[
            buildWidgetPreview(
              column: 5,
              functionName: 'cardPreview',
              libraryUri: 'package:my_app/card.dart',
              line: 12,
              packageName: 'my_app',
              previewFunction: () => const SizedBox(),
              scriptUri: 'file:///project/lib/card.dart',
              transformedPreview: const Preview(name: 'Mobile Light'),
            ),
            buildWidgetPreview(
              column: 1,
              functionName: 'dupOne',
              libraryUri: 'package:my_app/a.dart',
              line: 20,
              packageName: 'my_app',
              previewFunction: () => const SizedBox(),
              scriptUri: 'file:///project/lib/a.dart',
              transformedPreview: const Preview(name: 'Shared'),
            ),
            buildWidgetPreview(
              column: 1,
              functionName: 'dupTwo',
              libraryUri: 'package:my_app/b.dart',
              line: 30,
              packageName: 'my_app',
              previewFunction: () => const SizedBox(),
              scriptUri: 'file:///project/lib/b.dart',
              transformedPreview: const Preview(name: 'Shared'),
            ),
            buildWidgetPreviewError(
              column: 1,
              dependencyHasErrors: false,
              functionName: 'brokenPreview',
              libraryUri: 'package:my_app/broken.dart',
              line: 40,
              packageName: 'my_app',
              scriptUri: 'file:///project/lib/broken.dart',
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

        // Explicit null optional parameters and integer numbers decode cleanly.
        final dtdResponse = await dtd.dtd.call(
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
        );
        final parsed = CapturePreviewResponse.fromDTDResponse(dtdResponse);
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

        // Compile-error preview short-circuits with compile_error diagnostic.
        final brokenResponse = CapturePreviewResponse.fromDTDResponse(
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

        // Error 101 on unknown preview and 102 on ambiguous name.
        await expectLater(
          dtd.dtd.call(
            dtd.scaffoldServiceName,
            WidgetPreviewScaffoldDtdServices.kCapturePreview,
            params: <String, Object?>{'previewId': 'Unknown'},
          ),
          throwsA(
            isA<RpcException>().having(
              (RpcException e) => e.code,
              'code',
              WidgetPreviewDtdServices.kPreviewNotFoundErrorCode,
            ),
          ),
        );
        await expectLater(
          dtd.dtd.call(
            dtd.scaffoldServiceName,
            WidgetPreviewScaffoldDtdServices.kCapturePreview,
            params: <String, Object?>{'previewId': 'Shared'},
          ),
          throwsA(
            isA<RpcException>().having(
              (RpcException e) => e.code,
              'code',
              WidgetPreviewDtdServices.kAmbiguousPreviewNameErrorCode,
            ),
          ),
        );

        // Invalid parameters throw -32602 (RpcErrorCodes.kInvalidParams).
        await expectLater(
          dtd.dtd.call(
            dtd.scaffoldServiceName,
            WidgetPreviewScaffoldDtdServices.kCapturePreview,
            params: <String, Object?>{
              'previewId': 'Mobile Light',
              'brightness': 'sepia',
            },
          ),
          throwsA(
            isA<RpcException>().having(
              (RpcException e) => e.code,
              'code',
              RpcErrorCodes.kInvalidParams,
            ),
          ),
        );
        await expectLater(
          dtd.dtd.call(
            dtd.scaffoldServiceName,
            WidgetPreviewScaffoldDtdServices.kCapturePreview,
            params: <String, Object?>{'previewId': 'Mobile Light', 'width': 0},
          ),
          throwsA(
            isA<RpcException>().having(
              (RpcException e) => e.code,
              'code',
              RpcErrorCodes.kInvalidParams,
            ),
          ),
        );
      },
    );

    testWithoutContext(
      'viewer-only readOnly connect skips service registration and Connected, and reloads on PreviewReloaded',
      () async {
        dtdServer = await launchDtdServer();
        dtdServer.setDevToolsServerAddress(
          devToolsServerAddress: Uri.http('localhost:8282', 'devtools'),
          applicationUri: Uri(scheme: 'ws', host: 'localhost', port: 1234),
        );

        // Observe all events posted to WidgetPreviewScaffold stream.
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

        // Connect primary scaffold normally so PreviewScaffold methods exist.
        final primaryDtd = WidgetPreviewScaffoldDtdServices();
        scaffoldDtd = primaryDtd;
        WidgetPreviewScaffoldController(
          dtdServicesOverride: primaryDtd,
          previews: () => <scaffold_preview.WidgetPreview>[
            buildWidgetPreview(
              column: 1,
              functionName: 'primaryCard',
              libraryUri: 'package:my_app/card.dart',
              line: 10,
              packageName: 'my_app',
              previewFunction: () => const SizedBox(),
              scriptUri: 'file:///project/lib/card.dart',
              transformedPreview: const Preview(name: 'Primary'),
            ),
          ],
        );
        await primaryDtd.connect(dtdUri: dtdServer.dtdUri);
        await dtdServer.waitForScaffoldConnected();
        await pumpEventQueue();
        expect(
          observedEvents
              .where(
                (DTDEvent e) =>
                    e.kind ==
                    WidgetPreviewDtdServices.kWidgetPreviewConnectedEvent,
              )
              .length,
          1,
        );

        // Connect a second viewer-only client via embed=1 URL fragment and
        // explicit readOnly: true without colliding on PreviewScaffold RPCs.
        debugSetUrlFragment(
          'embed=1&previewId=Primary&dtdProxy=/dtd_ws',
          baseUri: Uri.parse('https://preview.proxy.example:8443/'),
        );
        final EmbedPreviewParams parsed = EmbedPreviewParams.fromCurrentUrl();
        expect(parsed.isEmbed, isTrue);
        expect(
          parsed.resolveDtdProxyUri(getBaseUri()),
          Uri.parse('wss://preview.proxy.example:8443/dtd_ws'),
        );

        var viewerReloadCallbacks = 0;
        final viewerDtd = WidgetPreviewScaffoldDtdServices(
          onPreviewReloaded: () => viewerReloadCallbacks++,
        );
        addTearDown(viewerDtd.dispose);
        await viewerDtd.connect(dtdUri: dtdServer.dtdUri, readOnly: true);
        await pumpEventQueue();

        // No second Connected event was posted by the viewer-only client.
        expect(
          observedEvents
              .where(
                (DTDEvent e) =>
                    e.kind ==
                    WidgetPreviewDtdServices.kWidgetPreviewConnectedEvent,
              )
              .length,
          1,
        );

        // Primary scaffold RPCs continue routing cleanly without collision.
        final DTDResponse primaryList = await observerDtd.call(
          primaryDtd.scaffoldServiceName,
          WidgetPreviewScaffoldDtdServices.kGetPreviews,
        );
        expect(
          PreviewListResponse.fromDTDResponse(primaryList).previews,
          hasLength(1),
        );

        // Broadcasting PreviewReloaded triggers reload only on the viewer client.
        await dtdServer.postPreviewReloaded(fullRestart: false);
        await pumpEventQueue();
        expect(viewerReloadCallbacks, 1);

        // Default viewer without onPreviewReloaded triggers reloadWindow().
        final defaultViewerDtd = WidgetPreviewScaffoldDtdServices();
        addTearDown(defaultViewerDtd.dispose);
        await defaultViewerDtd.connect(dtdUri: dtdServer.dtdUri);
        await dtdServer.postPreviewReloaded(fullRestart: true);
        await pumpEventQueue();
        expect(viewerReloadCallbacks, 2);
        expect(debugReloadCount, 1);

        // Verify PreviewReloaded payload data was preserved on the stream.
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

        // Disposal unsubscribes from further PreviewReloaded events.
        await viewerDtd.dispose();
        await defaultViewerDtd.dispose();
        await dtdServer.postPreviewReloaded(fullRestart: false);
        await pumpEventQueue();
        expect(viewerReloadCallbacks, 2);
        expect(debugReloadCount, 1);
      },
    );
  });
}

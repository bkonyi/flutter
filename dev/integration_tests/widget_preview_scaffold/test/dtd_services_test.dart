// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io' show Process, ProcessStartMode;

import 'package:file/memory.dart';
import 'package:flutter/widget_previews.dart' show Preview;
import 'package:flutter/widgets.dart'
    show Brightness, Size, SizedBox, Text, WidgetsFlutterBinding;
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
import 'package:path/path.dart' as path;
import 'package:test/fake.dart';
import 'package:widget_preview_scaffold/src/dtd/dtd_services.dart';
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
            scaffold_preview.WidgetPreview.test(
              builder: () => const SizedBox(),
              column: 5,
              functionName: 'cardPreview',
              libraryUri: 'package:my_app/card.dart',
              line: 12,
              packageName: 'my_app',
              previewData: const Preview(
                brightness: Brightness.light,
                group: 'Cards',
                name: 'Mobile Light',
                size: Size(375, 667),
              ),
              scriptUri: 'file:///my_app/lib/card.dart',
            ),
            scaffold_preview.WidgetPreview.test(
              builder: () => const Text('broken'),
              column: 1,
              errorMessage: 'package:my_app/broken.dart has errors!',
              functionName: 'brokenPreview',
              hasError: true,
              libraryUri: 'package:my_app/broken.dart',
              line: 20,
              packageName: 'my_app',
              previewData: const Preview(group: 'Invalid Previews'),
              scriptUri: 'file:///my_app/lib/broken.dart',
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
  });
}

// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:dtd/dtd.dart';
import 'package:file/memory.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/widget_preview/analytics.dart';
import 'package:flutter_tools/src/widget_preview/dtd_services.dart';
import 'package:flutter_tools/src/widget_preview/dtd_types.dart';
import 'package:json_rpc_2/error_code.dart' as error_code;
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:test/fake.dart';
import 'package:unified_analytics/unified_analytics.dart';

import '../../../src/common.dart';
import '../../../src/fake_process_manager.dart';
import '../../../src/fakes.dart';

class FakeWidgetPreviewAnalytics extends Fake implements WidgetPreviewAnalytics {
  int reportPreviewerConnectedCount = 0;

  @override
  void reportPreviewerConnected({String? mode}) {
    reportPreviewerConnectedCount++;
  }
}

class FakeDtdLauncher extends Fake implements DtdLauncher {
  @override
  Future<void> dispose() async {}
}

RegisteredServicesResponse _lspServicesResponse(Iterable<String> methods) {
  return RegisteredServicesResponse.fromDTDResponse(
    DTDResponse('1', RegisteredServicesResponse.type, <String, Object?>{
      'type': RegisteredServicesResponse.type,
      'dtdServices': <String>[],
      'clientServices': <Map<String, Object?>>[
        <String, Object?>{
          'name': WidgetPreviewDtdServices.kLspStream,
          'methods': <Map<String, Object?>>[
            for (final String method in methods) <String, Object?>{'name': method},
          ],
        },
      ],
    }),
  );
}

class FakeDartToolingDaemon extends Fake implements DartToolingDaemon {
  final postedEvents = <({String streamId, String eventKind, Map<String, Object?> eventData})>[];
  final registeredMethods = <String, Map<String, DTDServiceCallback>>{};
  final _eventControllers = <String, StreamController<DTDEvent>>{};
  final subscribedStreams = <String>{};
  int getRegisteredServicesCallCount = 0;
  int streamListenCallCount = 0;
  int streamCancelCallCount = 0;
  int waitForAnalysisCallCount = 0;
  RegisteredServicesResponse registeredServicesResponse = const RegisteredServicesResponse(
    clientServices: [],
    dtdServices: <String>[],
  );
  RpcException? streamListenError;
  Exception? postEventException;
  Error? postEventError;
  Future<DTDResponse> Function(
    String? serviceName,
    String methodName,
    Map<String, Object?>? params,
  )?
  onCall;
  FlutterWidgetPreviews? lspPreviewsResponse;

  bool hasListener(String streamId) => _eventControllers[streamId]?.hasListener ?? false;

  @override
  Future<void> registerService(
    String service,
    String method,
    DTDServiceCallback callback, {
    Map<String, Object?>? capabilities,
  }) async {
    registeredMethods.putIfAbsent(service, () => <String, DTDServiceCallback>{})[method] = callback;
  }

  @override
  Future<void> postEvent(String streamId, String eventKind, Map<String, Object?> eventData) async {
    if (postEventException case final Exception error) {
      throw error;
    }
    if (postEventError case final Error error) {
      throw error;
    }
    postedEvents.add((streamId: streamId, eventKind: eventKind, eventData: eventData));
  }

  @override
  Future<void> streamListen(String streamId) async {
    streamListenCallCount++;
    if (streamListenError case final RpcException error) {
      throw error;
    }
    if (subscribedStreams.contains(streamId)) {
      throw RpcException(RpcErrorCodes.kStreamAlreadySubscribed, 'Stream already subscribed');
    }
    subscribedStreams.add(streamId);
  }

  @override
  Future<void> streamCancel(String streamId) async {
    streamCancelCallCount++;
    if (!subscribedStreams.contains(streamId)) {
      throw RpcException(RpcErrorCodes.kStreamNotSubscribed, 'Stream not subscribed');
    }
    subscribedStreams.remove(streamId);
  }

  @override
  Stream<DTDEvent> onEvent(String streamId) =>
      _eventControllers.putIfAbsent(streamId, StreamController<DTDEvent>.broadcast).stream;

  void postFakeEvent(String streamId, String eventKind, Map<String, Object?> eventData) {
    _eventControllers[streamId]?.add(DTDEvent(streamId, eventKind, eventData, 0));
  }

  @override
  Future<RegisteredServicesResponse> getRegisteredServices() async {
    getRegisteredServicesCallCount++;
    return registeredServicesResponse;
  }

  @override
  Future<DTDResponse> call(
    String? serviceName,
    String methodName, {
    Map<String, Object?>? params,
  }) async {
    if (onCall case final handler?) {
      return handler(serviceName, methodName, params);
    }
    if (serviceName == WidgetPreviewDtdServices.kLspStream &&
        (methodName == WidgetPreviewDtdServices.kGetFlutterWidgetPreviewsMethod ||
            methodName == WidgetPreviewDtdServices.kGetFlutterWidgetPreviewsForFileMethod)) {
      return DTDResponse('1', 'result', <String, Object?>{
        'result':
            lspPreviewsResponse?.toJson() ??
            <String, Object?>{
              'namespaces': <String, String>{},
              'previews': <Map<String, Object?>>[],
              'scriptUris': <String>[],
            },
      });
    }
    if (serviceName == WidgetPreviewDtdServices.kLspStream &&
        methodName == WidgetPreviewDtdServices.kWorkspaceAnalysisCompleteMethod) {
      waitForAnalysisCallCount++;
      return DTDResponse('1', 'Null', <String, Object?>{'type': 'Null', 'result': null});
    }
    throw UnimplementedError('Unexpected call: $serviceName.$methodName');
  }

  @override
  Future<void> close() async {
    for (final StreamController<DTDEvent> controller in _eventControllers.values) {
      await controller.close();
    }
  }
}

DTDServiceCallback _callbackFor(WidgetPreviewDtdServices services, String method) {
  for (final (String name, DTDServiceCallback callback) in services.services) {
    if (name == method) {
      return callback;
    }
  }
  fail('Expected service method "$method" to be registered.');
}

Matcher _throwsRpcCode(int code) =>
    throwsA(isA<RpcException>().having((RpcException e) => e.code, 'code', code));

void main() {
  group('DTD Types', () {
    testWithoutContext('WebPreviewUrlResult and PreviewServiceInfo round-trip and equality', () {
      final urlResult = WebPreviewUrlResult(
        host: '127.0.0.1',
        port: 8080,
        url: 'http://127.0.0.1:8080',
      );
      final Map<String, Object?> urlJson = urlResult.toJson();
      expect(urlJson[WebPreviewUrlResult.kType], WebPreviewUrlResult.kTypeName);
      final deserializedUrl = WebPreviewUrlResult.fromDTDResponse(
        DTDResponse('1', WebPreviewUrlResult.kTypeName, urlJson),
      );
      expect(deserializedUrl, equals(urlResult));
      expect(deserializedUrl.host, '127.0.0.1');
      expect(deserializedUrl.port, 8080);
      expect(deserializedUrl.url, 'http://127.0.0.1:8080');

      final info = PreviewServiceInfo(
        dtdUri: 'ws://127.0.0.1:42135/xyz',
        previewService: 'widget-preview-123',
        projectRoot: '/abs/path/to/project',
        scaffoldConnected: true,
        scaffoldService: 'PreviewScaffold-123',
        scaffoldStream: 'WidgetPreviewScaffold-123',
        webPreviewUri: 'http://127.0.0.1:8080',
      );
      final Map<String, Object?> infoJson = info.toJson();
      expect(infoJson[PreviewServiceInfo.kType], PreviewServiceInfo.kTypeName);
      final deserializedInfo = PreviewServiceInfo.fromDTDResponse(
        DTDResponse('1', PreviewServiceInfo.kTypeName, infoJson),
      );
      expect(deserializedInfo, equals(info));
      expect(deserializedInfo.dtdUri, 'ws://127.0.0.1:42135/xyz');
      expect(deserializedInfo.projectRoot, '/abs/path/to/project');
      expect(deserializedInfo.previewService, 'widget-preview-123');
      expect(deserializedInfo.scaffoldService, 'PreviewScaffold-123');
      expect(deserializedInfo.scaffoldStream, 'WidgetPreviewScaffold-123');
      expect(deserializedInfo.webPreviewUri, 'http://127.0.0.1:8080');
      expect(deserializedInfo.scaffoldConnected, isTrue);

      final disconnectedInfo = PreviewServiceInfo(
        dtdUri: 'ws://127.0.0.1:42135/xyz',
        previewService: 'widget-preview',
        projectRoot: '/abs/path/to/project',
        scaffoldConnected: false,
        scaffoldService: 'PreviewScaffold',
        scaffoldStream: 'WidgetPreviewScaffold',
      );
      final Map<String, Object?> disconnectedJson = disconnectedInfo.toJson();
      expect(disconnectedJson.containsKey(PreviewServiceInfo.kWebPreviewUri), isTrue);
      expect(disconnectedJson[PreviewServiceInfo.kWebPreviewUri], isNull);
      expect(
        PreviewServiceInfo.fromDTDResponse(
          DTDResponse('1', PreviewServiceInfo.kTypeName, disconnectedJson),
        ),
        equals(disconnectedInfo),
      );
    });

    testWithoutContext('SyncPreviewsResponse serialization, fromDTDResponse, and equality', () {
      const okResponse = SyncPreviewsResponse(
        compileSuccess: true,
        errorPreviewCount: 0,
        fullRestart: false,
        reloaded: true,
      );
      final Map<String, Object?> okJson = okResponse.toJson();
      expect(okJson[SyncPreviewsResponse.kType], SyncPreviewsResponse.kTypeName);
      expect(okJson.containsKey(SyncPreviewsResponse.kCompileError), isTrue);
      expect(okJson[SyncPreviewsResponse.kCompileError], isNull);

      final deserializedOk = SyncPreviewsResponse.fromDTDResponse(
        DTDResponse('1', SyncPreviewsResponse.kTypeName, okJson),
      );
      expect(deserializedOk, equals(okResponse));
      expect(deserializedOk.hashCode, equals(okResponse.hashCode));

      const failedResponse = SyncPreviewsResponse(
        compileError: 'Failed to recompile application.',
        compileSuccess: false,
        errorPreviewCount: 2,
        fullRestart: true,
        reloaded: false,
      );
      final deserializedFailed = SyncPreviewsResponse.fromDTDResponse(
        DTDResponse('1', SyncPreviewsResponse.kTypeName, failedResponse.toJson()),
      );
      expect(deserializedFailed, equals(failedResponse));
      expect(deserializedFailed.compileError, 'Failed to recompile application.');
      expect(deserializedFailed.errorPreviewCount, 2);
      expect(deserializedFailed.fullRestart, isTrue);
      expect(deserializedFailed.reloaded, isFalse);
      expect(deserializedFailed.toString(), contains('Failed to recompile application.'));
    });

    testWithoutContext('PreviewDiagnostic, PreviewEntry, PreviewListResponse, and CapturePreviewResponse round-trip', () {
      const overflowDiag = PreviewDiagnostic(
        kind: .overflow,
        overflowAxis: 'horizontal',
        overflowPixels: 48.0,
        overflowSide: 'right',
        phase: .paint,
        summary: 'A RenderFlex overflowed by 48 pixels on the right.',
        targetType: 'RenderFlex',
      );
      final Map<String, Object?> overflowJson = overflowDiag.toJson();
      expect(
        overflowJson,
        equals(<String, Object?>{
          'phase': 'paint',
          'kind': 'overflow',
          'summary': 'A RenderFlex overflowed by 48 pixels on the right.',
          'severity': 'error',
          'overflowPixels': 48.0,
          'overflowSide': 'right',
          'overflowAxis': 'horizontal',
          'targetType': 'RenderFlex',
        }),
      );
      expect(PreviewDiagnostic.fromJson(overflowJson), equals(overflowDiag));
      expect(PreviewDiagnostic.fromJson(overflowJson).hashCode, equals(overflowDiag.hashCode));

      const compileDiag = PreviewDiagnostic(
        kind: .compileError,
        phase: .compile,
        summary: 'package:my_app/card.dart has errors!',
      );
      expect(
        compileDiag.toJson(),
        equals(<String, Object?>{
          'phase': 'compile',
          'kind': 'compile_error',
          'summary': 'package:my_app/card.dart has errors!',
          'severity': 'error',
        }),
      );
      expect(PreviewDiagnostic.fromJson(compileDiag.toJson()), equals(compileDiag));

      const warningDiag = PreviewDiagnostic(
        kind: .textTruncated,
        phase: .layout,
        severity: .warning,
        summary: 'Text truncated with ellipsis.',
      );
      expect(warningDiag.toJson()['kind'], 'text_truncated');
      expect(warningDiag.toJson()['severity'], 'warning');
      expect(PreviewDiagnostic.fromJson(warningDiag.toJson()), equals(warningDiag));
      for (final (String raw, PreviewDiagnosticKind expected)
          in const <(String, PreviewDiagnosticKind)>[
            ('zero_size', PreviewDiagnosticKind.zeroSize),
            ('small_tap_target', PreviewDiagnosticKind.smallTapTarget),
            ('pending_frame', PreviewDiagnosticKind.pendingFrame),
          ]) {
        expect(PreviewDiagnosticKind.fromJson(raw), expected);
      }

      final entry = PreviewEntry(
        brightness: 'light',
        column: 5,
        functionName: 'cardPreview',
        group: 'Default',
        hasError: false,
        height: 667.0,
        id: 'package:my_app/card.dart::cardPreview',
        libraryUri: 'package:my_app/card.dart',
        line: 12,
        name: 'Mobile Light',
        packageName: 'my_app',
        scriptUri: 'file:///abs/path/lib/card.dart',
        width: 375.0,
      );
      final Map<String, Object?> entryJson = entry.toJson();
      expect(
        entryJson,
        equals(<String, Object?>{
          'id': 'package:my_app/card.dart::cardPreview',
          'libraryUri': 'package:my_app/card.dart',
          'scriptUri': 'file:///abs/path/lib/card.dart',
          'packageName': 'my_app',
          'functionName': 'cardPreview',
          'multiPreviewIndex': null,
          'line': 12,
          'column': 5,
          'group': 'Default',
          'name': 'Mobile Light',
          'width': 375.0,
          'height': 667.0,
          'textScaleFactor': null,
          'brightness': 'light',
          'hasError': false,
          'errorMessage': null,
        }),
      );
      expect(
        PreviewEntry.fromJson(<String, Object?>{...entryJson, 'width': 375, 'height': 667}),
        equals(entry),
      );

      final listResponse = PreviewListResponse(previews: <PreviewEntry>[entry]);
      final Map<String, Object?> listJson = listResponse.toJson();
      expect(listJson[PreviewListResponse.kType], PreviewListResponse.kTypeName);
      final deserializedList = PreviewListResponse.fromDTDResponse(
        DTDResponse('1', PreviewListResponse.kTypeName, listJson),
      );
      expect(deserializedList, equals(listResponse));
      expect(deserializedList.previews.single.id, entry.id);

      const pngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
      const captureResponse = CapturePreviewResponse(
        diagnostics: <PreviewDiagnostic>[overflowDiag],
        hasErrors: true,
        imageBase64: pngBase64,
        name: 'Mobile Light',
        pixelRatio: 2.0,
        previewId: 'package:my_app/card.dart::cardPreview',
        renderedHeight: 220.0,
        renderedWidth: 375.0,
      );
      final Map<String, Object?> captureJson = captureResponse.toJson();
      expect(
        captureJson,
        equals(<String, Object?>{
          'type': 'CapturePreviewResponse',
          'previewId': 'package:my_app/card.dart::cardPreview',
          'name': 'Mobile Light',
          'renderedWidth': 375.0,
          'renderedHeight': 220.0,
          'pixelRatio': 2.0,
          'imageBase64': pngBase64,
          'hasErrors': true,
          'diagnostics': <Map<String, Object?>>[overflowDiag.toJson()],
        }),
      );
      final deserializedCapture = CapturePreviewResponse.fromDTDResponse(
        DTDResponse('1', CapturePreviewResponse.kTypeName, captureJson),
      );
      expect(deserializedCapture, equals(captureResponse));
      expect(deserializedCapture.hashCode, equals(captureResponse.hashCode));
      expect(deserializedCapture.withoutImage().imageBase64, isNull);
      expect(
        CapturePreviewResponse.fromDTDResponse(
          DTDResponse('1', CapturePreviewResponse.kTypeName, <String, Object?>{
            ...captureJson,
            'renderedWidth': 375,
            'renderedHeight': 220,
            'pixelRatio': 2,
          }),
        ),
        equals(captureResponse),
      );
    });

    testWithoutContext('fromDTDResponse rejects mismatched response types with INVALID_PARAMS', () {
      final wrongType = DTDResponse('1', 'WrongType', <String, Object?>{'type': 'WrongType'});
      for (final parser in <Object? Function(DTDResponse)>[
        WebPreviewUrlResult.fromDTDResponse,
        PreviewServiceInfo.fromDTDResponse,
        SyncPreviewsResponse.fromDTDResponse,
        PreviewListResponse.fromDTDResponse,
        CapturePreviewResponse.fromDTDResponse,
      ]) {
        expect(() => parser(wrongType), _throwsRpcCode(error_code.INVALID_PARAMS));
      }
    });
  });

  group('WidgetPreviewDtdServices Method Registration & Handlers', () {
    late FileSystem fs;
    late Logger logger;
    late ShutdownHooks shutdownHooks;
    late FlutterProject project;
    late WidgetPreviewAnalytics analytics;

    setUp(() {
      fs = MemoryFileSystem.test();
      logger = BufferLogger.test();
      shutdownHooks = ShutdownHooks();
      final Directory projectDir = fs.directory('/project')..createSync(recursive: true);
      projectDir.childFile('pubspec.yaml').writeAsStringSync('name: test_project\n');
      project = FlutterProjectFactory(
        config: FakeConfig(),
        fileSystem: fs,
        logger: logger,
      ).fromDirectory(projectDir);
      analytics = WidgetPreviewAnalytics(analytics: const NoOpAnalytics());
    });

    WidgetPreviewDtdServices createServices({
      bool addUuid = false,
      DartToolingDaemon? dtd,
      FutureOr<FlutterWidgetPreviews?> Function()? lspPreviewsProvider,
      Future<void> Function()? onHotReloadPreviewer,
      Future<SyncPreviewsResponse> Function({required Duration timeout})? onSyncPreviews,
      WidgetPreviewAnalytics? previewAnalytics,
      FlutterProject? targetProject,
      String? projectRootPath,
      Uri? Function()? webPreviewUriProvider,
    }) {
      return WidgetPreviewDtdServices(
        addUuidToServiceName: addUuid,
        dtd: dtd,
        dtdLauncher: FakeDtdLauncher(),
        fs: fs,
        logger: logger,
        lspPreviewsProvider: lspPreviewsProvider,
        onHotReloadPreviewer: onHotReloadPreviewer,
        onHotRestartPreviewerRequest: () {},
        onSyncPreviews: onSyncPreviews,
        previewAnalytics: previewAnalytics ?? analytics,
        project: targetProject ?? project,
        projectRootPath: projectRootPath,
        shutdownHooks: shutdownHooks,
        webPreviewUriProvider: webPreviewUriProvider,
      );
    }

    testWithoutContext('builds matching service and stream names with and without UUID', () {
      final WidgetPreviewDtdServices withoutUuid = createServices();
      expect(withoutUuid.widgetPreviewService, 'widget-preview');
      expect(withoutUuid.widgetPreviewScaffoldService, 'PreviewScaffold');
      expect(withoutUuid.widgetPreviewScaffoldStream, 'WidgetPreviewScaffold');

      final WidgetPreviewDtdServices withUuid = createServices(addUuid: true);
      final String uuid = withUuid.serviceUuid;
      expect(uuid, isNotEmpty);
      expect(withUuid.widgetPreviewService, 'widget-preview-$uuid');
      expect(withUuid.widgetPreviewScaffoldService, 'PreviewScaffold-$uuid');
      expect(withUuid.widgetPreviewScaffoldStream, 'WidgetPreviewScaffold-$uuid');
    });

    testWithoutContext('registers expected DTD service methods', () {
      final WidgetPreviewDtdServices services = createServices();
      expect(
        <String>{for (final (String name, _) in services.services) name},
        equals(<String>{
          WidgetPreviewDtdServices.kHotRestartPreviewer,
          WidgetPreviewDtdServices.kHotReloadPreviewer,
          WidgetPreviewDtdServices.kIsWindows,
          WidgetPreviewDtdServices.kResolveUri,
          WidgetPreviewDtdServices.kSetPreference,
          WidgetPreviewDtdServices.kGetPreference,
          WidgetPreviewDtdServices.kGetDevToolsUri,
          WidgetPreviewDtdServices.kGetWebPreviewUrl,
          WidgetPreviewDtdServices.kGetServiceInfo,
          WidgetPreviewDtdServices.kSyncPreviews,
          WidgetPreviewDtdServices.kListPreviews,
        }),
      );
    });

    testWithoutContext('invokes onHotReloadPreviewer when hotReloadPreviewer is called', () async {
      var hotReloadCalled = false;
      final WidgetPreviewDtdServices services = createServices(
        onHotReloadPreviewer: () async {
          hotReloadCalled = true;
        },
      );
      final Map<String, Object?> response = await _callbackFor(
        services,
        WidgetPreviewDtdServices.kHotReloadPreviewer,
      )(Parameters('hotReloadPreviewer', <String, Object?>{}));

      expect(hotReloadCalled, isTrue);
      expect(response, equals(const Success().toJson()));
    });

    testWithoutContext(
      'getWebPreviewUrl returns URL when available and throws otherwise',
      () async {
        final WidgetPreviewDtdServices available = createServices(
          webPreviewUriProvider: () => Uri.parse('http://127.0.0.1:9090'),
        );
        final Map<String, Object?> response = await _callbackFor(
          available,
          WidgetPreviewDtdServices.kGetWebPreviewUrl,
        )(Parameters('getWebPreviewUrl', <String, Object?>{}));
        expect(response[WebPreviewUrlResult.kType], WebPreviewUrlResult.kTypeName);
        expect(response['host'], '127.0.0.1');
        expect(response['port'], 9090);
        expect(response['url'], 'http://127.0.0.1:9090');

        for (final provider in <Uri? Function()?>[null, () => null]) {
          final WidgetPreviewDtdServices unavailable = createServices(
            webPreviewUriProvider: provider,
          );
          await expectLater(
            _callbackFor(unavailable, WidgetPreviewDtdServices.kGetWebPreviewUrl)(
              Parameters('getWebPreviewUrl', <String, Object?>{}),
            ),
            _throwsRpcCode(WidgetPreviewDtdServices.kNoValueForKey),
          );
        }
      },
    );

    testWithoutContext('returns PreviewServiceInfo from getServiceInfo', () async {
      final fakeDtd = FakeDartToolingDaemon();
      addTearDown(fakeDtd.close);
      final WidgetPreviewDtdServices services = createServices(
        addUuid: true,
        dtd: fakeDtd,
        targetProject: project.widgetPreviewScaffoldProject,
        projectRootPath: '/project',
        webPreviewUriProvider: () => Uri.parse('http://127.0.0.1:8080'),
      );
      await services.connect(dtdWsUri: Uri.parse('ws://127.0.0.1:54322/secret'));

      final DTDServiceCallback callback = _callbackFor(
        services,
        WidgetPreviewDtdServices.kGetServiceInfo,
      );
      final Map<String, Object?> initial = await callback(
        Parameters('getServiceInfo', <String, Object?>{}),
      );
      final String uuid = services.serviceUuid;
      expect(initial[PreviewServiceInfo.kType], PreviewServiceInfo.kTypeName);
      expect(initial[PreviewServiceInfo.kDtdUri], 'ws://127.0.0.1:54322/secret');
      expect(initial[PreviewServiceInfo.kProjectRoot], '/project');
      expect(initial[PreviewServiceInfo.kPreviewService], 'widget-preview-$uuid');
      expect(initial[PreviewServiceInfo.kScaffoldService], 'PreviewScaffold-$uuid');
      expect(initial[PreviewServiceInfo.kScaffoldStream], 'WidgetPreviewScaffold-$uuid');
      expect(initial[PreviewServiceInfo.kWebPreviewUri], 'http://127.0.0.1:8080');
      expect(initial[PreviewServiceInfo.kScaffoldConnected], isFalse);

      fakeDtd.postFakeEvent(
        services.widgetPreviewScaffoldStream,
        WidgetPreviewDtdServices.kWidgetPreviewConnectedEvent,
        const <String, Object?>{},
      );
      await pumpEventQueue();

      final Map<String, Object?> connected = await callback(
        Parameters('getServiceInfo', <String, Object?>{}),
      );
      expect(connected[PreviewServiceInfo.kScaffoldConnected], isTrue);
    });

    testWithoutContext('syncPreviews forwards timeout and validates parameters', () async {
      Duration? receivedTimeout;
      final WidgetPreviewDtdServices services = createServices(
        onSyncPreviews: ({required Duration timeout}) async {
          receivedTimeout = timeout;
          return const SyncPreviewsResponse(
            compileSuccess: true,
            errorPreviewCount: 1,
            fullRestart: false,
            reloaded: true,
          );
        },
      );
      final DTDServiceCallback callback = _callbackFor(
        services,
        WidgetPreviewDtdServices.kSyncPreviews,
      );

      for (final params in <Map<String, Object?>?>[
        null,
        <String, Object?>{},
        <String, Object?>{'timeoutMs': null},
      ]) {
        receivedTimeout = null;
        final Map<String, Object?> response = await callback(Parameters('syncPreviews', params));
        expect(
          receivedTimeout,
          const Duration(milliseconds: WidgetPreviewDtdServices.kDefaultSyncTimeoutMs),
        );
        expect(response[SyncPreviewsResponse.kType], SyncPreviewsResponse.kTypeName);
        expect(response[SyncPreviewsResponse.kReloaded], isTrue);
        expect(response[SyncPreviewsResponse.kErrorPreviewCount], 1);
      }

      await callback(Parameters('syncPreviews', <String, Object?>{'timeoutMs': 12500}));
      expect(receivedTimeout, const Duration(milliseconds: 12500));

      for (final invalidTimeout in const <Object>[-1, 'invalid']) {
        await expectLater(
          callback(Parameters('syncPreviews', <String, Object?>{'timeoutMs': invalidTimeout})),
          _throwsRpcCode(error_code.INVALID_PARAMS),
        );
      }

      await expectLater(
        _callbackFor(createServices(), WidgetPreviewDtdServices.kSyncPreviews)(
          Parameters('syncPreviews', <String, Object?>{}),
        ),
        _throwsRpcCode(WidgetPreviewDtdServices.kNoValueForKey),
      );
    });

    testWithoutContext(
      'tracks scaffoldConnected across Connected events, markScaffoldDisconnected, and timeouts',
      () async {
        final fakeDtd = FakeDartToolingDaemon();
        addTearDown(fakeDtd.close);
        final fakeAnalytics = FakeWidgetPreviewAnalytics();
        final WidgetPreviewDtdServices services = createServices(
          dtd: fakeDtd,
          previewAnalytics: fakeAnalytics,
        );
        await services.connect(dtdWsUri: Uri.parse('ws://127.0.0.1:54322/secret'));
        expect(services.scaffoldConnected, isFalse);

        var waiterCompleted = false;
        final Future<void> initialWait = services.waitForScaffoldConnected().then((_) {
          waiterCompleted = true;
        });
        await pumpEventQueue();
        expect(waiterCompleted, isFalse);

        fakeDtd.postFakeEvent(
          services.widgetPreviewScaffoldStream,
          WidgetPreviewDtdServices.kWidgetPreviewConnectedEvent,
          const <String, Object?>{},
        );
        await initialWait;
        expect(waiterCompleted, isTrue);
        expect(services.scaffoldConnected, isTrue);
        expect(fakeAnalytics.reportPreviewerConnectedCount, 1);

        await services.waitForScaffoldConnected(timeout: Duration.zero);

        services.markScaffoldDisconnected();
        expect(services.scaffoldConnected, isFalse);
        await expectLater(
          services.waitForScaffoldConnected(timeout: const Duration(milliseconds: 10)),
          throwsA(isA<TimeoutException>()),
        );
        expect(services.scaffoldConnected, isFalse);

        final Future<void> secondWait = services.waitForScaffoldConnected();
        fakeDtd.postFakeEvent(
          services.widgetPreviewScaffoldStream,
          WidgetPreviewDtdServices.kWidgetPreviewConnectedEvent,
          const <String, Object?>{},
        );
        await secondWait;
        expect(services.scaffoldConnected, isTrue);
        expect(fakeAnalytics.reportPreviewerConnectedCount, 2);

        services.markScaffoldDisconnected();
        expect(services.scaffoldConnected, isFalse);
        final Future<void> restoredWait = services.waitForScaffoldConnected();
        services.markScaffoldConnected();
        await restoredWait;
        expect(services.scaffoldConnected, isTrue);
        expect(fakeAnalytics.reportPreviewerConnectedCount, 2);
      },
    );

    testWithoutContext(
      'postPreviewReloaded emits PreviewReloaded and ignores disconnected or closed DTD',
      () async {
        await createServices().postPreviewReloaded(fullRestart: false);

        final fakeDtd = FakeDartToolingDaemon();
        addTearDown(fakeDtd.close);
        final WidgetPreviewDtdServices services = createServices(addUuid: true, dtd: fakeDtd);
        await services.connect(dtdWsUri: Uri.parse('ws://127.0.0.1:54322/secret'));

        await services.postPreviewReloaded(fullRestart: false);
        await services.postPreviewReloaded(fullRestart: true);

        expect(fakeDtd.postedEvents, hasLength(2));
        for (final (int index, bool expectedRestart) in const <(int, bool)>[
          (0, false),
          (1, true),
        ]) {
          expect(fakeDtd.postedEvents[index].streamId, services.widgetPreviewScaffoldStream);
          expect(
            fakeDtd.postedEvents[index].eventKind,
            WidgetPreviewDtdServices.kPreviewReloadedEvent,
          );
          expect(
            fakeDtd.postedEvents[index].eventData,
            equals(<String, Object?>{WidgetPreviewDtdServices.kFullRestart: expectedRestart}),
          );
        }

        fakeDtd.postEventException = RpcException(RpcErrorCodes.kConnectionFailed, 'Disconnected');
        await services.postPreviewReloaded(fullRestart: false);

        fakeDtd
          ..postEventException = null
          ..postEventError = StateError('The client is closed.');
        await services.postPreviewReloaded(fullRestart: true);
      },
    );

    testWithoutContext(
      'listPreviews syncs when requested, delegates to scaffold getPreviews when connected, '
      'and falls back to LSP metadata when disconnected or failed compilation',
      () async {
        final fakeDtd = FakeDartToolingDaemon()
          ..registeredServicesResponse = _lspServicesResponse(
            WidgetPreviewDtdServices.kRequiredLspServices,
          )
          ..lspPreviewsResponse = FlutterWidgetPreviews(
            namespaces: const <String, String>{},
            previews: <FlutterWidgetPreviewDetails>[
              FlutterWidgetPreviewDetails(
                functionName: 'cardPreview',
                hasError: false,
                dependencyHasErrors: false,
                isBuilder: false,
                isMultiPreview: false,
                packageName: 'my_app',
                position: const Position(character: 5, line: 12),
                previewAnnotation:
                    "const _i4.Preview(group: 'Cards', name: 'Mobile Light', "
                    'size: _i5.Size(375, 667.0), textScaleFactor: 1.25, '
                    'brightness: _i5.Brightness.light)',
                scriptUri: Uri.parse('file:///project/lib/card.dart'),
                libraryUri: Uri.parse('package:my_app/card.dart'),
              ),
              FlutterWidgetPreviewDetails(
                functionName: 'brokenPreview',
                hasError: true,
                dependencyHasErrors: false,
                isBuilder: false,
                isMultiPreview: false,
                packageName: 'my_app',
                position: const Position(character: 1, line: 30),
                previewAnnotation: 'const _i4.Preview()',
                scriptUri: Uri.parse('file:///project/lib/broken.dart'),
                libraryUri: Uri.parse('package:my_app/broken.dart'),
              ),
              FlutterWidgetPreviewDetails(
                functionName: 'outsideLibPreview',
                hasError: false,
                dependencyHasErrors: false,
                isBuilder: false,
                isMultiPreview: false,
                position: const Position(character: 1, line: 4),
                previewAnnotation: 'const _i4.Preview()',
                scriptUri: Uri.parse('file:///project/test/preview_test.dart'),
                libraryUri: Uri.parse('test/preview_test.dart'),
              ),
            ],
            scriptUris: <Uri>[
              Uri.parse('file:///project/lib/card.dart'),
              Uri.parse('file:///project/lib/broken.dart'),
            ],
          );
        addTearDown(fakeDtd.close);

        var syncCallCount = 0;
        var syncCompileSuccess = true;
        final scaffoldCalls = <Map<String, Object?>?>[];
        var throwServiceDisappeared = false;

        final scaffoldEntry = PreviewEntry(
          brightness: 'dark',
          column: 5,
          functionName: 'cardPreviews',
          group: 'Cards',
          hasError: false,
          height: 667.0,
          id: 'package:my_app/card.dart::cardPreviews#0',
          libraryUri: 'package:my_app/card.dart',
          line: 12,
          multiPreviewIndex: 0,
          name: 'Dark Variant',
          packageName: 'my_app',
          scriptUri: 'file:///project/lib/card.dart',
          width: 375.0,
        );

        final WidgetPreviewDtdServices services = createServices(
          addUuid: true,
          dtd: fakeDtd,
          onSyncPreviews: ({required Duration timeout}) async {
            syncCallCount++;
            return SyncPreviewsResponse(
              compileError: syncCompileSuccess ? null : 'Compile failed',
              compileSuccess: syncCompileSuccess,
              errorPreviewCount: syncCompileSuccess ? 0 : 1,
              fullRestart: false,
              reloaded: syncCompileSuccess,
            );
          },
        );
        fakeDtd.onCall =
            (String? serviceName, String methodName, Map<String, Object?>? params) async {
              if (serviceName == services.widgetPreviewScaffoldService &&
                  methodName == WidgetPreviewDtdServices.kGetPreviews) {
                if (throwServiceDisappeared) {
                  throw RpcException(RpcErrorCodes.kServiceDisappeared, 'Service disappeared');
                }
                scaffoldCalls.add(params);
                return DTDResponse(
                  '1',
                  PreviewListResponse.kTypeName,
                  PreviewListResponse(previews: <PreviewEntry>[scaffoldEntry]).toJson(),
                );
              }
              if (serviceName == WidgetPreviewDtdServices.kLspStream &&
                  methodName == WidgetPreviewDtdServices.kGetFlutterWidgetPreviewsMethod) {
                return DTDResponse('1', 'result', <String, Object?>{
                  'result': fakeDtd.lspPreviewsResponse!.toJson(),
                });
              }
              if (serviceName == WidgetPreviewDtdServices.kLspStream &&
                  methodName == WidgetPreviewDtdServices.kWorkspaceAnalysisCompleteMethod) {
                fakeDtd.waitForAnalysisCallCount++;
                return DTDResponse('1', 'Null', <String, Object?>{'type': 'Null', 'result': null});
              }
              throw UnimplementedError('Unexpected call: $serviceName.$methodName');
            };

        await services.connect(dtdWsUri: Uri.parse('ws://127.0.0.1:54322/secret'));
        final DTDServiceCallback listCallback = _callbackFor(
          services,
          WidgetPreviewDtdServices.kListPreviews,
        );

        final PreviewListResponse fallbackAll = PreviewListResponse.fromJson(
          await listCallback(Parameters('listPreviews', <String, Object?>{})),
        );
        expect(syncCallCount, 1);
        expect(scaffoldCalls, isEmpty);
        expect(
          fallbackAll.previews.map((PreviewEntry e) => e.id).toList(),
          equals(<String>[
            'package:my_app/broken.dart::brokenPreview',
            'package:my_app/card.dart::cardPreview',
          ]),
        );
        final PreviewEntry brokenFallback = fallbackAll.previews.first;
        expect(brokenFallback.hasError, isTrue);
        expect(brokenFallback.errorMessage, 'package:my_app/broken.dart has errors!');
        expect(brokenFallback.group, 'Invalid Previews');

        final PreviewEntry cardFallback = fallbackAll.previews.last;
        expect(cardFallback.hasError, isFalse);
        expect(cardFallback.errorMessage, isNull);
        expect(cardFallback.group, 'Cards');
        expect(cardFallback.name, 'Mobile Light');
        expect(cardFallback.width, 375.0);
        expect(cardFallback.height, 667.0);
        expect(cardFallback.textScaleFactor, 1.25);
        expect(cardFallback.brightness, 'light');

        final PreviewListResponse filteredFallback = PreviewListResponse.fromJson(
          await listCallback(
            Parameters('listPreviews', <String, Object?>{
              'fileUri': 'package:my_app/card.dart',
              'sync': false,
            }),
          ),
        );
        expect(syncCallCount, 1);
        expect(filteredFallback.previews.single.id, 'package:my_app/card.dart::cardPreview');

        services.markScaffoldConnected();
        final PreviewListResponse connectedList = PreviewListResponse.fromJson(
          await listCallback(
            Parameters('listPreviews', <String, Object?>{
              'fileUri': 'file:///project/lib/card.dart',
            }),
          ),
        );
        expect(syncCallCount, 2);
        expect(
          scaffoldCalls,
          equals(<Map<String, Object?>?>[
            <String, Object?>{'fileUri': 'file:///project/lib/card.dart'},
          ]),
        );
        expect(connectedList.previews, equals(<PreviewEntry>[scaffoldEntry]));

        syncCompileSuccess = false;
        final PreviewListResponse compileFailed = PreviewListResponse.fromJson(
          await listCallback(Parameters('listPreviews', <String, Object?>{})),
        );
        expect(syncCallCount, 3);
        expect(scaffoldCalls, hasLength(1));
        expect(compileFailed.previews, hasLength(2));

        syncCompileSuccess = true;
        throwServiceDisappeared = true;
        final PreviewListResponse disappeared = PreviewListResponse.fromJson(
          await listCallback(Parameters('listPreviews', <String, Object?>{'sync': false})),
        );
        expect(syncCallCount, 3);
        expect(disappeared.previews, hasLength(2));
      },
    );
  });

  group('Lsp service and stream handling', () {
    late FileSystem fs;
    late Logger logger;
    late FakeDartToolingDaemon fakeDtd;
    late WidgetPreviewDtdServices dtdServices;

    setUp(() {
      fs = MemoryFileSystem.test();
      logger = BufferLogger.test();
      fakeDtd = FakeDartToolingDaemon();
      final FlutterProject project = FlutterProjectFactory(
        config: FakeConfig(),
        fileSystem: fs,
        logger: logger,
      ).fromDirectory(fs.directory('project'));

      dtdServices = WidgetPreviewDtdServices(
        addUuidToServiceName: false,
        dtd: fakeDtd,
        dtdLauncher: FakeDtdLauncher(),
        fs: fs,
        logger: logger,
        onHotRestartPreviewerRequest: () {},
        previewAnalytics: FakeWidgetPreviewAnalytics(),
        project: project,
        shutdownHooks: ShutdownHooks(),
      );
    });

    tearDown(() async {
      await fakeDtd.close();
    });

    void postLspInitialized() {
      fakeDtd.postFakeEvent(
        WidgetPreviewDtdServices.kLspStream,
        WidgetPreviewDtdServices.kLspInitializedEvent,
        const <String, Object?>{},
      );
    }

    testWithoutContext(
      'concurrent Lsp preview calls share single streamListen and registration check',
      () async {
        final Future<FlutterWidgetPreviews> future1 = dtdServices.getFlutterWidgetPreviews();
        final Future<FlutterWidgetPreviews> future2 = dtdServices.getFlutterWidgetPreviews();
        final Future<FlutterWidgetPreviews> future3 = dtdServices.getFlutterWidgetPreviewsForFile(
          filePath: fs.path.join('lib', 'main.dart'),
        );

        await pumpEventQueue();
        postLspInitialized();

        final (
          FlutterWidgetPreviews result1,
          FlutterWidgetPreviews result2,
          FlutterWidgetPreviews result3,
        ) = await (
          future1,
          future2,
          future3,
        ).wait;
        expect(result1.previews, isEmpty);
        expect(result2.previews, isEmpty);
        expect(result3.previews, isEmpty);
        expect(fakeDtd.streamListenCallCount, 1);
        expect(fakeDtd.getRegisteredServicesCallCount, 1);
      },
    );

    testWithoutContext(
      'getFlutterWidgetPreviews succeeds when stream is already subscribed',
      () async {
        fakeDtd.subscribedStreams.add(WidgetPreviewDtdServices.kLspStream);
        final Future<FlutterWidgetPreviews> future = dtdServices.getFlutterWidgetPreviews();
        await pumpEventQueue();
        postLspInitialized();
        expect((await future).previews, isEmpty);
      },
    );

    testWithoutContext(
      'waitForAnalysis calls Lsp.dart/workspace/analysis/complete over DTD',
      () async {
        final Future<void> future = dtdServices.waitForAnalysis(delay: Duration.zero);
        await pumpEventQueue();
        postLspInitialized();
        await future;
        expect(fakeDtd.waitForAnalysisCallCount, 1);
      },
    );

    testWithoutContext(
      'waits for Lsp initialized event when only a subset of required Lsp methods are registered',
      () async {
        fakeDtd.registeredServicesResponse = _lspServicesResponse(<String>[
          WidgetPreviewDtdServices.kGetFlutterWidgetPreviewsMethod,
        ]);

        var completed = false;
        final Future<FlutterWidgetPreviews> future = dtdServices.getFlutterWidgetPreviews().then((
          FlutterWidgetPreviews value,
        ) {
          completed = true;
          return value;
        });

        await pumpEventQueue();
        expect(completed, isFalse);
        postLspInitialized();

        expect((await future).previews, isEmpty);
        expect(completed, isTrue);
      },
    );

    testWithoutContext(
      'proceeds without waiting for event when all required Lsp methods are already registered',
      () async {
        fakeDtd.registeredServicesResponse = _lspServicesResponse(
          WidgetPreviewDtdServices.kRequiredLspServices,
        );
        expect((await dtdServices.getFlutterWidgetPreviews()).previews, isEmpty);
        expect(fakeDtd.getRegisteredServicesCallCount, 1);
      },
    );

    testWithoutContext('cancels the Lsp event subscription when streamListen fails', () async {
      fakeDtd.streamListenError = RpcErrorCodes.buildRpcException(RpcErrorCodes.kConnectionFailed);
      await expectLater(
        dtdServices.getFlutterWidgetPreviews(),
        _throwsRpcCode(RpcErrorCodes.kConnectionFailed),
      );
      expect(fakeDtd.hasListener(WidgetPreviewDtdServices.kLspStream), isFalse);
    });

    for (final failureCase in const <({String name, String stdout, int exitCode})>[
      (name: 'malformed stdout', stdout: 'not json\n', exitCode: 0),
      (name: 'premature empty exit', stdout: '', exitCode: 1),
    ]) {
      testWithoutContext('DtdLauncher.launch throws ToolExit on ${failureCase.name}', () async {
        final launcher = DtdLauncher(
          artifacts: Artifacts.test(),
          logger: logger,
          processManager: FakeProcessManager.list(<FakeCommand>[
            FakeCommand(
              command: const <String>['Artifact.engineDartBinary', 'tooling-daemon', '--machine'],
              stdout: failureCase.stdout,
              exitCode: failureCase.exitCode,
            ),
          ]),
        );
        await expectLater(
          launcher.launch(),
          throwsToolExit(message: 'Unable to start the Dart Tooling Daemon'),
        );
      });
    }

    testWithoutContext('connect leaves dtdUri null when connection fails', () async {
      final services = WidgetPreviewDtdServices(
        addUuidToServiceName: false,
        dtdLauncher: FakeDtdLauncher(),
        fs: fs,
        logger: logger,
        onHotRestartPreviewerRequest: () {},
        previewAnalytics: WidgetPreviewAnalytics(analytics: const NoOpAnalytics()),
        project: FlutterProject.fromDirectoryTest(fs.currentDirectory),
        shutdownHooks: ShutdownHooks(),
      );
      await expectLater(
        services.connect(dtdWsUri: Uri.parse('ws://127.0.0.1:1')),
        throwsA(isA<Exception>()),
      );
      expect(services.dtdUri, isNull);
    });

    testWithoutContext(
      'listPreviewsJson matches symlinked --file paths against scriptUri',
      () async {
        final File realFile = (fs.directory(
          '/real/app/lib',
        )..createSync(recursive: true)).childFile('main.dart')..writeAsStringSync('');
        final Link symlinkFile = fs.link(
          (fs.directory('/link/app/lib')..createSync(recursive: true)).childFile('main.dart').path,
        )..createSync(realFile.path);

        final services = WidgetPreviewDtdServices(
          addUuidToServiceName: false,
          dtd: fakeDtd,
          dtdLauncher: FakeDtdLauncher(),
          fs: fs,
          logger: logger,
          onHotRestartPreviewerRequest: () {},
          previewAnalytics: WidgetPreviewAnalytics(analytics: const NoOpAnalytics()),
          project: FlutterProject.fromDirectoryTest(fs.currentDirectory),
          shutdownHooks: ShutdownHooks(),
          lspPreviewsProvider: () => FlutterWidgetPreviews(
            namespaces: const <String, String>{},
            previews: <FlutterWidgetPreviewDetails>[
              FlutterWidgetPreviewDetails(
                dependencyHasErrors: false,
                functionName: 'myPreview',
                hasError: false,
                isBuilder: false,
                isMultiPreview: false,
                libraryUri: Uri.parse('package:my_app/main.dart'),
                packageName: 'my_app',
                position: const Position(character: 1, line: 5),
                previewAnnotation: 'const Preview()',
                scriptUri: realFile.uri,
              ),
            ],
            scriptUris: <Uri>[realFile.uri],
          ),
        );

        final PreviewListResponse response = PreviewListResponse.fromJson(
          await services.listPreviewsJson(fileUri: fs.file(symlinkFile.path).uri.toString()),
        );
        expect(response.previews.single.functionName, 'myPreview');
      },
    );
  });
}

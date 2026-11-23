// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:dwds/data/build_result.dart';
import 'package:dwds/dwds.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/config.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/isolated/web_asset_server.dart';
import 'package:flutter_tools/src/isolated/widget_preview_live_server.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/web/bootstrap.dart';
import 'package:flutter_tools/src/web/compile.dart';
import 'package:flutter_tools/src/web/devfs_config.dart';
import 'package:flutter_tools/src/web/memory_fs.dart';
import 'package:flutter_tools/src/widget_preview/analytics.dart';
import 'package:flutter_tools/src/widget_preview/dtd_services.dart';
import 'package:flutter_tools/src/widget_preview/dtd_types.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:stream_channel/stream_channel.dart';
import 'package:test/fake.dart';
import 'package:unified_analytics/unified_analytics.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../src/common.dart';
import '../../src/context.dart';
import '../../src/fakes.dart';

void main() {
  late MemoryFileSystem fs;
  late BufferLogger logger;
  late FlutterProject project;
  late _FakeWidgetPreviewDtdServices dtdServices;

  setUp(() {
    fs = MemoryFileSystem.test();
    fs.file('HostArtifact.flutterJsDirectory/flutter.js')
      ..createSync(recursive: true)
      ..writeAsStringSync('// flutter.js');
    logger = BufferLogger.test();
    final Directory projectDir = fs.directory('/tmp/my_app')..createSync(recursive: true);
    projectDir.childFile('pubspec.yaml').writeAsStringSync('name: my_app\n');
    project = FlutterProject.fromDirectoryTest(projectDir);
    dtdServices = _FakeWidgetPreviewDtdServices(
      fs: fs,
      logger: logger,
      project: project,
      projectRootPath: projectDir.path,
    );
  });

  group('$WidgetPreviewLiveServer', () {
    late WebMemoryFS webMemoryFS;
    late Map<String, String> modules;
    late WidgetPreviewLiveServer server;

    WidgetPreviewLiveServer createServer({
      List<String> allowedOrigins = const <String>[],
      String basePath = '',
      WidgetPreviewDtdServices? dtdServicesOverride,
      DtdWebSocketConnector? dtdWebSocketConnector,
      int maxActiveWebSockets = WidgetPreviewLiveConfig.kDefaultMaxActiveWebSockets,
      Map<String, String>? modulesOverride,
      String flutterBootstrapJs =
          'window._flutter.buildConfig = {"builds":[{"mainJsPath":"main.dart.js"}]};',
      String indexHtml = '<html><head></head><body><script src="flutter_bootstrap.js" async></script></body></html>',
    }) {
      final instance = WidgetPreviewLiveServer(
        basePathProvider: () => basePath,
        config: WidgetPreviewLiveConfig(
          allowedOrigins: allowedOrigins,
          dtdServices: dtdServicesOverride ?? dtdServices,
          dtdWebSocketConnector: dtdWebSocketConnector ?? WebSocketChannel.connect,
          maxActiveWebSockets: maxActiveWebSockets,
        ),
        configuredHost: 'localhost',
        isWindows: false,
        modules: modulesOverride ?? modules,
        renderFlutterBootstrapJs: () => flutterBootstrapJs,
        renderIndexHtml: () => indexHtml,
        webMemoryFS: webMemoryFS,
      );
      addTearDown(instance.dispose);
      return instance;
    }

    Future<shelf.Response> request(
      String pathOrUrl, {
      String method = 'GET',
      Map<String, String>? headers,
      WidgetPreviewLiveServer? target,
    }) {
      final url = pathOrUrl.startsWith('http') ? pathOrUrl : 'http://localhost:8080$pathOrUrl';
      return (target ?? server).handler(shelf.Request(method, Uri.parse(url), headers: headers));
    }

    setUp(() {
      webMemoryFS = WebMemoryFS();
      modules = <String, String>{
        'packages/my_app/main.dart': 'packages/my_app/main.dart.lib',
        'web_entrypoint.dart': 'web_entrypoint.dart.lib',
      };
      webMemoryFS.files['packages/my_app/main.dart.lib.js'] = Uint8List.fromList(
        utf8.encode('console.log("app");\n//# sourceMappingURL=main.dart.lib.js.map\n'),
      );
      webMemoryFS.files['web_entrypoint.dart.lib.js'] = Uint8List.fromList(
        utf8.encode('console.log("entry");\n//# sourceMappingURL=web_entrypoint.dart.lib.js.map'),
      );
      webMemoryFS.files['main_module.bootstrap.js'] = Uint8List.fromList(
        utf8.encode(
          generateDDCLibraryBundleMainModule(
            entrypoint: 'web_entrypoint.dart',
            nativeNullAssertions: true,
            onLoadEndBootstrap: 'on_load_end_bootstrap.js',
            isCi: false,
          ),
        ),
      );
      webMemoryFS.incrementRevision();
      server = createServer();
    });

    testWithoutContext('separates GET / from GET /?embed=1 and rewrites embed bootstrap', () async {
      expect((await request('/')).statusCode, io.HttpStatus.notFound);

      final shelf.Response embedRoot = await request('/?embed=1');
      expect(embedRoot.statusCode, io.HttpStatus.ok);
      expect(embedRoot.headers['cross-origin-resource-policy'], 'same-site');
      expect(embedRoot.headers['x-content-type-options'], 'nosniff');
      expect(embedRoot.headers['content-security-policy'], "frame-ancestors 'self'");
      expect(embedRoot.headers.containsKey('access-control-allow-origin'), isFalse);
      final String embedHtml = await embedRoot.readAsString();
      expect(embedHtml, contains('__embed_flutter_bootstrap.js'));
      expect(embedHtml, contains('id="wp-live-bg"'));
      expect(embedHtml, contains('background:#121212'));
      expect(embedHtml, isNot(contains('"flutter_bootstrap.js"')));

      final shelf.Response embedBootstrap = await request('/__embed_flutter_bootstrap.js');
      expect(embedBootstrap.statusCode, io.HttpStatus.ok);
      expect(await embedBootstrap.readAsString(), contains('__embed_main.dart.js'));

      final shelf.Response embedMain = await request('/__embed_main.dart.js');
      expect(embedMain.statusCode, io.HttpStatus.ok);
      final String mainJs = await embedMain.readAsString();
      expect(mainJs, contains('"src": "__embed_main_module.bootstrap.js"'));
      expect(mainJs, isNot(contains('"src": "/__embed_main_module.bootstrap.js"')));
      expect(
        mainJs.indexOf('dart_sdk.js'),
        lessThan(mainJs.indexOf('__embed_main_module.bootstrap.js')),
      );
      expect(mainJs, isNot(contains('indeterminate')));

      final shelf.Response embedMainModule = await request('/__embed_main_module.bootstrap.js');
      expect(embedMainModule.statusCode, io.HttpStatus.ok);
      expect(embedMainModule.headers['cache-control'], 'no-cache');
      final String moduleBootstrap = await embedMainModule.readAsString();
      expect(moduleBootstrap, startsWith('self.__wpLiveRevision=1;\n'));
      expect(moduleBootstrap, contains('"id":"packages/my_app/main.dart"'));
      expect(moduleBootstrap, contains('"id":"web_entrypoint.dart"'));
      expect(moduleBootstrap, contains('packages/my_app/main.dart.lib.js?rev='));
      expect(moduleBootstrap, contains(r'window.$dartLoader.loadConfig.maxRequestPoolSize = 100;'));
      expect(moduleBootstrap, contains('loader.addScriptsToQueue(scripts, null);'));
      expect(moduleBootstrap, isNot(contains('__ddc_bundle.js')));
      expect(moduleBootstrap, isNot(contains('{src: "on_load_end_bootstrap.js"')));
      expect(moduleBootstrap, contains(r'window.$dartLoader.loader.nextAttempt();'));
    });

    testWithoutContext('serves versioned DDC modules with immutable cache on current token and no-store on stale token', () async {
      final String bootstrap = await (await request('/__embed_main_module.bootstrap.js'))
          .readAsString();
      final RegExpMatch? match = RegExp(r'packages/my_app/main\.dart\.lib\.js\?rev=([^"]+)')
          .firstMatch(bootstrap);
      expect(match, isNotNull);
      final String currentRevToken = match!.group(1)!;

      final shelf.Response current = await request(
        '/packages/my_app/main.dart.lib.js?rev=$currentRevToken',
      );
      expect(current.statusCode, io.HttpStatus.ok);
      expect(current.headers['cross-origin-resource-policy'], 'same-site');
      expect(current.headers['x-content-type-options'], 'nosniff');
      expect(current.headers['cache-control'], 'private, max-age=31536000, immutable');
      expect(current.headers.containsKey('access-control-allow-origin'), isFalse);
      final String body = await current.readAsString();
      expect(body, contains('console.log("app");'));
      expect(body, contains('//# sourceMappingURL=main.dart.lib.js.map'));

      final shelf.Response stale = await request(
        '/packages/my_app/main.dart.lib.js?rev=other-nonce-0',
      );
      expect(stale.statusCode, io.HttpStatus.ok);
      expect(stale.headers['cache-control'], 'no-store');

      final WidgetPreviewLiveServer otherServer = createServer(
        flutterBootstrapJs: '',
        indexHtml: '',
      );
      final shelf.Response crossServer = await request(
        '/packages/my_app/main.dart.lib.js?rev=$currentRevToken',
        target: otherServer,
      );
      expect(crossServer.statusCode, io.HttpStatus.ok);
      expect(crossServer.headers['cache-control'], 'no-store');

      final WidgetPreviewLiveServer allowedServer = createServer(
        allowedOrigins: const <String>[
          'https://ide.example:8443',
          'http://localhost:3000',
          '*',
          'javascript://evil',
        ],
      );
      final shelf.Response allowedHtml = await request('/live', target: allowedServer);
      expect(
        allowedHtml.headers['content-security-policy'],
        "frame-ancestors 'self' https://ide.example:8443 http://localhost:3000",
      );
    });

    group('authorization', () {
      const authCases =
          <
            ({
              String name,
              String method,
              String url,
              Map<String, String> headers,
              int expectedStatus,
            })
          >[
            (
              name: 'rejects cross-site Origin',
              method: 'GET',
              url: '/__api/status',
              headers: <String, String>{'host': 'localhost:8080', 'origin': 'https://evil.example'},
              expectedStatus: io.HttpStatus.forbidden,
            ),
            (
              name: 'rejects cross-port loopback Origin',
              method: 'GET',
              url: '/__api/status',
              headers: <String, String>{
                'host': 'localhost:8080',
                'origin': 'http://localhost:9999',
              },
              expectedStatus: io.HttpStatus.forbidden,
            ),
            (
              name: 'rejects Sec-Fetch-Site cross-site without allowlisted Origin',
              method: 'GET',
              url: '/packages/my_app/main.dart.lib.js?rev=test-0',
              headers: <String, String>{'host': 'localhost:8080', 'sec-fetch-site': 'cross-site'},
              expectedStatus: io.HttpStatus.forbidden,
            ),
            (
              name: 'rejects Sec-Fetch-Site same-site without Origin',
              method: 'GET',
              url: '/packages/my_app/main.dart.lib.js?rev=test-0',
              headers: <String, String>{'host': 'localhost:8080', 'sec-fetch-site': 'same-site'},
              expectedStatus: io.HttpStatus.forbidden,
            ),
            (
              name: 'rejects DNS-rebinding Host and Origin pair',
              method: 'POST',
              url: 'http://evil.example:8080/__api/sync',
              headers: <String, String>{
                'host': 'evil.example:8080',
                'origin': 'http://evil.example:8080',
                'sec-fetch-site': 'same-origin',
              },
              expectedStatus: io.HttpStatus.forbidden,
            ),
            (
              name: 'allows same-port loopback equivalence',
              method: 'GET',
              url: '/__api/status',
              headers: <String, String>{
                'host': 'localhost:8080',
                'origin': 'http://127.0.0.1:8080',
              },
              expectedStatus: io.HttpStatus.ok,
            ),
            (
              name: 'rejects /dtd_ws upgrade with cross-port Origin',
              method: 'GET',
              url: '/dtd_ws',
              headers: <String, String>{
                'host': 'localhost:8080',
                'origin': 'http://localhost:9999',
                'connection': 'Upgrade',
                'upgrade': 'websocket',
              },
              expectedStatus: io.HttpStatus.forbidden,
            ),
            (
              name: 'allows explicit --web-allow-origin with cross-site Sec-Fetch-Site',
              method: 'GET',
              url: '/__api/status',
              headers: <String, String>{
                'host': 'localhost:8080',
                'origin': 'https://ide.example:8443',
                'sec-fetch-site': 'cross-site',
              },
              expectedStatus: io.HttpStatus.ok,
            ),
            (
              name:
                  'allows classic script load without Origin when Host matches --web-allow-origin',
              method: 'GET',
              url: 'http://ide.example:8443/packages/my_app/main.dart.lib.js?rev=test-0',
              headers: <String, String>{
                'host': 'ide.example:8443',
                'sec-fetch-site': 'same-origin',
              },
              expectedStatus: io.HttpStatus.ok,
            ),
            (
              name: 'rejects classic script load without Origin when Host port mismatches --web-allow-origin',
              method: 'GET',
              url: 'http://ide.example:9999/packages/my_app/main.dart.lib.js?rev=test-0',
              headers: <String, String>{
                'host': 'ide.example:9999',
                'sec-fetch-site': 'same-origin',
              },
              expectedStatus: io.HttpStatus.forbidden,
            ),
            (
              name: 'rejects classic script load without Origin on unallowed non-loopback Host',
              method: 'GET',
              url: 'http://evil.example:8443/packages/my_app/main.dart.lib.js?rev=test-0',
              headers: <String, String>{
                'host': 'evil.example:8443',
                'sec-fetch-site': 'same-origin',
              },
              expectedStatus: io.HttpStatus.forbidden,
            ),
            (
              name: 'allows Sec-Fetch-Site none without Origin',
              method: 'GET',
              url: '/__api/status',
              headers: <String, String>{'host': 'localhost:8080', 'sec-fetch-site': 'none'},
              expectedStatus: io.HttpStatus.ok,
            ),
            (
              name: 'allows request with no Host and no Origin',
              method: 'GET',
              url: '/__api/status',
              headers: <String, String>{},
              expectedStatus: io.HttpStatus.ok,
            ),
            (
              name: 'rejects request with Origin when Host header is missing',
              method: 'GET',
              url: '/__api/status',
              headers: <String, String>{'origin': 'http://localhost:8080'},
              expectedStatus: io.HttpStatus.forbidden,
            ),
          ];

      for (final authCase in authCases) {
        testWithoutContext(authCase.name, () async {
          final WidgetPreviewLiveServer serverWithAllowlist = createServer(
            allowedOrigins: const <String>['https://ide.example:8443'],
            flutterBootstrapJs: '',
            indexHtml: '',
          );
          final shelf.Response response = await request(
            authCase.url,
            method: authCase.method,
            headers: authCase.headers,
            target: serverWithAllowlist,
          );
          expect(response.statusCode, authCase.expectedStatus);
        });
      }
    });

    testWithoutContext(
      'serves /live, /__api/status, and POST /__api/sync while returning 404 for removed endpoints',
      () async {
        for (final livePath in const <String>['/live', '/live/']) {
          final shelf.Response live = await request(livePath);
          expect(live.statusCode, io.HttpStatus.ok);
          expect(live.headers['cross-origin-resource-policy'], 'same-site');
          expect(live.headers['cache-control'], 'no-cache');
          final String liveHtml = await live.readAsString();
          expect(liveHtml, contains('__embed_flutter_bootstrap.js'));
          expect(liveHtml, contains('id="wp-live-bg"'));
          expect(liveHtml, contains('background:#121212'));
          expect(liveHtml, isNot(contains('<iframe')));
        }

        for (final removedPath in const <String>[
          '/__api/capabilities',
          '/__api/previews',
          '/__api/selection',
        ]) {
          expect((await request(removedPath)).statusCode, io.HttpStatus.notFound);
        }

        final shelf.Response status = await request('/__api/status');
        expect(status.statusCode, io.HttpStatus.ok);
        final statusJson = jsonDecode(await status.readAsString()) as Map<String, Object?>;
        expect(statusJson['status'], 'ready');
        expect(statusJson['previewService'], dtdServices.widgetPreviewService);
        expect(statusJson['scaffoldService'], dtdServices.widgetPreviewScaffoldService);
        expect(statusJson['scaffoldStream'], dtdServices.widgetPreviewScaffoldStream);

        final shelf.Response sync = await request('/__api/sync', method: 'POST');
        expect(sync.statusCode, io.HttpStatus.ok);
        final syncJson = jsonDecode(await sync.readAsString()) as Map<String, Object?>;
        expect(syncJson['compileSuccess'], isTrue);
      },
    );

    testWithoutContext('GET /__api/hot-reload gates uncommitted revisions, signals fullRestartRequired, and serves versioned module JS', () async {
      for (final badUrl in const <String>['/__api/hot-reload', '/__api/hot-reload?since=-1']) {
        expect((await request(badUrl)).statusCode, io.HttpStatus.badRequest);
      }

      final int initialRevision = webMemoryFS.revision;
      server.recordReloadCommitted(fullRestart: false);

      final shelf.Response unchanged = await request('/__api/hot-reload?since=$initialRevision');
      expect(unchanged.statusCode, io.HttpStatus.ok);
      expect(jsonDecode(await unchanged.readAsString()), <String, Object?>{
        'revision': initialRevision,
        'scaffoldStream': dtdServices.widgetPreviewScaffoldStream,
        'fullRestartRequired': false,
        'modules': const <Object?>[],
      });

      webMemoryFS.metadataFiles['packages/my_app/main.dart.lib.js.metadata'] = Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'version': '2.0.0',
            'name': 'packages/my_app/main.dart',
            'closureName': 'load__main',
            'sourceMapUri': 'packages/my_app/main.dart.lib.js.map',
            'moduleUri': 'packages/my_app/main.dart.lib.js',
            'libraries': <Map<String, Object?>>[
              <String, Object?>{
                'name': 'main',
                'importUri': 'package:my_app/main.dart',
                'partUris': const <String>[],
              },
            ],
          }),
        ),
      );
      webMemoryFS.writeFileBytes(
        'packages/my_app/main.dart.lib.js',
        Uint8List.fromList(
          utf8.encode('console.log("app v2");\n//# sourceMappingURL=main.dart.lib.js.map\n'),
        ),
      );
      final int updatedRevision = webMemoryFS.revision;
      expect(updatedRevision, initialRevision + 1);

      // Before commit, uncommitted revisions are hidden from live viewers.
      final shelf.Response uncommitted = await request('/__api/hot-reload?since=$initialRevision');
      expect(uncommitted.statusCode, io.HttpStatus.ok);
      expect(jsonDecode(await uncommitted.readAsString()), <String, Object?>{
        'revision': initialRevision,
        'scaffoldStream': dtdServices.widgetPreviewScaffoldStream,
        'fullRestartRequired': false,
        'modules': const <Object?>[],
      });

      server.recordReloadCommitted(fullRestart: false);
      final shelf.Response delta = await request('/__api/hot-reload?since=$initialRevision');
      expect(delta.statusCode, io.HttpStatus.ok);
      final deltaJson = jsonDecode(await delta.readAsString()) as Map<String, Object?>;
      expect(deltaJson['revision'], updatedRevision);
      expect(deltaJson['scaffoldStream'], dtdServices.widgetPreviewScaffoldStream);
      expect(deltaJson['fullRestartRequired'], isFalse);
      final changedModules = deltaJson['modules']! as List<Object?>;
      expect(changedModules, hasLength(1));
      final firstModule = changedModules.single! as Map<String, Object?>;
      final moduleSrc = firstModule['src']! as String;
      expect(moduleSrc, startsWith('packages/my_app/main.dart.lib.js?rev='));
      expect(moduleSrc, endsWith('-$updatedRevision'));
      expect(firstModule['id'], 'packages/my_app/main.dart');
      expect(firstModule['libraries'], const <String>['package:my_app/main.dart']);

      final shelf.Response moduleJs = await request('/$moduleSrc');
      expect(moduleJs.statusCode, io.HttpStatus.ok);
      expect(moduleJs.headers['cross-origin-resource-policy'], 'same-site');
      expect(moduleJs.headers['cache-control'], 'private, max-age=31536000, immutable');
      expect(
        await moduleJs.readAsString(),
        'console.log("app v2");\n//# sourceMappingURL=main.dart.lib.js.map\n',
      );

      webMemoryFS.metadataFiles.remove('packages/my_app/main.dart.lib.js.metadata');
      expect(
        (await request('/__api/hot-reload?since=$initialRevision')).statusCode,
        io.HttpStatus.internalServerError,
      );

      // After a full restart commit, viewers behind the restart revision must
      // receive fullRestartRequired: true instead of an incremental delta.
      webMemoryFS.incrementRevision();
      final int restartRevision = webMemoryFS.revision;
      server.recordReloadCommitted(fullRestart: true);
      final shelf.Response restartDelta = await request('/__api/hot-reload?since=$initialRevision');
      expect(restartDelta.statusCode, io.HttpStatus.ok);
      expect(jsonDecode(await restartDelta.readAsString()), <String, Object?>{
        'revision': restartRevision,
        'scaffoldStream': dtdServices.widgetPreviewScaffoldStream,
        'fullRestartRequired': true,
        'modules': const <Object?>[],
      });

      final shelf.Response caughtUp = await request('/__api/hot-reload?since=$restartRevision');
      expect(caughtUp.statusCode, io.HttpStatus.ok);
      expect(jsonDecode(await caughtUp.readAsString()), <String, Object?>{
        'revision': restartRevision,
        'scaffoldStream': dtdServices.widgetPreviewScaffoldStream,
        'fullRestartRequired': false,
        'modules': const <Object?>[],
      });
    });

    testWithoutContext(
      '/dtd_ws enforces maxActiveWebSockets cap and releases slots on close',
      () async {
        final controllers = <StreamChannelController<Object?>>[];
        final WidgetPreviewLiveServer cappedServer = createServer(
          maxActiveWebSockets: 2,
          dtdWebSocketConnector: (_) {
            final controller = StreamChannelController<Object?>();
            controller.foreign.stream.listen((_) {});
            controllers.add(controller);
            return _FakeWebSocketChannel(controller.local);
          },
          flutterBootstrapJs: '',
          indexHtml: '',
        );
        final io.HttpServer httpServer = await shelf_io.serve(
          cappedServer.handler,
          io.InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() async {
          for (final c in controllers) {
            unawaited(c.local.sink.close());
            unawaited(c.foreign.sink.close());
          }
          await httpServer.close(force: true);
        });

        final Uri wsUri = Uri.parse('ws://127.0.0.1:${httpServer.port}/dtd_ws');
        final client1 = IOWebSocketChannel.connect(wsUri);
        await client1.ready;
        final StreamSubscription<Object?> sub1 = client1.stream.listen((_) {});
        final client2 = IOWebSocketChannel.connect(wsUri);
        await client2.ready;
        final StreamSubscription<Object?> sub2 = client2.stream.listen((_) {});

        final httpClient = io.HttpClient();
        addTearDown(() => httpClient.close(force: true));
        final io.HttpClientRequest rejectedReq = await httpClient.getUrl(
          Uri.parse('http://127.0.0.1:${httpServer.port}/dtd_ws'),
        );
        final io.HttpClientResponse rejectedRes = await rejectedReq.close();
        expect(rejectedRes.statusCode, io.HttpStatus.serviceUnavailable);
        expect(rejectedRes.headers.value('retry-after'), '5');
        await rejectedRes.drain<void>();

        await client1.sink.close();
        await sub1.cancel();
        await controllers.first.foreign.sink.close();
        await controllers.first.local.sink.done;

        final client3 = IOWebSocketChannel.connect(wsUri);
        await client3.ready;
        final StreamSubscription<Object?> sub3 = client3.stream.listen((_) {});
        await client2.sink.close();
        await client3.sink.close();
        await sub2.cancel();
        await sub3.cancel();
      },
    );

    testWithoutContext(
      '/dtd_ws enforces JSON-RPC allowlist and rejects disallowed methods',
      () async {
        final forwardedToUpstream = <Map<String, Object?>>[];
        final upstreamController = StreamChannelController<Object?>();
        upstreamController.foreign.stream.listen((Object? message) {
          final decoded = jsonDecode(message! as String) as Map<String, Object?>;
          forwardedToUpstream.add(decoded);
          upstreamController.foreign.sink.add(
            jsonEncode(<String, Object?>{
              'jsonrpc': '2.0',
              'id': decoded['id'],
              'result': <String, Object?>{'ok': true},
            }),
          );
        });

        final WidgetPreviewLiveServer wsServer = createServer(
          dtdWebSocketConnector: (_) => _FakeWebSocketChannel(upstreamController.local),
          flutterBootstrapJs: '',
          indexHtml: '',
        );
        final io.HttpServer httpServer = await shelf_io.serve(
          wsServer.handler,
          io.InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() async {
          await upstreamController.local.sink.close();
          await upstreamController.foreign.sink.close();
          await httpServer.close(force: true);
        });

        final client = IOWebSocketChannel.connect(
          Uri.parse('ws://127.0.0.1:${httpServer.port}/dtd_ws'),
        );
        final responses = StreamIterator<Object?>(client.stream);

        Future<Map<String, Object?>> sendRpc(Object payload) async {
          client.sink.add(payload is String ? payload : jsonEncode(payload));
          expect(await responses.moveNext(), isTrue);
          return jsonDecode(responses.current! as String) as Map<String, Object?>;
        }

        expect(
          (await sendRpc(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'streamListen',
            'params': <String, Object?>{'streamId': dtdServices.widgetPreviewScaffoldStream},
          }))['result'],
          <String, Object?>{'ok': true},
        );

        final Map<String, Object?> listResp = await sendRpc(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 3,
          'method': '${dtdServices.widgetPreviewService}.listPreviews',
          'params': <String, Object?>{'sync': true, 'fileUri': 'file:///tmp/a.dart'},
        });
        expect(listResp['result'], <String, Object?>{'ok': true});
        expect(forwardedToUpstream.last['params'], <String, Object?>{
          'sync': false,
          'fileUri': 'file:///tmp/a.dart',
        });

        expect(
          (await sendRpc(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 4,
            'method': '${dtdServices.widgetPreviewScaffoldService}.getPreviews',
          }))['result'],
          <String, Object?>{'ok': true},
        );

        final Map<String, Object?> getServiceInfoResp = await sendRpc(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 2,
          'method': '${dtdServices.widgetPreviewService}.getServiceInfo',
          'params': <String, Object?>{'unexpected': true},
        });
        final serviceInfoResult = getServiceInfoResp['result']! as Map<String, Object?>;
        expect(serviceInfoResult, <String, Object?>{
          'type': 'PreviewServiceInfo',
          'previewService': dtdServices.widgetPreviewService,
          'scaffoldService': dtdServices.widgetPreviewScaffoldService,
          'scaffoldStream': dtdServices.widgetPreviewScaffoldStream,
          'webPreviewUri': dtdServices.webPreviewUriProvider?.call()?.toString(),
          'scaffoldConnected': dtdServices.scaffoldConnected,
        });
        expect(serviceInfoResult.containsKey('dtdUri'), isFalse);
        expect(serviceInfoResult.containsKey('projectRoot'), isFalse);
        expect(forwardedToUpstream, hasLength(3));

        for (final (int id, String method) in <(int, String)>[
          (5, 'FileSystem.readFileAsString'),
          (6, 'registerService'),
          (7, 'postEvent'),
          (8, '${dtdServices.widgetPreviewScaffoldService}.capturePreview'),
          (9, '${dtdServices.widgetPreviewService}.syncPreviews'),
          (10, '${dtdServices.widgetPreviewService}.getSelection'),
          (11, '${dtdServices.widgetPreviewService}.setSelection'),
        ]) {
          final Map<String, Object?> err = await sendRpc(<String, Object?>{
            'jsonrpc': '2.0',
            'id': id,
            'method': method,
          });
          expect((err['error']! as Map<String, Object?>)['code'], -32601);
        }

        for (final (Object payload, int expectedCode) in <(Object, int)>[
          (
            '{"jsonrpc":"2.0","id":45,"method":"${dtdServices.widgetPreviewService}.listPreviews",'
                '"params":{"fileUri":"${'x' * (64 * 1024)}"}}',
            -32600,
          ),
          (
            <String, Object?>{
              'jsonrpc': '2.0',
              'id': 12,
              'method': 'streamListen',
              'params': <String, Object?>{'streamId': 'Editor'},
            },
            -32601,
          ),
          ('{not-json', -32700),
          ('[1, 2]', -32600),
          (
            <String, Object?>{
              'jsonrpc': '2.0',
              'id': 13,
              'method': 'streamListen',
              'params': <int>[1],
            },
            -32602,
          ),
          (
            <String, Object?>{
              'jsonrpc': '2.0',
              'method': 'streamListen',
              'params': <String, Object?>{'streamId': dtdServices.widgetPreviewScaffoldStream},
            },
            -32600,
          ),
        ]) {
          final Map<String, Object?> err = await sendRpc(payload);
          expect((err['error']! as Map<String, Object?>)['code'], expectedCode);
        }

        expect(forwardedToUpstream, hasLength(3));
        await client.sink.close();
      },
    );

    testWithoutContext(
      '/dtd_ws closes viewer channel when upstream closes and on server dispose',
      () async {
        Future<
          ({
            IOWebSocketChannel client,
            StreamChannelController<Object?> upstreamController,
            WidgetPreviewLiveServer wsServer,
          })
        >
        connectBridge() async {
          final upstreamController = StreamChannelController<Object?>();
          unawaited(upstreamController.foreign.stream.drain<void>());
          final WidgetPreviewLiveServer wsServer = createServer(
            dtdWebSocketConnector: (_) => _FakeWebSocketChannel(upstreamController.local),
            flutterBootstrapJs: '',
            indexHtml: '',
          );
          final io.HttpServer httpServer = await shelf_io.serve(
            wsServer.handler,
            io.InternetAddress.loopbackIPv4,
            0,
          );
          addTearDown(() async {
            await upstreamController.local.sink.close();
            await upstreamController.foreign.sink.close();
            await httpServer.close(force: true);
          });
          final client = IOWebSocketChannel.connect(
            Uri.parse('ws://127.0.0.1:${httpServer.port}/dtd_ws'),
          );
          await client.ready;
          return (client: client, upstreamController: upstreamController, wsServer: wsServer);
        }

        final (
          :IOWebSocketChannel client,
          :StreamChannelController<Object?> upstreamController,
          wsServer: _,
        ) = await connectBridge();
        await upstreamController.foreign.sink.close();
        await expectLater(client.stream, emitsDone);

        final (
          client: IOWebSocketChannel client2,
          upstreamController: _,
          :WidgetPreviewLiveServer wsServer,
        ) = await connectBridge();
        await wsServer.dispose();
        await expectLater(client2.stream, emitsDone);
      },
    );

    testWithoutContext('returns 503 JSON error when POST /__api/sync times out', () async {
      final WidgetPreviewLiveServer timeoutServer = createServer(
        dtdServicesOverride: _FakeWidgetPreviewDtdServices(
          fs: fs,
          logger: logger,
          project: project,
          onSyncPreviews: ({required Duration timeout}) =>
              throw TimeoutException('Sync timed out', timeout),
        ),
        modulesOverride: const <String, String>{},
      );
      final shelf.Response response = await request(
        '/__api/sync',
        method: 'POST',
        target: timeoutServer,
      );
      expect(response.statusCode, io.HttpStatus.serviceUnavailable);
      expect(jsonDecode(await response.readAsString()), <String, Object?>{
        'error': contains('Sync timed out'),
      });
    });

    testWithoutContext(
      'rewrites embed URLs as root-relative under basePath and throws on missing marker',
      () async {
        final WidgetPreviewLiveServer subappServer = createServer(
          basePath: 'subapp',
          modulesOverride: const <String, String>{'main_module': 'main_module'},
          flutterBootstrapJs: 'load("main.dart.js");',
          indexHtml: '<script src="flutter_bootstrap.js"></script>',
        );
        final shelf.Response liveResponse = await request('/subapp/live/', target: subappServer);
        expect(liveResponse.statusCode, io.HttpStatus.ok);
        expect(
          await liveResponse.readAsString(),
          contains('src="/subapp/__embed_flutter_bootstrap.js"'),
        );

        final shelf.Response mainJsResponse = await request(
          '/subapp/__embed_main.dart.js',
          target: subappServer,
        );
        expect(mainJsResponse.statusCode, io.HttpStatus.ok);
        final String subappMainJs = await mainJsResponse.readAsString();
        expect(subappMainJs, contains('"src": "__embed_main_module.bootstrap.js"'));
        expect(subappMainJs, isNot(contains('/subapp/__embed_main_module.bootstrap.js')));

        webMemoryFS.files['main_module.bootstrap.js'] = utf8.encode('console.log("no marker");');
        await expectLater(
          request('/subapp/__embed_main_module.bootstrap.js', target: subappServer),
          throwsA(isA<StateError>()),
        );
      },
    );
  });

  group('$WebAssetServer live wiring', () {
    Future<WebAssetServer> startServer({
      WidgetPreviewLiveConfig? liveConfig,
      String? baseHref,
    }) async {
      final WebAssetServer server = await WebAssetServer.start(
        null,
        null,
        false,
        false,
        false,
        BuildInfo.debug,
        false,
        const DartDevelopmentServiceConfiguration(enable: false),
        Uri.parse('file:///tmp/my_app/lib/main.dart'),
        null,
        crossOriginIsolation: false,
        webDevServerConfig: WebDevServerConfig(host: '127.0.0.1', baseHref: baseHref),
        webRenderer: WebRendererMode.canvaskit,
        isWasm: false,
        useLocalCanvasKit: false,
        toolContext: FakeToolContext(
          artifacts: Artifacts.test(),
          cache: Cache.test(processManager: FakeProcessManager.any()),
          config: Config.test(),
          fs: fs,
          flutterVersion: FakeFlutterVersion(),
          logger: logger,
          platform: FakePlatform(),
        ),
        dwdsLauncher: ({
          required AssetReader assetReader,
          required Stream<BuildResult> buildResults,
          required ConnectionProvider chromeConnection,
          required ToolConfiguration toolConfiguration,
          bool useDwdsWebSocketConnection = false,
        }) async => _FakeDwds(),
        widgetPreviewLiveConfig: liveConfig,
      );
      server.markReady();
      return server;
    }

    Future<({int statusCode, Map<String, String> headers, String body})> httpGet(
      io.HttpClient client,
      int port,
      String path,
    ) async {
      final io.HttpClientRequest req = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port$path'),
      );
      final io.HttpClientResponse res = await req.close();
      final String body = await utf8.decoder.bind(res).join();
      final headers = <String, String>{};
      res.headers.forEach((String name, List<String> values) {
        headers[name] = values.join(', ');
      });
      return (statusCode: res.statusCode, headers: headers, body: body);
    }

    testWithoutContext(
      'mounts live handler before DWDS, bumps revision on writeBytes, and supports basePath',
      () async {
        final WebAssetServer server = await startServer(
          liveConfig: WidgetPreviewLiveConfig(dtdServices: dtdServices),
          baseHref: '/subapp/',
        );
        final client = io.HttpClient();
        addTearDown(() async {
          client.close(force: true);
          await server.dispose();
        });

        server.writeFile('packages/my_app/main.dart.lib.js', 'console.log("v1");');
        server.writeFile(
          'main_module.bootstrap.js',
          generateDDCLibraryBundleMainModule(
            entrypoint: 'web_entrypoint.dart',
            nativeNullAssertions: true,
            onLoadEndBootstrap: 'on_load_end_bootstrap.js',
            isCi: false,
          ),
        );
        server.updateModulesAndDigests(<String>['packages/my_app/main.dart.lib.js']);

        final ({String body, Map<String, String> headers, int statusCode}) normalRoot =
            await httpGet(client, server.selectedPort, '/subapp/');
        expect(normalRoot.statusCode, io.HttpStatus.ok);
        expect(normalRoot.body, contains('/* DWDS_INJECTED */'));

        for (final bypassPath in const <String>[
          '/subapp/?embed=1',
          '/subapp/__embed_main_module.bootstrap.js',
        ]) {
          final ({String body, Map<String, String> headers, int statusCode}) res = await httpGet(
            client,
            server.selectedPort,
            bypassPath,
          );
          expect(res.statusCode, io.HttpStatus.ok);
          expect(res.body, isNot(contains('/* DWDS_INJECTED */')));
        }

        expect((await httpGet(client, server.selectedPort, '/subapp/live')).statusCode, 200);
        final ({String body, Map<String, String> headers, int statusCode}) liveSlash =
            await httpGet(client, server.selectedPort, '/subapp/live/');
        expect(liveSlash.statusCode, io.HttpStatus.ok);
        expect(liveSlash.body, contains('__embed_main.dart.js'));
        expect(
          (await httpGet(client, server.selectedPort, '/subapp/__api/status')).statusCode,
          200,
        );

        final ({String body, Map<String, String> headers, int statusCode}) bootstrap1 =
            await httpGet(client, server.selectedPort, '/subapp/__embed_main_module.bootstrap.js');
        expect(bootstrap1.statusCode, io.HttpStatus.ok);
        final RegExpMatch? match1 = RegExp(r'packages/my_app/main\.dart\.lib\.js\?rev=([^"]+)')
            .firstMatch(bootstrap1.body);
        expect(match1, isNotNull);
        final String rev1 = match1!.group(1)!;
        final ({String body, Map<String, String> headers, int statusCode}) mod1 = await httpGet(
          client,
          server.selectedPort,
          '/subapp/packages/my_app/main.dart.lib.js?rev=$rev1',
        );
        expect(mod1.statusCode, io.HttpStatus.ok);
        expect(mod1.headers['cache-control'], 'private, max-age=31536000, immutable');
        expect(mod1.body, contains('console.log("v1");'));

        server.writeBytes(
          'packages/my_app/main.dart.lib.js',
          Uint8List.fromList(utf8.encode('console.log("v2");')),
        );
        final ({String body, Map<String, String> headers, int statusCode}) bootstrap2 =
            await httpGet(client, server.selectedPort, '/subapp/__embed_main_module.bootstrap.js');
        final RegExpMatch? match2 = RegExp(r'packages/my_app/main\.dart\.lib\.js\?rev=([^"]+)')
            .firstMatch(bootstrap2.body);
        expect(match2, isNotNull);
        final String rev2 = match2!.group(1)!;
        expect(rev2, isNot(rev1));
        final ({String body, Map<String, String> headers, int statusCode}) mod2 = await httpGet(
          client,
          server.selectedPort,
          '/subapp/packages/my_app/main.dart.lib.js?rev=$rev2',
        );
        expect(mod2.statusCode, io.HttpStatus.ok);
        expect(mod2.headers['cache-control'], 'private, max-age=31536000, immutable');
        expect(mod2.body, contains('console.log("v2");'));
      },
    );

    testWithoutContext('does not mount live routes when widgetPreviewLiveConfig is null', () async {
      final WebAssetServer server = await startServer();
      final client = io.HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.dispose();
      });

      final ({String body, Map<String, String> headers, int statusCode}) status = await httpGet(
        client,
        server.selectedPort,
        '/__api/status',
      );
      expect(status.headers['content-type'], isNot(contains('application/json')));
      expect(status.body, contains('/* DWDS_INJECTED */'));
    });
  });
}

class _FakeDwds extends Fake implements Dwds {
  @override
  shelf.Middleware get middleware => (shelf.Handler innerHandler) {
    return (shelf.Request request) async {
      final shelf.Response response = await innerHandler(request);
      final String body = await response.readAsString();
      return response.change(body: '$body\n/* DWDS_INJECTED */');
    };
  };

  @override
  shelf.Handler get handler =>
      (shelf.Request request) => shelf.Response.notFound('');

  @override
  Future<void> stop() async {}
}

class _FakeWebSocketChannel extends StreamChannelMixin<Object?> implements WebSocketChannel {
  _FakeWebSocketChannel(this._inner);

  final StreamChannel<Object?> _inner;

  @override
  Stream<Object?> get stream => _inner.stream;

  @override
  WebSocketSink get sink => _FakeWebSocketSink(_inner.sink);

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future<void>.value();
}

class _FakeWebSocketSink extends DelegatingStreamSink<Object?> implements WebSocketSink {
  _FakeWebSocketSink(super.sink);

  @override
  Future<void> close([int? closeCode, String? closeReason]) => super.close();
}

class _FakeDtdLauncher extends Fake implements DtdLauncher {
  @override
  Future<void> dispose() async {}
}

class _FakeWidgetPreviewDtdServices extends WidgetPreviewDtdServices {
  _FakeWidgetPreviewDtdServices({
    required super.fs,
    required super.logger,
    required super.project,
    Future<SyncPreviewsResponse> Function({required Duration timeout})? onSyncPreviews,
    super.projectRootPath,
  }) : super(
         addUuidToServiceName: false,
         dtdLauncher: _FakeDtdLauncher(),
         onHotRestartPreviewerRequest: () {},
         previewAnalytics: WidgetPreviewAnalytics(analytics: const NoOpAnalytics()),
         shutdownHooks: ShutdownHooks(),
         onSyncPreviews:
             onSyncPreviews ??
             ({required Duration timeout}) async => const SyncPreviewsResponse(
               compileSuccess: true,
               errorPreviewCount: 0,
               fullRestart: false,
               reloaded: true,
             ),
       );

  @override
  Uri? get dtdUri => Uri.parse('ws://127.0.0.1:12345/dtd');
}

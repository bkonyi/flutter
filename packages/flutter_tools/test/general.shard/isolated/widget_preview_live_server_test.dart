// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:dtd/dtd.dart';
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
import 'package:flutter_tools/src/widget_preview/preview_selection_store.dart';
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
  group('$WidgetPreviewLiveServer', () {
    late MemoryFileSystem fs;
    late BufferLogger logger;
    late _FakeWidgetPreviewDtdServices dtdServices;
    late WebMemoryFS webMemoryFS;
    late Map<String, String> modules;
    late WidgetPreviewLiveServer server;

    setUp(() {
      fs = MemoryFileSystem.test();
      fs.file('HostArtifact.flutterJsDirectory/flutter.js')
        ..createSync(recursive: true)
        ..writeAsStringSync('// flutter.js');
      logger = BufferLogger.test();
      final Directory projectDir = fs.directory('/tmp/my_app')..createSync(recursive: true);
      projectDir.childFile('pubspec.yaml').writeAsStringSync('name: my_app\n');
      final FlutterProject project = FlutterProject.fromDirectoryTest(projectDir);
      dtdServices = _FakeWidgetPreviewDtdServices(
        fs: fs,
        logger: logger,
        project: project,
        projectRootPath: projectDir.path,
      );
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

      server = WidgetPreviewLiveServer(
        basePathProvider: () => '',
        config: WidgetPreviewLiveConfig(dtdServices: dtdServices),
        configuredHost: 'localhost',
        isWindows: false,
        modules: modules,
        renderFlutterBootstrapJs: () =>
            'window._flutter.buildConfig = {"builds":[{"mainJsPath":"main.dart.js"}]};',
        renderIndexHtml: () =>
            '<html><body><script src="flutter_bootstrap.js" async></script></body></html>',
        webMemoryFS: webMemoryFS,
      );
    });

    tearDown(() async {
      await server.dispose();
    });

    testWithoutContext('separates GET / from GET /?embed=1 and rewrites embed bootstrap', () async {
      final shelf.Response normalRoot = await server.handler(
        shelf.Request('GET', Uri.parse('http://localhost:8080/')),
      );
      expect(normalRoot.statusCode, io.HttpStatus.notFound);

      final shelf.Response embedRoot = await server.handler(
        shelf.Request('GET', Uri.parse('http://localhost:8080/?embed=1')),
      );
      expect(embedRoot.statusCode, io.HttpStatus.ok);
      expect(embedRoot.headers['cross-origin-resource-policy'], 'same-site');
      expect(embedRoot.headers['x-content-type-options'], 'nosniff');
      expect(embedRoot.headers.containsKey('access-control-allow-origin'), isFalse);
      final String embedHtml = await embedRoot.readAsString();
      expect(embedHtml, contains('__embed_flutter_bootstrap.js'));
      expect(embedHtml, isNot(contains('"flutter_bootstrap.js"')));

      final shelf.Response embedBootstrap = await server.handler(
        shelf.Request('GET', Uri.parse('http://localhost:8080/__embed_flutter_bootstrap.js')),
      );
      expect(embedBootstrap.statusCode, io.HttpStatus.ok);
      expect(await embedBootstrap.readAsString(), contains('__embed_main.dart.js'));

      final shelf.Response embedMain = await server.handler(
        shelf.Request('GET', Uri.parse('http://localhost:8080/__embed_main.dart.js')),
      );
      expect(embedMain.statusCode, io.HttpStatus.ok);
      final String mainJs = await embedMain.readAsString();
      expect(mainJs, contains('__embed_main_module.bootstrap.js'));
      expect(
        mainJs.indexOf('dart_sdk.js'),
        lessThan(mainJs.indexOf('__embed_main_module.bootstrap.js')),
      );
      expect(mainJs, isNot(contains('indeterminate')));

      final shelf.Response embedMainModule = await server.handler(
        shelf.Request('GET', Uri.parse('http://localhost:8080/__embed_main_module.bootstrap.js')),
      );
      expect(embedMainModule.statusCode, io.HttpStatus.ok);
      final String moduleBootstrap = await embedMainModule.readAsString();
      expect(moduleBootstrap, contains('"id":"packages/my_app/main.dart"'));
      expect(moduleBootstrap, contains('"id":"web_entrypoint.dart"'));
      expect(moduleBootstrap, contains('src: "__ddc_bundle.js"'));
      expect(moduleBootstrap, isNot(contains('{src: "on_load_end_bootstrap.js"')));
      expect(moduleBootstrap, contains(r'window.$dartLoader.loader.nextAttempt();'));
    });

    testWithoutContext(
      '/__ddc_bundle.js concatenates modules, caches by revision, supports 304 and gzip',
      () async {
        final shelf.Response first = await server.handler(
          shelf.Request('GET', Uri.parse('http://localhost:8080/__ddc_bundle.js')),
        );
        expect(first.statusCode, io.HttpStatus.ok);
        final String? etag1 = first.headers['etag'];
        expect(etag1, isNotNull);
        expect(etag1, endsWith('-rev-1"'));
        expect(first.headers['cross-origin-resource-policy'], 'same-site');
        expect(first.headers['x-content-type-options'], 'nosniff');
        expect(first.headers.containsKey('access-control-allow-origin'), isFalse);

        final String body = await first.readAsString();
        expect(body, contains('console.log("app");'));
        expect(body, contains('console.log("entry");'));
        expect(body, isNot(contains('//# sourceMappingURL=')));

        final shelf.Response notModified = await server.handler(
          shelf.Request(
            'GET',
            Uri.parse('http://localhost:8080/__ddc_bundle.js'),
            headers: <String, String>{'if-none-match': etag1!},
          ),
        );
        expect(notModified.statusCode, io.HttpStatus.notModified);

        final shelf.Response gzipped = await server.handler(
          shelf.Request(
            'GET',
            Uri.parse('http://localhost:8080/__ddc_bundle.js'),
            headers: <String, String>{'accept-encoding': 'gzip, deflate'},
          ),
        );
        expect(gzipped.statusCode, io.HttpStatus.ok);
        expect(gzipped.headers['content-encoding'], 'gzip');
        final List<int> compressedBytes = await gzipped.read().expand((List<int> c) => c).toList();
        final String decompressed = utf8.decode(io.gzip.decode(compressedBytes));
        expect(decompressed, body);

        // Respects gzip;q=0 and serves uncompressed UTF-8.
        final shelf.Response gzipRejected = await server.handler(
          shelf.Request(
            'GET',
            Uri.parse('http://localhost:8080/__ddc_bundle.js'),
            headers: <String, String>{'accept-encoding': 'gzip;q=0, identity'},
          ),
        );
        expect(gzipRejected.statusCode, io.HttpStatus.ok);
        expect(gzipRejected.headers.containsKey('content-encoding'), isFalse);
        expect(await gzipRejected.readAsString(), body);

        // Separate server instances produce distinct ETags for the same revision.
        final otherServer = WidgetPreviewLiveServer(
          basePathProvider: () => '',
          config: WidgetPreviewLiveConfig(dtdServices: dtdServices),
          configuredHost: 'localhost',
          isWindows: false,
          modules: modules,
          renderFlutterBootstrapJs: () => '',
          renderIndexHtml: () => '',
          webMemoryFS: webMemoryFS,
        );
        addTearDown(otherServer.dispose);
        final shelf.Response otherFirst = await otherServer.handler(
          shelf.Request('GET', Uri.parse('http://localhost:8080/__ddc_bundle.js')),
        );
        expect(otherFirst.headers['etag'], isNot(first.headers['etag']));

        // Incrementing revision invalidates cache and updates ETag.
        webMemoryFS.incrementRevision();
        final shelf.Response second = await server.handler(
          shelf.Request(
            'GET',
            Uri.parse('http://localhost:8080/__ddc_bundle.js'),
            headers: <String, String>{'if-none-match': etag1},
          ),
        );
        expect(second.statusCode, io.HttpStatus.ok);
        expect(second.headers['etag'], endsWith('-rev-2"'));
      },
    );

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
              url: 'http://localhost:8080/__api/status',
              headers: <String, String>{'host': 'localhost:8080', 'origin': 'https://evil.example'},
              expectedStatus: io.HttpStatus.forbidden,
            ),
            (
              name: 'rejects cross-port loopback Origin',
              method: 'GET',
              url: 'http://localhost:8080/__api/status',
              headers: <String, String>{
                'host': 'localhost:8080',
                'origin': 'http://localhost:9999',
              },
              expectedStatus: io.HttpStatus.forbidden,
            ),
            (
              name: 'rejects Sec-Fetch-Site cross-site without allowlisted Origin',
              method: 'GET',
              url: 'http://localhost:8080/__ddc_bundle.js',
              headers: <String, String>{'host': 'localhost:8080', 'sec-fetch-site': 'cross-site'},
              expectedStatus: io.HttpStatus.forbidden,
            ),
            (
              name: 'rejects Sec-Fetch-Site same-site without Origin',
              method: 'GET',
              url: 'http://localhost:8080/__ddc_bundle.js',
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
              url: 'http://localhost:8080/__api/status',
              headers: <String, String>{
                'host': 'localhost:8080',
                'origin': 'http://127.0.0.1:8080',
              },
              expectedStatus: io.HttpStatus.ok,
            ),
            (
              name: 'rejects /dtd_ws upgrade with cross-port Origin',
              method: 'GET',
              url: 'http://localhost:8080/dtd_ws',
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
              url: 'http://localhost:8080/__api/status',
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
              url: 'http://ide.example:8443/__ddc_bundle.js',
              headers: <String, String>{
                'host': 'ide.example:8443',
                'sec-fetch-site': 'same-origin',
              },
              expectedStatus: io.HttpStatus.ok,
            ),
            (
              name: 'rejects classic script load without Origin when Host port mismatches --web-allow-origin',
              method: 'GET',
              url: 'http://ide.example:9999/__ddc_bundle.js',
              headers: <String, String>{
                'host': 'ide.example:9999',
                'sec-fetch-site': 'same-origin',
              },
              expectedStatus: io.HttpStatus.forbidden,
            ),
            (
              name: 'rejects classic script load without Origin on unallowed non-loopback Host',
              method: 'GET',
              url: 'http://evil.example:8443/__ddc_bundle.js',
              headers: <String, String>{
                'host': 'evil.example:8443',
                'sec-fetch-site': 'same-origin',
              },
              expectedStatus: io.HttpStatus.forbidden,
            ),
            (
              name: 'allows Sec-Fetch-Site none without Origin',
              method: 'GET',
              url: 'http://localhost:8080/__api/status',
              headers: <String, String>{'host': 'localhost:8080', 'sec-fetch-site': 'none'},
              expectedStatus: io.HttpStatus.ok,
            ),
            (
              name: 'allows request with no Host and no Origin',
              method: 'GET',
              url: 'http://localhost:8080/__api/status',
              headers: <String, String>{},
              expectedStatus: io.HttpStatus.ok,
            ),
            (
              name: 'rejects request with Origin when Host header is missing',
              method: 'GET',
              url: 'http://localhost:8080/__api/status',
              headers: <String, String>{'origin': 'http://localhost:8080'},
              expectedStatus: io.HttpStatus.forbidden,
            ),
          ];

      for (final authCase in authCases) {
        testWithoutContext(authCase.name, () async {
          final serverWithAllowlist = WidgetPreviewLiveServer(
            basePathProvider: () => '',
            config: WidgetPreviewLiveConfig(
              dtdServices: dtdServices,
              allowedOrigins: const <String>['https://ide.example:8443'],
            ),
            configuredHost: 'localhost',
            isWindows: false,
            modules: modules,
            renderFlutterBootstrapJs: () => '',
            renderIndexHtml: () => '',
            webMemoryFS: webMemoryFS,
          );
          addTearDown(serverWithAllowlist.dispose);

          final shelf.Response response = await serverWithAllowlist.handler(
            shelf.Request(authCase.method, Uri.parse(authCase.url), headers: authCase.headers),
          );
          expect(response.statusCode, authCase.expectedStatus);
        });
      }
    });

    testWithoutContext(
      'serves /live, /__api/status, /__api/previews, and POST /__api/sync',
      () async {
        final shelf.Response live = await server.handler(
          shelf.Request('GET', Uri.parse('http://localhost:8080/live')),
        );
        expect(live.statusCode, io.HttpStatus.ok);
        expect(live.headers['cross-origin-resource-policy'], 'same-site');
        final String liveHtml = await live.readAsString();
        expect(liveHtml, contains('All Previews'));
        expect(liveHtml, contains('id="zoom-out"'));
        expect(liveHtml, contains('id="zoom-reset"'));
        expect(liveHtml, contains('id="zoom-in"'));
        expect(liveHtml, contains('id="select-toggle"'));
        expect(liveHtml, contains('id="selection-bar"'));
        expect(liveHtml, contains('id="copy-selection-btn"'));
        expect(liveHtml, contains('id="selection-clear"'));
        expect(liveHtml, contains('flutter-widget-preview-selections'));
        expect(liveHtml, contains('flutter-widget-preview-set-select-mode'));
        expect(liveHtml, contains('flutter-widget-preview-clear-selections'));
        expect(liveHtml, contains('__api/selection'));
        expect(liveHtml, contains('#sync-btn:disabled'));
        expect(liveHtml, contains('flutter-widget-preview-zoom'));
        expect(liveHtml, contains('__api/sync'));
        expect(liveHtml, contains("frame.addEventListener('load'"));
        expect(liveHtml, contains('clearLocalSelections();'));
        expect(liveHtml, contains('__api/previews'));
        expect(liveHtml, isNot(contains('src="./?embed=1')));
        expect(liveHtml, contains("window.location.pathname.endsWith('/') ? '../' : './'"));
        expect(liveHtml, contains("rootPrefix + '?embed=1#'"));

        final shelf.Response liveSlash = await server.handler(
          shelf.Request('GET', Uri.parse('http://localhost:8080/live/')),
        );
        expect(liveSlash.statusCode, io.HttpStatus.ok);
        final String liveSlashHtml = await liveSlash.readAsString();
        expect(liveSlashHtml, isNot(contains('src="./?embed=1')));
        expect(liveSlashHtml, contains("rootPrefix + '__api/previews'"));
        expect(liveSlashHtml, contains("rootPrefix + '__api/sync'"));

        final shelf.Response status = await server.handler(
          shelf.Request('GET', Uri.parse('http://localhost:8080/__api/status')),
        );
        expect(status.statusCode, io.HttpStatus.ok);
        final statusJson = jsonDecode(await status.readAsString()) as Map<String, Object?>;
        expect(statusJson['status'], 'ready');
        expect(statusJson['previewService'], dtdServices.widgetPreviewService);
        expect(statusJson['scaffoldService'], dtdServices.widgetPreviewScaffoldService);
        expect(statusJson['scaffoldStream'], dtdServices.widgetPreviewScaffoldStream);

        final shelf.Response previews = await server.handler(
          shelf.Request('GET', Uri.parse('http://localhost:8080/__api/previews')),
        );
        expect(previews.statusCode, io.HttpStatus.ok);
        final previewsJson = jsonDecode(await previews.readAsString()) as Map<String, Object?>;
        expect(previewsJson['previews'], isA<List<Object?>>());
        expect(dtdServices.lastListSyncArg, isFalse);

        final shelf.Response sync = await server.handler(
          shelf.Request('POST', Uri.parse('http://localhost:8080/__api/sync')),
        );
        expect(sync.statusCode, io.HttpStatus.ok);
        final syncJson = jsonDecode(await sync.readAsString()) as Map<String, Object?>;
        expect(syncJson['compileSuccess'], isTrue);

        // GET /__api/selection starts empty.
        final shelf.Response initialSelection = await server.handler(
          shelf.Request('GET', Uri.parse('http://localhost:8080/__api/selection')),
        );
        expect(initialSelection.statusCode, io.HttpStatus.ok);
        expect(jsonDecode(await initialSelection.readAsString()), <String, Object?>{
          'type': 'WidgetPreviewSelection',
          'selections': <Object?>[],
          'count': 0,
          'updatedAt': null,
        });

        // POST /__api/selection stores selection entries and returns Success with count/updatedAt.
        final sampleSelection = <String, Object?>{
          'id': 'sel-1',
          'index': 1,
          'kind': 'region',
          'previewId': 'package:my_app/main.dart::myPreview',
          'x': 24,
          'y': 16,
          'width': 180,
          'height': 64,
          'previewWidth': 400,
          'previewHeight': 300,
          'brightness': 'light',
          'textScale': 1.0,
          'zoom': 1.0,
          'widgets': <Map<String, Object?>>[
            <String, Object?>{
              'widget': 'ElevatedButton',
              'text': 'Submit',
              'x': 32,
              'y': 24,
              'width': 120,
              'height': 40,
            },
          ],
        };
        final shelf.Response postSelection = await server.handler(
          shelf.Request(
            'POST',
            Uri.parse('http://localhost:8080/__api/selection'),
            body: jsonEncode(<String, Object?>{
              'selections': <Map<String, Object?>>[sampleSelection],
            }),
          ),
        );
        expect(postSelection.statusCode, io.HttpStatus.ok);
        final postJson = jsonDecode(await postSelection.readAsString()) as Map<String, Object?>;
        expect(postJson['type'], 'Success');
        expect(postJson['count'], 1);
        expect(postJson['updatedAt'], isA<String>());
        expect(dtdServices.fakeDtd.postedEvents, hasLength(1));
        expect(
          dtdServices.fakeDtd.postedEvents.single.streamId,
          dtdServices.widgetPreviewScaffoldStream,
        );
        expect(
          dtdServices.fakeDtd.postedEvents.single.eventKind,
          WidgetPreviewDtdServices.kSelectionUpdatedEvent,
        );
        expect(dtdServices.fakeDtd.postedEvents.single.eventData, <String, Object?>{
          'selections': <Object?>[sampleSelection],
          'count': 1,
          'updatedAt': postJson['updatedAt'],
        });

        final shelf.Response updatedSelection = await server.handler(
          shelf.Request('GET', Uri.parse('http://localhost:8080/__api/selection')),
        );
        expect(updatedSelection.statusCode, io.HttpStatus.ok);
        final updatedJson =
            jsonDecode(await updatedSelection.readAsString()) as Map<String, Object?>;
        expect(updatedJson['type'], 'WidgetPreviewSelection');
        expect(updatedJson['count'], 1);
        expect(updatedJson['updatedAt'], postJson['updatedAt']);
        expect(updatedJson['selections'], <Object?>[sampleSelection]);

        // Malformed body, oversized body, schema violations, and non-list selections return 400 Bad Request, and cross-origin is 403.
        final shelf.Response badJson = await server.handler(
          shelf.Request('POST', Uri.parse('http://localhost:8080/__api/selection'), body: '{bad'),
        );
        expect(badJson.statusCode, io.HttpStatus.badRequest);
        final shelf.Response badParams = await server.handler(
          shelf.Request(
            'POST',
            Uri.parse('http://localhost:8080/__api/selection'),
            body: jsonEncode(<String, Object?>{'selections': 'invalid'}),
          ),
        );
        expect(badParams.statusCode, io.HttpStatus.badRequest);

        // Oversized body with Content-Length > 64 KiB returns 400.
        final oversizedBody =
            '{"selections":[{"kind":"point","x":1,"y":2,"previewId":"'
            '${'a' * PreviewSelectionStore.kMaxSelectionBodyBytes}"}]}';
        final shelf.Response oversizedContentLength = await server.handler(
          shelf.Request(
            'POST',
            Uri.parse('http://localhost:8080/__api/selection'),
            body: oversizedBody,
          ),
        );
        expect(oversizedContentLength.statusCode, io.HttpStatus.badRequest);

        // Chunked stream without Content-Length stops reading as soon as 64 KiB is exceeded.
        var trailingChunkRead = false;
        Stream<List<int>> buildOversizedChunkStream() async* {
          yield List<int>.filled((PreviewSelectionStore.kMaxSelectionBodyBytes ~/ 2) + 1, 0x20);
          yield List<int>.filled((PreviewSelectionStore.kMaxSelectionBodyBytes ~/ 2) + 1, 0x20);
          trailingChunkRead = true;
          yield const <int>[0x20];
        }

        final shelf.Response oversizedChunked = await server.handler(
          shelf.Request(
            'POST',
            Uri.parse('http://localhost:8080/__api/selection'),
            body: buildOversizedChunkStream(),
          ),
        );
        expect(oversizedChunked.statusCode, io.HttpStatus.badRequest);
        expect(trailingChunkRead, isFalse);

        // Unknown nested keys, > 32 entries, and > 12 widgets return 400.
        final shelf.Response unknownKeyResp = await server.handler(
          shelf.Request(
            'POST',
            Uri.parse('http://localhost:8080/__api/selection'),
            body: jsonEncode(<String, Object?>{
              'selections': <Map<String, Object?>>[
                <String, Object?>{
                  'kind': 'point',
                  'x': 1,
                  'y': 2,
                  'extra': <String, Object?>{'nested': true},
                },
              ],
            }),
          ),
        );
        expect(unknownKeyResp.statusCode, io.HttpStatus.badRequest);

        final shelf.Response tooManyEntriesResp = await server.handler(
          shelf.Request(
            'POST',
            Uri.parse('http://localhost:8080/__api/selection'),
            body: jsonEncode(<String, Object?>{
              'selections': <Map<String, Object?>>[
                for (var i = 0; i < PreviewSelectionStore.kMaxSelections + 1; i++)
                  <String, Object?>{'kind': 'point', 'x': i, 'y': i},
              ],
            }),
          ),
        );
        expect(tooManyEntriesResp.statusCode, io.HttpStatus.badRequest);

        final shelf.Response tooManyWidgetsResp = await server.handler(
          shelf.Request(
            'POST',
            Uri.parse('http://localhost:8080/__api/selection'),
            body: jsonEncode(<String, Object?>{
              'selections': <Map<String, Object?>>[
                <String, Object?>{
                  'kind': 'point',
                  'x': 1,
                  'y': 2,
                  'widgets': <Map<String, Object?>>[
                    for (var i = 0; i < PreviewSelectionStore.kMaxWidgetsPerSelection + 1; i++)
                      <String, Object?>{
                        'widget': 'Text',
                        'x': 0,
                        'y': 0,
                        'width': 10,
                        'height': 10,
                      },
                  ],
                },
              ],
            }),
          ),
        );
        expect(tooManyWidgetsResp.statusCode, io.HttpStatus.badRequest);

        final shelf.Response crossOriginSelection = await server.handler(
          shelf.Request(
            'POST',
            Uri.parse('http://localhost:8080/__api/selection'),
            headers: <String, String>{'host': 'localhost:8080', 'origin': 'https://evil.example'},
            body: jsonEncode(<String, Object?>{'selections': <Object?>[]}),
          ),
        );
        expect(crossOriginSelection.statusCode, io.HttpStatus.forbidden);
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

        final wsServer = WidgetPreviewLiveServer(
          basePathProvider: () => '',
          config: WidgetPreviewLiveConfig(
            dtdServices: dtdServices,
            dtdWebSocketConnector: (_) => _FakeWebSocketChannel(upstreamController.local),
          ),
          configuredHost: 'localhost',
          isWindows: false,
          modules: modules,
          renderFlutterBootstrapJs: () => '',
          renderIndexHtml: () => '',
          webMemoryFS: webMemoryFS,
        );
        final io.HttpServer httpServer = await shelf_io.serve(
          wsServer.handler,
          io.InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() async {
          await upstreamController.local.sink.close();
          await upstreamController.foreign.sink.close();
          await wsServer.dispose();
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

        // Allowed: streamListen on widgetPreviewScaffoldStream.
        final Map<String, Object?> listenResp = await sendRpc(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'streamListen',
          'params': <String, Object?>{'streamId': dtdServices.widgetPreviewScaffoldStream},
        });
        expect(listenResp['result'], <String, Object?>{'ok': true});

        // Allowed: listPreviews (forces sync: false even when client passes sync: true).
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

        // Allowed: getPreviews.
        final Map<String, Object?> getPreviewsResp = await sendRpc(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 4,
          'method': '${dtdServices.widgetPreviewScaffoldService}.getPreviews',
        });
        expect(getPreviewsResp['result'], <String, Object?>{'ok': true});

        // Allowed: getSelection and setSelection on widgetPreviewService.
        final Map<String, Object?> getSelectionResp = await sendRpc(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 41,
          'method': '${dtdServices.widgetPreviewService}.getSelection',
          'params': <String, Object?>{'ignored': true},
        });
        expect(getSelectionResp['result'], <String, Object?>{'ok': true});
        expect(forwardedToUpstream.last['params'], isEmpty);

        final Map<String, Object?> setSelectionResp = await sendRpc(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 42,
          'method': '${dtdServices.widgetPreviewService}.setSelection',
          'params': <String, Object?>{
            'selections': <Map<String, Object?>>[
              <String, Object?>{'id': 'sel-1', 'index': 1, 'kind': 'point', 'x': 10, 'y': 20},
            ],
            'unexpected': true,
          },
        });
        expect(setSelectionResp['result'], <String, Object?>{'ok': true});
        expect(forwardedToUpstream.last['params'], <String, Object?>{
          'selections': <Map<String, Object?>>[
            <String, Object?>{'id': 'sel-1', 'index': 1, 'kind': 'point', 'x': 10, 'y': 20},
          ],
        });

        final Map<String, Object?> badSetSelectionResp = await sendRpc(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 43,
          'method': '${dtdServices.widgetPreviewService}.setSelection',
          'params': <String, Object?>{'selections': 'not-a-list'},
        });
        expect((badSetSelectionResp['error']! as Map<String, Object?>)['code'], -32602);

        final Map<String, Object?> unknownKeyWsResp = await sendRpc(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 44,
          'method': '${dtdServices.widgetPreviewService}.setSelection',
          'params': <String, Object?>{
            'selections': <Map<String, Object?>>[
              <String, Object?>{'kind': 'point', 'x': 1, 'y': 2, 'unknown': true},
            ],
          },
        });
        expect((unknownKeyWsResp['error']! as Map<String, Object?>)['code'], -32602);

        final Map<String, Object?> oversizedFrameResp = await sendRpc(
          '{"jsonrpc":"2.0","id":45,"method":"${dtdServices.widgetPreviewService}.setSelection",'
          '"params":{"selections":[{"kind":"point","x":1,"y":2,"previewId":"'
          '${'x' * PreviewSelectionStore.kMaxSelectionBodyBytes}"}]}}',
        );
        expect((oversizedFrameResp['error']! as Map<String, Object?>)['code'], -32600);

        // Allowed: getServiceInfo (answered locally with redacted fields, never
        // forwarded upstream and never exposing dtdUri or projectRoot).
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
        expect(forwardedToUpstream, hasLength(5));

        // Disallowed methods must be rejected with -32601 without forwarding.
        for (final (int id, String method) in <(int, String)>[
          (5, 'FileSystem.readFileAsString'),
          (6, 'registerService'),
          (7, 'postEvent'),
          (8, '${dtdServices.widgetPreviewScaffoldService}.capturePreview'),
          (9, '${dtdServices.widgetPreviewService}.syncPreviews'),
        ]) {
          final Map<String, Object?> err = await sendRpc(<String, Object?>{
            'jsonrpc': '2.0',
            'id': id,
            'method': method,
          });
          expect((err['error']! as Map<String, Object?>)['code'], -32601);
        }

        // Disallowed streamId must be rejected with -32601 without forwarding.
        final Map<String, Object?> badStream = await sendRpc(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 10,
          'method': 'streamListen',
          'params': <String, Object?>{'streamId': 'Editor'},
        });
        expect((badStream['error']! as Map<String, Object?>)['code'], -32601);

        // Malformed JSON, batch array, non-Map params, and notification without id
        // rejected without forwarding.
        final Map<String, Object?> parseErr = await sendRpc('{not-json');
        expect((parseErr['error']! as Map<String, Object?>)['code'], -32700);
        final Map<String, Object?> batchErr = await sendRpc('[1, 2]');
        expect((batchErr['error']! as Map<String, Object?>)['code'], -32600);
        final Map<String, Object?> paramsErr = await sendRpc(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 11,
          'method': 'streamListen',
          'params': <int>[1],
        });
        expect((paramsErr['error']! as Map<String, Object?>)['code'], -32602);
        final Map<String, Object?> notificationErr = await sendRpc(<String, Object?>{
          'jsonrpc': '2.0',
          'method': 'streamListen',
          'params': <String, Object?>{'streamId': dtdServices.widgetPreviewScaffoldStream},
        });
        expect((notificationErr['error']! as Map<String, Object?>)['code'], -32600);

        expect(forwardedToUpstream, hasLength(5));
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
          final wsServer = WidgetPreviewLiveServer(
            basePathProvider: () => '',
            config: WidgetPreviewLiveConfig(
              dtdServices: dtdServices,
              dtdWebSocketConnector: (_) => _FakeWebSocketChannel(upstreamController.local),
            ),
            configuredHost: 'localhost',
            isWindows: false,
            modules: modules,
            renderFlutterBootstrapJs: () => '',
            renderIndexHtml: () => '',
            webMemoryFS: webMemoryFS,
          );
          final io.HttpServer httpServer = await shelf_io.serve(
            wsServer.handler,
            io.InternetAddress.loopbackIPv4,
            0,
          );
          addTearDown(() async {
            await upstreamController.local.sink.close();
            await upstreamController.foreign.sink.close();
            await wsServer.dispose();
            await httpServer.close(force: true);
          });
          final client = IOWebSocketChannel.connect(
            Uri.parse('ws://127.0.0.1:${httpServer.port}/dtd_ws'),
          );
          await client.ready;
          return (client: client, upstreamController: upstreamController, wsServer: wsServer);
        }

        // Upstream DTD closing tears down the viewer client channel.
        final (
          :IOWebSocketChannel client,
          :StreamChannelController<Object?> upstreamController,
          wsServer: _,
        ) = await connectBridge();
        await upstreamController.foreign.sink.close();
        await expectLater(client.stream, emitsDone);

        // liveServer.dispose() closes active /dtd_ws client channels.
        final (
          client: IOWebSocketChannel client2,
          upstreamController: _,
          :WidgetPreviewLiveServer wsServer,
        ) = await connectBridge();
        await wsServer.dispose();
        await expectLater(client2.stream, emitsDone);
      },
    );
  });

  group('$WebAssetServer live wiring', () {
    late MemoryFileSystem fs;
    late BufferLogger logger;
    late _FakeWidgetPreviewDtdServices dtdServices;

    setUp(() {
      fs = MemoryFileSystem.test();
      fs.file('HostArtifact.flutterJsDirectory/flutter.js')
        ..createSync(recursive: true)
        ..writeAsStringSync('// flutter.js');
      logger = BufferLogger.test();
      final Directory projectDir = fs.directory('/tmp/my_app')..createSync(recursive: true);
      projectDir.childFile('pubspec.yaml').writeAsStringSync('name: my_app\n');
      final FlutterProject project = FlutterProject.fromDirectoryTest(projectDir);
      dtdServices = _FakeWidgetPreviewDtdServices(
        fs: fs,
        logger: logger,
        project: project,
        projectRootPath: projectDir.path,
      );
    });

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

        // Normal root goes through DWDS middleware (marker injected).
        final ({String body, Map<String, String> headers, int statusCode}) normalRoot =
            await httpGet(client, server.selectedPort, '/subapp/');
        expect(normalRoot.statusCode, io.HttpStatus.ok);
        expect(normalRoot.body, contains('/* DWDS_INJECTED */'));

        // Embed root and embed bootstrap bypass DWDS middleware (no marker).
        final ({String body, Map<String, String> headers, int statusCode}) embedRoot =
            await httpGet(client, server.selectedPort, '/subapp/?embed=1');
        expect(embedRoot.statusCode, io.HttpStatus.ok);
        expect(embedRoot.body, isNot(contains('/* DWDS_INJECTED */')));

        final ({String body, Map<String, String> headers, int statusCode}) embedModule =
            await httpGet(client, server.selectedPort, '/subapp/__embed_main_module.bootstrap.js');
        expect(embedModule.statusCode, io.HttpStatus.ok);
        expect(embedModule.body, isNot(contains('/* DWDS_INJECTED */')));

        // /live, /live/, and /__api/status work under non-empty basePath.
        final ({String body, Map<String, String> headers, int statusCode}) live = await httpGet(
          client,
          server.selectedPort,
          '/subapp/live',
        );
        expect(live.statusCode, io.HttpStatus.ok);
        final ({String body, Map<String, String> headers, int statusCode}) liveSlash =
            await httpGet(client, server.selectedPort, '/subapp/live/');
        expect(liveSlash.statusCode, io.HttpStatus.ok);
        expect(liveSlash.body, isNot(contains('src="./?embed=1')));
        expect(liveSlash.body, contains("window.location.pathname.endsWith('/') ? '../' : './'"));
        final ({String body, Map<String, String> headers, int statusCode}) status = await httpGet(
          client,
          server.selectedPort,
          '/subapp/__api/status',
        );
        expect(status.statusCode, io.HttpStatus.ok);

        // writeBytes bumps WebMemoryFS.revision so /__ddc_bundle.js ETag changes.
        final ({String body, Map<String, String> headers, int statusCode}) bundle1 = await httpGet(
          client,
          server.selectedPort,
          '/subapp/__ddc_bundle.js',
        );
        expect(bundle1.statusCode, io.HttpStatus.ok);
        final String? etag1 = bundle1.headers['etag'];
        expect(etag1, isNotNull);

        server.writeBytes(
          'packages/my_app/main.dart.lib.js',
          Uint8List.fromList(utf8.encode('console.log("v2");')),
        );
        final ({String body, Map<String, String> headers, int statusCode}) bundle2 = await httpGet(
          client,
          server.selectedPort,
          '/subapp/__ddc_bundle.js',
        );
        expect(bundle2.statusCode, io.HttpStatus.ok);
        expect(bundle2.headers['etag'], isNot(etag1));
        expect(bundle2.body, contains('console.log("v2");'));
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

class _FakeRecordingDtd extends Fake implements DartToolingDaemon {
  final postedEvents = <({String streamId, String eventKind, Map<String, Object?> eventData})>[];

  @override
  Future<void> postEvent(String streamId, String eventKind, Map<String, Object?> eventData) async {
    postedEvents.add((streamId: streamId, eventKind: eventKind, eventData: eventData));
  }

  @override
  Future<void> close() async {}
}

class _FakeWidgetPreviewDtdServices extends WidgetPreviewDtdServices {
  _FakeWidgetPreviewDtdServices({
    required FileSystem fs,
    required Logger logger,
    required FlutterProject project,
    String? projectRootPath,
  }) : this._(
         fakeDtd: _FakeRecordingDtd(),
         fs: fs,
         logger: logger,
         project: project,
         projectRootPath: projectRootPath,
       );

  _FakeWidgetPreviewDtdServices._({
    required this.fakeDtd,
    required super.fs,
    required super.logger,
    required super.project,
    super.projectRootPath,
  }) : super(
         addUuidToServiceName: false,
         dtd: fakeDtd,
         dtdLauncher: _FakeDtdLauncher(),
         onHotRestartPreviewerRequest: () {},
         previewAnalytics: WidgetPreviewAnalytics(analytics: const NoOpAnalytics()),
         shutdownHooks: ShutdownHooks(),
         onSyncPreviews: ({required Duration timeout}) async => const SyncPreviewsResponse(
           compileSuccess: true,
           errorPreviewCount: 0,
           fullRestart: false,
           reloaded: true,
         ),
       );

  final _FakeRecordingDtd fakeDtd;
  bool? lastListSyncArg;

  @override
  Uri? get dtdUri => Uri.parse('ws://127.0.0.1:12345/dtd');

  @override
  Future<Map<String, Object?>> listPreviewsJson({
    String? fileUri,
    bool sync = false,
    int timeoutMs = WidgetPreviewDtdServices.kDefaultSyncTimeoutMs,
  }) async {
    lastListSyncArg = sync;
    return const PreviewListResponse(
      previews: <PreviewEntry>[
        PreviewEntry(
          column: 1,
          functionName: 'myPreview',
          group: 'Default',
          hasError: false,
          id: 'package:my_app/main.dart::myPreview',
          libraryUri: 'package:my_app/main.dart',
          line: 10,
          name: 'myPreview',
          packageName: 'my_app',
          scriptUri: 'file:///tmp/my_app/lib/main.dart',
        ),
      ],
    ).toJson();
  }
}

class _FakeDtdLauncher extends Fake implements DtdLauncher {
  @override
  Future<void> dispose() async {}
}

// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:file/file.dart';
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/os.dart';
import 'package:flutter_tools/src/commands/widget_preview.dart';
import 'package:flutter_tools/src/web/chrome.dart';
import 'package:flutter_tools/src/widget_preview/dtd_services.dart';
import 'package:http/http.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart' hide StackTrace;

import '../src/common.dart';
import 'test_data/basic_project.dart';
import 'test_utils.dart';

typedef ExpectedEvent = ({String event, FutureOr<bool> Function(Map<String, Object?>)? validator});

final launchEvents = <ExpectedEvent>[
  (
    event: 'widget_preview.initializing',
    validator: (Map<String, Object?> params) {
      return params.containsKey('pid');
    },
  ),
  (
    event: 'widget_preview.started',
    validator: (Map<String, Object?> params) async {
      if (params case {'url': final String uri}) {
        try {
          final Response response = await get(Uri.parse(uri));
          return response.statusCode == HttpStatus.ok;
          // ignore: avoid_catches_without_on_clauses
        } catch (e) {
          printOnFailure('Failed to access widget previewer: $e');
        }
      }
      return false;
    },
  ),
];

void main() {
  late Directory tempDir;
  Process? process;
  DtdLauncher? dtdLauncher;
  final project = BasicProject();

  setUp(() async {
    tempDir = createResolvedTempDirectorySync('widget_preview_test.');
    await project.setUpIn(tempDir);
  });

  tearDown(() async {
    process?.kill();
    process = null;
    await dtdLauncher?.dispose();
    dtdLauncher = null;
    tryToDelete(tempDir);
  });

  Future<void> runWidgetPreviewMachineMode({
    required List<ExpectedEvent> expectedEvents,
    bool useWebServer = false,
  }) async {
    expect(expectedEvents, isNotEmpty);
    process = await processManager.start(<String>[
      flutterBin,
      'widget-preview',
      'start',
      '--machine',
      '--${WidgetPreviewStartCommand.kHeadless}',
      if (useWebServer) '--${WidgetPreviewStartCommand.kWebServer}',
    ], workingDirectory: tempDir.path);

    final completer = Completer<void>();
    var nextExpectationIndex = 0;
    process!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((
      String message,
    ) async {
      printOnFailure('STDOUT: $message');
      if (completer.isCompleted) {
        return;
      }
      try {
        final Object? event = json.decode(message);
        if (event case [final Map<String, Object?> eventObject]) {
          final ExpectedEvent expectation = expectedEvents[nextExpectationIndex];
          if (expectation.event == eventObject['event']) {
            expect(
              await expectation.validator?.call(eventObject['params']! as Map<String, Object?>),
              true,
              reason: 'Validator[$nextExpectationIndex] failed.',
            );
            ++nextExpectationIndex;
          }
        }
        if (nextExpectationIndex == expectedEvents.length) {
          completer.complete();
        }
      } on FormatException {
        // Do nothing.
      }
    });

    process!.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((String msg) {
      printOnFailure('STDERR: $msg');
    });

    unawaited(
      process!.exitCode.then((int exitCode) {
        if (completer.isCompleted) {
          return;
        }
        completer.completeError(
          TestFailure('The widget previewer exited unexpectedly (exit code: $exitCode)'),
        );
      }),
    );
    await completer.future;
  }

  group('flutter widget-preview start --machine', () {
    testWithoutContext('launches in browser', () async {
      await runWidgetPreviewMachineMode(expectedEvents: launchEvents);
    });

    testWithoutContext('launches web server', () async {
      await runWidgetPreviewMachineMode(expectedEvents: launchEvents, useWebServer: true);
    });
  });

  group('flutter widget-preview list and snapshot --machine', () {
    testWithoutContext('lists and captures snapshot end-to-end with headless Chrome', () async {
      tempDir.childDirectory('lib').childFile('preview.dart').writeAsStringSync('''
import 'package:flutter/widgets.dart';
import 'package:flutter/widget_previews.dart';

@Preview(name: 'MachineTestPreview')
Widget machineTestPreview() => const Text('Hello');
''');

      final ProcessResult listResult = await processManager.run(<String>[
        flutterBin,
        'widget-preview',
        'list',
        '--machine',
      ], workingDirectory: tempDir.path);
      expect(listResult.exitCode, 0, reason: 'STDERR: ${listResult.stderr}');
      final Object? listDecoded = jsonDecode(listResult.stdout as String);
      expect(
        listDecoded,
        isA<Map<String, Object?>>().having(
          (Map<String, Object?> m) => m['previews'],
          'previews',
          contains(
            isA<Map<String, Object?>>().having(
              (Map<String, Object?> p) => p['name'],
              'name',
              'MachineTestPreview',
            ),
          ),
        ),
      );

      final ProcessResult snapshotResult = await processManager.run(<String>[
        flutterBin,
        'widget-preview',
        'snapshot',
        '--machine',
        'MachineTestPreview',
      ], workingDirectory: tempDir.path);
      expect(snapshotResult.exitCode, 0, reason: 'STDERR: ${snapshotResult.stderr}');
      final Object? snapshotDecoded = jsonDecode(snapshotResult.stdout as String);
      expect(
        snapshotDecoded,
        isA<Map<String, Object?>>()
            .having((Map<String, Object?> m) => m['hasErrors'], 'hasErrors', isFalse)
            .having((Map<String, Object?> m) => m['imageBase64'], 'imageBase64', isNotEmpty),
      );
    });

    testWithoutContext(
      '/live loads versioned DDC modules without DWDS and hot-reloads in-place in Chrome',
      () async {
        final File previewFile = tempDir.childDirectory('lib').childFile('preview.dart');
        previewFile.writeAsStringSync('''
import 'package:flutter/widgets.dart';
import 'package:flutter/widget_previews.dart';

@Preview(name: 'LiveReloadPreview')
Widget liveReloadPreview() => const Text('BeforeLiveReload');
''');

        Uri? startedUri;
        await runWidgetPreviewMachineMode(
          expectedEvents: <ExpectedEvent>[
            launchEvents.first,
            (
              event: 'widget_preview.started',
              validator: (Map<String, Object?> params) async {
                if (params case {'url': final String rawUrl}) {
                  startedUri = Uri.parse(rawUrl);
                  return true;
                }
                return false;
              },
            ),
          ],
        );
        final Uri baseUri = startedUri!;

        Future<bool> pollUntil(
          Future<bool> Function() predicate, {
          Duration timeout = const Duration(seconds: 60),
          Duration interval = const Duration(milliseconds: 250),
        }) async {
          final DateTime deadline = DateTime.now().add(timeout);
          while (DateTime.now().isBefore(deadline)) {
            if (await predicate()) {
              return true;
            }
            await Future<void>.delayed(interval);
          }
          return false;
        }

        // Wait until the headless scaffold finishes connecting to DTD.
        final bool scaffoldReady = await pollUntil(() async {
          final Response statusRes = await get(baseUri.resolve('__api/status'));
          if (statusRes.statusCode == HttpStatus.ok) {
            if (jsonDecode(statusRes.body) case {'scaffoldConnected': true}) {
              return true;
            }
          }
          return false;
        });
        expect(scaffoldReady, isTrue, reason: 'Primary headless scaffold never connected.');

        // Verify /live CSP and versioned individual DDC module bootstrap.
        final Response liveHtml = await get(baseUri.resolve('live'));
        expect(liveHtml.statusCode, HttpStatus.ok);
        expect(liveHtml.headers['content-security-policy'], "frame-ancestors 'self'");
        expect(
          liveHtml.body,
          anyOf(contains('__embed_flutter_bootstrap.js'), contains('__embed_main.dart.js')),
        );

        final Response moduleBootstrap = await get(
          baseUri.resolve('__embed_main_module.bootstrap.js'),
        );
        expect(moduleBootstrap.statusCode, HttpStatus.ok);
        expect(moduleBootstrap.body, contains('self.__wpLiveRevision='));
        expect(moduleBootstrap.body, contains('.lib.js?rev='));
        expect(moduleBootstrap.body, isNot(contains('__ddc_bundle.js')));

        // Launch a second headless Chrome tab on /live using ChromiumLauncher
        // to verify real DDC module loading and in-place hot reload end-to-end.
        final chromeLogger = BufferLogger.test();
        final chromeLauncher = ChromiumLauncher(
          browserFinder: findChromeExecutable,
          fileSystem: fileSystem,
          logger: chromeLogger,
          operatingSystemUtils: OperatingSystemUtils(
            fileSystem: fileSystem,
            logger: chromeLogger,
            platform: platform,
            processManager: processManager,
          ),
          platform: platform,
          processManager: processManager,
        );
        final Chromium chrome = await chromeLauncher.launch(
          baseUri.resolve('live').toString(),
          headless: true,
        );
        WipConnection? wip;
        addTearDown(() async {
          await wip?.close();
          await chrome.close();
        });

        final ChromeTab? tab = await chrome.chromeConnection.getTab(
          (ChromeTab t) => t.url.contains('/live'),
          retryFor: const Duration(seconds: 15),
        );
        expect(tab, isNotNull, reason: 'No /live tab appeared in headless Chrome.');
        wip = await tab!.connect();
        await wip.runtime.enable();
        final consoleErrors = <String>[];
        wip.runtime.onConsoleAPICalled.listen((ConsoleAPIEvent event) {
          final String text = event.args
              .map((RemoteObject a) => '${a.value ?? a.description}')
              .join(' ');
          printOnFailure('CHROME CONSOLE [${event.type}]: $text');
          if (event.type == 'error') {
            consoleErrors.add(text);
          }
        });
        wip.runtime.onExceptionThrown.listen((ExceptionThrownEvent event) {
          final String text = event.exceptionDetails.text;
          final String? desc = event.exceptionDetails.exception?.description;
          printOnFailure('CHROME EXCEPTION: $text ${desc ?? ''}');
          consoleErrors.add('$text ${desc ?? ''}');
        });

        Future<Object?> evalJs(String expression) async {
          final RemoteObject result = await wip!.runtime.evaluate(expression);
          return result.value;
        }

        // Wait for Flutter Web + DDC embedder to finish loading on /live.
        final bool booted = await pollUntil(() async {
          return (await evalJs(
                'typeof window.dartDevEmbedder?.hotReload === "function" && '
                'typeof window.__wpLiveRevision === "number" && '
                'document.querySelector("flutter-view") !== null',
              )) ==
              true;
        });
        if (!booted) {
          final Object? debugState = await evalJs(r'''
JSON.stringify({
  href: window.location.href,
  hasHotReload: typeof window.dartDevEmbedder?.hotReload,
  liveRev: window.__wpLiveRevision,
  hasFlutterView: document.querySelector("flutter-view") !== null,
  numToLoad: window.$dartLoader && window.$dartLoader.loader && window.$dartLoader.loader.numToLoad,
  numLoaded: window.$dartLoader && window.$dartLoader.loader && window.$dartLoader.loader.numLoaded,
  numFailed: window.$dartLoader && window.$dartLoader.loader && window.$dartLoader.loader.numFailed,
  queueLen: window.$dartLoader && window.$dartLoader.loader && window.$dartLoader.loader.queue && window.$dartLoader.loader.queue.length,
  scripts: document.querySelectorAll("script").length
})''');
          fail('/live viewer did not boot in Chrome. state=$debugState errors=$consoleErrors');
        }
        expect(
          await evalJs(
            'performance.getEntriesByType("resource")'
            '.some(e => e.name.includes("dwdsSseHandler"))',
          ),
          isFalse,
          reason: '/live must bypass DWDS.',
        );

        final initialGen = (await evalJs('window.dartDevEmbedder.hotReloadGeneration'))! as int;
        await evalJs('window.__wpInPlaceCheck = "alive"');

        // Edit the preview widget and trigger POST /__api/sync to drive an
        // in-place DDC hot reload in the live viewer tab.
        writeFile(previewFile.path, '''
import 'package:flutter/widgets.dart';
import 'package:flutter/widget_previews.dart';

@Preview(name: 'LiveReloadPreview')
Widget liveReloadPreview() => const Text('AfterLiveReload');
''', writeFutureModifiedDate: true);

        final Response syncRes = await post(baseUri.resolve('__api/sync'));
        expect(syncRes.statusCode, HttpStatus.ok, reason: syncRes.body);
        expect(jsonDecode(syncRes.body), containsPair('compileSuccess', true));

        final bool reloadedInPlace = await pollUntil(() async {
          final Object? gen = await evalJs('window.dartDevEmbedder.hotReloadGeneration');
          return gen is int && gen > initialGen;
        }, timeout: const Duration(seconds: 30));
        expect(
          reloadedInPlace,
          isTrue,
          reason: '/live viewer did not apply in-place DDC hot reload.',
        );
        expect(
          await evalJs('window.__wpInPlaceCheck'),
          'alive',
          reason: '/live performed a full page reload instead of an in-place hot reload.',
        );
      },
    );
  });
}

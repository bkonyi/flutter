// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:dtd/dtd.dart';
import 'package:file/file.dart';
import 'package:file_testing/file_testing.dart';
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/commands/widget_preview.dart';
import 'package:flutter_tools/src/devtools_launcher.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/widget_preview/dtd_services.dart';
import 'package:process/process.dart';

import '../src/common.dart';
import '../src/context.dart';
import '../src/fakes.dart';
import 'test_data/basic_project.dart';
import 'test_utils.dart';
import 'widget_preview_test_helpers.dart';

void main() {
  late Directory tempDir;
  Logger? logger;
  DtdLauncher? dtdLauncher;
  DevtoolsServerLauncher? devtoolsLauncher;
  late BasicProject project;
  var projectCounter = 0;
  const ProcessManager processManager = LocalProcessManager();

  setUp(() async {
    logger = BufferLogger.test();
    tempDir = createResolvedTempDirectorySync('widget_preview_smoke_test.');
    projectCounter++;
    project = BasicProject(name: 'test_smoke_$projectCounter');
    await project.setUpIn(tempDir);
  });

  tearDown(() async {
    await dtdLauncher?.dispose();
    await devtoolsLauncher?.close();
    devtoolsLauncher = null;
    dtdLauncher = null;
    tryToDelete(tempDir);
  });

  group('flutter widget-preview start', () {
    testWithoutContext('smoke test', () async {
      await runWidgetPreview(tempDir: tempDir, expectedMessages: firstLaunchMessagesWeb);
    });

    testWithoutContext('--web-server starts a web server instance', () async {
      await runWidgetPreview(
        tempDir: tempDir,
        expectedMessages: firstLaunchMessagesWebServer,
        useWebServer: true,
      );
    });

    testWithoutContext('runs flutter pub get in widget_preview_scaffold if '
        "widget_preview_scaffold/.dart_tool doesn't exist", () async {
      // Regression test for https://github.com/flutter/flutter/issues/178660
      // Generate the widget preview scaffold, but don't bother launching it.
      processManager.runSync(<String>[
        flutterBin,
        'widget-preview',
        'start',
        '--no-${WidgetPreviewStartCommand.kLaunchPreviewer}',
      ], workingDirectory: tempDir.path);

      // Ensure .widget_preview/.dart_tool/package_config.json exists.
      final Directory widgetPreviewScaffoldDartTool = tempDir
          .childDirectory('.widget_preview')
          .childDirectory('.dart_tool');
      expect(widgetPreviewScaffoldDartTool, exists);
      expect(widgetPreviewScaffoldDartTool.childFile('package_config.json'), exists);

      // Delete .widget_preview/.dart_tool/. This simulates an interrupted
      // flutter widget-preview start where 'flutter pub get' wasn't run after
      // the widget_preview_scaffold project was created.
      widgetPreviewScaffoldDartTool.deleteSync(recursive: true);

      // Ensure we don't crash due to the package_config.json lookup pointing to
      // the parent project's package_config.json due to
      // .widget_preview/.dart_tool/package_config.json not existing.
      await runWidgetPreview(tempDir: tempDir, expectedMessages: subsequentLaunchMessagesWeb);
    });

    testWithoutContext('does not recreate project on subsequent runs', () async {
      // The first run of 'flutter widget-preview start' should generate a new preview scaffold
      await runWidgetPreview(tempDir: tempDir, expectedMessages: firstLaunchMessagesWeb);

      // We shouldn't regenerate the scaffold after the initial run.
      await runWidgetPreview(tempDir: tempDir, expectedMessages: subsequentLaunchMessagesWeb);
    });

    testUsingContext('can connect to an existing DTD instance', () async {
      dtdLauncher = DtdLauncher(
        logger: logger!,
        artifacts: globals.artifacts!,
        processManager: globals.processManager,
      );

      // Start a DTD instance.
      final Uri dtdUri = await dtdLauncher!.launch();

      // Connect to it and listen to the WidgetPreviewScaffold stream.
      //
      // The preview scaffold will send a 'Connected' event on this stream once it has initialized
      // and is ready.
      final DartToolingDaemon dtdConnection = await DartToolingDaemon.connect(dtdUri);
      final completer = Completer<void>();
      dtdConnection.onEvent(WidgetPreviewDtdServices.kWidgetPreviewScaffoldStreamRoot).listen((
        DTDEvent event,
      ) {
        expect(event.stream, WidgetPreviewDtdServices.kWidgetPreviewScaffoldStreamRoot);
        expect(event.kind, 'Connected');
        completer.complete();
      });
      await dtdConnection.streamListen(WidgetPreviewDtdServices.kWidgetPreviewScaffoldStreamRoot);

      // Start the widget preview and wait for the 'Connected' event.
      await runWidgetPreview(
        tempDir: tempDir,
        expectedMessages: firstLaunchMessagesWeb,
        dtdUri: dtdUri,
      );
      await completer.future;
    });

    testUsingContext('can connect to an existing DevTools instance', () async {
      devtoolsLauncher = DevtoolsServerLauncher(
        processManager: processManager,
        logger: logger!,
        botDetector: const FakeBotDetector(true),
        artifacts: globals.artifacts!,
      );

      // Start a DevTools instance.
      final Uri devtoolsUri = (await devtoolsLauncher!.serve())!.uri!;

      // Start the widget preview and wait for the DevTools message.
      await runWidgetPreview(
        tempDir: tempDir,
        expectedMessages: <Pattern>[
          'The Flutter DevTools debugger and profiler on Chrome is available at: $devtoolsUri',
        ],
        devToolsServerAddress: devtoolsUri,
      );
    });

    testUsingContext("doesn't crash on flutter clean", () async {
      // Regression test for https://github.com/flutter/flutter/issues/175058.
      dtdLauncher = DtdLauncher(
        logger: logger!,
        artifacts: globals.artifacts!,
        processManager: globals.processManager,
      );

      // Start a DTD instance.
      final Uri dtdUri = await dtdLauncher!.launch();

      // Connect to it and listen to the WidgetPreviewScaffold stream.
      final DartToolingDaemon dtdConnection = await DartToolingDaemon.connect(dtdUri);
      final completer = Completer<void>();
      var firstConnection = true;
      dtdConnection.onEvent(WidgetPreviewDtdServices.kWidgetPreviewScaffoldStreamRoot).listen((
        DTDEvent event,
      ) {
        expect(event.stream, WidgetPreviewDtdServices.kWidgetPreviewScaffoldStreamRoot);
        expect(event.kind, 'Connected');
        if (firstConnection) {
          firstConnection = false;
          runFlutterClean(tempDir);
          // Restore dependencies so the Analysis Server and Dwds can resolve packages during Hot Restart.
          // Add --offline flag to prevent attempts to reach the network during CI.
          processManager.runSync(<String>[
            flutterBin,
            'pub',
            'get',
            '--offline',
          ], workingDirectory: tempDir.path);
          dtdConnection.call(
            WidgetPreviewDtdServices.kWidgetPreviewServiceRoot,
            WidgetPreviewDtdServices.kHotRestartPreviewer,
          );
          return;
        }
        // The second `Connected` event should come after the previewer is hot restarted successfully.
        completer.complete();
      });
      await dtdConnection.streamListen(WidgetPreviewDtdServices.kWidgetPreviewScaffoldStreamRoot);

      // Start the widget preview and wait for the 'Connected' event.
      final Stream<String> stdoutStream = await runWidgetPreview(
        tempDir: tempDir,
        expectedMessages: firstLaunchMessagesWeb,
        dtdUri: dtdUri,
      );

      final processExitCompleter = Completer<void>();
      final StreamSubscription<String> subscription = stdoutStream.listen(
        null,
        onDone: () => processExitCompleter.complete(),
      );

      // Race the connection completer against process exit for clearer failure messages.
      await Future.any(<Future<void>>[completer.future, processExitCompleter.future]);
      expect(
        processExitCompleter.isCompleted,
        isFalse,
        reason: 'Widget preview process exited unexpectedly after flutter clean.',
      );
      await subscription.cancel();
    });

    testWithoutContext('generated _defaultPreviewLocalizations renders material_ui, cupertino_ui, and legacy material/cupertino widgets', () async {
      tempDir.childFile('pubspec.yaml').writeAsStringSync('''
name: ${project.name}
environment:
  sdk: ^3.12.0

dependencies:
  flutter:
    sdk: flutter
  cupertino_ui: ^1.0.0
  material_ui: ^1.0.0
''');
      tempDir.childDirectory('lib').childFile('localizations_previews.dart').writeAsStringSync('''
import 'package:cupertino_ui/cupertino_ui.dart' as cupertino_ui;
import 'package:flutter/cupertino.dart' as legacy_cupertino;
import 'package:flutter/material.dart' as legacy_material;
import 'package:flutter/widget_previews.dart';
import 'package:material_ui/material_ui.dart' as material_ui;

@Preview(name: 'material_ui')
material_ui.Widget materialUiTextFieldPreview() => const material_ui.Material(
  child: material_ui.SizedBox(width: 220, child: material_ui.TextField()),
);

@Preview(name: 'cupertino_ui')
cupertino_ui.Widget cupertinoUiTextFieldPreview() => const cupertino_ui.SizedBox(
  width: 220,
  child: cupertino_ui.CupertinoTextField(),
);

@Preview(name: 'legacy_material')
// ignore: deprecated_member_use
legacy_material.Widget legacyMaterialTextFieldPreview() => const legacy_material.Material(
  // ignore: deprecated_member_use
  child: legacy_material.SizedBox(width: 220, child: legacy_material.TextField()),
);

@Preview(name: 'legacy_cupertino')
// ignore: deprecated_member_use
legacy_cupertino.Widget legacyCupertinoTextFieldPreview() => const legacy_cupertino.SizedBox(
  width: 220,
  // ignore: deprecated_member_use
  child: legacy_cupertino.CupertinoTextField(),
);
''');

      final ProcessResult pubGetResult = processManager.runSync(<String>[
        flutterBin,
        'pub',
        'get',
        '--offline',
      ], workingDirectory: tempDir.path);
      expect(
        pubGetResult.exitCode,
        0,
        reason: 'stdout:\n${pubGetResult.stdout}\nstderr:\n${pubGetResult.stderr}',
      );

      final ProcessResult startResult = processManager.runSync(<String>[
        flutterBin,
        'widget-preview',
        'start',
        '--no-${WidgetPreviewStartCommand.kLaunchPreviewer}',
      ], workingDirectory: tempDir.path);
      expect(
        startResult.exitCode,
        0,
        reason: 'stdout:\n${startResult.stdout}\nstderr:\n${startResult.stderr}',
      );

      final Directory scaffoldDir = tempDir.childDirectory('.widget_preview');
      final String dartBin = tempDir.fileSystem.path.join(
        tempDir.fileSystem.path.dirname(flutterBin),
        'cache',
        'dart-sdk',
        'bin',
        'dart',
      );
      final ProcessResult analyzeResult = processManager.runSync(<String>[
        dartBin,
        'analyze',
        '--fatal-infos',
      ], workingDirectory: scaffoldDir.path);
      expect(
        analyzeResult.exitCode,
        0,
        reason: 'stdout:\n${analyzeResult.stdout}\nstderr:\n${analyzeResult.stderr}',
      );

      scaffoldDir.childDirectory('test').childFile('generated_localizations_smoke_test.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
import 'package:cupertino_ui/cupertino_ui.dart' as cupertino_ui;
// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart' as legacy_cupertino;
// ignore: deprecated_member_use
import 'package:flutter/material.dart' as legacy_material;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as material_ui;
import 'package:widget_preview_scaffold/src/generated_preview.dart' as generated;
import 'package:widget_preview_scaffold/src/widget_preview.dart';

void main() {
  testWidgets('generated previews render with synthesized localizations', (
    tester,
  ) async {
    final List<WidgetPreview> generatedPreviews = generated.previews();
    expect(generatedPreviews, hasLength(4));

    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
            PageRouteBuilder<T>(
              settings: settings,
              pageBuilder: (
                BuildContext context,
                Animation<double> animation,
                Animation<double> secondaryAnimation,
              ) => builder(context),
            ),
        builder: (BuildContext context, Widget? child) => child!,
        home: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              for (final WidgetPreview preview in generatedPreviews)
                Localizations(
                  locale: preview.localizations!.locale!,
                  delegates: preview.localizations!.localizationsDelegates!.toList(),
                  child: preview.previewBuilder(),
                ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(material_ui.TextField), findsOneWidget);
    expect(find.byType(cupertino_ui.CupertinoTextField), findsOneWidget);
    // ignore: deprecated_member_use
    expect(find.byType(legacy_material.TextField), findsOneWidget);
    // ignore: deprecated_member_use
    expect(find.byType(legacy_cupertino.CupertinoTextField), findsOneWidget);
  });
}
''');

      // PreviewPubspecBuilder.buildPubspec strips flutter_test when hydrating .widget_preview/pubspec.yaml.
      final File scaffoldPubspec = scaffoldDir.childFile('pubspec.yaml');
      scaffoldPubspec.writeAsStringSync('''
${scaffoldPubspec.readAsStringSync()}
dev_dependencies:
  flutter_test:
    sdk: flutter
''');

      final ProcessResult scaffoldPubGetResult = processManager.runSync(<String>[
        flutterBin,
        'pub',
        'get',
        '--offline',
      ], workingDirectory: scaffoldDir.path);
      expect(
        scaffoldPubGetResult.exitCode,
        0,
        reason: 'stdout:\n${scaffoldPubGetResult.stdout}\nstderr:\n${scaffoldPubGetResult.stderr}',
      );

      final ProcessResult testResult = processManager.runSync(<String>[
        flutterBin,
        'test',
        '--no-pub',
        'test/generated_localizations_smoke_test.dart',
      ], workingDirectory: scaffoldDir.path);
      expect(
        testResult.exitCode,
        0,
        reason: 'stdout:\n${testResult.stdout}\nstderr:\n${testResult.stderr}',
      );
    });
  });
}

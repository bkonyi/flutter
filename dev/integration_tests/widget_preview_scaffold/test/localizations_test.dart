// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widget_preview_scaffold/src/utils.dart';
import 'package:widget_preview_scaffold/src/widget_preview.dart';
import 'package:widget_preview_scaffold/src/widget_preview_rendering.dart';

import 'utils/localizations_utils.dart';
import 'utils/widget_preview_scaffold_test_utils.dart';

const _kDefaultLocale = Locale('en', 'US');
const _kSpanishLocale = Locale('es');
const _kPreviewWidth = 220.0;
const _kPreviewHeight = 90.0;
const _kPreviewTextScale = 1.25;

PreviewLocalizationsData _defaultTestLocalizations() =>
    const PreviewLocalizationsData(
      locale: _kDefaultLocale,
      localizationsDelegates: <LocalizationsDelegate<Object?>>[
        DefaultMaterialLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
    );

PreviewLocalizationsData _explicitSpanishLocalizations() => forLocale('es');

final class _FakePreviewThemeData extends PreviewThemeData {
  const _FakePreviewThemeData();

  @override
  Widget apply(BuildContext context, Widget child) => child;
}

PreviewThemeData _fakePreviewTheme() => const _FakePreviewThemeData();

Widget _fakeWrapper(Widget child) =>
    ColoredBox(color: Colors.red, child: child);

final class _CustomBrightnessPreview extends Preview {
  const _CustomBrightnessPreview({super.name})
    : super(brightness: Brightness.dark);
}

final class _MixedLocalizationsMultiPreview extends MultiPreview {
  const _MixedLocalizationsMultiPreview();

  @override
  List<Preview> get previews => const <Preview>[
    Preview(name: 'Fallback Variant', brightness: Brightness.light),
    Preview(
      name: 'Explicit Variant',
      brightness: Brightness.dark,
      localizations: _explicitSpanishLocalizations,
    ),
  ];
}

void expectLocalization<T extends AppLocalizations?>({
  required BuildContext context,
  required PreviewLocalizationsData? expected,
}) {
  final AppLocalizations? actual = AppLocalizations.of(context);
  expect(actual, isA<T>());
  if (expected == null) {
    expect(actual, isNull);
  }
  expect(actual!.localeName, expected!.locale?.languageCode);
  expect(
    AppLocalizations.localizationsDelegates,
    expected.localizationsDelegates,
  );
}

WidgetPreviewerWidgetScaffolding previewForLocalizations({
  required Key key,
  PreviewLocalizations? previewLocalizationsData,
}) {
  final controller = FakeWidgetPreviewScaffoldController();
  return WidgetPreviewerWidgetScaffolding(
    child: WidgetPreviewWidget(
      controller: controller,
      preview: WidgetPreview.test(
        builder: () => Text('Foo', key: key),
        previewData: Preview(localizations: previewLocalizationsData),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'Localization data is correctly propagated down to the previewed widget',
    (WidgetTester tester) async {
      final key = GlobalKey();
      PreviewLocalizationsData data = forLocale('en');
      await tester.pumpWidget(
        previewForLocalizations(key: key, previewLocalizationsData: () => data),
      );
      expectLocalization<AppLocalizationsEn>(
        context: key.currentContext!,
        expected: data,
      );

      data = forLocale('es');
      await tester.pumpWidget(
        previewForLocalizations(key: key, previewLocalizationsData: () => data),
      );
      expectLocalization<AppLocalizationsEs>(
        context: key.currentContext!,
        expected: data,
      );
    },
  );

  test(
    'buildWidgetPreview and buildMultiWidgetPreview apply defaultLocalizations '
    'only when preview.localizations is null while preserving all other fields',
    () {
      final WidgetPreview fallbackPreview = makeTestPreview(
        brightness: Brightness.dark,
        column: 2,
        defaultLocalizations: _defaultTestLocalizations,
        functionName: 'myPreview',
        group: 'CustomGroup',
        name: 'MyName',
        packageName: 'foo',
        previewFunction: () => const Text('Hello'),
        size: const Size(_kPreviewWidth, _kPreviewHeight),
        textScaleFactor: _kPreviewTextScale,
        theme: _fakePreviewTheme,
        wrapper: _fakeWrapper,
      );

      expect(fallbackPreview.localizations?.locale, _kDefaultLocale);
      expect(
        fallbackPreview.localizations?.localizationsDelegates,
        containsAll(<LocalizationsDelegate<Object?>>[
          DefaultMaterialLocalizations.delegate,
          DefaultCupertinoLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ]),
      );
      expect(fallbackPreview.previewData.group, 'CustomGroup');
      expect(fallbackPreview.name, 'MyName');
      expect(fallbackPreview.size, const Size(_kPreviewWidth, _kPreviewHeight));
      expect(fallbackPreview.textScaleFactor, _kPreviewTextScale);
      expect(fallbackPreview.brightness, Brightness.dark);
      expect(fallbackPreview.theme, isA<_FakePreviewThemeData>());
      expect(fallbackPreview.previewBuilder(), isA<ColoredBox>());

      final WidgetPreview explicitPreview = makeTestPreview(
        defaultLocalizations: _defaultTestLocalizations,
        functionName: 'spanishPreview',
        localizations: _explicitSpanishLocalizations,
        name: 'Spanish',
        packageName: 'foo',
        previewFunction: () => const Text('Hola'),
      );
      expect(explicitPreview.localizations?.locale, _kSpanishLocale);
      expect(
        explicitPreview.previewData.localizations,
        same(_explicitSpanishLocalizations),
      );

      final List<WidgetPreview> multiPreviews = buildMultiWidgetPreview(
        column: 1,
        defaultLocalizations: _defaultTestLocalizations,
        functionName: 'multiPreview',
        libraryUri: 'package:foo/foo.dart',
        line: 30,
        packageName: 'foo',
        preview: const _MixedLocalizationsMultiPreview(),
        previewFunction: () => const Text('Multi'),
        scriptUri: 'file:///foo/lib/foo.dart',
      ).toList();
      expect(multiPreviews, hasLength(2));
      expect(multiPreviews[0].name, 'Fallback Variant');
      expect(multiPreviews[0].brightness, Brightness.light);
      expect(multiPreviews[0].localizations?.locale, _kDefaultLocale);
      expect(multiPreviews[1].name, 'Explicit Variant');
      expect(multiPreviews[1].brightness, Brightness.dark);
      expect(multiPreviews[1].localizations?.locale, _kSpanishLocale);
    },
  );

  testWidgets(
    'bare Material TextField and CupertinoTextField render with defaultLocalizations',
    (WidgetTester tester) async {
      final controller = FakeWidgetPreviewScaffoldController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        WidgetPreviewerWidgetScaffolding(
          child: WidgetPreviewWidget(
            controller: controller,
            preview: makeTestPreview(
              functionName: 'bareTextField',
              packageName: 'foo',
              previewFunction: () => const Material(
                child: SizedBox(width: _kPreviewWidth, child: TextField()),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isA<FlutterError>());

      await tester.pumpWidget(
        WidgetPreviewerWidgetScaffolding(
          child: Column(
            children: <Widget>[
              WidgetPreviewWidget(
                controller: controller,
                preview: makeTestPreview(
                  defaultLocalizations: _defaultTestLocalizations,
                  functionName: 'bareTextField',
                  packageName: 'foo',
                  previewFunction: () => const Material(
                    child: SizedBox(width: _kPreviewWidth, child: TextField()),
                  ),
                ),
              ),
              WidgetPreviewWidget(
                controller: controller,
                preview: makeTestPreview(
                  defaultLocalizations: _defaultTestLocalizations,
                  functionName: 'bareCupertinoTextField',
                  packageName: 'foo',
                  previewFunction: () => const SizedBox(
                    width: _kPreviewWidth,
                    child: CupertinoTextField(),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(CupertinoTextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'typed text');
      await tester.pump();
      expect(find.text('typed text'), findsOneWidget);
    },
  );

  test(
    'buildWidgetPreview preserves custom Preview subclass identity and toStringShort',
    () {
      const customPreview = _CustomBrightnessPreview(name: 'Dark');
      final WidgetPreview widgetPreview = makeTestPreview(
        defaultLocalizations: _defaultTestLocalizations,
        functionName: 'customPreview',
        packageName: 'foo',
        previewFunction: () => const Text('Hello'),
        rawPreview: customPreview,
      );

      expect(widgetPreview.previewData, same(customPreview));
      expect(widgetPreview.localizations?.locale, _kDefaultLocale);
      expect(
        PreviewWidget(
          preview: widgetPreview,
          child: const SizedBox.shrink(),
        ).toStringShort(),
        '@_CustomBrightnessPreview(name: "Dark")',
      );
    },
  );
}

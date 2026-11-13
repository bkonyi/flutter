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
    (tester) async {
      final key = GlobalKey();
      PreviewLocalizationsData previewLocalizationsData = forLocale('en');

      // Check that both en and es localizations are available to the previewed widget.
      WidgetPreviewerWidgetScaffolding widgetPreview = previewForLocalizations(
        key: key,
        previewLocalizationsData: () => previewLocalizationsData,
      );
      await tester.pumpWidget(widgetPreview);

      expectLocalization<AppLocalizationsEn>(
        context: key.currentContext!,
        expected: previewLocalizationsData,
      );

      previewLocalizationsData = forLocale('es');
      widgetPreview = previewForLocalizations(
        key: key,
        previewLocalizationsData: () => previewLocalizationsData,
      );
      await tester.pumpWidget(widgetPreview);

      expectLocalization<AppLocalizationsEs>(
        context: key.currentContext!,
        expected: previewLocalizationsData,
      );
    },
  );

  test(
    'buildWidgetPreview and buildMultiWidgetPreview apply defaultLocalizations '
    'only when preview.localizations is null while preserving all other fields',
    () {
      final WidgetPreview fallbackPreview = buildWidgetPreview(
        column: 2,
        defaultLocalizations: _defaultTestLocalizations,
        functionName: 'myPreview',
        libraryUri: 'package:foo/foo.dart',
        line: 10,
        packageName: 'foo',
        previewFunction: () => const Text('Hello'),
        scriptUri: 'file:///foo/lib/foo.dart',
        transformedPreview: const Preview(
          brightness: Brightness.dark,
          group: 'CustomGroup',
          name: 'MyName',
          size: Size(_kPreviewWidth, _kPreviewHeight),
          textScaleFactor: _kPreviewTextScale,
          theme: _fakePreviewTheme,
          wrapper: _fakeWrapper,
        ).transform(),
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

      final WidgetPreview explicitPreview = buildWidgetPreview(
        column: 2,
        defaultLocalizations: _defaultTestLocalizations,
        functionName: 'spanishPreview',
        libraryUri: 'package:foo/foo.dart',
        line: 20,
        packageName: 'foo',
        previewFunction: () => const Text('Hola'),
        scriptUri: 'file:///foo/lib/foo.dart',
        transformedPreview: const Preview(
          localizations: _explicitSpanishLocalizations,
          name: 'Spanish',
        ).transform(),
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
    (tester) async {
      final controller = FakeWidgetPreviewScaffoldController();

      // Without defaultLocalizations inside a WidgetsApp host, Material TextField
      // fails because MaterialLocalizations is absent.
      final WidgetPreview unlocalizedPreview = buildWidgetPreview(
        column: 1,
        functionName: 'bareTextField',
        libraryUri: 'package:foo/foo.dart',
        line: 1,
        packageName: 'foo',
        previewFunction: () => const Material(
          child: SizedBox(width: _kPreviewWidth, child: TextField()),
        ),
        scriptUri: 'file:///foo/lib/foo.dart',
        transformedPreview: const Preview().transform(),
      );
      await tester.pumpWidget(
        WidgetPreviewerWidgetScaffolding(
          child: WidgetPreviewWidget(
            controller: controller,
            preview: unlocalizedPreview,
          ),
        ),
      );
      expect(tester.takeException(), isA<FlutterError>());

      // With defaultLocalizations synthesized, bare Material TextField and
      // CupertinoTextField both render cleanly with zero exceptions.
      final WidgetPreview localizedMaterialPreview = buildWidgetPreview(
        column: 1,
        defaultLocalizations: _defaultTestLocalizations,
        functionName: 'bareTextField',
        libraryUri: 'package:foo/foo.dart',
        line: 10,
        packageName: 'foo',
        previewFunction: () => const Material(
          child: SizedBox(width: _kPreviewWidth, child: TextField()),
        ),
        scriptUri: 'file:///foo/lib/foo.dart',
        transformedPreview: const Preview().transform(),
      );
      final WidgetPreview localizedCupertinoPreview = buildWidgetPreview(
        column: 1,
        defaultLocalizations: _defaultTestLocalizations,
        functionName: 'bareCupertinoTextField',
        libraryUri: 'package:foo/foo.dart',
        line: 20,
        packageName: 'foo',
        previewFunction: () =>
            const SizedBox(width: _kPreviewWidth, child: CupertinoTextField()),
        scriptUri: 'file:///foo/lib/foo.dart',
        transformedPreview: const Preview().transform(),
      );

      await tester.pumpWidget(
        WidgetPreviewerWidgetScaffolding(
          child: Column(
            children: <Widget>[
              WidgetPreviewWidget(
                controller: controller,
                preview: localizedMaterialPreview,
              ),
              WidgetPreviewWidget(
                controller: controller,
                preview: localizedCupertinoPreview,
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
      expect(tester.takeException(), isNull);
      expect(find.text('typed text'), findsOneWidget);
    },
  );

  test(
    'buildWidgetPreview preserves custom Preview subclass identity and toStringShort',
    () {
      const customPreview = _CustomBrightnessPreview(name: 'Dark');
      final WidgetPreview widgetPreview = buildWidgetPreview(
        column: 1,
        defaultLocalizations: _defaultTestLocalizations,
        functionName: 'customPreview',
        libraryUri: 'package:foo/foo.dart',
        line: 5,
        packageName: 'foo',
        previewFunction: () => const Text('Hello'),
        scriptUri: 'file:///foo/lib/foo.dart',
        transformedPreview: customPreview.transform(),
      );

      expect(widgetPreview.previewData, same(customPreview));
      expect(widgetPreview.previewData, isA<_CustomBrightnessPreview>());
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

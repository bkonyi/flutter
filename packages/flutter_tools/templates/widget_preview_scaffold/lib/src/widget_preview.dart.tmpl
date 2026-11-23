// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:dtd/dtd.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';
import 'package:json_rpc_2/json_rpc_2.dart';

const _kBrightnessKey = 'brightness';
const _kColumnKey = 'column';
const _kErrorMessageKey = 'errorMessage';
const _kFunctionNameKey = 'functionName';
const _kGroupKey = 'group';
const _kHasErrorKey = 'hasError';
const _kHeightKey = 'height';
const _kIdKey = 'id';
const _kLibraryUriKey = 'libraryUri';
const _kLineKey = 'line';
const _kMultiPreviewIndexKey = 'multiPreviewIndex';
const _kNameKey = 'name';
const _kPackageNameKey = 'packageName';
const _kPreviewsKey = 'previews';
const _kScriptUriKey = 'scriptUri';
const _kTextScaleFactorKey = 'textScaleFactor';
const _kTypeKey = 'type';
const _kWidthKey = 'width';

void _expectDtdResponseType(DTDResponse response, String expectedType) {
  if (response.result[_kTypeKey] != expectedType) {
    throw RpcException.invalidParams(
      'Expected $_kTypeKey param to be $expectedType, got: ${response.result[_kTypeKey]}',
    );
  }
}

/// A group of [WidgetPreview] instances sharing the same group name.
class WidgetPreviewGroup {
  const WidgetPreviewGroup({required this.name, required this.previews});

  /// Returns `false` if the group has no previews.
  ///
  /// This can happen if a filter is applied that results in no previews matching
  /// the filter being part of the group.
  bool get hasPreviews => previews.isNotEmpty;

  /// The name of the group, as specified by the 'group' parameter in [Preview].
  final String name;

  /// The set of preview instances which are part of a group with a given [name].
  final List<WidgetPreview> previews;
}

/// Wraps a [Widget], initializing various state and properties to allow for
/// previewing of the [Widget] in the widget previewer.
class WidgetPreview {
  /// Wraps [builder] in a [WidgetPreview] instance that applies some set of
  /// properties.
  const WidgetPreview({
    required this.builder,
    required this.column,
    required this.line,
    required this.packageName,
    required this.previewData,
    required this.scriptUri,
    this.errorMessage,
    this.functionName = '',
    this.hasError = false,
    this.libraryUri = '',
    this.multiPreviewIndex,
  });

  @visibleForTesting
  const WidgetPreview.test({
    required this.builder,
    required this.previewData,
    this.column = -1,
    this.errorMessage,
    this.functionName = '',
    this.hasError = false,
    this.libraryUri = '',
    this.line = -1,
    this.multiPreviewIndex,
    this.packageName = '',
    this.scriptUri = '',
  });

  /// Canonical identifier for this preview instance.
  ///
  /// Uses `'$libraryUri::$functionName'` for single `@Preview` declarations, or
  /// `'$libraryUri::$functionName#$multiPreviewIndex'` for `@MultiPreview`
  /// entries.
  String get id => multiPreviewIndex == null
      ? '$libraryUri::$functionName'
      : '$libraryUri::$functionName#$multiPreviewIndex';

  /// The absolute file:// URI pointing to the script containing this preview.
  ///
  /// This matches the URI format sent by IDEs for active location change events.
  final String scriptUri;

  /// The package: or dart: URI of the library containing this preview.
  final String libraryUri;

  /// The name of the preview function, constructor, or static member.
  final String functionName;

  /// Zero-based index within an expanded [MultiPreview], or `null` for a single
  /// [Preview].
  final int? multiPreviewIndex;

  /// The line at which the Preview annotation was applied.
  final int line;

  /// The column at which the Preview annotation was applied.
  final int column;

  /// The name of the package in which a preview was defined.
  ///
  /// For example, if a preview is defined in 'package:foo/src/bar.dart', this
  /// will have the value 'foo'.
  final String packageName;

  /// Whether this preview failed static analysis or compilation.
  final bool hasError;

  /// Static analysis or compilation error message when [hasError] is `true`.
  final String? errorMessage;

  /// A description to be displayed alongside the preview.
  ///
  /// If not provided, no name will be associated with the preview.
  String? get name => previewData.name;

  /// A callback to build the [Widget] to be rendered in the preview.
  final Widget Function() builder;

  Widget Function() get previewBuilder {
    return switch (previewData) {
      Preview(:final Widget Function(Widget) wrapper) => () => wrapper(
        builder(),
      ),
      _ => builder,
    };
  }

  /// Artificial constraints to be applied to the previewed widget.
  ///
  /// If not provided, the previewed widget will attempt to set its own
  /// constraints.
  ///
  /// If a dimension has a value of `double.infinity`, the previewed widget
  /// will attempt to set its own constraints in the relevant dimension.
  Size? get size => previewData.size;

  /// Finite width constraint from [size], or `null` when unset or infinite.
  double? get finiteWidth => switch (size?.width) {
    final double w when w.isFinite => w,
    _ => null,
  };

  /// Finite height constraint from [size], or `null` when unset or infinite.
  double? get finiteHeight => switch (size?.height) {
    final double h when h.isFinite => h,
    _ => null,
  };

  /// Applies font scaling to text within the [Widget] returned by [builder].
  ///
  /// If not provided, the default text scaling factor provided by [MediaQuery]
  /// will be used.
  double? get textScaleFactor => previewData.textScaleFactor;

  /// Finite [textScaleFactor], or `null` when unset or non-finite.
  double? get finiteTextScaleFactor => switch (textScaleFactor) {
    final double scale when scale.isFinite => scale,
    _ => null,
  };

  /// Material and Cupertino theming data to be applied to the previewed [Widget].
  ///
  /// If not provided, the default theme will be used.
  PreviewThemeData? get theme => previewData.theme?.call();

  /// Sets the initial theme brightness.
  ///
  /// If not provided, the current system default brightness will be used.
  Brightness? get brightness => previewData.brightness;

  /// A callback to return a localization configuration to be applied to the
  /// previewed [Widget].
  ///
  /// Note: this must be a reference to a static, public function defined as
  /// either a top-level function or static member in a class.
  PreviewLocalizationsData? get localizations =>
      previewData.localizations?.call();

  final Preview previewData;

  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
      ..add(DiagnosticsProperty<String>('id', id))
      ..add(DiagnosticsProperty<String>('name', name, ifNull: 'not set'))
      ..add(DiagnosticsProperty<String>('group', previewData.group))
      ..add(DiagnosticsProperty<Size>('size', size))
      ..add(DiagnosticsProperty<double>('textScaleFactor', textScaleFactor))
      ..add(DiagnosticsProperty<PreviewThemeData>('theme', theme))
      ..add(DiagnosticsProperty<Brightness>('brightness', brightness))
      ..add(
        DiagnosticsProperty<PreviewLocalizationsData>(
          'localizations',
          localizations,
        ),
      );
  }
}

/// Metadata and error summary for a single discovered widget preview instance.
extension type const PreviewEntry.fromJson(Map<String, Object?> _json) {
  factory PreviewEntry({
    required int column,
    required String functionName,
    required String group,
    required bool hasError,
    required String id,
    required String libraryUri,
    required int line,
    required String packageName,
    required String scriptUri,
    String? brightness,
    String? errorMessage,
    double? height,
    int? multiPreviewIndex,
    String? name,
    double? textScaleFactor,
    double? width,
  }) => PreviewEntry.fromJson(<String, Object?>{
    _kIdKey: id,
    _kLibraryUriKey: libraryUri,
    _kScriptUriKey: scriptUri,
    _kPackageNameKey: packageName,
    _kFunctionNameKey: functionName,
    _kMultiPreviewIndexKey: multiPreviewIndex,
    _kLineKey: line,
    _kColumnKey: column,
    _kGroupKey: group,
    _kNameKey: name,
    _kWidthKey: width,
    _kHeightKey: height,
    _kTextScaleFactorKey: textScaleFactor,
    _kBrightnessKey: brightness,
    _kHasErrorKey: hasError,
    _kErrorMessageKey: errorMessage,
  });

  /// Configured brightness override (`light` or `dark`), if set.
  String? get brightness => _json[_kBrightnessKey] as String?;

  /// Zero-based source column of the `@Preview` annotation.
  int get column => (_json[_kColumnKey]! as num).toInt();

  /// Analyzer or compilation error summary when [hasError] is `true`.
  String? get errorMessage => _json[_kErrorMessageKey] as String?;

  /// Name of the preview function, constructor, or static member.
  String get functionName => _json[_kFunctionNameKey]! as String;

  /// Group label assigned to this preview.
  String get group => _json[_kGroupKey]! as String;

  /// Whether static analysis or compilation errors prevent rendering.
  bool get hasError => _json[_kHasErrorKey]! as bool;

  /// Explicit preview height in logical pixels, if constrained.
  double? get height => (_json[_kHeightKey] as num?)?.toDouble();

  /// Canonical preview identifier (`<libraryUri>::<functionName>[#<index>]`).
  String get id => _json[_kIdKey]! as String;

  /// `package:` or `dart:` URI of the declaring library.
  String get libraryUri => _json[_kLibraryUriKey]! as String;

  /// Zero-based source line of the `@Preview` annotation.
  int get line => (_json[_kLineKey]! as num).toInt();

  /// Zero-based index within an expanded `@MultiPreview`, or `null`.
  int? get multiPreviewIndex =>
      (_json[_kMultiPreviewIndexKey] as num?)?.toInt();

  /// Optional display name specified on the `@Preview` annotation.
  String? get name => _json[_kNameKey] as String?;

  /// Name of the Dart package declaring this preview.
  String get packageName => _json[_kPackageNameKey]! as String;

  /// `file://` URI of the source file declaring this preview.
  String get scriptUri => _json[_kScriptUriKey]! as String;

  /// Explicit text scale factor override, if configured.
  double? get textScaleFactor =>
      (_json[_kTextScaleFactorKey] as num?)?.toDouble();

  /// Explicit preview width in logical pixels, if constrained.
  double? get width => (_json[_kWidthKey] as num?)?.toDouble();

  /// Returns the underlying JSON-serializable map representation.
  Map<String, Object?> toJson() => _json;
}

/// DTD response containing the list of widget previews in the scaffold.
extension type const PreviewListResponse.fromJson(Map<String, Object?> _json) {
  factory PreviewListResponse({required List<PreviewEntry> previews}) =>
      PreviewListResponse.fromJson(<String, Object?>{
        _kTypeKey: kTypeName,
        _kPreviewsKey: <Map<String, Object?>>[
          for (final PreviewEntry preview in previews) preview.toJson(),
        ],
      });

  factory PreviewListResponse.fromDTDResponse(DTDResponse response) {
    _expectDtdResponseType(response, kTypeName);
    return PreviewListResponse.fromJson(response.result);
  }

  /// Empty [PreviewListResponse] with no preview entries.
  static const empty = PreviewListResponse.fromJson(<String, Object?>{
    _kTypeKey: kTypeName,
    _kPreviewsKey: <Map<String, Object?>>[],
  });

  /// DTD response type discriminator for [PreviewListResponse].
  static const kTypeName = 'PreviewListResponse';

  /// All discovered widget previews included in this response.
  List<PreviewEntry> get previews => <PreviewEntry>[
    for (final Object? item in _json[_kPreviewsKey]! as List<Object?>)
      PreviewEntry.fromJson(item! as Map<String, Object?>),
  ];

  /// Returns the underlying JSON-serializable map representation.
  Map<String, Object?> toJson() => _json;
}

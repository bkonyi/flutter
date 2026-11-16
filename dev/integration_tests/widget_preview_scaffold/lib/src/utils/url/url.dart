// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// NOTE: originally from package:devtools_app_shared

import 'dart:ui' show Brightness;

import 'package:flutter/foundation.dart' show immutable;

import '_url_stub.dart' if (dart.library.js_interop) '_url_web.dart';

export '_url_stub.dart' if (dart.library.js_interop) '_url_web.dart';

const _kZoomPrecisionScale = 10000.0;

/// Parses URL fragment key/value pairs using query-string decoding after
/// stripping any leading `'#'`, `'/'`, or `'?'` characters.
Map<String, String> parseFragmentParameters(String fragment) {
  var normalized = fragment.trim();
  while (normalized.startsWith('#') ||
      normalized.startsWith('/') ||
      normalized.startsWith('?')) {
    normalized = normalized.substring(1);
  }
  if (normalized.isEmpty) {
    return const <String, String>{};
  }
  try {
    return Uri.splitQueryString(normalized);
  } on ArgumentError {
    return const <String, String>{};
  } on FormatException {
    return const <String, String>{};
  }
}

/// Formats [zoom] as a canonical decimal string without trailing `.0` noise.
String formatEmbedZoom(double zoom) {
  final double rounded =
      (zoom * _kZoomPrecisionScale).roundToDouble() / _kZoomPrecisionScale;
  if (rounded == rounded.truncateToDouble()) {
    return rounded.toInt().toString();
  }
  return rounded.toString();
}

/// Returns [fragment] updated with [EmbedPreviewParams.kZoomParam] set to
/// [formatEmbedZoom] of [zoom], or removed when [zoom] equals `1.0`.
String buildUpdatedZoomFragment(String fragment, double zoom) {
  final params = Map<String, String>.of(parseFragmentParameters(fragment));
  if ((zoom - EmbedPreviewParams.kDefaultZoom).abs() <=
      EmbedPreviewParams.kZoomEpsilon) {
    params.remove(EmbedPreviewParams.kZoomParam);
  } else {
    params[EmbedPreviewParams.kZoomParam] = formatEmbedZoom(zoom);
  }
  return Uri(queryParameters: params).query;
}

/// Parsed URL fragment configuration for chromeless single-preview or
/// all-previews embed mode.
@immutable
class EmbedPreviewParams {
  const EmbedPreviewParams({
    this.brightness,
    this.dtdProxy,
    this.height,
    this.isEmbed = false,
    this.previewId,
    this.selectMode = false,
    this.textScale,
    this.width,
    this.zoom,
  });

  factory EmbedPreviewParams.fromCurrentUrl() {
    return EmbedPreviewParams.fromFragment(getUrlFragment());
  }

  factory EmbedPreviewParams.parse(String fragment) =
      EmbedPreviewParams.fromFragment;

  factory EmbedPreviewParams.fromFragment(String fragment) {
    final Map<String, String> params = parseFragmentParameters(fragment);
    final String? rawPreviewId = params[kPreviewIdParam];
    final String? previewId = rawPreviewId != null && rawPreviewId.isNotEmpty
        ? rawPreviewId
        : null;
    final String? rawDtdProxy = params[kDtdProxyParam];
    final String? dtdProxy = rawDtdProxy != null && rawDtdProxy.isNotEmpty
        ? rawDtdProxy
        : null;
    return EmbedPreviewParams(
      brightness: _parseBrightness(params[kBrightnessParam]),
      dtdProxy: dtdProxy,
      height: _parsePositiveFiniteDouble(params[kHeightParam]),
      isEmbed: params[kEmbedParam] == kEmbedEnabledValue,
      previewId: previewId,
      selectMode: _parseSelectMode(params[kSelectParam]),
      textScale: _parsePositiveFiniteDouble(params[kTextScaleParam]),
      width: _parsePositiveFiniteDouble(params[kWidthParam]),
      zoom: _parseZoom(params[kZoomParam]),
    );
  }

  static const kAllPreviewsValue = '*';
  static const kBrightnessParam = 'brightness';
  static const kDarkBrightness = 'dark';
  static const kDefaultDtdProxyPath = 'dtd_ws';
  static const kDefaultZoom = 1.0;
  static const kDtdProxyParam = 'dtdProxy';
  static const kEmbedEnabledValue = '1';
  static const kEmbedParam = 'embed';
  static const kHeightParam = 'height';
  static const kHttpScheme = 'http';
  static const kHttpsScheme = 'https';
  static const kLightBrightness = 'light';
  static const kMaxZoom = 4.0;
  static const kMinZoom = 0.25;
  static const kPreviewIdParam = 'previewId';
  static const kSelectEnabledValue = '1';
  static const kSelectParam = 'select';
  static const kTextScaleParam = 'textScale';
  static const kWidthParam = 'width';
  static const kWsScheme = 'ws';
  static const kWssScheme = 'wss';
  static const kZoomEpsilon = 1e-6;
  static const kZoomParam = 'zoom';
  static const kZoomStep = 0.25;
  static const _kSelectTrueValue = 'true';

  final Brightness? brightness;
  final String? dtdProxy;
  final double? height;
  final bool isEmbed;
  final String? previewId;
  final bool selectMode;
  final double? textScale;
  final double? width;
  final double? zoom;

  /// Whether this embed configuration targets the grouped all-previews gallery
  /// (when [previewId] is omitted, empty, or [kAllPreviewsValue]).
  bool get isAllPreviews => previewId == null || previewId == kAllPreviewsValue;

  /// Returns a copy of this configuration with the specified fields updated.
  EmbedPreviewParams copyWith({
    Brightness? brightness,
    String? dtdProxy,
    double? height,
    bool? isEmbed,
    String? previewId,
    bool? selectMode,
    double? textScale,
    double? width,
    double? zoom,
  }) {
    return EmbedPreviewParams(
      brightness: brightness ?? this.brightness,
      dtdProxy: dtdProxy ?? this.dtdProxy,
      height: height ?? this.height,
      isEmbed: isEmbed ?? this.isEmbed,
      previewId: previewId ?? this.previewId,
      selectMode: selectMode ?? this.selectMode,
      textScale: textScale ?? this.textScale,
      width: width ?? this.width,
      zoom: zoom ?? this.zoom,
    );
  }

  /// Serializes this configuration into a canonical URL fragment query string
  /// without a leading `'#'`.
  String toFragment() {
    final queryParams = <String, String>{
      if (isEmbed) kEmbedParam: kEmbedEnabledValue,
      if (previewId case final String id when id.isNotEmpty)
        kPreviewIdParam: id,
      if (brightness case final Brightness resolvedBrightness)
        kBrightnessParam: resolvedBrightness == Brightness.dark
            ? kDarkBrightness
            : kLightBrightness,
      if (width case final double resolvedWidth)
        kWidthParam: formatEmbedZoom(resolvedWidth),
      if (height case final double resolvedHeight)
        kHeightParam: formatEmbedZoom(resolvedHeight),
      if (textScale case final double resolvedTextScale)
        kTextScaleParam: formatEmbedZoom(resolvedTextScale),
      if (zoom case final double resolvedZoom
          when (resolvedZoom - kDefaultZoom).abs() > kZoomEpsilon)
        kZoomParam: formatEmbedZoom(resolvedZoom),
      if (selectMode) kSelectParam: kSelectEnabledValue,
      if (dtdProxy case final String proxy when proxy.isNotEmpty)
        kDtdProxyParam: proxy,
    };
    if (queryParams.isEmpty) {
      return '';
    }
    return Uri(queryParameters: queryParams).query;
  }

  /// Returns a copy of this configuration with [zoom] clamped to
  /// `[kMinZoom, kMaxZoom]`, or cleared to `null` when at [kDefaultZoom].
  EmbedPreviewParams withZoom(double nextZoom) {
    final double clamped = nextZoom.clamp(kMinZoom, kMaxZoom);
    final double? normalized = (clamped - kDefaultZoom).abs() <= kZoomEpsilon
        ? null
        : clamped;
    return EmbedPreviewParams(
      brightness: brightness,
      dtdProxy: dtdProxy,
      height: height,
      isEmbed: isEmbed,
      previewId: previewId,
      selectMode: selectMode,
      textScale: textScale,
      width: width,
      zoom: normalized,
    );
  }

  /// Resolves [dtdProxy] (or [kDefaultDtdProxyPath] when [isEmbed] is `true`)
  /// against [baseUri] using `ws` or `wss`, or returns `null` if [baseUri] has
  /// no authority, is not HTTP/HTTPS, or [dtdProxy] is unset outside embed
  /// mode.
  Uri? resolveDtdProxyUri(Uri baseUri) {
    if (baseUri.authority.isEmpty ||
        (baseUri.scheme != kHttpScheme && baseUri.scheme != kHttpsScheme)) {
      return null;
    }
    final String wsScheme = baseUri.scheme == kHttpsScheme
        ? kWssScheme
        : kWsScheme;
    final String? proxy = dtdProxy;
    if (proxy != null && proxy.isNotEmpty) {
      final String normalizedPath = proxy.startsWith('/') ? proxy : '/$proxy';
      return Uri.parse('$wsScheme://${baseUri.authority}$normalizedPath');
    }
    if (!isEmbed) {
      return null;
    }
    return baseUri.resolve(kDefaultDtdProxyPath).replace(scheme: wsScheme);
  }

  static Brightness? _parseBrightness(String? value) => switch (value) {
    kLightBrightness => Brightness.light,
    kDarkBrightness => Brightness.dark,
    _ => null,
  };

  static bool _parseSelectMode(String? value) =>
      value == kSelectEnabledValue || value?.toLowerCase() == _kSelectTrueValue;

  static double? _parsePositiveFiniteDouble(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final double? parsed = double.tryParse(value);
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      return null;
    }
    return parsed;
  }

  static double? _parseZoom(String? value) {
    final double? parsed = _parsePositiveFiniteDouble(value);
    if (parsed == null) {
      return null;
    }
    return parsed.clamp(kMinZoom, kMaxZoom);
  }

  @override
  int get hashCode => Object.hash(
    brightness,
    dtdProxy,
    height,
    isEmbed,
    previewId,
    selectMode,
    textScale,
    width,
    zoom,
  );

  @override
  bool operator ==(Object other) {
    return other is EmbedPreviewParams &&
        other.runtimeType == EmbedPreviewParams &&
        brightness == other.brightness &&
        dtdProxy == other.dtdProxy &&
        height == other.height &&
        isEmbed == other.isEmbed &&
        previewId == other.previewId &&
        selectMode == other.selectMode &&
        textScale == other.textScale &&
        width == other.width &&
        zoom == other.zoom;
  }
}

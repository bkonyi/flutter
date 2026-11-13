// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// NOTE: originally from package:devtools_app_shared

import 'dart:ui' show Brightness;

import 'package:flutter/foundation.dart' show immutable;

import '_url_stub.dart' if (dart.library.js_interop) '_url_web.dart';

export '_url_stub.dart' if (dart.library.js_interop) '_url_web.dart';

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
    this.textScale,
    this.width,
  });

  factory EmbedPreviewParams.fromCurrentUrl() {
    return EmbedPreviewParams.fromFragment(getUrlFragment());
  }

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
      textScale: _parsePositiveFiniteDouble(params[kTextScaleParam]),
      width: _parsePositiveFiniteDouble(params[kWidthParam]),
    );
  }

  static const kAllPreviewsValue = '*';
  static const kBrightnessParam = 'brightness';
  static const kDarkBrightness = 'dark';
  static const kDefaultDtdProxyPath = 'dtd_ws';
  static const kDtdProxyParam = 'dtdProxy';
  static const kEmbedEnabledValue = '1';
  static const kEmbedParam = 'embed';
  static const kHeightParam = 'height';
  static const kHttpScheme = 'http';
  static const kHttpsScheme = 'https';
  static const kLightBrightness = 'light';
  static const kPreviewIdParam = 'previewId';
  static const kTextScaleParam = 'textScale';
  static const kWidthParam = 'width';
  static const kWsScheme = 'ws';
  static const kWssScheme = 'wss';

  final Brightness? brightness;
  final String? dtdProxy;
  final double? height;
  final bool isEmbed;
  final String? previewId;
  final double? textScale;
  final double? width;

  /// Whether this embed configuration targets the grouped all-previews gallery
  /// (when [previewId] is omitted, empty, or [kAllPreviewsValue]).
  bool get isAllPreviews => previewId == null || previewId == kAllPreviewsValue;

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

  @override
  int get hashCode => Object.hash(
    brightness,
    dtdProxy,
    height,
    isEmbed,
    previewId,
    textScale,
    width,
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
        textScale == other.textScale &&
        width == other.width;
  }
}

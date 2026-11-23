// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:json_rpc_2/json_rpc_2.dart' show RpcException;
import 'package:meta/meta.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../base/io.dart';
import '../convert.dart';
import '../web/bootstrap.dart';
import '../web/memory_fs.dart';
import '../web/module_metadata.dart';
import '../widget_preview/dtd_services.dart';
import '../widget_preview/dtd_types.dart';
import 'web_server_utilities.dart';

/// Factory for opening an upstream DTD [WebSocketChannel] connection.
typedef DtdWebSocketConnector = WebSocketChannel Function(Uri uri);

/// Configuration for the DWDS-free widget preview live server and scoped DTD
/// WebSocket proxy.
class WidgetPreviewLiveConfig {
  const WidgetPreviewLiveConfig({
    required this.dtdServices,
    this.allowedOrigins = const <String>[],
    @visibleForTesting this.dtdWebSocketConnector = WebSocketChannel.connect,
    @visibleForTesting this.maxActiveWebSockets = kDefaultMaxActiveWebSockets,
  });

  /// Default cap on concurrent `/dtd_ws` client WebSocket connections.
  static const kDefaultMaxActiveWebSockets = 32;

  /// The tool-side DTD service manager backing `/__api/*` and `/dtd_ws`.
  final WidgetPreviewDtdServices dtdServices;

  /// Explicit HTTP/HTTPS origins permitted in addition to same-origin loopback
  /// requests (supplied via `--web-allow-origin`).
  final List<String> allowedOrigins;

  /// Factory used to open upstream WebSocket connections to DTD.
  final DtdWebSocketConnector dtdWebSocketConnector;

  /// Maximum number of concurrent `/dtd_ws` client connections accepted before
  /// rejecting additional upgrades with HTTP 503.
  final int maxActiveWebSockets;
}

String _normalizeLoopbackHost(String host) => switch (host.toLowerCase()) {
  'localhost' || '127.0.0.1' || '::1' || '[::1]' => 'localhost',
  final String lower => lower,
};

/// Zero-cost wrapper over a parsed origin [Uri] with loopback-normalized host
/// and resolved HTTP/HTTPS port semantics.
extension type const _OriginAuthority._(Uri _uri) {
  /// Parses [raw] into an origin authority, returning `null` if [raw] lacks a
  /// scheme or host.
  static _OriginAuthority? tryParse(String raw) {
    final Uri? uri = Uri.tryParse(raw.trim());
    return uri != null && uri.hasScheme && uri.host.isNotEmpty ? _OriginAuthority._(uri) : null;
  }

  String get host => _normalizeLoopbackHost(_uri.host);
  int get port => _uri.hasPort ? _uri.port : (scheme == 'https' ? 443 : 80);
  String get scheme => _uri.scheme;
  bool get isHttpOrHttps => scheme == 'http' || scheme == 'https';
  String get normalized => '$scheme://$host:$port';
  String get origin => _uri.origin;

  bool matchesHostPort(_OriginAuthority other) => host == other.host && port == other.port;
}

/// Serves DWDS-free widget preview embed assets, the `/live` interactive shell,
/// `/__api/*` HTTP endpoints, and the scoped `/dtd_ws` JSON-RPC bridge.
class WidgetPreviewLiveServer {
  WidgetPreviewLiveServer({
    required this.basePathProvider,
    required this.config,
    required this.configuredHost,
    required this.isWindows,
    required this.modules,
    required this.renderFlutterBootstrapJs,
    required this.renderIndexHtml,
    required this.webMemoryFS,
  });

  static const _kApiHotReloadPath = '__api/hot-reload';
  static const _kApiStatusPath = '__api/status';
  static const _kApiSyncPath = '__api/sync';
  static const _kCodeKey = 'code';
  static const _kCorpHeader = 'cross-origin-resource-policy';
  static const _kCorpSameSite = 'same-site';
  static const _kCspHeader = 'content-security-policy';
  static const _kDtdWsPath = 'dtd_ws';
  static const _kEmbedFlutterBootstrapPath = '__embed_flutter_bootstrap.js';
  static const _kEmbedMainDartJsPath = '__embed_main.dart.js';
  static const _kEmbedMainModuleBootstrapPath = '__embed_main_module.bootstrap.js';
  static const _kEntrypointExtensionMarker = '/* ENTRYPOINT_EXTENTION_MARKER */';
  static const _kErrorKey = 'error';
  static const _kFullRestartRequiredKey = 'fullRestartRequired';
  static const _kHtmlContentType = 'text/html; charset=utf-8';
  static const _kIdKey = 'id';
  static const _kImmutableCacheControl = 'private, max-age=31536000, immutable';
  static const _kJsContentType = 'application/javascript; charset=utf-8';
  static const _kJsonContentType = 'application/json; charset=utf-8';
  static const _kJsonRpcKey = 'jsonrpc';
  static const _kJsonRpcVersion = '2.0';
  static const _kLiveBgStyleTag =
      '<style id="wp-live-bg">html,body{margin:0;background:#121212;color:#e4e4e7}</style>';
  static const _kLivePath = 'live';
  static const _kLiveRevisionKey = '__wpLiveRevision';
  static const _kLiveSlashPath = 'live/';
  static const _kMainModuleBootstrapPath = 'main_module.bootstrap.js';
  static const int _kMaxRequestPoolSize = 100;
  static const int _kMaxRpcFrameBytes = 64 * 1024;
  static const _kMessageKey = 'message';
  static const _kMethodKey = 'method';
  static const _kModulesKey = 'modules';
  static const _kNoCacheHeaders = <String, String>{HttpHeaders.cacheControlHeader: 'no-cache'};
  static const _kNoSniffHeader = 'x-content-type-options';
  static const _kNoSniffValue = 'nosniff';
  static const _kNoStoreHeaders = <String, String>{HttpHeaders.cacheControlHeader: 'no-store'};
  static const _kOriginHeader = 'origin';
  static const _kParamsKey = 'params';
  static const _kPlainContentType = 'text/plain; charset=utf-8';
  static const _kResultKey = 'result';
  static const _kRetryAfterSeconds = '5';
  static const _kRevQueryParam = 'rev';
  static const _kRevisionKey = 'revision';
  static const _kSecFetchSiteHeader = 'sec-fetch-site';
  static const _kSecFetchSiteNone = 'none';
  static const _kSecFetchSiteSameOrigin = 'same-origin';
  static const _kSinceQueryParam = 'since';
  static const _kStatusKey = 'status';
  static const _kStreamListenMethod = 'streamListen';
  static const _kStreamCancelMethod = 'streamCancel';
  static const _kStreamIdKey = 'streamId';
  static const _kWebSocketPingInterval = Duration(seconds: 30);

  static const _kJsonRpcParseError = -32700;
  static const _kJsonRpcInvalidRequest = -32600;
  static const _kJsonRpcMethodNotFound = -32601;
  static const _kJsonRpcInvalidParams = -32602;

  /// Returns the current base URL path prefix for the web asset server.
  final String Function() basePathProvider;

  /// Live server and DTD WebSocket bridge configuration.
  final WidgetPreviewLiveConfig config;

  /// Hostname configured for the web asset server (e.g. `localhost`).
  final String configuredHost;

  /// Whether the Flutter tool is running on Windows.
  final bool isWindows;

  /// Map of DDC module IDs to their relative script paths (without `.js`).
  final Map<String, String> modules;

  /// Renders the current `flutter_bootstrap.js` content.
  final String Function() renderFlutterBootstrapJs;

  /// Renders the current `index.html` content.
  final String Function() renderIndexHtml;

  /// In-memory compiled DDC files, metadata, and revision tracking.
  final WebMemoryFS webMemoryFS;

  final String _serverNonce =
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${Random.secure().nextInt(0x7fffffff).toRadixString(36)}';
  final _clientChannels = <WebSocketChannel>{};
  final _upstreamChannels = <WebSocketChannel>{};
  int? _committedRevision;
  var _lastFullRestartRevision = 0;
  var _reportedEmbedOpen = false;
  var _reportedLiveOpen = false;

  static const _kBaseSecurityHeaders = <String, String>{
    _kCorpHeader: _kCorpSameSite,
    _kNoSniffHeader: _kNoSniffValue,
  };

  int get _currentRevision => _committedRevision ?? webMemoryFS.revision;

  /// Records that the primary preview runtime committed the current
  /// [WebMemoryFS.revision].
  ///
  /// When [fullRestart] is `true`, viewers catching up from any earlier
  /// revision are instructed via `fullRestartRequired: true` on
  /// `/__api/hot-reload` to reload the page instead of applying an in-place
  /// module delta across a hot-restart boundary.
  void recordReloadCommitted({required bool fullRestart}) {
    final int revision = webMemoryFS.revision;
    _committedRevision = revision;
    if (fullRestart) {
      _lastFullRestartRevision = revision;
    }
  }

  /// Handles incoming requests for live/embed routes, returning 404 for all
  /// non-live routes so normal DWDS traffic falls through.
  Future<shelf.Response> handler(shelf.Request request) async {
    final String? requestPath = stripBasePath(request.url.path, basePathProvider());
    if (requestPath == null) {
      return shelf.Response.notFound('');
    }

    if (request.method == 'GET' &&
        (requestPath == '/' || requestPath.isEmpty) &&
        request.url.queryParameters['embed'] == '1') {
      if (!_reportedEmbedOpen) {
        _reportedEmbedOpen = true;
        config.dtdServices.previewAnalytics.reportLiveViewOpened(isEmbed: true);
      }
      return _serveEmbedIndexHtml();
    }

    if (request.method == 'GET' && (requestPath == _kLivePath || requestPath == _kLiveSlashPath)) {
      if (!_reportedLiveOpen) {
        _reportedLiveOpen = true;
        config.dtdServices.previewAnalytics.reportLiveViewOpened(isEmbed: false);
      }
      return _serveEmbedIndexHtml();
    }

    final bool isVersionedModule =
        request.method == 'GET' &&
        request.url.queryParameters.containsKey(_kRevQueryParam) &&
        requestPath.endsWith('.js') &&
        webMemoryFS.files.containsKey(requestPath);
    final bool isProtectedRoute = switch (requestPath) {
      _kEmbedFlutterBootstrapPath ||
      _kEmbedMainDartJsPath ||
      _kEmbedMainModuleBootstrapPath ||
      _kApiHotReloadPath ||
      _kApiStatusPath ||
      _kApiSyncPath ||
      _kDtdWsPath => true,
      _ => isVersionedModule,
    };
    if (!isProtectedRoute) {
      return shelf.Response.notFound('');
    }

    if (!_isRequestAuthorized(request)) {
      return shelf.Response.forbidden(
        'Cross-origin request rejected.',
        headers: _securityHeaders(contentType: _kPlainContentType),
      );
    }

    if (isVersionedModule) {
      return _serveVersionedModule(requestPath, request.url.queryParameters[_kRevQueryParam]);
    }

    return switch ((request.method, requestPath)) {
      ('GET', _kEmbedFlutterBootstrapPath) => _serveEmbedFlutterBootstrapJs(),
      ('GET', _kEmbedMainDartJsPath) => _serveEmbedMainDartJs(),
      ('GET', _kEmbedMainModuleBootstrapPath) => _serveEmbedMainModuleBootstrapJs(),
      ('GET', _kApiHotReloadPath) => _serveApiHotReload(request),
      ('GET', _kApiStatusPath) => _serveApiStatus(),
      ('POST', _kApiSyncPath) => _serveApiSync(),
      ('GET', _kDtdWsPath) => _serveDtdWebSocket(request),
      _ => shelf.Response.notFound(''),
    };
  }

  /// Closes all active `/dtd_ws` WebSocket connections.
  Future<void> dispose() async {
    final channels = <WebSocketChannel>[..._clientChannels, ..._upstreamChannels];
    _clientChannels.clear();
    _upstreamChannels.clear();
    await Future.wait(channels.map(_closeChannelSafely));
  }

  Map<String, String> _securityHeaders({
    String? contentType,
    Map<String, String> extra = const <String, String>{},
  }) => <String, String>{
    ..._kBaseSecurityHeaders,
    HttpHeaders.contentTypeHeader: ?contentType,
    ...extra,
  };

  shelf.Response _jsOkResponse(
    Object body, {
    Map<String, String> extra = const <String, String>{},
  }) {
    return shelf.Response.ok(
      body,
      encoding: body is String ? utf8 : null,
      headers: _securityHeaders(contentType: _kJsContentType, extra: extra),
    );
  }

  shelf.Response _jsonResponse(
    Map<String, Object?> payload, {
    int statusCode = HttpStatus.ok,
    bool noStore = false,
  }) => shelf.Response(
    statusCode,
    body: jsonEncode(payload),
    encoding: utf8,
    headers: _securityHeaders(
      contentType: _kJsonContentType,
      extra: noStore ? _kNoStoreHeaders : const <String, String>{},
    ),
  );

  shelf.Response _jsonErrorResponse(int statusCode, String message) =>
      _jsonResponse(<String, Object?>{_kErrorKey: message}, statusCode: statusCode);

  String _rootRelativePath(String subPath) {
    final String basePath = basePathProvider().replaceAll(RegExp(r'^/+|/+$'), '');
    return basePath.isEmpty ? '/$subPath' : '/$basePath/$subPath';
  }

  String _frameAncestorsPolicy() {
    final ancestors = <String>["'self'"];
    for (final String allowed in config.allowedOrigins) {
      if (_OriginAuthority.tryParse(allowed) case final _OriginAuthority auth
          when auth.isHttpOrHttps) {
        final String origin = auth.origin;
        if (!ancestors.contains(origin)) {
          ancestors.add(origin);
        }
      }
    }
    return 'frame-ancestors ${ancestors.join(' ')}';
  }

  shelf.Response _serveEmbedIndexHtml() {
    final String html = renderIndexHtml()
        .replaceAll('flutter_bootstrap.js', _rootRelativePath(_kEmbedFlutterBootstrapPath))
        .replaceAll('main.dart.js', _rootRelativePath(_kEmbedMainDartJsPath))
        .replaceFirst('</head>', '$_kLiveBgStyleTag</head>');
    return shelf.Response.ok(
      html,
      encoding: utf8,
      headers: _securityHeaders(
        contentType: _kHtmlContentType,
        extra: <String, String>{..._kNoCacheHeaders, _kCspHeader: _frameAncestorsPolicy()},
      ),
    );
  }

  shelf.Response _serveEmbedFlutterBootstrapJs() => _jsOkResponse(
    renderFlutterBootstrapJs().replaceAll('main.dart.js', _rootRelativePath(_kEmbedMainDartJsPath)),
  );

  shelf.Response _serveEmbedMainDartJs() => _jsOkResponse(
    generateDDCLibraryBundleBootstrapScript(
      ddcModuleLoaderUrl: 'ddc_module_loader.js',
      mapperUrl: 'stack_trace_mapper.js',
      generateLoadingIndicator: false,
      isWindows: isWindows,
    ).replaceAll('main_module.bootstrap.js', _kEmbedMainModuleBootstrapPath),
  );

  shelf.Response _serveEmbedMainModuleBootstrapJs() {
    final Uint8List? storedBootstrap = webMemoryFS.files[_kMainModuleBootstrapPath];
    if (storedBootstrap == null) {
      return shelf.Response.notFound(
        '$_kMainModuleBootstrapPath has not been compiled yet.',
        headers: _securityHeaders(contentType: _kPlainContentType),
      );
    }
    final String decodedBootstrap = utf8.decode(storedBootstrap);
    if (!decodedBootstrap.contains(_kEntrypointExtensionMarker)) {
      throw StateError(
        '$_kMainModuleBootstrapPath is missing expected $_kEntrypointExtensionMarker marker.',
      );
    }
    return _jsOkResponse(
      decodedBootstrap.replaceFirst(_kEntrypointExtensionMarker, _buildEmbedModuleRegistrationJs()),
      extra: _kNoCacheHeaders,
    );
  }

  String _moduleRevToken(int moduleRev) => '$_serverNonce-$moduleRev';

  String _versionedModuleSrc(String fileName, int moduleRev) =>
      '$fileName?$_kRevQueryParam=${_moduleRevToken(moduleRev)}';

  String _buildEmbedModuleRegistrationJs() {
    final int revision = _currentRevision;
    final scripts = <Map<String, String>>[
      for (final MapEntry(key: name, value: path) in modules.entries)
        <String, String>{
          'src': _versionedModuleSrc('$path.js', webMemoryFS.moduleRevisions['$path.js'] ?? 0),
          'id': name,
        },
    ];
    // Cap concurrent script requests at 100 (matching bootstrap.dart CI mode;
    // https://github.com/flutter/flutter/issues/169574) so loading 1,000+
    // versioned DDC modules in headless Chrome does not stall.
    return '''
self.$_kLiveRevisionKey=$revision;
var scripts = ${jsonEncode(scripts)};
window.\$dartLoader.loadConfig.maxRequestPoolSize = $_kMaxRequestPoolSize;
window.\$dartLoader.loadConfig.loadScriptFn = function(loader) {
  loader.addScriptsToQueue(scripts, null);
  loader.loadEnqueuedModules();
};
window.\$dartLoader.loader.nextAttempt();
''';
  }

  shelf.Response _serveVersionedModule(String requestPath, String? revParam) {
    final Uint8List? fileBytes = webMemoryFS.files[requestPath];
    if (fileBytes == null) {
      return shelf.Response.notFound('');
    }
    final int moduleRev = webMemoryFS.moduleRevisions[requestPath] ?? 0;
    final bool matchesCurrent = revParam != null && revParam == _moduleRevToken(moduleRev);
    return _jsOkResponse(
      fileBytes,
      extra: matchesCurrent
          ? const <String, String>{HttpHeaders.cacheControlHeader: _kImmutableCacheControl}
          : _kNoStoreHeaders,
    );
  }

  shelf.Response _serveApiHotReload(shelf.Request request) {
    final String? rawSince = request.url.queryParameters[_kSinceQueryParam];
    final int? since = rawSince != null ? int.tryParse(rawSince) : null;
    if (since == null || since < 0) {
      return _jsonErrorResponse(
        HttpStatus.badRequest,
        'Query parameter "$_kSinceQueryParam" must be a non-negative integer.',
      );
    }
    final int currentRevision = _currentRevision;
    final bool fullRestartRequired = since < _lastFullRestartRevision;
    final changedModules = <Map<String, Object?>>[];
    if (!fullRestartRequired && since < currentRevision) {
      for (final MapEntry(key: id, value: path) in modules.entries) {
        final fileName = '$path.js';
        final int? moduleRev = webMemoryFS.moduleRevisions[fileName];
        if (moduleRev == null ||
            moduleRev <= since ||
            moduleRev > currentRevision ||
            !webMemoryFS.files.containsKey(fileName)) {
          continue;
        }
        final List<String>? libraries = _librariesForModule(fileName);
        if (libraries == null) {
          return _jsonErrorResponse(
            HttpStatus.internalServerError,
            'Missing DDC module metadata for "$fileName".',
          );
        }
        changedModules.add(<String, Object?>{
          'src': _versionedModuleSrc(fileName, moduleRev),
          'id': id,
          'libraries': libraries,
        });
      }
    }
    return _jsonResponse(<String, Object?>{
      _kRevisionKey: currentRevision,
      PreviewServiceInfo.kScaffoldStream: config.dtdServices.widgetPreviewScaffoldStream,
      _kFullRestartRequiredKey: fullRestartRequired,
      _kModulesKey: changedModules,
    }, noStore: true);
  }

  List<String>? _librariesForModule(String fileName) {
    final Uint8List? metadataBytes = webMemoryFS.metadataFiles['$fileName.metadata'];
    if (metadataBytes == null) {
      return null;
    }
    final Object? decoded = json.decode(utf8.decode(metadataBytes));
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final metadata = ModuleMetadata.fromJson(decoded);
    return metadata.libraries.isEmpty ? null : metadata.libraries.keys.toList();
  }

  shelf.Response _serveApiStatus() {
    final WidgetPreviewDtdServices dtdServices = config.dtdServices;
    return _jsonResponse(<String, Object?>{
      _kStatusKey: 'ready',
      PreviewServiceInfo.kProjectRoot:
          dtdServices.projectRootPath ?? dtdServices.project.directory.path,
      PreviewServiceInfo.kPreviewService: dtdServices.widgetPreviewService,
      PreviewServiceInfo.kScaffoldService: dtdServices.widgetPreviewScaffoldService,
      PreviewServiceInfo.kScaffoldStream: dtdServices.widgetPreviewScaffoldStream,
      PreviewServiceInfo.kScaffoldConnected: dtdServices.scaffoldConnected,
    }, noStore: true);
  }

  Future<shelf.Response> _serveApiSync() async {
    final Future<SyncPreviewsResponse> Function({required Duration timeout})? onSyncPreviews =
        config.dtdServices.onSyncPreviews;
    if (onSyncPreviews == null) {
      return _jsonErrorResponse(
        HttpStatus.serviceUnavailable,
        'Preview synchronization is not currently available.',
      );
    }
    try {
      final SyncPreviewsResponse response = await onSyncPreviews(
        timeout: const Duration(milliseconds: WidgetPreviewDtdServices.kDefaultSyncTimeoutMs),
      );
      return _jsonResponse(response.toJson(), noStore: true);
    } on RpcException catch (e) {
      return _jsonErrorResponse(HttpStatus.serviceUnavailable, e.message);
    } on TimeoutException catch (e) {
      return _jsonErrorResponse(
        HttpStatus.serviceUnavailable,
        e.message ?? 'Timed out synchronizing widget previews.',
      );
    }
  }

  FutureOr<shelf.Response> _serveDtdWebSocket(shelf.Request request) {
    final Uri? dtdUri = config.dtdServices.dtdUri;
    if (dtdUri == null) {
      return shelf.Response(
        HttpStatus.serviceUnavailable,
        body: 'DTD server URI is not available.',
        headers: _securityHeaders(contentType: _kPlainContentType),
      );
    }
    if (_clientChannels.length >= config.maxActiveWebSockets) {
      return shelf.Response(
        HttpStatus.serviceUnavailable,
        body: 'Too many active /dtd_ws connections.',
        headers: _securityHeaders(
          contentType: _kPlainContentType,
          extra: const <String, String>{HttpHeaders.retryAfterHeader: _kRetryAfterSeconds},
        ),
      );
    }
    final shelf.Handler wsHandler = webSocketHandler((WebSocketChannel clientChannel, String? _) {
      _bridgeDtdWebSocket(clientChannel, dtdUri);
    }, pingInterval: _kWebSocketPingInterval);
    return wsHandler(request);
  }

  void _bridgeDtdWebSocket(WebSocketChannel clientChannel, Uri dtdUri) {
    if (_clientChannels.length >= config.maxActiveWebSockets) {
      unawaited(_closeChannelSafely(clientChannel));
      return;
    }
    final WebSocketChannel upstreamChannel = config.dtdWebSocketConnector(dtdUri);
    _clientChannels.add(clientChannel);
    _upstreamChannels.add(upstreamChannel);

    var closed = false;
    Future<void> closeBoth() async {
      if (closed) {
        return;
      }
      closed = true;
      _clientChannels.remove(clientChannel);
      _upstreamChannels.remove(upstreamChannel);
      await Future.wait<void>(<Future<void>>[
        _closeChannelSafely(clientChannel),
        _closeChannelSafely(upstreamChannel),
      ]);
    }

    upstreamChannel.stream.listen(
      (Object? message) {
        if (!closed) {
          clientChannel.sink.add(message);
        }
      },
      onError: (Object _) => closeBoth(),
      onDone: closeBoth,
    );

    clientChannel.stream.listen(
      (Object? message) {
        if (closed) {
          return;
        }
        final String? sanitized = _sanitizeAndFilterRpc(message, clientChannel);
        if (sanitized != null) {
          upstreamChannel.sink.add(sanitized);
        }
      },
      onError: (Object _) => closeBoth(),
      onDone: closeBoth,
    );
  }

  String? _sanitizeAndFilterRpc(Object? message, WebSocketChannel clientChannel) {
    String? fail(int code, String errorMessage, {Object? id}) {
      _sendRpcError(clientChannel, id: id, code: code, message: errorMessage);
      return null;
    }

    if (message is! String) {
      return fail(_kJsonRpcInvalidRequest, 'JSON-RPC requests must be text frames.');
    }
    if (message.length > _kMaxRpcFrameBytes ||
        (message.length * 3 > _kMaxRpcFrameBytes &&
            utf8.encode(message).length > _kMaxRpcFrameBytes)) {
      return fail(_kJsonRpcInvalidRequest, 'JSON-RPC request exceeds maximum frame size.');
    }

    final Object? decoded;
    try {
      decoded = json.decode(message);
    } on FormatException {
      return fail(_kJsonRpcParseError, 'Parse error.');
    }

    if (decoded is! Map<String, Object?>) {
      return fail(_kJsonRpcInvalidRequest, 'Invalid Request.');
    }

    final Object? rawId = decoded[_kIdKey];
    final Object? rpcId = (rawId is String || rawId is int) ? rawId : null;
    if (decoded case {_kJsonRpcKey: _kJsonRpcVersion, _kMethodKey: final String method, _kIdKey: _}
        when rpcId != null) {
      final Object? rawParams = decoded[_kParamsKey];
      if (rawParams is! Map<String, Object?>?) {
        return fail(_kJsonRpcInvalidParams, 'Invalid params.', id: rpcId);
      }
      final Map<String, Object?>? params = rawParams;
      final WidgetPreviewDtdServices dtdServices = config.dtdServices;

      final Map<String, Object?> cleanParams;
      if (method == _kStreamListenMethod || method == _kStreamCancelMethod) {
        if (params?[_kStreamIdKey] != dtdServices.widgetPreviewScaffoldStream) {
          return fail(
            _kJsonRpcMethodNotFound,
            'Stream "$method" is not allowed on this endpoint.',
            id: rpcId,
          );
        }
        cleanParams = <String, Object?>{_kStreamIdKey: dtdServices.widgetPreviewScaffoldStream};
      } else if (method ==
          '${dtdServices.widgetPreviewService}.${WidgetPreviewDtdServices.kListPreviews}') {
        cleanParams = <String, Object?>{
          WidgetPreviewDtdServices.kSync: false,
          if (params?[WidgetPreviewDtdServices.kFileUri] case final String fileUri
              when fileUri.isNotEmpty)
            WidgetPreviewDtdServices.kFileUri: fileUri,
        };
      } else if (method ==
          '${dtdServices.widgetPreviewScaffoldService}.${WidgetPreviewDtdServices.kGetPreviews}') {
        cleanParams = <String, Object?>{
          if (params?[WidgetPreviewDtdServices.kFileUri] case final String fileUri
              when fileUri.isNotEmpty)
            WidgetPreviewDtdServices.kFileUri: fileUri,
        };
      } else if (method ==
          '${dtdServices.widgetPreviewService}.${WidgetPreviewDtdServices.kGetServiceInfo}') {
        _sendRpcResult(
          clientChannel,
          id: rpcId,
          result: <String, Object?>{
            PreviewServiceInfo.kType: PreviewServiceInfo.kTypeName,
            PreviewServiceInfo.kPreviewService: dtdServices.widgetPreviewService,
            PreviewServiceInfo.kScaffoldService: dtdServices.widgetPreviewScaffoldService,
            PreviewServiceInfo.kScaffoldStream: dtdServices.widgetPreviewScaffoldStream,
            PreviewServiceInfo.kWebPreviewUri: dtdServices.webPreviewUriProvider
                ?.call()
                ?.toString(),
            PreviewServiceInfo.kScaffoldConnected: dtdServices.scaffoldConnected,
          },
        );
        return null;
      } else {
        return fail(_kJsonRpcMethodNotFound, 'Method "$method" is not allowed.', id: rpcId);
      }

      return jsonEncode(<String, Object?>{
        _kJsonRpcKey: _kJsonRpcVersion,
        _kIdKey: rpcId,
        _kMethodKey: method,
        _kParamsKey: cleanParams,
      });
    }

    return fail(_kJsonRpcInvalidRequest, 'Invalid Request.', id: rpcId);
  }

  static Future<void> _closeChannelSafely(WebSocketChannel channel) async {
    try {
      await channel.sink.close();
    } on Object {
      // Ignore errors when closing an already-terminated WebSocket sink.
    }
  }

  static void _sendRpcResult(
    WebSocketChannel channel, {
    required Object? id,
    required Map<String, Object?> result,
  }) {
    channel.sink.add(
      jsonEncode(<String, Object?>{
        _kJsonRpcKey: _kJsonRpcVersion,
        _kIdKey: id,
        _kResultKey: result,
      }),
    );
  }

  static void _sendRpcError(
    WebSocketChannel channel, {
    required int code,
    required Object? id,
    required String message,
  }) {
    channel.sink.add(
      jsonEncode(<String, Object?>{
        _kJsonRpcKey: _kJsonRpcVersion,
        _kIdKey: id,
        _kErrorKey: <String, Object?>{_kCodeKey: code, _kMessageKey: message},
      }),
    );
  }

  bool _isRequestAuthorized(shelf.Request request) {
    final String? originHeader = request.headers[_kOriginHeader];
    final String? secFetchSite = request.headers[_kSecFetchSiteHeader]?.toLowerCase();
    final bool originExplicitlyAllowed =
        originHeader != null && _isOriginExplicitlyAllowed(originHeader);

    // Unless the Origin is explicitly allowlisted via --web-allow-origin, only
    // allow same-origin, none, or missing Sec-Fetch-Site. Rejecting
    // `same-site` (e.g. `<script>` from another local port) provides
    // defense-in-depth on the live bundle and API routes.
    if (secFetchSite != null &&
        secFetchSite.isNotEmpty &&
        secFetchSite != _kSecFetchSiteSameOrigin &&
        secFetchSite != _kSecFetchSiteNone &&
        !originExplicitlyAllowed) {
      return false;
    }

    if (originExplicitlyAllowed) {
      return true;
    }

    final String? hostHeader = request.headers[HttpHeaders.hostHeader];
    if (originHeader == null || originHeader.isEmpty) {
      return hostHeader == null ||
          hostHeader.isEmpty ||
          _isAllowedHostHeader(hostHeader) ||
          _isHostMatchingAllowedOrigin(hostHeader);
    }

    if (hostHeader != null && hostHeader.isNotEmpty && !_isAllowedHostHeader(hostHeader)) {
      return false;
    }

    return _isSameAuthorityOrigin(originHeader, hostHeader);
  }

  bool _isHostMatchingAllowedOrigin(String hostHeader) {
    for (final String allowed in config.allowedOrigins) {
      final _OriginAuthority? allowedAuth = _OriginAuthority.tryParse(allowed);
      if (allowedAuth == null || !allowedAuth.isHttpOrHttps) {
        continue;
      }
      final _OriginAuthority? hostAuth = _OriginAuthority.tryParse(
        '${allowedAuth.scheme}://$hostHeader',
      );
      if (hostAuth != null && hostAuth.matchesHostPort(allowedAuth)) {
        return true;
      }
    }
    return false;
  }

  bool _isAllowedHostHeader(String hostHeader) {
    final _OriginAuthority? auth = _OriginAuthority.tryParse('http://$hostHeader');
    return auth != null && _isAllowedNormalizedHost(auth.host);
  }

  bool _isAllowedNormalizedHost(String normalizedHost) =>
      normalizedHost == 'localhost' || normalizedHost == _normalizeLoopbackHost(configuredHost);

  bool _isOriginExplicitlyAllowed(String originHeader) {
    final _OriginAuthority? requestAuth = _OriginAuthority.tryParse(originHeader);
    if (requestAuth == null || !requestAuth.isHttpOrHttps) {
      return false;
    }
    for (final String allowed in config.allowedOrigins) {
      if (_OriginAuthority.tryParse(allowed) case final _OriginAuthority allowedAuth
          when allowedAuth.isHttpOrHttps && allowedAuth.normalized == requestAuth.normalized) {
        return true;
      }
    }
    return false;
  }

  bool _isSameAuthorityOrigin(String originHeader, String? hostHeader) {
    if (hostHeader == null || hostHeader.isEmpty) {
      return false;
    }
    final _OriginAuthority? originAuth = _OriginAuthority.tryParse(originHeader);
    if (originAuth == null || !originAuth.isHttpOrHttps) {
      return false;
    }
    final _OriginAuthority? hostAuth = _OriginAuthority.tryParse(
      '${originAuth.scheme}://$hostHeader',
    );
    return hostAuth != null &&
        originAuth.matchesHostPort(hostAuth) &&
        _isAllowedNormalizedHost(originAuth.host);
  }
}

// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:isolate';
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
  });

  final WidgetPreviewDtdServices dtdServices;
  final List<String> allowedOrigins;
  final DtdWebSocketConnector dtdWebSocketConnector;
}

class _CachedDdcBundle {
  _CachedDdcBundle({required this.etag, required this.revision, required this.utf8Bytes});

  final String etag;
  final int revision;
  final Uint8List utf8Bytes;
  Future<Uint8List>? _gzipBytesFuture;

  Future<Uint8List> getGzipBytes() =>
      _gzipBytesFuture ??= Isolate.run(() => Uint8List.fromList(gzip.encode(utf8Bytes)));
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
  static const _kDdcBundlePath = '__ddc_bundle.js';
  static const _kDtdWsPath = 'dtd_ws';
  static const _kEmbedFlutterBootstrapPath = '__embed_flutter_bootstrap.js';
  static const _kEmbedMainDartJsPath = '__embed_main.dart.js';
  static const _kEmbedMainModuleBootstrapPath = '__embed_main_module.bootstrap.js';
  static const _kEntrypointExtensionMarker = '/* ENTRYPOINT_EXTENTION_MARKER */';
  static const _kErrorKey = 'error';
  static const _kHtmlContentType = 'text/html; charset=utf-8';
  static const _kIdKey = 'id';
  static const _kJsContentType = 'application/javascript; charset=utf-8';
  static const _kJsonContentType = 'application/json; charset=utf-8';
  static const _kJsonRpcKey = 'jsonrpc';
  static const _kJsonRpcVersion = '2.0';
  static const _kLiveBgStyleTag =
      '<style id="wp-live-bg">html,body{margin:0;background:#121212;color:#e4e4e7}</style>';
  static const _kLivePath = 'live';
  static const _kLiveSlashPath = 'live/';
  static const _kMainModuleBootstrapPath = 'main_module.bootstrap.js';
  static const int _kMaxRpcFrameBytes = 64 * 1024;
  static const _kMessageKey = 'message';
  static const _kMethodKey = 'method';
  static const _kModulesKey = 'modules';
  static const _kNoSniffHeader = 'x-content-type-options';
  static const _kNoSniffValue = 'nosniff';
  static const _kNoStoreHeaders = <String, String>{HttpHeaders.cacheControlHeader: 'no-store'};
  static const _kOriginHeader = 'origin';
  static const _kParamsKey = 'params';
  static const _kPlainContentType = 'text/plain; charset=utf-8';
  static const _kResultKey = 'result';
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

  static const _kJsonRpcParseError = -32700;
  static const _kJsonRpcInvalidRequest = -32600;
  static const _kJsonRpcMethodNotFound = -32601;
  static const _kJsonRpcInvalidParams = -32602;

  static final List<int> _kSourceMappingUrlPrefixBytes = utf8.encode('//# sourceMappingURL=');

  final String Function() basePathProvider;
  final WidgetPreviewLiveConfig config;
  final String configuredHost;
  final bool isWindows;
  final Map<String, String> modules;
  final String Function() renderFlutterBootstrapJs;
  final String Function() renderIndexHtml;
  final WebMemoryFS webMemoryFS;

  final String _serverNonce =
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${Random.secure().nextInt(0x7fffffff).toRadixString(36)}';
  final _activeChannels = <WebSocketChannel>{};
  _CachedDdcBundle? _cachedBundle;
  var _reportedEmbedOpen = false;
  var _reportedLiveOpen = false;

  static const _kBaseSecurityHeaders = <String, String>{
    _kCorpHeader: _kCorpSameSite,
    _kNoSniffHeader: _kNoSniffValue,
  };

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

    final bool isHotReloadModule =
        request.method == 'GET' &&
        request.url.queryParameters.containsKey(_kRevQueryParam) &&
        requestPath.endsWith('.js') &&
        webMemoryFS.files.containsKey(requestPath);
    final bool isProtectedRoute = switch (requestPath) {
      _kEmbedFlutterBootstrapPath ||
      _kEmbedMainDartJsPath ||
      _kEmbedMainModuleBootstrapPath ||
      _kDdcBundlePath ||
      _kApiHotReloadPath ||
      _kApiStatusPath ||
      _kApiSyncPath ||
      _kDtdWsPath => true,
      _ => isHotReloadModule,
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

    if (isHotReloadModule) {
      return _serveHotReloadModule(requestPath);
    }

    return switch ((request.method, requestPath)) {
      ('GET', _kEmbedFlutterBootstrapPath) => _serveEmbedFlutterBootstrapJs(),
      ('GET', _kEmbedMainDartJsPath) => _serveEmbedMainDartJs(),
      ('GET', _kEmbedMainModuleBootstrapPath) => _serveEmbedMainModuleBootstrapJs(),
      ('GET', _kDdcBundlePath) => _serveDdcBundle(request),
      ('GET', _kApiHotReloadPath) => _serveApiHotReload(request),
      ('GET', _kApiStatusPath) => _serveApiStatus(),
      ('POST', _kApiSyncPath) => _serveApiSync(),
      ('GET', _kDtdWsPath) => _serveDtdWebSocket(request),
      _ => shelf.Response.notFound(''),
    };
  }

  /// Pre-builds the concatenated DDC bundle and warms its gzip cache in the
  /// background for the current [WebMemoryFS.revision].
  void prewarmBundle() {
    unawaited(_getOrBuildBundle().getGzipBytes());
  }

  /// Closes all active `/dtd_ws` WebSocket connections.
  Future<void> dispose() async {
    final List<WebSocketChannel> channels = _activeChannels.toList();
    _activeChannels.clear();
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

  shelf.Response _serveEmbedIndexHtml() {
    final String html = renderIndexHtml()
        .replaceAll('flutter_bootstrap.js', _rootRelativePath(_kEmbedFlutterBootstrapPath))
        .replaceAll('main.dart.js', _rootRelativePath(_kEmbedMainDartJsPath))
        .replaceFirst('</head>', '$_kLiveBgStyleTag</head>');
    return shelf.Response.ok(
      html,
      encoding: utf8,
      headers: _securityHeaders(contentType: _kHtmlContentType),
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
    );
  }

  String _buildEmbedModuleRegistrationJs() {
    const registerCall = r'window.$dartLoader.loader.registerScript';
    const tail =
        '''
window.\$dartLoader.loadConfig.loadScriptFn = function(loader) {
  loader.addScriptsToQueue([
    {src: "$_kDdcBundlePath", id: "__ddc_bundle__"}
  ], null);
  loader.loadEnqueuedModules();
};
window.\$dartLoader.loader.nextAttempt();
''';
    return <String>[
      for (final MapEntry(key: name, value: path) in modules.entries)
        '$registerCall(${jsonEncode(<String, String>{'src': '$path.js', 'id': name})});',
      tail,
    ].join('\n');
  }

  _CachedDdcBundle _getOrBuildBundle() {
    final int revision = webMemoryFS.revision;
    final _CachedDdcBundle? existing = _cachedBundle;
    if (existing != null && existing.revision == revision) {
      return existing;
    }
    final builder = BytesBuilder(copy: false)
      ..add(utf8.encode('self.__wpLiveRevision=$revision;\n'));
    var wroteModule = false;
    for (final String path in modules.values) {
      final Uint8List? fileBytes = webMemoryFS.files['$path.js'];
      if (fileBytes == null) {
        continue;
      }
      if (wroteModule) {
        builder.addByte(0x0A);
      }
      builder.add(_stripTrailingSourceMappingUrlBytes(fileBytes));
      wroteModule = true;
    }
    return _cachedBundle = _CachedDdcBundle(
      etag: '"ddc-$_serverNonce-rev-$revision"',
      revision: revision,
      utf8Bytes: builder.takeBytes(),
    );
  }

  static Uint8List _stripTrailingSourceMappingUrlBytes(Uint8List bytes) {
    int end = bytes.length;
    while (end > 0 && _isAsciiWhitespace(bytes[end - 1])) {
      end--;
    }
    var lineStart = end;
    while (lineStart > 0 && bytes[lineStart - 1] != 0x0A) {
      lineStart--;
    }
    if (_startsWithBytes(bytes, lineStart, end, _kSourceMappingUrlPrefixBytes)) {
      var cut = lineStart;
      if (cut > 0 && bytes[cut - 1] == 0x0A) {
        cut--;
      }
      if (cut > 0 && bytes[cut - 1] == 0x0D) {
        cut--;
      }
      return Uint8List.sublistView(bytes, 0, cut);
    }
    return bytes;
  }

  static bool _isAsciiWhitespace(int byte) =>
      byte == 0x0A || byte == 0x0D || byte == 0x20 || byte == 0x09;

  static bool _startsWithBytes(Uint8List bytes, int start, int end, List<int> prefix) {
    if (end - start < prefix.length) {
      return false;
    }
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[start + i] != prefix[i]) {
        return false;
      }
    }
    return true;
  }

  Future<shelf.Response> _serveDdcBundle(shelf.Request request) async {
    final _CachedDdcBundle bundle = _getOrBuildBundle();
    final String? ifNoneMatch = request.headers[HttpHeaders.ifNoneMatchHeader];
    if (_matchesEtag(ifNoneMatch, bundle.etag)) {
      return shelf.Response.notModified(
        headers: _securityHeaders(
          extra: <String, String>{
            HttpHeaders.cacheControlHeader: 'max-age=0, must-revalidate',
            HttpHeaders.etagHeader: bundle.etag,
          },
        ),
      );
    }

    final bool acceptsGzip = _acceptsGzipEncoding(
      request.headers[HttpHeaders.acceptEncodingHeader],
    );
    final Uint8List bodyBytes = acceptsGzip ? await bundle.getGzipBytes() : bundle.utf8Bytes;
    return _jsOkResponse(
      bodyBytes,
      extra: <String, String>{
        HttpHeaders.cacheControlHeader: 'max-age=0, must-revalidate',
        HttpHeaders.etagHeader: bundle.etag,
        HttpHeaders.varyHeader: HttpHeaders.acceptEncodingHeader,
        if (acceptsGzip) HttpHeaders.contentEncodingHeader: 'gzip',
      },
    );
  }

  static bool _acceptsGzipEncoding(String? acceptEncoding) {
    if (acceptEncoding == null || acceptEncoding.isEmpty) {
      return false;
    }
    for (final String part in acceptEncoding.split(',')) {
      final List<String> segments = part.trim().split(';');
      if (segments.isEmpty || segments.first.trim().toLowerCase() != 'gzip') {
        continue;
      }
      var quality = 1.0;
      for (final String param in segments.skip(1)) {
        final List<String> kv = param.trim().split('=');
        if (kv.length == 2 && kv.first.trim().toLowerCase() == 'q') {
          quality = double.tryParse(kv[1].trim()) ?? 1.0;
        }
      }
      return quality > 0;
    }
    return false;
  }

  static bool _matchesEtag(String? ifNoneMatch, String etag) =>
      ifNoneMatch != null &&
      ifNoneMatch.isNotEmpty &&
      (ifNoneMatch == etag || ifNoneMatch.split(',').any((String part) => part.trim() == etag));

  shelf.Response _serveHotReloadModule(String requestPath) {
    final Uint8List? fileBytes = webMemoryFS.files[requestPath];
    if (fileBytes == null) {
      return shelf.Response.notFound('');
    }
    return _jsOkResponse(_stripTrailingSourceMappingUrlBytes(fileBytes), extra: _kNoStoreHeaders);
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
    final int currentRevision = webMemoryFS.revision;
    final changedModules = <Map<String, Object?>>[];
    if (since < currentRevision) {
      for (final MapEntry(key: id, value: path) in modules.entries) {
        final fileName = '$path.js';
        final int? moduleRev = webMemoryFS.moduleRevisions[fileName];
        if (moduleRev == null || moduleRev <= since || !webMemoryFS.files.containsKey(fileName)) {
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
          'src': '$fileName?$_kRevQueryParam=$moduleRev',
          'id': id,
          'libraries': libraries,
        });
      }
    }
    return _jsonResponse(<String, Object?>{
      _kRevisionKey: currentRevision,
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
    final shelf.Handler wsHandler = webSocketHandler((WebSocketChannel clientChannel, String? _) {
      _bridgeDtdWebSocket(clientChannel, dtdUri);
    });
    return wsHandler(request);
  }

  void _bridgeDtdWebSocket(WebSocketChannel clientChannel, Uri dtdUri) {
    final WebSocketChannel upstreamChannel = config.dtdWebSocketConnector(dtdUri);
    _activeChannels
      ..add(clientChannel)
      ..add(upstreamChannel);

    var closed = false;
    Future<void> closeBoth() async {
      if (closed) {
        return;
      }
      closed = true;
      _activeChannels
        ..remove(clientChannel)
        ..remove(upstreamChannel);
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
        final Object? fileUri = params?[WidgetPreviewDtdServices.kFileUri];
        cleanParams = <String, Object?>{
          WidgetPreviewDtdServices.kSync: false,
          if (fileUri is String && fileUri.isNotEmpty) WidgetPreviewDtdServices.kFileUri: fileUri,
        };
      } else if (method ==
          '${dtdServices.widgetPreviewScaffoldService}.${WidgetPreviewDtdServices.kGetPreviews}') {
        final Object? fileUri = params?[WidgetPreviewDtdServices.kFileUri];
        cleanParams = <String, Object?>{
          if (fileUri is String && fileUri.isNotEmpty) WidgetPreviewDtdServices.kFileUri: fileUri,
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

  static ({String scheme, String host, int port})? _parseOriginAuthority(String raw) {
    final Uri? uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return null;
    }
    final String scheme = uri.scheme.toLowerCase();
    final int port = uri.hasPort ? uri.port : (scheme == 'https' ? 443 : 80);
    return (scheme: scheme, host: _normalizeLoopbackHost(uri.host), port: port);
  }

  bool _isHostMatchingAllowedOrigin(String hostHeader) {
    for (final String allowed in config.allowedOrigins) {
      final ({String host, int port, String scheme})? allowedAuth = _parseOriginAuthority(allowed);
      if (allowedAuth == null) {
        continue;
      }
      final ({String host, int port, String scheme})? hostAuth = _parseOriginAuthority(
        '${allowedAuth.scheme}://$hostHeader',
      );
      if (hostAuth != null &&
          hostAuth.host == allowedAuth.host &&
          hostAuth.port == allowedAuth.port) {
        return true;
      }
    }
    return false;
  }

  bool _isAllowedHostHeader(String hostHeader) {
    final ({String host, int port, String scheme})? auth = _parseOriginAuthority(
      'http://$hostHeader',
    );
    return auth != null && _isAllowedNormalizedHost(auth.host);
  }

  bool _isAllowedNormalizedHost(String normalizedHost) =>
      normalizedHost == 'localhost' || normalizedHost == _normalizeLoopbackHost(configuredHost);

  bool _isOriginExplicitlyAllowed(String originHeader) {
    final String normalizedOrigin = _normalizeOriginString(originHeader);
    return config.allowedOrigins.any(
      (String allowed) => _normalizeOriginString(allowed) == normalizedOrigin,
    );
  }

  static String _normalizeOriginString(String origin) {
    final ({String host, int port, String scheme})? auth = _parseOriginAuthority(origin);
    return auth == null ? origin.trim() : '${auth.scheme}://${auth.host}:${auth.port}';
  }

  bool _isSameAuthorityOrigin(String originHeader, String? hostHeader) {
    if (hostHeader == null || hostHeader.isEmpty) {
      return false;
    }
    final ({String host, int port, String scheme})? originAuth = _parseOriginAuthority(
      originHeader,
    );
    if (originAuth == null || (originAuth.scheme != 'http' && originAuth.scheme != 'https')) {
      return false;
    }
    final ({String host, int port, String scheme})? hostAuth = _parseOriginAuthority(
      '${originAuth.scheme}://$hostHeader',
    );
    return hostAuth != null &&
        originAuth.host == hostAuth.host &&
        _isAllowedNormalizedHost(originAuth.host) &&
        originAuth.port == hostAuth.port;
  }

  static String _normalizeLoopbackHost(String host) => switch (host.toLowerCase()) {
    'localhost' || '127.0.0.1' || '::1' || '[::1]' => 'localhost',
    final String lower => lower,
  };
}

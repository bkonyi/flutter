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
import '../widget_preview/dtd_services.dart';
import '../widget_preview/dtd_types.dart';
import 'web_server_utilities.dart';
import 'widget_preview_live_shell.dart';

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
/// `/__api/*` HTTP endpoints, and the scoped read-only `/dtd_ws` JSON-RPC bridge.
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

  static const _kApiPreviewsPath = '__api/previews';
  static const _kApiStatusPath = '__api/status';
  static const _kApiSyncPath = '__api/sync';
  static const _kCorpHeader = 'cross-origin-resource-policy';
  static const _kCorpSameSite = 'same-site';
  static const _kDdcBundlePath = '__ddc_bundle.js';
  static const _kDtdWsPath = 'dtd_ws';
  static const _kEmbedFlutterBootstrapPath = '__embed_flutter_bootstrap.js';
  static const _kEmbedMainDartJsPath = '__embed_main.dart.js';
  static const _kEmbedMainModuleBootstrapPath = '__embed_main_module.bootstrap.js';
  static const _kLivePath = 'live';
  static const _kLiveSlashPath = 'live/';
  static const _kMainModuleBootstrapPath = 'main_module.bootstrap.js';
  static const _kNoSniffHeader = 'x-content-type-options';
  static const _kNoSniffValue = 'nosniff';
  static const _kOriginHeader = 'origin';
  static const _kSecFetchSiteHeader = 'sec-fetch-site';
  static const _kSecFetchSiteNone = 'none';
  static const _kSecFetchSiteSameOrigin = 'same-origin';
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
      return _serveEmbedIndexHtml();
    }

    if (request.method == 'GET' && (requestPath == _kLivePath || requestPath == _kLiveSlashPath)) {
      return _serveLiveShell();
    }

    final bool isProtectedRoute = switch (requestPath) {
      _kEmbedFlutterBootstrapPath ||
      _kEmbedMainDartJsPath ||
      _kEmbedMainModuleBootstrapPath ||
      _kDdcBundlePath ||
      _kApiStatusPath ||
      _kApiPreviewsPath ||
      _kApiSyncPath ||
      _kDtdWsPath => true,
      _ => false,
    };
    if (!isProtectedRoute) {
      return shelf.Response.notFound('');
    }

    if (!_isRequestAuthorized(request)) {
      return shelf.Response.forbidden(
        'Cross-origin request rejected.',
        headers: _securityHeaders(contentType: 'text/plain; charset=utf-8'),
      );
    }

    return switch ((request.method, requestPath)) {
      ('GET', _kEmbedFlutterBootstrapPath) => _serveEmbedFlutterBootstrapJs(),
      ('GET', _kEmbedMainDartJsPath) => _serveEmbedMainDartJs(),
      ('GET', _kEmbedMainModuleBootstrapPath) => _serveEmbedMainModuleBootstrapJs(),
      ('GET', _kDdcBundlePath) => _serveDdcBundle(request),
      ('GET', _kApiStatusPath) => _serveApiStatus(),
      ('GET', _kApiPreviewsPath) => _serveApiPreviews(request),
      ('POST', _kApiSyncPath) => _serveApiSync(),
      ('GET', _kDtdWsPath) => _serveDtdWebSocket(request),
      _ => shelf.Response.notFound(''),
    };
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
  }) {
    return <String, String>{
      ..._kBaseSecurityHeaders,
      HttpHeaders.contentTypeHeader: ?contentType,
      ...extra,
    };
  }

  shelf.Response _serveEmbedIndexHtml() {
    final String html = renderIndexHtml()
        .replaceAll('flutter_bootstrap.js', _kEmbedFlutterBootstrapPath)
        .replaceAll('main.dart.js', _kEmbedMainDartJsPath);
    return shelf.Response.ok(
      html,
      encoding: utf8,
      headers: _securityHeaders(contentType: 'text/html; charset=utf-8'),
    );
  }

  shelf.Response _serveLiveShell() {
    final WidgetPreviewDtdServices dtdServices = config.dtdServices;
    final String projectRoot = dtdServices.projectRootPath ?? dtdServices.project.directory.path;
    return shelf.Response.ok(
      buildWidgetPreviewLiveShellHtml(projectRoot: projectRoot),
      encoding: utf8,
      headers: _securityHeaders(contentType: 'text/html; charset=utf-8'),
    );
  }

  shelf.Response _serveEmbedFlutterBootstrapJs() {
    final String js = renderFlutterBootstrapJs().replaceAll('main.dart.js', _kEmbedMainDartJsPath);
    return shelf.Response.ok(
      js,
      encoding: utf8,
      headers: _securityHeaders(contentType: 'application/javascript; charset=utf-8'),
    );
  }

  shelf.Response _serveEmbedMainDartJs() {
    final String js = generateDDCLibraryBundleBootstrapScript(
      ddcModuleLoaderUrl: 'ddc_module_loader.js',
      mapperUrl: 'stack_trace_mapper.js',
      generateLoadingIndicator: false,
      isWindows: isWindows,
    ).replaceAll('main_module.bootstrap.js', _kEmbedMainModuleBootstrapPath);
    return shelf.Response.ok(
      js,
      encoding: utf8,
      headers: _securityHeaders(contentType: 'application/javascript; charset=utf-8'),
    );
  }

  shelf.Response _serveEmbedMainModuleBootstrapJs() {
    final Uint8List? storedBootstrap = webMemoryFS.files[_kMainModuleBootstrapPath];
    if (storedBootstrap == null) {
      return shelf.Response.notFound(
        '$_kMainModuleBootstrapPath has not been compiled yet.',
        headers: _securityHeaders(contentType: 'text/plain; charset=utf-8'),
      );
    }
    final String bootstrap = utf8
        .decode(storedBootstrap)
        .replaceFirst('/* ENTRYPOINT_EXTENTION_MARKER */', _buildEmbedModuleRegistrationJs());
    return shelf.Response.ok(
      bootstrap,
      encoding: utf8,
      headers: _securityHeaders(contentType: 'application/javascript; charset=utf-8'),
    );
  }

  String _buildEmbedModuleRegistrationJs() {
    final buffer = StringBuffer();
    for (final MapEntry(key: name, value: path) in modules.entries) {
      final String scriptJson = jsonEncode(<String, String>{'src': '$path.js', 'id': name});
      buffer.writeln('window.\$dartLoader.loader.registerScript($scriptJson);');
    }
    buffer.writeln('''
window.\$dartLoader.loadConfig.loadScriptFn = function(loader) {
  loader.addScriptsToQueue([
    {src: "$_kDdcBundlePath", id: "__ddc_bundle__"}
  ], null);
  loader.loadEnqueuedModules();
};
window.\$dartLoader.loader.nextAttempt();''');
    return buffer.toString();
  }

  _CachedDdcBundle _getOrBuildBundle() {
    final int revision = webMemoryFS.revision;
    final _CachedDdcBundle? existing = _cachedBundle;
    if (existing != null && existing.revision == revision) {
      return existing;
    }
    final builder = BytesBuilder(copy: false);
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
    final Uint8List utf8Bytes = builder.takeBytes();
    final built = _CachedDdcBundle(
      etag: '"ddc-$_serverNonce-rev-$revision"',
      revision: revision,
      utf8Bytes: utf8Bytes,
    );
    _cachedBundle = built;
    return built;
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
    return shelf.Response.ok(
      bodyBytes,
      headers: _securityHeaders(
        contentType: 'application/javascript; charset=utf-8',
        extra: <String, String>{
          HttpHeaders.cacheControlHeader: 'max-age=0, must-revalidate',
          HttpHeaders.etagHeader: bundle.etag,
          HttpHeaders.varyHeader: HttpHeaders.acceptEncodingHeader,
          if (acceptsGzip) HttpHeaders.contentEncodingHeader: 'gzip',
        },
      ),
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

  static bool _matchesEtag(String? ifNoneMatch, String etag) {
    if (ifNoneMatch == null || ifNoneMatch.isEmpty) {
      return false;
    }
    if (ifNoneMatch == etag) {
      return true;
    }
    return ifNoneMatch.split(',').any((String part) => part.trim() == etag);
  }

  shelf.Response _serveApiStatus() {
    final WidgetPreviewDtdServices dtdServices = config.dtdServices;
    final payload = <String, Object?>{
      'status': 'ready',
      'projectRoot': dtdServices.projectRootPath ?? dtdServices.project.directory.path,
      'previewService': dtdServices.widgetPreviewService,
      'scaffoldService': dtdServices.widgetPreviewScaffoldService,
      'scaffoldStream': dtdServices.widgetPreviewScaffoldStream,
      'scaffoldConnected': dtdServices.scaffoldConnected,
    };
    return shelf.Response.ok(
      jsonEncode(payload),
      encoding: utf8,
      headers: _securityHeaders(
        contentType: 'application/json; charset=utf-8',
        extra: const <String, String>{HttpHeaders.cacheControlHeader: 'no-store'},
      ),
    );
  }

  shelf.Response _jsonErrorResponse(int statusCode, String message) {
    return shelf.Response(
      statusCode,
      body: jsonEncode(<String, Object?>{'error': message}),
      encoding: utf8,
      headers: _securityHeaders(contentType: 'application/json; charset=utf-8'),
    );
  }

  Future<shelf.Response> _serveApiPreviews(shelf.Request request) async {
    final String? fileUri = request.url.queryParameters['fileUri'];
    try {
      final Map<String, Object?> payload = await config.dtdServices.listPreviewsJson(
        fileUri: fileUri,
      );
      return shelf.Response.ok(
        jsonEncode(payload),
        encoding: utf8,
        headers: _securityHeaders(
          contentType: 'application/json; charset=utf-8',
          extra: const <String, String>{HttpHeaders.cacheControlHeader: 'no-store'},
        ),
      );
    } on RpcException catch (e) {
      return _jsonErrorResponse(HttpStatus.serviceUnavailable, e.message);
    }
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
      return shelf.Response.ok(
        jsonEncode(response.toJson()),
        encoding: utf8,
        headers: _securityHeaders(
          contentType: 'application/json; charset=utf-8',
          extra: const <String, String>{HttpHeaders.cacheControlHeader: 'no-store'},
        ),
      );
    } on RpcException catch (e) {
      return _jsonErrorResponse(HttpStatus.serviceUnavailable, e.message);
    }
  }

  FutureOr<shelf.Response> _serveDtdWebSocket(shelf.Request request) {
    final Uri? dtdUri = config.dtdServices.dtdUri;
    if (dtdUri == null) {
      return shelf.Response(
        HttpStatus.serviceUnavailable,
        body: 'DTD server URI is not available.',
        headers: _securityHeaders(contentType: 'text/plain; charset=utf-8'),
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
    if (message is! String) {
      _sendRpcError(
        clientChannel,
        id: null,
        code: _kJsonRpcInvalidRequest,
        message: 'JSON-RPC requests must be text frames.',
      );
      return null;
    }

    final Object? decoded;
    try {
      decoded = json.decode(message);
    } on FormatException {
      _sendRpcError(clientChannel, id: null, code: _kJsonRpcParseError, message: 'Parse error.');
      return null;
    }

    if (decoded is! Map<String, Object?>) {
      _sendRpcError(
        clientChannel,
        id: null,
        code: _kJsonRpcInvalidRequest,
        message: 'Invalid Request.',
      );
      return null;
    }

    final Object? rawId = decoded['id'];
    final Object? rpcId = (rawId is String || rawId is int) ? rawId : null;
    if (decoded case {'jsonrpc': '2.0', 'method': final String method, 'id': final Object _}
        when rpcId != null) {
      final Object? rawParams = decoded['params'];
      if (rawParams is! Map<String, Object?>?) {
        _sendRpcError(
          clientChannel,
          id: rpcId,
          code: _kJsonRpcInvalidParams,
          message: 'Invalid params.',
        );
        return null;
      }
      final Map<String, Object?>? params = rawParams;
      final WidgetPreviewDtdServices dtdServices = config.dtdServices;

      Map<String, Object?>? cleanParams;
      if (method == _kStreamListenMethod || method == _kStreamCancelMethod) {
        if (params?[_kStreamIdKey] != dtdServices.widgetPreviewScaffoldStream) {
          _sendRpcError(
            clientChannel,
            id: rpcId,
            code: _kJsonRpcMethodNotFound,
            message: 'Stream "$method" is not allowed on this endpoint.',
          );
          return null;
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
        _sendRpcError(
          clientChannel,
          id: rpcId,
          code: _kJsonRpcMethodNotFound,
          message: 'Method "$method" is not allowed.',
        );
        return null;
      }

      return jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': rpcId,
        'method': method,
        'params': cleanParams,
      });
    }

    _sendRpcError(
      clientChannel,
      id: rpcId,
      code: _kJsonRpcInvalidRequest,
      message: 'Invalid Request.',
    );
    return null;
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
    channel.sink.add(jsonEncode(<String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': result}));
  }

  static void _sendRpcError(
    WebSocketChannel channel, {
    required Object? id,
    required int code,
    required String message,
  }) {
    channel.sink.add(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, Object?>{'code': code, 'message': message},
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
      if (hostHeader == null || hostHeader.isEmpty) {
        return true;
      }
      return _isAllowedHostHeader(hostHeader) || _isHostMatchingAllowedOrigin(hostHeader);
    }

    if (hostHeader != null && hostHeader.isNotEmpty && !_isAllowedHostHeader(hostHeader)) {
      return false;
    }

    return _isSameAuthorityOrigin(originHeader, hostHeader);
  }

  bool _isHostMatchingAllowedOrigin(String hostHeader) {
    for (final String allowed in config.allowedOrigins) {
      final Uri? allowedUri = Uri.tryParse(allowed.trim());
      if (allowedUri == null || !allowedUri.hasScheme || allowedUri.host.isEmpty) {
        continue;
      }
      final Uri? hostUri = Uri.tryParse('${allowedUri.scheme}://$hostHeader');
      if (hostUri == null || hostUri.host.isEmpty) {
        continue;
      }
      if (_normalizeLoopbackHost(hostUri.host) == _normalizeLoopbackHost(allowedUri.host) &&
          _resolveUriPort(hostUri) == _resolveUriPort(allowedUri)) {
        return true;
      }
    }
    return false;
  }

  bool _isAllowedHostHeader(String hostHeader) {
    final Uri? hostUri = Uri.tryParse('http://$hostHeader');
    if (hostUri == null || hostUri.host.isEmpty) {
      return false;
    }
    return _isAllowedNormalizedHost(_normalizeLoopbackHost(hostUri.host));
  }

  bool _isAllowedNormalizedHost(String normalizedHost) {
    if (normalizedHost == 'localhost') {
      return true;
    }
    return normalizedHost == _normalizeLoopbackHost(configuredHost);
  }

  bool _isOriginExplicitlyAllowed(String originHeader) {
    final String normalizedOrigin = _normalizeOriginString(originHeader);
    for (final String allowed in config.allowedOrigins) {
      if (_normalizeOriginString(allowed) == normalizedOrigin) {
        return true;
      }
    }
    return false;
  }

  static String _normalizeOriginString(String origin) {
    final Uri? uri = Uri.tryParse(origin.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return origin.trim();
    }
    final int port = _resolveUriPort(uri);
    return '${uri.scheme.toLowerCase()}://${_normalizeLoopbackHost(uri.host)}:$port';
  }

  bool _isSameAuthorityOrigin(String originHeader, String? hostHeader) {
    if (hostHeader == null || hostHeader.isEmpty) {
      return false;
    }
    final Uri? originUri = Uri.tryParse(originHeader);
    if (originUri == null ||
        (originUri.scheme != 'http' && originUri.scheme != 'https') ||
        originUri.host.isEmpty) {
      return false;
    }
    final Uri? hostUri = Uri.tryParse('${originUri.scheme}://$hostHeader');
    if (hostUri == null || hostUri.host.isEmpty) {
      return false;
    }
    final String originHost = _normalizeLoopbackHost(originUri.host);
    final String requestHost = _normalizeLoopbackHost(hostUri.host);
    return originHost == requestHost &&
        _isAllowedNormalizedHost(originHost) &&
        _resolveUriPort(originUri) == _resolveUriPort(hostUri);
  }

  static String _normalizeLoopbackHost(String host) {
    final String lower = host.toLowerCase();
    return switch (lower) {
      'localhost' || '127.0.0.1' || '::1' || '[::1]' => 'localhost',
      _ => lower,
    };
  }

  static int _resolveUriPort(Uri uri) {
    if (uri.hasPort) {
      return uri.port;
    }
    return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
  }
}

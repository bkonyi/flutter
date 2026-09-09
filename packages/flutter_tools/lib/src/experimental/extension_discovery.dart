// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:isolate';

import 'package:flutter_tools_extension/flutter_tools_extension.dart';
import 'package:json_rpc_2/json_rpc_2.dart' as json_rpc;
import 'package:meta/meta.dart';
import 'package:stream_channel/isolate_channel.dart';

import '../base/logger.dart';

const String _kGetCapabilitiesMethod = 'extension.getCapabilities';

/// Typedef for an extension isolate entrypoint function.
typedef ExtensionEntryPoint = void Function(SendPort sendPort);

/// Signature for spawning an extension isolate from an entrypoint URI.
typedef ExtensionUriSpawner =
    Future<ExtensionConnection> Function(
      Uri entrypointUri, {
      required Logger logger,
      List<String> args,
      Uri? packageConfigUri,
      Duration timeout,
    });

/// Represents an active host-side connection to a running tool extension isolate.
class ExtensionConnection {
  ExtensionConnection._({
    required this.capabilities,
    required Isolate? isolate,
    required Logger logger,
    required json_rpc.Peer peer,
    RawReceivePort? errorPort,
    RawReceivePort? exitPort,
  }) : _isolate = isolate,
       _peer = peer,
       _logger = logger,
       _errorPort = errorPort,
       _exitPort = exitPort;

  /// Creates an [ExtensionConnection] with custom or mock dependencies for testing.
  @visibleForTesting
  factory ExtensionConnection.custom({
    required ToolExtensionCapabilities capabilities,
    required json_rpc.Peer peer,
    required Logger logger,
    RawReceivePort? errorPort,
    RawReceivePort? exitPort,
    Isolate? isolate,
  }) => ExtensionConnection._(
    capabilities: capabilities,
    errorPort: errorPort,
    exitPort: exitPort,
    isolate: isolate,
    logger: logger,
    peer: peer,
  );

  /// Default timeout for completing the initial extension handshake.
  static const Duration defaultHandshakeTimeout = Duration(seconds: 2);

  Isolate? _isolate;
  final json_rpc.Peer _peer;
  final Logger _logger;
  RawReceivePort? _errorPort;
  RawReceivePort? _exitPort;

  /// The capabilities and supported service namespaces of the extension.
  final ToolExtensionCapabilities capabilities;

  bool _isDisposed = false;

  /// Sends an RPC request to the extension isolate.
  Future<Object?> sendRequest(
    String method, [
    Object? params,
    Duration timeout = const Duration(seconds: 5),
  ]) async {
    if (_isDisposed) {
      throw StateError('ExtensionConnection has been disposed.');
    }
    _logger.printTrace('ExtensionConnection sending RPC request "$method"...');
    try {
      final Object? result = await _peer.sendRequest(method, params).timeout(timeout);
      _logger.printTrace('ExtensionConnection received response for RPC request "$method".');
      return result;
    } on Object catch (error) {
      _logger.printTrace('ExtensionConnection RPC request "$method" failed with error: $error');
      rethrow;
    }
  }

  /// Spawns an extension isolate from [entryPoint] and completes handshake.
  static Future<ExtensionConnection> spawn(
    ExtensionEntryPoint entryPoint, {
    required Logger logger,
    Duration timeout = defaultHandshakeTimeout,
  }) {
    logger.printTrace('ExtensionConnection spawning extension isolate...');
    return _spawnAndHandshake(
      isolateFactory: (SendPort sendPort, SendPort onError, SendPort onExit) {
        return Isolate.spawn(entryPoint, sendPort, onError: onError, onExit: onExit);
      },
      logger: logger,
      timeout: timeout,
    );
  }

  /// Spawns an extension isolate from [entrypointUri] using [Isolate.spawnUri] and completes handshake.
  static Future<ExtensionConnection> spawnUri(
    Uri entrypointUri, {
    required Logger logger,
    List<String> args = const <String>[],
    Uri? packageConfigUri,
    Duration timeout = defaultHandshakeTimeout,
  }) {
    logger.printTrace('ExtensionConnection spawning extension isolate from $entrypointUri...');
    return _spawnAndHandshake(
      isolateFactory: (SendPort sendPort, SendPort onError, SendPort onExit) {
        return Isolate.spawnUri(
          entrypointUri,
          args,
          sendPort,
          onError: onError,
          onExit: onExit,
          packageConfig: packageConfigUri,
        );
      },
      logger: logger,
      timeout: timeout,
      targetDescription: entrypointUri.toString(),
    );
  }

  static Future<ExtensionConnection> _spawnAndHandshake({
    required Future<Isolate> Function(SendPort sendPort, SendPort onError, SendPort onExit)
    isolateFactory,
    required Logger logger,
    required Duration timeout,
    String? targetDescription,
  }) async {
    final receivePort = ReceivePort();
    final errorPort = RawReceivePort();
    final exitPort = RawReceivePort();
    final errorCompleter = Completer<Never>();

    errorPort.handler = (Object? error) {
      if (!errorCompleter.isCompleted) {
        if (error case [final Object? err, ...]) {
          errorCompleter.completeError(StateError('Extension isolate error: $err'));
        } else {
          errorCompleter.completeError(StateError('Extension isolate error: $error'));
        }
      }
    };

    exitPort.handler = (Object? _) {
      if (!errorCompleter.isCompleted) {
        errorCompleter.completeError(
          StateError('Extension isolate exited unexpectedly before handshake completed.'),
        );
      }
    };

    Isolate? isolate;
    try {
      isolate = await isolateFactory(receivePort.sendPort, errorPort.sendPort, exitPort.sendPort);
      return await _completeHandshake(
        errorCompleter: errorCompleter,
        errorPort: errorPort,
        exitPort: exitPort,
        isolate: isolate,
        logger: logger,
        receivePort: receivePort,
        timeout: timeout,
      );
    } on TimeoutException {
      logger.printTrace(
        'ExtensionConnection handshake timed out${targetDescription != null ? ' for $targetDescription' : ''}.',
      );
      receivePort.close();
      errorPort.close();
      exitPort.close();
      isolate?.kill(priority: Isolate.immediate);
      throw TimeoutException(
        'Handshake with tool extension isolate timed out${targetDescription != null ? ': $targetDescription' : '.'}',
      );
    } on Object catch (error) {
      logger.printTrace(
        'ExtensionConnection spawn failed${targetDescription != null ? ' for $targetDescription' : ''}: $error',
      );
      receivePort.close();
      errorPort.close();
      exitPort.close();
      isolate?.kill(priority: Isolate.immediate);
      rethrow;
    }
  }

  static Future<ExtensionConnection> _completeHandshake({
    required Completer<Never> errorCompleter,
    required RawReceivePort errorPort,
    required RawReceivePort exitPort,
    required Isolate? isolate,
    required Logger logger,
    required ReceivePort receivePort,
    required Duration timeout,
  }) async {
    logger.printTrace('ExtensionConnection isolate spawned; connecting IsolateChannel...');
    final channel = IsolateChannel<Object?>.connectReceive(receivePort);
    final peer = json_rpc.Peer.withoutJson(channel);

    unawaited(peer.listen());

    logger.printTrace('ExtensionConnection querying $_kGetCapabilitiesMethod...');
    final Object? responseObj = await Future.any<Object?>([
      peer.sendRequest(_kGetCapabilitiesMethod),
      errorCompleter.future,
    ]).timeout(timeout);
    if (responseObj is! Map<String, Object?>) {
      throw StateError(
        'Extension handshake failed: $_kGetCapabilitiesMethod did not return a Map.',
      );
    }
    final capabilities = ToolExtensionCapabilities.fromJson(responseObj);
    logger.printTrace(
      'ExtensionConnection handshake complete. Capabilities: ${capabilities.services}',
    );

    errorPort.handler = (Object? error) {
      logger.printTrace('Extension isolate runtime error: $error');
    };
    exitPort.handler = (Object? _) {
      logger.printTrace('Extension isolate exited.');
    };

    return ExtensionConnection._(
      capabilities: capabilities,
      errorPort: errorPort,
      exitPort: exitPort,
      isolate: isolate,
      logger: logger,
      peer: peer,
    );
  }

  /// Disposes the extension isolate connection.
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _logger.printTrace('ExtensionConnection disposing isolate connection.');
    _errorPort?.close();
    _errorPort = null;
    _exitPort?.close();
    _exitPort = null;
    try {
      await _peer.close();
    } on Object catch (error) {
      _logger.printTrace('Error closing extension connection peer: $error');
    } finally {
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
    }
  }
}

/// Discovers and manages active tool extension isolate connections.
class ExtensionDiscovery {
  /// Creates an [ExtensionDiscovery] instance with required [logger].
  ExtensionDiscovery({required Logger logger}) : _logger = logger;

  final List<ExtensionConnection> _connections = <ExtensionConnection>[];
  final Logger _logger;

  /// Active extension connections.
  List<ExtensionConnection> get connections => List<ExtensionConnection>.unmodifiable(_connections);

  /// Registers an active [connection].
  void registerConnection(ExtensionConnection connection) {
    _logger.printTrace('ExtensionDiscovery registering active connection.');
    _connections.add(connection);
  }

  /// Registers multiple active [connections].
  void registerConnections(Iterable<ExtensionConnection> connections) {
    _logger.printTrace('ExtensionDiscovery registering ${connections.length} connection(s).');
    _connections.addAll(connections);
  }

  /// Disposes all registered extension isolate connections.
  Future<void> dispose() async {
    _logger.printTrace('ExtensionDiscovery disposing all registered connections.');
    for (final ExtensionConnection connection in _connections) {
      await connection.dispose();
    }
    _connections.clear();
  }
}

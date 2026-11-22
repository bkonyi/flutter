// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import '../base/io.dart';
import '../base/logger.dart';
import '../base/terminal.dart';
import '../convert.dart';

/// A custom logger for the widget-preview commands that disables non-event output to stdio when
/// machine mode is enabled.
final class WidgetPreviewMachineAwareLogger extends DelegatingLogger {
  WidgetPreviewMachineAwareLogger(
    super.delegate, {
    required this.machine,
    required this._stdio,
    required this.verbose,
  });

  /// Event suffix emitted as soon as `flutter widget-preview start` begins.
  static const kInitializingEvent = 'initializing';

  /// Event suffix emitted once the widget previewer web server and DTD services
  /// are ready.
  static const kStartedEvent = 'started';

  /// JSON key carrying the Flutter tool process ID in [kInitializingEvent].
  static const kPidKey = 'pid';

  /// JSON key carrying the web preview HTTP URL in [kStartedEvent].
  static const kUrlKey = 'url';

  /// JSON key carrying the DTD WebSocket URI in [kStartedEvent].
  static const kDtdUriKey = 'dtdUri';

  /// JSON key carrying the registered tool DTD service name in [kStartedEvent].
  static const kPreviewServiceKey = 'previewService';

  /// JSON key carrying the registered scaffold DTD service name in
  /// [kStartedEvent].
  static const kScaffoldServiceKey = 'scaffoldService';

  /// JSON key carrying the resolved project root path in [kStartedEvent].
  static const kProjectRootKey = 'projectRoot';

  static const _kEventKey = 'event';
  static const _kEventPrefix = 'widget_preview.';
  static const _kLevelError = 'error';
  static const _kLevelKey = 'level';
  static const _kLevelStatus = 'status';
  static const _kLevelTrace = 'trace';
  static const _kLevelWarning = 'warning';
  static const _kLogMessageEvent = 'logMessage';
  static const _kMessageKey = 'message';
  static const _kParamsKey = 'params';
  static const _kStackTraceKey = 'stackTrace';

  /// Whether `--machine` JSON event output is enabled.
  final bool machine;

  /// Whether verbose trace logging is enabled.
  final bool verbose;
  final Stdio _stdio;

  void _sendLogMessage(String level, String message, {StackTrace? stackTrace}) {
    sendEvent(_kLogMessageEvent, <String, Object?>{
      _kLevelKey: level,
      _kMessageKey: message,
      _kStackTraceKey: ?stackTrace?.toString(),
    });
  }

  @override
  void printError(
    String message, {
    StackTrace? stackTrace,
    bool? emphasis,
    TerminalColor? color,
    int? indent,
    int? hangingIndent,
    bool? wrap,
  }) {
    if (machine) {
      _sendLogMessage(_kLevelError, message, stackTrace: stackTrace);
      return;
    }
    super.printError(
      message,
      stackTrace: stackTrace,
      emphasis: emphasis,
      color: color,
      indent: indent,
      hangingIndent: hangingIndent,
      wrap: wrap,
    );
  }

  @override
  void printWarning(
    String message, {
    bool? emphasis,
    TerminalColor? color,
    int? indent,
    int? hangingIndent,
    bool? wrap,
    bool fatal = true,
  }) {
    if (machine) {
      _sendLogMessage(_kLevelWarning, message);
      return;
    }
    super.printWarning(
      message,
      emphasis: emphasis,
      color: color,
      indent: indent,
      hangingIndent: hangingIndent,
      wrap: wrap,
      fatal: fatal,
    );
  }

  @override
  void printStatus(
    String message, {
    bool? emphasis,
    TerminalColor? color,
    bool? newline,
    int? indent,
    int? hangingIndent,
    bool? wrap,
  }) {
    if (machine) {
      _sendLogMessage(_kLevelStatus, message);
      return;
    }
    super.printStatus(
      message,
      emphasis: emphasis,
      color: color,
      newline: newline,
      indent: indent,
      hangingIndent: hangingIndent,
      wrap: wrap,
    );
  }

  @override
  void printBox(String message, {String? title}) {
    if (!machine) {
      super.printBox(message, title: title);
    }
  }

  @override
  void printTrace(String message) {
    if (!verbose) {
      return;
    }
    if (machine) {
      _sendLogMessage(_kLevelTrace, message);
    } else {
      super.printTrace(message);
    }
  }

  /// Notifies tooling that the widget previewer is initializing.
  void sendInitializingEvent() {
    sendEvent(kInitializingEvent, <String, Object?>{kPidKey: pid});
  }

  /// Notifies tooling that the widget previewer has started and is being
  /// served at [applicationUrl].
  void sendStartedEvent({
    required Uri applicationUrl,
    Uri? dtdUri,
    String? previewService,
    String? projectRoot,
    String? scaffoldService,
  }) {
    sendEvent(kStartedEvent, <String, Object?>{
      kUrlKey: applicationUrl.toString(),
      kDtdUriKey: ?dtdUri?.toString(),
      kPreviewServiceKey: ?previewService,
      kScaffoldServiceKey: ?scaffoldService,
      kProjectRootKey: ?projectRoot,
    });
  }

  @override
  void sendEvent(String name, [Map<String, Object?>? args]) {
    if (!machine) {
      return;
    }
    // Don't call super.printStatus as it will result in a prefix being printed when --verbose is
    // provided.
    _stdio.stdout.writeln(
      json.encode(<Map<String, Object?>>[
        <String, Object?>{_kEventKey: '$_kEventPrefix$name', _kParamsKey: ?args},
      ]),
    );
  }

  @override
  Status startProgress(
    String message, {
    String? progressId,
    int progressIndicatorPadding = kDefaultStatusPadding,
  }) {
    if (machine) {
      printStatus(message);
      return SilentStatus(stopwatch: Stopwatch());
    }
    return super.startProgress(
      message,
      progressId: progressId,
      progressIndicatorPadding: progressIndicatorPadding,
    );
  }

  @override
  Status startSpinner({
    VoidCallback? onFinish,
    Duration? timeout,
    SlowWarningCallback? slowWarningCallback,
    TerminalColor? warningColor,
  }) {
    if (machine) {
      return SilentStatus(stopwatch: Stopwatch());
    }
    return super.startSpinner(
      onFinish: onFinish,
      timeout: timeout,
      slowWarningCallback: slowWarningCallback,
      warningColor: warningColor,
    );
  }
}

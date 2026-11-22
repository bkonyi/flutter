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

  static const kInitializingEvent = 'initializing';
  static const kStartedEvent = 'started';
  static const kPidKey = 'pid';
  static const kUrlKey = 'url';
  static const kDtdUriKey = 'dtdUri';
  static const kPreviewServiceKey = 'previewService';
  static const kScaffoldServiceKey = 'scaffoldService';
  static const kProjectRootKey = 'projectRoot';

  final bool machine;
  final bool verbose;
  final Stdio _stdio;

  void _sendLogMessage(String level, String message, {StackTrace? stackTrace}) {
    sendEvent('logMessage', <String, Object?>{
      'level': level,
      'message': message,
      'stackTrace': ?stackTrace?.toString(),
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
      _sendLogMessage('error', message, stackTrace: stackTrace);
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
      _sendLogMessage('warning', message);
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
      _sendLogMessage('status', message);
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
      _sendLogMessage('trace', message);
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
        <String, Object?>{'event': 'widget_preview.$name', 'params': ?args},
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

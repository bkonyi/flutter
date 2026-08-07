// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import '../base/logger.dart';
import '../globals.dart' as globals;
import '../runner/flutter_command.dart';

class GenerateCommand extends FlutterCommand {
  GenerateCommand({Logger? logger}) : _logger = logger {
    usesTargetOption();
  }

  final Logger? _logger;
  Logger get _effectiveLogger => _logger ?? globals.logger;

  @override
  String get description => 'run code generators.';

  @override
  String get name => 'generate';

  @override
  bool get hidden => true;

  @override
  Future<FlutterCommandResult> runCommand() async {
    _effectiveLogger.printError(
      '"flutter generate" is deprecated, use "dart run build_runner" instead. '
      'The following dependencies must be added to dev_dependencies in pubspec.yaml:\n'
      'build_runner: ^1.10.0\n'
      'including all dependencies under the "builders" key',
    );
    return FlutterCommandResult.fail();
  }
}

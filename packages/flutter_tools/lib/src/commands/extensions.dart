// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import '../base/common.dart';
import '../base/logger.dart';
import '../experimental/extension_registry.dart';
import '../runner/flutter_command.dart';

/// Command to manage global Flutter tool extensions.
class ExtensionsCommand extends FlutterCommand {
  ExtensionsCommand({required GlobalExtensionRegistry extensionRegistry, required Logger logger}) {
    addSubcommand(ExtensionsListCommand(globalRegistry: extensionRegistry, logger: logger));
    addSubcommand(ExtensionsInstallCommand(globalRegistry: extensionRegistry, logger: logger));
    addSubcommand(ExtensionsUninstallCommand(globalRegistry: extensionRegistry, logger: logger));
    addSubcommand(ExtensionsEnableCommand(globalRegistry: extensionRegistry, logger: logger));
    addSubcommand(ExtensionsDisableCommand(globalRegistry: extensionRegistry, logger: logger));
    addSubcommand(ExtensionsUpgradeCommand(globalRegistry: extensionRegistry, logger: logger));
  }

  @override
  String get name => 'extensions';

  @override
  String get description => 'Manage global Flutter tool extensions.';

  @override
  String get category => FlutterCommandCategory.tools;

  @override
  Future<FlutterCommandResult> runCommand() async {
    return FlutterCommandResult.success();
  }
}

/// Subcommand to list all installed global extensions.
class ExtensionsListCommand extends FlutterCommand {
  ExtensionsListCommand({required GlobalExtensionRegistry globalRegistry, required Logger logger})
    : _globalRegistry = globalRegistry,
      _logger = logger {
    argParser.addFlag('machine', negatable: false, help: 'Produce machine-readable JSON output.');
  }

  final GlobalExtensionRegistry _globalRegistry;
  final Logger _logger;

  @override
  String get name => 'list';

  @override
  String get description => 'List all installed global Flutter tool extensions.';

  @override
  String get category => FlutterCommandCategory.tools;

  @override
  Future<FlutterCommandResult> runCommand() async {
    final bool machine = boolArg('machine');
    final Map<String, GlobalExtensionEntry> entries = _globalRegistry.loadEntries();

    if (machine) {
      final List<Map<String, Object?>> jsonList = entries.values
          .map((GlobalExtensionEntry e) => e.toJson())
          .toList();
      _logger.printStatus(json.encode(jsonList));
      return FlutterCommandResult.success();
    }

    if (entries.isEmpty) {
      _logger.printStatus('No global extensions installed.');
      return FlutterCommandResult.success();
    }

    _logger.printStatus('Installed global extensions:');
    for (final GlobalExtensionEntry entry in entries.values) {
      final status = entry.enabled ? 'enabled' : 'disabled';
      final String services = entry.capabilities.services.isEmpty
          ? 'none'
          : entry.capabilities.services.join(', ');
      final String platforms = entry.capabilities.supportedPlatforms.isEmpty
          ? 'all'
          : entry.capabilities.supportedPlatforms.join(', ');
      _logger.printStatus('''
- ${entry.name} (${entry.version}, source: ${entry.source}) [$status]
  Capabilities: $services
  Platforms: $platforms
  Install dir: ${entry.installDir}
  Entrypoint: ${entry.entrypointPath}
  Snapshot: ${entry.snapshotPath ?? 'none'}''');
    }

    return FlutterCommandResult.success();
  }
}

/// Subcommand to install a global extension.
class ExtensionsInstallCommand extends FlutterCommand {
  ExtensionsInstallCommand({
    required GlobalExtensionRegistry globalRegistry,
    required Logger logger,
  }) : _globalRegistry = globalRegistry,
       _logger = logger {
    argParser.addOption(
      'name',
      abbr: 'n',
      help: 'The name of the extension to install (derived automatically if omitted).',
    );
  }

  final GlobalExtensionRegistry _globalRegistry;
  final Logger _logger;

  @override
  String get name => 'install';

  @override
  String get description =>
      'Install a global Flutter tool extension from a local path, pub, or git.';

  @override
  String get category => FlutterCommandCategory.tools;

  @override
  Future<FlutterCommandResult> runCommand() async {
    if (argResults?.rest.isEmpty ?? true) {
      throwToolExit('A source must be specified for "install".');
    }
    final String source = argResults!.rest.first;
    final String? name = stringArg('name');

    _logger.printStatus('Installing global extension from "$source"...');
    try {
      final GlobalExtensionEntry entry = await _globalRegistry.install(source: source, name: name);
      _logger.printStatus('Successfully installed extension "${entry.name}" (${entry.version}).');
      return FlutterCommandResult.success();
    } on Object catch (error) {
      throwToolExit('Failed to install extension: $error');
    }
  }
}

/// Subcommand to uninstall a global extension.
class ExtensionsUninstallCommand extends FlutterCommand {
  ExtensionsUninstallCommand({
    required GlobalExtensionRegistry globalRegistry,
    required Logger logger,
  }) : _globalRegistry = globalRegistry,
       _logger = logger;

  final GlobalExtensionRegistry _globalRegistry;
  final Logger _logger;

  @override
  String get name => 'uninstall';

  @override
  String get description => 'Uninstall a global Flutter tool extension.';

  @override
  String get category => FlutterCommandCategory.tools;

  @override
  Future<FlutterCommandResult> runCommand() async {
    if (argResults?.rest.isEmpty ?? true) {
      throwToolExit('An extension name must be specified for "uninstall".');
    }
    final String name = argResults!.rest.first;

    final bool removed = await _globalRegistry.uninstall(name);
    if (!removed) {
      throwToolExit('Extension "$name" is not installed.');
    }
    _logger.printStatus('Successfully uninstalled extension "$name".');
    return FlutterCommandResult.success();
  }
}

/// Subcommand to enable a global extension.
class ExtensionsEnableCommand extends FlutterCommand {
  ExtensionsEnableCommand({required GlobalExtensionRegistry globalRegistry, required Logger logger})
    : _globalRegistry = globalRegistry,
      _logger = logger;

  final GlobalExtensionRegistry _globalRegistry;
  final Logger _logger;

  @override
  String get name => 'enable';

  @override
  String get description => 'Enable a global Flutter tool extension.';

  @override
  String get category => FlutterCommandCategory.tools;

  @override
  Future<FlutterCommandResult> runCommand() async {
    if (argResults?.rest.isEmpty ?? true) {
      throwToolExit('An extension name must be specified for "enable".');
    }
    final String name = argResults!.rest.first;

    final bool success = _globalRegistry.enable(name);
    if (!success) {
      throwToolExit('Extension "$name" is not installed.');
    }
    _logger.printStatus('Enabled extension "$name".');
    return FlutterCommandResult.success();
  }
}

/// Subcommand to disable a global extension.
class ExtensionsDisableCommand extends FlutterCommand {
  ExtensionsDisableCommand({
    required GlobalExtensionRegistry globalRegistry,
    required Logger logger,
  }) : _globalRegistry = globalRegistry,
       _logger = logger;

  final GlobalExtensionRegistry _globalRegistry;
  final Logger _logger;

  @override
  String get name => 'disable';

  @override
  String get description => 'Disable a global Flutter tool extension.';

  @override
  String get category => FlutterCommandCategory.tools;

  @override
  Future<FlutterCommandResult> runCommand() async {
    if (argResults?.rest.isEmpty ?? true) {
      throwToolExit('An extension name must be specified for "disable".');
    }
    final String name = argResults!.rest.first;

    final bool success = _globalRegistry.disable(name);
    if (!success) {
      throwToolExit('Extension "$name" is not installed.');
    }
    _logger.printStatus('Disabled extension "$name".');
    return FlutterCommandResult.success();
  }
}

/// Subcommand to upgrade installed global extensions.
class ExtensionsUpgradeCommand extends FlutterCommand {
  ExtensionsUpgradeCommand({
    required GlobalExtensionRegistry globalRegistry,
    required Logger logger,
  }) : _globalRegistry = globalRegistry,
       _logger = logger;

  final GlobalExtensionRegistry _globalRegistry;
  final Logger _logger;

  @override
  String get name => 'upgrade';

  @override
  String get description => 'Upgrade installed global Flutter tool extensions.';

  @override
  String get category => FlutterCommandCategory.tools;

  @override
  Future<FlutterCommandResult> runCommand() async {
    final String? name = argResults?.rest.isNotEmpty ?? false ? argResults!.rest.first : null;

    _logger.printStatus(
      name != null
          ? 'Upgrading global extension "$name"...'
          : 'Upgrading all installed global extensions...',
    );

    try {
      final List<GlobalExtensionEntry> upgraded = await _globalRegistry.upgrade(name: name);
      if (upgraded.isEmpty) {
        if (name != null) {
          throwToolExit('Extension "$name" is not installed.');
        }
        _logger.printStatus('No global extensions to upgrade.');
      } else {
        for (final entry in upgraded) {
          _logger.printStatus('Successfully upgraded extension "${entry.name}".');
        }
      }
      return FlutterCommandResult.success();
    } on Object catch (error) {
      throwToolExit('Failed to upgrade extensions: $error');
    }
  }
}

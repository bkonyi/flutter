// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:args/args.dart';
import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:meta/meta.dart';
import 'package:process/process.dart';

import '../android/android_sdk.dart';
import '../artifacts.dart';
import '../base/common.dart' show throwToolExit;
import '../base/config.dart';
import '../base/file_system.dart';
import '../base/logger.dart';
import '../base/os.dart';
import '../base/platform.dart';
import '../base/process.dart';
import '../base/template.dart';
import '../base/terminal.dart';
import '../build_info.dart';
import '../build_system/build_system.dart';
import '../cache.dart';
import '../experimental/extension_arg_parser.dart';
import '../experimental/extension_build_manager.dart';
import '../features.dart';
import '../ios/code_signing.dart';
import '../ios/plist_parser.dart';
import '../macos/xcode.dart';
import '../runner/flutter_command.dart';
import '../version.dart';
import 'build_aar.dart';
import 'build_apk.dart';
import 'build_appbundle.dart';
import 'build_bundle.dart';
import 'build_ios.dart';
import 'build_ios_framework.dart';
import 'build_linux.dart';
import 'build_macos.dart';
import 'build_macos_framework.dart';
import 'build_swift_package.dart';
import 'build_web.dart';
import 'build_windows.dart';
import 'darwin_add_to_app.dart';

class BuildCommand extends FlutterCommand with ExtensionArgParserMixin {
  BuildCommand({
    required Artifacts artifacts,
    required Cache cache,
    required FileSystem fileSystem,
    required FlutterVersion flutterVersion,
    required BuildSystem buildSystem,
    required OperatingSystemUtils osUtils,
    required Logger logger,
    required AndroidSdk? androidSdk,
    required Config config,
    required Platform platform,
    required ProcessUtils processUtils,
    required ProcessManager processManager,
    required FileSystemUtils fileSystemUtils,
    required TemplateRenderer templateRenderer,
    required Terminal terminal,
    required PlistParser plistParser,
    required Xcode? xcode,
    ExtensionBuildManager? extensionBuildManager,
    bool verboseHelp = false,
  }) : _fileSystem = fileSystem,
       _logger = logger,
       _extensionBuildManager = extensionBuildManager,
       _verboseHelp = verboseHelp {
    _addSubcommand(
      BuildAarCommand(
        fileSystem: fileSystem,
        androidSdk: androidSdk,
        logger: logger,
        verboseHelp: verboseHelp,
      ),
    );
    _addSubcommand(BuildApkCommand(logger: logger, verboseHelp: verboseHelp));
    _addSubcommand(BuildAppBundleCommand(logger: logger, verboseHelp: verboseHelp));
    _addSubcommand(BuildIOSCommand(logger: logger, verboseHelp: verboseHelp));
    _addSubcommand(
      BuildIOSFrameworkCommand(
        logger: logger,
        buildSystem: buildSystem,
        verboseHelp: verboseHelp,
        codesign: DarwinAddToAppCodesigning(
          logger: logger,
          xcodeCodeSigningSettings: XcodeCodeSigningSettings(
            config: config,
            logger: logger,
            platform: platform,
            processUtils: processUtils,
            fileSystem: fileSystem,
            fileSystemUtils: fileSystemUtils,
            terminal: terminal,
            plistParser: plistParser,
          ),
        ),
      ),
    );
    _addSubcommand(
      BuildMacOSFrameworkCommand(
        logger: logger,
        buildSystem: buildSystem,
        verboseHelp: verboseHelp,
        codesign: DarwinAddToAppCodesigning(
          logger: logger,
          xcodeCodeSigningSettings: XcodeCodeSigningSettings(
            config: config,
            logger: logger,
            platform: platform,
            processUtils: processUtils,
            fileSystem: fileSystem,
            fileSystemUtils: fileSystemUtils,
            terminal: terminal,
            plistParser: plistParser,
          ),
        ),
      ),
    );
    _addSubcommand(
      BuildSwiftPackage(
        logger: logger,
        analytics: analytics,
        artifacts: artifacts,
        buildSystem: buildSystem,
        cache: cache,
        featureFlags: featureFlags,
        fileSystem: fileSystem,
        flutterVersion: flutterVersion,
        platform: platform,
        processManager: processManager,
        templateRenderer: templateRenderer,
        xcode: xcode,
        codesign: DarwinAddToAppCodesigning(
          logger: logger,
          xcodeCodeSigningSettings: XcodeCodeSigningSettings(
            config: config,
            logger: logger,
            platform: platform,
            processUtils: processUtils,
            fileSystem: fileSystem,
            fileSystemUtils: fileSystemUtils,
            terminal: terminal,
            plistParser: plistParser,
          ),
        ),
        verboseHelp: verboseHelp,
      ),
    );

    _addSubcommand(BuildIOSArchiveCommand(logger: logger, verboseHelp: verboseHelp));
    _addSubcommand(BuildBundleCommand(logger: logger, verboseHelp: verboseHelp));
    _addSubcommand(
      BuildWebCommand(fileSystem: fileSystem, logger: logger, verboseHelp: verboseHelp),
    );
    _addSubcommand(BuildMacosCommand(logger: logger, verboseHelp: verboseHelp));
    _addSubcommand(
      BuildLinuxCommand(logger: logger, operatingSystemUtils: osUtils, verboseHelp: verboseHelp),
    );
    _addSubcommand(
      BuildWindowsCommand(logger: logger, operatingSystemUtils: osUtils, verboseHelp: verboseHelp),
    );
  }

  final FileSystem _fileSystem;
  final Logger _logger;
  final ExtensionBuildManager? _extensionBuildManager;
  final bool _verboseHelp;

  @override
  void populateBaseArgParser(ArgParser parser) {}

  @override
  String? get extensionArgParserCacheKey {
    final targets = <ExtensionBuildTarget>[
      ...?_extensionBuildManager?.cachedTargets,
    ];
    if (targets.isEmpty) {
      return null;
    }
    return targets.map((ExtensionBuildTarget t) => t.name).join(',');
  }

  @override
  ArgParser buildDynamicArgParser(ArgParser baseParser) {
    final newParser = ArgParser(
      allowTrailingOptions: baseParser.allowTrailingOptions,
      usageLineLength: baseParser.usageLineLength,
    );
    for (final Option opt in baseParser.options.values) {
      if (opt.isFlag) {
        newParser.addFlag(
          opt.name,
          abbr: opt.abbr,
          help: opt.help,
          defaultsTo: opt.defaultsTo as bool?,
          negatable: opt.negatable ?? true,
          hide: opt.hide,
          hideNegatedUsage: opt.hideNegatedUsage ?? false,
          aliases: opt.aliases,
        );
      } else if (opt.isSingle) {
        final Map<String, String>? allowedHelp = opt.allowedHelp != null
            ? Map<String, String>.from(opt.allowedHelp!)
            : null;
        newParser.addOption(
          opt.name,
          abbr: opt.abbr,
          help: opt.help,
          defaultsTo: opt.defaultsTo as String?,
          allowed: opt.allowed,
          allowedHelp: allowedHelp,
          hide: opt.hide,
          aliases: opt.aliases,
        );
      } else if (opt.isMultiple) {
        final Map<String, String>? allowedHelp = opt.allowedHelp != null
            ? Map<String, String>.from(opt.allowedHelp!)
            : null;
        newParser.addMultiOption(
          opt.name,
          abbr: opt.abbr,
          help: opt.help,
          defaultsTo: opt.defaultsTo as List<String>?,
          allowed: opt.allowed,
          allowedHelp: allowedHelp,
          hide: opt.hide,
          aliases: opt.aliases,
        );
      }
    }
    return newParser;
  }

  @override
  Future<void> initializeDynamicOptions() async {
    if (_extensionBuildManager case final ExtensionBuildManager extensionBuildManager?) {
      final targets = <ExtensionBuildTarget>[
        ...await extensionBuildManager.getBuildTargets(),
      ];
      for (final target in targets) {
        if (!subcommands.containsKey(target.name)) {
          _addSubcommand(
            ExtensionBuildSubCommand(
              target: target,
              buildManager: extensionBuildManager,
              fileSystem: _fileSystem,
              logger: _logger,
              verboseHelp: _verboseHelp,
            ),
          );
        }
      }
    }
  }

  void _addSubcommand(BuildSubCommand command) {
    if (command.supported) {
      addSubcommand(command);
    }
  }

  @override
  final name = 'build';

  @override
  final description = 'Build an executable app or install bundle.';

  @override
  String get category => FlutterCommandCategory.project;

  @override
  Future<FlutterCommandResult> runCommand() async => FlutterCommandResult.fail();
}

abstract class BuildSubCommand extends FlutterCommand {
  BuildSubCommand({required this.logger, required bool verboseHelp}) {
    requiresPubspecYaml();
    usesFatalWarningsOption(verboseHelp: verboseHelp);
  }

  @protected
  final Logger logger;

  /// Whether this command is supported and should be shown.
  bool get supported => true;
}

class ExtensionBuildSubCommand extends BuildSubCommand {
  ExtensionBuildSubCommand({
    required this.target,
    required ExtensionBuildManager buildManager,
    required FileSystem fileSystem,
    required super.logger,
    required bool verboseHelp,
  }) : _buildManager = buildManager,
       _fileSystem = fileSystem,
       super(verboseHelp: verboseHelp) {
    usesTargetOption();
    usesPubOption();
    addBuildModeFlags(verboseHelp: verboseHelp);
  }

  final ExtensionBuildTarget target;
  final ExtensionBuildManager _buildManager;
  final FileSystem _fileSystem;

  @override
  String get name => target.name;

  @override
  String get description => target.description;

  @override
  Future<FlutterCommandResult> runCommand() async {
    final String projectRoot = _fileSystem.currentDirectory.path;
    final String mainPath = targetFile;
    final BuildInfo buildInfo = await getBuildInfo();
    final String buildModeName = buildInfo.mode.name;

    final ExtensionBuildResult result = await _buildManager.build(
      targetName: target.name,
      projectRoot: projectRoot,
      mainPath: mainPath,
      buildMode: buildModeName,
    );

    if (result.success) {
      return FlutterCommandResult.success();
    } else {
      throwToolExit(result.errorMessage ?? 'Build failed.');
    }
  }
}

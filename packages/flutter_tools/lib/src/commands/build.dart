// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';
import 'package:process/process.dart';

import '../android/android_builder.dart';
import '../android/android_sdk.dart';
import '../artifacts.dart';
import '../base/config.dart';
import '../base/file_system.dart';
import '../base/logger.dart';
import '../base/os.dart';
import '../base/platform.dart';
import '../base/process.dart';
import '../base/template.dart';
import '../base/terminal.dart';
import '../build_system/build_system.dart';
import '../cache.dart';
import '../context/android_context.dart';
import '../context/apple_context.dart';
import '../context/tool_context.dart';
import '../features.dart';
import '../globals.dart' as globals;
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

class BuildCommand extends FlutterCommand {
  BuildCommand({
    ToolContext? toolContext,
    AndroidContext? androidContext,
    AppleContext? appleContext,
    Artifacts? artifacts,
    Cache? cache,
    FileSystem? fileSystem,
    FlutterVersion? flutterVersion,
    BuildSystem? buildSystem,
    OperatingSystemUtils? osUtils,
    Logger? logger,
    AndroidSdk? androidSdk,
    Config? config,
    Platform? platform,
    ProcessUtils? processUtils,
    ProcessManager? processManager,
    FileSystemUtils? fileSystemUtils,
    TemplateRenderer? templateRenderer,
    Terminal? terminal,
    PlistParser? plistParser,
    Xcode? xcode,
    AndroidBuilder? androidBuilder,
    bool verboseHelp = false,
  }) {
    final FileSystem effectiveFileSystem = fileSystem ?? toolContext?.fs ?? globals.fs;
    final Logger effectiveLogger = logger ?? toolContext?.logger ?? globals.logger;
    final Platform effectivePlatform = platform ?? toolContext?.platform ?? globals.platform;
    final ProcessManager effectiveProcessManager =
        processManager ?? toolContext?.processManager ?? globals.processManager;
    final ProcessUtils effectiveProcessUtils =
        processUtils ?? toolContext?.processUtils ?? globals.processUtils;
    final FileSystemUtils effectiveFileSystemUtils =
        fileSystemUtils ?? toolContext?.fileSystemUtils ?? globals.fsUtils;
    final Terminal effectiveTerminal = terminal ?? toolContext?.terminal ?? globals.terminal;
    final Config effectiveConfig = config ?? toolContext?.config ?? globals.config;
    final Artifacts effectiveArtifacts = artifacts ?? toolContext?.artifacts ?? globals.artifacts!;
    final Cache effectiveCache = cache ?? toolContext?.cache ?? globals.cache;
    final FlutterVersion effectiveFlutterVersion =
        flutterVersion ?? toolContext?.flutterVersion ?? globals.flutterVersion;
    final OperatingSystemUtils effectiveOsUtils = osUtils ?? toolContext?.os ?? globals.os;
    final TemplateRenderer effectiveTemplateRenderer = templateRenderer ?? globals.templateRenderer;
    final AndroidSdk? effectiveAndroidSdk =
        androidSdk ?? androidContext?.androidSdk ?? globals.androidSdk;
    final PlistParser effectivePlistParser =
        plistParser ?? appleContext?.plistParser ?? globals.plistParser;
    final Xcode? effectiveXcode = xcode ?? appleContext?.xcode ?? globals.xcode;
    final BuildSystem effectiveBuildSystem = buildSystem ?? globals.buildSystem;

    final xcodeCodeSigningSettings = XcodeCodeSigningSettings(
      config: effectiveConfig,
      logger: effectiveLogger,
      platform: effectivePlatform,
      processUtils: effectiveProcessUtils,
      fileSystem: effectiveFileSystem,
      fileSystemUtils: effectiveFileSystemUtils,
      terminal: effectiveTerminal,
      plistParser: effectivePlistParser,
    );
    final darwinAddToAppCodesigning = DarwinAddToAppCodesigning(
      logger: effectiveLogger,
      xcodeCodeSigningSettings: xcodeCodeSigningSettings,
    );

    _addSubcommand(
      BuildAarCommand(
        androidBuilder: androidBuilder,
        androidSdk: effectiveAndroidSdk,
        fileSystem: effectiveFileSystem,
        logger: effectiveLogger,
        verboseHelp: verboseHelp,
      ),
    );
    _addSubcommand(
      BuildApkCommand(
        androidBuilder: androidBuilder,
        androidSdk: effectiveAndroidSdk,
        logger: effectiveLogger,
        verboseHelp: verboseHelp,
      ),
    );
    _addSubcommand(
      BuildAppBundleCommand(
        androidBuilder: androidBuilder,
        androidSdk: effectiveAndroidSdk,
        logger: effectiveLogger,
        verboseHelp: verboseHelp,
      ),
    );
    _addSubcommand(BuildIOSCommand(logger: effectiveLogger, verboseHelp: verboseHelp));
    _addSubcommand(
      BuildIOSFrameworkCommand(
        logger: effectiveLogger,
        buildSystem: effectiveBuildSystem,
        verboseHelp: verboseHelp,
        codesign: darwinAddToAppCodesigning,
      ),
    );
    _addSubcommand(
      BuildMacOSFrameworkCommand(
        logger: effectiveLogger,
        buildSystem: effectiveBuildSystem,
        verboseHelp: verboseHelp,
        codesign: darwinAddToAppCodesigning,
      ),
    );
    _addSubcommand(
      BuildSwiftPackage(
        logger: effectiveLogger,
        analytics: globals.analytics,
        artifacts: effectiveArtifacts,
        buildSystem: effectiveBuildSystem,
        cache: effectiveCache,
        featureFlags: featureFlags,
        fileSystem: effectiveFileSystem,
        flutterVersion: effectiveFlutterVersion,
        platform: effectivePlatform,
        processManager: effectiveProcessManager,
        templateRenderer: effectiveTemplateRenderer,
        xcode: effectiveXcode,
        codesign: darwinAddToAppCodesigning,
        verboseHelp: verboseHelp,
      ),
    );

    _addSubcommand(BuildIOSArchiveCommand(logger: effectiveLogger, verboseHelp: verboseHelp));
    _addSubcommand(BuildBundleCommand(logger: effectiveLogger, verboseHelp: verboseHelp));
    _addSubcommand(
      BuildWebCommand(
        fileSystem: effectiveFileSystem,
        logger: effectiveLogger,
        verboseHelp: verboseHelp,
      ),
    );
    _addSubcommand(BuildMacosCommand(logger: effectiveLogger, verboseHelp: verboseHelp));
    _addSubcommand(
      BuildLinuxCommand(
        logger: effectiveLogger,
        operatingSystemUtils: effectiveOsUtils,
        verboseHelp: verboseHelp,
      ),
    );
    _addSubcommand(
      BuildWindowsCommand(
        logger: effectiveLogger,
        operatingSystemUtils: effectiveOsUtils,
        verboseHelp: verboseHelp,
      ),
    );
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

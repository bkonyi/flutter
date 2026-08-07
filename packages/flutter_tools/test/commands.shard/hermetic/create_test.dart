// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:args/args.dart';
import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/commands/create.dart';
import 'package:flutter_tools/src/experimental/extension_manager.dart';
import 'package:flutter_tools/src/experimental/templates.dart';
import 'package:flutter_tools/src/features.dart';
import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:test/fake.dart';

import '../../src/context.dart';
import '../../src/fakes.dart';
import '../../src/test_flutter_command_runner.dart';

class FakeExtensionManager extends Fake implements ExtensionManager {}

base class FakeExtensionTemplateManager extends ExtensionTemplateManager {
  FakeExtensionTemplateManager({
    required super.fileSystem,
    required super.logger,
    required super.featureFlags,
    this.templates = const <ProjectTemplate>[],
  }) : super(extensionManager: FakeExtensionManager());

  final List<ProjectTemplate> templates;

  @override
  List<ProjectTemplate> get cachedTemplates => templates;

  @override
  Future<List<ProjectTemplate>> getProjectTemplates() async => templates;
}

void main() {
  group('CreateCommand Custom Templates', () {
    late MemoryFileSystem fileSystem;
    late BufferLogger logger;
    late FakeExtensionTemplateManager extensionTemplateManager;

    setUp(() {
      fileSystem = MemoryFileSystem.test();
      logger = BufferLogger.test();
    });

    testUsingContext(
      'custom templates are registered in the parser when extensions are enabled',
      () async {
        final customTemplate = ExtensionProjectTemplate(
          name: 'my_custom_template',
          hidden: false,
          templateDependencies: <String>{},
          templateSources: <String>{},
          templatePath: 'some/path',
        );
        extensionTemplateManager = FakeExtensionTemplateManager(
          fileSystem: fileSystem,
          logger: logger,
          featureFlags: TestFeatureFlags(isToolExtensionsEnabled: true),
          templates: <ProjectTemplate>[customTemplate],
        );

        final command = CreateCommand(extensionTemplateManager: extensionTemplateManager);
        createTestCommandRunner(command);

        await command.initializeDynamicOptions();

        final Option? templateOption = command.argParser.options['template'];
        expect(templateOption, isNotNull);
        expect(templateOption!.allowedHelp, contains('my_custom_template'));
      },
      overrides: <Type, Generator>{
        FeatureFlags: () => TestFeatureFlags(isToolExtensionsEnabled: true),
        FileSystem: () => fileSystem,
        ProcessManager: () => FakeProcessManager.any(),
      },
    );
  });
}

// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';

/// Prototype Linux implementation of [CleanService].
final class LinuxCleanService extends CleanService {
  @override
  Future<void> clean(CleanEnvironment environment) async {
    final String buildPath = environment.buildDir.toFilePath();
    final String projectPath = environment.projectRoot.toFilePath();

    final linuxBuildDir = Directory('$buildPath/linux');
    if (linuxBuildDir.existsSync()) {
      linuxBuildDir.deleteSync(recursive: true);
    }

    final linuxEphemeralDir = Directory('$projectPath/linux/flutter/ephemeral');
    if (linuxEphemeralDir.existsSync()) {
      linuxEphemeralDir.deleteSync(recursive: true);
    }
  }
}

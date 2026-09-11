// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';

/// Prototype Linux [CleanService] implementation.
final class LinuxCleanService extends CleanService {
  @override
  Future<void> clean(CleanEnvironment environment) async {
    final buildDir = Directory.fromUri(environment.buildDir);
    final linuxBuildDir = Directory('${buildDir.path}/linux');
    if (linuxBuildDir.existsSync()) {
      linuxBuildDir.deleteSync(recursive: true);
    }
  }
}

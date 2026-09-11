// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';

/// Prototype Linux [ArtifactService] implementation.
final class LinuxArtifactService extends ArtifactService {
  @override
  Set<ArtifactDependency> get artifacts => <ArtifactDependency>{
    const ArtifactDependency(
      hostPlatform: 'linux-x64',
      name: 'linux-headers',
      sha256Checksums: <String, String>{
        'linux-x64': '3c8264482ab165120c56c81c7d0df8cf8e934aa7bd9e8386a819b79525ef9cc7',
      },
      targetArchitecture: 'x64',
      targetPlatform: 'linux',
    ),
  };

  @override
  Future<void> downloadArtifacts(
    Set<String> artifactNames, {
    required BuildMode buildMode,
    required Uri destinationDirectory,
    required HostPlatform hostPlatform,
    required TargetPlatform targetPlatform,
  }) async {
    final destinationDir = Directory.fromUri(destinationDirectory);
    if (!destinationDir.existsSync()) {
      destinationDir.createSync(recursive: true);
    }
    for (final name in artifactNames) {
      final file = File('${destinationDir.path}/$name');
      if (!file.existsSync()) {
        file.writeAsStringSync('artifact payload for $name\n');
      }
    }
  }
}

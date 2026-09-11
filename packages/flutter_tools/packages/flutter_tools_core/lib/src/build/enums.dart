// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
import 'package:meta/meta.dart';

// Simple string utilities to avoid dependencies.
String _snakeCase(String name) {
  return name
      .replaceAllMapped(RegExp(r'(?<=[a-z0-9])[A-Z]'), (Match m) => '_${m.group(0)}')
      .toLowerCase();
}

String _sentenceCase(String name) {
  if (name.isEmpty) {
    return name;
  }
  return '${name[0].toUpperCase()}${name.substring(1)}';
}

/// The mode in which the application is built.
enum BuildMode {
  /// Built in JIT mode with no optimizations, enabled asserts, and a VM service.
  debug,

  /// Built in AOT mode with some optimizations and a VM service.
  profile,

  /// Built in AOT mode with all optimizations and no VM service.
  release,

  /// Built in JIT mode with all optimizations and no VM service.
  jitRelease;

  factory BuildMode.fromCliName(String value) => values.singleWhere(
    (BuildMode element) => element.cliName == value,
    orElse: () => throw ArgumentError('$value is not a supported build mode'),
  );

  static const releaseModes = <BuildMode>{release, jitRelease};
  static const jitModes = <BuildMode>{debug, jitRelease};

  /// Whether this mode is considered release.
  bool get isRelease => releaseModes.contains(this);

  /// Whether this mode is using the JIT runtime.
  bool get isJit => jitModes.contains(this);

  /// Whether this mode is using the precompiled runtime.
  bool get isPrecompiled => !isJit;

  /// [name] formatted in snake case.
  String get cliName => _snakeCase(name);

  /// [cliName] formatted in sentence case.
  String get uppercaseName => _sentenceCase(cliName);

  /// [cliName] with `_` replaced with a space.
  String get friendlyName => cliName.replaceAll('_', ' ');

  /// [friendlyName] formatted in sentence case.
  String get uppercaseFriendlyName => _sentenceCase(friendlyName);

  @override
  String toString() => cliName;
}

/// Represents an artifact downloaded from the Flutter cache (e.g. engine binaries, frameworks).
///
/// Extensions can reference these artifacts in their target inputs/outputs,
/// and the host will resolve them to physical paths on the host before build execution.
@immutable
class Artifact {
  const Artifact(this.name);

  /// The unique identifying name of this artifact.
  final String name;

  @override
  bool operator ==(Object other) => other is Artifact && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}

/// Represents an artifact used by the host build system (e.g. compilers, tools).
///
/// Extensions can reference these host-side artifacts in their target inputs/outputs,
/// and the host will resolve them to physical paths on the host before build execution.
@immutable
class HostArtifact {
  const HostArtifact(this.name);

  /// The unique identifying name of this host artifact.
  final String name;

  @override
  bool operator ==(Object other) => other is HostArtifact && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}

/// The architecture of a CPU.
enum CpuArch {
  armv7,
  arm64,
  x86,
  x64,
  riscv64,
  unknown;

  factory CpuArch.fromName(String name) {
    return switch (name) {
      'unknown' => unknown,
      'armv7' => armv7,
      'arm64' => arm64,
      'x86' => x86,
      'x64' || 'x86_64' => x64,
      'riscv64' => riscv64,
      _ => throw Exception('Unsupported CPU arch name "$name"'),
    };
  }

  /// The [CpuArch] of the given [hostPlatform].
  factory CpuArch.fromHostPlatform(HostPlatform hostPlatform) {
    return switch (hostPlatform) {
      HostPlatform.darwin_x64 || HostPlatform.linux_x64 || HostPlatform.windows_x64 => x64,
      HostPlatform.darwin_arm64 || HostPlatform.linux_arm64 || HostPlatform.windows_arm64 => arm64,
      HostPlatform.linux_riscv64 => riscv64,
    };
  }

  /// Returns the Dart SDK's name for the specified target architecture.
  String get dartName {
    return switch (this) {
      armv7 => 'armv7',
      arm64 => 'arm64',
      x86 => 'x86',
      x64 => 'x64',
      riscv64 => 'riscv64',
      unknown => throw UnsupportedError('Unexpected CPU arch $this'),
    };
  }

  /// The Apple architecture name for this architecture.
  String get darwinArchName => switch (this) {
    armv7 => 'armv7',
    arm64 => 'arm64',
    x64 => 'x86_64',
    x86 || riscv64 || unknown => throw UnsupportedError('Unexpected Darwin CPU arch $this'),
  };

  /// The name of the Android ABI (as used in `jniLibs` directories) for this
  /// architecture.
  String get androidArchName => switch (this) {
    armv7 => 'armeabi-v7a',
    arm64 => 'arm64-v8a',
    x64 => 'x86_64',
    x86 || riscv64 || unknown => throw UnsupportedError('Unexpected Android CPU arch $this'),
  };

  /// The `TargetPlatform` name of the Android platform for this architecture.
  String get androidPlatformName => switch (this) {
    armv7 => 'android-arm',
    arm64 => 'android-arm64',
    x64 => 'android-x64',
    x86 || riscv64 || unknown => throw UnsupportedError('Unexpected Android CPU arch $this'),
  };
}

/// Represents the platform running the Flutter tool.
enum HostPlatform {
  darwin_x64('darwin-x64', 'x64'),
  darwin_arm64('darwin-arm64', 'arm64'),
  linux_x64('linux-x64', 'x64'),
  linux_arm64('linux-arm64', 'arm64'),
  linux_riscv64('linux-riscv64', 'riscv64'),
  windows_x64('windows-x64', 'x64'),
  windows_arm64('windows-arm64', 'arm64');

  const HostPlatform(this.cliName, this.platformName);

  final String cliName;
  final String platformName;

  /// Returns the host platform for the specified OS and architecture.
  static HostPlatform? fromOsAndArch(String os, String arch) {
    return switch ((os, arch.toLowerCase())) {
      ('macos', 'x64') => darwin_x64,
      ('macos', 'arm64') => darwin_arm64,
      ('linux', 'x64') => linux_x64,
      ('linux', 'arm64') => linux_arm64,
      ('linux', 'riscv64') => linux_riscv64,
      ('windows', 'x64') => windows_x64,
      ('windows', 'arm64') => windows_arm64,
      _ => null,
    };
  }
}

/// The platform for which an application is built or targeted.
enum TargetPlatform {
  android('android'),
  ios('ios'),
  darwin('darwin'),
  linux_x64('linux-x64'),
  linux_arm64('linux-arm64'),
  linux_riscv64('linux-riscv64'),
  windows_x64('windows-x64'),
  windows_arm64('windows-arm64'),
  fuchsia_arm64('fuchsia-arm64'),
  fuchsia_x64('fuchsia-x64'),
  tester('flutter-tester'),
  web_javascript('web-javascript'),
  // The arch specific android target platforms are soft-deprecated.
  // Instead of using TargetPlatform as a combination arch + platform
  // the code will be updated to carry arch information in [CpuArch].
  android_arm('android-arm'),
  android_arm64('android-arm64'),
  android_x64('android-x64'),
  unsupported('unsupported');

  const TargetPlatform(this._defaultName);

  factory TargetPlatform.fromName(String name) {
    return switch (name) {
      'android' => TargetPlatform.android,
      'android-arm' => TargetPlatform.android_arm,
      'android-arm64' => TargetPlatform.android_arm64,
      'android-x64' => TargetPlatform.android_x64,
      'fuchsia-arm64' => TargetPlatform.fuchsia_arm64,
      'fuchsia-x64' => TargetPlatform.fuchsia_x64,
      'ios' => TargetPlatform.ios,
      'darwin' || 'darwin-x64' || 'darwin-arm64' => TargetPlatform.darwin,
      'linux-x64' || 'linux_x64' => TargetPlatform.linux_x64,
      'linux-arm64' || 'linux_arm64' => TargetPlatform.linux_arm64,
      'linux-riscv64' || 'linux_riscv64' => TargetPlatform.linux_riscv64,
      'windows-x64' || 'windows_x64' => TargetPlatform.windows_x64,
      'windows-arm64' || 'windows_arm64' => TargetPlatform.windows_arm64,
      'web-javascript' => TargetPlatform.web_javascript,
      'flutter-tester' => TargetPlatform.tester,
      _ => throw Exception('Unsupported platform name "$name"'),
    };
  }

  final String _defaultName;

  String getName({CpuArch? cpuArch}) {
    return switch (this) {
      TargetPlatform.ios when cpuArch != null => 'ios-${cpuArch.darwinArchName}',
      TargetPlatform.darwin when cpuArch != null => 'darwin-${cpuArch.darwinArchName}',
      _ => _defaultName,
    };
  }

  String get fuchsiaArchForTargetPlatform => switch (this) {
    fuchsia_arm64 => 'arm64',
    fuchsia_x64 => 'x64',
    android ||
    android_arm ||
    android_arm64 ||
    android_x64 ||
    darwin ||
    ios ||
    linux_arm64 ||
    linux_riscv64 ||
    linux_x64 ||
    tester ||
    web_javascript ||
    windows_x64 ||
    windows_arm64 ||
    unsupported => throw UnsupportedError('Unexpected Fuchsia platform $this'),
  };

  String get osName => switch (this) {
    linux_x64 || linux_arm64 || linux_riscv64 => 'linux',
    darwin => 'macos',
    windows_x64 || windows_arm64 => 'windows',
    android || android_arm || android_arm64 || android_x64 => 'android',
    fuchsia_arm64 || fuchsia_x64 => 'fuchsia',
    ios => 'ios',
    tester => 'flutter-tester',
    web_javascript => 'web',
    unsupported => throw UnsupportedError('Unexpected target platform $this'),
  };

  String get simpleName => switch (this) {
    linux_x64 || darwin || windows_x64 => 'x64',
    linux_arm64 || windows_arm64 => 'arm64',
    linux_riscv64 => 'riscv64',
    android ||
    android_arm ||
    android_arm64 ||
    android_x64 ||
    fuchsia_arm64 ||
    fuchsia_x64 ||
    ios ||
    tester ||
    web_javascript ||
    unsupported => throw UnsupportedError('Unexpected target platform $this'),
  };

  static Never throwUnsupportedTarget() =>
      throw UnsupportedError('Target platform is unsupported.');
}

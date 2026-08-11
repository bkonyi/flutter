# Plugins Extension Slice & Dynamic Plugin Resolution Architecture

This document details the architecture of the **Plugins Extension Slice** introduced in `ft-ext-step09-plugins-slice`. It explains how custom platform plugins are dynamically resolved on the host, passed across isolate IPC boundaries without host-side platform assumptions, symlinked into transient build directories, and injected into extension-driven native build pipelines (such as CMake configuration generation). It also highlights the modern Dart 3 refactorings in `package:flutter_tools/src/plugins.dart`.

---

## 1. Architecture Overview & End-to-End Flow

The Plugins extension slice decouples platform-specific plugin handling from the host CLI (`flutter_tools`). Traditionally, `flutter_tools` contained hardcoded assumptions about supported platforms (`android`, `ios`, `linux`, `macos`, `windows`, `web`), including platform-specific YAML parsing, code generation, and directory structures.

With the Plugins extension slice:
1. **Host-Side Neutrality**: The host CLI parses pubspec plugin definitions for unrecognized/custom platform keys into generic [CustomPlatformPlugin](file:///usr/local/google/home/bkonyi/.gemini/jetski/worktrees/flutter/resume_handoff_step_08/packages/flutter_tools/lib/src/platform_plugins.dart#L668-L675) instances.
2. **IPC Data Transfer**: Resolved plugins for a target platform are serialized into lightweight [ExtensionPlugin](file:///usr/local/google/home/bkonyi/.gemini/jetski/worktrees/flutter/resume_handoff_step_08/packages/flutter_tools/packages/flutter_tools_core/lib/src/build/plugin.dart#L5-L44) Data Transfer Objects (DTOs) and passed to extension isolates inside [ExtensionBuildContext](file:///usr/local/google/home/bkonyi/.gemini/jetski/worktrees/flutter/resume_handoff_step_08/packages/flutter_tools/packages/flutter_tools_extension/lib/src/build.dart#L10-L42).
3. **Extension-Driven Pre-Build Injection**: Extension isolates handle pre-build plugin injection, transient symlinking, registrant code generation, and native tool invocation (e.g. CMake, Ninja) completely within the extension runtime.

### Component Overview

- **Data Contract (`package:flutter_tools_core`)**:
  - [ExtensionPlugin](file:///usr/local/google/home/bkonyi/.gemini/jetski/worktrees/flutter/resume_handoff_step_08/packages/flutter_tools/packages/flutter_tools_core/lib/src/build/plugin.dart#L5-L44): Immutable DTO representing a plugin resolved for an extension target platform. Contains:
    - `name`: The plugin package name (e.g., `'url_launcher'`).
    - `path`: The absolute file system path to the plugin root directory on the host.
    - `configuration`: Untyped `Map<String, Object?>` extracted from the platform section of `pubspec.yaml`.
  - [Target](file:///usr/local/google/home/bkonyi/.gemini/jetski/worktrees/flutter/resume_handoff_step_08/packages/flutter_tools/packages/flutter_tools_core/lib/src/build/target.dart#L33) & [ExtensionBuildTarget](file:///usr/local/google/home/bkonyi/.gemini/jetski/worktrees/flutter/resume_handoff_step_08/packages/flutter_tools/packages/flutter_tools_core/lib/src/build.dart#L79): Exposes optional `pluginPlatformKey` String getter (e.g. `'linux'`), linking build targets to pubspec platform keys.
- **Service Contract (`package:flutter_tools_extension`)**:
  - [ExtensionBuildContext](file:///usr/local/google/home/bkonyi/.gemini/jetski/worktrees/flutter/resume_handoff_step_08/packages/flutter_tools/packages/flutter_tools_extension/lib/src/build.dart#L42): Updated to include `List<ExtensionPlugin> plugins`.
  - [BuildService](file:///usr/local/google/home/bkonyi/.gemini/jetski/worktrees/flutter/resume_handoff_step_08/packages/flutter_tools/packages/flutter_tools_extension/lib/src/build.dart#L142-L175): Deserializes `plugins` from `build.build` RPC parameter maps and populates `ExtensionBuildContext`.
- **Host Resolution Engine (`package:flutter_tools`)**:
  - [CustomPlatformPlugin](file:///usr/local/google/home/bkonyi/.gemini/jetski/worktrees/flutter/resume_handoff_step_08/packages/flutter_tools/lib/src/platform_plugins.dart#L668-L675): Generic `PluginPlatform` subclass storing unhandled platform configuration maps.
  - [Plugin._fromMultiPlatformYaml](file:///usr/local/google/home/bkonyi/.gemini/jetski/worktrees/flutter/resume_handoff_step_08/packages/flutter_tools/lib/src/plugins.dart#L172-L176): Updated to instantiate `CustomPlatformPlugin` for non-builtin platform keys.
  - [BuildCommand](file:///usr/local/google/home/bkonyi/.gemini/jetski/worktrees/flutter/resume_handoff_step_08/packages/flutter_tools/lib/src/commands/build.dart#L348-L365) & [ExtensionDeviceManager](file:///usr/local/google/home/bkonyi/.gemini/jetski/worktrees/flutter/resume_handoff_step_08/packages/flutter_tools/lib/src/experimental/extension_device_manager.dart#L212-L226): Queries `project` dependencies for the target's `pluginPlatformKey`, converts resolved plugins into `ExtensionPlugin` DTOs, and includes them in the build RPC request.
- **Platform Extension Prototype (`package:flutter_tools_extension_linux_prototype`)**:
  - [CustomLinuxBuildTarget](file:///usr/local/google/home/bkonyi/.gemini/jetski/worktrees/flutter/resume_handoff_step_08/packages/flutter_tools/packages/flutter_tools_extension_linux_prototype/lib/src/build.dart#L31-L40): Declares `pluginPlatformKey => 'linux'`.
  - [CustomLinuxBuildTarget.build](file:///usr/local/google/home/bkonyi/.gemini/jetski/worktrees/flutter/resume_handoff_step_08/packages/flutter_tools/packages/flutter_tools_extension_linux_prototype/lib/src/build.dart#L113-L232): Receives `context.plugins`, creates transient symlinks under `linux/flutter/ephemeral/.plugin_symlinks`, generates `generated_config.cmake`, `generated_plugins.cmake`, `generated_plugin_registrant.h`, and `generated_plugin_registrant.cc`, then invokes Ninja/CMake.

---

## 2. End-to-End Plugin Discovery & Build Injection Sequence

### 2.1 Dynamic Plugin Resolution and Host IPC Transfer

When a build is initiated (e.g. `flutter build custom-linux-build` or launching on an extension custom device), the host CLI resolves applicable plugins for the target platform key and transmits them over isolate RPC boundaries:

```mermaid
sequenceDiagram
    autonumber
    participant CLI as Host Build Command / Device Manager<br/>(package:flutter_tools)
    participant PR as Plugin Resolver<br/>(package:flutter_tools/src/plugins.dart)
    participant BM as ExtensionBuildManager<br/>(package:flutter_tools)
    participant Connection as ExtensionConnection<br/>(Isolate Channel)
    participant ExtService as BuildService / Extension Isolate<br/>(package:flutter_tools_extension)

    CLI->>CLI: Identify target pluginPlatformKey (e.g. 'linux')
    CLI->>PR: refreshPluginsList(project) & findPlugins(project)
    PR-->>CLI: List<Plugin> (including CustomPlatformPlugin entries)
    CLI->>PR: resolvePluginImplementationsForPlatform(allPlugins, 'linux')
    PR-->>CLI: List<Plugin> resolved
    
    loop For each resolved Plugin
        CLI->>CLI: Extract PluginPlatform config for 'linux'<br/>Construct ExtensionPlugin(name, path, configuration)
    end
    
    CLI->>BM: build(targetName, projectRoot, ..., plugins)
    BM->>Connection: sendRequest("build.build", {..., plugins: [ExtensionPlugin.toMap()]})
    Connection->>ExtService: RPC Request: build.build(payload)
    activate ExtService
    ExtService->>ExtService: Deserialize plugins: List<ExtensionPlugin.fromJson>
    ExtService->>ExtService: Construct ExtensionBuildContext(..., plugins)
    ExtService->>ExtService: target.build(context)
    ExtService-->>Connection: ExtensionBuildResult.toMap()
    deactivate ExtService
    Connection-->>BM: RPC response
    BM-->>CLI: Build outcome
```

### 2.2 Pre-Build Plugin Injection & Native Code Generation within Extension Isolate

Once the extension isolate receives `ExtensionBuildContext`, it manages transient directory creation, symlinking, CMake configuration writing, and native compilation:

```mermaid
sequenceDiagram
    autonumber
    participant Target as CustomLinuxBuildTarget<br/>(Extension Isolate)
    participant FS as File System<br/>(Host Disk)
    participant CMake as Native CMake / Ninja
    
    Target->>FS: Unpack artifacts (headers, desktop engine) into ephemeral dir
    Target->>FS: Write ephemeral/generated_config.cmake
    Target->>FS: Clean and recreate ephemeral/.plugin_symlinks/
    
    loop For each ExtensionPlugin in context.plugins
        Target->>FS: Create Link: .plugin_symlinks/{plugin.name} -> plugin.path
        Target->>Target: Inspect plugin.configuration (MethodChannel vs FFI vs Dart)
    end
    
    Target->>FS: Write ephemeral/generated_plugins.cmake (add_subdirectory rules)
    Target->>FS: Write ephemeral/generated_plugin_registrant.h
    Target->>FS: Write ephemeral/generated_plugin_registrant.cc (fl_register_plugins)
    
    Target->>CMake: Process.start('cmake', ['-G', 'Ninja', ...])
    activate CMake
    CMake-->>Target: CMake build complete
    deactivate CMake
    
    Target->>CMake: Process.start('ninja', ['-C', buildDir])
    activate CMake
    CMake-->>Target: Compilation & Linking finished
    deactivate CMake
    
    Target-->>Target: Return success status & executablePath DTO
```

---

## 3. Data-Only Contract Separation vs Host Resolution Logic

The architecture enforces strict boundary separation between data contracts in `flutter_tools_core`, service contracts in `flutter_tools_extension`, host parsing/resolution in `flutter_tools`, and native code generation in extension prototypes:

```mermaid
graph TD
    subgraph Core ["package:flutter_tools_core (Data Contract)"]
        EP["ExtensionPlugin<br/>(name, path, configuration)"]
        EBT["ExtensionBuildTarget / Target<br/>(pluginPlatformKey)"]
    end

    subgraph Extension ["package:flutter_tools_extension (Service Contract)"]
        EBC["ExtensionBuildContext<br/>(plugins: List<ExtensionPlugin>)"]
        BS["BuildService<br/>(RPC Deserialization)"]
    end

    subgraph Host ["package:flutter_tools (Host Resolution Engine)"]
        CPP["CustomPlatformPlugin<br/>(PluginPlatform implementation)"]
        PR["Plugin Resolution<br/>(_yamlToDart, _yamlMapToMap, resolvePluginImplementationsForPlatform)"]
        EBM["ExtensionBuildManager"]
    end

    subgraph Prototype ["package:flutter_tools_extension_linux_prototype (Native Pipeline)"]
        CLBT["CustomLinuxBuildTarget<br/>(Pre-build injection, CMake & registrant generation)"]
    end

    EBC --> EP
    BS --> EBC
    EBT --> EP
    PR --> CPP
    EBM --> EP
    CLBT --> EBC
    CLBT --> EP

    classDef core fill:#2a9d8f,stroke:#264653,color:#fff;
    classDef ext fill:#e76f51,stroke:#264653,color:#fff;
    classDef host fill:#2b4c7e,stroke:#1d3557,color:#fff;
    classDef proto fill:#6a4c93,stroke:#264653,color:#fff;

    class EP,EBT core;
    class EBC,BS ext;
    class CPP,PR,EBM host;
    class CLBT proto;
```

### Pure Data Model (`ExtensionPlugin`)

Located in [packages/flutter_tools_core/lib/src/build/plugin.dart](file:///usr/local/google/home/bkonyi/.gemini/jetski/worktrees/flutter/resume_handoff_step_08/packages/flutter_tools/packages/flutter_tools_core/lib/src/build/plugin.dart):

```dart
@immutable
class ExtensionPlugin {
  const ExtensionPlugin({
    required this.configuration,
    required this.name,
    required this.path,
  });

  factory ExtensionPlugin.fromJson(Map<String, Object?> json) {
    return ExtensionPlugin(
      configuration: (json['configuration'] as Map<Object?, Object?>?)?.cast<String, Object?>() ?? const <String, Object?>{},
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
    );
  }

  final Map<String, Object?> configuration;
  final String name;
  final String path;

  Map<String, Object?> toMap() => <String, Object?>{
    'configuration': configuration,
    'name': name,
    'path': path,
  };
}
```

---

## 4. Zero Host-Side Platform Assumptions & Generic Custom Plugins

Prior to Step 9, `Plugin._fromMultiPlatformYaml` in `flutter_tools` only recognized standard host platforms:

```dart
// Legacy approach: Unknown platform keys in pubspec.yaml were ignored or dropped
if (key == AndroidPlugin.kConfigKey) { ... }
else if (key == IOSPlugin.kConfigKey) { ... }
else if (key == LinuxPlugin.kConfigKey) { ... }
else if (key == MacOSPlugin.kConfigKey) { ... }
else if (key == WebPlugin.kConfigKey) { ... }
else if (key == WindowsPlugin.kConfigKey) { ... }
```

In Step 9, host parsing was decoupled using [CustomPlatformPlugin](file:///usr/local/google/home/bkonyi/.gemini/jetski/worktrees/flutter/resume_handoff_step_08/packages/flutter_tools/lib/src/platform_plugins.dart#L668-L675):

```dart
class CustomPlatformPlugin extends PluginPlatform {
  const CustomPlatformPlugin({required this.configuration});

  final Map<String, Object?> configuration;

  @override
  Map<String, dynamic> toMap() => configuration;
}
```

And `Plugin._fromMultiPlatformYaml` was updated to capture custom platform entries automatically:

```dart
// Modern approach in package:flutter_tools/src/plugins.dart
} else {
  if (_providesImplementationForPlatform(platformsYaml, key)) {
    platforms[key] = CustomPlatformPlugin(configuration: _yamlMapToMap(value));
  }
}
```

When building for a target platform (e.g., `'linux'` or any custom platform key), `flutter_tools` resolves plugins supporting that key and extracts `platformConfig.toMap()`. The host CLI does not need to understand what keys exist inside `configuration` (e.g. `ffiPlugin`, `pluginClass`, `filename`); it simply forwards the serialized `ExtensionPlugin` map to the extension isolate.

---

## 5. Pre-Build Injection, Symlinking, & Native Build Generation

The extension isolate handles platform-specific build generation without host CLI assistance. For example, in `package:flutter_tools_extension_linux_prototype`:

### 5.1 Transient Plugin Symlinks
Before native build tools are invoked, plugin paths are symlinked into the ephemeral build tree:
```dart
final symlinkDirectory = Directory('${ephemeralDir.path}/.plugin_symlinks');
if (symlinkDirectory.existsSync()) {
  symlinkDirectory.deleteSync(recursive: true);
}
symlinkDirectory.createSync(recursive: true);

for (final ExtensionPlugin plugin in context.plugins) {
  final link = Link('${symlinkDirectory.path}/${plugin.name}');
  link.createSync(plugin.path);
}
```

### 5.2 CMake Integration File Generation
The extension isolate parses each plugin's generic `configuration` map to classify plugin types (Method Channel vs. FFI) and generates `generated_plugins.cmake`:
```cmake
# Generated by extension isolate in ephemeral/generated_plugins.cmake
list(APPEND FLUTTER_PLUGIN_LIST
  url_launcher_linux
)

foreach(plugin ${FLUTTER_PLUGIN_LIST})
  add_subdirectory(flutter/ephemeral/.plugin_symlinks/${plugin}/linux plugins/${plugin})
  target_link_libraries(${BINARY_NAME} PRIVATE ${plugin}_plugin)
endforeach(plugin)
```

### 5.3 Native Registrant Code Generation
The extension generates `generated_plugin_registrant.h` and `generated_plugin_registrant.cc` directly in the project's ephemeral directory:
```cpp
// Generated by extension isolate in ephemeral/generated_plugin_registrant.cc
#include "generated_plugin_registrant.h"
#include <url_launcher_linux/url_launcher_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) url_launcher_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "UrlLauncherPlugin");
  url_launcher_plugin_register_with_registrar(url_launcher_linux_registrar);
}
```

---

## 6. Modern Dart 3 Refactoring in `plugins.dart`

As part of Step 9, legacy YAML conversion helper functions in `packages/flutter_tools/lib/src/plugins.dart` were modernized using Dart 3 switch expressions, type pattern matching, pattern destructuring in `for` loops, and tear-offs.

### Comparison: `_yamlToDart` & `_yamlMapToMap`

#### Legacy Implementation (Pre-Step 9)

```dart
Object? _yamlToDart(Object? value) {
  if (value is YamlMap) {
    return _yamlMapToMap(value);
  }
  if (value is YamlList) {
    return value.map((dynamic e) => _yamlToDart(e)).toList();
  }
  return value;
}

Map<String, Object?> _yamlMapToMap(YamlMap map) {
  final result = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in map.entries) {
    final Object? key = entry.key;
    if (key is String) {
      final Object? value = entry.value;
      result[key] = _yamlToDart(value);
    }
  }
  return result;
}
```

#### Modernized Dart 3 Implementation (Step 9)

```dart
Object? _yamlToDart(Object? value) => switch (value) {
  YamlMap() => _yamlMapToMap(value),
  YamlList() => value.map(_yamlToDart).toList(),
  _ => value,
};

Map<String, Object?> _yamlMapToMap(YamlMap map) => <String, Object?>{
  for (final MapEntry<Object?, Object?>(:key, :value) in map.entries)
    if (key is String) key: _yamlToDart(value),
};
```

### Improvements
1. **Switch Expressions**: Replaces explicit `if (value is T)` chains with a concise expression-bodied switch expression.
2. **Type Pattern Matching**: `YamlMap()` and `YamlList()` patterns handle type checking cleanly.
3. **Tear-offs**: `value.map(_yamlToDart)` replaces redundant closure lambdas (`(dynamic e) => _yamlToDart(e)`).
4. **Pattern Destructuring in Collection For**: `for (final MapEntry<Object?, Object?>(:key, :value) in map.entries)` uses property extraction pattern matching directly in a collection literal map comprehension.

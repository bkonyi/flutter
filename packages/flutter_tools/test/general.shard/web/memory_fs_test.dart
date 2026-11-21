// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/web/memory_fs.dart';

import '../../src/common.dart';

void main() {
  testWithoutContext('correctly parses source, source map, metadata, manifest files', () {
    final fileSystem = MemoryFileSystem();
    final File source = fileSystem.file('source')..writeAsStringSync('main() {}');
    final File sourcemap = fileSystem.file('sourcemap')..writeAsStringSync('{}');
    final File metadata = fileSystem.file('metadata')..writeAsStringSync('{}');
    final File manifest = fileSystem.file('manifest')
      ..writeAsStringSync(
        json.encode(<String, Object>{
          '/foo.js': <String, Object>{
            'code': <int>[0, source.lengthSync()],
            'sourcemap': <int>[0, 2],
            'metadata': <int>[0, 2],
          },
        }),
      );
    final webMemoryFS = WebMemoryFS();
    webMemoryFS.write(source, manifest, sourcemap, metadata);

    expect(utf8.decode(webMemoryFS.files['foo.js']!), 'main() {}');
    expect(utf8.decode(webMemoryFS.sourcemaps['foo.js.map']!), '{}');
    expect(utf8.decode(webMemoryFS.metadataFiles['foo.js.metadata']!), '{}');
    expect(webMemoryFS.mergedMetadata, '{}');
  });

  testWithoutContext('skips modules whose manifest offsets are malformed', () {
    final fileSystem = MemoryFileSystem();
    final File source = fileSystem.file('source')..writeAsStringSync('main() {}');
    final File sourcemap = fileSystem.file('sourcemap')..writeAsStringSync('{}');
    final File metadata = fileSystem.file('metadata')..writeAsStringSync('{}');
    final File manifest = fileSystem.file('manifest')
      ..writeAsStringSync(
        json.encode(<String, Object>{
          '/good.js': <String, Object>{
            'code': <int>[0, source.lengthSync()],
            'sourcemap': <int>[0, 2],
            'metadata': <int>[0, 2],
          },
          '/not_ints.js': <String, Object>{
            'code': <Object>['0', source.lengthSync()],
            'sourcemap': <int>[0, 2],
            'metadata': <int>[0, 2],
          },
          '/wrong_length.js': <String, Object>{
            'code': <int>[0],
            'sourcemap': <int>[0, 2],
            'metadata': <int>[0, 2],
          },
          '/missing_key.js': <String, Object>{
            'code': <int>[0, source.lengthSync()],
            'sourcemap': <int>[0, 2],
          },
          '/not_a_map.js': 'nope',
        }),
      );
    final webMemoryFS = WebMemoryFS();
    final List<String> modules = webMemoryFS.write(source, manifest, sourcemap, metadata);

    expect(modules, <String>['good.js']);
    expect(webMemoryFS.files.keys, <String>['good.js']);
    expect(webMemoryFS.sourcemaps.keys, <String>['good.js.map']);
    expect(webMemoryFS.metadataFiles.keys, <String>['good.js.metadata']);
  });

  testWithoutContext('increments revision on write and incrementRevision', () {
    final fileSystem = MemoryFileSystem();
    final File source = fileSystem.file('source')..writeAsStringSync('main() {}');
    final File sourcemap = fileSystem.file('sourcemap')..writeAsStringSync('{}');
    final File metadata = fileSystem.file('metadata')..writeAsStringSync('{}');
    final File manifest = fileSystem.file('manifest')
      ..writeAsStringSync(
        json.encode(<String, Object>{
          '/foo.js': <String, Object>{
            'code': <int>[0, source.lengthSync()],
            'sourcemap': <int>[0, 2],
            'metadata': <int>[0, 2],
          },
        }),
      );
    final webMemoryFS = WebMemoryFS();
    expect(webMemoryFS.revision, 0);

    webMemoryFS.write(source, manifest, sourcemap, metadata);
    expect(webMemoryFS.revision, 1);
    expect(webMemoryFS.moduleRevisions, <String, int>{'foo.js': 1});

    // Re-writing identical bytes does not bump revision or mark modules changed.
    webMemoryFS.write(source, manifest, sourcemap, metadata);
    expect(webMemoryFS.revision, 1);
    expect(webMemoryFS.moduleRevisions, <String, int>{'foo.js': 1});

    // Writing an empty manifest (no-op recompile) does not bump revision.
    final File emptyManifest = fileSystem.file('empty_manifest')..writeAsStringSync('{}');
    webMemoryFS.write(source, emptyManifest, sourcemap, metadata);
    expect(webMemoryFS.revision, 1);

    // Updating only one of two modules bumps revision once and only updates the changed module's revision.
    final File twoSources = fileSystem.file('two_sources')
      ..writeAsStringSync('main() {}bar() { return 1; }');
    final File twoSourcemap = fileSystem.file('two_sourcemap')..writeAsStringSync('{}{}');
    final File twoMetadata = fileSystem.file('two_metadata')..writeAsStringSync('{}{}');
    final File twoManifest = fileSystem.file('two_manifest')
      ..writeAsStringSync(
        json.encode(<String, Object>{
          '/foo.js': <String, Object>{
            'code': <int>[0, 9],
            'sourcemap': <int>[0, 2],
            'metadata': <int>[0, 2],
          },
          '/bar.js': <String, Object>{
            'code': <int>[9, twoSources.lengthSync()],
            'sourcemap': <int>[2, 4],
            'metadata': <int>[2, 4],
          },
        }),
      );
    webMemoryFS.write(twoSources, twoManifest, twoSourcemap, twoMetadata);
    expect(webMemoryFS.revision, 2);
    expect(webMemoryFS.moduleRevisions, <String, int>{'foo.js': 1, 'bar.js': 2});

    // writeFileBytes skips identical content and honors trackRevision: false.
    webMemoryFS.writeFileBytes('foo.js', Uint8List.fromList(utf8.encode('main() {}')));
    expect(webMemoryFS.revision, 2);
    webMemoryFS.writeFileBytes(
      'reloaded_sources.json',
      Uint8List.fromList(utf8.encode('[]')),
      trackRevision: false,
    );
    expect(utf8.decode(webMemoryFS.files['reloaded_sources.json']!), '[]');
    expect(webMemoryFS.revision, 2);
    expect(webMemoryFS.moduleRevisions.containsKey('reloaded_sources.json'), isFalse);

    webMemoryFS.incrementRevision();
    expect(webMemoryFS.revision, 3);
  });
}

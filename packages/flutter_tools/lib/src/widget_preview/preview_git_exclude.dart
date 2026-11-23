// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import '../base/file_system.dart';
import '../base/logger.dart';
import '../convert.dart';

const _kCommonDirFileName = 'commondir';
const _kExcludeFileName = 'exclude';
const _kGitDirEntry = '.git';
const _kGitDirPrefix = 'gitdir:';
const _kInfoDirName = 'info';
const _kWidgetPreviewExcludeEntry = '.widget_preview/';
const _kWidgetPreviewExcludeName = '.widget_preview';

/// Ensures `.widget_preview/` is excluded in `$GIT_COMMON_DIR/info/exclude` when
/// running headless widget preview commands so tracked `.gitignore` files are
/// not modified.
void ensureWidgetPreviewGitExclude({required Directory projectDirectory, required Logger logger}) {
  final FileSystem fs = projectDirectory.fileSystem;
  final Directory? gitCommonDir = _resolveGitCommonDir(projectDirectory: projectDirectory, fs: fs);
  if (gitCommonDir == null || !gitCommonDir.existsSync()) {
    return;
  }

  try {
    final Directory infoDir = gitCommonDir.childDirectory(_kInfoDirName)
      ..createSync(recursive: true);
    final File excludeFile = infoDir.childFile(_kExcludeFileName);
    if (!excludeFile.existsSync()) {
      excludeFile.writeAsStringSync('$_kWidgetPreviewExcludeEntry\n');
      return;
    }

    final String originalContent = excludeFile.readAsStringSync();
    final bool alreadyExcluded = LineSplitter.split(originalContent)
        .any((String line) => _normalizeExcludeEntry(line) == _kWidgetPreviewExcludeName);
    if (alreadyExcluded) {
      return;
    }

    final buffer = StringBuffer(originalContent);
    if (originalContent.isNotEmpty && !originalContent.endsWith('\n')) {
      buffer.writeln();
    }
    buffer.writeln(_kWidgetPreviewExcludeEntry);
    excludeFile.writeAsStringSync(buffer.toString());
  } on FileSystemException catch (error) {
    logger.printTrace('Failed to update Git info/exclude for widget preview: $error');
  }
}

String _normalizeExcludeEntry(String line) {
  String trimmed = line.trim();
  while (trimmed.startsWith('/')) {
    trimmed = trimmed.substring(1);
  }
  while (trimmed.endsWith('/')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

Directory? _resolveGitCommonDir({required Directory projectDirectory, required FileSystem fs}) {
  Directory current = projectDirectory.absolute;
  while (true) {
    final Directory dotGitDir = current.childDirectory(_kGitDirEntry);
    if (dotGitDir.existsSync()) {
      return dotGitDir;
    }

    final File dotGitFile = current.childFile(_kGitDirEntry);
    if (dotGitFile.existsSync()) {
      final String content;
      try {
        content = dotGitFile.readAsStringSync().trim();
      } on FileSystemException {
        return null;
      }
      if (!content.startsWith(_kGitDirPrefix)) {
        return null;
      }
      final String rawGitDir = content.substring(_kGitDirPrefix.length).trim();
      if (rawGitDir.isEmpty) {
        return null;
      }
      final Directory gitDir = fs.directory(
        fs.path.isAbsolute(rawGitDir)
            ? rawGitDir
            : fs.path.normalize(fs.path.join(current.path, rawGitDir)),
      );
      final File commonDirFile = gitDir.childFile(_kCommonDirFileName);
      if (!commonDirFile.existsSync()) {
        return gitDir;
      }
      final String rawCommonDir;
      try {
        rawCommonDir = commonDirFile.readAsStringSync().trim();
      } on FileSystemException {
        return gitDir;
      }
      if (rawCommonDir.isEmpty) {
        return gitDir;
      }
      return fs.directory(
        fs.path.isAbsolute(rawCommonDir)
            ? rawCommonDir
            : fs.path.normalize(fs.path.join(gitDir.path, rawCommonDir)),
      );
    }

    final Directory parent = current.parent;
    if (parent.path == current.path) {
      return null;
    }
    current = parent;
  }
}

// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:path/path.dart' as path;
import 'package:widget_preview_scaffold/src/widget_preview_rendering.dart';
import 'dtd/dtd_services.dart';
import 'widget_preview.dart';

/// Result of resolving a preview identifier or unique shorthand name against
/// discovered widget previews.
sealed class PreviewLookupResult {
  const PreviewLookupResult();
}

/// Successful resolution of a single [WidgetPreview].
final class PreviewLookupMatch extends PreviewLookupResult {
  const PreviewLookupMatch(this.preview);

  final WidgetPreview preview;
}

/// Resolution failure when no preview matched [previewId] (or none was given).
final class PreviewLookupMissing extends PreviewLookupResult {
  const PreviewLookupMissing({required this.availableIds, this.previewId});

  final List<String> availableIds;
  final String? previewId;
}

/// Resolution failure when a shorthand [previewId] matched multiple previews.
final class PreviewLookupAmbiguous extends PreviewLookupResult {
  const PreviewLookupAmbiguous({
    required this.candidateIds,
    required this.previewId,
  });

  final List<String> candidateIds;
  final String previewId;
}

/// Define the Enum for Layout Types
enum LayoutType { gridView, listView }

typedef WidgetPreviews = Iterable<WidgetPreview>;
typedef WidgetPreviewGroups = Iterable<WidgetPreviewGroup>;
typedef PreviewsCallback = WidgetPreviews Function();

/// Controller used to process events and determine which previews should be
/// displayed and how they should be displayed in the [WidgetPreviewScaffold].
class WidgetPreviewScaffoldController {
  WidgetPreviewScaffoldController({
    required this._previews,
    @visibleForTesting WidgetPreviewScaffoldDtdServices? dtdServicesOverride,
  }) : dtdServices = dtdServicesOverride ?? WidgetPreviewScaffoldDtdServices() {
    _context = _createPathContext();
    _refreshPreviewsSnapshot();
    dtdServices.onGetPreviews = getPreviews;
  }

  static const _kCanonicalIdSeparator = '::';

  @visibleForTesting
  static const kFilterBySelectedFilePreference = 'filterBySelectedFile';

  /// Initializes the controller by establishing a connection to DTD and
  /// listening for events.
  Future<void> initialize() async {
    await dtdServices.connect();
    _context = _createPathContext();
    _registerListeners();
    await Future.wait<void>([
      dtdServices
          .getFlag(kFilterBySelectedFilePreference, defaultValue: true)
          .then((value) => _filterBySelectedFile.value = value),
      dtdServices.getDevToolsUri().then((uri) {
        devToolsUri = uri;
      }),
    ]);
  }

  /// Cleanup internal controller state.
  Future<void> dispose() async {
    await dtdServices.dispose();
    clearAllDiagnostics();
    _liveDiagnosticPruners.clear();

    _layoutType.dispose();
    _filterBySelectedFile.dispose();
    _searchQuery.dispose();
    _previewsRevision.dispose();
    for (final searchField in _searchFields) {
      searchField.dispose();
    }
  }

  /// Update state after the project has been reassembled due to a hot reload.
  void onHotReload() {
    _refreshPreviewsSnapshot();
    clearAllDiagnostics();
    _updateFilteredPreviewSet();
    _previewsRevision.value++;
  }

  /// The active DTD connection used to communicate with other developer tooling.
  final WidgetPreviewScaffoldDtdServices dtdServices;

  final PreviewsCallback _previews;
  var _cachedPreviews = const <WidgetPreview>[];
  var _cachedPreviewGroups = const <WidgetPreviewGroup>[];

  void _refreshPreviewsSnapshot() {
    _cachedPreviews = List<WidgetPreview>.unmodifiable(_previews());
    _cachedPreviewGroups = _groupPreviews(_cachedPreviews);
  }

  static List<WidgetPreviewGroup> _groupPreviews(
    Iterable<WidgetPreview> previews,
  ) {
    final previewGroups = <String, List<WidgetPreview>>{};
    for (final WidgetPreview preview in previews) {
      previewGroups
          .putIfAbsent(preview.previewData.group, () => <WidgetPreview>[])
          .add(preview);
    }
    return List<WidgetPreviewGroup>.unmodifiable(<WidgetPreviewGroup>[
      for (final MapEntry(:String key, :List<WidgetPreview> value)
          in previewGroups.entries)
        WidgetPreviewGroup(
          name: key,
          previews: List<WidgetPreview>.unmodifiable(value),
        ),
    ]);
  }

  /// All unfiltered [WidgetPreview] instances currently defined in the project.
  WidgetPreviews get previews => _cachedPreviews;

  /// All unfiltered [WidgetPreviewGroup]s currently defined in the project.
  List<WidgetPreviewGroup> get allPreviewGroups => _cachedPreviewGroups;

  late path.Context _context;
  path.Context get context => _context;

  path.Context _createPathContext() => path.Context(
    style: dtdServices.isWindows ? path.Style.windows : path.Style.posix,
  );

  final Map<WidgetPreview, _PreviewDiagnosticsState> _diagnosticsByPreview =
      Map<WidgetPreview, _PreviewDiagnosticsState>.identity();
  final Map<WidgetPreview, VoidCallback> _liveDiagnosticPruners =
      Map<WidgetPreview, VoidCallback>.identity();

  /// Registers a callback invoked on-demand by [diagnosticsFor] to prune stale
  /// build/paint diagnostics when a mounted preview subtree has recovered.
  void registerDiagnosticPruner(
    WidgetPreview preview,
    VoidCallback pruneStaleDiagnostics,
  ) {
    _liveDiagnosticPruners[preview] = pruneStaleDiagnostics;
  }

  /// Unregisters the diagnostic pruner for [preview] if it matches [pruner].
  void unregisterDiagnosticPruner(WidgetPreview preview, VoidCallback pruner) {
    if (identical(_liveDiagnosticPruners[preview], pruner)) {
      _liveDiagnosticPruners.remove(preview);
    }
  }

  /// Records a runtime [diagnostic] for [preview], deduplicating identical
  /// entries within the same phase.
  void recordDiagnostic(WidgetPreview preview, PreviewDiagnostic diagnostic) {
    final _PreviewDiagnosticsState state = _diagnosticsByPreview.putIfAbsent(
      preview,
      _PreviewDiagnosticsState.new,
    );
    state.add(diagnostic);
  }

  /// Clears captured runtime diagnostics for [preview] in [phase].
  ///
  /// When [preserveOverflow] is `true`, `RenderFlex` overflow diagnostics are
  /// retained across incremental paints until the render subtree stops
  /// overflowing or is reassembled.
  void clearPhaseDiagnostics(
    WidgetPreview preview,
    PreviewDiagnosticPhase phase, {
    bool preserveOverflow = false,
  }) {
    final _PreviewDiagnosticsState? state = _diagnosticsByPreview[preview];
    if (state == null) {
      return;
    }
    state.clearPhase(phase, preserveOverflow: preserveOverflow);
    if (state.isEmpty) {
      _diagnosticsByPreview.remove(preview);
    }
  }

  /// Clears `RenderFlex` paint overflow diagnostics for [preview] once no
  /// descendant `RenderFlex` remains in an overflowing state.
  void clearRenderFlexOverflowDiagnostics(WidgetPreview preview) {
    final _PreviewDiagnosticsState? state = _diagnosticsByPreview[preview];
    if (state == null) {
      return;
    }
    state.clearRenderFlexOverflows();
    if (state.isEmpty) {
      _diagnosticsByPreview.remove(preview);
    }
  }

  /// Clears all captured runtime diagnostics for [preview].
  void clearDiagnosticsFor(WidgetPreview preview) {
    _diagnosticsByPreview.remove(preview);
  }

  /// Clears all captured runtime diagnostics across all previews.
  void clearAllDiagnostics() {
    _diagnosticsByPreview.clear();
  }

  /// Returns all active compile and runtime [PreviewDiagnostic]s for [preview].
  List<PreviewDiagnostic> diagnosticsFor(WidgetPreview preview) {
    _liveDiagnosticPruners[preview]?.call();
    final _PreviewDiagnosticsState? state = _diagnosticsByPreview[preview];
    return <PreviewDiagnostic>[
      if (preview.hasError)
        PreviewDiagnostic(
          kind: .compileError,
          phase: .compile,
          summary: preview.errorMessage ?? '${preview.libraryUri} has errors!',
        ),
      if (state != null) ...state.all,
    ];
  }

  /// Builds a [PreviewListResponse] across unfiltered [previews], optionally
  /// filtered by [fileUri] (`scriptUri` or `libraryUri`), ignoring UI-only
  /// selected-file and search filters.
  PreviewListResponse getPreviews({String? fileUri}) {
    final entries = <PreviewEntry>[];
    for (final WidgetPreview preview in _cachedPreviews) {
      if (fileUri != null &&
          fileUri.isNotEmpty &&
          !_matchesFileUri(
            fileUri: fileUri,
            libraryUri: preview.libraryUri,
            pathContext: _context,
            scriptUri: preview.scriptUri,
          )) {
        continue;
      }
      final List<PreviewDiagnostic> diagnostics = diagnosticsFor(preview);
      final bool hasError = preview.hasError || diagnostics.isNotEmpty;
      final String? errorMessage = preview.hasError
          ? preview.errorMessage
          : (diagnostics.isNotEmpty
                ? diagnostics.map((PreviewDiagnostic d) => d.summary).join('\n')
                : null);
      entries.add(
        PreviewEntry(
          brightness: preview.brightness?.name,
          column: preview.column,
          errorMessage: errorMessage,
          functionName: preview.functionName,
          group: preview.previewData.group,
          hasError: hasError,
          height: preview.finiteHeight,
          id: preview.id,
          libraryUri: preview.libraryUri,
          line: preview.line,
          multiPreviewIndex: preview.multiPreviewIndex,
          name: preview.name,
          packageName: preview.packageName,
          scriptUri: preview.scriptUri,
          textScaleFactor: preview.finiteTextScaleFactor,
          width: preview.finiteWidth,
        ),
      );
    }
    return PreviewListResponse(previews: entries);
  }

  /// Resolves [previewId] against all unfiltered [previews] without throwing.
  PreviewLookupResult resolvePreviewMatch(String? previewId) {
    if (previewId == null || previewId.isEmpty) {
      return PreviewLookupMissing(
        availableIds: <String>[
          for (final WidgetPreview preview in _cachedPreviews) preview.id,
        ],
      );
    }
    for (final WidgetPreview preview in _cachedPreviews) {
      if (preview.id == previewId) {
        return PreviewLookupMatch(preview);
      }
    }
    if (!previewId.contains(_kCanonicalIdSeparator)) {
      final nameMatches = <WidgetPreview>[
        for (final WidgetPreview preview in _cachedPreviews)
          if (preview.previewData.name == previewId) preview,
      ];
      if (nameMatches.length == 1) {
        return PreviewLookupMatch(nameMatches.single);
      }
      if (nameMatches.length > 1) {
        return PreviewLookupAmbiguous(
          candidateIds: <String>[
            for (final WidgetPreview preview in nameMatches) preview.id,
          ],
          previewId: previewId,
        );
      }
    }
    return PreviewLookupMissing(
      availableIds: <String>[
        for (final WidgetPreview preview in _cachedPreviews) preview.id,
      ],
      previewId: previewId,
    );
  }

  /// Resolves [previewId] against all unfiltered [previews].
  ///
  /// Matches canonical [WidgetPreview.id] first, falling back to a unique
  /// `previewData.name` match when [previewId] does not contain `'::'`.
  /// Throws an [RpcException] with code `101` when no preview matches or code
  /// `102` listing candidate canonical IDs when a shorthand name is ambiguous.
  WidgetPreview resolvePreview(String previewId) {
    return switch (resolvePreviewMatch(previewId)) {
      PreviewLookupMatch(:final WidgetPreview preview) => preview,
      PreviewLookupAmbiguous(:final List<String> candidateIds) =>
        throw RpcException(
          WidgetPreviewScaffoldDtdServices.kAmbiguousPreviewNameErrorCode,
          'Preview name "$previewId" is ambiguous; specify one of: '
          '${candidateIds.join(', ')}',
        ),
      PreviewLookupMissing(:final List<String> availableIds) =>
        throw RpcException(
          WidgetPreviewScaffoldDtdServices.kPreviewNotFoundErrorCode,
          'Preview "$previewId" not found. Available IDs: '
          '${availableIds.join(', ')}',
        ),
    };
  }

  /// Specifies how the previews should be laid out.
  ValueListenable<LayoutType> get layoutTypeListenable => _layoutType;
  final _layoutType = ValueNotifier<LayoutType>(LayoutType.gridView);

  LayoutType get layoutType => _layoutType.value;
  set layoutType(LayoutType type) => _layoutType.value = type;

  /// Set to true when the Editor service is available over DTD.
  ValueListenable<bool> get editorServiceAvailable =>
      dtdServices.editorServiceAvailable;

  /// Monotonically incremented whenever [onHotReload] refreshes [previews].
  ValueListenable<int> get previewsRevisionListenable => _previewsRevision;
  final _previewsRevision = ValueNotifier<int>(0);

  /// The DevTools instance that's used to display the widget inspector within the previewer.
  late Uri devToolsUri;

  /// Specifies if only previews from the currently selected source file should be rendered.
  ValueListenable<bool> get filterBySelectedFileListenable =>
      _filterBySelectedFile;
  final _filterBySelectedFile = ValueNotifier<bool>(true);

  /// Enable or disable filtering by selected source file.
  Future<void> toggleFilterBySelectedFile() async {
    final updated = !_filterBySelectedFile.value;
    await dtdServices.setPreference(kFilterBySelectedFilePreference, updated);
    _filterBySelectedFile.value = updated;
  }

  /// The current case-insensitive query used to search previews.
  ValueListenable<String> get searchQueryListenable => _searchQuery;
  final _searchQuery = ValueNotifier<String>('');

  /// Update the search query used to filter previews.
  void updateSearchQuery(String query) => _searchQuery.value = query;

  /// Whether to include group names when applying search filters.
  ValueListenable<bool> get searchByGroupNameListenable => _searchByGroupName;
  final _searchByGroupName = ValueNotifier<bool>(true);

  /// Whether to include preview names when applying search filters.
  ValueListenable<bool> get searchByPreviewNameListenable =>
      _searchByPreviewName;
  final _searchByPreviewName = ValueNotifier<bool>(true);

  /// Whether to include script URIs when applying search filters.
  ValueListenable<bool> get searchByContainingScriptListenable =>
      _searchByContainingScript;
  final _searchByContainingScript = ValueNotifier<bool>(true);

  /// Whether to include package names when applying search filters.
  ValueListenable<bool> get searchByContainingPackageListenable =>
      _searchByContainingPackage;
  final _searchByContainingPackage = ValueNotifier<bool>(true);

  /// Toggle inclusion of group names in search filters.
  ///
  /// Returns true if the filter state was changed.
  bool toggleSearchByGroupName() => _toggleSearchField(_searchByGroupName);

  /// Toggle inclusion of preview names in search filters.
  ///
  /// Returns true if the filter state was changed.
  bool toggleSearchByPreviewName() => _toggleSearchField(_searchByPreviewName);

  /// Toggle inclusion of script URIs in search filters.
  ///
  /// Returns true if the filter state was changed.
  bool toggleSearchByContainingScript() =>
      _toggleSearchField(_searchByContainingScript);

  /// Toggle inclusion of package names in search filters.
  ///
  /// Returns true if the filter state was changed.
  bool toggleSearchByContainingPackage() =>
      _toggleSearchField(_searchByContainingPackage);

  /// Specifies if the DevTools Widget Inspector should be visible.
  ValueListenable<bool> get widgetInspectorVisible => _widgetInspectorVisible;
  final _widgetInspectorVisible = ValueNotifier<bool>(false);

  /// Enable or disable the DevTools Widget Inspector.
  void toggleWidgetInspectorVisible() =>
      _widgetInspectorVisible.value = !_widgetInspectorVisible.value;

  /// The current set of previews to be displayed.
  ValueListenable<WidgetPreviewGroups> get filteredPreviewSetListenable =>
      _filteredPreviewSet;
  final _filteredPreviewSet = ValueNotifier<WidgetPreviewGroups>([]);

  void _registerListeners() {
    dtdServices.selectedSourceFile.addListener(_updateFilteredPreviewSet);
    editorServiceAvailable.addListener(
      () => _updateFilteredPreviewSet(editorServiceAvailabilityUpdated: true),
    );
    filterBySelectedFileListenable.addListener(_updateFilteredPreviewSet);
    searchQueryListenable.addListener(_updateFilteredPreviewSet);
    for (final searchField in _searchFields) {
      searchField.addListener(_updateFilteredPreviewSet);
    }
    // Set the initial state.
    _updateFilteredPreviewSet();
  }

  late final _searchFields = <ValueNotifier<bool>>[
    _searchByGroupName,
    _searchByPreviewName,
    _searchByContainingScript,
    _searchByContainingPackage,
  ];

  String _getSearchableValue(
    WidgetPreview preview,
    ValueNotifier<bool> searchField,
  ) {
    if (identical(searchField, _searchByGroupName)) {
      return preview.previewData.group.toLowerCase();
    }
    if (identical(searchField, _searchByPreviewName)) {
      return (preview.name ?? '').toLowerCase();
    }
    if (identical(searchField, _searchByContainingScript)) {
      return preview.scriptUri.toLowerCase();
    }
    if (identical(searchField, _searchByContainingPackage)) {
      return preview.packageName.toLowerCase();
    }

    throw StateError('Unknown search field');
  }

  bool _toggleSearchField(ValueNotifier<bool> searchField) {
    if (searchField.value && !_hasAnotherActiveSearchField(searchField)) {
      return false;
    }
    searchField.value = !searchField.value;
    return true;
  }

  bool _hasAnotherActiveSearchField(ValueNotifier<bool> activeSearchField) =>
      _searchFields.any(
        (field) => !identical(field, activeSearchField) && field.value,
      );

  bool _matchesSearchFilter(WidgetPreview preview, String searchQuery) {
    if (searchQuery.isEmpty) {
      return true;
    }

    for (final searchField in _searchFields) {
      if (!searchField.value) {
        continue;
      }
      if (_getSearchableValue(preview, searchField).contains(searchQuery)) {
        return true;
      }
    }

    return false;
  }

  void _updateFilteredPreviewSet({
    bool editorServiceAvailabilityUpdated = false,
  }) {
    final normalizedSearchQuery = _searchQuery.value.trim().toLowerCase();
    String? selectedSourcePath;

    if (editorServiceAvailable.value && _filterBySelectedFile.value) {
      final selectedSourceFile = dtdServices.selectedSourceFile.value;
      // If the Editor service has only just become available and we're filtering
      // by selected file, we need to explicitly set the filtered preview set as
      // empty, otherwise `selectedSourceFile` will interpreted as a non-source
      // file being selected in the editor.
      if (editorServiceAvailabilityUpdated && selectedSourceFile == null) {
        _filteredPreviewSet.value = [];
        return;
      }
      // If filtering by selected file, we don't update the filtered preview set
      // if the currently selected file is null. This can happen when a non-source
      // window is selected (e.g., the widget previewer itself in VSCode), so we
      // ignore these updates.
      if (selectedSourceFile == null) {
        return;
      }
      // Convert to a file path for comparing to avoid issues with optional encoding in URIs.
      // See https://github.com/flutter/flutter/issues/175524.
      selectedSourcePath = context.fromUri(selectedSourceFile.uriAsString);
    }

    final filteredPreviews = <WidgetPreview>[];
    for (final preview in _cachedPreviews) {
      if (selectedSourcePath != null &&
          !context.equals(
            // TODO(bkonyi): we can probably save some cycles by caching the file path
            // rather than computing it on each filter.
            context.fromUri(preview.scriptUri),
            selectedSourcePath,
          )) {
        continue;
      }
      if (!_matchesSearchFilter(preview, normalizedSearchQuery)) {
        continue;
      }
      filteredPreviews.add(preview);
    }
    _filteredPreviewSet.value = _groupPreviews(filteredPreviews);
  }

  static bool _matchesFileUri({
    required String fileUri,
    required String libraryUri,
    required path.Context pathContext,
    required String scriptUri,
  }) {
    if (libraryUri == fileUri || scriptUri == fileUri) {
      return true;
    }
    final Uri? parsedScript = Uri.tryParse(scriptUri);
    if (parsedScript == null || !parsedScript.isScheme('file')) {
      return false;
    }
    final String scriptPath = pathContext.fromUri(parsedScript);
    final Uri? parsedFilter = Uri.tryParse(fileUri);
    if (parsedFilter != null && parsedFilter.isScheme('file')) {
      return pathContext.equals(scriptPath, pathContext.fromUri(parsedFilter));
    }
    if (!fileUri.startsWith('package:') && !fileUri.startsWith('dart:')) {
      return pathContext.equals(scriptPath, pathContext.normalize(fileUri));
    }
    return false;
  }
}

class _PreviewDiagnosticsState {
  final build = <PreviewDiagnostic>[];
  final layout = <PreviewDiagnostic>[];
  final paint = <PreviewDiagnostic>[];

  bool get isEmpty => build.isEmpty && layout.isEmpty && paint.isEmpty;

  Iterable<PreviewDiagnostic> get all sync* {
    yield* build;
    yield* layout;
    yield* paint;
  }

  void add(PreviewDiagnostic diagnostic) {
    final List<PreviewDiagnostic> bucket = switch (diagnostic.phase) {
      .compile || .build => build,
      .layout => layout,
      .paint => paint,
    };
    if (!bucket.contains(diagnostic)) {
      bucket.add(diagnostic);
    }
  }

  void clearPhase(
    PreviewDiagnosticPhase phase, {
    bool preserveOverflow = false,
  }) {
    switch (phase) {
      case .compile || .build:
        build.clear();
      case .layout:
        layout.clear();
      case .paint:
        if (preserveOverflow) {
          paint.removeWhere(
            (PreviewDiagnostic d) => d.kind != PreviewDiagnosticKind.overflow,
          );
        } else {
          paint.clear();
        }
    }
  }

  void clearRenderFlexOverflows() {
    paint.removeWhere(
      (PreviewDiagnostic d) =>
          d.kind == PreviewDiagnosticKind.overflow &&
          d.targetType == 'RenderFlex',
    );
  }
}

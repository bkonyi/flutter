// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Builds the self-contained HTML/CSS/ES2022 interactive shell served at `/live`.
String buildWidgetPreviewLiveShellHtml({required String projectRoot}) {
  final String escapedRoot = _escapeHtml(projectRoot);
  return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Flutter Widget Preview - $escapedRoot</title>
  <style>
    :root {
      color-scheme: light dark;
      --bg: #111318;
      --surface: #1b1f27;
      --border: #2c3340;
      --text: #e6eaf2;
      --muted: #98a2b3;
      --accent: #3b82f6;
      --danger-bg: #3b1219;
      --danger-border: #ef4444;
      --danger-text: #fecaca;
    }
    * { box-sizing: border-box; }
    html, body {
      margin: 0;
      padding: 0;
      height: 100%;
      background: var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      font-size: 13px;
    }
    body {
      display: flex;
      flex-direction: column;
    }
    .toolbar {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 8px;
      padding: 8px 12px;
      background: var(--surface);
      border-bottom: 1px solid var(--border);
    }
    .toolbar select,
    .toolbar button,
    .selection-bar button {
      height: 30px;
      padding: 0 10px;
      border-radius: 6px;
      border: 1px solid var(--border);
      background: var(--bg);
      color: var(--text);
      font-size: 12px;
      cursor: pointer;
    }
    .toolbar select {
      min-width: 220px;
      max-width: 420px;
    }
    .toolbar button.active {
      border-color: var(--accent);
      background: color-mix(in srgb, var(--accent) 20%, var(--bg));
    }
    .toolbar button:disabled,
    .selection-bar button:disabled {
      opacity: 0.6;
      cursor: not-allowed;
    }
    #sync-btn:disabled {
      cursor: wait;
    }
    .spacer {
      flex: 1;
    }
    .status {
      color: var(--muted);
      font-size: 12px;
    }
    .error-banner {
      padding: 8px 12px;
      background: var(--danger-bg);
      border-bottom: 1px solid var(--danger-border);
      color: var(--danger-text);
      white-space: pre-wrap;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 12px;
      max-height: 160px;
      overflow: auto;
    }
    .stage {
      flex: 1;
      display: flex;
      justify-content: center;
      align-items: stretch;
      padding: 0;
      overflow: auto;
      background: var(--bg);
    }
    .stage.constrained {
      padding: 16px;
    }
    iframe {
      width: 100%;
      height: 100%;
      border: 0;
      background: #ffffff;
    }
    .stage.constrained iframe {
      border: 1px solid var(--border);
      border-radius: 8px;
      box-shadow: 0 8px 28px rgba(0, 0, 0, 0.35);
    }
    .selection-bar {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 8px;
      padding: 8px 12px;
      background: var(--surface);
      border-top: 1px solid var(--border);
    }
    .selection-bar[hidden] {
      display: none;
    }
    .selection-chips {
      display: flex;
      flex: 1;
      flex-wrap: wrap;
      align-items: center;
      gap: 6px;
      min-width: 0;
    }
    .selection-chip {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      height: 26px;
      padding: 0 8px;
      border-radius: 999px;
      border: 1px solid color-mix(in srgb, var(--accent) 55%, var(--border));
      background: color-mix(in srgb, var(--accent) 16%, var(--bg));
      color: var(--text);
      font-size: 12px;
      max-width: 320px;
    }
    .selection-chip-label {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .selection-chip button.selection-chip-remove {
      height: 18px;
      width: 18px;
      padding: 0;
      border: 0;
      border-radius: 999px;
      background: transparent;
      color: var(--text);
      font-size: 14px;
      line-height: 1;
      cursor: pointer;
    }
    .selection-chip button.selection-chip-remove:hover {
      background: color-mix(in srgb, var(--accent) 32%, transparent);
    }
    .selection-actions {
      display: flex;
      align-items: center;
      gap: 8px;
    }
  </style>
</head>
<body>
  <header class="toolbar">
    <select id="preview-select" aria-label="Select preview">
      <option value="*">All Previews (0)</option>
    </select>
    <button id="theme-toggle" type="button">Light</button>
    <button class="width-btn active" data-width="" type="button">Responsive</button>
    <button class="width-btn" data-width="375" type="button">375px</button>
    <button class="width-btn" data-width="768" type="button">768px</button>
    <button id="zoom-out" type="button" title="Zoom out" aria-label="Zoom out">-</button>
    <button id="zoom-reset" type="button" title="Reset zoom" aria-label="Reset zoom">100%</button>
    <button id="zoom-in" type="button" title="Zoom in" aria-label="Zoom in">+</button>
    <button id="select-toggle" type="button" title="Select regions in preview (or hold Shift + drag)">Select</button>
    <button id="sync-btn" type="button">Sync Reload</button>
    <span class="spacer"></span>
    <span id="status-text" class="status">Connecting...</span>
  </header>
  <div id="error-banner" class="error-banner" hidden></div>
  <main id="stage" class="stage">
    <iframe id="preview-frame" title="Widget Preview"></iframe>
  </main>
  <footer id="selection-bar" class="selection-bar" hidden>
    <div id="selection-chips" class="selection-chips"></div>
    <div class="selection-actions">
      <button id="copy-selection-btn" type="button">Copy Context</button>
      <button id="selection-clear" type="button">Clear</button>
    </div>
  </footer>
  <script>
    (() => {
      const rootPrefix = window.location.pathname.endsWith('/') ? '../' : './';
      const previewSelect = document.getElementById('preview-select');
      const themeToggle = document.getElementById('theme-toggle');
      const widthButtons = Array.from(document.querySelectorAll('.width-btn'));
      const zoomOut = document.getElementById('zoom-out');
      const zoomReset = document.getElementById('zoom-reset');
      const zoomIn = document.getElementById('zoom-in');
      const selectToggle = document.getElementById('select-toggle');
      const syncBtn = document.getElementById('sync-btn');
      const statusText = document.getElementById('status-text');
      const errorBanner = document.getElementById('error-banner');
      const stage = document.getElementById('stage');
      const frame = document.getElementById('preview-frame');
      const selectionBar = document.getElementById('selection-bar');
      const selectionChips = document.getElementById('selection-chips');
      const copySelectionBtn = document.getElementById('copy-selection-btn');
      const selectionClear = document.getElementById('selection-clear');

      const MIN_ZOOM = 0.25;
      const MAX_ZOOM = 4;
      const DEFAULT_ZOOM = 1;
      const ZOOM_STEP = 0.25;
      const ZOOM_EPSILON = 1e-6;
      const WHEEL_DELTA_THRESHOLD = 40;

      const roundZoom = (zoom) => Math.round(zoom * 10000) / 10000;

      const parseZoom = (raw) => {
        if (!raw) return DEFAULT_ZOOM;
        const parsed = Number(raw);
        if (!Number.isFinite(parsed) || parsed <= 0) return DEFAULT_ZOOM;
        return roundZoom(Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, parsed)));
      };

      const parseSelectMode = (raw) =>
        raw === '1' || String(raw || '').toLowerCase() === 'true';

      const formatZoom = (zoom) => String(roundZoom(zoom));

      const parseParams = (raw) => {
        const cleaned = (raw || '').replace(/^[#/?]+/, '');
        return new URLSearchParams(cleaned);
      };

      const initialQuery = parseParams(window.location.search);
      const initialHash = parseParams(window.location.hash);
      const readInitial = (key, fallback = '') =>
        initialHash.get(key) ?? initialQuery.get(key) ?? fallback;

      const state = {
        previewId: readInitial('previewId', '*') || '*',
        brightness: readInitial('brightness', readInitial('theme', 'light')) === 'dark'
          ? 'dark'
          : 'light',
        width: readInitial('width', ''),
        height: readInitial('height', ''),
        textScale: readInitial('textScale', ''),
        zoom: parseZoom(readInitial('zoom', '')),
        selectMode: parseSelectMode(readInitial('select', '')),
      };

      let selections = [];
      let copyResetTimer = null;

      const clearLocalSelections = () => {
        if (selections.length === 0) return;
        selections = [];
        renderSelectionBar();
      };

      const buildFragment = () => {
        const params = new URLSearchParams();
        params.set('embed', '1');
        params.set('previewId', state.previewId || '*');
        params.set('brightness', state.brightness);
        if (state.width) params.set('width', state.width);
        if (state.height) params.set('height', state.height);
        if (state.textScale) params.set('textScale', state.textScale);
        if (Math.abs(state.zoom - DEFAULT_ZOOM) > ZOOM_EPSILON) {
          params.set('zoom', formatZoom(state.zoom));
        }
        if (state.selectMode) {
          params.set('select', '1');
        }
        return params.toString();
      };

      const postToFrame = (payload) => {
        try {
          if (frame.contentWindow) {
            frame.contentWindow.postMessage(payload, window.location.origin);
          }
        } catch (_) {}
      };

      const syncSelectionsToServer = async (items) => {
        try {
          await fetch(rootPrefix + '__api/selection', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ selections: items }),
          });
        } catch (_) {}
      };

      const formatChipSummary = (sel) => {
        const widgets = Array.isArray(sel.widgets) ? sel.widgets : [];
        const primaryWidget = widgets.length > 0 && widgets[0].widget
          ? widgets[0].widget
          : (sel.previewName || sel.previewId || 'Preview');
        const geometry = sel.kind === 'point'
          ? '(' + sel.x + ', ' + sel.y + ')'
          : sel.width + '\u00D7' + sel.height;
        return '#' + sel.index + ' ' + primaryWidget + ' ' + geometry;
      };

      const formatSelectionContext = (items) => {
        if (!items.length) return '';
        const lines = ['Selected Widget Preview Context (' + items.length + '):'];
        for (const sel of items) {
          const previewLabel = sel.previewName
            ? sel.previewName + ' (' + sel.previewId + ')'
            : String(sel.previewId || '');
          const geometry = sel.kind === 'point'
            ? 'point (' + sel.x + ', ' + sel.y + ')'
            : 'region (' + sel.x + ', ' + sel.y + ') ' + sel.width + 'x' + sel.height;
          const frameSize = sel.previewWidth + 'x' + sel.previewHeight;
          lines.push(
            '#' + sel.index + ' ' + previewLabel + ' - ' + geometry + ' in ' + frameSize +
            ' [' + sel.brightness + ', textScale=' + sel.textScale + ', zoom=' + sel.zoom + ']'
          );
          const widgets = Array.isArray(sel.widgets) ? sel.widgets : [];
          for (const w of widgets) {
            const keyPart = w.key ? ' key=' + w.key : '';
            const textPart = w.text ? ' "' + w.text + '"' : '';
            lines.push(
              '  - ' + w.widget + keyPart + textPart +
              ' (' + w.x + ', ' + w.y + ') ' + w.width + 'x' + w.height
            );
          }
        }
        return lines.join('\n');
      };

      const renderSelectionBar = () => {
        selectionBar.hidden = selections.length === 0;
        selectionChips.innerHTML = '';
        for (const sel of selections) {
          const chip = document.createElement('span');
          chip.className = 'selection-chip';
          const label = document.createElement('span');
          label.className = 'selection-chip-label';
          label.textContent = formatChipSummary(sel);
          chip.appendChild(label);
          const removeBtn = document.createElement('button');
          removeBtn.type = 'button';
          removeBtn.className = 'selection-chip-remove';
          removeBtn.title = 'Remove #' + sel.index;
          removeBtn.setAttribute('aria-label', 'Remove selection #' + sel.index);
          removeBtn.textContent = '\u00D7';
          removeBtn.addEventListener('click', () => {
            postToFrame({
              type: 'flutter-widget-preview-clear-selections',
              id: sel.id,
            });
          });
          chip.appendChild(removeBtn);
          selectionChips.appendChild(chip);
        }
      };

      const applyFrameViewport = () => {
        if (state.width) {
          stage.classList.add('constrained');
          frame.style.width = state.width + 'px';
        } else {
          stage.classList.remove('constrained');
          frame.style.width = '100%';
        }
        frame.style.height = state.height ? state.height + 'px' : '100%';
      };

      const syncUi = (updateHash = true) => {
        themeToggle.textContent = state.brightness === 'dark' ? 'Dark' : 'Light';
        themeToggle.classList.toggle('active', state.brightness === 'dark');
        for (const btn of widthButtons) {
          btn.classList.toggle('active', (btn.dataset.width || '') === state.width);
        }
        zoomReset.textContent = Math.round(state.zoom * 100) + '%';
        zoomReset.classList.toggle('active', Math.abs(state.zoom - DEFAULT_ZOOM) > ZOOM_EPSILON);
        zoomOut.disabled = state.zoom <= MIN_ZOOM + ZOOM_EPSILON;
        zoomIn.disabled = state.zoom >= MAX_ZOOM - ZOOM_EPSILON;
        selectToggle.classList.toggle('active', state.selectMode);
        selectToggle.setAttribute('aria-pressed', state.selectMode ? 'true' : 'false');
        applyFrameViewport();
        const fragment = buildFragment();
        if (updateHash) {
          try {
            if (frame.contentWindow && frame.contentWindow.location) {
              frame.contentWindow.location.hash = '#' + fragment;
            } else {
              frame.src = rootPrefix + '?embed=1#' + fragment;
            }
          } catch (_) {
            frame.src = rootPrefix + '?embed=1#' + fragment;
          }
          if (window.location.hash !== '#' + fragment) {
            history.replaceState(null, '', '#' + fragment);
          }
        }
      };

      const updateWindowHashOnly = () => {
        const fragment = buildFragment();
        if (window.location.hash !== '#' + fragment) {
          history.replaceState(null, '', '#' + fragment);
        }
      };

      const setZoom = (nextZoom, updateIframe = true) => {
        const clamped = roundZoom(Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, nextZoom)));
        state.zoom = clamped;
        syncUi(updateIframe);
        if (!updateIframe) {
          updateWindowHashOnly();
        }
      };

      const renderPreviewOptions = (previews) => {
        const current = state.previewId || '*';
        previewSelect.innerHTML = '';
        const allOpt = document.createElement('option');
        allOpt.value = '*';
        allOpt.textContent = 'All Previews (' + previews.length + ')';
        previewSelect.appendChild(allOpt);
        for (const entry of previews) {
          const opt = document.createElement('option');
          opt.value = entry.id || '';
          const label = entry.name || entry.id || 'Unnamed';
          const group = entry.group ? ' [' + entry.group + ']' : '';
          opt.textContent = label + group;
          previewSelect.appendChild(opt);
        }
        const hasCurrent = Array.from(previewSelect.options).some((o) => o.value === current);
        previewSelect.value = hasCurrent ? current : '*';
        state.previewId = previewSelect.value;
      };

      const showCompileError = (message) => {
        if (message) {
          errorBanner.textContent = message;
          errorBanner.hidden = false;
        } else {
          errorBanner.textContent = '';
          errorBanner.hidden = true;
        }
      };

      const loadPreviews = async () => {
        try {
          const res = await fetch(rootPrefix + '__api/previews', { cache: 'no-store' });
          if (!res.ok) throw new Error('HTTP ' + res.status);
          const data = await res.json();
          const previews = Array.isArray(data.previews) ? data.previews : [];
          renderPreviewOptions(previews);
          statusText.textContent = previews.length + ' preview(s) ready';
        } catch (err) {
          statusText.textContent = 'Failed to load previews: ' + err.message;
        }
      };

      previewSelect.addEventListener('change', () => {
        state.previewId = previewSelect.value || '*';
        syncUi(true);
      });

      themeToggle.addEventListener('click', () => {
        state.brightness = state.brightness === 'dark' ? 'light' : 'dark';
        syncUi(true);
      });

      for (const btn of widthButtons) {
        btn.addEventListener('click', () => {
          state.width = btn.dataset.width || '';
          syncUi(true);
        });
      }

      zoomOut.addEventListener('click', () => setZoom(state.zoom - ZOOM_STEP, true));
      zoomReset.addEventListener('click', () => setZoom(DEFAULT_ZOOM, true));
      zoomIn.addEventListener('click', () => setZoom(state.zoom + ZOOM_STEP, true));

      selectToggle.addEventListener('click', () => {
        state.selectMode = !state.selectMode;
        syncUi(true);
        postToFrame({
          type: 'flutter-widget-preview-set-select-mode',
          active: state.selectMode,
        });
      });

      selectionClear.addEventListener('click', () => {
        postToFrame({ type: 'flutter-widget-preview-clear-selections' });
      });

      copySelectionBtn.addEventListener('click', async () => {
        const summary = formatSelectionContext(selections);
        if (!summary) return;
        let copied = false;
        try {
          if (navigator.clipboard && navigator.clipboard.writeText) {
            await navigator.clipboard.writeText(summary);
            copied = true;
          }
        } catch (_) {}
        if (!copied) {
          const fallbackArea = document.createElement('textarea');
          fallbackArea.value = summary;
          fallbackArea.style.position = 'fixed';
          fallbackArea.style.opacity = '0';
          document.body.appendChild(fallbackArea);
          fallbackArea.select();
          try {
            document.execCommand('copy');
            copied = true;
          } catch (_) {}
          document.body.removeChild(fallbackArea);
        }
        if (copied) {
          copySelectionBtn.textContent = 'Copied!';
          if (copyResetTimer) clearTimeout(copyResetTimer);
          copyResetTimer = setTimeout(() => {
            copySelectionBtn.textContent = 'Copy Context';
            copyResetTimer = null;
          }, 1200);
        }
      });

      const isEditableElement = (target) => {
        if (!(target instanceof HTMLElement)) return false;
        const tag = target.tagName;
        return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || target.isContentEditable;
      };

      let wheelDeltaAccum = 0;
      window.addEventListener('wheel', (event) => {
        if (!(event.ctrlKey || event.metaKey)) {
          wheelDeltaAccum = 0;
          return;
        }
        event.preventDefault();
        if (event.deltaY === 0) return;
        if (event.deltaY * wheelDeltaAccum < 0) {
          wheelDeltaAccum = 0;
        }
        let step = 0;
        if (event.deltaMode !== 0 || Math.abs(event.deltaY) >= WHEEL_DELTA_THRESHOLD) {
          wheelDeltaAccum = 0;
          step = event.deltaY < 0 ? ZOOM_STEP : -ZOOM_STEP;
        } else {
          wheelDeltaAccum += event.deltaY;
          if (Math.abs(wheelDeltaAccum) < WHEEL_DELTA_THRESHOLD) return;
          step = wheelDeltaAccum < 0 ? ZOOM_STEP : -ZOOM_STEP;
          wheelDeltaAccum %= WHEEL_DELTA_THRESHOLD;
        }
        setZoom(state.zoom + step, true);
      }, { passive: false });

      window.addEventListener('keydown', (event) => {
        if (event.altKey || isEditableElement(event.target)) return;
        if (event.key === 'Escape' && !event.ctrlKey && !event.metaKey) {
          if (state.selectMode) {
            event.preventDefault();
            state.selectMode = false;
            syncUi(true);
            postToFrame({
              type: 'flutter-widget-preview-set-select-mode',
              active: false,
            });
            return;
          }
          if (selections.length > 0) {
            event.preventDefault();
            postToFrame({ type: 'flutter-widget-preview-clear-selections' });
            return;
          }
        }
        if (event.key === '+' || event.key === '=') {
          event.preventDefault();
          setZoom(state.zoom + ZOOM_STEP, true);
        } else if (event.key === '-') {
          event.preventDefault();
          setZoom(state.zoom - ZOOM_STEP, true);
        } else if (event.key === '0' && !event.shiftKey) {
          event.preventDefault();
          setZoom(DEFAULT_ZOOM, true);
        }
      });

      window.addEventListener('message', (event) => {
        if (event.origin !== window.location.origin) return;
        if (event.source !== frame.contentWindow) return;
        const messageType = event.data?.type;
        if (messageType === 'flutter-widget-preview-zoom') {
          const nextZoom = Number(event.data.zoom);
          if (!Number.isFinite(nextZoom) || nextZoom <= 0) return;
          setZoom(nextZoom, false);
        } else if (messageType === 'flutter-widget-preview-selections') {
          state.selectMode = Boolean(event.data.selectMode);
          selections = Array.isArray(event.data.selections) ? event.data.selections : [];
          syncUi(false);
          updateWindowHashOnly();
          renderSelectionBar();
          syncSelectionsToServer(selections);
        }
      });

      frame.addEventListener('load', () => {
        clearLocalSelections();
      });

      syncBtn.addEventListener('click', async () => {
        syncBtn.disabled = true;
        statusText.textContent = 'Syncing...';
        try {
          const res = await fetch(rootPrefix + '__api/sync', { method: 'POST' });
          const data = await res.json();
          if (data.compileSuccess === false || data.errorMessage) {
            showCompileError(data.errorMessage || 'Compilation failed.');
            statusText.textContent = 'Compile error';
          } else {
            showCompileError('');
            clearLocalSelections();
            await loadPreviews();
          }
        } catch (err) {
          showCompileError('Sync failed: ' + err.message);
          statusText.textContent = 'Sync failed';
        } finally {
          syncBtn.disabled = false;
        }
      });

      frame.src = rootPrefix + '?embed=1#' + buildFragment();
      syncUi(false);
      renderSelectionBar();
      loadPreviews();
    })();
  </script>
</body>
</html>
''';
}

String _escapeHtml(String input) => input
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

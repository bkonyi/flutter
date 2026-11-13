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
    .toolbar button {
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
    .toolbar button:disabled {
      opacity: 0.6;
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
    <button id="sync-btn" type="button">Sync Reload</button>
    <span class="spacer"></span>
    <span id="status-text" class="status">Connecting...</span>
  </header>
  <div id="error-banner" class="error-banner" hidden></div>
  <main id="stage" class="stage">
    <iframe id="preview-frame" title="Widget Preview"></iframe>
  </main>
  <script>
    (() => {
      const rootPrefix = window.location.pathname.endsWith('/') ? '../' : './';
      const previewSelect = document.getElementById('preview-select');
      const themeToggle = document.getElementById('theme-toggle');
      const widthButtons = Array.from(document.querySelectorAll('.width-btn'));
      const syncBtn = document.getElementById('sync-btn');
      const statusText = document.getElementById('status-text');
      const errorBanner = document.getElementById('error-banner');
      const stage = document.getElementById('stage');
      const frame = document.getElementById('preview-frame');

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
      };

      const buildFragment = () => {
        const params = new URLSearchParams();
        params.set('embed', '1');
        params.set('previewId', state.previewId || '*');
        params.set('brightness', state.brightness);
        if (state.width) params.set('width', state.width);
        if (state.height) params.set('height', state.height);
        if (state.textScale) params.set('textScale', state.textScale);
        return params.toString();
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

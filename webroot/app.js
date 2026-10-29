(function () {
  'use strict';

  const helper = '/system/bin/sh /data/adb/modules/susfs4ksu-lkm-hide-mounts-by-mask/bin/config.sh';
  const rules = document.getElementById('rules');
  const status = document.getElementById('status');
  const message = document.getElementById('message');
  const indicator = document.getElementById('guardIndicator');
  const controls = ['reload', 'save', 'apply', 'statusButton', 'scanButton']
    .map((id) => document.getElementById(id));
  let original = '';
  let requestId = 0;
  let configLoaded = false;

  function notify(text, kind) {
    message.hidden = !text;
    message.dataset.kind = kind || '';
    message.textContent = text || '';
  }

  function setBusy(busy) {
    controls.forEach((button) => { button.disabled = busy; });
    rules.disabled = busy;
  }

  function updateEditorState() {
    const content = rules.value;
    document.getElementById('lineCount').textContent = (content ? content.split('\n').length : 0) + ' lines';
    document.getElementById('dirtyDot').hidden = content === original;
  }

  // The one-argument ksu.exec() returns only the LAST stdout line on
  // KernelSU Next (ShellUtils.fastCmd). The callback form returns the full
  // stdout, stderr, and exit status, which are essential for multiline config.
  function exec(action, payload) {
    if (!window.ksu || typeof window.ksu.exec !== 'function') {
      return Promise.reject(new Error('KernelSU Next WebUI bridge is unavailable'));
    }
    const command = helper + ' ' + action + (payload ? " '" + payload + "'" : '');
    return new Promise((resolve, reject) => {
      const callback = '__susfsMountExec' + (++requestId);
      window[callback] = (exitCode, stdout, stderr) => {
        delete window[callback];
        if (Number(exitCode) !== 0) {
          reject(new Error(String(stderr || stdout || 'Command failed').trim()));
        } else {
          resolve(String(stdout || ''));
        }
      };
      try {
        window.ksu.exec(command, callback);
      } catch (error) {
        delete window[callback];
        reject(error);
      }
    });
  }

  function encodeUtf8(text) {
    const bytes = new TextEncoder().encode(text);
    let binary = '';
    for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
    return btoa(binary);
  }

  function parseStatus(raw) {
    const match = raw.match(/^mount prefixes:\s*(\d+)\/(\d+)/m);
    const ready = Boolean(match);
    indicator.dataset.state = ready ? 'ready' : 'error';
    document.getElementById('guardLabel').textContent = ready ? 'Mounts: hiding active' : 'Mounts: hiding unavailable';
    document.getElementById('prefixCount').textContent = ready ? match[1] + '/' + match[2] : '—';
  }

  async function refreshStatus() {
    try {
      const text = await exec('status');
      status.textContent = text.trim() || 'No status available';
      parseStatus(text);
    } catch (e) {
      status.textContent = String(e.message || e);
      parseStatus('');
    }
  }

  function confirmDiscardChanges() {
    const dialog = document.getElementById('discardDialog');
    if (dialog.open) return Promise.resolve(false);

    return new Promise((resolve) => {
      dialog.addEventListener('close', () => {
        resolve(dialog.returnValue === 'discard');
      }, { once: true });
      dialog.returnValue = 'cancel';
      dialog.showModal();
      document.getElementById('keepEditing').focus();
    });
  }

  async function load(ask) {
    if (ask && rules.value !== original && !(await confirmDiscardChanges())) return;
    setBusy(true);
    try {
      const data = await exec('read');
      if (data.startsWith('ERROR:')) throw new Error(data.trim());
      rules.value = original = data;
      configLoaded = true;
      updateEditorState();
      notify('Rules loaded', 'ok');
    } catch (e) {
      configLoaded = false;
      notify(String(e.message || e), 'error');
    } finally {
      setBusy(false);
      // Never permit saving if reading the current config has failed.
      document.getElementById('save').disabled = !configLoaded;
      document.getElementById('apply').disabled = !configLoaded;
    }
  }

  async function save(scanAfter) {
    if (!configLoaded) return;
    setBusy(true);
    try {
      const encoded = encodeUtf8(rules.value);
      if (encoded.length > 32768) throw new Error('Configuration exceeds 24 KB');
      const response = (await exec('save', encoded)).trim();
      if (!response.startsWith('OK:')) throw new Error(response || 'Save failed');
      original = rules.value;
      updateEditorState();
      if (scanAfter) {
        try {
          const scanned = (await exec('scan')).trim();
          if (!scanned.startsWith('OK:')) throw new Error(scanned || 'Scan failed');
          await refreshStatus();
        } catch (error) {
          throw new Error('Configuration saved, but scan failed: ' + String(error.message || error));
        }
      }
      notify(scanAfter ? 'Rules saved and mounts scanned' : 'Configuration saved', 'ok');
    } catch (e) {
      notify(String(e.message || e), 'error');
    } finally {
      setBusy(false);
    }
  }

  async function scan() {
    setBusy(true);
    try {
      const result = (await exec('scan')).trim();
      if (!result.startsWith('OK:')) throw new Error(result || 'Scan failed');
      await refreshStatus();
      notify('Current mounts scanned', 'ok');
    } catch (e) {
      notify(String(e.message || e), 'error');
    } finally {
      setBusy(false);
    }
  }

  document.getElementById('reload').addEventListener('click', () => { void load(true); });
  document.getElementById('save').addEventListener('click', () => { void save(false); });
  document.getElementById('apply').addEventListener('click', () => { void save(true); });
  document.getElementById('statusButton').addEventListener('click', () => { void refreshStatus(); });
  document.getElementById('scanButton').addEventListener('click', () => { void scan(); });
  rules.addEventListener('input', updateEditorState);

  // Avoid accidentally losing an edited configuration when leaving WebUI.
  window.addEventListener('beforeunload', (event) => {
    if (rules.value === original) return;
    event.preventDefault();
    event.returnValue = '';
  });

  document.getElementById('save').disabled = true;
  document.getElementById('apply').disabled = true;
  void (async () => {
    await load(false);
    await refreshStatus();
  })();
})();

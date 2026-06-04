// Background removal bridge.
// Uses esm.sh to serve @imgly/background-removal as a browser-ready ES module
// (the npm dist has bare specifiers; esm.sh rewrites them to CDN URLs).
// Assets (WASM + model) are fetched from the official staticimgly CDN.

const _BG_MOD        = 'https://esm.sh/@imgly/background-removal@1.4.5';
const _BG_PUBLIC_PATH = 'https://staticimgly.com/@imgly/background-removal-data/1.4.5/dist/';

let _removeBackground = null;

async function _getLib() {
  if (_removeBackground) return _removeBackground;
  console.log('[bg_remover] Loading library from esm.sh…');
  try {
    const mod = await import(_BG_MOD);
    _removeBackground = mod.removeBackground;
    if (!_removeBackground) throw new Error('removeBackground not found in module exports');
    console.log('[bg_remover] Library ready.');
    return _removeBackground;
  } catch (err) {
    console.error('[bg_remover] Failed to load library:', err);
    throw err;
  }
}

window.aetherraRemoveBg = async function (base64Input) {
  const removeBackground = await _getLib();

  console.log('[bg_remover] Decoding input…');
  const binary = atob(base64Input);
  const bytes  = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);

  // Detect MIME type from magic bytes so the library can parse it correctly.
  let mime = 'image/png';
  if (bytes[0] === 0xFF && bytes[1] === 0xD8) mime = 'image/jpeg';
  else if (bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[4] === 0x57 && bytes[5] === 0x45) mime = 'image/webp';

  const inputBlob = new Blob([bytes], { type: mime });

  console.log('[bg_remover] Running model (first run downloads ~100 MB — cached after)…');
  const resultBlob = await removeBackground(inputBlob, {
    publicPath: _BG_PUBLIC_PATH,
    output: { type: 'image/png', quality: 1.0 },
  });

  console.log('[bg_remover] Done — encoding result…');
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onloadend = () => { console.log('[bg_remover] Complete.'); resolve(reader.result.split(',')[1]); };
    reader.onerror  = reject;
    reader.readAsDataURL(resultBlob);
  });
};

console.log('[bg_remover] window.aetherraRemoveBg registered.');

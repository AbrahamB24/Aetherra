// @ts-nocheck — Deno runtime
import { Image } from 'https://deno.land/x/imagescript@1.2.15/mod.ts';

const CORS = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const HF_URL = 'https://api-inference.huggingface.co/models/briaai/RMBG-1.4';

// Retry when model is still loading (HF returns 503)
async function callHF(token: string, imageBytes: Uint8Array, attempts = 4): Promise<Response> {
  for (let i = 0; i < attempts; i++) {
    const resp = await fetch(HF_URL, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/octet-stream' },
      body: imageBytes,
    });
    if (resp.status !== 503) return resp;
    if (i < attempts - 1) await new Promise(r => setTimeout(r, 3000));
  }
  throw new Error('Model still loading after retries — try again in a few seconds.');
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  try {
    const token = Deno.env.get('HF_TOKEN');
    if (!token) {
      return new Response(JSON.stringify({ error: 'HF_TOKEN not configured' }), {
        status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
      });
    }

    const { image } = await req.json();
    if (!image) {
      return new Response(JSON.stringify({ error: 'Missing image field' }), {
        status: 400, headers: { ...CORS, 'Content-Type': 'application/json' },
      });
    }

    const imageBytes = Uint8Array.from(atob(image), c => c.charCodeAt(0));

    // ── 1. Get segmentation mask from HuggingFace ──────────────────
    const hfResp = await callHF(token, imageBytes);
    if (!hfResp.ok) {
      const txt = await hfResp.text();
      return new Response(JSON.stringify({ error: `HF API ${hfResp.status}: ${txt}` }), {
        status: hfResp.status, headers: { ...CORS, 'Content-Type': 'application/json' },
      });
    }

    const masks = await hfResp.json();
    if (!masks?.length || !masks[0]?.mask) {
      return new Response(JSON.stringify({ error: 'No mask returned from model' }), {
        status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
      });
    }

    // mask is "data:image/png;base64,..." or plain base64
    const raw    = masks[0].mask as string;
    const maskB64 = raw.includes(',') ? raw.split(',')[1] : raw;
    const maskBytes = Uint8Array.from(atob(maskB64), c => c.charCodeAt(0));

    // ── 2. Decode original + mask ──────────────────────────────────
    const [orig, mask] = await Promise.all([
      Image.decode(imageBytes),
      Image.decode(maskBytes),
    ]);

    // Resize mask to match original if dimensions differ
    if (mask.width !== orig.width || mask.height !== orig.height) {
      mask.resize(orig.width, orig.height);
    }

    // ── 3. Apply mask as alpha channel ─────────────────────────────
    // RMBG mask: white = keep foreground, black = remove (background)
    for (let x = 1; x <= orig.width; x++) {
      for (let y = 1; y <= orig.height; y++) {
        const op = orig.getPixelAt(x, y);
        const mp = mask.getPixelAt(x, y);
        const r = (op >>> 24) & 0xFF;
        const g = (op >>> 16) & 0xFF;
        const b = (op >>>  8) & 0xFF;
        const a = (mp >>> 24) & 0xFF; // red channel of grayscale mask → alpha
        orig.setPixelAt(x, y, Image.rgbaToColor(r, g, b, a));
      }
    }

    // ── 4. Encode as PNG (preserves transparency) ──────────────────
    const resultBytes = await orig.encode(0); // 0 = PNG
    let b64 = '';
    for (let i = 0; i < resultBytes.byteLength; i++) b64 += String.fromCharCode(resultBytes[i]);

    return new Response(JSON.stringify({ result: btoa(b64) }), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    });

  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
    });
  }
});

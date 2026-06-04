// tool/generate_logo.dart
// Generates Aetherra logo PNGs for web / PWA icons.
// Run from project root:  dart run tool/generate_logo.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

// ── CRC-32 (required by PNG format) ──────────────────────────────────────

final _crcT = () {
  final t = List<int>.filled(256, 0);
  for (int n = 0; n < 256; n++) {
    int c = n;
    for (int k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    }
    t[n] = c;
  }
  return t;
}();

int _crc32(List<int> d) {
  int c = 0xFFFFFFFF;
  for (final b in d) { c = _crcT[(c ^ b) & 0xFF] ^ (c >>> 8); }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

// ── PNG writer ────────────────────────────────────────────────────────────

Uint8List _chunk(String type, List<int> data) {
  final tb  = type.codeUnits;
  final crc = _crc32([...tb, ...data]);
  final out = ByteData(12 + data.length);
  out.setUint32(0, data.length, Endian.big);
  for (int i = 0; i < 4; i++) { out.setUint8(4 + i, tb[i]); }
  for (int i = 0; i < data.length; i++) { out.setUint8(8 + i, data[i]); }
  out.setUint32(8 + data.length, crc, Endian.big);
  return out.buffer.asUint8List();
}

Uint8List encodePng(Uint8List rgb, int w, int h) {
  // Filter byte 0 (None) prepended to each row
  final raw = Uint8List(h * (1 + w * 3));
  for (int y = 0; y < h; y++) {
    raw[y * (w * 3 + 1)] = 0;
    for (int x = 0; x < w * 3; x++) {
      raw[y * (w * 3 + 1) + 1 + x] = rgb[y * w * 3 + x];
    }
  }
  final comp = ZLibEncoder().convert(raw);

  final ihdr = ByteData(13)
    ..setUint32(0, w, Endian.big)
    ..setUint32(4, h, Endian.big)
    ..setUint8(8, 8)   // bit depth
    ..setUint8(9, 2);  // color type: RGB

  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
    ..._chunk('IHDR', ihdr.buffer.asUint8List()),
    ..._chunk('IDAT', comp),
    ..._chunk('IEND', []),
  ]);
}

// ── Pixel-level drawing ───────────────────────────────────────────────────

void _blend(Uint8List buf, int w, int x, int y, List<int> c, double a) {
  if (x < 0 || x >= w || y < 0 || y >= w || a <= 0) return;
  final i = (y * w + x) * 3;
  if (a >= 1.0) {
    buf[i] = c[0]; buf[i + 1] = c[1]; buf[i + 2] = c[2];
  } else {
    buf[i]     = (buf[i]     + (c[0] - buf[i])     * a).round();
    buf[i + 1] = (buf[i + 1] + (c[1] - buf[i + 1]) * a).round();
    buf[i + 2] = (buf[i + 2] + (c[2] - buf[i + 2]) * a).round();
  }
}

double _dSeg(double px, double py, double ax, double ay, double bx, double by) {
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  final t = len2 == 0 ? 0.0
    : (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0);
  final qx = ax + t * dx, qy = ay + t * dy;
  return math.sqrt((px - qx) * (px - qx) + (py - qy) * (py - qy));
}

void _line(Uint8List buf, int sz,
    double x1, double y1, double x2, double y2,
    double hw, List<int> c, {double alpha = 1.0}) {
  final x0 = (math.min(x1, x2) - hw - 1).floor().clamp(0, sz - 1);
  final xE = (math.max(x1, x2) + hw + 1).ceil().clamp(0, sz - 1);
  final y0 = (math.min(y1, y2) - hw - 1).floor().clamp(0, sz - 1);
  final yE = (math.max(y1, y2) + hw + 1).ceil().clamp(0, sz - 1);
  for (int y = y0; y <= yE; y++) {
    for (int x = x0; x <= xE; x++) {
      final d = _dSeg(x + 0.5, y + 0.5, x1, y1, x2, y2);
      final a = (hw + 0.5 - d).clamp(0.0, 1.0) * alpha;
      if (a > 0) _blend(buf, sz, x, y, c, a);
    }
  }
}

void _dot(Uint8List buf, int sz,
    double cx, double cy, double r, List<int> c, {double alpha = 1.0}) {
  final x0 = (cx - r - 1).floor().clamp(0, sz - 1);
  final xE = (cx + r + 1).ceil().clamp(0, sz - 1);
  final y0 = (cy - r - 1).floor().clamp(0, sz - 1);
  final yE = (cy + r + 1).ceil().clamp(0, sz - 1);
  for (int y = y0; y <= yE; y++) {
    for (int x = x0; x <= xE; x++) {
      final d = math.sqrt((x + 0.5 - cx) * (x + 0.5 - cx)
                        + (y + 0.5 - cy) * (y + 0.5 - cy));
      final a = (r + 0.5 - d).clamp(0.0, 1.0) * alpha;
      if (a > 0) _blend(buf, sz, x, y, c, a);
    }
  }
}

// ── Logo rendering ────────────────────────────────────────────────────────

const _bg   = [0x0D, 0x0B, 0x08];
const _gold = [0xC9, 0xA8, 0x4C];

Uint8List renderLogo(int sz) {
  final buf = Uint8List(sz * sz * 3);
  // Background
  for (int i = 0; i < sz * sz; i++) {
    buf[i * 3] = _bg[0]; buf[i * 3 + 1] = _bg[1]; buf[i * 3 + 2] = _bg[2];
  }

  final s = sz.toDouble();

  // Octagon vertices (e = edge pad, k = corner cut, both as fraction of s)
  const e = 0.03, k = 0.30;
  final v = [
    [k * s, e * s],           [(1 - k) * s, e * s],         // top
    [(1 - e) * s, k * s],     [(1 - e) * s, (1 - k) * s],   // right
    [(1 - k) * s, (1 - e) * s], [k * s, (1 - e) * s],       // bottom
    [e * s, (1 - k) * s],     [e * s, k * s],                // left
  ];

  final bw  = s * 0.013; // octagon border half-width
  final ctr = s / 2;

  // Outer octagon
  for (int i = 0; i < 8; i++) {
    final j = (i + 1) % 8;
    _line(buf, sz, v[i][0], v[i][1], v[j][0], v[j][1], bw, _gold);
  }

  // Inner octagon (30 % opacity accent)
  const sc = 0.87;
  for (int i = 0; i < 8; i++) {
    final j = (i + 1) % 8;
    _line(buf, sz,
      ctr + (v[i][0] - ctr) * sc, ctr + (v[i][1] - ctr) * sc,
      ctr + (v[j][0] - ctr) * sc, ctr + (v[j][1] - ctr) * sc,
      s * 0.004, _gold, alpha: 0.30);
  }

  // Corner dots at octagon vertices
  for (final p in v) { _dot(buf, sz, p[0], p[1], bw, _gold); }

  // ── A letterform ──────────────────────────────────────────────────────
  final lw = s * 0.075; // leg half-width
  final cw = s * 0.048; // crossbar half-width

  // Left leg: apex → base-left
  _line(buf, sz, s * 0.500, s * 0.185, s * 0.185, s * 0.828, lw, _gold);
  // Right leg: apex → base-right
  _line(buf, sz, s * 0.500, s * 0.185, s * 0.815, s * 0.828, lw, _gold);
  // Crossbar
  _line(buf, sz, s * 0.315, s * 0.530, s * 0.685, s * 0.530, cw, _gold);

  return buf;
}

// ── Main ──────────────────────────────────────────────────────────────────

void main() {
  final icons = {
    'web/favicon.png':                 64,
    'web/icons/Icon-192.png':          192,
    'web/icons/Icon-512.png':          512,
    'web/icons/Icon-maskable-192.png': 192,
    'web/icons/Icon-maskable-512.png': 512,
  };

  for (final entry in icons.entries) {
    final sz  = entry.value;
    final png = encodePng(renderLogo(sz), sz, sz);
    File(entry.key).writeAsBytesSync(png);
    stdout.writeln('✓ ${entry.key}  ($sz×$sz)');
  }
}

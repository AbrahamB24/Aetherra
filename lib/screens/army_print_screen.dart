import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/army_state.dart';
import '../services/game_data_service.dart';
import '../app_theme.dart';
import '../widgets/nav_btn.dart';
import '../widgets/photo_crop_dialog.dart';

class ArmyPrintScreen extends StatefulWidget {
  final ArmyState army;
  final String?   logoB64;
  final String?   logoBgHex;
  final String?   creator;
  const ArmyPrintScreen({super.key, required this.army, this.logoB64, this.logoBgHex, this.creator});
  @override State<ArmyPrintScreen> createState() => _ArmyPrintScreenState();
}

class _ArmyPrintScreenState extends State<ArmyPrintScreen> {
  String _mode = 'color'; // 'color' | 'white' | 'bw'

  static const _gold  = AppColors.gold;
  static const _dark  = AppColors.dark;
  
  // ── Caches ────────────────────────────────────────────────────────────────────
  // Fonts: static so they survive mode switches and screen rebuilds.
  static pw.Font? _fontReg;
  static pw.Font? _fontBold;

  // Photos: keyed by base64 string.  Raw = color-rendered; BW derived from raw.
  final _rawPhotos = <String, Uint8List>{};
  final _bwPhotos  = <String, Uint8List>{};

  // Logo: rendered once, both variants derived from the same raw render.
  Uint8List? _logoRaw;
  Uint8List? _logoBw; // grayscale version of _logoRaw

  // Icons: keyed by 'type_mode'.
  final _iconBytes = <String, Uint8List>{};

  List<ArmyUnit> _unitsForGroup(String grp) =>
      widget.army.units.where((u) => u.groupName == grp).toList();

  List<String> get _orderedGroups => ['', ...widget.army.groups];

  // ── Color helpers ─────────────────────────────────────────────────────────────

  // True when perceived brightness < 50 % — used to pick contrasting text.
  static bool _isBgDark(PdfColor c) =>
      0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue < 0.5;

  // Returns type color tuned per mode: muted on AppColors.dark, saturated on white, grey in b&w.
  static PdfColor _pdfTypeColor(String type, String mode) {
    if (mode == 'bw') return PdfColors.black;
    if (mode == 'white') {
      switch (type.toLowerCase()) {
        case 'infantry':  return PdfColor.fromHex('1456C8');
        case 'cavalry':   return PdfColor.fromHex('1A7A10');
        case 'shooting':  return PdfColor.fromHex('CC1870');
        case 'artillery': return PdfColor.fromHex('CC0A0A');
        case 'hero':      return PdfColor.fromHex('9A7820');
        case 'monster':   return PdfColor.fromHex('5522A8');
        default:          return PdfColor.fromHex('504030');
      }
    }
    switch (type.toLowerCase()) {
      case 'infantry':  return PdfColor.fromHex('80A0C0');
      case 'cavalry':   return PdfColor.fromHex('90C080');
      case 'shooting':  return PdfColor.fromHex('F080B0');
      case 'artillery': return PdfColor.fromHex('D48080');
      case 'hero':      return PdfColor.fromHex('E0C060');
      case 'monster':   return PdfColor.fromHex('B090E0');
      default:          return PdfColor.fromHex('B0A090');
    }
  }

  static PdfColor _blend(PdfColor fg, double a, PdfColor bg) => PdfColor(
    (bg.red   + (fg.red   - bg.red)   * a).clamp(0.0, 1.0),
    (bg.green + (fg.green - bg.green) * a).clamp(0.0, 1.0),
    (bg.blue  + (fg.blue  - bg.blue)  * a).clamp(0.0, 1.0),
  );

  static String _typeAbbrev(String type) {
    switch (type.toLowerCase()) {
      case 'infantry':  return 'INF';
      case 'cavalry':   return 'CAV';
      case 'shooting':  return 'SHO';
      case 'artillery': return 'ART';
      case 'hero':      return 'HERO';
      case 'monster':   return 'MON';
      default:          return '?';
    }
  }

  static IconData _flutterTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'infantry':  return Icons.sports_martial_arts;
      case 'cavalry':   return Icons.directions_run;
      case 'shooting':  return Icons.adjust;
      case 'artillery': return Icons.architecture;
      case 'hero':      return Icons.star;
      case 'monster':   return Icons.pets;
      default:          return Icons.shield_outlined;
    }
  }

  // Renders a Material icon glyph to PNG bytes via ParagraphBuilder.
  static Future<Uint8List?> _renderTypeIconBytes(
      String type, ui.Color color, double sizePx) async {
    final icon = _flutterTypeIcon(type);
    try {
      const res = 2;
      final s = sizePx * res;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, s, s));
      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
        fontFamily: icon.fontFamily ?? 'MaterialIcons',
      ))
        ..pushStyle(ui.TextStyle(
          color: color,
          fontSize: s,
          fontFamily: icon.fontFamily ?? 'MaterialIcons',
        ))
        ..addText(String.fromCharCode(icon.codePoint));
      final para = builder.build();
      para.layout(ui.ParagraphConstraints(width: s));
      canvas.drawParagraph(para, ui.Offset.zero);
      final pic = recorder.endRecording();
      final img = await pic.toImage(s.round(), s.round());
      pic.dispose();
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      return bd?.buffer.asUint8List();
    } catch (_) { return null; }
  }

  // ── Photo crop renderer ───────────────────────────────────────────────────────

  // Convert any PNG/JPEG bytes to greyscale via raw RGBA pixel manipulation.
  static Future<Uint8List> _toGrayscaleBytes(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img   = frame.image;
      final iw = img.width;
      final ih = img.height;
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      if (bd == null) return bytes;
      final px = bd.buffer.asUint8List();
      for (int i = 0; i < px.length; i += 4) {
        final g = (0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2])
            .round().clamp(0, 255);
        px[i] = px[i + 1] = px[i + 2] = g;
      }
      final c = Completer<ui.Image>();
      ui.decodeImageFromPixels(px, iw, ih, ui.PixelFormat.rgba8888, c.complete);
      final greyImg = await c.future;
      final bd2 = await greyImg.toByteData(format: ui.ImageByteFormat.png);
      greyImg.dispose();
      return bd2?.buffer.asUint8List() ?? bytes;
    } catch (_) {
      return bytes;
    }
  }



  // Render the stored crop transform, then optionally convert to greyscale.
  // Falls back to raw photo bytes if the JSON envelope is absent or malformed.
  static Future<Uint8List> _renderCroppedPhoto(
      String photoBase64, double w, double h, {bool grayscale = false}) async {
    Uint8List? result;
    try {
      final raw = base64Decode(photoBase64);
      if (raw.isNotEmpty && raw[0] == 0x7B) {
        final info     = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
        final srcBytes = base64Decode(info['src'] as String);
        final scale    = (info['scale']   as num?)?.toDouble() ?? 1.0;
        final ox       = (info['offsetX'] as num?)?.toDouble() ?? 0.0;
        final oy       = (info['offsetY'] as num?)?.toDouble() ?? 0.0;
        final prevW    = (info['previewW'] as num?)?.toDouble()
                      ?? (info['_pw']     as num?)?.toDouble() ?? 200.0;
        final prevH    = (info['previewH'] as num?)?.toDouble()
                      ?? (info['_ph']     as num?)?.toDouble() ?? 350.0;

        final codec = await ui.instantiateImageCodec(srcBytes);
        final frame = await codec.getNextFrame();
        final img   = frame.image;

        final k       = math.min(w / prevW, h / prevH);
        final hCenter = (w - prevW * k) / 2.0;
        final vCenter = (h - prevH * k) / 2.0;

        const res      = 2;
        final recorder = ui.PictureRecorder();
        final canvas   = ui.Canvas(recorder,
          ui.Rect.fromLTWH(0, 0, w * res, h * res));
        canvas.scale(res.toDouble());
        canvas.clipRect(ui.Rect.fromLTWH(0, 0, w, h));
        canvas.translate(ox * k + hCenter, oy * k + vCenter);
        canvas.scale(scale * k);
        canvas.drawImage(img, ui.Offset.zero, ui.Paint());
        img.dispose();

        final pic      = recorder.endRecording();
        final rendered = await pic.toImage((w * res).round(), (h * res).round());
        pic.dispose();
        final bd = await rendered.toByteData(format: ui.ImageByteFormat.png);
        rendered.dispose();
        result = bd?.buffer.asUint8List();
      }
    } catch (_) {}

    result ??= decodePhotoBytes(photoBase64);
    return grayscale ? await _toGrayscaleBytes(result) : result;
  }

  // ── PDF builder ───────────────────────────────────────────────────────────────

  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    final isBw   = _mode == 'bw';
    final isDark = _mode == 'color';
    final doc    = pw.Document();

    _fontReg  ??= await PdfGoogleFonts.cinzelRegular();
    _fontBold ??= await PdfGoogleFonts.cinzelBold();
    final fReg  = _fontReg!;
    final fBold = _fontBold!;

    // Palette — gold and borders are saturated for white mode, greyscale for bw.
    final bgPage  = isDark ? PdfColor.fromHex('0D0B08') : PdfColors.white;
    final cardBg  = isDark ? PdfColor.fromHex('161310') : PdfColors.white;
    final cGold   = isDark  ? PdfColor.fromHex('C9A84C') : PdfColors.black;
    final cGrey   = isBw    ? PdfColors.black
                  : isDark  ? PdfColor.fromHex('B0A090')
                            : const PdfColor(0.35, 0.35, 0.35);
    final cBorder = isDark  ? PdfColor.fromHex('C9A84C') : PdfColors.black;
    final cGrpBg  = isDark  ? PdfColor.fromHex('1A1208') : PdfColors.white;
    final cDark4  = isDark  ? PdfColor.fromHex('0D0B08') : const PdfColor(0.90, 0.90, 0.90);

    const margin = 24.0;
    const gap    = 8.0;
    const cols   = 2;
    final cardW  = (format.width - margin * 2 - gap * (cols - 1)) / cols;

    pw.PageTheme makeTheme() => pw.PageTheme(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(margin),
      theme: pw.ThemeData.withFont(base: fReg, bold: fBold),
      buildBackground: (_) => pw.FullPage(
        ignoreMargins: true, child: pw.Container(color: bgPage)),
    );

    // ── Icons, photos, logo — all in parallel ────────────────────────────────
    const photoW = 50.0;
    const photoH = 88.0;

    final allB64s = widget.army.units
        .map((u) => u.photoBase64)
        .where((b) => b != null && b.isNotEmpty)
        .cast<String>()
        .toSet();

    await Future.wait([
      // Icons: 5 types, cached per 'type_mode'
      ...['infantry', 'cavalry', 'ranged', 'artillery', 'hero'].map((type) async {
        final key = '${type}_$_mode';
        if (_iconBytes.containsKey(key)) return;
        final tc  = _pdfTypeColor(type, _mode);
        final uiC = ui.Color.fromARGB(255,
          (tc.red * 255).round(), (tc.green * 255).round(), (tc.blue * 255).round());
        final bytes = await _renderTypeIconBytes(type, uiC, 22.0);
        if (bytes != null) _iconBytes[key] = bytes;
      }),
      // Photos: render color once, derive BW from that
      ...allB64s.map((b64) async {
        if (!_rawPhotos.containsKey(b64)) {
          _rawPhotos[b64] = await _renderCroppedPhoto(b64, photoW, photoH);
        }
        if (isBw && !_bwPhotos.containsKey(b64)) {
          _bwPhotos[b64] = await _toGrayscaleBytes(_rawPhotos[b64]!);
        }
      }),
      // Logo: render raw once, derive color+gradient and BW from it
      if (widget.logoB64 != null && widget.logoB64!.isNotEmpty)
        () async {
          if (_logoRaw == null) {
            _logoRaw = await _renderCroppedPhoto(widget.logoB64!, 400.0, 230.0);
            _logoBw  = await _toGrayscaleBytes(_logoRaw!);
          }
        }(),
    ]);

    final iconImgCache = <String, pw.MemoryImage>{
      for (final type in ['infantry', 'cavalry', 'ranged', 'artillery', 'hero'])
        if (_iconBytes.containsKey('${type}_$_mode'))
          type: pw.MemoryImage(_iconBytes['${type}_$_mode']!),
    };

    final photoCache = <String, pw.MemoryImage>{
      for (final b64 in allB64s)
        if (_rawPhotos.containsKey(b64))
          b64: pw.MemoryImage(isBw ? (_bwPhotos[b64] ?? _rawPhotos[b64]!) : _rawPhotos[b64]!),
    };

    pw.MemoryImage? logoImg;
    PdfColor? logoBgColor;
    if (widget.logoB64 != null && widget.logoB64!.isNotEmpty) {
      final bytes = isBw ? _logoBw : _logoRaw;
      if (bytes != null) logoImg = pw.MemoryImage(bytes);
      if (!isBw) {
        final hex = (widget.logoBgHex ?? '#1E1A15').replaceAll('#', '');
        try { logoBgColor = PdfColor.fromHex(hex); } catch (_) {}
      }
    }

    // ── Roster pages ──────────────────────────────────────────────────────────
    final rosterContent = <pw.Widget>[];
    rosterContent.add(_pdfHeader(widget.army, fBold, fReg, cGold, cGrey, _mode, logoImg, logoBgColor, widget.creator));
    rosterContent.add(pw.SizedBox(height: 14));

    for (final grp in _orderedGroups) {
      final units = _unitsForGroup(grp);
      if (units.isEmpty) continue;

      if (grp.isNotEmpty) {
        rosterContent.add(_pdfGroupHeader(grp, units, fBold, fReg, cGold, cGrey, cGrpBg, cBorder));
        rosterContent.add(pw.SizedBox(height: 6));
      }

      for (int i = 0; i < units.length; i += cols) {
        final row = units.sublist(i, (i + cols).clamp(0, units.length));
        rosterContent.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: gap),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (int j = 0; j < row.length; j++) ...[
                if (j > 0) pw.SizedBox(width: gap),
                pw.SizedBox(
                  width: cardW,
                  child: _pdfUnitCard(row[j], fBold, fReg, cardBg, cGold, cGrey,
                      cDark4, _mode, photoCache, iconImgCache)),
              ],
              if (row.length < cols) ...[
                pw.SizedBox(width: gap),
                pw.SizedBox(width: cardW),
              ],
            ],
          ),
        ));
      }
      rosterContent.add(pw.SizedBox(height: 8));
    }

    doc.addPage(pw.MultiPage(
      pageTheme: makeTheme(),
      build: (_) => rosterContent,
    ));

    // ── Glossary page ─────────────────────────────────────────────────────────
    final usedAbilities = <String>{};
    for (final grp in _orderedGroups) {
      for (final au in _unitsForGroup(grp)) {
        usedAbilities.addAll(au.unit.abilities);
      }
    }

    if (usedAbilities.isNotEmpty) {
      final sorted = usedAbilities.toList()..sort();
      final glossContent = <pw.Widget>[];

      glossContent.add(pw.SizedBox(height: 4));
      glossContent.add(pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(10, 5, 10, 5),
        decoration: pw.BoxDecoration(
          color: cGrpBg,
          border: pw.Border(left: pw.BorderSide(color: cBorder, width: 3))),
        child: pw.Text('ABILITIES GLOSSARY',
          style: pw.TextStyle(font: fBold, fontSize: 9.5, color: cGold, letterSpacing: 1.5)),
      ));
      glossContent.add(pw.SizedBox(height: 10));

      for (final name in sorted) {
        final ab   = GameDataService.abilities.where((x) => x['name'] == name).firstOrNull;
        final desc = ab?['description'] as String? ?? '';
        final cost = ab?['cost']        as int?    ?? 0;
        glossContent.add(_pdfAbilityRow(name, desc, cost, fBold, fReg, cGold, cGrey, isDark ? cardBg : null));
        glossContent.add(pw.SizedBox(height: 5));
      }

      doc.addPage(pw.MultiPage(
        pageTheme: makeTheme(),
        build: (_) => glossContent,
      ));
    }

    return doc.save();
  }

  // ── Army header ───────────────────────────────────────────────────────────────

  pw.Widget _pdfHeader(ArmyState army, pw.Font bold, pw.Font reg,
      PdfColor gold, PdfColor grey, String mode,
      pw.MemoryImage? logo, PdfColor? logoBg, String? creator) {
    final isDark = mode == 'color';
    final isBw   = mode == 'bw';
    const headerH = 90.0;

    final headerBg = isBw
        ? PdfColors.white
        : logoBg ?? (isDark ? PdfColor.fromHex('1A1208') : PdfColors.white);

    // With logo + color/white: gradient is baked in → bright text needed.
    final onDark  = logo != null && !isBw;
    // Pick text colour for maximum contrast against the actual header background.
    final headerDark = isDark || (onDark && _isBgDark(logoBg ?? PdfColor.fromHex('1E1A15')));
    final nameFg  = headerDark ? (isDark ? gold : PdfColors.white) : PdfColors.black;
    final valueFg = nameFg;
    final labelFg = isDark ? grey : nameFg;

    final pts = army.totalPoints;
    const chipW = 27.0;

    final stats = [
      ('${army.units.length}',                             'Units'),
      ('${army.units.fold(0, (s, u) => s + u.unit.cp)}',  'AP'),
      ('${army.units.fold(0, (s, u) => s + u.unit.atk)}', 'ATK'),
      ('${army.units.fold(0, (s, u) => s + u.unit.def)}', 'DEF'),
      ('${army.units.fold(0, (s, u) => s + u.unit.rng)}', 'SHO'),
      ('${army.units.fold(0, (s, u) => s + u.unit.mob)}', 'MOB'),
      ('${army.units.fold(0, (s, u) => s + u.unit.con)}', 'STR'),
    ];

    pw.Widget lbl(String t) => pw.SizedBox(width: chipW,
      child: pw.Text(t, textAlign: pw.TextAlign.center,
        style: pw.TextStyle(font: reg, fontSize: 6.5, color: labelFg,
          letterSpacing: 0.8)));

    pw.Widget val(String v) => pw.SizedBox(width: chipW,
      child: pw.Text(v, textAlign: pw.TextAlign.center,
        style: pw.TextStyle(font: bold, fontSize: 13, color: valueFg)));

    final content = pw.Padding(
      padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Line 1: Name — Points
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(army.name.isEmpty ? 'ARMY ROSTER' : army.name.toUpperCase(),
                style: pw.TextStyle(font: bold, fontSize: 15, color: nameFg,
                  letterSpacing: 2.0)),
              pw.Text('$pts / ${army.limit} pts',
                style: pw.TextStyle(font: bold, fontSize: 12, color: nameFg)),
            ]),
          pw.SizedBox(height: 5),
          // Line 2: Creator — Stat labels
          pw.Row(children: [
            pw.Expanded(child: pw.Text(creator ?? '',
              style: pw.TextStyle(font: reg, fontSize: 9, color: labelFg,
                letterSpacing: 1.2))),
            ...stats.map((s) => lbl(s.$2)),
          ]),
          pw.SizedBox(height: 2),
          // Line 3: (spacer) — Stat values aligned under labels
          pw.Row(children: [
            pw.Expanded(child: pw.SizedBox()),
            ...stats.map((s) => val(s.$1)),
          ]),
        ]));

    return pw.SizedBox(
      height: headerH,
      child: pw.Stack(children: [
        pw.Positioned.fill(child: pw.Container(color: headerBg)),
        if (logo != null)
          pw.Positioned.fill(
            child: pw.Center(
              child: pw.Image(logo, fit: pw.BoxFit.contain))),
        pw.Positioned.fill(child: content),
      ]));
  }

  // ── Group header ──────────────────────────────────────────────────────────────

  pw.Widget _pdfGroupHeader(String name, List<ArmyUnit> units,
      pw.Font bold, pw.Font reg,
      PdfColor gold, PdfColor grey, PdfColor bg, PdfColor border) {
    final pts = units.fold(0, (s, u) => s + u.unit.cost);
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(10, 5, 10, 5),
      decoration: pw.BoxDecoration(
        color: bg,
        border: pw.Border(left: pw.BorderSide(color: border, width: 3))),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(name.toUpperCase(),
            style: pw.TextStyle(font: bold, fontSize: 9.5, color: gold, letterSpacing: 1.5)),
          pw.Text('${units.length} units � $pts pts',
            style: pw.TextStyle(font: reg, fontSize: 8, color: grey)),
        ]));
  }

  // ── Unit card ─────────────────────────────────────────────────────────────────

  pw.Widget _pdfUnitCard(ArmyUnit au, pw.Font bold, pw.Font reg,
      PdfColor cardBg, PdfColor cGold, PdfColor cGrey, PdfColor cDark4,
      String mode,
      Map<String, pw.MemoryImage> photoCache,
      Map<String, pw.MemoryImage> iconImgCache) {

    final isDark = mode == 'color';
    final unit   = au.unit;
    final name   = au.customName.isNotEmpty ? au.customName : unit.name;
    final tc       = _pdfTypeColor(unit.type, mode);
    final tcBg     = (mode == 'bw') ? cardBg : _blend(tc, 0.12, cardBg);
    final tcBorder = (mode == 'bw') ? PdfColors.black : _blend(tc, 0.40, cardBg);

    final photo = au.photoBase64 != null ? photoCache[au.photoBase64!] : null;

    pw.Widget statBox(String label, String value, bool dimmed) {
      final PdfColor lc;
      final PdfColor vc;
      if (isDark) {
        lc = dimmed ? _blend(cGrey, 0.35, cDark4) : cGrey;
        vc = dimmed ? _blend(PdfColors.white, 0.2, cDark4) : PdfColors.white;
      } else {
        lc = dimmed ? const PdfColor(0.65, 0.65, 0.65) : cGrey;
        vc = dimmed ? const PdfColor(0.65, 0.65, 0.65) : PdfColors.black;
      }
      return pw.Expanded(child: pw.Container(
        margin: const pw.EdgeInsets.only(right: 1),
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        color: isDark ? cDark4 : null,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(label, textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: reg, fontSize: 6, color: lc)),
            pw.Text(value, textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: bold, fontSize: 11, color: vc)),
          ])));
    }

    pw.Widget abilityTag(String a) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: pw.BoxDecoration(
        color: tcBg,
        border: pw.Border.all(color: _blend(tc, 0.45, cardBg), width: 0.5)),
      child: pw.Text(a, style: pw.TextStyle(font: reg, fontSize: 6, color: tc)));

    return pw.SizedBox(
      height: 88,
      child: pw.Container(
      decoration: pw.BoxDecoration(
        color: cardBg,
        border: pw.Border.all(color: tcBorder, width: 1.5)),
      padding: const pw.EdgeInsets.all(1.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            width: 50,
            child: photo != null
              ? pw.Container(
                  decoration: pw.BoxDecoration(
                    image: pw.DecorationImage(image: photo, fit: pw.BoxFit.cover)))
              : pw.Container(
                  color: tcBg,
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      if (iconImgCache.containsKey(unit.type.toLowerCase()))
                        pw.Image(iconImgCache[unit.type.toLowerCase()]!,
                          width: 24, height: 24, fit: pw.BoxFit.contain)
                      else
                        pw.Text(_typeAbbrev(unit.type),
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(font: bold, fontSize: 13, color: tc)),
                      pw.SizedBox(height: 3),
                      pw.Text(unit.type,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(font: reg, fontSize: 7, color: tc)),
                    ]))),
          pw.Expanded(child: pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(7, 3, 5, 3),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(child: pw.Text(name, maxLines: 1,
                      style: pw.TextStyle(font: bold, fontSize: 9.5, color: cGold))),
                    pw.Text('${unit.cost}pts',
                      style: pw.TextStyle(font: bold, fontSize: 8.5, color: cGrey)),
                  ]),
                pw.SizedBox(height: 2),
                pw.Row(children: [
                  statBox('ATK', '${unit.atk}', unit.atk == 0),
                  statBox('DEF', '${unit.def}', unit.def == 0),
                  statBox('SHO', '${unit.rng}', unit.rng == 0),
                  statBox('MOB', '${unit.mob}', unit.mob == 0),
                  statBox('STR', '${unit.con}', unit.con == 0),
                  statBox('AP',  '${unit.cp}',  unit.cp  == 0),
                ]),
                if (unit.abilities.isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Wrap(
                    spacing: 3, runSpacing: 2,
                    children: unit.abilities.map(abilityTag).toList()),
                ],
                pw.SizedBox(height: 3),
              ]))),
        ])));
  }

  // ── Ability row for glossary ──────────────────────────────────────────────────

  pw.Widget _pdfAbilityRow(String name, String desc, int cost,
      pw.Font bold, pw.Font reg,
      PdfColor cGold, PdfColor cGrey, PdfColor? cardBg) {

    final cpMatch = RegExp(r'^(\d+)\s*CP:').firstMatch(desc);
    final cpLabel = cpMatch != null ? '${cpMatch.group(1)} CP' : null;
    final bg = cardBg ?? PdfColors.white;

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: cardBg,
        border: cardBg != null
          ? pw.Border(
              left:   pw.BorderSide(color: _blend(cGold, 0.55, bg), width: 2),
              right:  pw.BorderSide(color: _blend(cGold, 0.20, bg), width: 0.5),
              top:    pw.BorderSide(color: _blend(cGold, 0.20, bg), width: 0.5),
              bottom: pw.BorderSide(color: _blend(cGold, 0.20, bg), width: 0.5))
          : pw.Border(
              left: pw.BorderSide(color: _blend(cGold, 0.55, bg), width: 2))),
      child: pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(10, 6, 8, 6),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(name,
                  style: pw.TextStyle(font: bold, fontSize: 10, color: cGold)),
                if (cpLabel != null) ...[
                  pw.SizedBox(width: 7),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: _blend(cGold, 0.65, bg), width: 1)),
                    child: pw.Text(cpLabel,
                      style: pw.TextStyle(font: bold, fontSize: 9, color: cGold))),
                ],
              ]),
            if (desc.isNotEmpty) ...[
              pw.SizedBox(height: 3),
              pw.Text(desc,
                style: pw.TextStyle(font: reg, fontSize: 8, color: cGrey)),
            ],
          ])));
  }

  // ── Flutter UI ────────────────────────────────────────────────────────────────

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _dark,
      appBar: AppBar(
        backgroundColor: AppColors.dark,
        leading: NavBtn(
          icon: Icons.arrow_back_ios_new,
          onPressed: () => Navigator.pop(context)),
        title: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            widget.army.name.isEmpty ? 'Print Army' : 'Print � ${widget.army.name}',
            style: GoogleFonts.cinzel(color: _gold, fontSize: 15, letterSpacing: 1)),
          if (widget.creator != null && widget.creator!.isNotEmpty)
            Text('by ${widget.creator}',
              style: GoogleFonts.cinzel(color: AppColors.grey, fontSize: 11)),
        ]),
        centerTitle: true,
        actions: [
          _ModeBtn(label: 'Color', active: _mode == 'color', onTap: () => setState(() => _mode = 'color')),
          const SizedBox(width: 4),
          _ModeBtn(label: 'White', active: _mode == 'white', onTap: () => setState(() => _mode = 'white')),
          const SizedBox(width: 4),
          _ModeBtn(label: 'B&W',   active: _mode == 'bw',    onTap: () => setState(() => _mode = 'bw')),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PdfPreview(
              key: ValueKey(_mode),
              build: _buildPdf,
              allowPrinting: false,
              allowSharing: false,
              canChangeOrientation: false,
              canChangePageFormat: false,
              useActions: false,
              pdfFileName: '${widget.army.name.isEmpty ? "army" : widget.army.name.toLowerCase().replaceAll(" ", "_")}.pdf',
              loadingWidget: const Center(child: CircularProgressIndicator(color: _gold)),
              previewPageMargin: const EdgeInsets.all(8),
              scrollViewDecoration: const BoxDecoration(color: AppColors.dark),
              pdfPreviewPageDecoration: const BoxDecoration(
                boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 6)]),
            ),
          ),
          Container(
            color: AppColors.dark,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                NavBtn(icon: Icons.print,  onPressed: _printPdf),
                NavBtn(icon: Icons.file_download,  onPressed: _sharePdf),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _pdfFileName => widget.army.name.isEmpty
      ? 'army.pdf'
      : '${widget.army.name.toLowerCase().replaceAll(" ", "_")}.pdf';

  Future<void> _printPdf() async {
    await Printing.layoutPdf(
      onLayout: _buildPdf,
      name: widget.army.name.isEmpty ? 'Army' : widget.army.name,
    );
  }

  Future<void> _sharePdf() async {
    final bytes = await _buildPdf(PdfPageFormat.a4);
    await Printing.sharePdf(bytes: bytes, filename: _pdfFileName);
  }
}

// ── Toggle button ─────────────────────────────────────────────────────────────
class _ModeBtn extends StatefulWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ModeBtn({required this.label, required this.active, required this.onTap});
  @override State<_ModeBtn> createState() => _ModeBtnState();
}
class _ModeBtnState extends State<_ModeBtn> {
  bool _hovered = false;
  @override Widget build(BuildContext context) {
    const gold = AppColors.gold;
    const grey = AppColors.grey;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: widget.active
              ? gold.withValues(alpha: 0.15)
              : _hovered ? gold.withValues(alpha: 0.07) : Colors.transparent,
            border: Border.all(
              color: widget.active ? gold : gold.withValues(alpha: 0.3),
              width: widget.active ? 1.5 : 1)),
          child: Text(widget.label,
            style: GoogleFonts.cinzel(
              color: widget.active ? gold : grey,
              fontSize: 11,
              fontWeight: widget.active ? FontWeight.w600 : FontWeight.normal)),
        ),
      ),
    );
  }
}

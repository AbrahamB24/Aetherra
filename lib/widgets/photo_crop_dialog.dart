import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../app_theme.dart';

/// Renders a cropped photo at [displayW] × [displayH], applying the stored
/// pan/zoom from the JSON envelope so the result matches the crop dialog view.
/// Falls back to BoxFit.contain for plain base64 images.
Widget buildCroppedPhotoDisplay(String photoBase64, double displayW, double displayH) {
  try {
    final raw = base64Decode(photoBase64);
    if (raw.isNotEmpty && raw[0] == 0x7B) {
      final info      = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      final srcBytes  = base64Decode(info['src'] as String);
      final scale     = (info['scale']   as num?)?.toDouble() ?? 1.0;
      final ox        = (info['offsetX'] as num?)?.toDouble() ?? 0.0;
      final oy        = (info['offsetY'] as num?)?.toDouble() ?? 0.0;
      final prevW = (info['previewW'] as num?)?.toDouble()
                 ?? (info['_pw']      as num?)?.toDouble() ?? 200.0;
      final prevH = (info['previewH'] as num?)?.toDouble()
                 ?? (info['_ph']      as num?)?.toDouble() ?? 350.0;
      final k       = math.min(displayW / prevW, displayH / prevH);
      final hCenter = (displayW - prevW * k) / 2.0;
      final vCenter = (displayH - prevH * k) / 2.0;
      return ClipRect(
        child: SizedBox(
          width: displayW, height: displayH,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: Transform.translate(
              offset: Offset(ox * k + hCenter, oy * k + vCenter),
              child: Transform.scale(
                scale: scale * k,
                alignment: Alignment.topLeft,
                child: Image.memory(srcBytes, fit: BoxFit.none))))));
    }
  } catch (_) {}
  return Image.memory(
    decodePhotoBytes(photoBase64),
    width: displayW, height: displayH,
    fit: BoxFit.contain);
}

/// Decodes a photoBase64 string into raw image bytes.
/// Handles both plain base64 images and JSON-wrapped crop envelopes
/// produced by [pickAndCropPhoto].
Uint8List decodePhotoBytes(String photoBase64) {
  try {
    final raw = base64Decode(photoBase64);
    if (raw.isNotEmpty && raw[0] == 0x7B) {
      final info = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      return base64Decode(info['src'] as String);
    }
    return raw;
  } catch (_) {}
  return base64Decode(photoBase64);
}

/// Converts a legacy JSON-envelope photo to a pre-rendered 160×280 PNG thumbnail.
/// Returns the migrated string, or the original if already in new format or on error.
Future<String> migratePhotoIfNeeded(String photoBase64) async {
  try {
    final raw = base64Decode(photoBase64);
    if (raw[0] != 0x7B) return photoBase64; // already new PNG format

    final info  = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
    final srcB  = base64Decode(info['src'] as String);
    final scale = (info['scale']    as num?)?.toDouble() ?? 1.0;
    final ox    = (info['offsetX']  as num?)?.toDouble() ?? 0.0;
    final oy    = (info['offsetY']  as num?)?.toDouble() ?? 0.0;
    final prevW = (info['previewW'] as num?)?.toDouble()
               ?? (info['_pw']      as num?)?.toDouble() ?? 200.0;
    final prevH = (info['previewH'] as num?)?.toDouble()
               ?? (info['_ph']      as num?)?.toDouble() ?? 350.0;

    final codec = await ui.instantiateImageCodec(srcB);
    final frame = await codec.getNextFrame();
    final src   = frame.image;
    final imgW  = src.width.toDouble();
    final imgH  = src.height.toDouble();

    const outW = 160.0;
    const outH = 280.0;

    final visL = math.max(0.0, ox);
    final visT = math.max(0.0, oy);
    final visR = math.min(prevW, ox + imgW * scale);
    final visB = math.min(prevH, oy + imgH * scale);

    if (visR > visL && visB > visT) {
      final recorder = ui.PictureRecorder();
      final canvas   = Canvas(recorder);
      canvas.drawRect(const Rect.fromLTWH(0, 0, outW, outH),
        Paint()..color = AppColors.dark);
      canvas.drawImageRect(
        src,
        Rect.fromLTRB(
          (visL - ox) / scale, (visT - oy) / scale,
          (visR - ox) / scale, (visB - oy) / scale),
        Rect.fromLTRB(
          visL / prevW * outW, visT / prevH * outH,
          visR / prevW * outW, visB / prevH * outH),
        Paint()..filterQuality = FilterQuality.high);
      final img  = await recorder.endRecording().toImage(outW.toInt(), outH.toInt());
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      src.dispose();
      img.dispose();
      if (data != null) return base64Encode(data.buffer.asUint8List());
    }
    src.dispose();
  } catch (_) {}
  return photoBase64;
}

/// Open the crop dialog for an existing logo so the user can re-adjust zoom/pan.
Future<String?> editLogoCropPhoto(BuildContext context, String existingBase64) async {
  try {
    Uint8List imageBytes;
    double?   initialScale;
    Offset?   initialOffset;
    try {
      final raw = base64Decode(existingBase64);
      if (raw.isNotEmpty && raw[0] == 0x7B) {
        final info   = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
        imageBytes   = base64Decode(info['src'] as String);
        initialScale = (info['scale']   as num?)?.toDouble();
        final ox     = (info['offsetX'] as num?)?.toDouble();
        final oy     = (info['offsetY'] as num?)?.toDouble();
        if (ox != null && oy != null) initialOffset = Offset(ox, oy);
      } else {
        imageBytes = raw;
      }
    } catch (_) {
      imageBytes = base64Decode(existingBase64);
    }
    if (!context.mounted) return null;
    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CropDialog(
        imageBytes:    imageBytes,
        initialScale:  initialScale,
        initialOffset: initialOffset,
        previewW: 200,
        previewH: 115,
        fillToFit: initialScale == null,
        cropType: 'logo')); // fill only if no saved crop
  } catch (_) {
    return null;
  }
}

/// Pick a logo image and open a zoom/pan dialog (landscape preview).
/// Returns a JSON-envelope base64 string with crop info, or null if cancelled.
Future<String?> pickLogoPhotoWithCrop(BuildContext context) async {
  try {
    final xfile = await ImagePicker().pickImage(
      source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (xfile == null) return null;
    final bytes = await xfile.readAsBytes();
    if (!context.mounted) return null;
    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CropDialog(
        imageBytes: bytes,
        previewW: 200,
        previewH: 115,
        fillToFit: true,
        cropType: 'logo'));
  } catch (_) {
    return null;
  }
}

/// Pick a photo and show crop/pan/zoom dialog.
Future<String?> pickAndCropPhoto(BuildContext context) async {
  try {
    final picker = ImagePicker();
    final xfile  = await picker.pickImage(
      source: ImageSource.gallery, maxWidth: 600, imageQuality: 82);
    if (xfile == null) return null;
    final bytes = await xfile.readAsBytes();
    if (!context.mounted) return null;
    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CropDialog(imageBytes: bytes));
  } catch (_) {
    return null;
  }
}

/// Open the crop dialog pre-loaded with an existing photo and its saved crop.
/// [showDelete] adds a delete icon that returns '' as a delete sentinel.
Future<String?> editCropPhoto(BuildContext context, String existingBase64,
    {bool showDelete = false}) async {
  try {
    Uint8List imageBytes;
    double?  initialScale;
    Offset?  initialOffset;
    try {
      final raw = base64Decode(existingBase64);
      if (raw.isNotEmpty && raw[0] == 0x7B) {
        final info    = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
        imageBytes    = base64Decode(info['src'] as String);
        initialScale  = (info['scale']   as num?)?.toDouble();
        final ox      = (info['offsetX'] as num?)?.toDouble();
        final oy      = (info['offsetY'] as num?)?.toDouble();
        if (ox != null && oy != null) initialOffset = Offset(ox, oy);
      } else {
        imageBytes = raw;
      }
    } catch (_) {
      imageBytes = base64Decode(existingBase64);
    }
    if (!context.mounted) return null;
    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CropDialog(
        imageBytes:    imageBytes,
        initialScale:  initialScale,
        initialOffset: initialOffset,
        showDelete:    showDelete));
  } catch (_) {
    return null;
  }
}

class _CropDialog extends StatefulWidget {
  final Uint8List imageBytes;
  final double?  initialScale;
  final Offset?  initialOffset;
  final bool     showDelete;
  final double   previewW;
  final double   previewH;
  final bool     fillToFit; // true = cover (logo), false = contain (portrait)
  final String?  cropType;  // stored in JSON envelope for display scaling
  const _CropDialog({required this.imageBytes, this.initialScale,
    this.initialOffset, this.showDelete = false,
    this.previewW = 200.0, this.previewH = 350.0,
    this.fillToFit = false, this.cropType});
  @override State<_CropDialog> createState() => _CropDialogState();
}

class _CropDialogState extends State<_CropDialog> {
  static const gold  = AppColors.gold;
  double get _pad => widget.cropType == 'logo' ? 20.0 : 50.0;

  double get _pw => widget.previewW;
  double get _ph => widget.previewH;

  double _scale = 1.0;
  Offset _offset = Offset.zero;

  double _scaleAtStart  = 1.0;
  Offset _offsetAtStart = Offset.zero;
  Offset _focalAtStart  = Offset.zero;
  bool   _dragging      = false;

  double _imgW = 1, _imgH = 1;
  bool _loaded = false;
  bool _confirming = false;
  ui.Image? _srcImage;
  late Uint8List _imageBytes;

  @override void initState() {
    super.initState();
    _imageBytes = widget.imageBytes;
    _loadSize();
  }

  @override void dispose() {
    _srcImage?.dispose();
    super.dispose();
  }

  Future<void> _loadSize() async {
    final codec = await ui.instantiateImageCodec(_imageBytes);
    final frame = await codec.getNextFrame();
    if (!mounted) { frame.image.dispose(); return; }
    setState(() {
      _srcImage?.dispose();
      _srcImage = frame.image;
      _imgW = frame.image.width.toDouble();
      _imgH = frame.image.height.toDouble();
      _loaded = true;
      if (widget.initialScale != null) {
        _scale  = widget.initialScale!;
        _offset = widget.initialOffset ?? Offset.zero;
      } else {
        final sx = _pw / _imgW;
        final sy = _ph / _imgH;
        _scale = widget.fillToFit
            ? math.max(sx, sy) // cover: fill area (logo)
            : math.min(sx, sy); // contain: show full photo (portrait)
      }
    });
  }

  Future<void> _replace() async {
    try {
      final picker = ImagePicker();
      final xfile  = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 600, imageQuality: 82);
      if (xfile == null || !mounted) return;
      final bytes = await xfile.readAsBytes();
      setState(() { _imageBytes = bytes; _loaded = false; _scale = 1.0; _offset = Offset.zero; });
      await _loadSize();
    } catch (_) {}
  }

  void _onScaleStart(ScaleStartDetails d) {
    _scaleAtStart  = _scale;
    _offsetAtStart = _offset;
    _focalAtStart  = d.localFocalPoint;
    setState(() => _dragging = true);
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      _scale = (_scaleAtStart * d.scale).clamp(0.05, 8.0);
      final r = _scale / _scaleAtStart;
      _offset = d.localFocalPoint - (_focalAtStart - _offsetAtStart) * r;
    });
  }

  void _onScaleEnd(ScaleEndDetails d) {
    setState(() => _dragging = false);
  }

  void _onScroll(PointerScrollEvent e) {
    final d  = e.scrollDelta.dy > 0 ? -0.08 : 0.08;
    final ns = (_scale + d).clamp(0.05, 8.0);
    final r  = ns / _scale;
    setState(() {
      _offset = Offset(
        e.localPosition.dx - (e.localPosition.dx - _offset.dx) * r,
        e.localPosition.dy - (e.localPosition.dy - _offset.dy) * r);
      _scale = ns;
    });
  }

  Future<void> _confirm() async {
    if (_confirming) return;
    setState(() => _confirming = true);
    try {
      final result = await _renderCrop();
      if (mounted) Navigator.pop(context, result);
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<String> _renderCrop() async {
    // Store full image + crop position so the original is always recoverable.
    return base64Encode(utf8.encode(jsonEncode({
      'src':      base64Encode(_imageBytes),
      'offsetX':  _offset.dx,
      'offsetY':  _offset.dy,
      'scale':    _scale,
      'previewW': _pw,
      'previewH': _ph,
      if (widget.cropType != null) 'type': widget.cropType,
    })));
  }

  @override Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.dark,
      shape: const RoundedRectangleBorder(),
      child: Container(
        width: _pw + _pad * 2 + 40,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.dark,
          border: Border.all(color: gold.withValues(alpha: 0.4))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _buildContent())));
  }

  List<Widget> _buildContent() {
    return [
      Row(children: [
        Container(width: 3, height: 16, color: gold),
        const SizedBox(width: 10),
        Text('Adjust Photo', style: GoogleFonts.cinzel(
          color: gold, fontSize: 14, letterSpacing: 1.5)),
        const Spacer(),
        _CropIconBtn(
          icon: Icons.add_photo_alternate_outlined,
          color: gold,
          onTap: _replace),
        if (widget.showDelete) ...[
          const SizedBox(width: 8),
          _CropIconBtn(
            icon: Icons.delete_outline,
            color: Colors.red,
            onTap: () => Navigator.pop(context, '')),
        ],
      ]),
      const SizedBox(height: 16),

      _buildPreview(),

      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: _DialogBtn(
          label: 'Cancel', outlined: true,
          onTap: _confirming ? () {} : () => Navigator.pop(context, null))),
        const SizedBox(width: 10),
        Expanded(child: _confirming
          ? const Center(child: SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(color: gold, strokeWidth: 2)))
          : _DialogBtn(label: 'Use Photo', onTap: _confirm)),
      ]),
    ];
  }

  Widget _buildPreview() {
    return SizedBox(
      width: _pw + _pad * 2,
      height: _ph + _pad * 2,
      child: Stack(children: [
        // AppColors.dark background
        const Positioned.fill(child: ColoredBox(color: AppColors.dark)),

        // Full-brightness image — visible everywhere, no clipping
        if (_loaded)
          Positioned(
            left: _offset.dx + _pad, top: _offset.dy + _pad,
            width: _imgW * _scale, height: _imgH * _scale,
            child: Image.memory(_imageBytes, fit: BoxFit.fill))
        else
          const Center(child: CircularProgressIndicator(color: gold, strokeWidth: 2)),

        // Interaction layer within crop window
        Positioned(
          left: _pad, top: _pad, width: _pw, height: _ph,
          child: MouseRegion(
            cursor: _dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerSignal: (e) {
                if (e is PointerScrollEvent) _onScroll(e);
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                onScaleEnd: _onScaleEnd,
                child: const SizedBox.expand())))),

        // Gold border — shows the saved crop area
        Positioned(
          left: _pad, top: _pad, width: _pw, height: _ph,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: gold.withValues(alpha: 0.6), width: 1.5))))),
      ]));
  }
}

class _DialogBtn extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool outlined;
  const _DialogBtn({required this.label, required this.onTap, this.outlined = false});
  @override State<_DialogBtn> createState() => _DialogBtnState();
}
class _DialogBtnState extends State<_DialogBtn> {
  bool _hovered = false, _pressed = false;
  static const gold = AppColors.gold;
  @override Widget build(BuildContext context) =>
    MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown:   (_) => setState(() => _pressed = true),
        onTapUp:     (_) { setState(() => _pressed = false); widget.onTap(); },
        onTapCancel: ()  => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          transform: _pressed ? (Matrix4.identity()..scaleByDouble(0.96, 0.96, 1.0, 1.0)) : Matrix4.identity(),
          transformAlignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: widget.outlined
              ? Colors.transparent
              : _pressed
                ? gold.withValues(alpha: 0.45)
                : gold.withValues(alpha: _hovered ? 0.7 : 1.0),
            border: widget.outlined
              ? Border.all(color: gold.withValues(alpha: _hovered ? 0.6 : 0.3))
              : null),
          child: Text(widget.label,
            textAlign: TextAlign.center,
            style: GoogleFonts.cinzel(
              color: widget.outlined
                ? gold.withValues(alpha: _hovered ? 0.8 : 0.5)
                : AppColors.dark,
              fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)))));
}

class _CropIconBtn extends StatefulWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _CropIconBtn({required this.icon, required this.color, required this.onTap});
  @override State<_CropIconBtn> createState() => _CropIconBtnState();
}
class _CropIconBtnState extends State<_CropIconBtn> {
  bool _hovered = false;
  @override Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit:  (_) => setState(() => _hovered = false),
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: Center(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 80),
            opacity: _hovered ? 1.0 : 0.55,
            child: Icon(widget.icon, color: widget.color, size: 20))))));
}
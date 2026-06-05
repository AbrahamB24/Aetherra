import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_theme.dart';
import '../models/army_state.dart';
import '../services/army_service.dart';
import '../services/subscription_service.dart';
import '../services/game_data_service.dart';
import '../services/bg_remover.dart';
import '../widgets/aetherra_dialog.dart';
import '../widgets/aetherra_text_field.dart';
import '../widgets/photo_crop_dialog.dart';
import '../widgets/unit_card.dart';
import '../widgets/group_trash_btn.dart';
import '../widgets/nav_btn.dart';
import 'my_factions_screen.dart';
import '../widgets/dnd_unit_grid.dart';
import 'army_print_screen.dart';
import '../game/notifiers/game_notifier.dart';
import 'builder_screen.dart';

const _kArmyBgPresets = [
  // Very AppColors.dark
  '#0D0B09', '#08111E', '#0A1A08', '#1A0808',
  '#120820', '#14061A', '#1A1004', '#1A0C0C',
  // AppColors.dark
  '#2D1B0E', '#0C2244', '#112C11', '#3C1111',
  '#1D1142', '#113D3D', '#3D2008', '#2C1024',
  // Medium
  '#5C3C1E', '#1E4E82', '#1E5E1E', '#6E1E1E',
  '#3C1C6E', '#1E5E5E', '#6E3E0E', '#4E1C40',
  // Medium-light
  '#8C6040', '#3A74AA', '#3A7440', '#A43C3C',
  '#5C3CAA', '#3A9292', '#AA6C20', '#7C3468',
  // Light
  '#C8A870', '#70AACC', '#70BC70', '#D48888',
  '#9870CC', '#70C0C0', '#CCAA38', '#C07898',
];

class ArmyViewScreen extends StatefulWidget {
  final String? imageB64;
  final String? bgColor;
  final String? creatorName;
  final String? lore;
  const ArmyViewScreen({super.key, this.imageB64, this.bgColor, this.creatorName, this.lore});
  @override
  State<ArmyViewScreen> createState() => _ArmyViewScreenState();
}

class _ArmyViewScreenState extends State<ArmyViewScreen> {
  static const gold  = AppColors.gold;
  static const grey  = AppColors.grey;
  static final sb    = Supabase.instance.client;

  bool _saving = false;
  bool _bannerVisible = true;
  final Set<String> _collapsedGroups = {};
  String? _imageB64;
  Widget? _cachedPhoto;
  String  _bgColor = '#1E1A15';
  String? _lore;
  bool    _loreOpen     = false;
  bool    _loreHovered  = false;
  bool    _unitsOpen    = false;
  bool    _unitsHovered = false;

  @override
  void initState() {
    super.initState();
    _imageB64  = widget.imageB64;
    if (_imageB64 != null) _cachedPhoto = buildCroppedPhotoDisplay(_imageB64!, AppColors.bannerW, AppColors.bannerH);
    _bgColor   = widget.bgColor ?? '#1E1A15';
    _lore = widget.lore;
  }

  void _toggleLore() => setState(() => _loreOpen = !_loreOpen);

  Future<void> _reloadMeta(String? listId) async {
    if (listId == null) return;
    try {
      final row = await sb.from('army_lists')
        .select('army_data').eq('id', listId).single();
      final ad = Map<String, dynamic>.from(row['army_data'] as Map? ?? {});
      if (mounted) {
        setState(() {
          _imageB64 = ad['image_b64'] as String?;
          _cachedPhoto = _imageB64 != null ? buildCroppedPhotoDisplay(_imageB64!, AppColors.bannerW, AppColors.bannerH) : null;
          _bgColor  = ad['bg_color']  as String? ?? '#1E1A15';
          _lore     = ad['lore']      as String?;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ArmyState>(builder: (_, army, __) =>
      Scaffold(
        backgroundColor: AppColors.dark,
        appBar: AppBar(
          leading: NavBtn(
            icon: Icons.arrow_back_ios_new,
            onPressed: () => Navigator.of(context).pop()),
          title: _saving
            ? const SizedBox(width: 10, height: 10,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: gold))
            : null,
          actions: [
            NavBtn(
              icon: Icons.edit_outlined,
              onPressed: () => _openEditSheet(context, army)),
            if (army.units.isNotEmpty) ...[
              NavBtn(
                icon: Icons.share_outlined,
                onPressed: () => _shareArmy(army)),
              NavBtn(
                icon: Icons.print_outlined,
                onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => ArmyPrintScreen(
                    army:      army,
                    logoB64:   _imageB64,
                    logoBgHex: _bgColor,
                    creator:   widget.creatorName)))),
            ],
            const SizedBox(width: 4),
          ],
        ),
        body: Column(children: [
          // Banner inline — slides up and fades on scroll
          AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: _bannerVisible ? 1.0 : 0.0,
            child: ClipRect(
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOut,
                alignment: Alignment.bottomCenter,
                heightFactor: _bannerVisible ? 1.0 : 0.0,
                child: _buildHeader(context, army)))),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 2),
            child: Center(child: PressBtn(
              label: 'New Cohort',
              centered: false,
              fontSize: 14,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              onTap: () => _addGroupDialog(context, army)))),
          Expanded(
            child: Stack(children: [
            NotificationListener<ScrollUpdateNotification>(
              onNotification: (n) {
                final show = n.metrics.pixels < 40;
                if (show != _bannerVisible) setState(() => _bannerVisible = show);
                return false;
              },
              child: army.units.isEmpty
                ? Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shield_outlined,
                        color: gold.withValues(alpha: 0.2), size: 40),
                      const SizedBox(height: 12),
                      Text('No units in this army.',
                        style: GoogleFonts.cinzel(color: grey, fontSize: 17)),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) =>
                            BuilderScreen(editMode: true,
                              showBack: true,
                              initialFactions: army.factionIds))),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: gold,
                          side: BorderSide(color: gold.withValues(alpha: 0.4)),
                          shape: const RoundedRectangleBorder()),
                        child: Text('Add Units',
                          style: GoogleFonts.cinzel(fontSize: 15))),
                    ]))
                : LayoutBuilder(builder: (ctx2, constraints) {
                    final w3   = constraints.maxWidth - 20;
                    final cols = (w3 / (260 + 8)).floor().clamp(1, 6);
                    final cardW = ((w3 - (cols - 1) * 8) / cols)
                      .clamp(260.0, 500.0);
                    return DndUnitGrid(
                      units:    army.units,
                      groups:   army.groups,
                      cardW:    cardW,
                      cols:     cols,
                      onReorder: () { army.refresh(); _autoSave(army); },
                      groupHeader: (grp, isDragOver) => _groupHeader(grp, army, isDragOver: isDragOver),
                      onEdit: (unit) => _editUnit(context, unit, army),
                      collapsedGroups: _collapsedGroups);
                  }),
            ),
              // gradient fade at top of scroll area
              const Positioned(
                top: 0, left: 0, right: 0, height: 36,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [AppColors.dark, Colors.transparent]))))),
              const Positioned(
                bottom: 0, left: 0, right: 0, height: 36,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [AppColors.dark, Colors.transparent]))))),
            ]),
          ),
        ]),
      ));
  }

  // â"€â"€ Share army â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
  Future<void> _shareArmy(ArmyState army) async {
    // Show spinner while generating
    showAetherraDialogRaw<void>(context,
      aetherraDialogContainer(
        title: 'Share Army',
        content: const SizedBox(
          height: 60,
          child: Center(child: CircularProgressIndicator(color: AppColors.gold)))),
      barrierDismissible: false);

    String? code;
    String? error;
    try {
      code = await ArmyService.shareArmy(army, army.listId);
    } catch (e) {
      error = e.toString();
    }

    if (!mounted) return;
    Navigator.of(context).pop(); // close spinner

    Widget shareContent;
    if (error != null) {
      shareContent = Text('Failed to generate share code.\n$error',
        style: GoogleFonts.cinzel(color: Colors.redAccent, fontSize: 13));
    } else if (code == null) {
      shareContent = Text('Could not generate a share code.',
        style: GoogleFonts.cinzel(color: AppColors.grey, fontSize: 13));
    } else {
      shareContent = Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Share this code with your friends:',
          style: GoogleFonts.cinzel(color: AppColors.grey, fontSize: 13)),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
              color: AppColors.dark),
            child: SelectableText(code,
              style: GoogleFonts.cinzel(
                color: AppColors.gold, fontSize: 28, letterSpacing: 6,
                fontWeight: FontWeight.bold))),
          NavBtn(
            icon: Icons.copy_outlined,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code!));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  backgroundColor: AppColors.dark,
                  content: Text('Code "$code" kopiert!',
                    style: GoogleFonts.cinzel(color: AppColors.gold))));
              }
            }),
        ]),
      ]);
    }

    await showAetherraDialogRaw<void>(context,
      aetherraDialogContainer(
        title: 'Share Army',
        content: shareContent,
        actions: [
          aDialogBtn('Cancel', AppColors.grey, () => Navigator.of(context).pop()),
          if (code != null)
            aDialogBtn('Send', AppColors.gold, () async {
              Navigator.of(context).pop();
              final armyName = army.name.isEmpty ? 'Unnamed Army' : army.name;
              final text = 'Join my Aetherra army "$armyName"!\n'
                           'Import code: $code\n'
                           '(Open Armies → Import → enter the code)';
              bool shared = false;
              try {
                final result = await SharePlus.instance.share(ShareParams(text: text));
                shared = result.status == ShareResultStatus.success;
              } catch (_) {}
              if (!shared && mounted) {
                await Clipboard.setData(ClipboardData(text: code!));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    backgroundColor: AppColors.dark,
                    content: Text('Code "$code" kopiert!',
                      style: GoogleFonts.cinzel(color: AppColors.gold))));
                }
              }
            }),
        ],
      ));
  }

  // â"€â"€ Edit bottom sheet â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
  Future<void> _openEditSheet(BuildContext context, ArmyState army) async {
    // Load current metadata from DB
    Map<String, dynamic> ad = {};
    if (army.listId != null) {
      try {
        final row = await sb.from('army_lists')
          .select('army_data').eq('id', army.listId!).single();
        ad = Map<String, dynamic>.from(row['army_data'] as Map? ?? {});
      } catch (_) {}
    }

    String? imageB64 = ad['image_b64'] as String?;
    String  selColor = ad['bg_color']  as String? ?? '#1E1A15';
    final   nameCtrl = TextEditingController(text: army.name);
    final   loreCtrl = TextEditingController(text: ad['lore'] as String? ?? '');
    bool    removingBg         = false;
    bool    placeholderHovered = false;
    String? bgError;

    if (!mounted || !context.mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.dark,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) =>
        DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.92,
          builder: (_, scroll) => SingleChildScrollView(
            controller: scroll,
            padding: EdgeInsets.fromLTRB(16, 16, 16,
              MediaQuery.of(context).viewInsets.bottom + 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

              // drag handle
              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(
                  color: grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Text('Edit Army',
                style: GoogleFonts.cinzel(color: gold, fontSize: 17)),
              const SizedBox(height: 14),

              // â"€â"€ Name â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
              _lbl('Name'),
              AetherraTextField(
                controller: nameCtrl,
                hintText: 'Army name...',
                style: const TextStyle(
                  color: AppColors.textLight, fontSize: 14),
                onChanged: (_) {},
              ),
              const SizedBox(height: 16),

              // â"€â"€ Banner preview â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
              Container(
                width: double.infinity, height: 115,
                foregroundDecoration: BoxDecoration(
                  border: Border.all(color: gold.withValues(alpha: 0.35))),
                color: AppColors.parseHex(selColor),
                child: Stack(children: [
                  Positioned.fill(child: imageB64 != null
                    ? Center(child: buildCroppedPhotoDisplay(imageB64!, AppColors.bannerW, AppColors.bannerH))
                    : GestureDetector(
                        onTap: () async {
                          final r = await pickLogoPhotoWithCrop(ctx);
                          if (r != null) setS(() => imageB64 = r);
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onEnter: (_) => setS(() => placeholderHovered = true),
                          onExit:  (_) => setS(() => placeholderHovered = false),
                          child: Center(child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 80),
                            opacity: placeholderHovered ? 1.0 : 0.35,
                            child: const Icon(Icons.add_photo_alternate_outlined,
                              color: gold, size: 44)))))),
                  if (removingBg)
                    Positioned.fill(child: Container(
                      color: AppColors.dark.withValues(alpha: 0.75),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(color: gold),
                          const SizedBox(height: 12),
                          Text('Removing background...',
                            style: GoogleFonts.cinzel(color: gold, fontSize: 12)),
                        ]))),
                ])),

              // â"€â"€ Remove background + bg color â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
              const SizedBox(height: 8),
              Row(children: [
                _UnitPhotoIcon(icon: Icons.add_photo_alternate_outlined,
                  onTap: () async {
                    final r = await pickLogoPhotoWithCrop(ctx);
                    if (r != null) setS(() => imageB64 = r);
                  }),
                if (imageB64 != null) ...[
                  const SizedBox(width: 6),
                  _UnitPhotoIcon(icon: Icons.crop,
                    onTap: () async {
                      final r = await editLogoCropPhoto(ctx, imageB64!);
                      if (r != null) setS(() => imageB64 = r);
                    }),
                  const SizedBox(width: 6),
                  _UnitPhotoIcon(icon: Icons.delete_outline,
                    color: Colors.red, onTap: () => setS(() => imageB64 = null)),
                ],
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(
                  onPressed: (removingBg || imageB64 == null) ? null : () async {
                    setS(() { removingBg = true; bgError = null; });
                    try {
                      final bytes  = decodePhotoBytes(imageB64!);
                      final result = await removeBg(bytes);
                      if (result != null) {
                        String newB64;
                        try {
                          final raw = base64Decode(imageB64!);
                          if (raw.isNotEmpty && raw[0] == 0x7B) {
                            final info = jsonDecode(utf8.decode(raw))
                              as Map<String, dynamic>;
                            newB64 = base64Encode(utf8.encode(
                              jsonEncode({
                                ...info,
                                'src': base64Encode(result),
                              })));
                          } else {
                            newB64 = base64Encode(result);
                          }
                        } catch (_) { newB64 = base64Encode(result); }
                        setS(() { imageB64 = newB64; removingBg = false; });
                      } else {
                        setS(() => removingBg = false);
                      }
                    } catch (e) {
                      setS(() { removingBg = false; bgError = e.toString(); });
                    }
                  },
                  icon: const Icon(Icons.auto_fix_high_outlined,
                    color: gold, size: 15),
                  label: Text('Remove Background',
                    style: GoogleFonts.cinzel(fontSize: 13, letterSpacing: 1)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: gold,
                    side: BorderSide(color: gold.withValues(alpha: 0.5)),
                    shape: const RoundedRectangleBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 10)))),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () async {
                    final picked = await showAetherraDialogRaw<String>(
                      ctx,
                      Builder(builder: (dCtx) => aetherraDialogContainer(
                        title: 'Background Color',
                        content: Wrap(
                          spacing: 8, runSpacing: 8,
                          children: _kArmyBgPresets.map((hex) {
                            final isSel = selColor.toLowerCase() == hex.toLowerCase();
                            return GestureDetector(
                              onTap: () => Navigator.pop(dCtx, hex),
                              child: Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: AppColors.parseHex(hex),
                                  border: Border.all(
                                    color: isSel ? gold : gold.withValues(alpha: 0.25),
                                    width: isSel ? 3.0 : 1.0)),
                                child: isSel
                                  ? const Center(child: Icon(Icons.check,
                                      color: Colors.white, size: 18,
                                      shadows: [Shadow(color: Colors.black87, blurRadius: 6)]))
                                  : null));
                          }).toList()))));
                    if (picked != null) setS(() => selColor = picked);
                  },
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.parseHex(selColor),
                      border: Border.all(color: AppColors.gold, width: 2)))),
              ]),
              const SizedBox(height: 6),
              if (bgError != null)
                Text(bgError!,
                  style: GoogleFonts.cinzel(color: Colors.redAccent, fontSize: 11))
              else
                Text('Tip: Upload a transparent PNG for better results.',
                  style: GoogleFonts.cinzel(color: AppColors.grey.withValues(alpha: 0.85),
                    fontSize: 10, fontStyle: FontStyle.italic)),
              const SizedBox(height: 10),

              _lbl('Lore (optional)'),
              AetherraTextField(
                controller: loreCtrl,
                hintText: 'Lore: origin, history, legend...',
                minLines: 4,
                maxLines: null,
                style: const TextStyle(
                  color: AppColors.textLight, fontSize: 14, height: 1.5),
                contentPadding: const EdgeInsets.all(12),
              ),
              const SizedBox(height: 16),

              SizedBox(width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(context,
                      MaterialPageRoute(builder: (_) =>
                        BuilderScreen(
                          editMode: true,
                          showBack: true,
                          initialFactions: army.factionIds)));
                  },
                  icon: const Icon(Icons.group_outlined,
                    color: gold, size: 15),
                  label: Text('Manage Units',
                    style: GoogleFonts.cinzel(
                      fontSize: 13, letterSpacing: 1)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: gold,
                    side: BorderSide(color: gold.withValues(alpha: 0.5)),
                    shape: const RoundedRectangleBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 12)))),
              const SizedBox(height: 20),

              // â"€â"€ Save â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
              SizedBox(width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final lore = loreCtrl.text.trim();
                    await _saveArmyMeta(
                      army, imageB64, selColor,
                      name.isEmpty ? army.name : name,
                      lore.isEmpty ? null : lore);
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: gold,
                    foregroundColor: AppColors.dark,
                    side: BorderSide.none,
                    shape: const RoundedRectangleBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text('Save',
                    style: GoogleFonts.cinzel(
                      fontSize: 15, letterSpacing: 2)))),
              const SizedBox(height: 8),

              // â"€â"€ Delete â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
              SizedBox(width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final nav = Navigator.of(context);
                    final ok = await showAetherraDialog<bool>(
                      context,
                      title: 'Delete Army?',
                      content: Text('This cannot be undone.',
                        style: GoogleFonts.cinzel(color: grey, fontSize: 13, height: 1.5)),
                      actions: [
                        aDialogBtn('Cancel', grey, () => Navigator.pop(context, false)),
                        aDialogBtn('Delete', Colors.red.shade300, () => Navigator.pop(context, true)),
                      ]);
                    if (ok != true || !mounted) return;
                    if (army.listId != null) {
                      await ArmyService.delete(army.listId!);
                    }
                    if (!mounted) return;
                    nav.popUntil((r) => r.isFirst);
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text('Delete Army',
                    style: GoogleFonts.cinzel(
                      fontSize: 14, letterSpacing: 1)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade300,
                    side: BorderSide(
                      color: Colors.red.shade300.withValues(alpha: 0.5)),
                    shape: const RoundedRectangleBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 12)))),
            ])))));

    await _reloadMeta(
        context.mounted ? context.read<ArmyState>().listId : null);
  }

  Widget _buildHeader(BuildContext context, ArmyState army) {
    final hasImg  = _imageB64 != null;
    final bg      = AppColors.parseHex(_bgColor);
    final pts     = army.totalPoints;
    final over    = army.isOverLimit;
    final hasLore = (_lore ?? '').isNotEmpty;

    return Container(
      color: bg,
      child: Stack(clipBehavior: Clip.hardEdge, children: [

        // Image â€" pinned to top, slides up when lore expands
        if (hasImg) Positioned(
          top: 0, left: 0, right: 0, height: 115,
          child: ClipRect(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: (_loreOpen || _unitsOpen) ? -40.0 : 0.0),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              builder: (_, dy, child) =>
                Transform.translate(offset: Offset(0, dy), child: child),
              child: Center(
                child: _cachedPhoto!)))),

        // Gradient spanning the entire block (header + lore)
        Positioned.fill(child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.45),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.55),
                ],
                stops: const [0.0, 0.4, 1.0]))))),

        // Content column: fixed header + animated lore
        Column(children: [
          SizedBox(
            height: 115,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top: name+creator left | pts right
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(army.name.isEmpty ? 'Army' : army.name,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.cinzel(
                            color: gold, fontSize: 17, letterSpacing: 2,
                            shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])),
                        if (widget.creatorName != null && widget.creatorName!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text('by ${widget.creatorName}',
                            style: GoogleFonts.cinzel(
                              color: Colors.white54, fontSize: 12,
                              shadows: const [Shadow(color: Colors.black87, blurRadius: 4)])),
                        ],
                      ])),
                    Text('$pts / ${army.limit} pts',
                      style: GoogleFonts.cinzel(
                        color: over ? Colors.red : gold,
                        fontSize: 17,
                        shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])),
                  ]),
                  // Bottom: icons left | stats right
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    GestureDetector(
                      onTap: hasLore ? _toggleLore : null,
                      child: MouseRegion(
                        cursor: hasLore ? SystemMouseCursors.click : MouseCursor.defer,
                        onEnter: hasLore ? (_) => setState(() => _loreHovered = true)  : null,
                        onExit:  hasLore ? (_) => setState(() => _loreHovered = false) : null,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 80),
                          opacity: hasLore ? (_loreOpen || _loreHovered ? 1.0 : 0.55) : 0.2,
                          child: Icon(
                            _loreOpen ? Icons.menu_book : Icons.menu_book_outlined,
                            color: gold, size: 18,
                            shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])))),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => setState(() => _unitsOpen = !_unitsOpen),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) => setState(() => _unitsHovered = true),
                        onExit:  (_) => setState(() => _unitsHovered = false),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 80),
                          opacity: _unitsOpen || _unitsHovered ? 1.0 : 0.55,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('${army.units.length}',
                              style: GoogleFonts.cinzel(
                                color: gold, fontSize: 13,
                                shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])),
                            const SizedBox(width: 3),
                            Icon(_unitsOpen ? Icons.group : Icons.group_outlined,
                              color: gold, size: 18,
                              shadows: const [Shadow(color: Colors.black87, blurRadius: 6)]),
                          ])))),
                    const Spacer(),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      BannerStat('${army.totalCP}', 'AP'),
                      BannerStat('${army.units.fold(0, (s, u) => s + u.unit.atk)}', 'ATK'),
                      BannerStat('${army.units.fold(0, (s, u) => s + u.unit.def)}', 'DEF'),
                      BannerStat('${army.units.fold(0, (s, u) => s + u.unit.rng)}', 'SHO'),
                      BannerStat('${army.units.fold(0, (s, u) => s + u.unit.mob)}', 'MOB'),
                      BannerStat('${army.units.fold(0, (s, u) => s + u.unit.con)}', 'STR'),
                    ]),
                  ]),
                ]))),

          // Lore panel
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            child: hasLore && _loreOpen
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                  child: Text(_lore!,
                    style: GoogleFonts.cinzel(
                      color: Colors.white70, fontSize: 13, height: 1.6,
                      fontStyle: FontStyle.italic,
                      shadows: const [Shadow(color: Colors.black87, blurRadius: 8)])))
              : const SizedBox.shrink()),

          // Units panel
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            child: _unitsOpen
              ? BannerUnitsPanel(
                  entries: army.units.map((u) => {
                    'name':  u.customName.isNotEmpty ? u.customName : u.unit.name,
                    'group': u.groupName,
                  }).toList(),
                  groupOrder: army.groups,
                )
              : const SizedBox.shrink()),
        ]),
      ]));
  }

  Future<void> _saveArmyMeta(
      ArmyState army, String? imageB64,
      String bgColor, String name, String? lore) async {
    if (army.listId == null) return;
    final row = await sb.from('army_lists')
      .select('army_data').eq('id', army.listId!).single();
    final ad = Map<String, dynamic>.from(row['army_data'] as Map? ?? {});
    if (imageB64 != null) { ad['image_b64'] = imageB64; }
    else                  { ad.remove('image_b64'); }
    ad['bg_color'] = bgColor;
    if (lore != null) { ad['lore'] = lore; }
    else              { ad.remove('lore'); }
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;
    await sb.from('army_lists').update({
      'name':       name,
      'army_data':  ad,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', army.listId!).eq('user_id', uid);
    army.setName(name);
  }

  // â"€â"€ Helpers â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
  Future<void> _autoSave(ArmyState army) async {
    if (army.listId == null || _saving) return;
    setState(() => _saving = true);
    try {
      await ArmyService.save(army, army.name, army.listId);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addGroupDialog(BuildContext context, ArmyState army) {
    final ctrl = TextEditingController();
    showAetherraDialog(context,
      title: 'New Cohort',
      content: AetherraTextField(
        controller: ctrl,
        autofocus: true,
        hintText: 'Cohort name...'),
      actions: [
        aDialogBtn('Cancel', grey, () => Navigator.pop(context)),
        aDialogBtn('Add', gold, () {
          army.addGroup(ctrl.text.trim());
          Navigator.pop(context);
          _autoSave(army);
        }),
      ]);
  }

  Future<void> _editUnit(
      BuildContext context, ArmyUnit unit, ArmyState army) async {
    if (unit.isEmbedded && !SubscriptionService.isPremium) {
      await showAetherraDialog(context,
        title: 'Premium Required',
        content: Text(
          '"${unit.unit.name}" is a custom unit from a shared army.\n\n'
          'Upgrade to Premium to edit or reuse custom units.',
          style: GoogleFonts.cinzel(color: AppColors.grey, fontSize: 13, height: 1.5)),
        actions: [
          aDialogBtn('Cancel', AppColors.grey, () => Navigator.of(context).pop()),
          aDialogBtn('Upgrade', AppColors.gold, () {
            Navigator.of(context).pop();
            Navigator.push(context,
              MaterialPageRoute(builder: (_) => const MyFactionsScreen()));
          }),
        ]);
      return;
    }
    final isPremium = SubscriptionService.isPremium;
    final isUserUnit = GameDataService.userUnits.any((u) => u['id'] == unit.unit.id);

    void showPremiumMsg() {
      showAetherraDialog(context,
        title: 'Premium Required',
        content: Text(
          'Photo, Lore and Background Color are only available with a Premium subscription.',
          style: GoogleFonts.cinzel(color: grey, fontSize: 13, height: 1.5)),
        actions: [
          aDialogBtn('Cancel', grey, () => Navigator.of(context).pop()),
          aDialogBtn('Upgrade', gold, () {
            Navigator.of(context).pop();
            Navigator.push(context,
              MaterialPageRoute(builder: (_) => const MyFactionsScreen()));
          }),
        ]);
    }
    Widget premiumLock(Widget child) {
      if (isPremium) return child;
      return GestureDetector(
        onTap: showPremiumMsg,
        behavior: HitTestBehavior.opaque,
        child: Stack(children: [
          AbsorbPointer(child: Opacity(opacity: 0.35, child: child)),
          Positioned.fill(child: Container(
            alignment: Alignment.center,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_outline, color: gold, size: 16),
              const SizedBox(width: 6),
              Text('Premium', style: GoogleFonts.cinzel(
                color: gold, fontSize: 11, letterSpacing: 1)),
            ]),
          )),
        ]),
      );
    }

    final nameCtrl = TextEditingController(
      text: unit.customName.isNotEmpty
        ? unit.customName : unit.unit.name);
    // Official units show their synchronized lore (read-only); user units show custom lore
    final loreCtrl = TextEditingController(
      text: isUserUnit ? (unit.lore ?? '') : (unit.unit.lore ?? ''));
    bool    removingBg         = false;
    bool    placeholderHovered = false;
    String  selColor           = unit.bgColor ?? '#1E1A15';
    String? bgError;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.dark,
      builder: (_) => StatefulBuilder(builder: (ctx, setSt) =>
        DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          builder: (_, scroll) => SingleChildScrollView(
            controller: scroll,
            padding: EdgeInsets.fromLTRB(16, 16, 16,
              MediaQuery.of(context).viewInsets.bottom + 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // drag handle
              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Text('Edit Unit', style: GoogleFonts.cinzel(color: gold, fontSize: 17)),
              const SizedBox(height: 16),
              if (isUserUnit)
                AetherraTextField(
                  controller: nameCtrl,
                  hintText: 'Display Name...',
                  style: GoogleFonts.cinzel(color: gold, fontSize: 13))
              else
                Text(nameCtrl.text,
                  style: GoogleFonts.cinzel(color: gold, fontSize: 15)),
              const SizedBox(height: 16),

              // photo
              premiumLock(Center(child: Container(
                width: 80, height: 140,
                foregroundDecoration: BoxDecoration(
                  border: Border.all(color: gold.withValues(alpha: 0.35))),
                child: Stack(children: [
                  Positioned.fill(child: (unit.photoBase64 ?? '').isNotEmpty
                    ? ColoredBox(
                        color: AppColors.parseHex(selColor),
                        child: CachedBase64Image(
                          base64: unit.photoBase64!, width: 80, height: 140))
                    : GestureDetector(
                        onTap: () async {
                          final b64 = await pickAndCropPhoto(context);
                          if (b64 != null && context.mounted) {
                            setSt(() { unit.photoBase64 = b64; placeholderHovered = false; });
                            _autoSave(army);
                            try {
                              final game = context.read<GameNotifier>();
                              game.state?.units
                                .where((gu) => gu.armyUnit.iid == unit.iid)
                                .forEach((gu) { gu.armyUnit.photoBase64 = b64; });
                              game.notifyListenersPublic();
                            } catch (_) {}
                          }
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onEnter: (_) => setSt(() => placeholderHovered = true),
                          onExit:  (_) => setSt(() => placeholderHovered = false),
                          child: Container(color: AppColors.dark,
                            child: Center(child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 80),
                              opacity: placeholderHovered ? 1.0 : 0.35,
                              child: const Icon(Icons.add_photo_alternate_outlined,
                                color: gold, size: 36,
                                shadows: [Shadow(color: Colors.black87, blurRadius: 8)]))))))),
                  if (removingBg)
                    Positioned.fill(child: Container(
                      color: AppColors.dark.withValues(alpha: 0.75),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(color: gold),
                          const SizedBox(height: 8),
                          Text('Removing...',
                            style: GoogleFonts.cinzel(color: gold, fontSize: 11)),
                        ]))),
                ])))),
              const SizedBox(height: 12),

              // icons + remove bg + color picker
              premiumLock(Row(children: [
                _UnitPhotoIcon(icon: Icons.add_photo_alternate_outlined,
                  onTap: () async {
                    final b64 = await pickAndCropPhoto(context);
                    if (b64 != null && context.mounted) {
                      setSt(() => unit.photoBase64 = b64);
                      _autoSave(army);
                      try {
                        final game = context.read<GameNotifier>();
                        game.state?.units
                          .where((gu) => gu.armyUnit.iid == unit.iid)
                          .forEach((gu) { gu.armyUnit.photoBase64 = b64; });
                        game.notifyListenersPublic();
                      } catch (_) {}
                    }
                  }),
                if ((unit.photoBase64 ?? '').isNotEmpty) ...[
                  const SizedBox(width: 4),
                  _UnitPhotoIcon(icon: Icons.crop,
                    onTap: () async {
                      final b64 = await editCropPhoto(ctx, unit.photoBase64!);
                      if (b64 != null) {
                        setSt(() => unit.photoBase64 = b64);
                        _autoSave(army);
                      }
                    }),
                  const SizedBox(width: 4),
                  _UnitPhotoIcon(icon: Icons.delete_outline,
                    color: Colors.red,
                    onTap: () {
                      setSt(() => unit.photoBase64 = null);
                      _autoSave(army);
                    }),
                ],
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(
                  onPressed: (removingBg || (unit.photoBase64 ?? '').isEmpty) ? null : () async {
                    setSt(() { removingBg = true; bgError = null; });
                    try {
                      final bytes  = decodePhotoBytes(unit.photoBase64!);
                      final result = await removeBg(bytes);
                      if (result != null) {
                        String newB64;
                        try {
                          final raw = base64Decode(unit.photoBase64!);
                          if (raw.isNotEmpty && raw[0] == 0x7B) {
                            final info = jsonDecode(utf8.decode(raw))
                              as Map<String, dynamic>;
                            newB64 = base64Encode(utf8.encode(jsonEncode(
                              {...info, 'src': base64Encode(result)})));
                          } else {
                            newB64 = base64Encode(result);
                          }
                        } catch (_) { newB64 = base64Encode(result); }
                        setSt(() { unit.photoBase64 = newB64; removingBg = false; });
                        _autoSave(army);
                      } else {
                        setSt(() => removingBg = false);
                      }
                    } catch (e) {
                      setSt(() { removingBg = false; bgError = e.toString(); });
                    }
                  },
                  icon: const Icon(Icons.auto_fix_high_outlined, color: gold, size: 15),
                  label: Text('Remove Background',
                    style: GoogleFonts.cinzel(fontSize: 13, letterSpacing: 1)),
                  style: OutlinedButton.styleFrom(foregroundColor: gold,
                    side: BorderSide(color: gold.withValues(alpha: 0.5)),
                    shape: const RoundedRectangleBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 10)))),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () async {
                    final picked = await showAetherraDialogRaw<String>(
                      ctx,
                      Builder(builder: (dCtx) => aetherraDialogContainer(
                        title: 'Background Color',
                        content: Wrap(
                          spacing: 8, runSpacing: 8,
                          children: _kArmyBgPresets.map((hex) {
                            final isSel = selColor.toLowerCase() == hex.toLowerCase();
                            return GestureDetector(
                              onTap: () => Navigator.pop(dCtx, hex),
                              child: Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: AppColors.parseHex(hex),
                                  border: Border.all(
                                    color: isSel ? gold : gold.withValues(alpha: 0.25),
                                    width: isSel ? 3.0 : 1.0)),
                                child: isSel
                                  ? const Center(child: Icon(Icons.check,
                                      color: Colors.white, size: 18,
                                      shadows: [Shadow(color: Colors.black87, blurRadius: 6)]))
                                  : null));
                          }).toList()))));
                    if (picked != null) setSt(() => selColor = picked);
                  },
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.parseHex(selColor),
                      border: Border.all(color: gold, width: 2)))),
              ])),
              const SizedBox(height: 6),
              if (bgError != null)
                Text(bgError!,
                  style: GoogleFonts.cinzel(color: Colors.redAccent, fontSize: 11))
              else
                Text('Tip: Upload a transparent PNG for better results.',
                  style: GoogleFonts.cinzel(color: grey.withValues(alpha: 0.85),
                    fontSize: 10, fontStyle: FontStyle.italic)),
              const SizedBox(height: 12),
              if (isUserUnit)
                premiumLock(AetherraTextField(
                  controller: loreCtrl,
                  hintText: 'Lore: origin, history, tactics...',
                  minLines: 3, maxLines: null,
                  style: GoogleFonts.cinzel(color: grey, fontSize: 12, height: 1.5)))
              else if (loreCtrl.text.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.gold.withValues(alpha: 0.2))),
                  child: Text(loreCtrl.text,
                    style: GoogleFonts.cinzel(color: grey, fontSize: 12, height: 1.5))),
              const SizedBox(height: 16),

              // save button
              SizedBox(width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      if (isUserUnit) unit.customName = nameCtrl.text.trim();
                      if (isPremium) {
                        unit.bgColor = selColor;
                        if (isUserUnit) {
                          final l = loreCtrl.text.trim();
                          unit.lore = l.isEmpty ? null : l;
                        }
                      }
                    });
                    _autoSave(army);
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: gold, foregroundColor: AppColors.dark,
                    shape: const RoundedRectangleBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text('Save', style: GoogleFonts.cinzel(
                    fontSize: 15, fontWeight: FontWeight.w600)))),
            ])))));
  }

  Widget _groupHeader(String name, ArmyState army, {bool isDragOver = false}) {
    final collapsed = _collapsedGroups.contains(name);
    bool hovered = false;
    return StatefulBuilder(builder: (ctx, setSt) =>
      MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setSt(() => hovered = true),
        onExit:  (_) => setSt(() => hovered = false),
        child: GestureDetector(
          onTap: () => setState(() {
            if (collapsed) { _collapsedGroups.remove(name); }
            else           { _collapsedGroups.add(name); }
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            margin: const EdgeInsets.only(bottom: 4, top: 4),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: gold.withValues(alpha: isDragOver || hovered ? 0.14 : 0.06),
              border: const Border(left: BorderSide(color: gold, width: 2))),
            child: Row(children: [
              Icon(collapsed ? Icons.chevron_right : Icons.expand_more,
                color: gold, size: 16),
              const SizedBox(width: 6),
              Expanded(child: Text(name.toUpperCase(),
                style: GoogleFonts.cinzel(
                  color: gold, fontSize: 13, letterSpacing: 2))),
              Text('· ${army.units.where((u) => u.groupName == name).length} u',
                style: GoogleFonts.cinzel(color: grey, fontSize: 12),
                overflow: TextOverflow.ellipsis),
              const SizedBox(width: 6),
              Text(
                '${army.units.where((u) => u.groupName == name).fold(0, (s, u) => s + u.unit.cost)} pts',
                style: GoogleFonts.cinzel(color: grey, fontSize: 12),
                overflow: TextOverflow.ellipsis),
              const SizedBox(width: 8),
              GroupTrashBtn(
                groupName: name,
                onDelete: () { army.removeGroup(name); _autoSave(army); }),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _lbl(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(t, style: GoogleFonts.cinzel(
      color: grey, fontSize: 13, letterSpacing: 1.5)));
}

// â"€â"€ Overlay button for image actions â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€â"€
class _UnitPhotoIcon extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  const _UnitPhotoIcon({required this.icon, required this.onTap, this.color = AppColors.gold});
  @override State<_UnitPhotoIcon> createState() => _UnitPhotoIconState();
}
class _UnitPhotoIconState extends State<_UnitPhotoIcon> {
  bool _hovered = false;
  @override Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit:  (_) => setState(() => _hovered = false),
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 80),
        opacity: _hovered ? 1.0 : 0.45,
        child: Icon(widget.icon, color: widget.color, size: 20))));
}

class _EditOverlay extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _EditOverlay({required this.icon, required this.onTap});
  @override State<_EditOverlay> createState() => _EditOverlayState();
}
class _EditOverlayState extends State<_EditOverlay> {
  bool _hovered = false;
  @override Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit:  (_) => setState(() => _hovered = false),
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: AppColors.dark.withValues(alpha: _hovered ? 0.92 : 0.70),
          border: Border.all(
            color: AppColors.gold.withValues(alpha: _hovered ? 0.9 : 0.4))),
        child: Icon(widget.icon,
          color: AppColors.gold.withValues(
            alpha: _hovered ? 1.0 : 0.65),
          size: 14))));
}

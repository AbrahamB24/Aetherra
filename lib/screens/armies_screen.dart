import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_theme.dart';
import '../models/army_state.dart';
import '../services/game_data_service.dart';
import '../services/army_service.dart';
import '../widgets/aetherra_dialog.dart';
import '../widgets/hover_icon_btn.dart';
import '../widgets/nav_btn.dart';
import '../widgets/photo_crop_dialog.dart';
import '../widgets/unit_card.dart' show PressBtn, BannerUnitsPanel, BannerStat;
import 'army_view_screen.dart';
import 'new_army_screen.dart';

class ArmiesScreen extends StatefulWidget {
  const ArmiesScreen({super.key});
  @override
  State<ArmiesScreen> createState() => _ArmiesScreenState();
}

class _ArmiesScreenState extends State<ArmiesScreen> {
  static const gold = AppColors.gold;

  List<Map<String, dynamic>> _armies = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await ArmyService.loadAll();
    setState(() {
      _armies = data;
      _loading = false;
    });
  }


  Future<void> _importArmy(BuildContext context) async {
    final codeCtrl = TextEditingController();
    String? errorMsg;
    bool loading = false;

    await showAetherraDialogRaw<void>(context, StatefulBuilder(builder: (ctx, setS) =>
      aetherraDialogContainer(
        title: 'Import Army',
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Enter the 6-character share code:',
            style: GoogleFonts.cinzel(color: AppColors.grey, fontSize: 13)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(
              controller: codeCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              style: GoogleFonts.cinzel(
                color: AppColors.gold, fontSize: 22, letterSpacing: 4),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                counterText: '',
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: AppColors.gold.withValues(alpha: 0.4))),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.gold)),
                filled: true,
                fillColor: AppColors.dark),
              onChanged: (_) { if (errorMsg != null) setS(() => errorMsg = null); })),
            HoverIconBtn(
              icon: Icons.content_paste_outlined,
              onTap: () async {
                final data = await Clipboard.getData('text/plain');
                final text = (data?.text ?? '').trim().toUpperCase()
                    .replaceAll(RegExp(r'[^A-Z0-9]'), '');
                if (text.isNotEmpty) {
                  codeCtrl.text = text.substring(0, text.length.clamp(0, 6));
                  setS(() => errorMsg = null);
                }
              }),
          ]),
          if (errorMsg != null) ...[
            const SizedBox(height: 8),
            Text(errorMsg!, style: GoogleFonts.cinzel(color: Colors.redAccent, fontSize: 12)),
          ],
        ]),
        actions: [
          aDialogBtn('Cancel', AppColors.grey, loading ? null : () => Navigator.of(ctx).pop()),
          loading
            ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.gold))
            : aDialogBtn('Import', AppColors.gold, () async {
                final code = codeCtrl.text.trim().toUpperCase();
                if (code.length != 6) {
                  setS(() => errorMsg = 'Code must be 6 characters.');
                  return;
                }
                setS(() { loading = true; errorMsg = null; });
                final row = await ArmyService.fetchShared(code);
                if (row == null) {
                  setS(() { loading = false; errorMsg = 'Code not found. Check and try again.'; });
                  return;
                }
                await ArmyService.importArmy(row);
                if (ctx.mounted) Navigator.of(ctx).pop();
                await _load();
              }),
        ],
      )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        leading: NavBtn(
          icon: Icons.home_outlined,
          onPressed: () =>
              Navigator.of(context).popUntil((r) => r.isFirst)),
        title: Text('My Armies',
          style: GoogleFonts.cinzel(
            color: gold, fontSize: 17, letterSpacing: 2)),
        actions: [
          NavBtn(
            icon: Icons.file_download_outlined,
            onPressed: () => _importArmy(context)),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: gold))
        : Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
              child: Center(child: FractionallySizedBox(
                widthFactor: 0.38,
                child: SizedBox(
                  height: 58,
                  child: PressBtn(
                    label: 'New Army',
                    centered: true,
                    fontSize: 18,
                    padding: const EdgeInsets.symmetric(vertical: 0),
                    onTap: () async {
                      await Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const NewArmyScreen()));
                      _load();
                    }))))),
            Expanded(child: _armies.isEmpty
              ? Center(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shield_outlined, color: gold, size: 44),
                    const SizedBox(height: 12),
                    Text('No saved armies yet.',
                      style: GoogleFonts.cinzel(color: gold, fontSize: 17)),
                  ],
                ))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _armies.length,
                  itemBuilder: (_, i) => _ArmyRowCard(
                    l: _armies[i],
                    onLoad: () => _loadArmyAndNavigate(_armies[i]),
                  ),
                )),
          ]),
    );
  }

  Future<void> _loadArmyAndNavigate(Map<String, dynamic> l) async {
    final army     = context.read<ArmyState>();
    final ad       = l['army_data'] as Map<String, dynamic>? ?? {};
    final unitList = (ad['units'] as List?) ?? [];
    final limit    = (ad['limit'] as int?) ?? 2500;

    army.clear();
    army.setLimit(limit);
    army.setName(l['name'] as String? ?? '');
    army.listId = l['id'] as String?;
    final fids = ad['factionIds'];
    army.setFactions(fids is List ? List<String>.from(fids) : []);
    final grps = ad['groups'];
    army.groups = grps is List ? List<String>.from(grps) : [];

    final restored = <ArmyUnit>[];
    for (final u in unitList) {
      final unitId = u['unitId'] as String?;
      if (unitId == null) continue;

      var unit = GameDataService.toGameUnit(unitId);
      bool isEmbedded = false;
      Map<String, dynamic>? embeddedDef;

      if (unit == null) {
        final def = u['embedded_def'];
        if (def is Map<String, dynamic>) {
          unit = GameDataService.gameUnitFromMap(def);
          if (unit != null) { isEmbedded = true; embeddedDef = def; }
        }
      }
      if (unit == null) continue;

      final inst = ArmyUnit(
        iid:  u['iid'] as String? ??
              'u${DateTime.now().millisecondsSinceEpoch}${restored.length}',
        unit: unit,
        isEmbedded:  isEmbedded,
        embeddedDef: embeddedDef,
      );
      final customName = u['name'] as String? ?? '';
      if (customName.isNotEmpty) inst.customName = customName;
      final groupName = u['group'] as String? ?? '';
      if (groupName.isNotEmpty) inst.groupName = groupName;
      inst.photoBase64 = u['photo']   as String?;
      inst.bgColor     = u['bgColor'] as String?;
      inst.lore        = u['lore']   as String?;
      restored.add(inst);
    }
    army.units = restored;
    army.refresh();

    _migratePhotos(army, l['id'] as String?, l['name'] as String? ?? '');

    final meta = Supabase.instance.client.auth.currentUser?.userMetadata ?? {};
    final fallbackName = meta['display_name'] as String?
        ?? meta['full_name'] as String?
        ?? meta['name'] as String?;
    final creatorName = ad['creator_name'] as String? ?? fallbackName;

    await Navigator.push(context,
      MaterialPageRoute(builder: (_) => ArmyViewScreen(
        imageB64:    ad['image_b64'] as String?,
        bgColor:     ad['bg_color']  as String?,
        creatorName: creatorName,
        lore:        ad['lore'] as String?,
      )));
    _load();
  }

  Future<void> _migratePhotos(
      ArmyState army, String? listId, String name) async {
    bool changed = false;
    for (final u in army.units) {
      if (u.photoBase64 == null || u.photoBase64!.isEmpty) continue;
      final migrated = await migratePhotoIfNeeded(u.photoBase64!);
      if (!identical(migrated, u.photoBase64)) {
        u.photoBase64 = migrated;
        changed = true;
      }
    }
    if (changed && listId != null) {
      army.refresh();
      await ArmyService.save(army, name, listId);
    }
  }
}

// ── Army tile ────────────────────────────────────────────────────────────────
class _ArmyRowCard extends StatefulWidget {
  final Map<String, dynamic> l;
  final VoidCallback onLoad;
  const _ArmyRowCard({required this.l, required this.onLoad});
  @override State<_ArmyRowCard> createState() => _ArmyRowCardState();
}

class _ArmyRowCardState extends State<_ArmyRowCard> {
  bool _loreExpanded  = false;
  bool _loreHovered   = false;
  bool _unitsExpanded = false;
  bool _unitsHovered  = false;
  bool _hovered = false;
  bool _pressed = false;
  Widget? _cachedImg;
  int _atk = 0, _def = 0, _rng = 0, _mob = 0, _con = 0, _cp = 0;
  final List<Map<String, String>> _unitEntries = [];
  List<String> _groupOrder = [];

  static final _kIdentity = Matrix4.identity();

  @override
  void initState() {
    super.initState();
    final ad       = widget.l['army_data'] as Map<String, dynamic>? ?? {};
    final imageB64 = ad['image_b64'] as String?;
    if (imageB64 != null && imageB64.isNotEmpty) {
      _cachedImg = buildCroppedPhotoDisplay(imageB64, AppColors.bannerW, AppColors.bannerH);
    }
    for (final u in (ad['units'] as List?) ?? []) {
      final unit = GameDataService.toGameUnit(u['unitId'] as String? ?? '');
      if (unit == null) continue;
      _atk += unit.atk; _def += unit.def; _rng += unit.rng;
      _mob += unit.mob; _con += unit.con; _cp  += unit.cp;
      final customName = u['name'] as String? ?? '';
      _unitEntries.add({
        'name':  customName.isNotEmpty ? customName : unit.name,
        'group': u['group'] as String? ?? '',
      });
    }
    _groupOrder = ((ad['groups'] as List?) ?? []).cast<String>();
  }



  @override
  Widget build(BuildContext context) {
    final l           = widget.l;
    final name        = l['name'] as String? ?? 'Untitled';
    final pts         = l['total_points'] as int? ?? 0;
    final ad          = l['army_data'] as Map<String, dynamic>? ?? {};
    final units       = (ad['units'] as List?)?.length ?? 0;
    final limit       = ad['limit'] as int? ?? 2500;
    final over        = pts > limit;
    final creatorName = ad['creator_name'] as String?;
    final lore        = ad['lore']   as String?;
    final hasLore     = lore != null && lore.isNotEmpty;
    final bgColor     = AppColors.parseHex(ad['bg_color'] as String? ?? '#1E1A15');
    final hasImg      = _cachedImg != null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onLoad,
        onTapDown:   (_) => setState(() => _pressed = true),
        onTapUp:     (_) => setState(() => _pressed = false),
        onTapCancel: ()  => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          transform: _pressed
            ? (Matrix4.identity()..scaleByDouble(0.98, 0.98, 1, 1))
            : _kIdentity,
          transformAlignment: Alignment.center,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: bgColor,
              border: Border.all(
                color: _hovered
                  ? AppColors.gold
                  : AppColors.gold.withValues(alpha: 0.2),
                width: 1.5)),
            child: Stack(clipBehavior: Clip.hardEdge, children: [

              if (hasImg) Positioned(
                top: 0, left: 0, right: 0, height: 115,
                child: ClipRect(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: (_loreExpanded || _unitsExpanded) ? -40.0 : 0.0),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    builder: (_, dy, child) =>
                      Transform.translate(offset: Offset(0, dy), child: child),
                    child: Center(child: _cachedImg!)))),

              if (!hasImg) Positioned.fill(
                child: Center(child: Icon(Icons.shield_outlined,
                  color: AppColors.gold.withValues(alpha: 0.15), size: 36))),

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
                              Text(name,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.cinzel(
                                  color: AppColors.gold, fontSize: 17,
                                  letterSpacing: 2,
                                  shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])),
                              if (creatorName != null && creatorName.isNotEmpty)
                                Text('by $creatorName',
                                  style: GoogleFonts.cinzel(
                                    color: Colors.white54, fontSize: 12,
                                    shadows: const [Shadow(color: Colors.black87, blurRadius: 4)])),
                            ])),
                          Text('$pts / $limit pts',
                            style: GoogleFonts.cinzel(
                              color: over ? Colors.red : AppColors.gold,
                              fontSize: 17,
                              shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])),
                        ]),
                        // Bottom: lore + units icons left | stats right
                        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                          GestureDetector(
                            onTap: hasLore ? () => setState(() => _loreExpanded = !_loreExpanded) : null,
                            child: MouseRegion(
                              cursor: hasLore ? SystemMouseCursors.click : MouseCursor.defer,
                              onEnter: hasLore ? (_) => setState(() => _loreHovered = true)  : null,
                              onExit:  hasLore ? (_) => setState(() => _loreHovered = false) : null,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 80),
                                opacity: hasLore ? (_loreExpanded || _loreHovered ? 1.0 : 0.55) : 0.2,
                                child: Icon(
                                  _loreExpanded ? Icons.menu_book : Icons.menu_book_outlined,
                                  color: AppColors.gold, size: 18,
                                  shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])))),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () => setState(() => _unitsExpanded = !_unitsExpanded),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              onEnter: (_) => setState(() => _unitsHovered = true),
                              onExit:  (_) => setState(() => _unitsHovered = false),
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 80),
                                opacity: _unitsExpanded || _unitsHovered ? 1.0 : 0.55,
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Text('$units',
                                    style: GoogleFonts.cinzel(
                                      color: AppColors.gold, fontSize: 13,
                                      shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])),
                                  const SizedBox(width: 3),
                                  Icon(_unitsExpanded ? Icons.group : Icons.group_outlined,
                                    color: AppColors.gold, size: 18,
                                    shadows: const [Shadow(color: Colors.black87, blurRadius: 6)]),
                                ])))),
                          const Spacer(),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            BannerStat('$_cp',   'AP'),
                            BannerStat('$_atk',  'ATK'),
                            BannerStat('$_def',  'DEF'),
                            BannerStat('$_rng',  'SHO'),
                            BannerStat('$_mob',  'MOB'),
                            BannerStat('$_con',  'STR'),
                          ]),
                        ]),
                      ]))),

                // Lore panel
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  child: hasLore && _loreExpanded
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                        child: Text(lore,
                          style: GoogleFonts.cinzel(
                            color: Colors.white70, fontSize: 13, height: 1.6,
                            fontStyle: FontStyle.italic,
                            shadows: const [Shadow(color: Colors.black87, blurRadius: 8)])))
                    : const SizedBox.shrink()),

                // Units panel
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  child: _unitsExpanded && _unitEntries.isNotEmpty
                    ? BannerUnitsPanel(entries: _unitEntries, groupOrder: _groupOrder)
                    : const SizedBox.shrink()),
              ]),
            ])))));
  }
}

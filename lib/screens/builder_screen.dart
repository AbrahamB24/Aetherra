import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/army_state.dart';
import '../widgets/photo_crop_dialog.dart';
import '../widgets/unit_card.dart';
import '../widgets/nav_btn.dart';
import '../widgets/dnd_unit_grid.dart';
import '../services/army_service.dart';
import '../services/bg_remover.dart';
import '../services/subscription_service.dart';
import '../game/notifiers/game_notifier.dart';
import '../services/game_data_service.dart';
import '../app_theme.dart';
import '../widgets/aetherra_dialog.dart';
import '../widgets/aetherra_text_field.dart';
import '../widgets/group_trash_btn.dart';

const _kBuilderBgPresets = [
  '#0D0B09', '#08111E', '#0A1A08', '#1A0808',
  '#120820', '#14061A', '#1A1004', '#1A0C0C',
  '#2D1B0E', '#0C2244', '#112C11', '#3C1111',
  '#1D1142', '#113D3D', '#3D2008', '#2C1024',
  '#5C3C1E', '#1E4E82', '#1E5E1E', '#6E1E1E',
  '#3C1C6E', '#1E5E5E', '#6E3E0E', '#4E1C40',
  '#8C6040', '#3A74AA', '#3A7440', '#A43C3C',
  '#5C3CAA', '#3A9292', '#AA6C20', '#7C3468',
  '#C8A870', '#70AACC', '#70BC70', '#D48888',
  '#9870CC', '#70C0C0', '#CCAA38', '#C07898',
];

// Helper class for army panel list items
class _ArmyItem {
  final bool isHeader;
  final String? groupName;
  final ArmyUnit? unit;
  const _ArmyItem({required this.isHeader, this.groupName, this.unit});
}

class BuilderScreen extends StatefulWidget {
  final List<String> initialFactions;
  final bool editMode;
  final bool showBack;
  const BuilderScreen({super.key,
    this.initialFactions = const [], this.editMode = false, this.showBack = false});
  @override
  State<BuilderScreen> createState() => _BuilderScreenState();
}

class _BuilderScreenState extends State<BuilderScreen> {
  static const gold  = AppColors.gold;
      static const grey  = AppColors.grey;

  List<String> _fFacs = []; // empty = all factions
  Set<String> _fTypes = {};
  String _sortBy      = 'name';
  bool   _sortAsc     = true;
  bool   _sortHovered = false;
  int    _tabIdx   = 0;
  double _armyWidth = 320.0;
  final Set<String> _collapsedGroups = {};

  ArmyState? _listenedArmy;
  Timer?     _autoSaveTimer;
  bool _saving = false;
  bool _saved  = false;

  @override
  void initState() {
    super.initState();
    _fFacs = List.from(widget.initialFactions);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final army = context.read<ArmyState>();
    if (!identical(_listenedArmy, army)) {
      _listenedArmy?.removeListener(_scheduleAutoSave);
      _listenedArmy = army;
      army.addListener(_scheduleAutoSave);
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _listenedArmy?.removeListener(_scheduleAutoSave);
    super.dispose();
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 800), () async {
      if (!mounted) return;
      final army = context.read<ArmyState>();
      final name = army.name.trim();
      if (name.isEmpty) return;
      try {
        final id = await ArmyService.save(army, name, army.listId);
        if (id != null && mounted) army.listId = id;
      } catch (_) {}
    });
  }

  List<Map<String, dynamic>> get _filtered {
    final list = GameDataService.units.where((u) {
      if (_fFacs.isNotEmpty && !_fFacs.contains(u['faction_id'])) return false;
      if (_fTypes.isNotEmpty && !_fTypes.contains(u['type'])) return false;
      return true;
    }).toList();
    list.sort((a, b) {
      int cmp;
      switch (_sortBy) {
        case 'cost': cmp = (b['cost']    as int).compareTo(a['cost']    as int); break;
        case 'atk':  cmp = (b['atk']     as int).compareTo(a['atk']     as int); break;
        case 'def':  cmp = (b['def_val'] as int).compareTo(a['def_val'] as int); break;
        case 'rng':  cmp = (b['rng']     as int).compareTo(a['rng']     as int); break;
        case 'mob':  cmp = (b['mob']     as int).compareTo(a['mob']     as int); break;
        case 'con':  cmp = (b['con_val'] as int).compareTo(a['con_val'] as int); break;
        case 'cp':   cmp = (b['cp']      as int).compareTo(a['cp']      as int); break;
        default:     cmp = (a['name'] as String).compareTo(b['name'] as String);
      }
      return _sortAsc ? cmp : -cmp;
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        leading: widget.showBack
          ? NavBtn(icon: Icons.arrow_back_ios_new,
              onPressed: () => Navigator.pop(context))
          : NavBtn(icon: Icons.home_outlined,
              onPressed: () async {
                await showAetherraDialog(context,
                  title: 'Army Saved',
                  content: Text(
                    'Your army has been saved automatically. You can continue editing it anytime.',
                    style: GoogleFonts.cinzel(color: grey, fontSize: 13, height: 1.5)),
                  actions: [
                    aDialogBtn('Stay', grey, () => Navigator.pop(context)),
                    aDialogBtn('Go Home', gold, () {
                      Navigator.pop(context);
                      Navigator.of(context).popUntil((r) => r.isFirst);
                    }),
                  ]);
              }),
        title: Text('Army Builder', style: GoogleFonts.cinzel(
          color: gold, fontSize: 17, letterSpacing: 2)),
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 661;
        if (isWide) {
          final totalW   = constraints.maxWidth;
          final armyW    = _armyWidth.clamp(375.0, totalW - 286.0);
          final rosterW  = (totalW - armyW - 6).clamp(280.0, totalW - 381.0);
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: SizedBox(
              width: rosterW + 6 + armyW,
              height: double.infinity,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: rosterW, child: _rosterPanel()),
                // Draggable divider
                GestureDetector(
                  onHorizontalDragUpdate: (d) => setState(() {
                    _armyWidth = (_armyWidth - d.delta.dx)
                      .clamp(375.0, totalW - 286.0);
                  }),
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: Container(
                  width: 6,
                  color: AppColors.dark,
                  child: Center(child: Container(
                    width: 2, height: 40,
                    decoration: BoxDecoration(
                      color: gold.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2))))))),
                SizedBox(width: armyW.clamp(375.0, totalW - 286.0),
                  child: _armyPanel()),
              ])));
        } else {
          return Column(children: [
            Expanded(child: _tabIdx == 0 ? _rosterPanel() : _armyPanel()),
            Container(
              color: AppColors.dark,
              child: Row(children: [
                Expanded(child: _BuilderTab(
                  icon: Icons.shield_outlined,
                  label: 'Roster',
                  selected: _tabIdx == 0,
                  onTap: () => setState(() => _tabIdx = 0))),
                Expanded(child: Consumer<ArmyState>(builder: (_, army, __) =>
                  _BuilderTab(
                    icon: Icons.format_list_bulleted,
                    label: 'Army (${army.units.length})',
                    selected: _tabIdx == 1,
                    onTap: () => setState(() => _tabIdx = 1)))),
              ]),
            ),
          ]);
        }
      }),
    );
  }

  // ── ROSTER ─────────────────────────────────────────────
  Widget _rosterPanel() {
    final army = context.watch<ArmyState>();
    return Stack(children: [
    Column(children: [
      // Roster header: Filter | Sort — fixed height 44px
      SizedBox(height: 44,
        child: Container(color: AppColors.dark,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _FilterDropdown(
                selected: _fTypes,
                onChanged: (s) => setState(() => _fTypes = s)),
              const Spacer(),
              MouseRegion(
                onEnter: (_) => setState(() => _sortHovered = true),
                onExit:  (_) => setState(() => _sortHovered = false),
                cursor: SystemMouseCursors.click,
                child: Theme(
                  data: Theme.of(context).copyWith(
                    splashFactory:   NoSplash.splashFactory,
                    highlightColor: Colors.transparent,
                    splashColor:    Colors.transparent,
                    hoverColor:     Colors.transparent),
                  child: PopupMenuButton<String>(
                    color: AppColors.dark,
                    enableFeedback: false,
                    tooltip: '',
                    iconSize: 0,
                    padding: EdgeInsets.zero,
                    position: PopupMenuPosition.under,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _sortHovered
                          ? gold.withValues(alpha: 0.12) : Colors.transparent,
                        border: Border.all(
                          color: _sortHovered ? gold : gold.withValues(alpha: 0.4))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.sort, color: gold, size: 16),
                        const SizedBox(width: 4),
                        Text('Sort', style: GoogleFonts.cinzel(color: gold, fontSize: 13)),
                      ])),
                    onSelected: (v) => setState(() {
                      if (v == _sortBy) { _sortAsc = !_sortAsc; }
                      else { _sortBy = v; _sortAsc = true; }
                    }),
                    itemBuilder: (_) => [
                      for (final s in [
                        ['name','Name A→Z'], ['cost','Points ↓'],
                        ['atk','ATK ↓'], ['def','DEF ↓'],
                        ['rng','SHO ↓'], ['mob','MOB ↓'],
                        ['con','STR ↓'], ['cp','CP ↓'],
                      ])
                        PopupMenuItem(value: s[0],
                          padding: EdgeInsets.zero,
                          child: _SortItem(
                            label: s[1],
                            active: _sortBy == s[0],
                            ascending: _sortBy == s[0] && _sortAsc)),
                    ]))),  // PopupMenuButton + Theme
            ]))),       // Row + Container + SizedBox

      Expanded(
        child: _filtered.isEmpty
          ? Center(child: Text('No units match.',
              style: GoogleFonts.cinzel(color: grey)))
          : LayoutBuilder(builder: (ctx, constraints) {
              final avail = constraints.maxWidth - 26;
              final cols  = avail < 600 ? 1 : avail < 950 ? 2 : avail < 1300 ? 3 : avail < 1650 ? 4 : 5;
              final rawCardW = (avail - (cols - 1) * 8) / cols;
              final cardW = rawCardW.floorToDouble();
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: (_filtered.length / cols).ceil(),
                itemBuilder: (_, row) {
                  final start = row * cols;
                  final end   = (start + cols).clamp(0, _filtered.length);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int i = start; i < end; i++) ...[
                          if (i > start) const SizedBox(width: 8),
                          SizedBox(width: cardW,
                            child: _unitCardCompact(_filtered[i], army)),
                        ],
                      ]));
                });
            }),
      ),
    ]),
    ]);
  }

  // ── COMPACT CARD VIEW ─────────────────────────────────
  Widget _unitCardCompact(Map<String, dynamic> u, ArmyState army) {
    final uid        = u['id'] as String;
    final cnt        = army.units.where((x) => x.unit.id == uid).length;
    final isUniq     = u['unique_unit'] as bool;
    final isDisabled = isUniq && cnt >= 1;
    return RosterCard(
      unitData: u,
      isDisabled: isDisabled,
      onAdd: () {
        final gu = GameDataService.toGameUnit(uid);
        if (gu == null) return;
        army.addUnit(gu);
      });
  }

    // ── ARMY PANEL ─────────────────────────────────────────
  Widget _armyPanel() {
    return Consumer<ArmyState>(builder: (_, army, __) {
      // Build flat list: [group_header, unit, unit, group_header, unit, ...]
      // ungrouped units first (group=''), then per group
      final allGroups = ['', ...army.groups];
      final items = <_ArmyItem>[];
      for (final g in allGroups) {
        final gUnits = army.units
          .where((u) => u.groupName == g).toList();
        if (gUnits.isEmpty && g.isEmpty) continue;
        if (g.isNotEmpty) {
          items.add(_ArmyItem(isHeader: true, groupName: g));
        }
        // Only add units if group not collapsed
        if (!_collapsedGroups.contains(g)) {
          for (final u in gUnits) {
            items.add(_ArmyItem(isHeader: false, unit: u));
          }
        }
      }

      return Stack(children: [
      Container(
        decoration: BoxDecoration(color: AppColors.dark,
          border: Border(left: BorderSide(color: gold.withValues(alpha: 0.2)))),
        child: Column(children: [
          // Army name + pts
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
            child: Row(children: [
              if (army.name.isNotEmpty)
                Expanded(child: Text(army.name,
                  style: GoogleFonts.cinzel(
                    color: gold, fontSize: 16, letterSpacing: 1),
                  maxLines: 1, overflow: TextOverflow.ellipsis))
              else
                const Spacer(),
              Text('${army.totalPoints} / ${army.limit} pts',
                style: GoogleFonts.cinzel(
                  color: army.isOverLimit ? Colors.red : gold,
                  fontSize: 15)),
            ])),
          LinearProgressIndicator(
            value: (army.totalPoints / army.limit).clamp(0.0, 1.0),
            backgroundColor: AppColors.dark,
            valueColor: AlwaysStoppedAnimation(
              army.isOverLimit ? Colors.red : gold),
            minHeight: 3),

          Container(color: AppColors.dark, padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(height: 44,
                child: ClipRect(child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    _mStat('${army.units.length}', 'Units'),
                    _mStat('${army.units.fold(0, (s, u) => s + u.unit.con)}', 'STR'),
                    _mStat('${army.units.fold(0, (s, u) => s + u.unit.atk)}', 'ATK'),
                    _mStat('${army.units.fold(0, (s, u) => s + u.unit.def)}', 'DEF'),
                    _mStat('${army.units.fold(0, (s, u) => s + u.unit.rng)}', 'SHO'),
                    _mStat('${army.units.fold(0, (s, u) => s + u.unit.mob)}', 'MOB'),
                    _mStat('${army.totalCP}', 'AP'),
                    if (army.isOverLimit) ...[
                      const SizedBox(width: 8),
                      Text('OVER', style: GoogleFonts.cinzel(color: Colors.red, fontSize: 13)),
                    ],
                  ])))),
              Row(mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _loadStyleBtn('New Group', () => _addGroupDialog(army)),
                  const SizedBox(width: 6),
                  PressBtn(
                    label: _saving ? 'Saving…' : _saved ? 'Saved' : 'Save',
                    onTap: _save),
                ]),
            ])),
          Divider(height: 1, color: gold.withValues(alpha: 0.15)),
          Expanded(
            child: army.units.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shield_outlined,
                      color: gold.withValues(alpha: 0.2), size: 32),
                    const SizedBox(height: 8),
                    Text('No units yet.',
                      style: GoogleFonts.cinzel(color: grey, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text('Add from the roster',
                      style: TextStyle(color: grey.withValues(alpha: 0.6), fontSize: 15)),
                  ]))
              : LayoutBuilder(builder: (ctx, constraints) {
                  final w2 = constraints.maxWidth - 20;
                  final cols = (w2 / (260 + 8)).floor().clamp(1, 4);
                  final rawW = (w2 - (cols - 1) * 8) / cols;
                  final cardW2 = rawW.clamp(260.0, 500.0);
                  return DndUnitGrid(
                    units:    army.units,
                    groups:   army.groups,
                    cardW:    cardW2,
                    cols:     cols,
                    onReorder: () => army.refresh(),
                    groupHeader: (grp, isDragOver) => _groupHeader(grp, army, isDragOver: isDragOver),
                    onEdit: (unit) => _editUnit(context, unit, army),
                    collapsedGroups: _collapsedGroups,
                    trailingBuilder: (unit) => _XButton(
                      onTap: () => army.removeUnit(unit.iid)));
                })),
        ])),
      ]);
    });
  }


  Future<void> _editUnit(BuildContext context, ArmyUnit unit, ArmyState army) async {
    final isPremium = SubscriptionService.isPremium;

    void showPremiumMsg() {
      showAetherraDialog(context,
        title: 'Premium Required',
        content: Text(
          'Photo, Lore and Background Color are only available with a Premium subscription.',
          style: GoogleFonts.cinzel(color: grey, fontSize: 13, height: 1.5)),
        actions: [aDialogBtn('OK', gold, () => Navigator.of(context).pop())]);
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
      text: unit.customName.isNotEmpty ? unit.customName : unit.unit.name);
    final loreCtrl = TextEditingController(text: unit.lore ?? '');
    bool removingBg = false;
    bool placeholderHovered = false;
    String selColor = unit.bgColor ?? '#1E1A15';
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

              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Text('Edit Unit', style: GoogleFonts.cinzel(color: gold, fontSize: 17)),
              const SizedBox(height: 16),
              AetherraTextField(
                controller: nameCtrl,
                hintText: 'Display Name...',
                style: GoogleFonts.cinzel(color: gold, fontSize: 13)),
              const SizedBox(height: 16),

              premiumLock(Center(child: Container(
                width: 80, height: 140,
                foregroundDecoration: BoxDecoration(
                  border: Border.all(color: gold.withValues(alpha: 0.35))),
                child: Stack(children: [
                  Positioned.fill(child: (unit.photoBase64 ?? '').isNotEmpty
                    ? ColoredBox(
                        color: AppColors.parseHex(selColor),
                        child: CachedBase64Image(base64: unit.photoBase64!, width: 80, height: 140))
                    : GestureDetector(
                        onTap: () async {
                          GameNotifier? game;
                          try { game = context.read<GameNotifier>(); } catch (_) {}
                          final b64 = await _pickPhoto();
                          if (b64 != null) {
                            setSt(() { unit.photoBase64 = b64; placeholderHovered = false; });
                            setState(() {});
                            army.refresh();
                            try {
                              game?.state?.units
                                .where((gu) => gu.armyUnit.iid == unit.iid)
                                .forEach((gu) { gu.armyUnit.photoBase64 = b64; });
                              game?.notifyListenersPublic();
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

              premiumLock(Row(children: [
                _BuilderPhotoIcon(icon: Icons.add_photo_alternate_outlined,
                  onTap: () async {
                    GameNotifier? game;
                    try { game = context.read<GameNotifier>(); } catch (_) {}
                    final b64 = await _pickPhoto();
                    if (b64 != null) {
                      setSt(() => unit.photoBase64 = b64);
                      setState(() {});
                      army.refresh();
                      try {
                        game?.state?.units
                          .where((gu) => gu.armyUnit.iid == unit.iid)
                          .forEach((gu) { gu.armyUnit.photoBase64 = b64; });
                        game?.notifyListenersPublic();
                      } catch (_) {}
                    }
                  }),
                if ((unit.photoBase64 ?? '').isNotEmpty) ...[
                  const SizedBox(width: 4),
                  _BuilderPhotoIcon(icon: Icons.crop,
                    onTap: () async {
                      final b64 = await editCropPhoto(ctx, unit.photoBase64!);
                      if (b64 != null) {
                        setSt(() => unit.photoBase64 = b64);
                        setState(() {});
                        army.refresh();
                      }
                    }),
                  const SizedBox(width: 4),
                  _BuilderPhotoIcon(icon: Icons.delete_outline,
                    color: Colors.red,
                    onTap: () {
                      setSt(() => unit.photoBase64 = null);
                      setState(() {});
                      army.refresh();
                    }),
                ],
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(
              onPressed: (removingBg || (unit.photoBase64 ?? '').isEmpty) ? null : () async {
                setSt(() => removingBg = true);
                try {
                  final bytes  = decodePhotoBytes(unit.photoBase64!);
                  final result = await removeBg(bytes);
                  if (result != null) {
                    String newB64;
                    try {
                      final raw = base64Decode(unit.photoBase64!);
                      if (raw.isNotEmpty && raw[0] == 0x7B) {
                        final info = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
                        newB64 = base64Encode(utf8.encode(
                          jsonEncode({...info, 'src': base64Encode(result)})));
                      } else {
                        newB64 = base64Encode(result);
                      }
                    } catch (_) { newB64 = base64Encode(result); }
                    setSt(() { unit.photoBase64 = newB64; removingBg = false; });
                    setState(() {});
                    army.refresh();
                  } else {
                    setSt(() => removingBg = false);
                  }
                } catch (_) {
                  setSt(() => removingBg = false);
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
                      children: _kBuilderBgPresets.map((hex) {
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
              Text('Tip: Upload a transparent PNG for better results.',
                style: GoogleFonts.cinzel(color: grey.withValues(alpha: 0.85),
                  fontSize: 10, fontStyle: FontStyle.italic)),
              const SizedBox(height: 12),
              premiumLock(AetherraTextField(
                controller: loreCtrl,
                hintText: 'Lore: origin, history, tactics...',
                maxLines: 4,
                style: GoogleFonts.cinzel(color: grey, fontSize: 12, height: 1.5))),
              const SizedBox(height: 16),

              SizedBox(width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      unit.customName = nameCtrl.text.trim();
                      if (isPremium) {
                        unit.bgColor = selColor;
                        final l = loreCtrl.text.trim();
                        unit.lore = l.isEmpty ? null : l;
                      }
                    });
                    army.refresh();
                    _scheduleAutoSave();
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

  Future<String?> _pickPhoto() => pickAndCropPhoto(context);

  Widget _loadStyleBtn(String label, VoidCallback onTap) =>
    PressBtn(label: label, onTap: onTap, outlined: true);

  // Group header widget
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
            if (collapsed) {
              _collapsedGroups.remove(name);
            } else {
              _collapsedGroups.add(name);
            }
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: gold.withValues(alpha: isDragOver || hovered ? 0.14 : 0.08),
              border: const Border(left: BorderSide(color: gold, width: 2))),
            child: Row(children: [
              Icon(collapsed ? Icons.chevron_right : Icons.expand_more,
                color: gold, size: 14),
              const SizedBox(width: 4),
              Text(name.toUpperCase(), style: GoogleFonts.cinzel(
                color: gold, fontSize: 13, letterSpacing: 1.2)),
              const Spacer(),
              Text('· ${army.units.where((u) => u.groupName == name).length} units',
                style: GoogleFonts.cinzel(color: grey, fontSize: 12)),
              const SizedBox(width: 6),
              Text(
                '${army.units.where((u) => u.groupName == name).fold(0, (s, u) => s + u.unit.cost)} pts',
                style: GoogleFonts.cinzel(color: grey, fontSize: 12)),
              const SizedBox(width: 8),
              GroupTrashBtn(
                groupName: name,
                onDelete: () => army.removeGroup(name)),
            ]),
          ),
        ),
      ),
    );
  }

  void _addGroupDialog(ArmyState army) {
    final ctrl = TextEditingController();
    showAetherraDialog(context,
      title: 'New Group',
      content: AetherraTextField(
        controller: ctrl,
        autofocus: true,
        hintText: 'Group name…'),
      actions: [
        aDialogBtn('Cancel', grey, () => Navigator.pop(context)),
        aDialogBtn('Add', gold, () {
          army.addGroup(ctrl.text.trim());
          Navigator.pop(context);
        }),
      ]);
  }

  Future<void> _save() async {
    final army = context.read<ArmyState>();
    final name = army.name.trim();
    if (name.isEmpty || _saving) return;
    setState(() { _saving = true; _saved = false; });
    try {
      final id = await ArmyService.save(army, name, army.listId);
      if (id != null && mounted) {
        army.listId = id;
        setState(() { _saving = false; _saved = true; });
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _saved = false);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── HELPERS ────────────────────────────────────────────
  Widget _mStat(String v, String l) => SizedBox(
    width: 36, height: 44,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(v, textAlign: TextAlign.center,
          style: GoogleFonts.cinzel(color: gold, fontSize: 17, fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()])),
        Text(l, textAlign: TextAlign.center,
          style: GoogleFonts.cinzel(color: grey, fontSize: 9, letterSpacing: 1.2)),
      ]));

}


// ── Multi-select filter dropdown ─────────────────────────────────────────────
class _FilterDropdown extends StatefulWidget {
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  const _FilterDropdown({required this.selected, required this.onChanged});
  @override State<_FilterDropdown> createState() => _FilterDropdownState();
}

class _FilterDropdownState extends State<_FilterDropdown> {
  static const gold  = AppColors.gold;
  static const types = ['Infantry','Cavalry','Shooting','Artillery','Hero','Monster'];

  OverlayEntry? _entry;
  final _link  = LayerLink();
  // Notifier so overlay rows rebuild without removing/re-inserting
  late final ValueNotifier<Set<String>> _sel =
    ValueNotifier(Set<String>.from(widget.selected));

  @override void didUpdateWidget(_FilterDropdown old) {
    super.didUpdateWidget(old);
    // Defer to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sel.value = Set<String>.from(widget.selected);
    });
  }

  @override void dispose() {
    _entry?.remove(); _entry = null;  // don't call setState in dispose
    _sel.dispose();
    super.dispose();
  }

  void _toggle() => _entry == null ? _open() : _close();

  void _open() {
    _entry = OverlayEntry(builder: (_) => _DropMenu(
      link: _link,
      types: types,
      sel: _sel,
      onToggle: (t) {
        final next = Set<String>.from(_sel.value);
        if (next.contains(t)) {
          next.remove(t);
        } else {
          next.add(t);
        }
        _sel.value = next;
        widget.onChanged(next);
      },
      onClose: _close,
    ));
    Overlay.of(context).insert(_entry!);
    setState(() {});
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  bool _hovered = false;

  @override Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit:  (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _toggle,
          child: ValueListenableBuilder<Set<String>>(
            valueListenable: _sel,
            builder: (_, sel, __) {
              final label = sel.isEmpty ? 'All Types'
                : sel.length == 1 ? sel.first
                : '${sel.length} Types';
              return AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _hovered
                    ? gold.withValues(alpha: 0.12)
                    : sel.isEmpty ? Colors.transparent : gold.withValues(alpha: 0.12),
                  border: Border.all(
                    color: _hovered
                      ? gold
                      : sel.isEmpty ? gold.withValues(alpha: 0.3) : gold)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.filter_list, color: gold, size: 15),
                  const SizedBox(width: 5),
                  Text(label, style: GoogleFonts.cinzel(color: gold, fontSize: 12),
                    maxLines: 1),
                  const SizedBox(width: 4),
                Icon(_entry != null ? Icons.expand_less : Icons.expand_more,
                  color: gold, size: 14),
              ]));
          }))));
  }
}

// ── Hover-aware checkbox item ─────────────────────────────────────────────────
class _CheckItem extends StatefulWidget {
  final String       text;
  final bool         checked;
  final VoidCallback onTap;
  const _CheckItem({required this.text, required this.checked, required this.onTap});
  @override State<_CheckItem> createState() => _CheckItemState();
}
class _CheckItemState extends State<_CheckItem> {
  bool _hovered = false;
  @override Widget build(BuildContext context) =>
    MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: double.infinity,
          color: _hovered && !widget.checked
            ? AppColors.gold.withValues(alpha: 0.06)
            : null,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Container(
              width: 16, height: 16,
              decoration: BoxDecoration(
                color: widget.checked
                  ? AppColors.gold
                  : Colors.transparent,
                border: Border.all(
                  color: AppColors.gold.withValues(
                    alpha: _hovered && !widget.checked ? 0.75 : 0.5))),
              child: widget.checked
                ? const Icon(Icons.check, color: AppColors.dark, size: 12)
                : _hovered
                  ? Icon(Icons.check,
                      color: AppColors.gold.withValues(alpha: 0.3),
                      size: 12)
                  : null),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.text,
              style: GoogleFonts.cinzel(
                color: widget.checked
                  ? AppColors.gold
                  : _hovered
                    ? AppColors.gold.withValues(alpha: 0.65)
                    : AppColors.grey,
                fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis)),
          ]))));
}

// ── Hover-aware sort popup item ───────────────────────────────────────────────
class _SortItem extends StatefulWidget {
  final String label;
  final bool   active;
  final bool   ascending;
  const _SortItem({required this.label, required this.active, this.ascending = true});
  @override State<_SortItem> createState() => _SortItemState();
}
class _SortItemState extends State<_SortItem> {
  static const _gold = AppColors.gold;
  bool _hovered = false;
  @override Widget build(BuildContext context) =>
    MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: _hovered && !widget.active
          ? _gold.withValues(alpha: 0.08)
          : null,
        child: Row(children: [
          Expanded(child: Text(widget.label, style: GoogleFonts.cinzel(
            color: widget.active ? _gold
              : _hovered ? _gold.withValues(alpha: 0.75)
              : AppColors.greyLight,
            fontSize: 15))),
          if (widget.active)
            Icon(widget.ascending ? Icons.arrow_upward : Icons.arrow_downward,
              color: _gold, size: 11),
        ])));
}

class _DropMenu extends StatelessWidget {
  final LayerLink link;
  final List<String> types;
  final ValueNotifier<Set<String>> sel;
  final void Function(String) onToggle;
  final VoidCallback onClose;
  const _DropMenu({required this.link, required this.types,
    required this.sel, required this.onToggle, required this.onClose});

  @override Widget build(BuildContext context) =>
    Stack(children: [
      Positioned.fill(child: GestureDetector(
        behavior: HitTestBehavior.opaque, onTap: onClose,
        child: const SizedBox.expand())),
      CompositedTransformFollower(
        link: link,
        showWhenUnlinked: false,
        offset: const Offset(0, 36),
        child: Material(color: Colors.transparent,
          child: Container(
            width: 160,
            decoration: BoxDecoration(
              color: AppColors.dark,
              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.4))),
            child: ValueListenableBuilder<Set<String>>(
              valueListenable: sel,
              builder: (_, current, __) => Column(
                mainAxisSize: MainAxisSize.min,
                children: types.map<Widget>((t) => _CheckItem(
                  text: t,
                  checked: current.contains(t),
                  onTap: () => onToggle(t),
                )).toList())))))
    ]);
}

class _XButton extends StatefulWidget {
  final VoidCallback onTap;
  const _XButton({required this.onTap});
  @override State<_XButton> createState() => _XButtonState();
}
class _XButtonState extends State<_XButton> {
  bool _pressed = false;
  bool _hovered = false;
  @override Widget build(BuildContext context) =>
    MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown:   (_) => setState(() => _pressed = true),
        onTapUp:     (_) { setState(() => _pressed = false); widget.onTap(); },
        onTapCancel: ()  => setState(() => _pressed = false),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: SizedBox(
            width: 20, height: 20,
            child: AnimatedScale(
              scale: _pressed ? 0.80 : _hovered ? 1.2 : 1.0,
              duration: const Duration(milliseconds: 100),
              child: Icon(Icons.delete_outline,
                color: Colors.red.withValues(
                  alpha: _pressed ? 1.0 : _hovered ? 0.9 : 0.5),
                size: 16))))));
}

class _BuilderPhotoIcon extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  const _BuilderPhotoIcon({required this.icon, required this.onTap, this.color = AppColors.gold});
  @override State<_BuilderPhotoIcon> createState() => _BuilderPhotoIconState();
}
class _BuilderPhotoIconState extends State<_BuilderPhotoIcon> {
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

class _BuilderTab extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _BuilderTab({required this.icon, required this.label,
    required this.selected, required this.onTap});
  @override State<_BuilderTab> createState() => _BuilderTabState();
}
class _BuilderTabState extends State<_BuilderTab> {
  bool _hovered = false;
  static const gold = AppColors.gold;
  static const grey = AppColors.grey;
  @override Widget build(BuildContext context) {
    final color = widget.selected ? gold
        : _hovered ? gold.withValues(alpha: 0.7) : grey;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(
              color: widget.selected ? gold : Colors.transparent,
              width: 2))),
          child: Column(children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 120),
              child: Icon(widget.icon, key: ValueKey(color), color: color, size: 18)),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 120),
              style: GoogleFonts.cinzel(color: color, fontSize: 13),
              child: Text(widget.label)),
          ]))));
  }
}


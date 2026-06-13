import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/game_data_service.dart';
import '../widgets/unit_card.dart';
import '../widgets/nav_btn.dart';
import '../widgets/aetherra_text_field.dart';
import '../app_theme.dart';

class FactionUnitPickerScreen extends StatefulWidget {
  final Map<String, dynamic>        faction;
  final List<Map<String, dynamic>>  userUnits;
  final List<Map<String, dynamic>>  allFactions;
  // Optional override: if provided, called instead of default DB save logic.
  // Receives (assignedUserIds, assignedOfficialRefs).
  final Future<void> Function(Set<String>, Set<String>)? saveCallback;

  const FactionUnitPickerScreen({
    super.key,
    required this.faction,
    required this.userUnits,
    required this.allFactions,
    this.saveCallback,
  });

  @override
  State<FactionUnitPickerScreen> createState() =>
      _FactionUnitPickerScreenState();
}

class _FactionUnitPickerScreenState extends State<FactionUnitPickerScreen> {
  static const gold  = AppColors.gold;
  static const grey  = AppColors.grey;
  static final _sb   = Supabase.instance.client;

  late final String _fid;
  late final String _fname;
  late final Color  _fcolor;

  late final Set<String> _assignedUserIds;
  late final Set<String> _assignedOfficialRefs;

  String      _search  = '';
  final _searchCtrl = TextEditingController();
  Set<String> _fTypes  = {};
  Set<String> _selFacs = {};
  String      _sortBy  = 'name';
  bool        _sortAsc = true;
  int         _tabIdx  = 0;
  double      _leftW   = 0; // 0 = use default ratio; set once layout known

  @override
  void initState() {
    super.initState();
    _fid    = widget.faction['id'] as String;
    _fname  = widget.faction['name'] as String;
    _fcolor = AppColors.parseHex(widget.faction['color'] as String? ?? '#888888');

    _assignedUserIds = Set<String>.from(
      widget.userUnits
          .where((u) => u['faction_id'] == _fid)
          .map((u) => u['id'] as String));

    _assignedOfficialRefs = Set<String>.from(
      (widget.faction['unit_refs'] as List?)?.cast<String>() ?? []);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Faction name lookup ───────────────────────────────────────
  String _facName(String? fid) {
    if (fid == null) return '';
    final off = GameDataService.factions
        .where((f) => f['id'] == fid).firstOrNull;
    if (off != null) return off['name'] as String;
    final usr = widget.allFactions
        .where((f) => f['id'] == fid).firstOrNull;
    return usr?['name'] as String? ?? '';
  }

  // All unique faction IDs present in available-unit pool
  List<Map<String, dynamic>> get _facChoices {
    final ids = <String>{};
    for (final u in widget.userUnits) {
      final fid = u['faction_id'] as String?;
      if (fid != null && fid != _fid) ids.add(fid);
    }
    for (final u in GameDataService.units) {
      final fid = u['faction_id'] as String?;
      if (fid != null) ids.add(fid);
    }
    final choices = ids
        .map((id) => {'id': id, 'name': _facName(id)})
        .where((m) => (m['name'] as String).isNotEmpty)
        .toList();
    choices.sort((a, b) =>
        (a['name'] as String).compareTo(b['name'] as String));
    return choices;
  }

  // ── Data helpers ──────────────────────────────────────────────
  Set<String> get _userUnitIds =>
      Set<String>.from(widget.userUnits.map((u) => u['id'] as String));

  List<Map<String, dynamic>> get _roster {
    final userIds = _userUnitIds;
    final result = <Map<String, dynamic>>[];
    for (final u in widget.userUnits) {
      if (_assignedUserIds.contains(u['id'] as String)) {
        result.add({...u, '_src': 'user'});
      }
    }
    for (final u in GameDataService.units) {
      if (userIds.contains(u['id'] as String)) continue;
      if (_assignedOfficialRefs.contains(u['name'] as String)) {
        result.add({...u, '_src': 'official'});
      }
    }
    result.sort((a, b) =>
        (a['name'] as String).compareTo(b['name'] as String));
    return result;
  }

  List<Map<String, dynamic>> get _available {
    final q = _search.toLowerCase();
    final userIds = _userUnitIds;
    final result = <Map<String, dynamic>>[];

    for (final u in widget.userUnits) {
      if (_assignedUserIds.contains(u['id'] as String)) { continue; }
      if (q.isNotEmpty &&
          !(u['name'] as String).toLowerCase().contains(q)) { continue; }
      if (_fTypes.isNotEmpty && !_fTypes.contains(u['type'])) { continue; }
      if (_selFacs.isNotEmpty &&
          !_selFacs.contains(u['faction_id'] as String?)) { continue; }
      result.add({...u, '_src': 'user'});
    }
    for (final u in GameDataService.units) {
      if (userIds.contains(u['id'] as String)) continue;
      if (_assignedOfficialRefs.contains(u['name'] as String)) { continue; }
      if (q.isNotEmpty &&
          !(u['name'] as String).toLowerCase().contains(q)) { continue; }
      if (_fTypes.isNotEmpty && !_fTypes.contains(u['type'])) { continue; }
      if (_selFacs.isNotEmpty &&
          !_selFacs.contains(u['faction_id'] as String?)) { continue; }
      result.add({...u, '_src': 'official'});
    }

    result.sort((a, b) {
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
    return result;
  }

  void _add(Map<String, dynamic> u) => setState(() {
    if (u['_src'] == 'user') {
      _assignedUserIds.add(u['id'] as String);
    } else {
      _assignedOfficialRefs.add(u['name'] as String);
    }
  });

  void _remove(Map<String, dynamic> u) => setState(() {
    if (u['_src'] == 'user') {
      _assignedUserIds.remove(u['id'] as String);
    } else {
      _assignedOfficialRefs.remove(u['name'] as String);
    }
  });

  Future<void> _saveAndPop() async {
    try {
      if (widget.saveCallback != null) {
        await widget.saveCallback!(_assignedUserIds, _assignedOfficialRefs);
      } else {
        for (final u in widget.userUnits) {
          final uid2  = u['id'] as String;
          final wasIn = u['faction_id'] == _fid;
          final nowIn = _assignedUserIds.contains(uid2);
          if (wasIn != nowIn) {
            await _sb.from('user_units').update({
              'faction_id': nowIn ? _fid : null,
            }).eq('id', uid2);
          }
        }
        try {
          await _sb.from('user_factions').update({
            'unit_refs': _assignedOfficialRefs.toList(),
          }).eq('id', _fid);
        } catch (_) {}
      }
    } catch (_) {}
    if (mounted) Navigator.pop(context, true);
  }

  // ── BUILD ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final available = _available;
    final roster    = _roster;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _saveAndPop();
      },
      child: Scaffold(
        backgroundColor: AppColors.dark,
        appBar: AppBar(
          scrolledUnderElevation: 0,
          leading: NavBtn(
            icon: Icons.arrow_back_ios_new,
            onPressed: _saveAndPop),
          title: Text('Assign Units',
            style: GoogleFonts.cinzel(
              color: gold, fontSize: 17, letterSpacing: 2)),
        ),
        body: Column(children: [
          Expanded(child: LayoutBuilder(builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 661;
          if (isWide) {
            final totalW  = constraints.maxWidth;
            const minLeft  = 380.0;
            const minRight = 280.0;
            if (_leftW == 0) _leftW = (totalW * 0.6).clamp(minLeft, totalW - minRight);
            final leftW  = _leftW.clamp(minLeft, totalW - minRight);
            final rightW = totalW - leftW - 6;
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: leftW,  child: _availablePanel(available)),
              // Draggable divider
              GestureDetector(
                onHorizontalDragUpdate: (d) => setState(() {
                  _leftW = (_leftW + d.delta.dx)
                      .clamp(minLeft, totalW - minRight);
                }),
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: Container(width: 6, color: AppColors.dark,
                    child: Center(child: Container(
                      width: 2, height: 40,
                      decoration: BoxDecoration(
                        color: gold.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2))))))),
              SizedBox(width: rightW, child: _factionPanel(roster)),
            ]);
          } else {
            return Column(children: [
              Expanded(child: _tabIdx == 0
                ? _availablePanel(available)
                : _factionPanel(roster)),
              Container(color: AppColors.dark,
                child: Row(children: [
                  Expanded(child: GestureDetector(
                    onTap: () => setState(() => _tabIdx = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(
                          color: _tabIdx == 0 ? gold : Colors.transparent,
                          width: 2))),
                      child: Column(children: [
                        Icon(Icons.list_alt_outlined,
                          color: _tabIdx == 0 ? gold : grey, size: 18),
                        const SizedBox(height: 2),
                        Text('Available',
                          style: GoogleFonts.cinzel(
                            color: _tabIdx == 0 ? gold : grey,
                            fontSize: 13)),
                      ])))),
                  Expanded(child: GestureDetector(
                    onTap: () => setState(() => _tabIdx = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(
                          color: _tabIdx == 1 ? gold : Colors.transparent,
                          width: 2))),
                      child: Column(children: [
                        Icon(Icons.format_list_bulleted,
                          color: _tabIdx == 1 ? gold : grey, size: 18),
                        const SizedBox(height: 2),
                        Text('$_fname (${roster.length})',
                          style: GoogleFonts.cinzel(
                            color: _tabIdx == 1 ? gold : grey,
                            fontSize: 13),
                          overflow: TextOverflow.ellipsis),
                      ])))),
                ])),
            ]);
          }
          })),
        ])));
  }

  // ── Available panel (left) ────────────────────────────────────
  Widget _availablePanel(List<Map<String, dynamic>> available) {
    final choices = _facChoices;
    return Column(children: [
      // Row 1: type filter + faction filter + sort (all on one line)
      SizedBox(height: 44,
        child: Container(color: AppColors.dark,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center,
            children: [
            _TypeDropdown(
              selected: _fTypes,
              onChanged: (s) => setState(() => _fTypes = s)),
            if (choices.isNotEmpty) ...[
              const SizedBox(width: 6),
              _FactionDropdown(
                choices: choices,
                selected: _selFacs,
                onChanged: (s) => setState(() => _selFacs = s)),
            ],
            const Spacer(),
            _SortButton(
              sortBy: _sortBy,
              ascending: _sortAsc,
              onSelected: (v) => setState(() {
                if (v == _sortBy) { _sortAsc = !_sortAsc; }
                else { _sortBy = v; _sortAsc = true; }
              })),
          ]))),
      // Row 2: search
      Container(color: AppColors.dark,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: AetherraTextField(
          controller: _searchCtrl,
          style: const TextStyle(color: AppColors.textLight, fontSize: 13),
          hintText: 'Search units…',
          hintStyle: TextStyle(color: grey.withValues(alpha: 0.45)),
          prefixIcon: const Icon(Icons.search, color: grey, size: 16),
          isDense: true,
          clearable: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
          onChanged: (v) => setState(() => _search = v))),
      // Responsive card grid
      Expanded(child: available.isEmpty
        ? Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _search.isEmpty && _fTypes.isEmpty && _selFacs.isEmpty
                ? 'All units are assigned.' : 'No units match.',
              textAlign: TextAlign.center,
              style: GoogleFonts.cinzel(
                color: grey.withValues(alpha: 0.45),
                fontSize: 13, height: 1.6))))
        : LayoutBuilder(builder: (ctx, constraints) {
            final avail = constraints.maxWidth - 26;
            final cols  = avail < 600 ? 1 : avail < 950 ? 2
                        : avail < 1300 ? 3 : avail < 1650 ? 4 : 5;
            final rawW  = (avail - (cols - 1) * 8) / cols;
            final cardW = rawW.floorToDouble();
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: (available.length / cols).ceil(),
              itemBuilder: (_, row) {
                final start = row * cols;
                final end   = (start + cols).clamp(0, available.length);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (int i = start; i < end; i++) ...[
                        if (i > start) const SizedBox(width: 8),
                        SizedBox(width: cardW,
                          child: RosterCard(
                            unitData: available[i],
                            isDisabled: false,
                            onAdd: () => _add(available[i]))),
                      ],
                    ]));
              });
          })),
    ]);
  }

  // ── Faction panel (right) ─────────────────────────────────────
  Widget _factionPanel(List<Map<String, dynamic>> roster) {
    return Container(
      decoration: BoxDecoration(color: AppColors.dark,
        border: Border(left: BorderSide(color: gold.withValues(alpha: 0.2)))),
      child: Column(children: [
        SizedBox(height: 44,
          child: Container(color: AppColors.dark,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center,
              children: [
              Expanded(child: Text(_fname,
                style: GoogleFonts.cinzel(
                  color: gold, fontSize: 14, letterSpacing: 1),
                overflow: TextOverflow.ellipsis)),
              Text('${roster.length} units',
                style: GoogleFonts.cinzel(
                  color: gold.withValues(alpha: 0.75), fontSize: 12)),
            ]))),
        Divider(height: 1, color: gold.withValues(alpha: 0.15)),
        Expanded(child: roster.isEmpty
          ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.group_outlined,
                color: gold.withValues(alpha: 0.2), size: 32),
              const SizedBox(height: 8),
              Text('No units yet.',
                style: GoogleFonts.cinzel(color: grey, fontSize: 15)),
              const SizedBox(height: 4),
              Text('Add from the roster',
                style: TextStyle(
                  color: grey.withValues(alpha: 0.6), fontSize: 13)),
            ]))
          : LayoutBuilder(builder: (ctx, constraints) {
              final avail = constraints.maxWidth - 26;
              final cols  = avail < 600 ? 1 : avail < 950 ? 2
                          : avail < 1300 ? 3 : avail < 1650 ? 4 : 5;
              final rawW  = (avail - (cols - 1) * 8) / cols;
              final cardW = rawW.floorToDouble();
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: (roster.length / cols).ceil(),
                itemBuilder: (_, row) {
                  final start = row * cols;
                  final end   = (start + cols).clamp(0, roster.length);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int i = start; i < end; i++) ...[
                          if (i > start) const SizedBox(width: 8),
                          SizedBox(width: cardW,
                            child: _AssignedCard(
                              unitData: roster[i],
                              factionColor: _fcolor,
                              onRemove: () => _remove(roster[i]))),
                        ],
                      ]));
                });
            })),
      ]));
  }
}

// ── Assigned unit card (faction roster) ──────────────────────────────────────
class _AssignedCard extends StatelessWidget {
  final Map<String, dynamic> unitData;
  final Color                factionColor;
  final VoidCallback         onRemove;

  const _AssignedCard({
    required this.unitData,
    required this.factionColor,
    required this.onRemove,
  });

  static const gold = AppColors.gold;

  @override Widget build(BuildContext context) {
    final u      = unitData;
    final tc     = typeColor(u['type'] as String? ?? '');
    final abs    = List<String>.from(u['abilities'] ?? []);
    bool z(String k) => (u[k] ?? 0) == 0;

    return Container(
      constraints: const BoxConstraints(
        minWidth: 260, maxHeight: 140, minHeight: 140),
      decoration: BoxDecoration(
        color: AppColors.dark,
        border: Border(
          left:   BorderSide(color: tc.withValues(alpha: 0.6), width: 2),
          right:  BorderSide(color: tc.withValues(alpha: 0.35)),
          top:    BorderSide(color: tc.withValues(alpha: 0.35)),
          bottom: BorderSide(color: tc.withValues(alpha: 0.35)))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Type icon column
        SizedBox(width: 80, height: 140,
          child: ColoredBox(color: tc.withValues(alpha: 0.12),
            child: Column(mainAxisAlignment: MainAxisAlignment.center,
              children: [
              typeIconWidget(u['type'] as String? ?? '',
                size: 42, color: tc.withValues(alpha: 0.7)),
              const SizedBox(height: 4),
              Text(u['type'] as String? ?? '',
                style: GoogleFonts.cinzel(color: tc, fontSize: 9),
                textAlign: TextAlign.center),
            ]))),
        // Content
        Expanded(child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 3, 6, 3),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Name + cost
            Row(children: [
              Expanded(child: Text(u['name'] as String? ?? '',
                style: GoogleFonts.cinzel(
                  color: AppColors.goldLight,
                  fontSize: 14, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text('${u['cost'] ?? 0}pts',
                style: GoogleFonts.cinzel(
                  color: gold, fontSize: 13,
                  fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 3),
            // Stats
            FittedBox(fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(children: [
                _statBox('ATK', '${u['atk'] ?? 0}',     z('atk')),
                _statBox('DEF', '${u['def_val'] ?? 0}',  z('def_val')),
                _statBox('SHO', '${u['rng'] ?? 0}',     z('rng')),
                _statBox('MOB', '${u['mob'] ?? 0}',     z('mob')),
                _statBox('STR', '${u['con_val'] ?? 0}',  z('con_val')),
                _statBox('CP',  '${u['cp'] ?? 0}',      z('cp')),
              ])),
            const SizedBox(height: 3),
            // 2-row ability layout with remove button as trailing
            abilityRows(abs, tColor: tc,
              trailing: _RemoveButton(onTap: onRemove)),
          ]))),
      ]));
  }

  static Widget _statBox(String label, String value, bool dimmed) =>
    Container(
      width: 44,
      margin: const EdgeInsets.only(right: 1),
      padding: const EdgeInsets.symmetric(vertical: 3),
      color: AppColors.dark,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        Text(label, textAlign: TextAlign.center,
          style: GoogleFonts.cinzel(
            fontSize: 10,
            color: dimmed
              ? AppColors.grey.withValues(alpha: 0.35)
              : AppColors.grey)),
        Text(value, textAlign: TextAlign.center,
          style: GoogleFonts.cinzel(
            fontSize: 16, fontWeight: FontWeight.w600,
            color: dimmed
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.white)),
      ]));
}

// ── Remove button ─────────────────────────────────────────────────────────────
class _RemoveButton extends StatefulWidget {
  final VoidCallback onTap;
  const _RemoveButton({required this.onTap});
  @override State<_RemoveButton> createState() => _RemoveButtonState();
}
class _RemoveButtonState extends State<_RemoveButton> {
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

// ── Sort button (mirrors builder_screen) ──────────────────────────────────────
class _SortButton extends StatefulWidget {
  final String sortBy;
  final bool ascending;
  final ValueChanged<String> onSelected;
  const _SortButton({required this.sortBy, required this.ascending, required this.onSelected});
  @override State<_SortButton> createState() => _SortButtonState();
}
class _SortButtonState extends State<_SortButton> {
  static const gold = AppColors.gold;
  bool _hovered = false;

  @override Widget build(BuildContext context) {
    final btn = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _hovered ? gold.withValues(alpha: 0.12) : Colors.transparent,
        border: Border.all(color: _hovered ? gold : gold.withValues(alpha: 0.4))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.sort, color: gold, size: 16),
        const SizedBox(width: 4),
        Text('Sort', style: GoogleFonts.cinzel(color: gold, fontSize: 13)),
      ]));

    final menu = PopupMenuButton<String>(
      color: AppColors.dark,
      enableFeedback: false,
      tooltip: '',
      iconSize: 0,
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      onSelected: widget.onSelected,
      itemBuilder: (_) => [
        for (final s in [
          ['name', 'Name A→Z'], ['cost', 'Points ↓'],
          ['atk',  'ATK ↓'],   ['def', 'DEF ↓'],
          ['rng',  'SHO ↓'],   ['mob', 'MOB ↓'],
          ['con',  'STR ↓'],   ['cp',  'AP ↓'],
        ])
          PopupMenuItem(value: s[0],
            padding: EdgeInsets.zero,
            child: _SortItem(
              label: s[1],
              active: widget.sortBy == s[0],
              ascending: widget.sortBy == s[0] && widget.ascending)),
      ],
      child: btn);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: Theme(
        data: Theme.of(context).copyWith(
          splashFactory:  NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          splashColor:    Colors.transparent,
          hoverColor:     Colors.transparent),
        child: menu));
  }
}

// ── Type multi-select filter dropdown (mirrors builder_screen) ─────────────────
class _TypeDropdown extends StatefulWidget {
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  const _TypeDropdown({required this.selected, required this.onChanged});
  @override State<_TypeDropdown> createState() => _TypeDropdownState();
}

class _TypeDropdownState extends State<_TypeDropdown> {
  static const gold  = AppColors.gold;
  static const types = ['Infantry', 'Cavalry', 'Shooting', 'Artillery', 'Hero', 'Monster', 'Flyer', 'Vehicle'];

  OverlayEntry? _entry;
  final _link   = LayerLink();
  late final ValueNotifier<Set<String>> _sel =
    ValueNotifier(Set<String>.from(widget.selected));

  @override void didUpdateWidget(_TypeDropdown old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sel.value = Set<String>.from(widget.selected);
    });
  }

  @override void dispose() {
    _entry?.remove(); _entry = null;
    _sel.dispose();
    super.dispose();
  }

  void _toggle() => _entry == null ? _open() : _close();

  void _open() {
    _entry = OverlayEntry(builder: (_) => _CheckDropMenu(
      link: _link, items: types, sel: _sel,
      onToggle: (t) {
        final next = Set<String>.from(_sel.value);
        if (next.contains(t)) { next.remove(t); } else { next.add(t); }
        _sel.value = next;
        widget.onChanged(next);
      },
      onClose: _close));
    Overlay.of(context).insert(_entry!);
    setState(() {});
  }

  void _close() {
    _entry?.remove(); _entry = null;
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _hovered
                    ? gold.withValues(alpha: 0.12)
                    : sel.isEmpty
                      ? Colors.transparent
                      : gold.withValues(alpha: 0.12),
                  border: Border.all(
                    color: _hovered ? gold
                      : sel.isEmpty ? gold.withValues(alpha: 0.3) : gold)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.filter_list, color: gold, size: 15),
                  const SizedBox(width: 5),
                  Text(label,
                    style: GoogleFonts.cinzel(color: gold, fontSize: 12)),
                  const SizedBox(width: 4),
                  Icon(_entry != null
                    ? Icons.expand_less : Icons.expand_more,
                    color: gold, size: 14),
                ]));
            }))));
  }
}

// ── Faction multi-select filter dropdown ──────────────────────────────────────
class _FactionDropdown extends StatefulWidget {
  final List<Map<String, dynamic>> choices;
  final Set<String>                selected;
  final ValueChanged<Set<String>>  onChanged;
  const _FactionDropdown({
    required this.choices,
    required this.selected,
    required this.onChanged,
  });
  @override State<_FactionDropdown> createState() => _FactionDropdownState();
}

class _FactionDropdownState extends State<_FactionDropdown> {
  static const gold = AppColors.gold;
  OverlayEntry? _entry;
  final _link   = LayerLink();
  // _sel stores faction NAMES (not IDs) so it can be passed directly to _CheckDropMenu
  late final ValueNotifier<Set<String>> _sel =
    ValueNotifier(_idsToNames(widget.selected));

  Set<String> _idsToNames(Set<String> ids) => ids.map((id) {
    final c = widget.choices.where((m) => m['id'] == id).firstOrNull;
    return c?['name'] as String? ?? '';
  }).where((n) => n.isNotEmpty).toSet();

  Set<String> _namesToIds(Set<String> names) => names.map((name) {
    final c = widget.choices.where((m) => m['name'] == name).firstOrNull;
    return c?['id'] as String? ?? '';
  }).where((id) => id.isNotEmpty).toSet();

  @override void didUpdateWidget(_FactionDropdown old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sel.value = _idsToNames(widget.selected);
    });
  }

  @override void dispose() {
    _entry?.remove(); _entry = null;
    _sel.dispose();
    super.dispose();
  }

  void _toggle() => _entry == null ? _open() : _close();

  void _open() {
    _entry = OverlayEntry(builder: (_) => _CheckDropMenu(
      link: _link,
      items: widget.choices.map((c) => c['name'] as String).toList(),
      sel: _sel,  // pass directly; _sel stores names
      onToggle: (name) {
        final next = Set<String>.from(_sel.value);
        if (next.contains(name)) { next.remove(name); } else { next.add(name); }
        _sel.value = next;
        widget.onChanged(_namesToIds(next));
      },
      onClose: _close));
    Overlay.of(context).insert(_entry!);
    setState(() {});
  }

  void _close() {
    _entry?.remove(); _entry = null;
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
              final label = sel.isEmpty ? 'All Factions'
                : sel.length == 1 ? sel.first
                : '${sel.length} Factions';
              return AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _hovered
                    ? gold.withValues(alpha: 0.12)
                    : sel.isEmpty
                      ? Colors.transparent
                      : gold.withValues(alpha: 0.12),
                  border: Border.all(
                    color: _hovered ? gold
                      : sel.isEmpty ? gold.withValues(alpha: 0.3) : gold)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.groups_outlined, color: gold, size: 15),
                  const SizedBox(width: 5),
                  Text(label,
                    style: GoogleFonts.cinzel(color: gold, fontSize: 12)),
                  const SizedBox(width: 4),
                  Icon(_entry != null
                    ? Icons.expand_less : Icons.expand_more,
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

// ── Generic check-list dropdown menu ─────────────────────────────────────────
class _CheckDropMenu extends StatelessWidget {
  final LayerLink                  link;
  final List<String>               items;
  final ValueNotifier<Set<String>> sel;
  final void Function(String)      onToggle;
  final VoidCallback               onClose;

  const _CheckDropMenu({
    required this.link,
    required this.items,
    required this.sel,
    required this.onToggle,
    required this.onClose,
  });

  @override Widget build(BuildContext context) =>
    Stack(children: [
      Positioned.fill(child: GestureDetector(
        behavior: HitTestBehavior.opaque, onTap: onClose,
        child: const SizedBox.expand())),
      CompositedTransformFollower(
        link: link, showWhenUnlinked: false,
        offset: const Offset(0, 36),
        child: Material(color: Colors.transparent,
          child: Container(
            width: 180,
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: BoxDecoration(
              color: AppColors.dark,
              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.4))),
            child: ValueListenableBuilder<Set<String>>(
              valueListenable: sel,
              builder: (_, current, __) => SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: items.map<Widget>((t) => _CheckItem(
                    text: t,
                    checked: current.contains(t),
                    onTap: () => onToggle(t),
                  )).toList()))))))
    ]);
}

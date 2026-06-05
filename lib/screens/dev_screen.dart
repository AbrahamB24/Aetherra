import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/game_data.dart';
import '../services/bg_remover.dart';
import '../services/cost_config.dart';
import '../services/game_data_service.dart';
import '../widgets/nav_btn.dart';
import '../widgets/photo_crop_dialog.dart';
import '../widgets/filter_widgets.dart';
import '../widgets/unit_card.dart';
import '../widgets/aetherra_text_field.dart';
import '../app_theme.dart';
import 'faction_unit_picker_screen.dart';

const _kBgPresets = [
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
  // Very light
  '#E0CCAA', '#A4CCD8', '#A4D4A4', '#EAA8A8',
  '#C0AAEC', '#94D4D4', '#E0D070', '#DCC0D0',
];

class DevScreen extends StatefulWidget {
  const DevScreen({super.key});
  @override
  State<DevScreen> createState() => _DevScreenState();
}

class _DevScreenState extends State<DevScreen>
    with SingleTickerProviderStateMixin {
  static const gold  = AppColors.gold;
        static const grey  = AppColors.grey;
  static final sb    = Supabase.instance.client;

  late TabController _tabs;

  // Supabase data
  List<Map<String, dynamic>> _dbUnits     = [];
  List<Map<String, dynamic>> _dbAbilities = [];
  bool _loading = true;

  // Cached derived lists — rebuilt after each _load()
  List<Map<String, dynamic>> _allFacs      = [];
  List<Map<String, dynamic>> _allUnits     = [];
  List<Map<String, dynamic>> _allAbilities = [];
  Map<String, int>           _allAbCosts   = {};
  String _creatorName = '';

  // Filters
  String _unitSearch     = '';
  String _abSearch       = '';
  String _unitSort       = 'name';
  bool   _unitSortAsc    = true;
  bool   _unitSearchOpen = false;
  bool   _abSearchOpen   = false;
  // Filters — factions
  String _facSearch      = '';
  String _facSort        = 'name';
  bool   _facSortAsc     = true;
  bool   _facSearchOpen  = false;
  final Set<String> _unitFacF  = {};
  final Set<String> _unitTypeF = {};
  final Set<String> _abTypeF   = {};
  final _unitSearchCtrl  = TextEditingController();
  final _unitSearchFocus = FocusNode();
  final _abSearchCtrl    = TextEditingController();
  final _abSearchFocus   = FocusNode();
  final _facSearchCtrl   = TextEditingController();
  final _facSearchFocus  = FocusNode();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _unitSearchCtrl.dispose();
    _unitSearchFocus.dispose();
    _abSearchCtrl.dispose();
    _abSearchFocus.dispose();
    _facSearchCtrl.dispose();
    _facSearchFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Reload everything from Supabase — updates all users' view
    await GameDataService.load();
    final r = await Future.wait([
      sb.from('custom_units').select('*').order('name'),
      sb.from('custom_factions').select('*').order('name'),
      sb.from('custom_abilities').select('*').order('name'),
    ]);
    final dbUnits     = List<Map<String,dynamic>>.from(r[0]);
    final dbFactions  = List<Map<String,dynamic>>.from(r[1]);
    final dbAbilities = List<Map<String,dynamic>>.from(r[2]);

    // Only show official abilities (from custom_abilities table), not Workshop/user content
    final userAbilityNames = GameDataService.userAbilities
        .map((a) => a['name'] as String).toSet();

    final abilities = <Map<String, dynamic>>[];
    for (final a in GameDataService.abilities) {
      final name = a['name'] as String;
      if (userAbilityNames.contains(name)) continue;
      final dbEntry  = dbAbilities.where((d) => d['name'] == name).firstOrNull;
      final isBuiltin = a['_builtin'] as bool? ?? false;
      final inDb     = dbEntry != null;
      abilities.add({
        ...a,
        '_overridden': inDb && isBuiltin,
        'cost':        inDb ? (dbEntry['cost'] ?? a['cost']) : a['cost'],
        'description': (inDb && dbEntry['description'] != null)
            ? dbEntry['description'] : a['description'],
        'types': inDb && dbEntry['types'] != null &&
            (dbEntry['types'] as List).isNotEmpty
            ? List<String>.from(dbEntry['types'] as List)
            : a['types'],
      });
    }

    final meta = sb.auth.currentUser?.userMetadata ?? {};
    final creatorName = meta['display_name'] as String?
        ?? meta['full_name'] as String?
        ?? meta['name'] as String?
        ?? '';

    setState(() {
      _dbUnits     = dbUnits;
      _dbAbilities = dbAbilities;
      // Merge builtins with their DB overrides (no duplicates).
      // Exclude user-owned units/factions — dev screen manages official content only.
      final userUnitIds    = GameDataService.userUnits.map((u) => u['id'] as String).toSet();
      final builtinFacIds  = builtinFactions.map((f) => f.id).toSet();
      final officialUnits  = GameDataService.units.where((u) => !userUnitIds.contains(u['id'] as String));
      final builtinUnitIds = officialUnits.map((u) => u['id'] as String).toSet();
      _allFacs = [
        ...builtinFactions.map((f) {
          final override = dbFactions
              .where((d) => d['id'] == f.id).firstOrNull;
          return override ?? {
            'id': f.id, 'name': f.name,
            'color': '#${f.color.toRadixString(16).substring(2).toUpperCase()}',
          };
        }),
        // Custom factions that are NOT builtin overrides
        ...dbFactions.where((d) => !builtinFacIds.contains(d['id'] as String)),
      ];
      // All builtin units merged with any DB overrides, plus pure custom units
      _allUnits = [
        ...officialUnits.map((u) {
          final override = dbUnits
              .where((d) => d['id'] == u['id']).firstOrNull;
          return override != null
              ? {...u, ...override, '_source': 'db'}
              : {...u, '_source': 'builtin'};
        }),
        ...dbUnits.where((d) => !builtinUnitIds.contains(d['id'] as String))
            .map((u) => {...u, '_source': 'db'}),
      ];
      _allAbilities = abilities;
      _allAbCosts   = GameDataService.abilityCosts;
      _creatorName  = creatorName;
      _loading      = false;
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        leading: NavBtn(icon: Icons.home_outlined, onPressed: () => Navigator.pop(context)),
        title: Text('Developer Mode',
          style: GoogleFonts.cinzel(color: gold, fontSize: 17, letterSpacing: 2)),
        actions: const [],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: AnimatedBuilder(
            animation: _tabs,
            builder: (_, __) => Row(
              children: [
                for (final e in ['Units','Factions','Abilities','Balance'].asMap().entries)
                  Expanded(child: _DevTabBtn(
                    label:    e.value,
                    selected: _tabs.index == e.key,
                    onTap:    () => _tabs.animateTo(e.key))),
              ]),
          )),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: gold))
        : TabBarView(controller: _tabs, children: [
            _unitsTab(), _factionsTab(), _abilitiesTab(), _balanceTab(),
          ]),
    );
  }

  // ═══════════════════════════════════════════════════
  // UNITS TAB — all editable
  // ═══════════════════════════════════════════════════
  Widget _unitsTab() {
    final all = _allUnits.where((u) {
      if (_unitFacF.isNotEmpty  && !_unitFacF.contains(u['faction_id'])) return false;
      if (_unitTypeF.isNotEmpty && !_unitTypeF.contains(u['type']))       return false;
      if (_unitSearch.isNotEmpty &&
        !(u['name'] as String).toLowerCase().contains(_unitSearch.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    all.sort((a, b) {
      int cmp;
      switch (_unitSort) {
        case 'cost': cmp = (b['cost']    as int? ?? 0).compareTo(a['cost']    as int? ?? 0); break;
        case 'atk':  cmp = (b['atk']     as int? ?? 0).compareTo(a['atk']     as int? ?? 0); break;
        case 'def':  cmp = (b['def_val'] as int? ?? 0).compareTo(a['def_val'] as int? ?? 0); break;
        case 'rng':  cmp = (b['rng']     as int? ?? 0).compareTo(a['rng']     as int? ?? 0); break;
        case 'mob':  cmp = (b['mob']     as int? ?? 0).compareTo(a['mob']     as int? ?? 0); break;
        case 'con':  cmp = (b['con_val'] as int? ?? 0).compareTo(a['con_val'] as int? ?? 0); break;
        default:     cmp = (a['name'] as String).compareTo(b['name'] as String);
      }
      return _unitSortAsc ? cmp : -cmp;
    });

    return Stack(children: [
      Positioned.fill(child: Column(children: [
        _filterBar(),
        Padding(padding: const EdgeInsets.fromLTRB(10,4,10,2),
          child: Align(alignment: Alignment.centerLeft,
            child: Text('${all.length} units',
              style: GoogleFonts.cinzel(color: grey, fontSize: 13, letterSpacing: 1.2)))),
        Expanded(
          child: all.isEmpty
            ? Center(child: Text('No units match.',
                style: GoogleFonts.cinzel(color: grey)))
            : LayoutBuilder(builder: (ctx, bc) {
                final avail = bc.maxWidth - 24;
                final cols  = avail < 600 ? 1 : avail < 950 ? 2 : 3;
                final cardW = ((avail - (cols - 1) * 8) / cols).floorToDouble().clamp(260.0, 600.0);
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 68),
                  itemCount: (all.length / cols).ceil(),
                  itemBuilder: (_, row) {
                    final start = row * cols;
                    final end   = (start + cols).clamp(0, all.length);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int i = start; i < end; i++) ...[
                          if (i > start) const SizedBox(width: 8),
                          SizedBox(width: cardW, child: _unitRow(all[i])),
                        ],
                      ]);
                  });
              })),
      ])),
      Positioned(bottom: 14, left: 0, right: 0,
        child: _CreateBtn(icon: Icons.add, label: 'New Unit',
          onTap: () => _openUnitForm(null))),
    ]);
  }

  Widget _filterBar() => Column(children: [
    SizedBox(height: 44, child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        FilterBtn(
          allLabel: 'All Factions',
          options: _allFacs.map((f) => MapEntry(
            f['id'] as String, f['name'] as String)).toList(),
          dotColors: { for (final f in _allFacs)
            f['id'] as String: AppColors.parseHex(f['color'] as String? ?? '#888') },
          selected: _unitFacF,
          onChanged: (s) => setState(() { _unitFacF.clear(); _unitFacF.addAll(s); })),
        const SizedBox(width: 8),
        FilterBtn(
          allLabel: 'All Types',
          options: const [
            MapEntry('Infantry','Infantry'), MapEntry('Cavalry','Cavalry'),
            MapEntry('Shooting','Shooting'), MapEntry('Artillery','Artillery'),
            MapEntry('Hero','Hero'), MapEntry('Monster','Monster'),
            MapEntry('Flyer','Flyer'),
          ],
          selected: _unitTypeF,
          onChanged: (s) => setState(() { _unitTypeF.clear(); _unitTypeF.addAll(s); })),
        const Spacer(),
        SortBtn(
          sortBy: _unitSort,
          ascending: _unitSortAsc,
          options: const [
            ['name','Name A→Z'], ['cost','Points ↓'],
            ['atk','ATK ↓'], ['def','DEF ↓'],
            ['rng','SHO ↓'], ['mob','MOB ↓'], ['con','STR ↓'],
          ],
          onSelected: (v) => setState(() {
            if (v == _unitSort) { _unitSortAsc = !_unitSortAsc; }
            else { _unitSort = v; _unitSortAsc = true; }
          })),
        const SizedBox(width: 8),
        SearchToggleBtn(
          isOpen: _unitSearchOpen,
          hasQuery: _unitSearch.isNotEmpty,
          onTap: () {
            setState(() {
              _unitSearchOpen = !_unitSearchOpen;
              if (!_unitSearchOpen) {
                _unitSearch = '';
                _unitSearchCtrl.clear();
              }
            });
            if (_unitSearchOpen) _unitSearchFocus.requestFocus();
          }),
      ]))),
    AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: _unitSearchOpen ? 46 : 0,
      color: AppColors.dark,
      clipBehavior: Clip.hardEdge,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
        child: AetherraTextField(
          controller: _unitSearchCtrl,
          focusNode: _unitSearchFocus,
          hintText: 'Search units…',
          prefixIcon: const Icon(Icons.search, color: grey, size: 18),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          onChanged: (v) => setState(() => _unitSearch = v)))),
  ]);

  Widget _unitRow(Map<String, dynamic> u) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RosterCard(
        unitData: u,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          _UnitActionBtn(
            icon: Icons.copy_outlined,
            color: grey.withValues(alpha: 0.55),
            onTap: () => _openUnitForm(u, isDuplicate: true)),
          _UnitActionBtn(
            icon: Icons.edit_outlined,
            color: gold.withValues(alpha: 0.75),
            onTap: () => _openUnitForm(u)),
        ])));
  }

  Future<void> _deleteUnit(Map<String, dynamic> u) async {
    if (!await _confirm('Delete "${u['name']}"?')) return;
    // Delete from DB (upserted builtins are stored there too)
    await sb.from('custom_units').delete().eq('id', u['id']);
    _load();
  }

  // ═══════════════════════════════════════════════════
  // FACTIONS TAB
  // ═══════════════════════════════════════════════════
  Widget _factionsTab() {
    var filtered = _allFacs.where((f) {
      if (_facSearch.isEmpty) return true;
      return (f['name'] as String).toLowerCase().contains(_facSearch.toLowerCase());
    }).toList();

    filtered.sort((a, b) {
      int cmp;
      switch (_facSort) {
        case 'units':
          final aU = GameDataService.units.where((u) => u['faction_id'] == a['id']).length;
          final bU = GameDataService.units.where((u) => u['faction_id'] == b['id']).length;
          cmp = bU.compareTo(aU);
          break;
        case 'created':
          final aD = a['created_at'] as String? ?? '';
          final bD = b['created_at'] as String? ?? '';
          cmp = bD.compareTo(aD);
          break;
        default:
          cmp = (a['name'] as String).compareTo(b['name'] as String);
      }
      return _facSortAsc ? cmp : -cmp;
    });

    return Stack(children: [
      Positioned.fill(child: Column(children: [
        SizedBox(height: 44, child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            const Spacer(),
            SortBtn(
              sortBy: _facSort,
              ascending: _facSortAsc,
              options: const [
                ['name',    'Name A→Z'],
                ['units',   'Units ↓'],
                ['created', 'Newest First'],
              ],
              onSelected: (v) => setState(() {
                if (v == _facSort) { _facSortAsc = !_facSortAsc; }
                else { _facSort = v; _facSortAsc = true; }
              })),
            const SizedBox(width: 8),
            SearchToggleBtn(
              isOpen: _facSearchOpen,
              hasQuery: _facSearch.isNotEmpty,
              onTap: () {
                setState(() {
                  _facSearchOpen = !_facSearchOpen;
                  if (!_facSearchOpen) {
                    _facSearch = '';
                    _facSearchCtrl.clear();
                  }
                });
                if (_facSearchOpen) _facSearchFocus.requestFocus();
              }),
          ]))),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: _facSearchOpen ? 46 : 0,
          color: AppColors.dark,
          clipBehavior: Clip.hardEdge,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
            child: AetherraTextField(
              controller: _facSearchCtrl,
              focusNode: _facSearchFocus,
              hintText: 'Search factions…',
              hintStyle: TextStyle(color: grey.withValues(alpha: 0.6)),
              prefixIcon: const Icon(Icons.search, color: grey, size: 18),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              onChanged: (v) => setState(() => _facSearch = v)))),
        filtered.isEmpty
          ? Expanded(child: Center(child: Text('No factions.',
              style: GoogleFonts.cinzel(color: grey.withValues(alpha: 0.5), fontSize: 14))))
          : Expanded(child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 68),
              itemCount: filtered.length,
              itemBuilder: (_, i) => _facRow(filtered[i]))),
      ])),
      Positioned(bottom: 14, left: 0, right: 0,
        child: _CreateBtn(icon: Icons.add, label: 'New Faction',
          onTap: _openFactionForm)),
    ]);
  }

  Widget _facRow(Map<String, dynamic> f) {
    final fid       = f['id'] as String;
    final bgColor   = AppColors.parseHex(f['color'] as String? ?? _kBgPresets.first);
    final unitCount = GameDataService.units.where((u) => u['faction_id'] == fid).length;
    return _DevFacRowCard(
      f: f, bgColor: bgColor, unitCount: unitCount,
      creatorName: _creatorName,
      onEdit: () => _openFactionForm(existing: f));
  }

  // ═══════════════════════════════════════════════════
  // ABILITIES TAB — all editable
  // ═══════════════════════════════════════════════════
  Widget _abilitiesTab() {
    final all = _allAbilities.where((a) {
      if (_abSearch.isNotEmpty &&
        !(a['name'] as String).toLowerCase()
          .contains(_abSearch.toLowerCase())) {
        return false;
      }
      if (_abTypeF.isNotEmpty) {
        final types = a['types'] as List;
        if (types.isNotEmpty && !types.any((t) => _abTypeF.contains(t as String))) {
          return false;
        }
      }
      return true;
    }).toList();

    return Stack(children: [
      Positioned.fill(child: Column(children: [
        SizedBox(height: 44, child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            FilterBtn(
              allLabel: 'All Types',
              options: const [
                MapEntry('Infantry','Infantry'), MapEntry('Cavalry','Cavalry'),
                MapEntry('Shooting','Shooting'), MapEntry('Artillery','Artillery'),
                MapEntry('Hero','Hero'), MapEntry('Monster','Monster'),
              ],
              selected: _abTypeF,
              onChanged: (s) => setState(() { _abTypeF.clear(); _abTypeF.addAll(s); })),
            const Spacer(),
            SearchToggleBtn(
              isOpen: _abSearchOpen,
              hasQuery: _abSearch.isNotEmpty,
              onTap: () {
                setState(() {
                  _abSearchOpen = !_abSearchOpen;
                  if (!_abSearchOpen) {
                    _abSearch = '';
                    _abSearchCtrl.clear();
                  }
                });
                if (_abSearchOpen) _abSearchFocus.requestFocus();
              }),
          ]))),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: _abSearchOpen ? 46 : 0,
          color: AppColors.dark,
          clipBehavior: Clip.hardEdge,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
            child: AetherraTextField(
              controller: _abSearchCtrl,
              focusNode: _abSearchFocus,
              hintText: 'Search abilities…',
              prefixIcon: const Icon(Icons.search, color: grey, size: 18),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              onChanged: (v) => setState(() => _abSearch = v)))),
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(12,0,12,68),
          itemCount: all.length,
          itemBuilder: (_, i) => _abilityRow(all[i]))),
      ])),
      Positioned(bottom: 14, left: 0, right: 0,
        child: _CreateBtn(icon: Icons.add, label: 'New Ability',
          onTap: () => _openAbilityForm(null))),
    ]);
  }

  Widget _abilityRow(Map<String, dynamic> a) {
    final isBuiltin = a['_builtin'] as bool? ?? false;
    final name = a['name'] as String;
    final nameIsBuiltin = isBuiltin ||
        builtinAbilities.any((b) => b.name == name);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AbilityCard(
        abilityData: a,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          _UnitActionBtn(
            icon: Icons.copy_outlined,
            color: grey.withValues(alpha: 0.55),
            onTap: () => _openAbilityForm(a, isDuplicate: true)),
          _UnitActionBtn(
            icon: Icons.edit_outlined,
            color: gold.withValues(alpha: 0.75),
            onTap: () => _openAbilityForm(a)),
          _UnitActionBtn(
            icon: Icons.delete_outline,
            color: Colors.red.shade300.withValues(alpha: 0.8),
            onTap: () => _deleteAbility(name, wasBuiltin: nameIsBuiltin)),
        ])));
  }

  // ═══════════════════════════════════════════════════
  // BALANCE TAB
  // ═══════════════════════════════════════════════════
  Widget _balanceTab() {
    final divCtrl = TextEditingController(
      text: CostConfig.formulaDivisor.toString());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Formula editor
        Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.dark,
            border: Border.all(color: gold.withValues(alpha: 0.4))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('COST FORMULA',
              style: GoogleFonts.cinzel(color: gold, fontSize: 15, letterSpacing: 2)),
            const SizedBox(height: 10),
            Container(padding: const EdgeInsets.all(10),
              color: AppColors.dark,
              child: const Text(
                'Total Cost  =  (ATK + DEF + SHO + MOB + CP + Abilities)  ×  CON_Multiplier  ÷  X\n\nThen rounded to the nearest 5.',
                style: TextStyle(color: grey, fontSize: 16, height: 1.6))),
            const SizedBox(height: 12),
            Row(children: [
              Text('Divisor  X  =  ',
                style: GoogleFonts.cinzel(color: AppColors.goldLight, fontSize: 17)),
              SizedBox(width: 90, child: AetherraTextField(
                controller: divCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                style: GoogleFonts.cinzel(color: gold, fontSize: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8))),
            ]),
            const SizedBox(height: 10),
            Text('Current: ${CostConfig.formulaDivisor}  →  Example: sum=200, CON×1.3 → ${((200 * 1.3) / CostConfig.formulaDivisor / 5).round() * 5} pts',
              style: const TextStyle(color: grey, fontSize: 15)),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final v = double.tryParse(divCtrl.text);
                  if (v == null || v <= 0) {
                    _toast('Enter a valid positive number.'); return;
                  }
                  CostConfig.formulaDivisor = v;
                  await GameDataService.saveConfig();
                  setState(() {});
                  _toast('Formula saved! Divisor = $v');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: gold.withValues(alpha: 0.15),
                  foregroundColor: gold, side: const BorderSide(color: gold),
                  shape: const RoundedRectangleBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 12)),
                child: Text('Save Formula',
                  style: GoogleFonts.cinzel(fontSize: 15, letterSpacing: 2)))),
          ])),
        const SizedBox(height: 16),

        // Attribute tables
        _balTable('ATK — Attack (0–10)',          CostConfig.atk),
        _balTable('DEF — Defense (0–10)',          CostConfig.def),
        _balTable('SHO — Shooting (0–10)',           CostConfig.rng),
        _balTable('MOB Infantry (0–8)',            CostConfig.mobI),
        _balTable('MOB Cavalry (0–20)',            CostConfig.mobC),
        _balTable('CON Multiplier (0–10)',         CostConfig.con),
        _balTable('CP — Command Points (0–10)',    CostConfig.cp),

        const SizedBox(height: 16),

        // Recalculate button
        SizedBox(width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _recalcAll,
            icon: const Icon(Icons.calculate_outlined, color: AppColors.dark),
            label: Text('Recalculate All Units & Apply Formula',
              style: GoogleFonts.cinzel(color: AppColors.dark, fontSize: 15, letterSpacing: 1.2)),
            style: ElevatedButton.styleFrom(backgroundColor: gold,
              shape: const RoundedRectangleBorder(),
              padding: const EdgeInsets.symmetric(vertical: 14)))),
        const SizedBox(height: 8),

        const Text(
          'This recalculates costs for ALL units using the current formula and attribute tables. '
          'Existing armies are updated automatically the next time they are loaded.',
          style: TextStyle(color: grey, fontSize: 15, height: 1.5)),
        const SizedBox(height: 12),

        SizedBox(width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              if (!await _confirm('Reset ALL balance settings to original defaults?')) return;
              CostConfig.resetToDefaults();
              await GameDataService.saveConfig();
              await _load();
              setState(() {});
              _toast('Reset to defaults! All users updated.');
            },
            icon: Icon(Icons.restore,
              color: Colors.red.withValues(alpha: 0.6), size: 16),
            label: Text('Reset All to Defaults',
              style: GoogleFonts.cinzel(
                color: Colors.red.withValues(alpha: 0.6), fontSize: 14)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.red.withValues(alpha: 0.3)),
              shape: const RoundedRectangleBorder()))),
      ]));
  }

  Widget _balTable(String label, List<double> values) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.cinzel(color: grey, fontSize: 13, letterSpacing: 2)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6,
        children: List.generate(values.length, (i) {
          final ctrl = TextEditingController(
            text: values[i] % 1 == 0
              ? values[i].toInt().toString()
              : values[i].toStringAsFixed(3));
          return SizedBox(width: 68,
            child: Column(children: [
              Text('$i', style: GoogleFonts.cinzel(color: grey, fontSize: 12)),
              const SizedBox(height: 2),
              AetherraTextField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                style: GoogleFonts.cinzel(color: AppColors.goldLight, fontSize: 15),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                onChanged: (v) {
                  final d = double.tryParse(v);
                  if (d != null) { values[i] = d; GameDataService.saveConfig(); }
                }),
            ]));
        })),
      const SizedBox(height: 14),
    ]);
  }

  Future<void> _recalcAll() async {
    if (!await _confirm(
      'Recalculate ALL unit costs using current formula and attribute tables?\n\n'
      'This updates all units. Armies automatically use updated costs on next load.')) {
      return;
    }
    int updated = 0;
    // Update DB units
    for (final u in _dbUnits) {
      final newCost = CostConfig.calcCost(
        a: u['atk'] as int, d: u['def_val'] as int, s: u['rng'] as int,
        m: u['mob'] as int, str: u['con_val'] as int, type: u['type'] as String,
        cpVal: u['cp'] as int,
        abilities: List<String>.from(u['abilities'] ?? []),
        allAbilityCosts: _allAbCosts);
      if (newCost != u['cost']) {
        await sb.from('custom_units').update({'cost': newCost}).eq('id', u['id']);
        updated++;
      }
    }
    // Builtin units that have been overridden in DB are already in _dbUnits
    // No local overrides to handle anymore
    await _load();
    _toast('Updated $updated unit${updated != 1 ? 's' : ''}!');
  }

  // ═══════════════════════════════════════════════════
  // UNIT FORM
  // ═══════════════════════════════════════════════════
  Future<void> _openUnitForm(Map<String, dynamic>? existing, {bool isDuplicate = false}) async {
    final isNew = existing == null || isDuplicate;
    final nameCtrl = TextEditingController(
      text: isDuplicate ? 'Copy of ${existing!['name']}' : existing?['name'] ?? '');
    final atkCtrl  = TextEditingController(text: '${existing?['atk'] ?? 4}');
    final defCtrl  = TextEditingController(text: '${existing?['def_val'] ?? 4}');
    final rngCtrl  = TextEditingController(text: '${existing?['rng'] ?? 0}');
    final mobCtrl  = TextEditingController(text: '${existing?['mob'] ?? 6}');
    final conCtrl  = TextEditingController(text: '${existing?['con_val'] ?? 3}');
    final cpCtrl   = TextEditingController(text: '${existing?['cp'] ?? 0}');
    final loreCtrl = TextEditingController(text: existing?['lore'] as String? ?? '');
    String  selFac   = existing?['faction_id'] ?? _allFacs.first['id'] as String;
    String  selType  = (existing?['type'] ?? 'Infantry') == 'Ranged' ? 'Shooting' : (existing?['type'] ?? 'Infantry');
    bool    isUniq   = existing?['unique_unit'] ?? false;
    final   selAbs   = List<String>.from(existing?['abilities'] ?? []);
    String? imageB64          = existing?['image_b64'] as String?;
    String  selBgColor        = existing?['bg_color']  as String? ?? _kBgPresets.first;
    bool    removingBg        = false;

    int calcCost() => CostConfig.calcCost(
      a: int.tryParse(atkCtrl.text) ?? 0,
      d: int.tryParse(defCtrl.text) ?? 0,
      s: int.tryParse(rngCtrl.text) ?? 0,
      m: int.tryParse(mobCtrl.text) ?? 6,
      str: int.tryParse(conCtrl.text) ?? 1,
      type: selType, cpVal: int.tryParse(cpCtrl.text) ?? 0,
      abilities: selAbs, allAbilityCosts: _allAbCosts);

    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: AppColors.dark,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) {
        final cost     = calcCost();
        final typeAbs  = _allAbilities
          .where((a) {
            final types = a['types'] as List;
            return types.isEmpty || types.contains(selType);
          })
          .map((a) => a['name'] as String)
          .toList();

        return DraggableScrollableSheet(
          expand: false, initialChildSize: 0.93,
          builder: (_, scroll) => SingleChildScrollView(
            controller: scroll,
            padding: EdgeInsets.fromLTRB(16,16,16,
              MediaQuery.of(context).viewInsets.bottom + 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Text(isNew
                  ? (isDuplicate ? 'Copy: ${existing?['name'] ?? ''}' : 'New Unit')
                  : 'Edit: ${existing['name']}',
                style: GoogleFonts.cinzel(color: gold, fontSize: 17, letterSpacing: 1.2)),
              const SizedBox(height: 14),
              _lbl('Unit Name'),
              _tf(nameCtrl, 'e.g. Elite Guards', onChanged: (_) => setS((){})),
              const SizedBox(height: 14),

              // ── Photo ───────────────────────────────────
              Center(child: Container(width: 120, height: 210,
                foregroundDecoration: BoxDecoration(
                  border: Border.all(color: gold.withValues(alpha: 0.35))),
                color: AppColors.parseHex(selBgColor),
                child: Stack(children: [
                  Positioned.fill(child: imageB64 != null
                    ? CachedBase64Image(base64: imageB64!, width: 120, height: 210)
                    : const Center(child: Icon(
                        Icons.add_photo_alternate_outlined,
                        color: gold, size: 44,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 8)]))),
                  if (removingBg)
                    Positioned.fill(child: Container(
                      color: AppColors.dark.withValues(alpha: 0.75),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(color: gold),
                          const SizedBox(height: 12),
                          Text('Removing…',
                            style: GoogleFonts.cinzel(color: gold, fontSize: 11)),
                        ]))),
                ]))),
              const SizedBox(height: 8),
              Row(children: [
                _DevFacOverlay(icon: Icons.add_photo_alternate_outlined,
                  onTap: () async {
                    final r = await pickAndCropPhoto(ctx);
                    if (r != null) setS(() => imageB64 = r);
                  }),
                if (imageB64 != null) ...[
                  const SizedBox(width: 4),
                  _DevFacOverlay(icon: Icons.crop,
                    onTap: () async {
                      final r = await editCropPhoto(ctx, imageB64!);
                      if (r != null) setS(() => imageB64 = r);
                    }),
                  const SizedBox(width: 4),
                  _DevFacOverlay(icon: Icons.delete_outline, color: Colors.red,
                    onTap: () => setS(() => imageB64 = null)),
                ],
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(
                  onPressed: (removingBg || imageB64 == null) ? null : () async {
                    setS(() => removingBg = true);
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
                            newB64 = base64Encode(utf8.encode(jsonEncode({
                              ...info, 'src': base64Encode(result),
                            })));
                          } else {
                            newB64 = base64Encode(result);
                          }
                        } catch (_) { newB64 = base64Encode(result); }
                        setS(() { imageB64 = newB64; removingBg = false; });
                      } else {
                        setS(() => removingBg = false);
                        if (ctx.mounted) _toast('Background removal failed.');
                      }
                    } catch (_) {
                      setS(() => removingBg = false);
                      if (ctx.mounted) _toast('Background removal failed.');
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
                    final picked = await showDialog<String>(
                      context: ctx,
                      builder: (dCtx) => Dialog(
                        backgroundColor: AppColors.dark,
                        shape: const RoundedRectangleBorder(),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Wrap(
                            spacing: 8, runSpacing: 8,
                            children: _kBgPresets.map((hex) {
                              final isSel = selBgColor.toLowerCase() == hex.toLowerCase();
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
                    if (picked != null) setS(() => selBgColor = picked);
                  },
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.parseHex(selBgColor),
                      border: Border.all(color: gold, width: 2)))),
              ]),
              const SizedBox(height: 6),
              Text('Tip: Upload a transparent PNG for better results.',
                style: GoogleFonts.cinzel(color: grey.withValues(alpha: 0.85),
                  fontSize: 10, fontStyle: FontStyle.italic)),
              const SizedBox(height: 8),
              Text('Lore (optional)',
                style: GoogleFonts.cinzel(color: grey, fontSize: 12)),
              const SizedBox(height: 6),
              AetherraTextField(
                controller: loreCtrl,
                hintText: 'Lore: origin, history, tactics...',
                minLines: 3, maxLines: null,
                style: GoogleFonts.cinzel(color: AppColors.grey, fontSize: 12, height: 1.5)),
              const SizedBox(height: 14),

              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _lbl('Faction'),
                  _dd<String>(value: selFac,
                    items: _allFacs.map((f) => DropdownMenuItem(
                      value: f['id'] as String,
                      child: Text(f['name'] as String,
                        style: const TextStyle(color: AppColors.textLight)))).toList(),
                    onChanged: (v) => setS(() => selFac = v!)),
                ])),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _lbl('Type'),
                  _dd<String>(value: selType,
                    items: ['Infantry','Cavalry','Shooting','Artillery','Hero','Monster','Flyer']
                      .map((t) => DropdownMenuItem(value: t,
                        child: Text(t, style: const TextStyle(color: AppColors.textLight)))).toList(),
                    onChanged: (v) => setS(() {
                      selType = v!;
                      selAbs.removeWhere((n) {
                        final ab = builtinAbilities.where((x) => x.name == n).firstOrNull;
                        return ab != null && ab.types.isNotEmpty && !ab.types.contains(selType);
                      });
                    })),
                ])),
              ]),
              const SizedBox(height: 10),
              _lbl('Stats'),
              Row(children: [
                _stI('ATK', atkCtrl, setS), const SizedBox(width: 4),
                _stI('DEF', defCtrl, setS), const SizedBox(width: 4),
                _stI('SHO', rngCtrl, setS), const SizedBox(width: 4),
                _stI('MOB', mobCtrl, setS,
                  max: selType == 'Cavalry' || selType == 'Hero' || selType == 'Monster' || selType == 'Flyer' ? 20 : 8),
                const SizedBox(width: 4),
                _stI('STR', conCtrl, setS),
                const SizedBox(width: 4),
                _stI('AP', cpCtrl, setS),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _lbl('Unique'),
                const SizedBox(width: 8),
                Switch(value: isUniq, onChanged: (v) => setS(() => isUniq = v),
                  activeThumbColor: gold),
                Text(isUniq ? 'Yes' : 'No', style: const TextStyle(color: grey, fontSize: 15)),
              ]),
              const SizedBox(height: 10),
              _lbl('Abilities (tap to select)'),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6,
                children: typeAbs.map((n) {
                  final on  = selAbs.contains(n);
                  final ab  = _allAbilities.where((a) => a['name'] == n).firstOrNull;
                  final abCost   = ab != null ? (ab['cost']    as int? ?? 0) : (_allAbCosts[n] ?? 0);
                  final abCpCost = ab != null ? (ab['cp_cost'] as int? ?? 0) : 0;
                  final Color c  = abCost < 0
                      ? const Color(0xFFCF6679)
                      : abCpCost > 0 ? gold : grey;
                  return GestureDetector(
                    onTap: () => setS(() {
                      if (on) { selAbs.remove(n); } else { selAbs.add(n); }
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: on ? c.withValues(alpha: 0.15) : AppColors.dark,
                        border: Border.all(color: on ? c : c.withValues(alpha: 0.35))),
                      child: Text(n, style: GoogleFonts.cinzel(
                        fontSize: 13, color: on ? c : c.withValues(alpha: 0.6)))));
                }).toList()),
              const SizedBox(height: 14),
              RosterCard(
                unitData: {
                  'name':      nameCtrl.text.trim().isEmpty ? '—' : nameCtrl.text.trim(),
                  'type':      selType,
                  'atk':       int.tryParse(atkCtrl.text) ?? 0,
                  'def_val':   int.tryParse(defCtrl.text) ?? 0,
                  'rng':       int.tryParse(rngCtrl.text) ?? 0,
                  'mob':       int.tryParse(mobCtrl.text) ?? 0,
                  'con_val':   int.tryParse(conCtrl.text) ?? 0,
                  'cp':        int.tryParse(cpCtrl.text) ?? 0,
                  'cost':      cost,
                  'abilities': selAbs,
                  'image_b64': imageB64,
                  'bg_color':  selBgColor,
                  'lore':      loreCtrl.text.trim().isNotEmpty ? loreCtrl.text.trim() : null,
                }),
              const SizedBox(height: 2),
              Text('Formula: (sum × conMult) ÷ ${CostConfig.formulaDivisor}',
                style: TextStyle(color: grey.withValues(alpha: 0.45), fontSize: 11)),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) { _toast('Enter a name.'); return; }
                    final payload = {
                      'name': name, 'faction_id': selFac, 'type': selType,
                      'atk': int.tryParse(atkCtrl.text) ?? 0,
                      'def_val': int.tryParse(defCtrl.text) ?? 0,
                      'rng': int.tryParse(rngCtrl.text) ?? 0,
                      'mob': int.tryParse(mobCtrl.text) ?? 6,
                      'con_val': int.tryParse(conCtrl.text) ?? 3,
                      'cp': int.tryParse(cpCtrl.text) ?? 0,
                      'cost': calcCost(),
                      'abilities': selAbs,
                      'unique_unit': isUniq,
                      'image_b64':  imageB64,
                      'bg_color':   selBgColor,
                      'lore':       loreCtrl.text.trim().isNotEmpty ? loreCtrl.text.trim() : null,
                    };
                    Future<void> doSave(Map<String, dynamic> p) async {
                      if (existing != null && !isDuplicate) {
                        await sb.from('custom_units').upsert({
                          ...p, 'id': existing['id'] as String,
                        });
                      } else {
                        await sb.from('custom_units').insert({
                          ...p, 'id': 'cu_${DateTime.now().millisecondsSinceEpoch}',
                        });
                      }
                    }
                    try {
                      await doSave(payload);
                    } catch (_) {
                      try {
                        final fallback = Map<String, dynamic>.from(payload)
                          ..remove('lore');
                        await doSave(fallback);
                      } catch (_) {
                        final fallback = Map<String, dynamic>.from(payload)
                          ..remove('image_b64')
                          ..remove('lore');
                        await doSave(fallback);
                      }
                    }
                    await GameDataService.load();
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    _load();
                    _toast(existing != null && !isDuplicate ? '"$name" updated!' : '"$name" created!');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: gold.withValues(alpha: 0.15),
                    foregroundColor: gold, side: const BorderSide(color: gold),
                    shape: const RoundedRectangleBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text(existing != null && !isDuplicate ? 'Save Changes' : 'Create Unit',
                    style: GoogleFonts.cinzel(fontSize: 15, letterSpacing: 2)))),

              // ── Delete (edit mode only, not when duplicating) ────
              if (existing != null && !isDuplicate) ...[
                const SizedBox(height: 12),
                SizedBox(width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _deleteUnit(existing);
                    },
                    icon: const Icon(Icons.delete_outline, size: 15,
                      color: Color(0xFFCF6679)),
                    label: Text('Delete Unit',
                      style: GoogleFonts.cinzel(fontSize: 13, letterSpacing: 1)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFCF6679),
                      side: const BorderSide(color: Color(0x66CF6679)),
                      shape: const RoundedRectangleBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 10)))),
              ],
            ])));
      }));
  }

  // ═══════════════════════════════════════════════════
  // FACTION FORM
  // ═══════════════════════════════════════════════════
  Future<void> _openFactionForm({Map<String, dynamic>? existing}) async {
    final isEdit   = existing != null;
    final fid      = existing?['id'] as String?
        ?? 'f_${DateTime.now().millisecondsSinceEpoch}';
    final nameCtrl = TextEditingController(text: existing?['name'] as String? ?? '');
    final loreCtrl = TextEditingController(text: existing?['lore'] as String? ?? '');
    String  selColor   = existing?['color'] as String? ?? _kBgPresets.first;
    String? imageB64   = existing?['image_b64'] as String?;
    bool    removingBg = false;

    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: AppColors.dark,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) =>
        DraggableScrollableSheet(
          expand: false, initialChildSize: 0.92,
          builder: (_, scroll) => SingleChildScrollView(
            controller: scroll,
            padding: EdgeInsets.fromLTRB(16, 16, 16,
              MediaQuery.of(context).viewInsets.bottom + 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Text(isEdit ? 'Edit Faction' : 'New Faction',
                style: GoogleFonts.cinzel(color: gold, fontSize: 17)),
              const SizedBox(height: 16),

              _lbl('Name'),
              _tf(nameCtrl, 'e.g. Elves', onChanged: (_) {}),
              const SizedBox(height: 16),

              // Logo preview
              Stack(children: [
                Container(
                  width: double.infinity, height: 115,
                  color: AppColors.parseHex(selColor),
                  child: imageB64 != null
                    ? Center(child: buildCroppedPhotoDisplay(imageB64!, AppColors.bannerW, AppColors.bannerH))
                    : Center(child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.image_outlined,
                            color: gold.withValues(alpha: 0.25), size: 44),
                          const SizedBox(height: 8),
                          Text('Upload logo', style: GoogleFonts.cinzel(
                            color: grey.withValues(alpha: 0.35), fontSize: 12)),
                        ]))),
                if (imageB64 != null)
                  Positioned(top: 8, left: 8,
                    child: _DevFacOverlay(icon: Icons.close,
                      onTap: () => setS(() => imageB64 = null))),
                if (imageB64 != null)
                  Positioned(top: 8, right: 48,
                    child: _DevFacOverlay(
                      icon: Icons.zoom_in,
                      onTap: () async {
                        final res = await editLogoCropPhoto(context, imageB64!);
                        if (res != null) setS(() => imageB64 = res);
                      })),
                Positioned(top: 8, right: 8,
                  child: _DevFacOverlay(
                    icon: Icons.add_photo_alternate_outlined,
                    onTap: () async {
                      final res = await pickLogoPhotoWithCrop(context);
                      if (res != null) setS(() => imageB64 = res);
                    })),
                if (removingBg)
                  Positioned.fill(child: Container(
                    color: AppColors.dark.withValues(alpha: 0.75),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: gold),
                        const SizedBox(height: 12),
                        Text('Removing background…',
                          style: GoogleFonts.cinzel(color: gold, fontSize: 12)),
                      ]))),
              ]),

              const SizedBox(height: 8),
              Row(children: [
                _DevFacOverlay(icon: Icons.add_photo_alternate_outlined,
                  onTap: () async {
                    final res = await pickLogoPhotoWithCrop(context);
                    if (res != null) setS(() => imageB64 = res);
                  }),
                if (imageB64 != null) ...[
                  const SizedBox(width: 4),
                  _DevFacOverlay(icon: Icons.crop,
                    onTap: () async {
                      final res = await editLogoCropPhoto(context, imageB64!);
                      if (res != null) setS(() => imageB64 = res);
                    }),
                  const SizedBox(width: 4),
                  _DevFacOverlay(icon: Icons.delete_outline, color: Colors.red,
                    onTap: () => setS(() => imageB64 = null)),
                ],
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(
                  onPressed: (removingBg || imageB64 == null) ? null : () async {
                    setS(() => removingBg = true);
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
                            newB64 = base64Encode(utf8.encode(jsonEncode({
                              ...info, 'src': base64Encode(result),
                            })));
                          } else {
                            newB64 = base64Encode(result);
                          }
                        } catch (_) { newB64 = base64Encode(result); }
                        setS(() { imageB64 = newB64; removingBg = false; });
                      } else {
                        setS(() => removingBg = false);
                        if (ctx.mounted) _toast('Background removal failed.');
                      }
                    } catch (_) {
                      setS(() => removingBg = false);
                      if (ctx.mounted) _toast('Background removal failed.');
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
                    final picked = await showDialog<String>(
                      context: ctx,
                      builder: (dCtx) => Dialog(
                        backgroundColor: AppColors.dark,
                        shape: const RoundedRectangleBorder(),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Wrap(
                            spacing: 8, runSpacing: 8,
                            children: _kBgPresets.map((hex) {
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
              Text('Tip: Upload a transparent PNG for better results.',
                style: GoogleFonts.cinzel(color: grey.withValues(alpha: 0.85),
                  fontSize: 10, fontStyle: FontStyle.italic)),
              const SizedBox(height: 10),

              _lbl('Lore (optional)'),
              AetherraTextField(
                controller: loreCtrl,
                minLines: 4, maxLines: null,
                style: const TextStyle(color: AppColors.textLight, fontSize: 14, height: 1.5),
                hintText: 'Lore: origin, history, culture...',
                hintStyle: TextStyle(color: grey.withValues(alpha: 0.5)),
                contentPadding: const EdgeInsets.all(12)),
              const SizedBox(height: 16),

              if (isEdit) ...[
                SizedBox(width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      if (!ctx.mounted) return;
                      // Pre-populate unit_refs with currently-assigned unit names
                      final assignedNames = GameDataService.units
                          .where((u) => u['faction_id'] == fid)
                          .map((u) => u['name'] as String)
                          .toList();
                      await Navigator.push(ctx, MaterialPageRoute(
                        builder: (_) => FactionUnitPickerScreen(
                          faction:     {...existing, 'unit_refs': assignedNames},
                          userUnits:   const [],
                          allFactions: _allFacs,
                          saveCallback: (_, officialRefs) async {
                            for (final u in GameDataService.units) {
                              final name  = u['name'] as String;
                              final wasIn = (u['faction_id'] as String?) == fid;
                              final nowIn = officialRefs.contains(name);
                              if (wasIn != nowIn) {
                                await sb.from('custom_units').upsert({
                                  'id':          u['id'] as String,
                                  'name':        name,
                                  'faction_id':  nowIn ? fid : null,
                                  'type':        u['type'],
                                  'atk':         u['atk'],
                                  'def_val':     u['def_val'],
                                  'rng':         u['rng'],
                                  'mob':         u['mob'],
                                  'con_val':     u['con_val'],
                                  'cp':          u['cp'],
                                  'cost':        u['cost'],
                                  'abilities':   u['abilities'],
                                  'unique_unit': u['unique_unit'],
                                });
                              }
                            }
                            await GameDataService.load();
                          })));
                      _load();
                    },
                    icon: const Icon(Icons.group_outlined, color: gold, size: 15),
                    label: Text('Manage Units',
                      style: GoogleFonts.cinzel(fontSize: 12, letterSpacing: 1)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: gold,
                      side: BorderSide(color: gold.withValues(alpha: 0.5)),
                      shape: const RoundedRectangleBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 12)))),
                const SizedBox(height: 20),
              ],

              // Save
              SizedBox(width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) { _toast('Enter a name.'); return; }
                    final nav     = Navigator.of(context);
                    final loreVal = loreCtrl.text.trim();
                    final base    = <String, dynamic>{'name': name, 'color': selColor};
                    final extra   = <String, dynamic>{
                      'lore':      loreVal.isEmpty ? null : loreVal,
                      'image_b64': imageB64,
                    };
                    bool savedWithImage = true;
                    try {
                      await sb.from('custom_factions')
                        .upsert({...base, ...extra, 'id': fid});
                    } catch (_) {
                      savedWithImage = false;
                      try {
                        await sb.from('custom_factions')
                          .upsert({...base, 'id': fid});
                      } catch (e) {
                        if (mounted) _toast('Could not save: $e');
                        return;
                      }
                    }
                    if (!mounted) return;
                    await GameDataService.load();
                    if (!mounted) return;
                    nav.pop(); _load();
                    if (savedWithImage) {
                      _toast(isEdit ? '"$name" updated!' : '"$name" created!');
                    } else {
                      _toast('Saved without image — run DB migration to enable image/lore columns.');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: gold, foregroundColor: AppColors.dark,
                    side: BorderSide.none,
                    shape: const RoundedRectangleBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text(isEdit ? 'Save Changes' : 'Create Faction',
                    style: GoogleFonts.cinzel(
                    color: AppColors.dark, fontSize: 15, letterSpacing: 2,
                    fontWeight: FontWeight.w700)))),

              // Delete (edit only)
              if (isEdit) ...[
                const SizedBox(height: 12),
                SizedBox(width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final nav  = Navigator.of(context);
                      final name = nameCtrl.text.trim().isNotEmpty
                          ? nameCtrl.text.trim()
                          : existing['name'] as String;
                      if (!await _confirm('Delete faction "$name"?')) return;
                      await sb.from('custom_factions').delete().eq('id', fid);
                      if (!mounted) return;
                      await GameDataService.load();
                      if (!mounted) return;
                      nav.pop(); _load();
                      _toast('"$name" deleted.');
                    },
                    icon: const Icon(Icons.delete_outline, size: 15,
                      color: Color(0xFFCF6679)),
                    label: Text('Delete Faction',
                      style: GoogleFonts.cinzel(fontSize: 13, letterSpacing: 1)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFCF6679),
                      side: const BorderSide(color: Color(0x66CF6679)),
                      shape: const RoundedRectangleBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 10)))),
              ],
            ])))));

  }

  // ═══════════════════════════════════════════════════
  // ABILITY FORM
  // ═══════════════════════════════════════════════════
  Future<void> _openAbilityForm(Map<String, dynamic>? existing, {bool isDuplicate = false}) async {
    final isBuiltin = !isDuplicate && existing != null && (existing['_builtin'] as bool? ?? false);
    final originalName  = existing?['name'] as String? ?? '';
    final nameCtrl      = TextEditingController(
      text: isDuplicate ? 'Copy of ${existing!['name']}' : originalName);
    final descCtrl      = TextEditingController(text: existing?['description'] as String? ?? '');
    final costCtrl      = TextEditingController(text: '${existing?['cost'] ?? 0}');
    int cpCost = (existing?['cp_cost'] as int?) ?? 0;
    // For builtins already overridden in DB, use DB types
    final dbEntry = _dbAbilities
      .where((x) => x['name'] == existing?['name'])
      .firstOrNull;
    final selTypes = List<String>.from(
      (dbEntry != null && dbEntry['types'] != null &&
       (dbEntry['types'] as List).isNotEmpty)
        ? dbEntry['types'] as List
        : existing?['types'] ?? []);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.dark,
      builder: (_) => StatefulBuilder(
        builder: (ctx2, setS2) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16,
            MediaQuery.of(context).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  existing == null ? 'New Ability'
                  : isDuplicate ? 'Copy: ${existing['name']}'
                  : 'Edit: ${existing['name']}',
                  style: GoogleFonts.cinzel(color: gold, fontSize: 17)),
                const SizedBox(height: 14),
                _lbl('Name'),
                _tf(nameCtrl, 'Ability name', onChanged: (_) {}),
                const SizedBox(height: 10),
                _lbl('Description'),
                AetherraTextField(
                  controller: descCtrl,
                  maxLines: 3,
                  hintText: 'Describe the effect…',
                  contentPadding: const EdgeInsets.all(10)),
                const SizedBox(height: 10),
                _lbl('Point Cost (negative = disadvantage)'),
                _tf(costCtrl, '0',
                  type: const TextInputType.numberWithOptions(signed: true),
                  onChanged: (_) => setS2(() {})),
                const SizedBox(height: 4),
                Builder(builder: (_) {
                  final v = int.tryParse(costCtrl.text) ?? 0;
                  final label = v > 0 ? '+$v pts (advantage)' 
                    : v < 0 ? '$v pts (disadvantage)' : '0 pts (neutral)';
                  final col = v > 0 ? gold : v < 0
                    ? Colors.orange : grey;
                  return Text(label,
                    style: GoogleFonts.cinzel(color: col, fontSize: 14));
                }),
                const SizedBox(height: 10),
                _lbl('Unit Types (leave empty = all types)'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: ['Infantry','Cavalry','Shooting','Artillery','Hero','Monster','Flyer']
                    .map((t) {
                      final on = selTypes.contains(t);
                      final tc = typeColor(t);
                      return GestureDetector(
                        onTap: () => setS2(() {
                          if (on) { selTypes.remove(t); } else { selTypes.add(t); }
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: on ? tc.withValues(alpha: 0.18) : AppColors.dark,
                            border: Border.all(color: on ? tc : tc.withValues(alpha: 0.35))),
                          child: Text(t,
                            style: GoogleFonts.cinzel(
                              fontSize: 13,
                              color: on ? tc : tc.withValues(alpha: 0.6)))));
                    }).toList()),

                const SizedBox(height: 10),
                _lbl('Command Point Cost (0 = no CP cost)'),
                const SizedBox(height: 6),
                SizedBox(
                  height: 36,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: 11,
                    itemBuilder: (_, i) {
                      final on = cpCost == i;
                      return GestureDetector(
                        onTap: () => setS2(() => cpCost = i),
                        child: Container(
                          width: 36, height: 36,
                          margin: const EdgeInsets.only(right: 4),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: on
                              ? gold.withValues(alpha: 0.22)
                              : AppColors.dark,
                            border: Border.all(
                              color: on
                                ? gold
                                : gold.withValues(alpha: 0.22))),
                          child: Text('$i',
                            style: GoogleFonts.cinzel(
                              color: on
                                ? gold
                                : grey,
                              fontSize: 14,
                              fontWeight: on ? FontWeight.w700 : FontWeight.normal))));
                    })),
                if (cpCost > 0) ...[
                  const SizedBox(height: 6),
                  Text('Command Ability — costs $cpCost CP to use',
                    style: GoogleFonts.cinzel(
                      color: gold, fontSize: 12)),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final name = nameCtrl.text.trim();
                      final desc = descCtrl.text.trim();
                      final cost      = int.tryParse(costCtrl.text) ?? 0;
                      if (name.isEmpty) { _toast('Enter a name.'); return; }
                      final nav = Navigator.of(context);
                      final sm  = ScaffoldMessenger.of(context);
                      try {
                        final payload = {
                          'name': name,
                          'description': desc.isNotEmpty ? desc : null,
                          'cost': cost,
                          'cp_cost': cpCost,
                          'types': selTypes,
                        };
                        if (existing != null && !isDuplicate) {
                          if (name != originalName) {
                            // Rename: delete old entry
                            await sb.from('custom_abilities').delete().eq('name', originalName);
                            // If old name was a builtin, mark it as deleted so it doesn't reappear
                            if (builtinAbilities.any((b) => b.name == originalName)) {
                              await GameDataService.addDeletedBuiltinAbilityName(originalName);
                            }
                            // Update all units that referenced the old ability name
                            final units = await sb.from('custom_units').select('id, abilities');
                            for (final u in List<Map<String, dynamic>>.from(units)) {
                              final abs = List<String>.from(u['abilities'] ?? []);
                              if (abs.contains(originalName)) {
                                await sb.from('custom_units')
                                  .update({'abilities': abs.map((a) => a == originalName ? name : a).toList()})
                                  .eq('id', u['id'] as String);
                              }
                            }
                          }
                        }
                        // Delete existing entry (no-op if not present), then insert fresh
                        await sb.from('custom_abilities').delete().eq('name', name);
                        await sb.from('custom_abilities').insert(payload);
                        await GameDataService.load();
                        if (!mounted) return;
                        nav.pop();
                        _load();
                        sm.showSnackBar(_snackBar('"$name" saved!'));
                        // Recalculate all units that use this ability
                        _recalcAffectedUnits(name).catchError((_) {});
                      } catch (e) {
                        _toast('Save failed: ${e.toString().split('\n').first}');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: gold.withValues(alpha: 0.15),
                      foregroundColor: gold,
                      side: const BorderSide(color: gold),
                      shape: const RoundedRectangleBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: Text(
                      isBuiltin ? 'Save Override'
                        : existing != null && !isDuplicate ? 'Save Changes' : 'Create Ability',
                      style: GoogleFonts.cinzel(
                        fontSize: 15, letterSpacing: 2)))),
                if (existing != null && !isDuplicate) ...[
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx2);
                        final n = existing['name'] as String;
                        final nameIsBuiltin = builtinAbilities.any((b) => b.name == n);
                        await _deleteAbility(n, wasBuiltin: nameIsBuiltin);
                      },
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: Text('Delete Ability',
                        style: GoogleFonts.cinzel(fontSize: 14, letterSpacing: 1)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade300,
                        side: BorderSide(color: Colors.red.shade300.withValues(alpha: 0.5)),
                        shape: const RoundedRectangleBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 12)))),
                ],
              ])))));
  }
  /// Called after ability cost changes — recalculates all units that use this ability
  Future<void> _recalcAffectedUnits(String abilityName) async {
    // Reload GameDataService first so ability costs are current
    await GameDataService.load();

    // ALL units (builtin + custom) that use this ability
    final allUnits = GameDataService.units;
    final affected = allUnits.where((u) {
      final abs = List<String>.from(u['abilities'] ?? []);
      return abs.contains(abilityName);
    }).toList();

    if (affected.isEmpty) return;

    for (final u in affected) {
      final newCost = CostConfig.calcCost(
        a: u['atk'] as int,
        d: u['def_val'] as int,
        s: u['rng'] as int,
        m: u['mob'] as int,
        str: u['con_val'] as int,
        type: u['type'] as String,
        cpVal: u['cp'] as int,
        abilities: List<String>.from(u['abilities'] ?? []),
        allAbilityCosts: GameDataService.abilityCosts);
      // Upsert so both builtin overrides and custom units get updated
      await sb.from('custom_units').upsert({
        'id':          u['id'],
        'name':        u['name'],
        'faction_id':  u['faction_id'],
        'type':        u['type'],
        'atk':         u['atk'],
        'def_val':     u['def_val'],
        'rng':         u['rng'],
        'mob':         u['mob'],
        'con_val':     u['con_val'],
        'cp':          u['cp'],
        'abilities':   u['abilities'],
        'unique_unit': u['unique_unit'],
        'cost':        newCost,
      });
    }

    // Reload after upserts so GameDataService has fresh data
    await GameDataService.load();

    // Recalculate total_points for all army_lists
    try {
      final armies = await sb.from('army_lists').select('id, army_data, total_points');
      for (final army in armies) {
        final data  = army['army_data'] as Map<String, dynamic>? ?? {};
        final units = List<dynamic>.from(data['units'] ?? []);
        int total   = 0;
        for (final u in units) {
          final uid = u['unitId'] as String? ?? '';
          final gu  = GameDataService.toGameUnit(uid);
          if (gu != null) total += gu.cost;
        }
        if (total != (army['total_points'] as int? ?? 0)) {
          await sb.from('army_lists')
            .update({'total_points': total}).eq('id', army['id']);
        }
      }
    } catch (_) {}
  }

    Future<void> _deleteAbility(String name, {bool wasBuiltin = false}) async {
    if (!await _confirm('Delete "$name"?')) return;
    await sb.from('custom_abilities').delete().eq('name', name);
    if (wasBuiltin) {
      await GameDataService.addDeletedBuiltinAbilityName(name);
    }
    // Remove ability from all units that reference it
    final units = await sb.from('custom_units').select('id, abilities');
    for (final u in List<Map<String, dynamic>>.from(units)) {
      final abs = List<String>.from(u['abilities'] ?? []);
      if (abs.contains(name)) {
        await sb.from('custom_units')
            .update({'abilities': abs..remove(name)})
            .eq('id', u['id'] as String);
      }
    }
    _load();
  }

  // ═══════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════

  Widget _lbl(String t) => Padding(padding: const EdgeInsets.only(bottom: 4),
    child: Text(t, style: GoogleFonts.cinzel(
      color: grey, fontSize: 13, letterSpacing: 1.5)));

  Widget _tf(TextEditingController ctrl, String hint, {
    bool readOnly = false,
    TextInputType type = TextInputType.text,
    required void Function(String) onChanged,
  }) => AetherraTextField(controller: ctrl, readOnly: readOnly,
    keyboardType: type, onChanged: onChanged,
    hintText: hint);

  Widget _dd<T>({required T value, required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged}) =>
    DropdownButtonFormField<T>(initialValue: value, items: items, onChanged: onChanged,
      isExpanded: true,
      dropdownColor: AppColors.dark,
      style: const TextStyle(color: AppColors.textLight, fontSize: 17),
      decoration: InputDecoration(filled: true, fillColor: AppColors.dark,
        border: OutlineInputBorder(borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: gold.withValues(alpha: 0.2))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: gold.withValues(alpha: 0.2))),
        focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: gold)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10)));

  Widget _stI(String label, TextEditingController ctrl,
      StateSetter setS, {int max = 10}) =>
    Expanded(child: Column(children: [
      Text(label, style: GoogleFonts.cinzel(color: grey, fontSize: 7)),
      const SizedBox(height: 2),
      AetherraTextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        onChanged: (_) => setS(() {}),
        style: GoogleFonts.cinzel(color: AppColors.goldLight, fontSize: 17),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 7)),
    ]));

  Future<bool> _confirm(String msg) async {
    final ok = await showDialog<bool>(context: context,
      builder: (_) => AlertDialog(backgroundColor: AppColors.dark,
        title: Text(msg,
          style: GoogleFonts.cinzel(color: gold, fontSize: 16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.cinzel(color: grey))),
          TextButton(onPressed: () => Navigator.pop(context, true),
            child: Text('Save', style: GoogleFonts.cinzel(color: gold))),
        ]));
    return ok ?? false;
  }

  SnackBar _snackBar(String msg) => SnackBar(
    backgroundColor: AppColors.dark,
    content: Text(msg, style: GoogleFonts.cinzel(color: gold)),
    duration: const Duration(seconds: 2));

  void _toast(String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(_snackBar(msg));
}

// ── Faction card (mirrors _FacRowCard from my_factions_screen) ───────────────
class _DevFacRowCard extends StatefulWidget {
  final Map<String, dynamic> f;
  final Color bgColor;
  final int unitCount;
  final String creatorName;
  final VoidCallback onEdit;
  const _DevFacRowCard({required this.f, required this.bgColor,
    required this.unitCount, required this.creatorName, required this.onEdit});
  @override State<_DevFacRowCard> createState() => _DevFacRowCardState();
}
class _DevFacRowCardState extends State<_DevFacRowCard> {
  bool _loreExpanded  = false;
  bool _loreHovered = false;
  bool _hovered     = false;
  bool _pressed       = false;
  Widget? _cachedImg;
  static final _kIdentity = Matrix4.identity();

  @override void initState() {
    super.initState();
    final b64 = widget.f['image_b64'] as String?;
    if (b64 != null && b64.isNotEmpty) {
      _cachedImg = CachedBase64Image(base64: b64, width: AppColors.bannerW, height: AppColors.bannerH);
    }
  }

  @override void didUpdateWidget(_DevFacRowCard old) {
    super.didUpdateWidget(old);
    final b64    = widget.f['image_b64'] as String?;
    final oldB64 = old.f['image_b64']    as String?;
    if (b64 != oldB64) {
      _cachedImg = (b64 != null && b64.isNotEmpty)
          ? CachedBase64Image(base64: b64, width: AppColors.bannerW, height: AppColors.bannerH) : null;
    }
  }

  @override Widget build(BuildContext context) {
    final lore     = widget.f['lore']       as String?;
    final hasLogo  = _cachedImg != null;
    final hasLore = lore != null && lore.isNotEmpty;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown:   (_) => setState(() => _pressed = true),
        onTapUp:     (_) => setState(() => _pressed = false),
        onTapCancel: ()  => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          transform: _pressed
            ? (Matrix4.identity()..scaleByDouble(0.99, 0.99, 1, 1))
            : _kIdentity,
          transformAlignment: Alignment.center,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: widget.bgColor,
              border: Border.all(
                color: _hovered
                  ? AppColors.gold.withValues(alpha: 0.5)
                  : AppColors.gold.withValues(alpha: 0.2),
                width: 1.5)),
            child: Stack(clipBehavior: Clip.hardEdge, children: [

              if (hasLogo) Positioned(
                top: 0, left: 0, right: 0, height: 115,
                child: ClipRect(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: _loreExpanded ? -70.0 : 0.0),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    builder: (_, dy, child) =>
                      Transform.translate(offset: Offset(0, dy), child: child),
                    child: Center(child: _cachedImg!)))),

              if (!hasLogo) Positioned.fill(
                child: Center(child: Icon(Icons.shield_outlined,
                  color: AppColors.gold.withValues(alpha: 0.15), size: 36))),

              Positioned.fill(
                child: IgnorePointer(
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
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(widget.f['name'] as String,
                                style: GoogleFonts.cinzel(color: Colors.white, fontSize: 16,
                                  shadows: [const Shadow(color: Colors.black54, blurRadius: 6)])),
                              if (widget.creatorName.isNotEmpty)
                                Text('by ${widget.creatorName}',
                                  style: GoogleFonts.cinzel(color: Colors.white54, fontSize: 12,
                                    shadows: [const Shadow(color: Colors.black87, blurRadius: 4)])),
                            ])),
                          RichText(text: TextSpan(children: [
                            TextSpan(text: '${widget.unitCount}',
                              style: GoogleFonts.cinzel(color: AppColors.gold, fontSize: 13,
                                fontWeight: FontWeight.w600,
                                shadows: [const Shadow(color: Colors.black54, blurRadius: 6)])),
                            TextSpan(text: ' unit${widget.unitCount != 1 ? 's' : ''}',
                              style: GoogleFonts.cinzel(color: Colors.white70, fontSize: 11,
                                shadows: [const Shadow(color: Colors.black54, blurRadius: 6)])),
                          ])),
                        ]),
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
                                  color: AppColors.gold, size: 17,
                                  shadows: const [Shadow(color: Colors.black87, blurRadius: 8)])))),
                          const Spacer(),
                          NavBtn(icon: Icons.edit_outlined, onPressed: widget.onEdit),
                        ]),
                      ]))),

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
                            shadows: [const Shadow(color: Colors.black87, blurRadius: 8)])))
                    : const SizedBox.shrink()),

              ]),
            ])))));
  }
}

// ── Overlay button on logo preview ───────────────────────────────────────────
class _DevFacOverlay extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  const _DevFacOverlay({required this.icon, required this.onTap, this.color = AppColors.gold});
  @override State<_DevFacOverlay> createState() => _DevFacOverlayState();
}
class _DevFacOverlayState extends State<_DevFacOverlay> {
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
        child: Icon(widget.icon, color: widget.color, size: 14))));
}

// ── Custom hover-aware tab button ─────────────────────────────────────────────
class _UnitActionBtn extends StatefulWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _UnitActionBtn({required this.icon, required this.color, required this.onTap});
  @override State<_UnitActionBtn> createState() => _UnitActionBtnState();
}
class _UnitActionBtnState extends State<_UnitActionBtn> {
  bool _hovered = false;
  @override Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit:  (_) => setState(() => _hovered = false),
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Icon(widget.icon,
          color: widget.color.withValues(alpha: _hovered ? 1.0 : widget.color.a),
          size: 17))));
}

class _CreateBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _CreateBtn({required this.icon, required this.label, required this.onTap});
  @override State<_CreateBtn> createState() => _CreateBtnState();
}
class _CreateBtnState extends State<_CreateBtn> {
  bool _hovered = false;
  bool _pressed = false;
  @override Widget build(BuildContext context) => Center(
    child: MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown:   (_) => setState(() => _pressed = true),
        onTapUp:     (_) { setState(() => _pressed = false); widget.onTap(); },
        onTapCancel: ()  => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28),
          decoration: BoxDecoration(
            color: _pressed
                ? AppColors.gold.withValues(alpha: 0.75)
                : _hovered
                    ? AppColors.gold.withValues(alpha: 0.88)
                    : AppColors.gold,
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
            ]),
          child: Text(widget.label, style: GoogleFonts.cinzel(
            color: AppColors.dark, fontSize: 13, letterSpacing: 1.1,
            fontWeight: FontWeight.w600))))));
}

class _DevTabBtn extends StatefulWidget {
  final String   label;
  final bool     selected;
  final VoidCallback onTap;
  const _DevTabBtn({required this.label, required this.selected, required this.onTap});
  @override State<_DevTabBtn> createState() => _DevTabBtnState();
}
class _DevTabBtnState extends State<_DevTabBtn> {
  bool _hovered = false;
  @override Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit:  (_) => setState(() => _hovered = false),
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        height: 46,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 100),
              style: GoogleFonts.cinzel(
                fontSize: 14, letterSpacing: 1,
                color: widget.selected
                  ? AppColors.gold
                  : _hovered
                    ? AppColors.gold.withValues(alpha: 0.75)
                    : AppColors.grey),
              child: Text(widget.label)),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              height: 2,
              width: double.infinity,
              color: widget.selected ? AppColors.gold : Colors.transparent),
          ]))));
}

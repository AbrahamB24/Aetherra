import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/game_data.dart';
import '../services/bg_remover.dart';
import '../services/cost_config.dart';
import '../services/game_data_service.dart';
import '../services/subscription_service.dart';
import '../widgets/crud_btns.dart';
import '../widgets/nav_btn.dart';
import '../widgets/photo_crop_dialog.dart';
import '../widgets/filter_widgets.dart';
import '../widgets/unit_card.dart';
import '../widgets/ability_picker_sheet.dart';
import '../widgets/aetherra_dialog.dart';
import '../widgets/aetherra_text_field.dart';
import '../app_theme.dart';
import 'faction_unit_picker_screen.dart';

const _stripePaymentUrl = 'https://buy.stripe.com/fZu7sLeoSg6ae8jfOWb3q00';

// AppColors.dark background presets — all have luminance < 0.10 so gold + white text
// always meet WCAG AA contrast at large-text sizes.
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

class MyFactionsScreen extends StatefulWidget {
  const MyFactionsScreen({super.key});
  @override
  State<MyFactionsScreen> createState() => _MyFactionsScreenState();
}

class _MyFactionsScreenState extends State<MyFactionsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const gold  = AppColors.gold;
        static const grey  = AppColors.grey;
  static final sb    = Supabase.instance.client;

  late TabController _tabs;
  bool _loading = true;

  // User's own content
  List<Map<String, dynamic>> _userFacs      = [];
  List<Map<String, dynamic>> _userUnits     = [];
  List<Map<String, dynamic>> _userAbilities = [];

  // Combined lists for pickers
  List<Map<String, dynamic>> _allFacs    = [];
  List<Map<String, dynamic>> _allAbs     = [];
  Map<String, int>           _allAbCosts = {};


  String _creatorName = '';

  // Filters — units / abilities
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
  final Set<String> _facSourceF = {};
  bool   _facSearchOpen  = false;
  final Set<String> _unitFacF    = {};
  final Set<String> _unitTypeF   = {};
  final Set<String> _unitSourceF = {};
  final Set<String> _abTypeF     = {};
  final Set<String> _abSourceF   = {};
  final Set<String> _abCategoryF = {};
  final _unitSearchCtrl  = TextEditingController();
  final _unitSearchFocus = FocusNode();
  final _abSearchCtrl    = TextEditingController();
  final _abSearchFocus   = FocusNode();
  final _facSearchCtrl   = TextEditingController();
  final _facSearchFocus  = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabs.dispose();
    _unitSearchCtrl.dispose();
    _unitSearchFocus.dispose();
    _abSearchCtrl.dispose();
    _abSearchFocus.dispose();
    _facSearchCtrl.dispose();
    _facSearchFocus.dispose();
    super.dispose();
  }

  // Called when user returns from browser after Stripe payment
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkSubscriptionRefresh();
    }
  }

  Future<void> _checkSubscriptionRefresh() async {
    final wasPremium = SubscriptionService.isPremium;
    await SubscriptionService.load();
    if (!wasPremium && SubscriptionService.isPremium && mounted) {
      // Newly unlocked — load full data and rebuild
      setState(() {});
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Reload shared + user data so everything is fresh
    await GameDataService.load();
    final uid = sb.auth.currentUser?.id;
    if (uid == null) { setState(() => _loading = false); return; }
    final r = await Future.wait([
      sb.from('user_factions').select('*').eq('user_id', uid).order('name'),
      sb.from('user_units').select('*').eq('user_id', uid).order('name'),
      sb.from('user_abilities').select('*').eq('user_id', uid).order('name'),
    ]);
    final userFacs  = List<Map<String, dynamic>>.from(r[0]);
    final userUnits = List<Map<String, dynamic>>.from(r[1]).map((u) => {
      ...u, 'abilities': List<String>.from(u['abilities'] ?? []),
    }).toList();
    final userAbs   = List<Map<String, dynamic>>.from(r[2]).map((a) => ({
      ...a, 'types': List<String>.from(a['types'] ?? []),
    })).toList();

    // All factions for unit assignment: shared factions + user's own
    final sharedFacIds = userFacs.map((f) => f['id'] as String).toSet();
    final sharedFacs = GameDataService.factions
        .where((f) => !sharedFacIds.contains(f['id']))
        .toList();
    final allFacs = [...sharedFacs, ...userFacs];

    // All abilities for unit picker: system + user's own
    final userAbNames = userAbs.map((a) => a['name'] as String).toSet();
    final systemAbs   = GameDataService.abilities
        .where((a) => !userAbNames.contains(a['name']))
        .toList();
    final allAbs = [...systemAbs, ...userAbs];

    final meta = sb.auth.currentUser?.userMetadata ?? {};
    final creatorName = meta['display_name'] as String?
        ?? meta['full_name'] as String?
        ?? meta['name'] as String?
        ?? '';

    setState(() {
      _userFacs      = userFacs;
      _userUnits     = userUnits;
      _userAbilities = userAbs;
      _allFacs       = allFacs;
      _allAbs        = allAbs;
      _allAbCosts    = {for (final a in allAbs)
        a['name'] as String: (a['cost'] as int? ?? 0)};
      _creatorName   = creatorName;
      _loading       = false;
    });
    if (creatorName.isEmpty && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _promptDisplayName());
    }
  }

  Future<void> _promptDisplayName() async {
    final ctrl = TextEditingController();
    await showAetherraSheet(context,
      title: 'Set Display Name',
      isDismissible: false,
      body: AetherraTextField(
        controller: ctrl, autofocus: true,
        hintText: 'Your name…',
        hintStyle: TextStyle(color: grey.withValues(alpha: 0.5))),
      actions: [
        SheetAction('Save', gold, () async {
          final name = ctrl.text.trim();
          if (name.isEmpty) return;
          await sb.auth.updateUser(UserAttributes(data: {'display_name': name}));
          if (mounted) { Navigator.pop(context); _load(); }
        }),
      ]);
  }

  // ═══════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (!SubscriptionService.isPremium) return _paywallView();
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        leading: NavBtn(icon: Icons.home_outlined, onPressed: () => Navigator.pop(context)),
        title: Text('Workshop',
          style: GoogleFonts.cinzel(color: gold, fontSize: 17, letterSpacing: 2)),
        actions: const [],
        bottom: TabBar(
          controller: _tabs,
          indicator: const BoxDecoration(),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          tabs: [
            _HoverTab(text: 'Factions', controller: _tabs, index: 0),
            _HoverTab(text: 'Units',    controller: _tabs, index: 1),
            _HoverTab(text: 'Abilities',controller: _tabs, index: 2),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: gold))
          : TabBarView(controller: _tabs, children: [
              _factionsTab(),
              _unitsTab(),
              _abilitiesTab(),
            ]),
    );
  }

  // ── PAYWALL ─────────────────────────────────────────
  Widget _paywallView() => Scaffold(
    backgroundColor: AppColors.dark,
    appBar: AppBar(
      leading: NavBtn(icon: Icons.arrow_back_ios_new, onPressed: () => Navigator.pop(context)),
      title: Text('Workshop',
        style: GoogleFonts.cinzel(color: gold, fontSize: 17, letterSpacing: 2)),
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: gold.withValues(alpha: 0.08),
                border: Border.all(color: gold.withValues(alpha: 0.3))),
              child: const Icon(Icons.auto_awesome_outlined, color: gold, size: 36)),
            const SizedBox(height: 24),
            Text('Premium Features',
              style: GoogleFonts.cinzel(
                color: gold, fontSize: 20, letterSpacing: 3,
                fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Container(
              width: 40, height: 1,
              color: gold.withValues(alpha: 0.4)),
            const SizedBox(height: 20),
            Text(
              'Create your own factions, units and abilities. '
              'Your creations are private and only visible to you — '
              'but armies you build with custom units can be shared '
              'with other players.',
              textAlign: TextAlign.center,
              style: GoogleFonts.cinzel(
                color: grey.withValues(alpha: 0.7),
                fontSize: 13, height: 1.6)),
            const SizedBox(height: 32),
            const _PremiumFeature(icon: Icons.shield_outlined,
              label: 'Custom Factions'),
            const SizedBox(height: 10),
            const _PremiumFeature(icon: Icons.group_outlined,
              label: 'Custom Units'),
            const SizedBox(height: 10),
            const _PremiumFeature(icon: Icons.flash_on_outlined,
              label: 'Custom Abilities'),
            const SizedBox(height: 10),
            const _PremiumFeature(icon: Icons.inventory_2_outlined,
              label: 'Usable in Army Builder'),
            const SizedBox(height: 10),
            const _PremiumFeature(icon: Icons.lock_outline,
              label: 'Private — only visible to you'),
            const SizedBox(height: 10),
            const _PremiumFeature(icon: Icons.share_outlined,
              label: 'Share armies with custom units with other players'),
            const SizedBox(height: 36),
            const _UpgradeButton(url: _stripePaymentUrl),
            const SizedBox(height: 8),
            Text(
              '1 Year Access',
              textAlign: TextAlign.center,
              style: GoogleFonts.cinzel(
                color: Colors.white,
                fontSize: 13, letterSpacing: 0.5)),
          ],
        ),
      ),
    )),
  );

  // ═══════════════════════════════════════════════════
  // FACTIONS TAB
  // ═══════════════════════════════════════════════════
  Widget _factionsTab() {
    final userFacIds   = _userFacs.map((f) => f['id'] as String).toSet();
    final officialFacs = _allFacs
        .where((f) => !userFacIds.contains(f['id'] as String))
        .map((f) => {...f, '_isOfficial': true})
        .toList();
    var filtered = [..._userFacs, ...officialFacs].where((f) {
      if (_facSearch.isNotEmpty &&
          !(f['name'] as String).toLowerCase().contains(_facSearch.toLowerCase())) {
        return false;
      }
      if (_facSourceF.isNotEmpty) {
        final isOfficial = f['_isOfficial'] as bool? ?? false;
        final matchOwn      = _facSourceF.contains('own') && !isOfficial;
        final matchOfficial = _facSourceF.contains('official') && isOfficial;
        if (!matchOwn && !matchOfficial) return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      int cmp;
      switch (_facSort) {
        case 'units':
          final aU = _userUnits.where((u) => u['faction_id'] == a['id']).length;
          final bU = _userUnits.where((u) => u['faction_id'] == b['id']).length;
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
            FilterBtn(
              allLabel: 'Sources',
              options: const [
                MapEntry('own',      'Own'),
                MapEntry('official', 'Official'),
              ],
              selected: _facSourceF,
              onChanged: (s) => setState(() { _facSourceF.clear(); _facSourceF.addAll(s); })),
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
              prefixIcon: const Icon(Icons.search, color: grey, size: 18),
              isDense: true,
              clearable: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              onChanged: (v) => setState(() => _facSearch = v)))),
        Expanded(child: Stack(children: [
          filtered.isEmpty
            ? _empty('No factions match.')
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 68),
                itemCount: filtered.length,
                itemBuilder: (_, i) => _facRow(filtered[i])),
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
        ])),
      ])),
      Positioned(bottom: 14, left: 0, right: 0,
        child: CrudCreateBtn(icon: Icons.add, label: 'New Faction',
          onTap: _openFactionForm)),
    ]);
  }

  Widget _facRow(Map<String, dynamic> f) {
    final isOfficial = f['_isOfficial'] == true;
    final bgHex      = f['color'] as String? ?? _kBgPresets.first;
    final bgColor    = AppColors.parseHex(bgHex);
    final List<String> unitNames = isOfficial
        ? GameDataService.units
            .where((u) => u['faction_id'] == f['id'])
            .map((u) => u['name'] as String)
            .toList()
        : [
            ..._userUnits
                .where((u) => u['faction_id'] == f['id'])
                .map((u) => u['name'] as String),
            ...((f['unit_refs'] as List?) ?? []).map((ref) {
              final u = GameDataService.units
                  .where((x) => x['name'] == ref).firstOrNull;
              return u?['name'] as String? ?? (ref as String);
            }).where((n) => n.isNotEmpty),
          ];
    return _FacRowCard(
      f: f, bgColor: bgColor, unitNames: unitNames,
      creatorName: isOfficial ? 'Aetherra' : _creatorName,
      onEdit: isOfficial ? null : () => _openFactionForm(existing: f),
      onCopy: () => _openFactionForm(existing: f, isDuplicate: true));
  }

  // ═══════════════════════════════════════════════════
  // UNITS TAB
  // ═══════════════════════════════════════════════════
  Widget _unitsTab() {
    final userUnitIds   = _userUnits.map((u) => u['id'] as String).toSet();
    final officialUnits = GameDataService.units
        .where((u) => !userUnitIds.contains(u['id'] as String))
        .map((u) => {...u, '_isOfficial': true})
        .toList();
    final filtered = [..._userUnits, ...officialUnits].where((u) {
      if (_unitFacF.isNotEmpty && !_unitFacF.contains(u['faction_id'])) return false;
      if (_unitTypeF.isNotEmpty && !_unitTypeF.contains(u['type'])) return false;
      if (_unitSearch.isNotEmpty &&
          !(u['name'] as String).toLowerCase()
              .contains(_unitSearch.toLowerCase())) {
        return false;
      }
      if (_unitSourceF.isNotEmpty) {
        final isOfficial = u['_isOfficial'] as bool? ?? false;
        final facId = u['faction_id'] as String?;
        final matchNoFac  = _unitSourceF.contains('no_faction') && (facId == null || facId.isEmpty);
        final matchOwn    = _unitSourceF.contains('own') && !isOfficial;
        final matchOfficial = _unitSourceF.contains('official') && isOfficial;
        if (!matchNoFac && !matchOwn && !matchOfficial) return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
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
        _unitFilterBar(),
        Padding(padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
          child: Align(alignment: Alignment.centerLeft,
            child: Text('${filtered.length} unit${filtered.length != 1 ? 's' : ''}',
              style: GoogleFonts.cinzel(color: grey, fontSize: 13, letterSpacing: 1.2)))),
        Expanded(child: Stack(children: [
          filtered.isEmpty
            ? _empty('No units match.')
            : LayoutBuilder(builder: (ctx, bc) {
                final avail = bc.maxWidth - 20;
                final cols  = avail < 600 ? 1 : avail < 950 ? 2 : 3;
                final cardW = ((avail - (cols - 1) * 8) / cols).floorToDouble().clamp(260.0, 600.0);
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 68),
                  itemCount: (filtered.length / cols).ceil(),
                  itemBuilder: (_, row) {
                    final start = row * cols;
                    final end   = (start + cols).clamp(0, filtered.length);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int i = start; i < end; i++) ...[
                          if (i > start) const SizedBox(width: 8),
                          SizedBox(width: cardW, child: _unitRow(filtered[i])),
                        ],
                      ]);
                  });
              }),
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
        ])),
      ])),
      Positioned(bottom: 14, left: 0, right: 0,
        child: CrudCreateBtn(icon: Icons.add, label: 'New Unit',
          onTap: () => _openUnitForm(null))),
    ]);
  }

  Widget _unitFilterBar() => LayoutBuilder(builder: (_, bc) {
    final c = bc.maxWidth < 430;
    final xs = bc.maxWidth < 360;
    return Column(children: [
    SizedBox(height: 44, child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        FilterBtn(
          allLabel: c ? 'Src' : 'Sources',
          compact: xs,
          options: const [
            MapEntry('no_faction', 'No Faction'),
            MapEntry('own',        'Own'),
            MapEntry('official',   'Official'),
          ],
          selected: _unitSourceF,
          onChanged: (s) => setState(() { _unitSourceF.clear(); _unitSourceF.addAll(s); })),
        SizedBox(width: xs ? 3 : 6),
        FilterBtn(
          allLabel: c ? 'Fac' : 'Factions',
          compact: xs,
          options: _allFacs.map((f) =>
            MapEntry(f['id'] as String, f['name'] as String)).toList(),
          dotColors: {for (final f in _allFacs)
            f['id'] as String: AppColors.parseHex(f['color'] as String? ?? '#888888')},
          selected: _unitFacF,
          onChanged: (s) => setState(() { _unitFacF.clear(); _unitFacF.addAll(s); })),
        SizedBox(width: xs ? 3 : 6),
        FilterBtn(
          allLabel: c ? 'Typ' : 'Types',
          compact: xs,
          options: ['Infantry','Cavalry','Shooting','Artillery','Hero','Monster','Flyer','Vehicle']
            .map((t) => MapEntry(t, t)).toList(),
          selected: _unitTypeF,
          onChanged: (s) => setState(() { _unitTypeF.clear(); _unitTypeF.addAll(s); })),
        const Spacer(),
        SortBtn(
          sortBy: _unitSort,
          ascending: _unitSortAsc,
          compact: xs,
          options: const [
            ['name','Name A→Z'], ['cost','Points ↓'],
            ['atk','ATK ↓'], ['def','DEF ↓'],
            ['rng','SHO ↓'], ['mob','MOB ↓'], ['con','CON ↓'],
          ],
          onSelected: (v) => setState(() {
            if (v == _unitSort) { _unitSortAsc = !_unitSortAsc; }
            else { _unitSort = v; _unitSortAsc = true; }
          })),
        SizedBox(width: xs ? 4 : 8),
        SearchToggleBtn(
          isOpen: _unitSearchOpen,
          hasQuery: _unitSearch.isNotEmpty,
          compact: xs,
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
          clearable: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          onChanged: (v) => setState(() => _unitSearch = v)))),
  ]);
  });

  Widget _unitRow(Map<String, dynamic> u) {
    final isOfficial = u['_isOfficial'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RosterCard(
        unitData: u,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          CrudActionBtn(
            icon: Icons.copy_outlined,
            color: grey.withValues(alpha: 0.55),
            onTap: () => _openUnitForm(u, isDuplicate: true)),
          if (isOfficial)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Icon(Icons.lock_outline,
                color: grey.withValues(alpha: 0.4), size: 17))
          else
            CrudActionBtn(
              icon: Icons.edit_outlined,
              color: gold.withValues(alpha: 0.75),
              onTap: () => _openUnitForm(u)),
        ])));
  }

  // ═══════════════════════════════════════════════════
  // ABILITIES TAB
  // ═══════════════════════════════════════════════════
  Widget _abilitiesTab() {
    final userAbNames   = _userAbilities.map((a) => a['name'] as String).toSet();
    final officialAbs   = GameDataService.abilities
        .where((a) => !userAbNames.contains(a['name'] as String))
        .map((a) => {...a, '_isOfficial': true})
        .toList();
    final filtered = [..._userAbilities, ...officialAbs].where((a) {
      if (_abSearch.isNotEmpty &&
          !(a['name'] as String).toLowerCase()
              .contains(_abSearch.toLowerCase())) {
        return false;
      }
      if (_abTypeF.isNotEmpty) {
        final types = a['types'] as List;
        if (types.isNotEmpty && !types.any((t) => _abTypeF.contains(t as String))) return false;
      }
      if (_abSourceF.isNotEmpty) {
        final isOfficial = a['_isOfficial'] as bool? ?? false;
        final matchOwn      = _abSourceF.contains('own') && !isOfficial;
        final matchOfficial = _abSourceF.contains('official') && isOfficial;
        if (!matchOwn && !matchOfficial) return false;
      }
      if (_abCategoryF.isNotEmpty) {
        final cost   = (a['cost']    as num?)?.toInt() ?? 0;
        final cpCost = (a['cp_cost'] as num?)?.toInt() ?? 0;
        final isCommand  = cpCost > 0;
        final isNegative = cost < 0;
        final isStandard = !isCommand && !isNegative;
        final match = (_abCategoryF.contains('standard') && isStandard) ||
                      (_abCategoryF.contains('command')  && isCommand)  ||
                      (_abCategoryF.contains('negative') && isNegative);
        if (!match) return false;
      }
      return true;
    }).toList();

    return Stack(children: [
      Positioned.fill(child: Column(children: [
        LayoutBuilder(builder: (_, bc) { final c = bc.maxWidth < 430; return
        SizedBox(height: 44, child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            FilterBtn(
              allLabel: c ? 'Src' : 'Sources',
              options: const [
                MapEntry('own',      'Own'),
                MapEntry('official', 'Official'),
              ],
              selected: _abSourceF,
              onChanged: (s) => setState(() { _abSourceF.clear(); _abSourceF.addAll(s); })),
            const SizedBox(width: 6),
            FilterBtn(
              allLabel: c ? 'Typ' : 'Types',
              options: ['Infantry','Cavalry','Shooting','Artillery','Hero','Monster','Flyer','Vehicle']
                .map((t) => MapEntry(t, t)).toList(),
              selected: _abTypeF,
              onChanged: (s) => setState(() { _abTypeF.clear(); _abTypeF.addAll(s); })),
            const SizedBox(width: 6),
            FilterBtn(
              allLabel: c ? 'Cat' : 'Category',
              options: const [
                MapEntry('standard', 'Standard'),
                MapEntry('command',  'Command'),
                MapEntry('negative', 'Negative'),
              ],
              selected: _abCategoryF,
              onChanged: (s) => setState(() { _abCategoryF.clear(); _abCategoryF.addAll(s); })),
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
          ])));
        }),
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
              clearable: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              onChanged: (v) => setState(() => _abSearch = v)))),
        Expanded(child: Stack(children: [
          filtered.isEmpty
            ? _empty('No abilities match.')
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 68),
                itemCount: filtered.length,
                itemBuilder: (_, i) => _abilityRow(filtered[i])),
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
        ])),
      ])),
      Positioned(bottom: 14, left: 0, right: 0,
        child: CrudCreateBtn(icon: Icons.add, label: 'New Ability',
          onTap: () => _openAbilityForm(null))),
    ]);
  }

  Widget _abilityRow(Map<String, dynamic> a) {
    final isOfficial = a['_isOfficial'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AbilityCard(
        abilityData: a,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          CrudActionBtn(
            icon: Icons.copy_outlined,
            color: grey.withValues(alpha: 0.55),
            onTap: () => _openAbilityForm(a, isDuplicate: true)),
          if (isOfficial)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Icon(Icons.lock_outline,
                color: grey.withValues(alpha: 0.4), size: 17))
          else
            CrudActionBtn(
              icon: Icons.edit_outlined,
              color: gold.withValues(alpha: 0.75),
              onTap: () => _openAbilityForm(a)),
        ])));
  }

  // ═══════════════════════════════════════════════════
  // FACTION FORM (create + edit)
  // ═══════════════════════════════════════════════════

  Future<void> _openFactionForm({Map<String, dynamic>? existing, bool isDuplicate = false}) async {
    final isEdit    = existing != null && !isDuplicate;
    // Official factions have no user_id — their lore is read-only
    final isUserFaction = !isEdit || isDuplicate ||
        existing['user_id'] != null ||
        GameDataService.userFactions.any((f) => f['id'] == existing['id']);
    final factionId = isEdit
        ? existing['id'] as String
        : 'uf_${DateTime.now().millisecondsSinceEpoch}';
    final nameCtrl = TextEditingController(
        text: isDuplicate ? 'Copy of ${existing!['name']}' : existing?['name'] as String? ?? '');
    final loreCtrl = TextEditingController(text: existing?['lore'] as String? ?? '');
    String  selColor   = existing?['color'] as String? ?? _kBgPresets.first;
    String? imageB64           = existing?['image_b64'] as String?;
    bool    removingBg         = false;
    bool    placeholderHovered = false;
    // True once the faction row exists in user_factions (edit mode or after auto-save)
    bool persisted = isEdit;

    // Unit refs to carry into the initial insert when duplicating.
    // Only applied once (on insert) — subsequent updates leave unit_refs to the picker.
    final List<String> sourceUnitRefs;
    if (isDuplicate && existing != null) {
      final stored = existing['unit_refs'] as List?;
      if (stored != null && stored.isNotEmpty) {
        // User faction: copy stored refs directly
        sourceUnitRefs = List<String>.from(stored);
      } else {
        // Official faction: derive from GameDataService by faction_id
        final fid = existing['id'] as String? ?? '';
        sourceUnitRefs = GameDataService.units
            .where((u) => u['faction_id'] == fid)
            .map((u) => u['name'] as String)
            .toList();
      }
    } else {
      sourceUnitRefs = [];
    }

    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: AppColors.dark,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) {

        return DraggableScrollableSheet(
          expand: false, initialChildSize: 0.92,
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
              Text(isEdit ? 'Edit Faction'
                  : isDuplicate ? 'Copy: ${existing?['name'] ?? ''}'
                  : 'New Faction',
                style: GoogleFonts.cinzel(color: gold, fontSize: 17)),
              const SizedBox(height: 16),

              // ── Name ──────────────────────────────────
              _lbl('Name'),
              if (isUserFaction)
                _tf(nameCtrl, 'e.g. Elves', onChanged: (_) {})
              else
                Text(nameCtrl.text,
                  style: GoogleFonts.cinzel(color: gold, fontSize: 15)),
              const SizedBox(height: 16),

              // ── Logo preview (full-width, on chosen bg color) ──
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
                          final res = await pickLogoPhotoWithCrop(context);
                          if (res != null) setS(() => imageB64 = res);
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
                          Text('Removing background…',
                            style: GoogleFonts.cinzel(color: gold, fontSize: 12)),
                        ]))),
                ])),

              // ── Remove background + bg color ─────────────
              const SizedBox(height: 8),
              Row(children: [
                _FacPhotoIcon(icon: Icons.add_photo_alternate_outlined,
                  onTap: () async {
                    final res = await pickLogoPhotoWithCrop(context);
                    if (res != null) setS(() => imageB64 = res);
                  }),
                if (imageB64 != null) ...[
                  const SizedBox(width: 6),
                  _FacPhotoIcon(icon: Icons.crop,
                    onTap: () async {
                      final res = await editLogoCropPhoto(context, imageB64!);
                      if (res != null) setS(() => imageB64 = res);
                    }),
                  const SizedBox(width: 6),
                  _FacPhotoIcon(icon: Icons.delete_outline,
                    color: Colors.red, onTap: () => setS(() => imageB64 = null)),
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
                style: GoogleFonts.cinzel(color: grey.withValues(alpha: 0.5),
                  fontSize: 10, fontStyle: FontStyle.italic)),
              const SizedBox(height: 10),

              _lbl('Lore (optional)'),
              if (isUserFaction)
                AetherraTextField(
                  controller: loreCtrl,
                  minLines: 4, maxLines: null,
                  style: const TextStyle(color: AppColors.textLight, fontSize: 14, height: 1.5),
                  hintText: 'Lore: origin, history, culture...',
                  hintStyle: TextStyle(color: grey.withValues(alpha: 0.5)),
                  contentPadding: const EdgeInsets.all(12))
              else if (loreCtrl.text.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.gold.withValues(alpha: 0.2))),
                  child: Text(loreCtrl.text,
                    style: const TextStyle(color: AppColors.textLight, fontSize: 14, height: 1.5))),
              const SizedBox(height: 16),

              if (isEdit || isDuplicate) ...[
                SizedBox(width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      if (!persisted) {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) { _toast('Enter a name.'); return; }
                        final uid = sb.auth.currentUser?.id;
                        if (uid == null) return;
                        try {
                          await sb.from('user_factions').insert({
                            'id': factionId, 'user_id': uid,
                            'name': name, 'color': selColor,
                            if (sourceUnitRefs.isNotEmpty) 'unit_refs': sourceUnitRefs,
                          });
                          persisted = true;
                        } catch (e) {
                          if (ctx.mounted) _toast('Could not save: $e');
                          return;
                        }
                      }
                      final fresh = await sb
                          .from('user_factions').select()
                          .eq('id', factionId).maybeSingle();
                      if (!ctx.mounted) return;
                      await Navigator.push(ctx, MaterialPageRoute(
                        builder: (_) => FactionUnitPickerScreen(
                          faction:     fresh ?? existing ?? {'id': factionId},
                          userUnits:   _userUnits,
                          allFactions: _allFacs)));
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

              // ── Save ──────────────────────────────────
              SizedBox(width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) { _toast('Enter a name.'); return; }
                    final uid = sb.auth.currentUser?.id;
                    if (uid == null) return;
                    final payload = <String, dynamic>{
                      'name': name, 'color': selColor,
                    };
                    final loreVal = isUserFaction ? loreCtrl.text.trim() : '';
                    final extra   = <String, dynamic>{
                      'lore':      loreVal.isEmpty ? null : loreVal,
                      'image_b64': imageB64,
                    };
                    try {
                      if (persisted) {
                        await sb.from('user_factions')
                            .update({...payload, ...extra}).eq('id', factionId);
                      } else {
                        await sb.from('user_factions').insert({
                          ...payload, ...extra, 'id': factionId, 'user_id': uid,
                          if (sourceUnitRefs.isNotEmpty) 'unit_refs': sourceUnitRefs,
                        });
                        persisted = true;
                      }
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx); _load();
                      _toast(isEdit ? '"$name" updated!' : '"$name" created!');
                    } catch (_) {
                      try {
                        if (persisted) {
                          await sb.from('user_factions')
                              .update(payload).eq('id', factionId);
                        } else {
                          await sb.from('user_factions').insert({
                            ...payload, 'id': factionId, 'user_id': uid,
                            if (sourceUnitRefs.isNotEmpty) 'unit_refs': sourceUnitRefs,
                          });
                          persisted = true;
                        }
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx); _load();
                        _toast(isEdit ? '"$name" updated!' : '"$name" created!');
                      } catch (e) {
                        if (ctx.mounted) _toast('Could not save: $e');
                      }
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

              // ── Delete (edit mode only) ────────────────
              if (isEdit) ...[
                const SizedBox(height: 12),
                SizedBox(width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final name = nameCtrl.text.trim().isNotEmpty
                          ? nameCtrl.text.trim()
                          : existing['name'] as String;
                      final unitCnt = _userUnits
                          .where((u) => u['faction_id'] == factionId).length;
                      if (unitCnt > 0) {
                        _toast('Remove $unitCnt unit${unitCnt > 1 ? 's' : ''} first.');
                        return;
                      }
                      if (!await _confirm('Delete faction "$name"?')) return;
                      await sb.from('user_factions').delete().eq('id', factionId);
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      _load();
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
            ])));
      }));
  }



  // ═══════════════════════════════════════════════════
  // UNIT FORM
  // ═══════════════════════════════════════════════════
  Future<void> _openUnitForm(Map<String, dynamic>? existing, {bool isDuplicate = false}) async {
    final isNew    = existing == null || isDuplicate;
    // Official units (from custom_units) are read-only for lore; user units are editable
    final isUserUnit = isNew ||
        existing['user_id'] != null ||
        GameDataService.userUnits.any((u) => u['id'] == existing['id']);
    final nameCtrl = TextEditingController(
      text: isDuplicate ? 'Copy of ${existing!['name']}' : existing?['name'] ?? '');
    final atkCtrl  = TextEditingController(text: '${existing?['atk']    ?? 4}');
    final defCtrl  = TextEditingController(text: '${existing?['def_val'] ?? 4}');
    final rngCtrl  = TextEditingController(text: '${existing?['rng']    ?? 0}');
    final mobCtrl  = TextEditingController(text: '${existing?['mob']    ?? 6}');
    final conCtrl  = TextEditingController(text: '${existing?['con_val'] ?? 3}');
    final cpCtrl   = TextEditingController(text: '${existing?['cp']     ?? 0}');
    final loreCtrl = TextEditingController(text: existing?['lore'] as String? ?? '');


    // Default faction: user's first, or first available
    final defaultFac = _allFacs.isNotEmpty ? _allFacs.first['id'] as String : '';
    String  selFac   = existing?['faction_id'] ?? defaultFac;
    String  selType  = (existing?['type'] ?? 'Infantry') == 'Ranged' ? 'Shooting' : (existing?['type'] ?? 'Infantry');
    bool    isUniq   = existing?['unique_unit'] ?? false;
    final   selAbs   = List<String>.from(existing?['abilities'] ?? []);
    String? imageB64           = existing?['image_b64'] as String?;
    String  selBgColor         = existing?['bg_color']  as String? ?? _kBgPresets.first;
    bool    removingBg         = false;
    bool    placeholderHovered = false;

    int calcCost() => CostConfig.calcCost(
      a:   int.tryParse(atkCtrl.text) ?? 0,
      d:   int.tryParse(defCtrl.text) ?? 0,
      s:   int.tryParse(rngCtrl.text) ?? 0,
      m:   int.tryParse(mobCtrl.text) ?? 6,
      str: int.tryParse(conCtrl.text) ?? 1,
      type: selType,
      cpVal: int.tryParse(cpCtrl.text) ?? 0,
      abilities: selAbs,
      allAbilityCosts: _allAbCosts);

    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: AppColors.dark,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) {
        final cost        = calcCost();
        final typeAbsData = _allAbs
            .where((a) {
              final types = a['types'] as List;
              return types.isEmpty || types.contains(selType);
            })
            .toList();

        return DraggableScrollableSheet(
          expand: false, initialChildSize: 0.93,
          builder: (_, scroll) => SingleChildScrollView(
            controller: scroll,
            padding: EdgeInsets.fromLTRB(16, 16, 16,
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
              if (isUserUnit)
                _tf(nameCtrl, 'e.g. Elite Guards', onChanged: (_) => setS(() {}))
              else
                Text(nameCtrl.text,
                  style: GoogleFonts.cinzel(color: gold, fontSize: 15)),
              const SizedBox(height: 14),

              // ── Photo ───────────────────────────────────
              Center(child: Container(width: 120, height: 210,
                foregroundDecoration: BoxDecoration(
                  border: Border.all(color: gold.withValues(alpha: 0.35))),
                color: AppColors.parseHex(selBgColor),
                child: Stack(children: [
                  Positioned.fill(child: imageB64 != null
                    ? CachedBase64Image(base64: imageB64!, width: 120, height: 210)
                    : GestureDetector(
                        onTap: () async {
                          final r = await pickAndCropPhoto(ctx);
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
                          Text('Removing background…',
                            style: GoogleFonts.cinzel(color: gold, fontSize: 11)),
                        ]))),
                ]))),
              const SizedBox(height: 8),
              Row(children: [
                _FacPhotoIcon(icon: Icons.add_photo_alternate_outlined,
                  onTap: () async {
                    final r = await pickAndCropPhoto(ctx);
                    if (r != null) setS(() => imageB64 = r);
                  }),
                if (imageB64 != null) ...[
                  const SizedBox(width: 6),
                  _FacPhotoIcon(icon: Icons.crop,
                    onTap: () async {
                      final r = await editCropPhoto(ctx, imageB64!);
                      if (r != null) setS(() => imageB64 = r);
                    }),
                  const SizedBox(width: 6),
                  _FacPhotoIcon(icon: Icons.delete_outline,
                    color: Colors.red, onTap: () => setS(() => imageB64 = null)),
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
                style: GoogleFonts.cinzel(color: grey.withValues(alpha: 0.5),
                  fontSize: 10, fontStyle: FontStyle.italic)),
              const SizedBox(height: 8),
              _lbl('Lore (optional)'),
              if (isUserUnit)
                AetherraTextField(
                  controller: loreCtrl,
                  hintText: 'Lore: origin, history, tactics...',
                  minLines: 3, maxLines: null,
                  style: GoogleFonts.cinzel(color: AppColors.grey, fontSize: 12, height: 1.5))
              else if (loreCtrl.text.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.gold.withValues(alpha: 0.2))),
                  child: Text(loreCtrl.text,
                    style: GoogleFonts.cinzel(color: AppColors.grey, fontSize: 12, height: 1.5))),
              const SizedBox(height: 14),

              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  _lbl('Faction'),
                  _dd<String>(
                    value: selFac,
                    items: _allFacs.map((f) => DropdownMenuItem(
                      value: f['id'] as String,
                      child: Text(f['name'] as String,
                        style: const TextStyle(color: AppColors.textLight)))).toList(),
                    onChanged: (v) => setS(() => selFac = v!)),
                ])),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  _lbl('Type'),
                  _dd<String>(
                    value: selType,
                    items: ['Infantry', 'Cavalry', 'Shooting', 'Artillery', 'Hero', 'Monster', 'Flyer', 'Vehicle']
                        .map((t) => DropdownMenuItem(value: t,
                          child: Text(t, style: const TextStyle(
                            color: AppColors.textLight)))).toList(),
                    onChanged: (v) => setS(() {
                      selType = v!;
                      if (selType == 'Hero' || selType == 'Monster') isUniq = true;
                      selAbs.removeWhere((n) {
                        final ab = builtinAbilities
                            .where((x) => x.name == n).firstOrNull;
                        return ab != null &&
                            ab.types.isNotEmpty &&
                            !ab.types.contains(selType);
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
                  max: selType == 'Cavalry' || selType == 'Hero' || selType == 'Monster' || selType == 'Flyer' || selType == 'Vehicle' ? 20 : 8),
                const SizedBox(width: 4),
                _stI('STR', conCtrl, setS),
                const SizedBox(width: 4),
                _stI('CP', cpCtrl, setS),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _lbl('Unique'),
                const SizedBox(width: 8),
                Switch(value: isUniq,
                  onChanged: (v) => setS(() => isUniq = v),
                  activeThumbColor: gold),
                Text(isUniq ? 'Yes' : 'No',
                  style: const TextStyle(color: grey, fontSize: 15)),
              ]),
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
                  'lore':      isUserUnit && loreCtrl.text.trim().isNotEmpty ? loreCtrl.text.trim() : null,
                }),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final newSel = await showModalBottomSheet<List<String>>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: AppColors.dark,
                      builder: (_) => AbilityPickerSheet(
                        allAbilities: typeAbsData,
                        initialSelected: selAbs,
                        unitDataBuilder: (abs) => {
                          'name':      nameCtrl.text.trim().isEmpty ? '—' : nameCtrl.text.trim(),
                          'type':      selType,
                          'atk':       int.tryParse(atkCtrl.text) ?? 0,
                          'def_val':   int.tryParse(defCtrl.text) ?? 0,
                          'rng':       int.tryParse(rngCtrl.text) ?? 0,
                          'mob':       int.tryParse(mobCtrl.text) ?? 0,
                          'con_val':   int.tryParse(conCtrl.text) ?? 0,
                          'cp':        int.tryParse(cpCtrl.text) ?? 0,
                          'cost':      CostConfig.calcCost(
                            a: int.tryParse(atkCtrl.text) ?? 0,
                            d: int.tryParse(defCtrl.text) ?? 0,
                            s: int.tryParse(rngCtrl.text) ?? 0,
                            m: int.tryParse(mobCtrl.text) ?? 6,
                            str: int.tryParse(conCtrl.text) ?? 1,
                            type: selType,
                            cpVal: int.tryParse(cpCtrl.text) ?? 0,
                            abilities: abs,
                            allAbilityCosts: _allAbCosts),
                          'abilities': abs,
                          'image_b64': imageB64,
                          'bg_color':  selBgColor,
                          'lore':      isUserUnit && loreCtrl.text.trim().isNotEmpty ? loreCtrl.text.trim() : null,
                        },
                      ),
                    );
                    if (newSel != null) {
                      setS(() {
                        selAbs.clear();
                        selAbs.addAll(newSel);
                      });
                    }
                  },
                  icon: const Icon(Icons.tune, size: 16),
                  label: Text(selAbs.isEmpty
                    ? 'Manage Abilities'
                    : 'Manage Abilities (${selAbs.length})'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.grey,
                    side: BorderSide(color: AppColors.gold.withValues(alpha: 0.3)),
                    shape: const RoundedRectangleBorder(),
                    textStyle: GoogleFonts.cinzel(fontSize: 13),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                )),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) { _toast('Enter a name.'); return; }
                    final uid = sb.auth.currentUser?.id;
                    if (uid == null) return;
                    final payload = {
                      'name':        name,
                      'user_id':     uid,
                      'faction_id':  selFac,
                      'type':        selType,
                      'atk':         int.tryParse(atkCtrl.text) ?? 0,
                      'def_val':     int.tryParse(defCtrl.text) ?? 0,
                      'rng':         int.tryParse(rngCtrl.text) ?? 0,
                      'mob':         int.tryParse(mobCtrl.text) ?? 6,
                      'con_val':     int.tryParse(conCtrl.text) ?? 3,
                      'cp':          int.tryParse(cpCtrl.text) ?? 0,
                      'cost':        calcCost(),
                      'abilities':   selAbs,
                      'unique_unit': isUniq,
                      'image_b64':   imageB64,
                      'bg_color':    selBgColor,
                      'lore':        isUserUnit && loreCtrl.text.trim().isNotEmpty ? loreCtrl.text.trim() : null,
                    };
                    Future<void> doSave(Map<String, dynamic> p) async {
                      if (existing != null && !isDuplicate) {
                        await sb.from('user_units')
                            .update(p).eq('id', existing['id'] as String);
                      } else {
                        await sb.from('user_units').insert({
                          ...p,
                          'id': 'uu_${DateTime.now().millisecondsSinceEpoch}',
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
                    backgroundColor: gold,
                    foregroundColor: AppColors.dark,
                    side: BorderSide.none,
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

  Future<void> _deleteUnit(Map<String, dynamic> u) async {
    if (!await _confirm('Delete "${u['name']}"?')) return;
    await sb.from('user_units').delete().eq('id', u['id'] as String);
    await GameDataService.load();
    _load();
  }

  // ═══════════════════════════════════════════════════
  // ABILITY FORM
  // ═══════════════════════════════════════════════════
  Future<void> _openAbilityForm(Map<String, dynamic>? existing, {bool isDuplicate = false}) async {
    final originalName = existing?['name'] as String? ?? '';
    final nameCtrl = TextEditingController(
      text: isDuplicate ? 'Copy of ${existing!['name']}' : originalName);
    final descCtrl = TextEditingController(text: existing?['description'] ?? '');
    final costCtrl = TextEditingController(text: '${existing?['cost'] ?? 0}');
    final selTypes = List<String>.from(existing?['types'] ?? []);

    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: AppColors.dark,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) =>
        Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16,
            MediaQuery.of(context).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Text(existing == null ? 'New Ability'
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
                onChanged: (_) => setS(() {})),
              const SizedBox(height: 4),
              Builder(builder: (_) {
                final v = int.tryParse(costCtrl.text) ?? 0;
                final label = v > 0 ? '+$v pts (advantage)'
                    : v < 0 ? '$v pts (disadvantage)' : '0 pts (neutral)';
                return Text(label, style: GoogleFonts.cinzel(
                  color: v > 0 ? gold : v < 0 ? Colors.orange : grey,
                  fontSize: 14));
              }),
              const SizedBox(height: 10),
              _lbl('Unit Types (leave empty = all types)'),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6,
                children: ['Infantry', 'Cavalry', 'Shooting', 'Artillery', 'Hero', 'Monster', 'Flyer']
                    .map((t) {
                      final on = selTypes.contains(t);
                      final tc = typeColor(t);
                      return GestureDetector(
                        onTap: () => setS(() {
                          if (on) { selTypes.remove(t); } else { selTypes.add(t); }
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: on ? tc.withValues(alpha: 0.18) : AppColors.dark,
                            border: Border.all(color: on ? tc : tc.withValues(alpha: 0.35))),
                          child: Text(t, style: GoogleFonts.cinzel(
                            fontSize: 13, color: on ? tc : tc.withValues(alpha: 0.6)))));
                    }).toList()),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final desc = descCtrl.text.trim();
                    final cost = int.tryParse(costCtrl.text) ?? 0;
                    if (name.isEmpty) { _toast('Name required.'); return; }
                    if (desc.isEmpty) { _toast('Description required.'); return; }
                    final uid = sb.auth.currentUser?.id;
                    if (uid == null) return;
                    final payload = {
                      'name': name, 'description': desc,
                      'cost': cost, 'types': selTypes, 'user_id': uid,
                    };
                    try {
                      if (existing != null && !isDuplicate) {
                        // delete + re-insert to avoid PK issues when renaming
                        await sb.from('user_abilities').delete().eq('id', existing['id'] as String);
                        await sb.from('user_abilities').insert({
                          ...payload,
                          'id': existing['id'] as String,
                        });
                        if (name != originalName) {
                          final units = await sb.from('user_units')
                            .select('id, abilities')
                            .eq('user_id', uid);
                          for (final u in List<Map<String, dynamic>>.from(units)) {
                            final abs = List<String>.from(u['abilities'] ?? []);
                            if (abs.contains(originalName)) {
                              await sb.from('user_units')
                                .update({'abilities': abs.map((a) => a == originalName ? name : a).toList()})
                                .eq('id', u['id'] as String);
                            }
                          }
                        }
                      } else {
                        await sb.from('user_abilities').insert({
                          ...payload,
                          'id': 'ua_${DateTime.now().millisecondsSinceEpoch}',
                        });
                      }
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      _load();
                      _toast(existing != null && !isDuplicate ? '"$name" updated!' : '"$name" saved!');
                      _recalcUserUnits(name).catchError((_) {});
                    } catch (e) {
                      _toast('Save failed: ${e.toString().split('\n').first}');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: gold,
                    foregroundColor: AppColors.dark,
                    side: BorderSide.none,
                    shape: const RoundedRectangleBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text(existing != null && !isDuplicate ? 'Save Changes' : 'Create Ability',
                    style: GoogleFonts.cinzel(fontSize: 15, letterSpacing: 2)))),
              if (existing != null && !isDuplicate) ...[
                const SizedBox(height: 8),
                SizedBox(width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _deleteAbility(existing);
                    },
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: Text('Delete Ability',
                      style: GoogleFonts.cinzel(fontSize: 14, letterSpacing: 1)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
                      shape: const RoundedRectangleBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 12)))),
              ],
            ])))));
  }

  Future<void> _recalcUserUnits(String abilityName) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;
    await GameDataService.load();
    final units = await sb.from('user_units').select('*').eq('user_id', uid);
    for (final u in List<Map<String, dynamic>>.from(units)) {
      final abs = List<String>.from(u['abilities'] ?? []);
      if (!abs.contains(abilityName)) continue;
      final type = (u['type'] as String?) == 'Ranged' ? 'Shooting' : (u['type'] as String? ?? 'Infantry');
      final newCost = CostConfig.calcCost(
        a: u['atk'] as int? ?? 0, d: u['def_val'] as int? ?? 0,
        s: u['rng'] as int? ?? 0, m: u['mob'] as int? ?? 6,
        str: u['con_val'] as int? ?? 3, type: type,
        cpVal: u['cp'] as int? ?? 0, abilities: abs,
        allAbilityCosts: GameDataService.abilityCosts,
      );
      if (newCost != (u['cost'] as int? ?? 0)) {
        await sb.from('user_units').update({'cost': newCost}).eq('id', u['id'] as String);
      }
    }
  }

  Future<void> _deleteAbility(Map<String, dynamic> a) async {
    final name = a['name'] as String;
    if (!await _confirm('Delete "$name"?')) return;
    await sb.from('user_abilities').delete().eq('id', a['id'] as String);
    _load();
  }

  // ═══════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════

  Widget _empty(String msg) => Center(
    child: Text(msg, textAlign: TextAlign.center,
      style: GoogleFonts.cinzel(
        color: grey.withValues(alpha: 0.5), fontSize: 14, height: 1.6)));

  Widget _lbl(String t) => Padding(padding: const EdgeInsets.only(bottom: 4),
    child: Text(t, style: GoogleFonts.cinzel(
      color: grey, fontSize: 13, letterSpacing: 1.5)));

  Widget _tf(TextEditingController ctrl, String hint, {
    bool readOnly = false,
    TextInputType type = TextInputType.text,
    required void Function(String) onChanged,
  }) => AetherraTextField(
    controller: ctrl, readOnly: readOnly,
    keyboardType: type, onChanged: onChanged,
    hintText: hint);

  Widget _dd<T>({required T value, required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged}) =>
    DropdownButtonFormField<T>(
      initialValue: value, items: items, onChanged: onChanged,
      isExpanded: true,
      dropdownColor: AppColors.dark,
      style: const TextStyle(color: AppColors.textLight, fontSize: 17),
      decoration: InputDecoration(
        filled: true, fillColor: AppColors.dark,
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
    final ok = await showAetherraSheet<bool>(context,
      title: msg,
      body: const SizedBox.shrink(),
      actions: [
        SheetAction('Cancel', grey,               () => Navigator.pop(context, false), outlined: true),
        SheetAction('Delete', Colors.red, () => Navigator.pop(context, true)),
      ]);
    return ok ?? false;
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: AppColors.dark,
      content: Text(msg, style: GoogleFonts.cinzel(color: gold)),
      duration: const Duration(seconds: 2)));
}

// ── UPGRADE BUTTON ───────────────────────────────────
class _UpgradeButton extends StatelessWidget {
  final String url;
  const _UpgradeButton({required this.url});

  static const gold = AppColors.gold;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 240,
    child: OutlinedButton.icon(
      onPressed: () => launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication),
      icon: const Icon(Icons.add, color: AppColors.dark, size: 16),
      label: Text('Upgrade to Premium',
        style: GoogleFonts.cinzel(fontSize: 14, letterSpacing: 1.2)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.dark,
        backgroundColor: gold,
        side: BorderSide.none,
        shape: const RoundedRectangleBorder(),
        padding: const EdgeInsets.symmetric(vertical: 18))));
}

// ── PAYWALL FEATURE BULLET ───────────────────────────
class _PremiumFeature extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _PremiumFeature({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.gold.withValues(alpha: 0.04),
      border: Border(
        left: BorderSide(color: AppColors.gold.withValues(alpha: 0.6), width: 2))),
    child: Row(children: [
      Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: 0.12),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.35))),
        child: Icon(icon, color: AppColors.gold, size: 22)),
      const SizedBox(width: 14),
      Expanded(child: Text(label,
        style: GoogleFonts.cinzel(
          color: AppColors.grey.withValues(alpha: 0.85),
          fontSize: 13, letterSpacing: 0.3, height: 1.4))),
    ]));
}

class _FacTrashBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _FacTrashBtn({required this.onTap});
  @override State<_FacTrashBtn> createState() => _FacTrashBtnState();
}
class _FacTrashBtnState extends State<_FacTrashBtn> {
  bool _hovered = false;
  bool _pressed = false;
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
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: 24, height: 24,
            child: AnimatedScale(
              scale: _pressed ? 0.85 : _hovered ? 1.2 : 1.0,
              duration: const Duration(milliseconds: 100),
              child: Icon(Icons.delete_outline,
                color: Colors.red.withValues(
                  alpha: _pressed ? 1.0 : _hovered ? 0.9 : 0.5),
                size: 20))))));
}

class _FacPhotoIcon extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  const _FacPhotoIcon({required this.icon, required this.onTap, this.color = AppColors.gold});
  @override State<_FacPhotoIcon> createState() => _FacPhotoIconState();
}
class _FacPhotoIconState extends State<_FacPhotoIcon> {
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
            opacity: _hovered ? 1.0 : 0.45,
            child: Icon(widget.icon, color: widget.color, size: 20))))));
}

class _FacEditOverlay extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _FacEditOverlay({required this.icon, required this.onTap});
  @override State<_FacEditOverlay> createState() => _FacEditOverlayState();
}
class _FacEditOverlayState extends State<_FacEditOverlay> {
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
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: AppColors.dark.withValues(alpha: _hovered ? 0.92 : 0.70),
              border: Border.all(
                color: AppColors.gold.withValues(alpha: _hovered ? 0.9 : 0.4))),
            child: Icon(widget.icon,
              color: AppColors.gold.withValues(alpha: _hovered ? 1.0 : 0.65),
              size: 14))))));
}

class _FacPicBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _FacPicBtn({required this.icon, required this.label,
    required this.color, required this.onTap});
  @override State<_FacPicBtn> createState() => _FacPicBtnState();
}
class _FacPicBtnState extends State<_FacPicBtn> {
  bool _hovered = false;
  @override Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit:  (_) => setState(() => _hovered = false),
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: widget.onTap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(widget.icon,
          color: widget.color.withValues(alpha: _hovered ? 1.0 : 0.55),
          size: 16),
        const SizedBox(width: 6),
        Text(widget.label, style: GoogleFonts.cinzel(
          color: widget.color.withValues(alpha: _hovered ? 1.0 : 0.55),
          fontSize: 12)),
      ])));
}

class _FacRowCard extends StatefulWidget {
  final Map<String, dynamic> f;
  final Color bgColor;
  final List<String> unitNames;
  final String creatorName;
  final VoidCallback? onEdit;   // null = official (locked)
  final VoidCallback? onCopy;
  const _FacRowCard({required this.f, required this.bgColor,
    required this.unitNames, required this.creatorName,
    this.onEdit, this.onCopy});
  @override State<_FacRowCard> createState() => _FacRowCardState();
}
class _FacRowCardState extends State<_FacRowCard> {
  bool _loreExpanded  = false;
  bool _unitsExpanded = false;
  bool _loreHovered   = false;
  bool _unitsHovered  = false;
  Widget? _cachedImg;

  @override void initState() {
    super.initState();
    final b64 = widget.f['image_b64'] as String?;
    if (b64 != null && b64.isNotEmpty) {
      _cachedImg = CachedBase64Image(base64: b64, width: AppColors.bannerW, height: AppColors.bannerH);
    }
  }

  @override void didUpdateWidget(_FacRowCard old) {
    super.didUpdateWidget(old);
    final b64    = widget.f['image_b64'] as String?;
    final oldB64 = old.f['image_b64']    as String?;
    if (b64 != oldB64) {
      _cachedImg = (b64 != null && b64.isNotEmpty)
          ? CachedBase64Image(base64: b64, width: AppColors.bannerW, height: AppColors.bannerH) : null;
    }
  }


  @override Widget build(BuildContext context) {
    final lore    = widget.f['lore'] as String?;
    final hasLogo = _cachedImg != null;
    final hasLore  = lore != null && lore.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: widget.bgColor,
        border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.2),
          width: 1.5)),
      child: Stack(clipBehavior: Clip.hardEdge, children: [

        if (hasLogo) Positioned(
          top: 0, left: 0, right: 0, height: 115,
          child: ClipRect(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: (_loreExpanded || _unitsExpanded) ? -70.0 : 0.0),
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
                          Text(widget.creatorName,
                            style: GoogleFonts.cinzel(color: Colors.white54, fontSize: 12,
                              shadows: [const Shadow(color: Colors.black87, blurRadius: 4)])),
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
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: widget.unitNames.isNotEmpty
                        ? () => setState(() => _unitsExpanded = !_unitsExpanded) : null,
                      child: MouseRegion(
                        cursor: widget.unitNames.isNotEmpty ? SystemMouseCursors.click : MouseCursor.defer,
                        onEnter: (_) => setState(() => _unitsHovered = true),
                        onExit:  (_) => setState(() => _unitsHovered = false),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 80),
                          opacity: widget.unitNames.isEmpty ? 0.2
                            : (_unitsExpanded || _unitsHovered ? 1.0 : 0.55),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('${widget.unitNames.length}',
                              style: GoogleFonts.cinzel(color: AppColors.gold, fontSize: 13,
                                shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])),
                            const SizedBox(width: 3),
                            Icon(_unitsExpanded ? Icons.group : Icons.group_outlined,
                              color: AppColors.gold, size: 18,
                              shadows: const [Shadow(color: Colors.black87, blurRadius: 6)]),
                          ])))),
                    const Spacer(),
                    if (widget.onCopy != null)
                      NavBtn(icon: Icons.copy_outlined, onPressed: widget.onCopy, size: 36),
                    if (widget.onEdit != null)
                      NavBtn(icon: Icons.edit_outlined, onPressed: widget.onEdit, size: 36)
                    else
                      const SizedBox(width: 36, height: 36,
                        child: Center(child: Icon(Icons.lock_outline,
                          color: Color(0x66FFFFFF), size: 18))),
                  ]),
                ]))),

          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            child: _unitsExpanded && widget.unitNames.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: widget.unitNames.map((n) => Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('· $n',
                        style: GoogleFonts.cinzel(
                          color: Colors.white70, fontSize: 11, height: 1.4,
                          shadows: [const Shadow(color: Colors.black87, blurRadius: 4)])))).toList()))
              : const SizedBox.shrink()),

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
      ]));
  }
}

class _HoverTab extends StatefulWidget {
  final String text;
  final TabController controller;
  final int index;
  const _HoverTab({required this.text, required this.controller, required this.index});
  @override State<_HoverTab> createState() => _HoverTabState();
}
class _HoverTabState extends State<_HoverTab> {
  bool _hovered = false;

  @override void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
  }
  @override void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }
  void _rebuild() => setState(() {});

  @override Widget build(BuildContext context) {
    final selected = widget.controller.index == widget.index;
    final color = selected
        ? AppColors.gold
        : _hovered
            ? AppColors.gold.withValues(alpha: 0.75)
            : AppColors.grey;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: Tab(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 100),
              style: GoogleFonts.cinzel(color: color, fontSize: 14, letterSpacing: 1),
              child: Text(widget.text)),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              height: 2,
              width: double.infinity,
              color: selected ? AppColors.gold : Colors.transparent),
          ])));
  }
}


import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/army_state.dart';
import '../services/game_data_service.dart';
import 'game_screen.dart';
import '../widgets/nav_btn.dart';
import '../widgets/unit_card.dart';
import 'new_army_screen.dart';
import '../game/models/game_state.dart';
import '../game/notifiers/game_notifier.dart';
import '../widgets/aetherra_dialog.dart';
import '../widgets/aetherra_text_field.dart';
import '../widgets/photo_crop_dialog.dart';
import '../app_theme.dart';
class GameSetupScreen extends StatefulWidget {
  const GameSetupScreen({super.key});
  @override
  State<GameSetupScreen> createState() => _GameSetupScreenState();
}

class _GameSetupScreenState extends State<GameSetupScreen> {
  static const gold  = AppColors.gold;
    static const grey  = AppColors.grey;

  // Step tracking
  int _step = 0; // 0=army, 1=role, 2=confirm

  // Loaded armies
  List<Map<String, dynamic>> _armies = [];
  bool _loadingArmies = true;

  // Saved games
  List<Map<String, dynamic>> _saves = [];
  bool _loadingSaves = true;

  // Selected army data
  List<ArmyUnit> _armyUnits = [];
  List<String>   _groups    = [];
  String         _armyName  = '';

  // Selected army metadata
  String? _armyListId;
  String? _armyBgColor;
  String? _armyImageB64;
  String? _armyLore;

  // Role & colors
  PlayerRole _role        = PlayerRole.player;
  Color      _playerColor = const Color(0xFF4080D4); // blue
  Color      _enemyColor  = const Color(0xFFD44040); // red
  int        _enemyCount  = 5;
  String     _saveName    = '';

  static const _colorOptions = [
    {'label': 'Red',     'color': Color(0xFFD44040)},
    {'label': 'Blue',    'color': Color(0xFF4080D4)},
    {'label': 'Green',   'color': Color(0xFF50A860)},
    {'label': 'Purple',  'color': Color(0xFF9050D0)},
    {'label': 'Orange',  'color': Color(0xFFD47030)},
    {'label': 'Cyan',    'color': Color(0xFF30B8C8)},
    {'label': 'Pink',    'color': Color(0xFFD050A0)},
    {'label': 'Lime',    'color': Color(0xFF80C030)},
  ];

  @override
  void initState() { super.initState(); _loadArmies(); _loadSaves(); }

  Future<void> _loadArmies() async {
    try {
      final uid  = Supabase.instance.client.auth.currentUser!.id;
      final data = await Supabase.instance.client
        .from('army_lists')
        .select('id, name, army_data, updated_at')
        .eq('user_id', uid)
        .order('updated_at', ascending: false);
      if (mounted) {
        setState(() {
        _armies = List<Map<String,dynamic>>.from(data);
        _loadingArmies = false;
      });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingArmies = false);
    }
  }

  Future<void> _loadSaves() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser!.id;
      final data = await Supabase.instance.client
        .from('game_sessions')
        .select('id, name, game_data, updated_at')
        .eq('user_id', uid)
        .order('updated_at', ascending: false);
      if (mounted) {
        setState(() {
        _saves = List<Map<String,dynamic>>.from(data);
        _loadingSaves = false;
      });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSaves = false);
    }
  }

  Future<void> _deleteSave(Map<String, dynamic> save) async {
    final confirm = await showAetherraSheet<bool>(context,
      title: 'Delete Save?',
      body: Text('Delete "${save['name']}"? This cannot be undone.',
        style: GoogleFonts.cinzel(color: grey, fontSize: 13, height: 1.5)),
      actions: [
        SheetAction('Cancel', grey,               () => Navigator.pop(context, false), outlined: true),
        SheetAction('Delete', Colors.red, () => Navigator.pop(context, true)),
      ]);
    if (confirm != true) return;
    try {
      await Supabase.instance.client
        .from('game_sessions')
        .delete()
        .eq('id', save['id'] as String);
      if (mounted) setState(() => _saves.remove(save));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.dark,
          content: Text('Could not delete save. Please try again.',
            style: GoogleFonts.cinzel(color: Colors.red))));
      }
    }
  }

  void _selectArmy(Map<String, dynamic> army) {
    final raw = army['army_data'];
    final ad  = raw is String ? jsonDecode(raw) : raw as Map<String,dynamic>;

    // Restore units
    final units = <ArmyUnit>[];
    final unitsList = ad['units'] as List? ?? [];
    for (final u in unitsList) {
      final uid   = u['unitId'] as String;
      final gu    = GameDataService.toGameUnit(uid);
      if (gu == null) continue;
      final inst  = ArmyUnit(iid: u['iid'] ?? uid, unit: gu);
      inst.customName  = u['name']  as String? ?? '';
      inst.groupName   = u['group'] as String? ?? '';
      inst.photoBase64 = u['photo']   as String?;
      inst.bgColor     = u['bgColor'] as String?;
      inst.lore        = u['lore']   as String?;
      units.add(inst);
    }

    setState(() {
      _armyUnits    = units;
      _armyName     = army['name'] as String? ?? 'Army';
      _saveName     = army['name'] as String? ?? 'Game';
      _groups       = (ad['groups'] as List? ?? []).cast<String>();
      _armyListId   = army['id']       as String?;
      _armyBgColor  = ad['bg_color']   as String?;
      _armyImageB64 = ad['image_b64'] as String?;
      _armyLore     = ad['lore']       as String?;
      _step         = 1;
    });
  }

  Future<void> _startGame() async {
    final name = _saveName.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red.withValues(alpha: 0.9),
        content: Text('Enter a game name.',
          style: GoogleFonts.cinzel(color: Colors.white))));
      return;
    }
    // Check duplicate name
    final duplicate = _saves.any((s) =>
      (s['name'] as String).toLowerCase() == name.toLowerCase());
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red.withValues(alpha: 0.9),
        content: Text('A save with this name already exists.',
          style: GoogleFonts.cinzel(color: Colors.white))));
      return;
    }
    final notifier = context.read<GameNotifier>();
    notifier.startGame(
      armyUnits:      _armyUnits,
      groups:         _groups,
      role:           _role,
      playerColor:    '#${(_playerColor.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
      enemyColor:     '#${(_enemyColor.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
      armyName:       _armyName,
      enemyUnitCount: _role == PlayerRole.gamemaster ? _enemyCount : 0,
      saveName:       name,
      armyBgColor:    _armyBgColor,
      armyImageB64:   _armyImageB64,
      armyLore:       _armyLore,
      armyListId:     _armyListId,
    );
    Navigator.pushReplacement(context,
      MaterialPageRoute(builder: (_) => const GameScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        leading: NavBtn(
          icon: _step == 0 ? Icons.home_outlined : Icons.arrow_back_ios_new,
          onPressed: () {
            if (_step == 0) {
              Navigator.pop(context);
            } else {
              setState(() => _step = _step == 10 ? 0 : _step == 1 ? 10 : _step - 1);
            }
          }),
        title: Text(
          _step == 0 ? 'Game Mode'
          : _step == 10 ? 'Select Your Army'
          : _step == 1 ? _armyName
          : 'Ready to Play',
          style: GoogleFonts.cinzel(color: gold, fontSize: 16, letterSpacing: 2),
          textAlign: TextAlign.center),
        actions: _step == 1 ? [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text('${_armyUnits.length} units',
              style: GoogleFonts.cinzel(color: grey, fontSize: 13)))),
        ] : null,
      ),
      body: _step == 0 ? _armyStep()
          : _step == 10 ? _armyPickerStep()
          : _step == 1 ? _setupStep()
          : const SizedBox(),
    );
  }

  void _continueGame(Map<String, dynamic> sv) {
    final notifier = context.read<GameNotifier>();
    notifier.loadGame(sv);
    Navigator.pushReplacement(context,
      MaterialPageRoute(builder: (_) => const GameScreen()));
  }

  // ── STEP 0: Landing ─────────────────────────────────────────────
  Widget _armyStep() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
        child: Center(child: FractionallySizedBox(
          widthFactor: 0.38,
          child: SizedBox(
            height: 58,
            child: PressBtn(
              label: 'NEW GAME',
              centered: true,
              fontSize: 18,
              padding: const EdgeInsets.symmetric(vertical: 0),
              onTap: () => setState(() => _step = 10)))))),
      Expanded(child: Stack(children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── CONTINUE SAVED GAME ───────────────────────────────────
            if (_loadingSaves)
              const Center(child: CircularProgressIndicator(color: gold))
            else if (_saves.isNotEmpty) ...[
              const SizedBox(height: 24),
              Align(alignment: Alignment.centerLeft,
                child: Container(height: 1, width: 48,
                  color: gold.withValues(alpha: 0.35))),
              const SizedBox(height: 16),
              _sectionHeader('CONTINUE SAVED GAME', Icons.play_circle_outline),
              const SizedBox(height: 8),
              for (final sv in _saves) _SaveRow(
                save: sv,
                armyData: _matchArmy(sv),
                onContinue: () => _continueGame(sv),
                onDelete: () => _deleteSave(sv),
              ),
            ],
          ]),
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
    ]);
  }

  // ── STEP 10: Army picker (new game flow) ─────────────────────────
  Widget _armyPickerStep() {
    return Column(children: [
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
                _loadArmies();
              }))))),
      Expanded(child: Stack(children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          children: [
            if (_loadingArmies)
              const Center(child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(color: gold)))
            else if (_armies.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                color: AppColors.dark,
                child: Text('No saved armies. Create one in Army Builder first.',
                  style: GoogleFonts.cinzel(color: grey, fontSize: 12)))
            else
              ..._armies.map((a) => _ArmyRow(
                army: a,
                onTap: () { _selectArmy(a); setState(() => _step = 1); })),
          ]),
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
    ]);
  }
  Widget _sectionHeader(String label, IconData icon) => Row(children: [
    Icon(icon, color: gold.withValues(alpha: 0.85), size: 24),
    const SizedBox(width: 10),
    Text(label, style: GoogleFonts.cinzel(
      color: gold.withValues(alpha: 0.85), fontSize: 15, letterSpacing: 2,
      fontWeight: FontWeight.w600)),
  ]);

  // ── STEP 1: Role & color setup ────────────────────────────────────
  Widget _setupStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Role
        Text('YOUR ROLE', style: GoogleFonts.cinzel(
          color: grey, fontSize: 11, letterSpacing: 2)),
        const SizedBox(height: 8),
        Row(children: [
          _roleBtn('Player', PlayerRole.player, Icons.person_outline),
          const SizedBox(width: 10),
          _roleBtn('Game Master', PlayerRole.gamemaster, Icons.manage_accounts_outlined),
        ]),
        const SizedBox(height: 20),

        // Player color
        Text('YOUR COLOR', style: GoogleFonts.cinzel(
          color: grey, fontSize: 11, letterSpacing: 2)),
        const SizedBox(height: 8),
        _colorRow(_playerColor, (c) => setState(() => _playerColor = c),
          exclude: _enemyColor),
        const SizedBox(height: 20),

        // Enemy color
        Text('ENEMY COLOR', style: GoogleFonts.cinzel(
          color: grey, fontSize: 11, letterSpacing: 2)),
        const SizedBox(height: 8),
        _colorRow(_enemyColor, (c) => setState(() => _enemyColor = c),
          exclude: _playerColor),
        const SizedBox(height: 20),

        // Enemy count (GM only)
        if (_role == PlayerRole.gamemaster) ...[
          Text('ENEMY UNITS', style: GoogleFonts.cinzel(
            color: grey, fontSize: 11, letterSpacing: 2)),
          const SizedBox(height: 8),
          Row(children: [
            _adj(() => setState(() => _enemyCount = (_enemyCount-1).clamp(1,30)),
              Icons.remove),
            const SizedBox(width: 16),
            Text('$_enemyCount', style: GoogleFonts.cinzel(
              color: gold, fontSize: 22)),
            const SizedBox(width: 16),
            _adj(() => setState(() => _enemyCount = (_enemyCount+1).clamp(1,30)),
              Icons.add),
          ]),
          const SizedBox(height: 20),
        ],

        // Save name
        Text('GAME NAME', style: GoogleFonts.cinzel(
          color: grey, fontSize: 11, letterSpacing: 2)),
        const SizedBox(height: 8),
        AetherraTextField(
          style: GoogleFonts.cinzel(color: gold, fontSize: 14),
          onChanged: (v) => _saveName = v,
          hintText: 'E.g. Battle of the North…',
          hintStyle: TextStyle(color: grey.withValues(alpha: 0.5)),
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12)),
        const SizedBox(height: 20),
        // Start button
        Center(child: FractionallySizedBox(
          widthFactor: 0.38,
          child: SizedBox(
            height: 58,
            child: PressBtn(
              label: 'START GAME',
              centered: true, fontSize: 18,
              padding: EdgeInsets.zero,
              onTap: _startGame)))),
      ]));
  }

  Widget _roleBtn(String label, PlayerRole role, IconData icon) =>
    Expanded(child: _RoleBtn(
      label: label, role: role, icon: icon,
      selected: _role == role,
      onTap: () => setState(() => _role = role)));

  Widget _colorRow(Color selected, void Function(Color) onSelect, {required Color exclude}) =>
    Wrap(spacing: 8, runSpacing: 8,
      children: _colorOptions.map<Widget>((o) {
        final c       = o['color'] as Color;
        final active  = selected == c;
        final blocked = c == exclude;
        return _ColorDot(
          color: c, active: active, blocked: blocked,
          onTap: blocked ? null : () => onSelect(c));
      }).toList());

  Widget _adj(VoidCallback onTap, IconData icon) => _AdjBtn(onTap: onTap, icon: icon);

  Map<String, dynamic>? _matchArmy(Map<String, dynamic> sv) {
    final raw  = sv['game_data'];
    final data = raw is String
        ? (jsonDecode(raw) as Map<String, dynamic>)
        : (raw as Map<String, dynamic>? ?? {});
    final listId   = data['armyListId'] as String?;
    final armyName = data['armyName']   as String? ?? '';
    if (listId != null) {
      final m = _armies.where((a) => a['id'] == listId).firstOrNull;
      if (m != null) return m;
    }
    return _armies
        .where((a) => (a['name'] as String? ?? '') == armyName)
        .firstOrNull;
  }
}

class _TrashBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _TrashBtn({required this.onTap});
  @override State<_TrashBtn> createState() => _TrashBtnState();
}
class _TrashBtnState extends State<_TrashBtn> {
  bool _hovered = false;
  bool _pressed = false;
  @override Widget build(BuildContext context) =>
    MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown:   (_) => setState(() => _pressed = true),
        onTapUp:     (_) { setState(() => _pressed = false); onTap(); },
        onTapCancel: ()  => setState(() => _pressed = false),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: 24, height: 24,
            child: AnimatedScale(
              scale: _pressed ? 0.85 : _hovered ? 1.2 : 1.0,
              duration: const Duration(milliseconds: 100),
              child: Icon(Icons.delete_outline,
                color: Colors.red.withValues(alpha: _pressed ? 1.0 : _hovered ? 0.9 : 0.5),
                size: 20))))));
  VoidCallback get onTap => widget.onTap;
}

class _SaveRow extends StatefulWidget {
  final Map<String, dynamic> save;
  final Map<String, dynamic>? armyData; // matched army from army_lists
  final VoidCallback onContinue;
  final VoidCallback onDelete;
  const _SaveRow({
    required this.save, required this.onContinue, required this.onDelete,
    this.armyData,
  });
  @override State<_SaveRow> createState() => _SaveRowState();
}
class _SaveRowState extends State<_SaveRow> {
  bool _hovered       = false;
  bool _pressed       = false;
  bool _loreExpanded  = false;
  bool _loreHovered   = false;
  bool _unitsExpanded = false;
  bool _unitsHovered  = false;
  bool _deleteHovered = false;
  Widget? _cachedImg;
  final List<Map<String, String>> _unitEntries = [];
  List<String> _groupOrder = [];
  static const gold = AppColors.gold;
  static const grey = AppColors.grey;
  static final _kIdentity = Matrix4.identity();
  String _armyName  = '';
  String _bgColor   = '#1E1A15';
  String _lore      = '';
  int _alivePts = 0;
  int _armyCost = 0;
  int _round    = 1;

  @override
  void initState() {
    super.initState();
    _parseGameData();
    _applyArmyData(widget.armyData);
  }

  @override
  void didUpdateWidget(_SaveRow old) {
    super.didUpdateWidget(old);
    if (widget.armyData != old.armyData) _applyArmyData(widget.armyData);
  }

  void _parseGameData() {
    final raw  = widget.save['game_data'];
    final data = raw is String
        ? (jsonDecode(raw) as Map<String, dynamic>)
        : (raw as Map<String, dynamic>? ?? {});
    _armyName = data['armyName'] as String? ?? '';

    // Compute alive / total pts directly from saved unit data
    int alive = 0, total = 0;
    for (final u in (data['units'] as List? ?? [])) {
      final savedCost = (u['cost'] as num?)?.toInt() ?? 0;
      final cost = savedCost > 0
          ? savedCost
          : ((GameDataService.unitById(u['unitId'] as String? ?? '')
                ?['cost'] as num?)?.toInt() ?? 0);
      if (cost == 0) continue;
      total += cost;
      final con = (u['currentCon'] as num?)?.toInt();
      if (con == null || con > 0) alive += cost; // null = old save without field, assume alive
    }
    _alivePts = alive;
    _armyCost = total;
    _round    = (data['round'] as num?)?.toInt() ?? 1;
  }

  void _applyArmyData(Map<String, dynamic>? army) {
    if (army == null) return;
    final ad  = army['army_data'] as Map<String, dynamic>? ?? {};
    final b64 = ad['image_b64'] as String?;
    _bgColor  = ad['bg_color']  as String? ?? '#1E1A15';
    _lore     = ad['lore']      as String? ?? '';
    if (b64 != null && b64.isNotEmpty) {
      _cachedImg = buildCroppedPhotoDisplay(b64, AppColors.bannerW, AppColors.bannerH);
    }
    _unitEntries.clear();
    for (final u in (ad['units'] as List?) ?? []) {
      final unit = GameDataService.toGameUnit(u['unitId'] as String? ?? '');
      if (unit == null) continue;
      final customName = u['name'] as String? ?? '';
      _unitEntries.add({
        'name':  customName.isNotEmpty ? customName : unit.name,
        'group': u['group'] as String? ?? '',
      });
    }
    _groupOrder = ((ad['groups'] as List?) ?? []).cast<String>();
  }


  String _fmt(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}.${dt.month}.${dt.year}  '
          '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    } catch (_) { return iso; }
  }

  @override Widget build(BuildContext context) {
    final gameName  = widget.save['name'] as String? ?? 'Save';
    final updatedAt = widget.save['updated_at'] as String? ?? '';
    final hasImg    = _cachedImg != null;
    final hasLore   = _lore.isNotEmpty;
    final bgColor   = AppColors.parseHex(_bgColor);

    return MouseRegion(
      onEnter:  (_) => setState(() => _hovered = true),
      onExit:   (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap:       widget.onContinue,
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
                color: _hovered ? gold : gold.withValues(alpha: 0.2),
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

              if (!hasImg) Positioned.fill(child: Center(child: Icon(
                Icons.sports_esports_outlined,
                color: gold.withValues(alpha: 0.08), size: 40))),

              Positioned.fill(child: IgnorePointer(
                child: DecoratedBox(decoration: BoxDecoration(
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
                              Text(gameName, overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.cinzel(
                                  color: gold, fontSize: 17, letterSpacing: 2,
                                  shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])),
                              if (_armyName.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(_armyName,
                                  style: GoogleFonts.cinzel(
                                    color: Colors.white54, fontSize: 12,
                                    shadows: const [Shadow(color: Colors.black87, blurRadius: 4)])),
                              ],
                            ])),
                          if (_armyCost > 0)
                            Column(crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('$_alivePts / $_armyCost pts',
                                  style: GoogleFonts.cinzel(
                                    color: gold, fontSize: 17,
                                    shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])),
                                const SizedBox(height: 2),
                                Text('Round $_round',
                                  style: GoogleFonts.cinzel(
                                    color: Colors.white54, fontSize: 11,
                                    shadows: const [Shadow(color: Colors.black87, blurRadius: 4)])),
                              ]),
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
                                  color: gold, size: 18,
                                  shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])))),
                          if (_unitEntries.isNotEmpty) ...[
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
                                    Text('${_unitEntries.length}',
                                      style: GoogleFonts.cinzel(
                                        color: gold, fontSize: 13,
                                        shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])),
                                    const SizedBox(width: 3),
                                    Icon(_unitsExpanded ? Icons.group : Icons.group_outlined,
                                      color: gold, size: 18,
                                      shadows: const [Shadow(color: Colors.black87, blurRadius: 6)]),
                                  ])))),
                          ],
                          const Spacer(),
                          Row(mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(_fmt(updatedAt),
                                style: GoogleFonts.cinzel(
                                  color: grey, fontSize: 10,
                                  shadows: const [Shadow(color: Colors.black54, blurRadius: 4)])),
                              const SizedBox(width: 6),
                              MouseRegion(
                                cursor: SystemMouseCursors.click,
                                onEnter: (_) => setState(() => _deleteHovered = true),
                                onExit:  (_) => setState(() => _deleteHovered = false),
                                child: GestureDetector(
                                  onTap: widget.onDelete,
                                  child: Icon(Icons.delete_outline,
                                    color: Colors.red.withValues(alpha: _deleteHovered ? 0.9 : 0.55),
                                    size: 18,
                                    shadows: const [Shadow(color: Colors.black87, blurRadius: 4)]))),
                            ]),
                        ]),
                      ]))),

                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  child: _unitsExpanded && _unitEntries.isNotEmpty
                    ? BannerUnitsPanel(entries: _unitEntries, groupOrder: _groupOrder)
                    : const SizedBox.shrink()),

                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  child: hasLore && _loreExpanded
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                        child: Text(_lore,
                          style: GoogleFonts.cinzel(
                            color: Colors.white70, fontSize: 13, height: 1.6,
                            fontStyle: FontStyle.italic,
                            shadows: const [Shadow(color: Colors.black87, blurRadius: 8)])))
                    : const SizedBox.shrink()),
              ]),
            ])))));
  }
}

class _ArmyRow extends StatefulWidget {
  final Map<String, dynamic> army;
  final VoidCallback onTap;
  const _ArmyRow({required this.army, required this.onTap});
  @override State<_ArmyRow> createState() => _ArmyRowState();
}

class _ArmyRowState extends State<_ArmyRow> {
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
    final ad       = widget.army['army_data'] as Map<String, dynamic>? ?? {};
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
    final l           = widget.army;
    final name        = l['name'] as String? ?? 'Untitled';
    final pts         = l['total_points'] as int? ?? 0;
    final ad          = l['army_data'] as Map<String, dynamic>? ?? {};
    final units       = (ad['units'] as List?)?.length ?? 0;
    final limit       = ad['limit'] as int? ?? 2500;
    final over        = pts > limit;
    final creatorName = ad['creator_name'] as String?;
    final lore        = ad['lore']  as String?;
    final hasLore     = lore != null && lore.isNotEmpty;
    final bgColor     = AppColors.parseHex(ad['bg_color'] as String? ?? '#1E1A15');
    final hasImg      = _cachedImg != null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
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
                                Text(creatorName,
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

                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  child: _unitsExpanded && _unitEntries.isNotEmpty
                    ? BannerUnitsPanel(entries: _unitEntries, groupOrder: _groupOrder)
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
                            shadows: const [Shadow(color: Colors.black87, blurRadius: 8)])))
                    : const SizedBox.shrink()),
              ]),
            ])))));
  }
}

class _RoleBtn extends StatefulWidget {
  final String label;
  final dynamic role;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _RoleBtn({required this.label, required this.role, required this.icon,
    required this.selected, required this.onTap});
  @override State<_RoleBtn> createState() => _RoleBtnState();
}
class _RoleBtnState extends State<_RoleBtn> {
  bool _hovered = false;
  bool _pressed = false;
  static const gold = AppColors.gold;
  static const grey = AppColors.grey;
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
          duration: const Duration(milliseconds: 100),
          transform: _pressed ? (Matrix4.identity()..scaleByDouble(0.96, 0.96, 1.0, 1.0)) : Matrix4.identity(),
          transformAlignment: Alignment.center,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: widget.selected || _hovered
              ? gold.withValues(alpha: 0.08) : Colors.transparent,
            border: Border.all(
              color: widget.selected || _hovered ? gold : gold.withValues(alpha: 0.3))),
          child: Column(children: [
            Icon(widget.icon,
              color: widget.selected || _hovered ? gold : grey, size: 24),
            const SizedBox(height: 6),
            Text(widget.label, style: GoogleFonts.cinzel(
              color: widget.selected || _hovered ? gold : grey, fontSize: 12)),
          ]))));
}

// ── Colour dot with hover + blocked state ────────────────────────────────────
class _ColorDot extends StatefulWidget {
  final Color color;
  final bool active, blocked;
  final VoidCallback? onTap;
  const _ColorDot({required this.color, required this.active,
    required this.blocked, required this.onTap});
  @override State<_ColorDot> createState() => _ColorDotState();
}
class _ColorDotState extends State<_ColorDot> {
  bool _hovered = false;
  @override Widget build(BuildContext context) {
    final blocked = widget.blocked;
    final active  = widget.active;
    return MouseRegion(
      onEnter: (_) { if (!blocked) setState(() => _hovered = true); },
      onExit:  (_) => setState(() => _hovered = false),
      cursor: blocked ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered && !blocked ? 1.15 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: blocked
                ? widget.color.withValues(alpha: 0.25)
                : widget.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: active ? Colors.white
                  : _hovered ? Colors.white.withValues(alpha: 0.7)
                  : Colors.transparent,
                width: 2)),
            child: blocked
              ? Icon(Icons.block, color: Colors.white.withValues(alpha: 0.4), size: 16)
              : active
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : null))));
  }
}

// ── +/- button with Sort-style hover/press ───────────────────────────────────
class _AdjBtn extends StatefulWidget {
  final VoidCallback onTap;
  final IconData icon;
  const _AdjBtn({required this.onTap, required this.icon});
  @override State<_AdjBtn> createState() => _AdjBtnState();
}
class _AdjBtnState extends State<_AdjBtn> {
  bool _hovered = false;
  bool _pressed = false;
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
          transform: _pressed ? (Matrix4.identity()..scaleByDouble(0.88, 0.88, 1.0, 1.0)) : Matrix4.identity(),
          transformAlignment: Alignment.center,
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: _hovered ? gold.withValues(alpha: 0.12) : Colors.transparent,
            border: Border.all(color: _hovered ? gold : gold.withValues(alpha: 0.4))),
          child: Icon(widget.icon,
            color: _hovered ? gold : gold.withValues(alpha: 0.7), size: 20))));
}




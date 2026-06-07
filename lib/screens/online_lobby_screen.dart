import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_theme.dart';
import '../models/army_state.dart';
import '../game/online/online_game_manager.dart';
import '../services/game_data_service.dart';
import '../widgets/nav_btn.dart';
import 'online_game_screen.dart';

class OnlineLobbyScreen extends StatefulWidget {
  const OnlineLobbyScreen({super.key});
  @override State<OnlineLobbyScreen> createState() => _OnlineLobbyScreenState();
}

class _OnlineLobbyScreenState extends State<OnlineLobbyScreen> {
  static const gold = AppColors.gold;
  static const dark = AppColors.dark;

  // Steps: 'home' | 'create_army' | 'create_waiting' | 'join_code' | 'join_army'
  String _step = 'home';

  // Army list
  List<Map<String, dynamic>> _armies      = [];
  bool                       _loadingArmies = true;

  // Selected army for this player
  List<ArmyUnit> _armyUnits     = [];
  String         _armyName      = '';
  String         _armyBgColor   = '#1E1A15';
  String?        _armyImageB64;
  String         _playerColor   = '#C9A84C';

  // Join flow
  final _codeCtrl = TextEditingController();
  String _codeError = '';

  // Manager
  late final OnlineGameManager _manager;
  bool _navigatedToGame = false;
  bool _creating = false;
  bool _joining  = false;

  @override
  void initState() {
    super.initState();
    _manager = OnlineGameManager();
    _manager.addListener(_onManagerChange);
    _loadArmies();
  }

  @override
  void dispose() {
    _manager.removeListener(_onManagerChange);
    _codeCtrl.dispose();
    super.dispose();
  }

  void _onManagerChange() {
    if (!mounted) return;
    // Navigate to game when opponent connects (host) or when we just joined (guest)
    if (_manager.gameActive && !_navigatedToGame) {
      _navigatedToGame = true;
      Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => OnlineGameScreen(manager: _manager)));
    }
    setState(() {});
  }

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
          _armies        = List<Map<String, dynamic>>.from(data as List);
          _loadingArmies = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingArmies = false);
    }
  }

  void _selectArmy(Map<String, dynamic> army) {
    final raw = army['army_data'];
    final ad  = raw is String ? jsonDecode(raw) as Map<String, dynamic>
                               : raw as Map<String, dynamic>;
    final units = <ArmyUnit>[];
    for (final u in (ad['units'] as List? ?? [])) {
      final uid2 = u['unitId'] as String;
      final gu   = GameDataService.toGameUnit(uid2);
      if (gu == null) continue;
      final inst = ArmyUnit(iid: u['iid'] ?? uid2, unit: gu)
        ..customName  = u['name']    as String? ?? ''
        ..groupName   = u['group']   as String? ?? ''
        ..photoBase64 = u['photo']   as String?
        ..bgColor     = u['bgColor'] as String?
        ..lore        = u['lore']    as String?;
      units.add(inst);
    }
    setState(() {
      _armyUnits   = units;
      _armyName    = army['name'] as String? ?? 'Army';
      _armyBgColor = (ad['bg_color'] as String?) ?? '#1E1A15';
      _armyImageB64 = ad['image_b64'] as String?;
    });
  }

  // ── Color picker for token color ─────────────────────────────────────────
  static const _colorOptions = [
    Color(0xFFC9A84C), // gold
    Color(0xFF4080D4), // blue
    Color(0xFFD44040), // red
    Color(0xFF50A860), // green
    Color(0xFF9050D0), // purple
    Color(0xFFD47030), // orange
    Color(0xFF30B8C8), // cyan
    Color(0xFFD050A0), // pink
  ];

  String _colorToHex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: dark,
    appBar: AppBar(
      backgroundColor: dark,
      leading: NavBtn(
        icon: Icons.arrow_back,
        onPressed: () {
          if (_step == 'home') {
            Navigator.pop(context);
          } else if (_step == 'create_waiting') {
            // Leave waiting; don't destroy manager, just go back
            setState(() { _step = 'home'; _navigatedToGame = false; });
          } else {
            setState(() => _step = 'home');
          }
        }),
      title: Text('Online Battle',
          style: GoogleFonts.cinzel(color: gold, fontSize: 15, letterSpacing: 1)),
    ),
    body: AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: _buildStep(),
    ));

  Widget _buildStep() {
    switch (_step) {
      case 'create_army':
        return _ArmyPickerStep(
          key: const ValueKey('create_army'),
          armies:        _armies,
          loading:       _loadingArmies,
          selectedName:  _armyUnits.isNotEmpty ? _armyName : null,
          colorOptions:  _colorOptions,
          playerColor:   _playerColor,
          onColorPicked: (c) => setState(() => _playerColor = _colorToHex(c)),
          onSelectArmy:  _selectArmy,
          onConfirm:     _armyUnits.isEmpty ? null : () => _createGame(),
          confirmLabel:  'Create Game',
          loading2:      _creating,
        );
      case 'create_waiting':
        return _WaitingStep(
          key:      const ValueKey('create_waiting'),
          roomCode: _manager.roomCode ?? '------',
          armyName: _armyName,
        );
      case 'join_code':
        return _EnterCodeStep(
          key:       const ValueKey('join_code'),
          ctrl:      _codeCtrl,
          error:     _codeError,
          loading:   _joining,
          onNext:    () => setState(() { _step = 'join_army'; _codeError = ''; }),
        );
      case 'join_army':
        return _ArmyPickerStep(
          key: const ValueKey('join_army'),
          armies:        _armies,
          loading:       _loadingArmies,
          selectedName:  _armyUnits.isNotEmpty ? _armyName : null,
          colorOptions:  _colorOptions,
          playerColor:   _playerColor,
          onColorPicked: (c) => setState(() => _playerColor = _colorToHex(c)),
          onSelectArmy:  _selectArmy,
          onConfirm:     _armyUnits.isEmpty ? null : () => _joinGame(),
          confirmLabel:  'Join Game',
          loading2:      _joining,
        );
      default: // 'home'
        return _HomeStep(
          key:       const ValueKey('home'),
          onCreate:  () => setState(() => _step = 'create_army'),
          onJoin:    () => setState(() => _step = 'join_code'),
        );
    }
  }

  // ── Create game ──────────────────────────────────────────────────────────
  Future<void> _createGame() async {
    if (_creating) return;
    setState(() => _creating = true);
    final code = await _manager.createGame(
      armyUnits:    _armyUnits,
      armyName:     _armyName,
      armyBgColor:  _armyBgColor,
      armyImageB64: _armyImageB64,
      playerColor:  _playerColor,
    );
    if (!mounted) return;
    if (code == null) {
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red.withValues(alpha: 0.9),
          content: Text('Could not create game. Check your connection.',
              style: GoogleFonts.cinzel(color: Colors.white))));
      return;
    }
    setState(() { _creating = false; _step = 'create_waiting'; });
  }

  // ── Join game ─────────────────────────────────────────────────────────────
  Future<void> _joinGame() async {
    if (_joining) return;
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _codeError = 'Room code must be 6 characters.');
      return;
    }
    setState(() => _joining = true);
    final ok = await _manager.joinGame(
      roomCode:     code,
      armyUnits:    _armyUnits,
      armyName:     _armyName,
      armyBgColor:  _armyBgColor,
      armyImageB64: _armyImageB64,
      playerColor:  _playerColor,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() { _joining = false; _codeError = 'Room not found or already full.'; _step = 'join_code'; });
      return;
    }
    setState(() => _joining = false);
    // _onManagerChange will detect gameActive = true and navigate
  }
}

// ── Home step ─────────────────────────────────────────────────────────────────
class _HomeStep extends StatelessWidget {
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  const _HomeStep({super.key, required this.onCreate, required this.onJoin});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(height: 1, width: 48,
          color: AppColors.gold.withValues(alpha: 0.5)),
      const SizedBox(height: 16),
      Text('Battle Mode',
          style: GoogleFonts.cinzel(
              color: AppColors.gold, fontSize: 26,
              fontWeight: FontWeight.w700, letterSpacing: 3)),
      const SizedBox(height: 8),
      Text('Challenge another commander to a real-time duel.',
          style: GoogleFonts.cinzel(
              color: AppColors.grey.withValues(alpha: 0.6),
              fontSize: 12, letterSpacing: 0.5)),
      const SizedBox(height: 40),
      _LobbyBtn(
          icon:     Icons.add_circle_outline,
          title:    'Create Game',
          subtitle: 'Generate a room code and wait for an opponent',
          onTap:    onCreate),
      const SizedBox(height: 16),
      _LobbyBtn(
          icon:     Icons.login,
          title:    'Join Game',
          subtitle: 'Enter a room code to join an existing battle',
          onTap:    onJoin),
    ]));
}

// ── Army picker step ──────────────────────────────────────────────────────────
class _ArmyPickerStep extends StatelessWidget {
  final List<Map<String, dynamic>> armies;
  final bool loading;
  final String? selectedName;
  final List<Color> colorOptions;
  final String playerColor;
  final void Function(Color) onColorPicked;
  final void Function(Map<String, dynamic>) onSelectArmy;
  final VoidCallback? onConfirm;
  final String confirmLabel;
  final bool loading2;

  const _ArmyPickerStep({
    super.key,
    required this.armies,
    required this.loading,
    required this.selectedName,
    required this.colorOptions,
    required this.playerColor,
    required this.onColorPicked,
    required this.onSelectArmy,
    required this.onConfirm,
    required this.confirmLabel,
    required this.loading2,
  });

  @override
  Widget build(BuildContext context) {
    final gold = AppColors.gold;
    final grey = AppColors.grey;
    return Column(children: [
      // Color picker
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Token Color',
              style: GoogleFonts.cinzel(color: grey, fontSize: 11, letterSpacing: 1)),
          const SizedBox(height: 8),
          Row(children: colorOptions.map((c) {
            final hex     = '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
            final selected = hex.toUpperCase() == playerColor.toUpperCase();
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onColorPicked(c),
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: selected ? Colors.white : Colors.transparent,
                        width: 2)),
                )));
          }).toList()),
        ])),

      Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 16),
          color: gold.withValues(alpha: 0.12)),

      // Army list
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text('Choose Your Army',
            style: GoogleFonts.cinzel(color: grey, fontSize: 11, letterSpacing: 1))),

      Expanded(child: loading
          ? Center(child: CircularProgressIndicator(
              strokeWidth: 1.5, color: gold.withValues(alpha: 0.5)))
          : armies.isEmpty
          ? Center(child: Text('No armies found. Create one first.',
                style: GoogleFonts.cinzel(color: grey, fontSize: 13)))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: armies.length,
              itemBuilder: (_, i) {
                final a    = armies[i];
                final name = a['name'] as String? ?? '—';
                final sel  = name == selectedName;
                return GestureDetector(
                  onTap: () => onSelectArmy(a),
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: sel
                          ? gold.withValues(alpha: 0.08)
                          : Colors.transparent,
                      border: Border.all(
                          color: sel
                              ? gold.withValues(alpha: 0.6)
                              : gold.withValues(alpha: 0.18))),
                    child: Row(children: [
                      Icon(sel ? Icons.check_circle : Icons.shield_outlined,
                          color: sel ? gold : grey, size: 18),
                      const SizedBox(width: 12),
                      Text(name,
                          style: GoogleFonts.cinzel(
                              color: sel ? gold : grey,
                              fontSize: 13)),
                    ])));
              })),

      // Confirm button
      Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16,
            MediaQuery.of(context).padding.bottom + 16),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onConfirm,
            style: ElevatedButton.styleFrom(
                backgroundColor: onConfirm != null ? gold : grey.withValues(alpha: 0.3),
                foregroundColor: AppColors.dark,
                shape: const RoundedRectangleBorder(),
                padding: const EdgeInsets.symmetric(vertical: 14)),
            child: loading2
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.dark))
                : Text(confirmLabel,
                    style: GoogleFonts.cinzel(
                        fontSize: 14, fontWeight: FontWeight.w600))),
        )),
    ]);
  }
}

// ── Waiting step ──────────────────────────────────────────────────────────────
class _WaitingStep extends StatefulWidget {
  final String roomCode;
  final String armyName;
  const _WaitingStep({super.key, required this.roomCode, required this.armyName});
  @override State<_WaitingStep> createState() => _WaitingStepState();
}

class _WaitingStepState extends State<_WaitingStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
  }

  @override void dispose() { _pulse.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      FadeTransition(
        opacity: Tween(begin: 0.4, end: 1.0).animate(_pulse),
        child: Icon(Icons.wifi_outlined,
            color: AppColors.gold, size: 48)),
      const SizedBox(height: 32),
      Text('Waiting for opponent…',
          style: GoogleFonts.cinzel(color: AppColors.grey, fontSize: 14)),
      const SizedBox(height: 32),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.5))),
        child: Column(children: [
          Text('ROOM CODE',
              style: GoogleFonts.cinzel(
                  color: AppColors.grey.withValues(alpha: 0.6),
                  fontSize: 10, letterSpacing: 2)),
          const SizedBox(height: 6),
          Text(widget.roomCode,
              style: GoogleFonts.cinzel(
                  color: AppColors.gold, fontSize: 32,
                  fontWeight: FontWeight.w700, letterSpacing: 8)),
        ])),
      const SizedBox(height: 16),
      TextButton.icon(
        onPressed: () {
          Clipboard.setData(ClipboardData(text: widget.roomCode));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              duration: const Duration(seconds: 1),
              backgroundColor: AppColors.dark,
              content: Text('Code copied!',
                  style: GoogleFonts.cinzel(color: AppColors.gold))));
        },
        icon: const Icon(Icons.copy, color: AppColors.grey, size: 16),
        label: Text('Copy code',
            style: GoogleFonts.cinzel(color: AppColors.grey, fontSize: 12))),
      const SizedBox(height: 12),
      Text('Share this code with your opponent',
          style: GoogleFonts.cinzel(
              color: AppColors.grey.withValues(alpha: 0.45),
              fontSize: 11)),
    ]));
}

// ── Enter code step ───────────────────────────────────────────────────────────
class _EnterCodeStep extends StatelessWidget {
  final TextEditingController ctrl;
  final String error;
  final bool loading;
  final VoidCallback onNext;
  const _EnterCodeStep({
    super.key,
    required this.ctrl,
    required this.error,
    required this.loading,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final gold = AppColors.gold;
    final grey = AppColors.grey;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 24),
        Text('Enter Room Code',
            style: GoogleFonts.cinzel(
                color: gold, fontSize: 20,
                fontWeight: FontWeight.w600, letterSpacing: 2)),
        const SizedBox(height: 8),
        Text('Ask your opponent for their 6-character code.',
            style: GoogleFonts.cinzel(
                color: grey.withValues(alpha: 0.55), fontSize: 12)),
        const SizedBox(height: 32),
        TextField(
          controller: ctrl,
          autofocus:   true,
          maxLength:   6,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
          ],
          style: GoogleFonts.cinzel(
              color: gold, fontSize: 24,
              fontWeight: FontWeight.w700, letterSpacing: 8),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            counterText: '',
            hintText:    '------',
            hintStyle: GoogleFonts.cinzel(
                color: grey.withValues(alpha: 0.25), fontSize: 24,
                letterSpacing: 8),
            enabledBorder:  OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(
                    color: gold.withValues(alpha: 0.4))),
            focusedBorder:  const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: AppColors.gold)),
            filled: true,
            fillColor: AppColors.dark,
          )),
        if (error.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(error, style: GoogleFonts.cinzel(
              color: Colors.red.shade300, fontSize: 12)),
        ],
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onNext,
            style: ElevatedButton.styleFrom(
                backgroundColor: gold,
                foregroundColor: AppColors.dark,
                shape: const RoundedRectangleBorder(),
                padding: const EdgeInsets.symmetric(vertical: 14)),
            child: Text('Next',
                style: GoogleFonts.cinzel(
                    fontSize: 14, fontWeight: FontWeight.w600)))),
      ]));
  }
}

// ── Lobby button ──────────────────────────────────────────────────────────────
class _LobbyBtn extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _LobbyBtn({
    required this.icon, required this.title,
    required this.subtitle, required this.onTap});
  @override State<_LobbyBtn> createState() => _LobbyBtnState();
}

class _LobbyBtnState extends State<_LobbyBtn> {
  bool _hovered = false;
  bool _pressed = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit:  (_) => setState(() => _hovered = false),
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTapDown:   (_) => setState(() => _pressed = true),
      onTapUp:     (_) { setState(() => _pressed = false); widget.onTap(); },
      onTapCancel: ()  => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        transform: _pressed
            ? (Matrix4.identity()..scaleByDouble(0.98, 0.98, 1.0, 1.0))
            : Matrix4.identity(),
        transformAlignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
            color: _hovered
                ? AppColors.gold.withValues(alpha: 0.06)
                : Colors.transparent,
            border: Border.all(
                color: _hovered
                    ? AppColors.gold.withValues(alpha: 0.7)
                    : AppColors.gold.withValues(alpha: 0.25))),
        child: Row(children: [
          Icon(widget.icon, color: AppColors.gold, size: 26),
          const SizedBox(width: 16),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, children: [
            Text(widget.title, style: GoogleFonts.cinzel(
                color: _hovered
                    ? AppColors.gold : AppColors.gold.withValues(alpha: 0.8),
                fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            const SizedBox(height: 2),
            Text(widget.subtitle, style: GoogleFonts.cinzel(
                color: AppColors.grey.withValues(alpha: _hovered ? 0.7 : 0.45),
                fontSize: 11)),
          ])),
          Icon(Icons.chevron_right,
              color: _hovered
                  ? AppColors.gold.withValues(alpha: 0.7)
                  : AppColors.gold.withValues(alpha: 0.2),
              size: 18),
        ]))));
}

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
import '../widgets/aetherra_dialog.dart';
import '../widgets/nav_btn.dart';
import '../widgets/photo_crop_dialog.dart';
import '../widgets/unit_card.dart' show BannerStat, BannerUnitsPanel;
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
  String         _armyName        = '';
  String?        _armyCreatorName;
  String         _armyBgColor     = '#1E1A15';
  String?        _armyImageB64;
  String?        _armyLore;
  final String         _playerColor     = '#C9A84C';

  // Join flow
  final _codeCtrl = TextEditingController();
  String _codeError = '';

  // Manager
  late final OnlineGameManager _manager;
  bool _navigatedToGame = false;
  bool _creating = false;
  bool _joining  = false;

  // Saved games
  List<SavedGameInfo> _savedGames   = [];
  bool                _loadingSaved = true;

  @override
  void initState() {
    super.initState();
    _manager = OnlineGameManager();
    _manager.addListener(_onManagerChange);
    _loadArmies();
    _loadSavedGames();
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

  Future<void> _loadSavedGames() async {
    final games = await OnlineGameManager.fetchSavedGames();
    if (mounted) setState(() { _savedGames = games; _loadingSaved = false; });
  }

  Future<void> _deleteGame(SavedGameInfo game) async {
    final confirm = await showAetherraSheet<bool>(context,
      title: 'End Saved Game?',
      body: Text(
        'This will permanently end the battle for both players.',
        style: GoogleFonts.cinzel(color: AppColors.grey, fontSize: 13, height: 1.5)),
      actions: [
        SheetAction('Cancel',   AppColors.grey,       () => Navigator.pop(context, false), outlined: true),
        SheetAction('End Game', Colors.red,  () => Navigator.pop(context, true)),
      ]);
    if (confirm != true) return;
    await OnlineGameManager.endSession(game.sessionId);
    _loadSavedGames();
  }

  Future<void> _continueGame(SavedGameInfo game) async {
    if (_joining) return;
    setState(() => _joining = true);
    final ok = await _manager.reconnect(game.roomCode);
    if (!mounted) return;
    if (!ok) {
      setState(() => _joining = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red.withValues(alpha: 0.9),
          content: Text('Could not resume game. It may have ended.',
              style: GoogleFonts.cinzel(color: Colors.white))));
      _loadSavedGames(); // refresh list
      return;
    }
    // _onManagerChange navigates once gameActive == true
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
      _armyUnits    = units;
      _armyName     = army['name'] as String? ?? 'Army';
      _armyCreatorName = ad['creator_name'] as String?;
      _armyBgColor     = (ad['bg_color'] as String?) ?? '#1E1A15';
      _armyImageB64    = ad['image_b64'] as String?;
      _armyLore        = ad['lore'] as String?;
    });
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: dark,
    appBar: AppBar(
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
          armies:       _armies,
          loading:      _loadingArmies,
          selectedName: _armyUnits.isNotEmpty ? _armyName : null,
          onSelectArmy: _selectArmy,
          onConfirm:    _armyUnits.isEmpty ? null : () => _createGame(),
          confirmLabel: 'Create Game',
          loading2:     _creating,
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
          onNext: () {
            final code = _codeCtrl.text.trim().toUpperCase();
            // If this code matches a saved game for this user, reconnect directly
            // instead of forcing them through army selection again.
            final saved = _savedGames.where((g) => g.roomCode == code).toList();
            if (saved.isNotEmpty) {
              _continueGame(saved.first);
              return;
            }
            setState(() { _step = 'join_army'; _codeError = ''; });
          },
        );
      case 'join_army':
        return _ArmyPickerStep(
          key: const ValueKey('join_army'),
          armies:       _armies,
          loading:      _loadingArmies,
          selectedName: _armyUnits.isNotEmpty ? _armyName : null,
          onSelectArmy: _selectArmy,
          onConfirm:    _armyUnits.isEmpty ? null : () => _joinGame(),
          confirmLabel: 'Join Game',
          loading2:     _joining,
        );
      default: // 'home'
        return _HomeStep(
          key:            const ValueKey('home'),
          onCreate:       () => setState(() => _step = 'create_army'),
          onJoin:         () => setState(() => _step = 'join_code'),
          savedGames:     _savedGames,
          loadingSaved:   _loadingSaved,
          onContinue:     _continueGame,
          onDelete:       _deleteGame,
          continueLoading: _joining,
        );
    }
  }

  // ── Create game ──────────────────────────────────────────────────────────
  Future<void> _createGame() async {
    if (_creating) return;
    setState(() => _creating = true);
    final code = await _manager.createGame(
      armyUnits:       _armyUnits,
      armyName:        _armyName,
      armyCreatorName: _armyCreatorName,
      armyBgColor:     _armyBgColor,
      armyImageB64:    _armyImageB64,
      armyLore:        _armyLore,
      playerColor:     _playerColor,
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
    // Navigate directly — OnlineGameScreen shows "Waiting for opponent" until guest joins
    _navigatedToGame = true;
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => OnlineGameScreen(manager: _manager)));
    }
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
      roomCode:        code,
      armyUnits:       _armyUnits,
      armyName:        _armyName,
      armyCreatorName: _armyCreatorName,
      armyBgColor:     _armyBgColor,
      armyImageB64:    _armyImageB64,
      armyLore:        _armyLore,
      playerColor:     _playerColor,
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
  final List<SavedGameInfo> savedGames;
  final bool loadingSaved;
  final void Function(SavedGameInfo) onContinue;
  final void Function(SavedGameInfo) onDelete;
  final bool continueLoading;

  const _HomeStep({
    super.key,
    required this.onCreate,
    required this.onJoin,
    required this.savedGames,
    required this.loadingSaved,
    required this.onContinue,
    required this.onDelete,
    required this.continueLoading,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(height: 1, width: 48,
          color: AppColors.gold.withValues(alpha: 0.35)),
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

      // ── Continue saved game section ────────────────────────────────────
      if (loadingSaved || savedGames.isNotEmpty) ...[
        const SizedBox(height: 40),
        Container(height: 1, width: 48,
            color: AppColors.gold.withValues(alpha: 0.35)),
        const SizedBox(height: 16),
        Row(children: [
          Icon(Icons.play_circle_outline,
              color: AppColors.gold.withValues(alpha: 0.85), size: 24),
          const SizedBox(width: 10),
          Text('CONTINUE SAVED GAME',
              style: GoogleFonts.cinzel(
                  color: AppColors.gold.withValues(alpha: 0.85),
                  fontSize: 15, letterSpacing: 2,
                  fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 12),
        if (loadingSaved)
          Center(child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: AppColors.gold.withValues(alpha: 0.5))))
        else
          ...savedGames.map((g) => _OnlineSaveCard(
            key:      ValueKey(g.sessionId),
            game:     g,
            loading:  continueLoading,
            onTap:    () => onContinue(g),
            onDelete: () => onDelete(g))),
      ],
    ]));
}

// ── Online saved game banner card (mirrors offline _SaveRow) ─────────────────
class _OnlineSaveCard extends StatefulWidget {
  final SavedGameInfo game;
  final bool          loading;
  final VoidCallback  onTap;
  final VoidCallback  onDelete;
  const _OnlineSaveCard({
    super.key,
    required this.game,
    required this.loading,
    required this.onTap,
    required this.onDelete,
  });
  @override State<_OnlineSaveCard> createState() => _OnlineSaveCardState();
}

class _OnlineSaveCardState extends State<_OnlineSaveCard> {
  static const gold = AppColors.gold;
  static const grey = AppColors.grey;
  static final _kIdentity = Matrix4.identity();

  bool _hovered       = false;
  bool _pressed       = false;
  bool _loreExpanded  = false;
  bool _loreHovered   = false;
  bool _unitsExpanded = false;
  bool _unitsHovered  = false;
  bool _deleteHovered = false;

  Widget? _cachedImg;

  @override
  void initState() {
    super.initState();
    final b64 = widget.game.myImageB64;
    if (b64 != null && b64.isNotEmpty) {
      try {
        _cachedImg = buildCroppedPhotoDisplay(b64, AppColors.bannerW, AppColors.bannerH);
      } catch (_) {}
    }
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '';
    final d = dt.toLocal();
    return '${d.day}.${d.month}.${d.year}  '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final g        = widget.game;
    final hasImg   = _cachedImg != null;
    final hasLore  = g.myLore.isNotEmpty;
    final hasUnits = g.myUnitEntries.isNotEmpty;
    final bgColor  = AppColors.parseHex(g.myBgColor);
    final opp      = g.opponentArmyName;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap:       widget.loading ? null : widget.onTap,
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

              // Banner image
              if (hasImg) Positioned(
                top: 0, left: 0, right: 0, height: 115,
                child: ClipRect(child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0,
                      end: (_loreExpanded || _unitsExpanded) ? -40.0 : 0.0),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  builder: (_, dy, child) =>
                      Transform.translate(offset: Offset(0, dy), child: child),
                  child: Center(child: _cachedImg!)))),

              if (!hasImg) Positioned.fill(child: Center(child: Icon(
                Icons.wifi_outlined,
                color: gold.withValues(alpha: 0.06), size: 40))),

              // Gradient overlay
              Positioned.fill(child: IgnorePointer(child: DecoratedBox(
                decoration: BoxDecoration(gradient: LinearGradient(
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

                        // Top row: army name + pts/round
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                g.myArmyName.isNotEmpty ? g.myArmyName : g.roomCode,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.cinzel(
                                  color: gold, fontSize: 17, letterSpacing: 2,
                                  shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])),
                              if (g.myCreatorName != null && g.myCreatorName!.isNotEmpty) ...[
                                const SizedBox(height: 1),
                                Text(
                                  g.myCreatorName!,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.cinzel(
                                    color: Colors.white54, fontSize: 11,
                                    shadows: const [Shadow(color: Colors.black87, blurRadius: 4)])),
                              ],
                              const SizedBox(height: 2),
                              Text(
                                opp != null ? 'vs $opp' : 'Waiting for opponent',
                                style: GoogleFonts.cinzel(
                                  color: opp != null ? Colors.white : Colors.white38,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                  shadows: const [Shadow(color: Colors.black87, blurRadius: 4)])),
                            ])),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (g.myTotalPts > 0) ...[
                                Text('${g.myAlivePts} / ${g.myTotalPts} pts',
                                  style: GoogleFonts.cinzel(
                                    color: gold, fontSize: 17,
                                    shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])),
                                const SizedBox(height: 2),
                              ],
                              Text('Round ${g.round}',
                                style: GoogleFonts.cinzel(
                                  color: Colors.white54, fontSize: 11,
                                  shadows: const [Shadow(color: Colors.black87, blurRadius: 4)])),
                            ]),
                        ]),

                        // Bottom row: lore/units icons + time + delete
                        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                          // Lore icon
                          GestureDetector(
                            onTap: hasLore
                                ? () => setState(() => _loreExpanded = !_loreExpanded)
                                : null,
                            child: MouseRegion(
                              cursor: hasLore ? SystemMouseCursors.click : MouseCursor.defer,
                              onEnter: hasLore ? (_) => setState(() => _loreHovered = true)  : null,
                              onExit:  hasLore ? (_) => setState(() => _loreHovered = false) : null,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 80),
                                opacity: hasLore
                                    ? (_loreExpanded || _loreHovered ? 1.0 : 0.55) : 0.2,
                                child: Icon(
                                  _loreExpanded
                                      ? Icons.menu_book : Icons.menu_book_outlined,
                                  color: gold, size: 18,
                                  shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])))),
                          // Units icon
                          if (hasUnits) ...[
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
                                    Text('${g.myUnitEntries.length}',
                                      style: GoogleFonts.cinzel(
                                        color: gold, fontSize: 13,
                                        shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])),
                                    const SizedBox(width: 3),
                                    Icon(
                                      _unitsExpanded ? Icons.group : Icons.group_outlined,
                                      color: gold, size: 18,
                                      shadows: const [Shadow(color: Colors.black87, blurRadius: 6)]),
                                  ])))),
                          ],
                          const Spacer(),
                          // Room code + time + delete
                          Row(mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: g.roomCode));
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    backgroundColor: AppColors.dark,
                                    duration: const Duration(seconds: 1),
                                    content: Text('Code copied',
                                      style: GoogleFonts.cinzel(
                                        color: gold, fontSize: 12))));
                                },
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Text(g.roomCode,
                                      style: GoogleFonts.cinzel(
                                        color: gold.withValues(alpha: 0.75),
                                        fontSize: 11, letterSpacing: 2,
                                        shadows: const [Shadow(color: Colors.black87, blurRadius: 4)])),
                                    const SizedBox(width: 3),
                                    Icon(Icons.copy_outlined,
                                      color: gold.withValues(alpha: 0.5),
                                      size: 13,
                                      shadows: const [Shadow(color: Colors.black87, blurRadius: 4)]),
                                  ]))),
                              const SizedBox(width: 8),
                              Text(_fmt(g.updatedAt),
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
                                    color: Colors.red.withValues(
                                        alpha: _deleteHovered ? 0.9 : 0.55),
                                    size: 18,
                                    shadows: const [Shadow(color: Colors.black87, blurRadius: 4)]))),
                            ]),
                        ]),
                      ]))),

                // Units panel
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  child: _unitsExpanded && hasUnits
                      ? BannerUnitsPanel(entries: g.myUnitEntries)
                      : const SizedBox.shrink()),

                // Lore panel
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  child: hasLore && _loreExpanded
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                          child: Text(g.myLore,
                            style: GoogleFonts.cinzel(
                              color: Colors.white70, fontSize: 13, height: 1.6,
                              fontStyle: FontStyle.italic,
                              shadows: const [Shadow(color: Colors.black87, blurRadius: 8)])))
                      : const SizedBox.shrink()),
              ]),
            ])))));
  }
}

// ── Army picker step ──────────────────────────────────────────────────────────
class _ArmyPickerStep extends StatelessWidget {
  final List<Map<String, dynamic>> armies;
  final bool loading;
  final String? selectedName;
  final void Function(Map<String, dynamic>) onSelectArmy;
  final VoidCallback? onConfirm;
  final String confirmLabel;
  final bool loading2;

  const _ArmyPickerStep({
    super.key,
    required this.armies,
    required this.loading,
    required this.selectedName,
    required this.onSelectArmy,
    required this.onConfirm,
    required this.confirmLabel,
    required this.loading2,
  });

  @override
  Widget build(BuildContext context) {
    const gold = AppColors.gold;
    const grey = AppColors.grey;

    return Column(children: [
      // Label
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text('Choose Your Army',
            style: GoogleFonts.cinzel(color: grey, fontSize: 11, letterSpacing: 1))),

      Expanded(child: loading
          ? Center(child: CircularProgressIndicator(
              strokeWidth: 1.5, color: gold.withValues(alpha: 0.5)))
          : armies.isEmpty
          ? Center(child: Text('No armies found. Create one first.',
                style: GoogleFonts.cinzel(color: grey, fontSize: 13)))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              itemCount: armies.length,
              itemBuilder: (_, i) {
                final a    = armies[i];
                final name = a['name'] as String? ?? '—';
                final sel  = name == selectedName;
                return _LobbyArmyCard(
                  key:      ValueKey(name),
                  army:     a,
                  selected: sel,
                  onTap:    () => onSelectArmy(a),
                );
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

// ── Full army banner card for the lobby army picker ───────────────────────────
class _LobbyArmyCard extends StatefulWidget {
  final Map<String, dynamic> army;
  final bool selected;
  final VoidCallback onTap;
  const _LobbyArmyCard({super.key, required this.army, required this.selected, required this.onTap});
  @override State<_LobbyArmyCard> createState() => _LobbyArmyCardState();
}

class _LobbyArmyCardState extends State<_LobbyArmyCard> {
  bool _loreExpanded  = false;
  bool _loreHovered   = false;
  bool _unitsExpanded = false;
  bool _unitsHovered  = false;
  Widget? _cachedImg;
  int _atk = 0, _def = 0, _rng = 0, _mob = 0, _con = 0, _cp = 0;
  final List<Map<String, String>> _unitEntries = [];

  @override void initState() {
    super.initState();
    final raw = widget.army['army_data'];
    final ad  = raw is String ? jsonDecode(raw) as Map<String, dynamic>
                              : (raw as Map<String, dynamic>? ?? {});
    final imageB64 = ad['image_b64'] as String?;
    if (imageB64 != null && imageB64.isNotEmpty) {
      try { _cachedImg = buildCroppedPhotoDisplay(imageB64, AppColors.bannerW, AppColors.bannerH); }
      catch (_) {}
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
  }

  @override Widget build(BuildContext context) {
    final a           = widget.army;
    final name        = a['name'] as String? ?? '—';
    final raw         = a['army_data'];
    final ad          = raw is String ? jsonDecode(raw) as Map<String, dynamic>
                                      : (raw as Map<String, dynamic>? ?? {});
    final limit       = ad['limit'] as int? ?? 2500;
    // Compute live from GameDataService so costs are always current (stored
    // total_points can be 0 when army was saved before costs were populated).
    final pts = (ad['units'] as List? ?? []).fold<int>(0, (s, u) {
      final uid = (u as Map<String, dynamic>)['unitId'] as String? ?? '';
      return s + (GameDataService.toGameUnit(uid)?.cost ?? 0);
    });
    final creatorName = ad['creator_name'] as String?;
    final lore        = ad['lore'] as String?;
    final hasLore     = lore != null && lore.isNotEmpty;
    final bgColor     = AppColors.parseHex(ad['bg_color'] as String? ?? '#1E1A15');
    final sel         = widget.selected;
    const gold        = AppColors.gold;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(
            color: sel ? gold : gold.withValues(alpha: 0.25),
            width: sel ? 2.0 : 1.0)),
        child: Stack(clipBehavior: Clip.hardEdge, children: [
          if (_cachedImg != null)
            Positioned(top: 0, left: 0, right: 0, height: 115,
              child: ClipRect(child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0,
                    end: (_loreExpanded || _unitsExpanded) ? -40.0 : 0.0),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                builder: (_, dy, child) =>
                    Transform.translate(offset: Offset(0, dy), child: child),
                child: Center(child: _cachedImg!)))),
          Positioned.fill(child: IgnorePointer(child: DecoratedBox(
            decoration: BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              stops: const [0.0, 0.4, 1.0],
              colors: [
                Colors.black.withValues(alpha: 0.45),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.55),
              ]))))),
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
                          Text(name,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.cinzel(
                              color: gold, fontSize: 17, letterSpacing: 2,
                              shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])),
                          if (creatorName != null && creatorName.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(creatorName,
                              style: GoogleFonts.cinzel(
                                color: Colors.white54, fontSize: 12,
                                shadows: const [Shadow(color: Colors.black87, blurRadius: 4)])),
                          ],
                        ])),
                      Text('$pts / $limit pts',
                        style: GoogleFonts.cinzel(
                          color: pts > limit ? Colors.red : gold, fontSize: 17,
                          shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])),
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
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: _unitEntries.isNotEmpty
                            ? () => setState(() => _unitsExpanded = !_unitsExpanded) : null,
                        child: MouseRegion(
                          cursor: _unitEntries.isNotEmpty
                              ? SystemMouseCursors.click : MouseCursor.defer,
                          onEnter: _unitEntries.isNotEmpty
                              ? (_) => setState(() => _unitsHovered = true)  : null,
                          onExit:  _unitEntries.isNotEmpty
                              ? (_) => setState(() => _unitsHovered = false) : null,
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
                      const Spacer(),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        BannerStat('$_cp',  'CP'),
                        BannerStat('$_atk', 'ATK'),
                        BannerStat('$_def', 'DEF'),
                        BannerStat('$_rng', 'SHO'),
                        BannerStat('$_mob', 'MOB'),
                        BannerStat('$_con', 'STR'),
                      ]),
                    ]),
                  ]))),
            AnimatedSize(
              duration: const Duration(milliseconds: 260), curve: Curves.easeOut,
              child: _unitsExpanded && _unitEntries.isNotEmpty
                ? BannerUnitsPanel(entries: _unitEntries)
                : const SizedBox.shrink()),
            AnimatedSize(
              duration: const Duration(milliseconds: 260), curve: Curves.easeOut,
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
        ])));
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
        child: const Icon(Icons.wifi_outlined,
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
    const gold = AppColors.gold;
    const grey = AppColors.grey;
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
              color: Colors.red, fontSize: 12)),
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

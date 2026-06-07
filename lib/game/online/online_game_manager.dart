import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/game_state.dart';
import '../../models/army_state.dart';
import '../../services/game_data_service.dart';

// ── Role & pending action types ──────────────────────────────────────────────
enum OnlineRole { host, guest }
enum OnlinePendingType { reactive, nextRound }

// ── OnlineGameManager ────────────────────────────────────────────────────────
// Manages all state for an online game session. Communicates with Supabase
// Realtime to keep both players in sync.
//
// Token colors in the DB: 'host' and 'guest'.
// In UI we convert to 'player'/'enemy' from each player's perspective via
// [myPerspectiveBag].
class OnlineGameManager extends ChangeNotifier {
  static final _supabase = Supabase.instance.client;
  static final _rng = Random();

  // ── Session info ────────────────────────────────────────────────────────
  String? _sessionId;
  String? _roomCode;
  OnlineRole? _myRole;
  String? get sessionId    => _sessionId;
  String? get roomCode     => _roomCode;
  OnlineRole? get myRole   => _myRole;

  // ── Connection ──────────────────────────────────────────────────────────
  bool _opponentConnected = false;
  bool _gameActive        = false;
  bool _leaving           = false;
  bool get opponentConnected => _opponentConnected;
  bool get gameActive        => _gameActive;

  // ── Shared state ────────────────────────────────────────────────────────
  int     _round        = 1;
  TokenBag _tokenBag    = TokenBag();
  String? _activePlayer; // 'host', 'guest', or null (first draw is free)
  int get round          => _round;
  String? get activePlayer => _activePlayer;

  // ── Pending action ──────────────────────────────────────────────────────
  OnlinePendingType?    _pendingType;
  String?               _pendingFrom; // 'host' or 'guest' (who triggered it)
  Map<String, dynamic>? _pendingData;
  OnlinePendingType?    get pendingType => _pendingType;
  String?               get pendingFrom => _pendingFrom;
  Map<String, dynamic>? get pendingData => _pendingData;

  // ── My state ────────────────────────────────────────────────────────────
  List<GameUnit> _myUnits      = [];
  int            _myCP         = 0;
  int            _myInitialCP  = 0;
  List<int>      _myDiceRolls  = [];
  String         _myArmyName   = '';
  String         _myBgColor    = '#1E1A15';
  String?        _myImageB64;
  String         _myPlayerColor = '#C9A84C';

  List<GameUnit> get myUnits      => _myUnits;
  int            get myCP         => _myCP;
  int            get myInitialCP  => _myInitialCP;
  List<int>      get myDiceRolls  => _myDiceRolls;
  String         get myArmyName   => _myArmyName;
  String         get myBgColor    => _myBgColor;
  String?        get myImageB64   => _myImageB64;
  String         get myPlayerColor => _myPlayerColor;

  // ── Opponent state (read-only) ───────────────────────────────────────────
  List<GameUnit> _opponentUnits      = [];
  int            _opponentCP         = 0;
  String         _opponentArmyName   = '';
  String         _opponentBgColor    = '#1E1A15';
  String?        _opponentImageB64;
  String         _opponentPlayerColor = '#D48080';

  List<GameUnit> get opponentUnits      => _opponentUnits;
  int            get opponentCP         => _opponentCP;
  String         get opponentArmyName   => _opponentArmyName;
  String         get opponentBgColor    => _opponentBgColor;
  String?        get opponentImageB64   => _opponentImageB64;
  String         get opponentPlayerColor => _opponentPlayerColor;

  // ── Derived ─────────────────────────────────────────────────────────────
  // Can the local player draw a token right now?
  bool get canDraw {
    if (!_gameActive || _pendingType != null || _leaving) return false;
    if (_activePlayer == null) return true; // round start: first draw is free
    return _activePlayer == _myRole?.name;
  }

  // Token bag re-interpreted from my perspective:
  // 'host'/'guest' colors → 'player'/'enemy' so existing UI code works unchanged.
  TokenBag get myPerspectiveBag {
    final mine = _myRole == OnlineRole.host ? 'host' : 'guest';
    Token conv(Token t) => Token(
        id:    t.id,
        color: t.color == mine ? 'player' : 'enemy');
    return TokenBag(
      bag:       _tokenBag.bag.map(conv).toList(),
      drawn:     _tokenBag.drawn.map(conv).toList(),
      lastDrawn: _tokenBag.lastDrawn == null ? null : conv(_tokenBag.lastDrawn!),
    );
  }

  RealtimeChannel? _channel;
  Timer?           _debounce;

  // ── CREATE GAME (host) ───────────────────────────────────────────────────
  Future<String?> createGame({
    required List<ArmyUnit> armyUnits,
    required String armyName,
    required String armyBgColor,
    String? armyImageB64,
    required String playerColor,
  }) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return null;

    final code      = _genCode();
    final gameUnits = armyUnits.map(GameUnit.fromArmyUnit).toList();
    final initCP    = GameState.calcInitialCP(armyUnits);

    // Bag with only host tokens; guest tokens added when they join
    final hostTokens = gameUnits.where((u) => !u.isEliminated)
        .map((u) => Token(id: 'h_${u.instanceId}', color: 'host'))
        .toList()..shuffle(_rng);

    try {
      final res = await _supabase.from('online_game_sessions').insert({
        'room_code':   code,
        'host_id':     uid,
        'status':      'waiting',
        'host_state':  _playerStateJson(
            units: gameUnits, cp: initCP, initCP: initCP,
            armyName: armyName, armyBgColor: armyBgColor,
            armyImageB64: armyImageB64, playerColor: playerColor),
        'shared': {
          'round':         1,
          'tokenBag':      TokenBag(bag: hostTokens).toJson(),
          'activePlayer':  null,
          'pendingAction': null,
        },
      }).select('id').single();

      _sessionId    = res['id'] as String;
      _roomCode     = code;
      _myRole       = OnlineRole.host;
      _myUnits      = gameUnits;
      _myCP         = initCP;
      _myInitialCP  = initCP;
      _myArmyName   = armyName;
      _myBgColor    = armyBgColor;
      _myImageB64   = armyImageB64;
      _myPlayerColor = playerColor;
      _tokenBag     = TokenBag(bag: hostTokens);

      _subscribe();
      notifyListeners();
      return code;
    } catch (e) {
      debugPrint('OnlineGameManager.createGame: $e');
      return null;
    }
  }

  // ── JOIN GAME (guest) ────────────────────────────────────────────────────
  Future<bool> joinGame({
    required String roomCode,
    required List<ArmyUnit> armyUnits,
    required String armyName,
    required String armyBgColor,
    String? armyImageB64,
    required String playerColor,
  }) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return false;

    try {
      final rows = await _supabase
          .from('online_game_sessions')
          .select()
          .eq('room_code', roomCode.toUpperCase())
          .eq('status', 'waiting')
          .limit(1);
      if ((rows as List).isEmpty) return false;
      final row = (rows as List<dynamic>).first as Map<String, dynamic>;
      _sessionId = row['id'] as String;

      final gameUnits = armyUnits.map(GameUnit.fromArmyUnit).toList();
      final initCP    = GameState.calcInitialCP(armyUnits);

      // Merge guest tokens into existing host bag
      final existingShared = _parseJsonField(row['shared']) ?? <String, dynamic>{};
      final existingBagData = existingShared['tokenBag'];
      final existingBag = existingBagData != null
          ? TokenBag.fromJson(_parseJsonField(existingBagData)!)
          : TokenBag();
      final guestTokens = gameUnits.where((u) => !u.isEliminated)
          .map((u) => Token(id: 'g_${u.instanceId}', color: 'guest'))
          .toList();
      existingBag.bag.addAll(guestTokens);
      existingBag.bag.shuffle(_rng);

      await _supabase.from('online_game_sessions').update({
        'guest_id':    uid,
        'guest_state': _playerStateJson(
            units: gameUnits, cp: initCP, initCP: initCP,
            armyName: armyName, armyBgColor: armyBgColor,
            armyImageB64: armyImageB64, playerColor: playerColor),
        'shared': {
          ...existingShared,
          'tokenBag': existingBag.toJson(),
        },
        'status':      'playing',
        'updated_at':  DateTime.now().toIso8601String(),
      }).eq('id', _sessionId!);

      _roomCode      = roomCode.toUpperCase();
      _myRole        = OnlineRole.guest;
      _myUnits       = gameUnits;
      _myCP          = initCP;
      _myInitialCP   = initCP;
      _myArmyName    = armyName;
      _myBgColor     = armyBgColor;
      _myImageB64    = armyImageB64;
      _myPlayerColor = playerColor;
      _tokenBag      = existingBag;
      _gameActive    = true;
      _opponentConnected = true;
      _round         = (existingShared['round'] as num? ?? 1).toInt();

      // Load host's state
      final hostData = _parseJsonField(row['host_state']);
      if (hostData != null) _loadOpponentState(hostData);

      _subscribe();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('OnlineGameManager.joinGame: $e');
      return false;
    }
  }

  // ── RECONNECT ────────────────────────────────────────────────────────────
  Future<bool> reconnect(String roomCode) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      final rows = await _supabase
          .from('online_game_sessions')
          .select()
          .eq('room_code', roomCode.toUpperCase())
          .limit(1);
      if ((rows as List).isEmpty) return false;
      final row = (rows as List<dynamic>).first as Map<String, dynamic>;
      _sessionId = row['id'] as String;
      _roomCode  = roomCode.toUpperCase();
      _myRole    = (row['host_id'] as String?) == uid
          ? OnlineRole.host : OnlineRole.guest;
      _loadFullRow(row);
      _subscribe();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('OnlineGameManager.reconnect: $e');
      return false;
    }
  }

  void _loadFullRow(Map<String, dynamic> row) {
    final myKey  = _myRole == OnlineRole.host ? 'host_state' : 'guest_state';
    final oppKey = _myRole == OnlineRole.host ? 'guest_state' : 'host_state';

    final myData  = _parseJsonField(row[myKey]);
    final oppData = _parseJsonField(row[oppKey]);
    final shared  = _parseJsonField(row['shared']);

    if (myData  != null) _loadMyState(myData);
    if (oppData != null) _loadOpponentState(oppData);
    if (shared  != null) _loadSharedState(shared);

    _gameActive = (row['status'] as String?) == 'playing';
    _opponentConnected =
        row[_myRole == OnlineRole.host ? 'guest_id' : 'host_id'] != null;
  }

  // ── REALTIME ─────────────────────────────────────────────────────────────
  void _subscribe() {
    if (_sessionId == null) return;
    _channel?.unsubscribe();
    _channel = _supabase
        .channel('online-game-$_sessionId')
        .onPostgresChanges(
          event:  PostgresChangeEvent.update,
          schema: 'public',
          table:  'online_game_sessions',
          filter: PostgresChangeFilter(
            type:   PostgresChangeFilterType.eq,
            column: 'id',
            value:  _sessionId!,
          ),
          callback: (payload) => _onRemoteUpdate(payload.newRecord),
        )
        .subscribe();
  }

  void _onRemoteUpdate(Map<String, dynamic> row) {
    final oppKey   = _myRole == OnlineRole.host ? 'guest_state' : 'host_state';
    final prevRound = _round;

    // Update opponent state
    final oppData = _parseJsonField(row[oppKey]);
    if (oppData != null) _loadOpponentState(oppData);

    // Update shared state
    final shared = _parseJsonField(row['shared']);
    if (shared != null) _loadSharedState(shared);

    // Round advanced via opponent confirming next round: reset my units too
    if (_round > prevRound) {
      for (final u in _myUnits) { u.deactivate(); u.expanded = true; }
      _myDiceRolls.clear();
      _persistMyState();
    }

    // Detect guest joining (host sees status change to 'playing')
    final status = row['status'] as String?;
    if (status == 'playing' && !_gameActive) {
      _gameActive        = true;
      _opponentConnected = row[_myRole == OnlineRole.host ? 'guest_id' : 'host_id'] != null;
    }

    notifyListeners();
  }

  void _loadSharedState(Map<String, dynamic> s) {
    _round        = (s['round'] as num? ?? 1).toInt();
    final bagData = _parseJsonField(s['tokenBag']);
    if (bagData != null) _tokenBag = TokenBag.fromJson(bagData);
    _activePlayer = s['activePlayer'] as String?;

    final pending = _parseJsonField(s['pendingAction']);
    if (pending == null) {
      _pendingType = null;
      _pendingFrom = null;
      _pendingData = null;
    } else {
      _pendingType = OnlinePendingType.values
          .where((e) => e.name == pending['type'])
          .firstOrNull;
      _pendingFrom = pending['fromPlayer'] as String?;
      _pendingData = pending;
    }
  }

  void _loadMyState(Map<String, dynamic> s) {
    _myCP          = (s['commandPoints'] as num? ?? 0).toInt();
    _myInitialCP   = (s['initialCP']     as num? ?? 0).toInt();
    _myArmyName    = s['armyName']    as String? ?? '';
    _myBgColor     = s['armyBgColor'] as String? ?? '#1E1A15';
    _myImageB64    = s['armyImageB64'] as String?;
    _myPlayerColor = s['playerColor'] as String? ?? '#C9A84C';
    _myDiceRolls   = (s['roundDiceRolls'] as List? ?? [])
        .map((e) => (e as num).toInt()).toList();
    _myUnits       = _parseUnits(s['units'] as List? ?? []);
  }

  void _loadOpponentState(Map<String, dynamic> s) {
    if (s.isEmpty) return;
    _opponentCP          = (s['commandPoints'] as num? ?? 0).toInt();
    _opponentArmyName    = s['armyName']    as String? ?? '';
    _opponentBgColor     = s['armyBgColor'] as String? ?? '#1E1A15';
    _opponentImageB64    = s['armyImageB64'] as String?;
    _opponentPlayerColor = s['playerColor'] as String? ?? '#D48080';
    _opponentUnits       = _parseUnits(s['units'] as List? ?? []);
  }

  List<GameUnit> _parseUnits(List<dynamic> list) {
    final result = <GameUnit>[];
    for (final raw in list) {
      final u = raw as Map<String, dynamic>;
      final unitId = u['unitId'] as String? ?? '';
      final gu     = GameDataService.toGameUnit(unitId);
      if (gu == null) continue;
      final au = ArmyUnit(iid: u['instanceId'] as String? ?? unitId, unit: gu)
        ..customName  = u['name']    as String? ?? ''
        ..groupName   = u['groupName'] as String? ?? ''
        ..photoBase64 = u['photo']   as String?
        ..bgColor     = u['bgColor'] as String?
        ..lore        = u['lore']    as String?;
      result.add(GameUnit(
        instanceId:         u['instanceId']     as String? ?? unitId,
        armyUnit:           au,
        currentCon:         (u['currentCon']    as num? ?? gu.con).toInt(),
        activated:          u['activated']      as bool?   ?? false,
        expanded:           u['expanded']       as bool?   ?? true,
        groupName:          u['groupName']      as String? ?? '',
        eliminatedOnRound:  u['eliminatedOnRound'] as int?,
      ));
    }
    return result;
  }

  // ── DRAW TOKEN ───────────────────────────────────────────────────────────
  Future<void> drawToken() async {
    if (!canDraw) return;
    final t = _tokenBag.drawRandom();
    if (t == null) return;

    _activePlayer = t.color; // 'host' or 'guest'

    final myColor       = _myRole == OnlineRole.host ? 'host' : 'guest';
    final opponentRole  = _myRole == OnlineRole.host ? 'guest' : 'host';

    // Reactive activation: when I draw MY token and opponent has AP
    Map<String, dynamic>? pending;
    if (t.color == myColor && _opponentCP > 0) {
      pending = {
        'type':           'reactive',
        'fromPlayer':     _myRole!.name,
        'awaitingPlayer': opponentRole,
        'drawnTokenId':   t.id,
        'drawnTokenColor': t.color,
      };
      _pendingType = OnlinePendingType.reactive;
      _pendingFrom = _myRole!.name;
      _pendingData = pending;
    }

    notifyListeners();
    await _persistShared(pendingAction: pending);
  }

  // ── REACTIVE ACTIVATION RESPONSE ─────────────────────────────────────────
  Future<void> respondReactive(bool accept) async {
    if (_pendingType != OnlinePendingType.reactive) return;
    if (_pendingData?['awaitingPlayer'] != _myRole?.name) return;

    if (accept) {
      // Put drawn token back
      final drawnId    = _pendingData!['drawnTokenId']    as String;
      final drawnColor = _pendingData!['drawnTokenColor'] as String;
      _tokenBag.drawn.removeWhere((t) => t.id == drawnId);
      _tokenBag.bag.add(Token(id: drawnId, color: drawnColor));
      _tokenBag.lastDrawn = null;

      // Deduct 1 AP
      _myCP = (_myCP - 1).clamp(0, _myInitialCP);

      // Draw MY token (no reactive popup for opponent)
      final myColor = _myRole == OnlineRole.host ? 'host' : 'guest';
      _tokenBag.drawByColor(myColor);
      _activePlayer = myColor;

      _pendingType = null;
      _pendingFrom = null;
      _pendingData = null;

      notifyListeners();
      await _persistMyState();
      await _persistShared(pendingAction: null);
    } else {
      // Decline: the drawing player remains active (already set in shared)
      _pendingType = null;
      _pendingFrom = null;
      _pendingData = null;
      notifyListeners();
      await _persistShared(pendingAction: null);
    }
  }

  // ── NEXT ROUND ────────────────────────────────────────────────────────────
  // Requesting player calls this; sets a pending action for opponent to confirm.
  Future<void> requestNextRound() async {
    final pending = {
      'type':       'nextRound',
      'fromPlayer': _myRole!.name,
      'round':      _round,
    };
    _pendingType = OnlinePendingType.nextRound;
    _pendingFrom = _myRole!.name;
    _pendingData = pending;
    notifyListeners();
    await _persistShared(pendingAction: pending);
  }

  // Confirming player (opponent) calls this to actually start the next round.
  Future<void> confirmNextRound() async {
    if (_pendingType != OnlinePendingType.nextRound) return;

    // Reset my units
    for (final u in _myUnits) {
      u.deactivate();
      u.expanded = true;
    }
    _myDiceRolls.clear();

    final newRound = _round + 1;
    _round         = newRound;
    _pendingType   = null;
    _pendingFrom   = null;
    _pendingData   = null;
    _activePlayer  = null; // first draw of new round is free

    // Rebuild token bag from surviving units
    _tokenBag = _rebuildBagForNewRound();

    notifyListeners();
    await _persistMyState();
    await _persistSharedRaw({
      'round':         newRound,
      'tokenBag':      _tokenBag.toJson(),
      'activePlayer':  null,
      'pendingAction': null,
    });
  }

  // When the requester detects the next-round confirmation came through
  // (round incremented in shared state), they execute the local reset.
  void executeLocalNextRound(int newRound) {
    if (_round >= newRound) return;
    for (final u in _myUnits) {
      u.deactivate();
      u.expanded = true;
    }
    _myDiceRolls.clear();
    _round = newRound;
    // Token bag + activePlayer already updated from shared state Realtime
    notifyListeners();
    _persistMyState();
  }

  TokenBag _rebuildBagForNewRound() {
    final myPfx  = _myRole == OnlineRole.host ? 'h' : 'g';
    final oppPfx = _myRole == OnlineRole.host ? 'g' : 'h';
    final myColor  = _myRole == OnlineRole.host ? 'host' : 'guest';
    final oppColor = _myRole == OnlineRole.host ? 'guest' : 'host';
    final tokens = <Token>[
      ..._myUnits.where((u) => !u.isEliminated).map(
          (u) => Token(id: '${myPfx}_${u.instanceId}', color: myColor)),
      ..._opponentUnits.where((u) => !u.isEliminated).map(
          (u) => Token(id: '${oppPfx}_${u.instanceId}', color: oppColor)),
    ]..shuffle(_rng);
    return TokenBag(bag: tokens);
  }

  // ── MY STATE ACTIONS ─────────────────────────────────────────────────────
  void adjustCP(int delta) {
    _myCP = (_myCP + delta).clamp(0, _myInitialCP);
    notifyListeners();
    _scheduleMyStatePersist();
  }

  void adjustCon(String instanceId, int delta) {
    final u = _findUnit(instanceId);
    if (u == null) return;
    final wasElim = u.isEliminated;
    u.adjustCon(delta);
    if (u.isEliminated && !wasElim) {
      u.eliminatedOnRound = _round;
      // Remove token from bag
      final pfx = _myRole == OnlineRole.host ? 'h' : 'g';
      _tokenBag.bag.removeWhere((t) => t.id == '${pfx}_${u.instanceId}');
      _persistShared(pendingAction: _pendingData);
    }
    notifyListeners();
    _scheduleMyStatePersist();
  }

  void activateUnit(String instanceId) {
    _findUnit(instanceId)?.activate();
    notifyListeners();
    _scheduleMyStatePersist();
  }

  void deactivateUnit(String instanceId) {
    _findUnit(instanceId)?.deactivate();
    notifyListeners();
    _scheduleMyStatePersist();
  }

  void toggleExpand(String instanceId) {
    final u = _findUnit(instanceId);
    if (u == null) return;
    u.expanded = !u.expanded;
    notifyListeners();
  }

  void recordDiceRolls(List<int> rolls) {
    _myDiceRolls.addAll(rolls);
    notifyListeners();
    _scheduleMyStatePersist();
  }

  // ── LEAVE GAME ────────────────────────────────────────────────────────────
  Future<void> leaveGame() async {
    _leaving = true;
    notifyListeners();
    _channel?.unsubscribe();
    _channel = null;
    _debounce?.cancel();
    if (_sessionId != null) {
      try {
        await _supabase.from('online_game_sessions')
            .update({'status': 'finished', 'updated_at': DateTime.now().toIso8601String()})
            .eq('id', _sessionId!);
      } catch (_) {}
    }
  }

  // ── DB PERSISTENCE ────────────────────────────────────────────────────────
  void _scheduleMyStatePersist() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _persistMyState);
  }

  Future<void> _persistMyState() async {
    if (_sessionId == null || _myRole == null) return;
    final key = _myRole == OnlineRole.host ? 'host_state' : 'guest_state';
    try {
      await _supabase.from('online_game_sessions').update({
        key:           _playerStateJson(
          units:        _myUnits,
          cp:           _myCP,
          initCP:       _myInitialCP,
          armyName:     _myArmyName,
          armyBgColor:  _myBgColor,
          armyImageB64: _myImageB64,
          playerColor:  _myPlayerColor,
          diceRolls:    _myDiceRolls,
        ),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', _sessionId!);
    } catch (e) { debugPrint('persistMyState: $e'); }
  }

  Future<void> _persistShared({Map<String, dynamic>? pendingAction}) =>
      _persistSharedRaw({
        'round':         _round,
        'tokenBag':      _tokenBag.toJson(),
        'activePlayer':  _activePlayer,
        'pendingAction': pendingAction,
      });

  Future<void> _persistSharedRaw(Map<String, dynamic> shared) async {
    if (_sessionId == null) return;
    try {
      await _supabase.from('online_game_sessions').update({
        'shared':      shared,
        'updated_at':  DateTime.now().toIso8601String(),
      }).eq('id', _sessionId!);
    } catch (e) { debugPrint('persistShared: $e'); }
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────
  GameUnit? _findUnit(String instanceId) {
    for (final u in _myUnits) {
      if (u.instanceId == instanceId) return u;
    }
    return null;
  }

  static Map<String, dynamic> _playerStateJson({
    required List<GameUnit> units,
    required int cp,
    required int initCP,
    required String armyName,
    required String armyBgColor,
    String? armyImageB64,
    required String playerColor,
    List<int>? diceRolls,
  }) => {
    'commandPoints':  cp,
    'initialCP':      initCP,
    'armyName':       armyName,
    'armyBgColor':    armyBgColor,
    'armyImageB64':   armyImageB64,
    'playerColor':    playerColor,
    'roundDiceRolls': diceRolls ?? [],
    'units':          units.map((u) => u.toJson()).toList(),
  };

  static String _genCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(6, (_) => chars[_rng.nextInt(chars.length)]).join();
  }

  static Map<String, dynamic>? _parseJsonField(dynamic v) {
    if (v == null) return null;
    if (v is Map<String, dynamic>) return v;
    if (v is String) {
      try { return jsonDecode(v) as Map<String, dynamic>; } catch (_) {}
    }
    return null;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }
}

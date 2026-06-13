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
enum OnlinePendingType { reactive, nextRound, endGame }

// ── Saved game summary (used by lobby to list resumable sessions) ─────────────
class SavedGameInfo {
  final String sessionId;
  final String roomCode;
  final int    round;
  final String myRole; // 'host' or 'guest'
  final String status; // 'playing' or 'paused'
  final DateTime? updatedAt;

  // My army display data (from host_state / guest_state)
  final String  myArmyName;
  final String? myCreatorName;
  final String  myBgColor;
  final String? myImageB64;
  final String  myLore;
  final List<Map<String, String>> myUnitEntries; // [{name, group}, ...]
  final int myAlivePts;
  final int myTotalPts;

  // Opponent
  final String? opponentArmyName;
  final String? opponentCreatorName;

  const SavedGameInfo({
    required this.sessionId,
    required this.roomCode,
    required this.round,
    required this.myRole,
    required this.status,
    this.updatedAt,
    required this.myArmyName,
    this.myCreatorName,
    required this.myBgColor,
    this.myImageB64,
    required this.myLore,
    required this.myUnitEntries,
    required this.myAlivePts,
    required this.myTotalPts,
    this.opponentArmyName,
    this.opponentCreatorName,
  });
}

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
  bool _opponentLeft      = false; // set when opponent leaves/saves while we are in-game
  bool _endGameConfirmed  = false; // set when opponent confirms our end-game request
  bool get opponentConnected  => _opponentConnected;
  bool get gameActive         => _gameActive;
  bool get opponentLeft       => _opponentLeft;
  bool get endGameConfirmed   => _endGameConfirmed;
  void clearOpponentLeft()    { _opponentLeft    = false; }
  void clearEndGameConfirmed(){ _endGameConfirmed = false; }

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
  bool _skipPendingFromRemote = false; // set during confirmNextRound to block stale DB reads
  OnlinePendingType?    get pendingType => _pendingType;
  String?               get pendingFrom => _pendingFrom;
  Map<String, dynamic>? get pendingData => _pendingData;

  // ── Draw serial ──────────────────────────────────────────────────────────
  // Monotonically increasing counter: incremented on every drawToken() call.
  // Stored in shared state so the inactive player can detect a new draw even
  // if the same token is redrawn (e.g. after a reactive put-back).
  int _drawSerial = 0;
  int get drawSerial => _drawSerial;

  // ── My state ────────────────────────────────────────────────────────────
  List<GameUnit> _myUnits         = [];
  int            _myCP            = 0;
  int            _myInitialCP     = 0;
  List<int>      _myDiceRolls     = [];
  String         _myArmyName      = '';
  String?        _myCreatorName;
  String         _myBgColor       = '#1E1A15';
  String?        _myImageB64;
  String?        _myArmyLore;
  String         _myPlayerColor   = '#C9A84C';

  List<GameUnit> get myUnits        => _myUnits;
  int            get myCP           => _myCP;
  int            get myInitialCP    => _myInitialCP;
  List<int>      get myDiceRolls    => _myDiceRolls;
  String         get myArmyName     => _myArmyName;
  String?        get myCreatorName  => _myCreatorName;
  String         get myBgColor      => _myBgColor;
  String?        get myImageB64     => _myImageB64;
  String?        get myArmyLore     => _myArmyLore;
  String         get myPlayerColor  => _myPlayerColor;

  // ── Opponent state (read-only) ───────────────────────────────────────────
  List<GameUnit> _opponentUnits         = [];
  int            _opponentCP            = 0;
  String         _opponentArmyName      = '';
  String?        _opponentCreatorName;
  String         _opponentBgColor       = '#1E1A15';
  String?        _opponentImageB64;
  String?        _opponentArmyLore;
  String         _opponentPlayerColor   = '#D48080';

  List<GameUnit> get opponentUnits         => _opponentUnits;
  int            get opponentCP            => _opponentCP;
  String         get opponentArmyName      => _opponentArmyName;
  String?        get opponentCreatorName   => _opponentCreatorName;
  String         get opponentBgColor       => _opponentBgColor;
  String?        get opponentImageB64      => _opponentImageB64;
  String?        get opponentArmyLore      => _opponentArmyLore;
  String         get opponentPlayerColor   => _opponentPlayerColor;

  // ── Activation gate ─────────────────────────────────────────────────────
  // _activeUnitInstanceId: the unit marked ACTIVE for the current draw.
  // null = no unit activated yet this draw.
  // Drawing is blocked when it's my turn and _activeUnitInstanceId is null.
  String? _activeUnitInstanceId;
  String? get activeUnitInstanceId => _activeUnitInstanceId;

  void _resetActivationGate() {
    _activeUnitInstanceId = null;
  }

  // ── Derived ─────────────────────────────────────────────────────────────
  // Can the local player draw a token right now?
  bool get canDraw {
    if (!_gameActive || _pendingType != null || _leaving) return false;
    if (_activePlayer == null) return true; // round start: first draw is free
    if (_activePlayer != _myRole?.name) return false; // not my turn
    // It's my turn: I must activate a unit before drawing again
    return _activeUnitInstanceId != null;
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
  Timer?           _resubscribeTimer;
  bool             _channelOk = false;

  bool get channelOk => _channelOk;

  // ── CREATE GAME (host) ───────────────────────────────────────────────────
  Future<String?> createGame({
    required List<ArmyUnit> armyUnits,
    required String armyName,
    String? armyCreatorName,
    required String armyBgColor,
    String? armyImageB64,
    String? armyLore,
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
            armyName: armyName, armyCreatorName: armyCreatorName,
            armyBgColor: armyBgColor,
            armyImageB64: armyImageB64, armyLore: armyLore, playerColor: playerColor),
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
      _myArmyName    = armyName;
      _myCreatorName = armyCreatorName;
      _myBgColor     = armyBgColor;
      _myImageB64    = armyImageB64;
      _myArmyLore    = armyLore;
      _myPlayerColor = playerColor;
      _tokenBag      = TokenBag(bag: hostTokens);

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
    String? armyCreatorName,
    required String armyBgColor,
    String? armyImageB64,
    String? armyLore,
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
            armyName: armyName, armyCreatorName: armyCreatorName,
            armyBgColor: armyBgColor,
            armyImageB64: armyImageB64, armyLore: armyLore, playerColor: playerColor),
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
      _myCreatorName = armyCreatorName;
      _myBgColor     = armyBgColor;
      _myImageB64    = armyImageB64;
      _myArmyLore    = armyLore;
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
          .inFilter('status', ['playing', 'paused'])
          .limit(1);
      if ((rows as List).isEmpty) return false;
      final row = (rows as List<dynamic>).first as Map<String, dynamic>;
      _sessionId = row['id'] as String;
      _roomCode  = roomCode.toUpperCase();
      _myRole    = (row['host_id'] as String?) == uid
          ? OnlineRole.host : OnlineRole.guest;
      _loadFullRow(row);
      // Resume a paused session
      if ((row['status'] as String?) == 'paused') {
        _supabase.from('online_game_sessions')
            .update({'status': 'playing', 'updated_at': DateTime.now().toIso8601String()})
            .eq('id', _sessionId!)
            .then((_) {})
            .catchError((_) {});
      }
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

    final st = row['status'] as String?;
    _gameActive = st == 'playing' || st == 'paused';
    _opponentConnected =
        row[_myRole == OnlineRole.host ? 'guest_id' : 'host_id'] != null;
  }

  // ── REALTIME ─────────────────────────────────────────────────────────────
  void _subscribe() {
    if (_sessionId == null) return;
    _resubscribeTimer?.cancel();
    _resubscribeTimer = null;
    _channel?.unsubscribe();
    _channelOk = false;
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
        .subscribe((status, [error]) {
          final ok = status == RealtimeSubscribeStatus.subscribed;
          if (_channelOk != ok) {
            _channelOk = ok;
            notifyListeners();
          }
          if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            _scheduleResubscribe();
          }
        });
  }

  void _scheduleResubscribe() {
    if (_leaving || _sessionId == null) return;
    _resubscribeTimer?.cancel();
    _resubscribeTimer = Timer(const Duration(seconds: 5), () {
      if (!_leaving && _sessionId != null) _subscribe();
    });
  }

  /// Called while waiting for the guest to join. Fetches the DB row and
  /// applies it so the host transitions to gameActive even if Realtime missed the event.
  Future<void> pollForStart() async {
    if (_sessionId == null || _gameActive) return;
    try {
      final rows = await _supabase
          .from('online_game_sessions')
          .select()
          .eq('id', _sessionId!)
          .limit(1);
      if ((rows as List).isNotEmpty) {
        _onRemoteUpdate((rows as List<dynamic>).first as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('pollForStart error: $e');
    }
  }

  /// Called by the UI when the app returns to foreground.
  /// Re-subscribes the channel and fetches a fresh DB row to catch any
  /// updates that arrived while the app was backgrounded.
  Future<void> resubscribeAndRefresh() async {
    if (_sessionId == null) return;
    _subscribe();
    try {
      final rows = await _supabase
          .from('online_game_sessions')
          .select()
          .eq('id', _sessionId!)
          .limit(1);
      if ((rows as List).isNotEmpty) {
        _onRemoteUpdate((rows as List<dynamic>).first as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  void _onRemoteUpdate(Map<String, dynamic> row) {
    final oppKey   = _myRole == OnlineRole.host ? 'guest_state' : 'host_state';
    final prevRound = _round;

    // Detect game start FIRST so notifyListeners() is reached even if state parsing fails.
    final status = row['status'] as String?;
    if (status == 'playing' && !_gameActive) {
      _gameActive        = true;
      _opponentConnected = row[_myRole == OnlineRole.host ? 'guest_id' : 'host_id'] != null;
    }

    // Update opponent state — wrapped so a parse failure never blocks notifyListeners().
    try {
      final oppData = _parseJsonField(row[oppKey]);
      if (oppData != null) _loadOpponentState(oppData);
    } catch (e) {
      debugPrint('_loadOpponentState error: $e');
    }

    // Update shared state
    try {
      final shared = _parseJsonField(row['shared']);
      if (shared != null) _loadSharedState(shared);
    } catch (e) {
      debugPrint('_loadSharedState error: $e');
    }

    // Round advanced via opponent confirming next round: reset my units too
    if (_round > prevRound) {
      for (final u in _myUnits) { u.deactivate(); u.expanded = true; }
      _myDiceRolls.clear();
      _resetActivationGate();
      _persistMyState();
    }

    // Detect opponent leaving/saving while we are still active
    if (!_leaving && _gameActive &&
        (status == 'paused' || status == 'finished')) {
      // If I requested end-game and opponent confirmed → clean signal
      if (_pendingType == OnlinePendingType.endGame &&
          _pendingFrom == _myRole?.name &&
          status == 'finished') {
        _endGameConfirmed = true;
      } else {
        _opponentLeft = true;
      }
    }

    notifyListeners();
  }

  void _loadSharedState(Map<String, dynamic> s) {
    _round        = (s['round'] as num? ?? 1).toInt();
    _drawSerial   = (s['drawSerial'] as num? ?? 0).toInt();
    final bagData = _parseJsonField(s['tokenBag']);
    if (bagData != null) _tokenBag = TokenBag.fromJson(bagData);
    _activePlayer = s['activePlayer'] as String?;

    // When it's the opponent's turn, clear the local ACTIVE badge.
    final myColor = _myRole == OnlineRole.host ? 'host' : 'guest';
    if (_activePlayer != myColor) {
      _activeUnitInstanceId = null;
    }

    if (!_skipPendingFromRemote) {
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
  }

  void _loadMyState(Map<String, dynamic> s) {
    _myCP           = (s['commandPoints'] as num? ?? 0).toInt();
    _myInitialCP    = (s['initialCP']     as num? ?? 0).toInt();
    _myArmyName     = s['armyName']       as String? ?? '';
    _myCreatorName  = s['armyCreatorName'] as String?;
    _myBgColor      = s['armyBgColor']    as String? ?? '#1E1A15';
    _myImageB64     = s['armyImageB64']   as String?;
    _myArmyLore     = s['armyLore']       as String?;
    _myPlayerColor  = s['playerColor']    as String? ?? '#C9A84C';
    _myDiceRolls   = (s['roundDiceRolls'] as List? ?? [])
        .map((e) => (e as num).toInt()).toList();
    _myUnits       = _parseUnits(s['units'] as List? ?? []);
    _actionLog
      ..clear()
      ..addAll((s['actionLog'] as List? ?? [])
          .map((e) => ActionLogEntry.fromJson(e as Map<String, dynamic>)));
  }

  void _loadOpponentState(Map<String, dynamic> s) {
    if (s.isEmpty) return;
    _opponentCP            = (s['commandPoints'] as num? ?? 0).toInt();
    _opponentArmyName      = s['armyName']        as String? ?? '';
    _opponentCreatorName   = s['armyCreatorName'] as String?;
    _opponentBgColor       = s['armyBgColor']     as String? ?? '#1E1A15';
    _opponentImageB64      = s['armyImageB64']    as String?;
    _opponentArmyLore      = s['armyLore']        as String?;
    _opponentPlayerColor   = s['playerColor']     as String? ?? '#D48080';
    _opponentUnits         = _parseUnits(s['units'] as List? ?? []);
    _opponentActionLog
      ..clear()
      ..addAll((s['actionLog'] as List? ?? [])
          .map((e) => ActionLogEntry.fromJson(e as Map<String, dynamic>)));
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
        conditions:         List<String>.from(u['conditions'] as List? ?? []),
        note:               u['note'] as String? ?? '',
      ));
    }
    return result;
  }

  // ── DRAW TOKEN ───────────────────────────────────────────────────────────
  Future<void> drawToken() async {
    if (!canDraw) return;
    final t = _tokenBag.drawRandom();
    if (t == null) return;

    _activePlayer         = t.color; // 'host' or 'guest'
    _activeUnitInstanceId = null;   // clear ACTIVE badge on every new draw

    final opponentRole = _myRole == OnlineRole.host ? 'guest' : 'host';

    // Reactive: the player whose token was NOT drawn (the non-active player)
    // may spend 1 AP to insert their own activation first.
    final reactingPlayer   = t.color == 'host' ? 'guest' : 'host';
    final reactingPlayerCP = reactingPlayer == opponentRole ? _opponentCP : _myCP;

    Map<String, dynamic>? pending;
    if (reactingPlayerCP > 0) {
      pending = {
        'type':           'reactive',
        'fromPlayer':     t.color,        // active player (token drawn, must wait)
        'awaitingPlayer': reactingPlayer, // who may react
        'drawnTokenId':   t.id,
        'drawnTokenColor': t.color,
        'eventId':        DateTime.now().millisecondsSinceEpoch.toString(),
      };
      _pendingType = OnlinePendingType.reactive;
      _pendingFrom = t.color;
      _pendingData = pending;
    }

    final myColor   = _myRole == OnlineRole.host ? 'host' : 'guest';
    final drawnBy   = t.color == myColor
        ? (_myCreatorName ?? _myArmyName)
        : (_opponentCreatorName ?? (_opponentArmyName.isNotEmpty ? _opponentArmyName : 'Opponent'));
    _drawSerial++;
    _log('token', 'Token drawn: $drawnBy');
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
      _log('reactive', 'Reactive activation (-1 CP → $_myCP)');

      // Draw MY token (no reactive popup for opponent)
      final myColor = _myRole == OnlineRole.host ? 'host' : 'guest';
      _tokenBag.drawByColor(myColor);
      _activePlayer = myColor;
      _activeUnitInstanceId = null;

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
    _resetActivationGate();

    final newRound = _round + 1;
    _log('round', '── Round $newRound started ──');
    _round         = newRound;
    _pendingType   = null;
    _pendingFrom   = null;
    _pendingData   = null;
    _activePlayer  = null; // first draw of new round is free

    // Rebuild token bag from surviving units
    _tokenBag = _rebuildBagForNewRound();

    notifyListeners();
    _skipPendingFromRemote = true;
    try {
      await _persistMyState();
      await _persistSharedRaw({
        'round':         newRound,
        'drawSerial':    _drawSerial,
        'tokenBag':      _tokenBag.toJson(),
        'activePlayer':  null,
        'pendingAction': null,
      });
    } finally {
      _skipPendingFromRemote = false;
    }
  }

  // Opponent declines the next-round request → clear pending so requester resets.
  Future<void> declineNextRound() async {
    if (_pendingType != OnlinePendingType.nextRound) return;
    _pendingType = null;
    _pendingFrom = null;
    _pendingData = null;
    notifyListeners();
    await _persistShared(pendingAction: null);
  }

  // ── END GAME (via opponent confirmation) ─────────────────────────────────
  Future<void> requestEndGame() async {
    final pending = {
      'type':       'endGame',
      'fromPlayer': _myRole!.name,
    };
    _pendingType = OnlinePendingType.endGame;
    _pendingFrom = _myRole!.name;
    _pendingData = pending;
    notifyListeners();
    await _persistShared(pendingAction: pending);
  }

  // Opponent confirms: end the game (status → finished; requester detects via Realtime).
  Future<void> confirmEndGame() async {
    await leaveGame();
  }

  // Opponent declines: clear the pending so the requester sees Waiting reset.
  Future<void> declineEndGame() async {
    if (_pendingType != OnlinePendingType.endGame) return;
    _pendingType = null;
    _pendingFrom = null;
    _pendingData = null;
    notifyListeners();
    await _persistShared(pendingAction: null);
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
    _resetActivationGate();
    _log('round', '── Round $newRound started ──');
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

  // ── ACTION LOG ───────────────────────────────────────────────────────────
  final List<ActionLogEntry> _actionLog         = [];
  final List<ActionLogEntry> _opponentActionLog = [];

  List<ActionLogEntry> get actionLog => _actionLog;

  List<ActionLogEntry> get combinedActionLog {
    final all = [..._actionLog, ..._opponentActionLog];
    all.sort((a, b) {
      final r = a.round.compareTo(b.round);
      return r != 0 ? r : a.ms.compareTo(b.ms);
    });
    final seenRounds = <int>{};
    return all.where((e) {
      if (e.tag != 'round') return true;
      final m = RegExp(r'Round (\d+)').firstMatch(e.text);
      final n = m != null ? int.tryParse(m.group(1)!) : null;
      if (n == null) return true;
      return seenRounds.add(n);
    }).toList();
  }

  void _log(String tag, String text) {
    _actionLog.add(ActionLogEntry(
      round: _round, tag: tag, text: text,
      player: _myCreatorName ?? _myArmyName,
      ms: DateTime.now().millisecondsSinceEpoch));
    if (_actionLog.length > 300) _actionLog.removeAt(0);
  }

  // ── MY STATE ACTIONS ─────────────────────────────────────────────────────
  void toggleCondition(String instanceId, String condition) {
    final u = _myUnits.firstWhere(
      (x) => x.instanceId == instanceId, orElse: () => _myUnits.first);
    if (!_myUnits.any((x) => x.instanceId == instanceId)) return;
    if (u.conditions.contains(condition)) {
      u.conditions.remove(condition);
      _log('condition', '${u.displayName}: $condition removed');
    } else {
      u.conditions.add(condition);
      _log('condition', '${u.displayName}: $condition added');
    }
    notifyListeners();
    _scheduleMyStatePersist();
  }

  void adjustCP(int delta) {
    _myCP = (_myCP + delta).clamp(0, _myInitialCP);
    if (delta < 0) _log('cp', 'CP: $delta → $_myCP');
    if (delta > 0) _log('cp', 'CP: +$delta → $_myCP');
    notifyListeners();
    _scheduleMyStatePersist();
  }

  void setNote(String instanceId, String note) {
    final u = _findUnit(instanceId);
    if (u == null) return;
    u.note = note;
    notifyListeners();
    _scheduleMyStatePersist();
  }

  void moveUnit(GameUnit unit, int toIdx, String toGroup) {
    final from = _myUnits.indexOf(unit);
    if (from < 0) return;
    final moved = GameUnit(
      instanceId: unit.instanceId, armyUnit: unit.armyUnit,
      currentCon: unit.currentCon, activated: unit.activated,
      expanded: unit.expanded, groupName: toGroup,
      eliminatedOnRound: unit.eliminatedOnRound,
      conditions: List.from(unit.conditions),
      note: unit.note);
    _myUnits.removeAt(from);
    final to = (toIdx > from ? toIdx - 1 : toIdx).clamp(0, _myUnits.length);
    _myUnits.insert(to, moved);
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
      _log('eliminate', '${u.displayName} eliminated');
      final pfx = _myRole == OnlineRole.host ? 'h' : 'g';
      _tokenBag.bag.removeWhere((t) => t.id == '${pfx}_${u.instanceId}');
      _persistShared(pendingAction: _pendingData);
    } else if (!u.isEliminated && wasElim) {
      _log('heal', '${u.displayName}: restored');
    } else if (delta < 0) {
      _log('damage', '${u.displayName}: $delta STR (${u.currentCon}/${u.armyUnit.unit.con})');
    } else if (delta > 0) {
      _log('heal', '${u.displayName}: +$delta STR (${u.currentCon}/${u.armyUnit.unit.con})');
    }
    notifyListeners();
    _scheduleMyStatePersist();
  }

  void activateUnit(String instanceId) {
    final u = _findUnit(instanceId);
    u?.activate();
    _activeUnitInstanceId = instanceId;
    if (u != null) _log('activate', '${u.displayName} activated');
    notifyListeners();
    _scheduleMyStatePersist();
  }

  void deactivateUnit(String instanceId) {
    final u = _findUnit(instanceId);
    u?.deactivate();
    if (_activeUnitInstanceId == instanceId) {
      _activeUnitInstanceId = null;
    }
    // Remove the matching activate log entry so undone activations don't appear
    if (u != null) {
      final idx = _actionLog.lastIndexWhere(
          (e) => e.tag == 'activate' && e.text == '${u.displayName} activated');
      if (idx != -1) _actionLog.removeAt(idx);
    }
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
    _log('dice', 'Roll: ${rolls.join(', ')} (sum ${rolls.fold(0, (a, b) => a + b)})');
    notifyListeners();
    _scheduleMyStatePersist();
  }

  // ── LEAVE GAME ────────────────────────────────────────────────────────────
  Future<void> leaveGame() async {
    _leaving = true;
    notifyListeners();
    _resubscribeTimer?.cancel();
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

  // ── SAVE GAME (pause without ending) ─────────────────────────────────────
  Future<void> saveGame() async {
    _leaving = true;
    notifyListeners();
    _resubscribeTimer?.cancel();
    _debounce?.cancel();
    // Flush state (including action log) before disconnecting
    await _persistMyState();
    _channel?.unsubscribe();
    _channel = null;
    if (_sessionId != null) {
      try {
        await _supabase.from('online_game_sessions')
            .update({'status': 'paused', 'updated_at': DateTime.now().toIso8601String()})
            .eq('id', _sessionId!);
      } catch (_) {}
    }
  }

  // ── FETCH SAVED GAMES (static, for lobby) ────────────────────────────────
  static Future<List<SavedGameInfo>> fetchSavedGames() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return [];
    try {
      final rows = await client
          .from('online_game_sessions')
          .select('id, room_code, shared, host_state, guest_state, host_id, guest_id, status, updated_at')
          .or('host_id.eq.$uid,guest_id.eq.$uid')
          .inFilter('status', ['paused', 'playing'])
          .order('updated_at', ascending: false)
          .limit(10);

      Map<String, dynamic>? parseRaw(dynamic raw) {
        if (raw == null) return null;
        if (raw is Map<String, dynamic>) return raw;
        if (raw is String) {
          try { return jsonDecode(raw) as Map<String, dynamic>; } catch (_) {}
        }
        return null;
      }

      final result = <SavedGameInfo>[];
      for (final row in (rows as List<dynamic>)) {
        final r      = row as Map<String, dynamic>;
        final myRole = (r['host_id'] as String?) == uid ? 'host' : 'guest';
        final myKey  = myRole == 'host' ? 'host_state' : 'guest_state';
        final oppKey = myRole == 'host' ? 'guest_state' : 'host_state';

        final shared = parseRaw(r['shared']);
        final round  = (shared?['round'] as num? ?? 1).toInt();

        final opp         = parseRaw(r[oppKey]);
        final oppName     = opp?['armyName']        as String?;
        final oppCreator  = opp?['armyCreatorName'] as String?;

        final my = parseRaw(r[myKey]);
        final myArmyName    = my?['armyName']        as String? ?? '';
        final myCreator     = my?['armyCreatorName']  as String?;
        final myBgColor     = my?['armyBgColor']      as String? ?? '#1E1A15';
        final myImageB64    = my?['armyImageB64']     as String?;
        final myLore        = my?['armyLore']         as String? ?? '';

        final rawUnits = my?['units'] as List<dynamic>? ?? [];
        final myUnitEntries = <Map<String, String>>[];
        int alivePts = 0, totalPts = 0;
        for (final u in rawUnits) {
          final uu   = u as Map<String, dynamic>;
          final cost = (uu['cost'] as num?)?.toInt() ?? 0;
          if (cost == 0) continue;
          totalPts += cost;
          final con = (uu['currentCon'] as num?)?.toInt();
          if (con == null || con > 0) alivePts += cost;
          final name = (uu['name'] as String? ?? '').isNotEmpty
              ? uu['name'] as String
              : uu['unitId'] as String? ?? '';
          myUnitEntries.add({
            'name':  name,
            'group': uu['groupName'] as String? ?? '',
          });
        }

        final updatedAt = DateTime.tryParse(r['updated_at'] as String? ?? '');

        result.add(SavedGameInfo(
          sessionId:        r['id']        as String,
          roomCode:         r['room_code'] as String,
          round:            round,
          myRole:           myRole,
          status:           r['status']    as String? ?? 'playing',
          updatedAt:        updatedAt,
          myArmyName:       myArmyName,
          myCreatorName:    myCreator,
          myBgColor:        myBgColor,
          myImageB64:       myImageB64,
          myLore:           myLore,
          myUnitEntries:    myUnitEntries,
          myAlivePts:       alivePts,
          myTotalPts:       totalPts,
          opponentArmyName:    oppName,
          opponentCreatorName: oppCreator,
        ));
      }
      return result;
    } catch (e) {
      debugPrint('fetchSavedGames: $e');
      return [];
    }
  }

  // ── END SESSION (static, from lobby) ─────────────────────────────────────
  static Future<void> endSession(String sessionId) async {
    try {
      await Supabase.instance.client
          .from('online_game_sessions')
          .update({'status': 'finished', 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', sessionId);
    } catch (e) { debugPrint('endSession: $e'); }
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
          units:           _myUnits,
          cp:              _myCP,
          initCP:          _myInitialCP,
          armyName:        _myArmyName,
          armyCreatorName: _myCreatorName,
          armyBgColor:     _myBgColor,
          armyImageB64:    _myImageB64,
          armyLore:        _myArmyLore,
          playerColor:     _myPlayerColor,
          diceRolls:       _myDiceRolls,
          actionLog:       _actionLog,
        ),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', _sessionId!);
    } catch (e) { debugPrint('persistMyState: $e'); }
  }

  Future<void> _persistShared({Map<String, dynamic>? pendingAction}) =>
      _persistSharedRaw({
        'round':         _round,
        'drawSerial':    _drawSerial,
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
    String? armyCreatorName,
    required String armyBgColor,
    String? armyImageB64,
    String? armyLore,
    required String playerColor,
    List<int>? diceRolls,
    List<ActionLogEntry>? actionLog,
  }) => {
    'commandPoints':   cp,
    'initialCP':       initCP,
    'armyName':        armyName,
    'armyCreatorName': armyCreatorName,
    'armyBgColor':     armyBgColor,
    'armyImageB64':    armyImageB64,
    'armyLore':        armyLore,
    'playerColor':     playerColor,
    'roundDiceRolls':  diceRolls ?? [],
    'actionLog':       actionLog?.map((e) => e.toJson()).toList() ?? [],
    'units':           units.map((u) => u.toJson()).toList(),
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

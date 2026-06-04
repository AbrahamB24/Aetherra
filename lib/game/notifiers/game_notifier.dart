import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/army_state.dart';
import '../../models/game_data.dart' as gd;
import '../../services/game_data_service.dart';
import '../../widgets/photo_crop_dialog.dart';
import '../models/game_state.dart';

class GameNotifier extends ChangeNotifier {
  GameState? _state;
  GameState? get state => _state;
  bool get hasGame => _state != null;
  bool _autoSaving = false;
  bool get autoSaving => _autoSaving;
  bool get isSaved => _state?.saveId != null;

  Token? get lastDrawn => _state?.tokenBag.lastDrawn;

  // â”€â”€ SETUP â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void startGame({
    required List<ArmyUnit> armyUnits,
    required List<String> groups,
    required PlayerRole role,
    required String playerColor,
    required String enemyColor,
    required String armyName,
    int enemyUnitCount = 0,
    String? saveName,
    String? armyBgColor,
    String? armyImageB64,
    String? armyLore,
    String? armyNotes,
    String? armyListId,
  }) {
    final gameUnits = armyUnits.map(GameUnit.fromArmyUnit).toList();
    final initCP    = GameState.calcInitialCP(armyUnits);

    final gs = GameState(
      role:              role,
      playerColor:       playerColor,
      enemyColor:        enemyColor,
      units:             gameUnits,
      commandPoints:     initCP,
      initialCP:         initCP,
      enemyUnitCount:    enemyUnitCount,
      currentEnemyAlive: enemyUnitCount,
      armyName:          armyName,
    );
    gs.saveName     = saveName;
    gs.armyBgColor  = armyBgColor;
    gs.armyImageB64 = armyImageB64;
    gs.armyLore     = armyLore;
    gs.armyNotes    = armyNotes;
    gs.armyListId   = armyListId;

    if (role == PlayerRole.gamemaster) {
      gs.tokenBag = TokenBag.build(
        playerUnits: gameUnits,
        enemyCount:  enemyUnitCount,
      );
    }

    _state = gs;
    notifyListeners();
    _migratePhotos(gameUnits);
  }

  void notifyListenersPublic() => notifyListeners();

  void endGame() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    _state = null;
    notifyListeners();
  }

  // Flush any pending debounced auto-save immediately (call before endGame).
  Future<void> flushAutoSave() async {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    final name = _state?.saveName;
    if (name != null && name.isNotEmpty) {
      await saveGame(name);
    }
  }

  Timer? _autoSaveTimer;

  void _autoSave() {
    final name = _state?.saveName;
    if (name == null || name.isEmpty) return;
    // Debounce: cancel previous pending save, schedule new one
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 800), () {
      saveGame(name).then((ok) {
        if (ok) { _autoSaving = false; notifyListeners(); }
      });
      _autoSaving = true;
      notifyListeners();
    });
  }

  // â”€â”€ SAVE / LOAD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<bool> loadGame(Map<String, dynamic> saveRow) async {
    _state = null; // clear stale state so failures show "No game active"
    try {
      final raw = saveRow['game_data'];
      final Map<String, dynamic> data =
        raw is String ? jsonDecode(raw) : raw as Map<String, dynamic>;

      int numInt(dynamic v, [int d = 0]) => v == null ? d : (v as num).toInt();

      // Restore units
      final unitsList = data['units'] as List? ?? [];
      final gameUnits = <GameUnit>[];
      for (final u in unitsList) {
        final unitId = u['unitId'] as String? ?? '';
        final gu = GameDataService.toGameUnit(unitId);
        if (gu == null) continue;

        // Use costs/con from save when DB has them as 0 (e.g. custom_units override
        // with null cost). Fall back to builtin values as last resort.
        final savedCost   = numInt(u['cost'],   0);
        final savedMaxCon = numInt(u['maxCon'], 0);
        final builtin     = gd.builtinUnits.where((b) => b.id == unitId).firstOrNull;
        final effectiveCost   = savedCost   > 0 ? savedCost   : (gu.cost   > 0 ? gu.cost   : (builtin?.cost   ?? 0));
        final effectiveMaxCon = savedMaxCon > 0 ? savedMaxCon : (gu.con    > 0 ? gu.con    : (builtin?.con    ?? 1));

        final effectiveGu = (effectiveCost != gu.cost || effectiveMaxCon != gu.con)
            ? gd.GameUnit(
                id: gu.id, name: gu.name, faction: gu.faction, type: gu.type,
                atk: gu.atk, def: gu.def, rng: gu.rng, mob: gu.mob,
                con: effectiveMaxCon, cp: gu.cp, cost: effectiveCost,
                unique: gu.unique, abilities: gu.abilities)
            : gu;

        final armyUnit = ArmyUnit(iid: u['instanceId'] as String? ?? unitId, unit: effectiveGu)
          ..customName  = u['name'] as String? ?? ''
          ..groupName   = u['groupName'] as String? ?? ''
          ..photoBase64 = u['photo'] as String?
          ..bgColor     = u['bgColor'] as String?
          ..lore        = u['lore']   as String?;
        final savedCon = numInt(u['currentCon'], -1);
        final gameUnit = GameUnit(
          instanceId:       u['instanceId'] as String? ?? unitId,
          armyUnit:         armyUnit,
          currentCon:       savedCon >= 0 ? savedCon : effectiveMaxCon,
          activated:        u['activated']        as bool? ?? false,
          expanded:         u['expanded']         as bool? ?? true,
          groupName:        u['groupName']        as String? ?? '',
          eliminatedOnRound: u['eliminatedOnRound'] as int?,
        );
        gameUnits.add(gameUnit);
      }

      // Restore token bag
      final bagData = data['tokenBag'] as Map<String, dynamic>?;
      final tokenBag = bagData != null ? TokenBag.fromJson(bagData) : TokenBag();

      _state = GameState(
        role:              PlayerRole.values.firstWhere(
          (r) => r.name == (data['role'] as String? ?? 'player'),
          orElse: () => PlayerRole.player),
        playerColor:       data['playerColor'] as String? ?? '#C9A84C',
        enemyColor:        data['enemyColor']  as String? ?? '#D48080',
        units:             gameUnits,
        commandPoints:     numInt(data['commandPoints']),
        initialCP:         numInt(data['initialCP'], numInt(data['commandPoints'])),
        enemyUnitCount:    numInt(data['enemyUnitCount']),
        currentEnemyAlive: numInt(data['currentEnemyAlive']),
        tokenBag:          tokenBag,
        round:             numInt(data['round'], 1),
        armyName:          data['armyName'] as String?,
      );
      _state!.saveId     = saveRow['id']   as String?;
      _state!.saveName   = saveRow['name'] as String? ?? data['saveName'] as String?;
      _state!.roundDiceRolls = (data['roundDiceRolls'] as List? ?? [])
          .map((e) => (e as num).toInt()).toList();
      _state!.armyBgColor  = data['armyBgColor']  as String?;
      _state!.armyImageB64 = data['armyImageB64'] as String?;
      _state!.armyLore     = data['armyLore']     as String?;
      _state!.armyNotes    = data['armyNotes']    as String?;
      _state!.armyListId   = data['armyListId']   as String?;
      notifyListeners();
      _migratePhotos(gameUnits);
      return true;
    } catch (e) {
      debugPrint('loadGame error: $e');
      return false;
    }
  }

  void _migratePhotos(List<GameUnit> units) async {
    for (final gu in units) {
      final p = gu.armyUnit.photoBase64;
      if (p == null || p.isEmpty) continue;
      final migrated = await migratePhotoIfNeeded(p);
      if (!identical(migrated, p)) {
        gu.armyUnit.photoBase64 = migrated;
      }
    }
  }

  Future<bool> saveGame(String saveName) async {
    if (_state == null) return false;
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return false;
      _state!.saveName = saveName;
      final payload = {
        'user_id':    uid,
        'name':       saveName,
        'game_data':  jsonEncode(_state!.toJson()),
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (_state!.saveId != null) {
        // Update existing row
        await Supabase.instance.client
          .from('game_sessions')
          .update(payload)
          .eq('id', _state!.saveId!);
      } else {
        // Insert new row
        final res = await Supabase.instance.client
          .from('game_sessions')
          .insert(payload)
          .select('id')
          .single();
        _state!.saveId = res['id'] as String?;
      }
      return true;
    } catch (e) { debugPrint('saveGame error: $e'); return false; }
  }

  Future<List<Map<String,dynamic>>> listSaves() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return [];
      final data = await Supabase.instance.client
        .from('game_sessions')
        .select('id, name, updated_at')
        .eq('user_id', uid)
        .order('updated_at', ascending: false);
      return List<Map<String,dynamic>>.from(data);
    } catch (_) { return []; }
  }

  // â”€â”€ UNIT CON â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void adjustCon(String instanceId, int delta) {
    final u = _unit(instanceId);
    if (u == null) return;
    final wasEliminated = u.isEliminated;
    u.adjustCon(delta);
    if (u.isEliminated && !wasEliminated) {
      u.eliminatedOnRound = _state!.round;
    } else if (!u.isEliminated && wasEliminated) {
      u.eliminatedOnRound = null;
    }
    // If eliminated and GM, remove token from bag
    if (u.isEliminated && _state!.role == PlayerRole.gamemaster) {
      _state!.tokenBag.bag.removeWhere((t) => t.id == 'p_${u.instanceId}');
    }
    notifyListeners();
    _autoSave();
  }

  // â”€â”€ ACTIVATION â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void activateUnit(String instanceId) {
    _unit(instanceId)?.activate();
    notifyListeners();
    _autoSave();
  }

  void deactivateUnit(String instanceId) {
    _unit(instanceId)?.deactivate();
    notifyListeners();
    _autoSave();
  }

  void reorderUnit(String instanceId, String beforeInstanceId, String newGroup) {
    if (_state == null) return;
    final from = _state!.units.indexWhere((u) => u.instanceId == instanceId);
    final to   = _state!.units.indexWhere((u) => u.instanceId == beforeInstanceId);
    if (from < 0 || to < 0 || from == to) return;
    final unit = _state!.units.removeAt(from);
    // Rebuild with new group (GameUnit is immutable so replace)
    final newUnit = GameUnit(
      instanceId: unit.instanceId,
      armyUnit:   unit.armyUnit,
      currentCon: unit.currentCon,
      activated:  unit.activated,
      expanded:   unit.expanded,
      groupName:  newGroup,
    );
    _state!.units.insert(to, newUnit);
    notifyListeners();
    _autoSave();
  }

  void toggleExpand(String instanceId) {
    final u = _unit(instanceId);
    if (u == null) return;
    u.expanded = !u.expanded;
    notifyListeners();
  }

  void resetAllUnits() {
    _state?.units.forEach((u) {
      u.deactivate();
      u.expanded = true;
    });
    notifyListeners();
    _autoSave();
  }

  // â”€â”€ COMMAND POINTS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void adjustCP(int delta) {
    if (_state == null) return;
    final max = _state!.initialCP;
    _state!.commandPoints = (_state!.commandPoints + delta).clamp(0, max);
    notifyListeners();
    _autoSave();
  }

  // â”€â”€ TOKEN BAG (GM only) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Token? drawRandom() {
    final t = _state?.tokenBag.drawRandom();
    if (t != null) { notifyListeners(); _autoSave(); }
    return t;
  }

  Token? drawByColor(String color) {
    final t = _state?.tokenBag.drawByColor(color);
    if (t != null) { notifyListeners(); _autoSave(); }
    return t;
  }

  bool undoLastDraw() {
    final ok = _state?.tokenBag.undoLastDraw() ?? false;
    if (ok) { notifyListeners(); _autoSave(); }
    return ok;
  }

  void setEnemyAlive(int count) {
    if (_state == null) return;
    _state!.currentEnemyAlive = count.clamp(0, _state!.enemyUnitCount);
    notifyListeners();
    _autoSave();
  }

  void recordDiceRoll(List<int> rolls) {
    if (_state == null) return;
    _state!.roundDiceRolls.addAll(rolls);
    notifyListeners();
  }

  // â”€â”€ NEXT ROUND â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void nextRound() {
    if (_state == null) return;
    // Return drawn tokens (except eliminated player tokens)
    _state!.tokenBag.resetForNextRound(_state!.eliminatedIds);
    // Also sync enemy tokens: rebuild enemy tokens based on currentEnemyAlive
    if (_state!.role == PlayerRole.gamemaster) {
      // Remove old enemy tokens from bag
      _state!.tokenBag.bag.removeWhere((t) => t.color == 'enemy');
      // Add current enemy count as tokens
      for (int i = 0; i < _state!.currentEnemyAlive; i++) {
        _state!.tokenBag.bag.add(Token(id: 'e_${_state!.round}_$i', color: 'enemy'));
      }
      _state!.tokenBag.bag.shuffle();
    }
    // Reset activations and per-round tracking
    for (final u in _state!.units) {
      u.deactivate();
      u.expanded = true;
    }
    _state!.roundDiceRolls.clear();
    _state!.round++;
    notifyListeners();
    _autoSave();
  }

  // â”€â”€ HELPERS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  GameUnit? _unit(String id) =>
      _state?.units.where((u) => u.instanceId == id).firstOrNull;

  // Sorted units for display: active groups, then ungrouped, eliminated last
  List<MapEntry<String, List<GameUnit>>> groupedUnits() {
    if (_state == null) return [];
    final alive = _state!.units.where((u) => !u.isEliminated).toList();
    final dead  = _state!.units.where((u) =>  u.isEliminated).toList();

    // Group alive units
    final groupOrder = <String>[''];  // ungrouped always first
    for (final u in alive) {
      if (!groupOrder.contains(u.groupName)) groupOrder.add(u.groupName);
    }

    final result = <MapEntry<String, List<GameUnit>>>[];
    for (final g in groupOrder) {
      final members = alive.where((u) => u.groupName == g).toList();
      if (members.isNotEmpty) result.add(MapEntry(g, members));
    }
    if (dead.isNotEmpty) result.add(MapEntry('__eliminated__', dead));
    return result;
  }
}
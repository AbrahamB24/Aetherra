import 'dart:math';
import '../../models/army_state.dart';

// â”€â”€ Enums â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
enum PlayerRole { player, gamemaster }

// â”€â”€ Token â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class Token {
  final String id;
  final String color; // 'player' or 'enemy'

  const Token({required this.id, required this.color});

  Map<String, dynamic> toJson() => {'id': id, 'color': color};
  factory Token.fromJson(Map<String, dynamic> j) =>
      Token(id: j['id'], color: j['color']);
}

// â”€â”€ TokenBag â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class TokenBag {
  List<Token> bag;      // tokens remaining in bag
  List<Token> drawn;    // tokens already drawn
  Token? lastDrawn;     // for undo
  final _rng = Random();

  TokenBag({List<Token>? bag, List<Token>? drawn, this.lastDrawn})
      : bag = bag ?? [],
        drawn = drawn ?? [];

  int get bagCount    => bag.length;
  int get playerCount => bag.where((t) => t.color == 'player').length;
  int get enemyCount  => bag.where((t) => t.color == 'enemy').length;
  // Online mode: tokens use 'host'/'guest' colors
  int get hostCount   => bag.where((t) => t.color == 'host').length;
  int get guestCount  => bag.where((t) => t.color == 'guest').length;

  // Draw random token
  Token? drawRandom() {
    if (bag.isEmpty) return null;
    final idx = _rng.nextInt(bag.length);
    final t = bag.removeAt(idx);
    drawn.add(t);
    lastDrawn = t;
    return t;
  }

  // Draw specific color
  Token? drawByColor(String color) {
    final idx = bag.indexWhere((t) => t.color == color);
    if (idx < 0) return null;
    final t = bag.removeAt(idx);
    drawn.add(t);
    lastDrawn = t;
    return t;
  }

  // Undo last draw
  bool undoLastDraw() {
    if (lastDrawn == null) return false;
    drawn.remove(lastDrawn);
    bag.add(lastDrawn!);
    lastDrawn = null;
    return true;
  }

  // Return all drawn tokens to bag (for next round)
  void resetForNextRound(Set<String> eliminatedIds) {
    // Only return tokens that don't belong to eliminated units
    for (final t in List.from(drawn)) {
      if (!eliminatedIds.contains(t.id)) {
        bag.add(t);
      }
    }
    drawn.clear();
    lastDrawn = null;
  }

  // Online mode: build bag with 'host'/'guest' token colors
  factory TokenBag.buildOnline({
    required List<GameUnit> hostUnits,
    required List<GameUnit> guestUnits,
  }) {
    final tokens = <Token>[
      ...hostUnits.where((u) => !u.isEliminated)
          .map((u) => Token(id: 'h_${u.instanceId}', color: 'host')),
      ...guestUnits.where((u) => !u.isEliminated)
          .map((u) => Token(id: 'g_${u.instanceId}', color: 'guest')),
    ]..shuffle();
    return TokenBag(bag: tokens);
  }

  // Rebuild bag from scratch
  factory TokenBag.build({
    required List<GameUnit> playerUnits,
    required int enemyCount,
  }) {
    final tokens = <Token>[];
    for (final u in playerUnits) {
      if (!u.isEliminated) {
        tokens.add(Token(id: 'p_${u.instanceId}', color: 'player'));
      }
    }
    for (int i = 0; i < enemyCount; i++) {
      tokens.add(Token(id: 'e_$i', color: 'enemy'));
    }
    tokens.shuffle();
    return TokenBag(bag: tokens);
  }

  Map<String, dynamic> toJson() => {
    'bag': bag.map((t) => t.toJson()).toList(),
    'drawn': drawn.map((t) => t.toJson()).toList(),
    'lastDrawn': lastDrawn?.toJson(),
  };

  factory TokenBag.fromJson(Map<String, dynamic> j) => TokenBag(
    bag: (j['bag'] as List).map((e) => Token.fromJson(e)).toList(),
    drawn: (j['drawn'] as List).map((e) => Token.fromJson(e)).toList(),
    lastDrawn: j['lastDrawn'] != null ? Token.fromJson(j['lastDrawn']) : null,
  );
}

// â”€â”€ GameUnit â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class GameUnit {
  final String instanceId;
  final ArmyUnit armyUnit;
  int  currentCon;    // starts at armyUnit.unit.con
  bool activated;
  bool expanded;      // whether card is expanded when activated
  final String groupName;
  int? eliminatedOnRound;

  GameUnit({
    required this.instanceId,
    required this.armyUnit,
    required this.currentCon,
    this.activated        = false,
    this.expanded         = true,
    required this.groupName,
    this.eliminatedOnRound,
  });

  bool get isEliminated => currentCon <= 0;

  String get displayName =>
      armyUnit.customName.isNotEmpty ? armyUnit.customName : armyUnit.unit.name;

  void activate()   => activated = true;
  void deactivate() => activated = false;

  void adjustCon(int delta) {
    currentCon = (currentCon + delta).clamp(0, armyUnit.unit.con);
  }

  Map<String, dynamic> toJson() => {
    'instanceId': instanceId,
    'unitId':     armyUnit.unit.id,
    'name':       armyUnit.customName,
    'photo':      armyUnit.photoBase64,
    'bgColor':    armyUnit.bgColor,
    'currentCon': currentCon,
    'maxCon':     armyUnit.unit.con,
    'cost':       armyUnit.unit.cost,
    'activated':         activated,
    'expanded':          expanded,
    'groupName':         groupName,
    'eliminatedOnRound': eliminatedOnRound,
    'lore':              armyUnit.lore,
  };

  factory GameUnit.fromArmyUnit(ArmyUnit u) => GameUnit(
    instanceId: u.iid,
    armyUnit:   u,
    currentCon: u.unit.con,
    groupName:  u.groupName,
  );
}

// â”€â”€ GameState â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class GameState {
  PlayerRole role;
  String     playerColor;   // hex e.g. '#C9A84C'
  String     enemyColor;    // hex
  List<GameUnit> units;
  int        commandPoints;
  int        initialCP;
  int        enemyUnitCount;   // GM: how many enemy units
  int        currentEnemyAlive; // GM: enemy units still alive
  TokenBag   tokenBag;
  int        round;
  String?    armyName;
  String?    armyBgColor;
  String?    armyImageB64;
  String?    armyLore;
  String?    armyNotes;
  String?    armyListId;
  String?    saveId;    // UUID from Supabase if saved
  String?    saveName;  // user-defined save name
  List<int>  roundDiceRolls = [];

  GameState({
    required this.role,
    required this.playerColor,
    required this.enemyColor,
    required this.units,
    required this.commandPoints,
    required this.initialCP,
    this.enemyUnitCount    = 0,
    this.currentEnemyAlive = 0,
    TokenBag? tokenBag,
    this.round    = 1,
    this.armyName,
  }) : tokenBag = tokenBag ?? TokenBag();

  Set<String> get eliminatedIds =>
      units.where((u) => u.isEliminated).map((u) => 'p_${u.instanceId}').toSet();

  // Total CP from heroes in army
  static int calcInitialCP(List<ArmyUnit> armyUnits) =>
      armyUnits.fold(0, (sum, u) => sum + u.unit.cp);

  Map<String, dynamic> toJson() => {
    'role':               role.name,
    'playerColor':        playerColor,
    'enemyColor':         enemyColor,
    'commandPoints':      commandPoints,
    'initialCP':          initialCP,
    'enemyUnitCount':     enemyUnitCount,
    'currentEnemyAlive':  currentEnemyAlive,
    'round':              round,
    'armyName':           armyName,
    'armyBgColor':        armyBgColor,
    'armyImageB64':       armyImageB64,
    'armyLore':           armyLore,
    'armyNotes':          armyNotes,
    'armyListId':         armyListId,
    'saveId':             saveId,
    'saveName':           saveName,
    'tokenBag':        tokenBag.toJson(),
    'units':           units.map((u) => u.toJson()).toList(),
    'roundDiceRolls':  roundDiceRolls,
  };
}
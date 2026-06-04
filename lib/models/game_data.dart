class Faction {
  final String id, name;
  final int color;
  const Faction(this.id, this.name, this.color);
}

class GameUnit {
  final String id, faction, type, name;
  final int atk, def, rng, mob, con, cp, cost;
  final bool unique;
  final List<String> abilities;
  final String? lore;
  const GameUnit({
    required this.id, required this.faction, required this.type,
    required this.name, required this.atk, required this.def,
    required this.rng, required this.mob, required this.con,
    required this.cp, required this.cost, required this.unique,
    required this.abilities, this.lore,
  });
}

class Ability {
  final String name, desc;
  final int cost, cpCost;
  final List<String> types;
  const Ability(this.name, this.desc, this.cost, this.types, {this.cpCost = 0});
}

// ─── BUILT-IN FACTIONS ───────────────────────────────────────
const builtinFactions = <Faction>[];

// ─── BUILT-IN UNITS ──────────────────────────────────────────
const builtinUnits = <GameUnit>[];

// ─── BUILT-IN ABILITIES ──────────────────────────────────────
const builtinAbilities = <Ability>[];

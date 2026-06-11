import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/game_data.dart';
import 'cost_config.dart';

/// Loads all game data from Supabase and merges with builtins.
/// All users share the same data. Developer changes propagate to everyone.
class GameDataService {
  static final _sb = Supabase.instance.client;

  // Merged data — available app-wide after load()
  static List<Map<String, dynamic>> units     = [];
  static List<Map<String, dynamic>> factions  = [];
  static List<Map<String, dynamic>> abilities = [];

  // Builtin ability names that have been deleted/renamed via DevMode
  static List<String> deletedBuiltinAbilityNames = [];

  // User-specific content (private to the logged-in user)
  static List<Map<String, dynamic>> userFactions  = [];
  static List<Map<String, dynamic>> userUnits     = [];
  static List<Map<String, dynamic>> userAbilities = [];

  /// Call once at startup (and after dev changes)
  static Future<void> load() async {
    await Future.wait([
      _loadConfig(),
      _loadUnits(),
      _loadFactions(),
      _loadAbilities(),
    ]);
    await _loadUserContent(); // merges after shared lists are ready
  }

  // â”€â”€ CONFIG (formula + balance tables) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static Future<void> _loadConfig() async {
    try {
      final r = await _sb
          .from('game_config')
          .select('config')
          .eq('id', 'main')
          .single();
      final cfg = r['config'] as Map<String, dynamic>? ?? {};
      if (cfg.isEmpty) return;
      if (cfg['atk']  != null) CostConfig.atk  = List<double>.from(cfg['atk']);
      if (cfg['def']  != null) CostConfig.def  = List<double>.from(cfg['def']);
      if (cfg['rng']  != null) CostConfig.rng  = List<double>.from(cfg['rng']);
      // Support both old (mobI/mobC) and new (mob) config keys
      if (cfg['mob'] != null) {
        CostConfig.mob = List<double>.from(cfg['mob']);
      } else if (cfg['mobC'] != null) {
        CostConfig.mob = List<double>.from(cfg['mobC']);
      }
      if (cfg['con']  != null) CostConfig.con  = List<double>.from(cfg['con']);
      if (cfg['cp']   != null) CostConfig.cp   = List<double>.from(cfg['cp']);
      if (cfg['formulaDivisor'] != null) {
        CostConfig.formulaDivisor =
            (cfg['formulaDivisor'] as num).toDouble();
      }
      if (cfg['deletedAbilityNames'] != null) {
        deletedBuiltinAbilityNames =
            List<String>.from(cfg['deletedAbilityNames'] as List);
      }
    } catch (_) {}
  }

  static Future<void> saveConfig() async {
    try {
      await _sb.from('game_config').upsert({
        'id': 'main',
        'config': {
          'atk':  CostConfig.atk,  'def':  CostConfig.def,
          'rng':  CostConfig.rng,  'mob': CostConfig.mob,
          'con':  CostConfig.con,
          'cp':   CostConfig.cp,
          'formulaDivisor':      CostConfig.formulaDivisor,
          'deletedAbilityNames': deletedBuiltinAbilityNames,
        },
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  /// Marks a builtin ability name as deleted so it no longer appears in the list.
  static Future<void> addDeletedBuiltinAbilityName(String name) async {
    if (!deletedBuiltinAbilityNames.contains(name)) {
      deletedBuiltinAbilityNames.add(name);
      await saveConfig();
    }
  }

  // â”€â”€ UNITS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static Future<void> _loadUnits() async {
    try {
      final db = await _sb.from('custom_units').select('*').order('name');
      final dbList = List<Map<String, dynamic>>.from(db);
      final dbMap  = { for (var u in dbList) u['id'] as String: u };

      final result = <Map<String, dynamic>>[];

      // Merge builtins with DB overrides
      for (final u in builtinUnits) {
        if (dbMap.containsKey(u.id)) {
          final entry = _fromDb(dbMap[u.id]!);
          // Preserve builtin cost when DB row has none (column added later)
          if ((entry['cost'] as int) == 0) entry['cost'] = u.cost;
          result.add(entry);
        } else {
          // Use builtin as-is
          result.add(_fromBuiltin(u));
        }
      }

      // Add pure custom units (not in builtins)
      final builtinIds = builtinUnits.map((u) => u.id).toSet();
      for (final u in dbList) {
        if (!builtinIds.contains(u['id'])) {
          result.add(_fromDb(u));
        }
      }

      result.sort((a, b) =>
          (a['name'] as String).compareTo(b['name'] as String));
      units = result;
    } catch (_) {
      // Fallback to builtins only
      units = builtinUnits.map(_fromBuiltin).toList();
    }
  }

  // â”€â”€ FACTIONS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static Future<void> _loadFactions() async {
    try {
      final db = await _sb.from('custom_factions').select('*').order('name');
      final dbList = List<Map<String, dynamic>>.from(db);
      final dbIds  = dbList.map((f) => f['id'] as String).toSet();

      final result = <Map<String, dynamic>>[];
      // Builtins first (unless overridden in DB)
      for (final f in builtinFactions) {
        if (!dbIds.contains(f.id)) {
          result.add({
            'id':      f.id,
            'name':    f.name,
            'color':   '#${f.color.toRadixString(16).substring(2).toUpperCase()}',
            '_source': 'builtin',
          });
        } else {
          result.add({
            ...dbList.firstWhere((d) => d['id'] == f.id),
            '_source': 'custom',
          });
        }
      }
      // Custom-only factions
      for (final f in dbList) {
        if (!builtinFactions.any((b) => b.id == f['id'])) {
          result.add({...f, '_source': 'custom'});
        }
      }
      factions = result;
    } catch (_) {
      factions = builtinFactions.map((f) => {
        'id': f.id, 'name': f.name,
        'color': '#${f.color.toRadixString(16).substring(2).toUpperCase()}',
      }).toList();
    }
  }

  // â”€â”€ ABILITIES â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static Future<void> _loadAbilities() async {
    try {
      final db = await _sb.from('custom_abilities').select('*').order('name');
      final dbList = List<Map<String, dynamic>>.from(db);
      final dbMap  = { for (var a in dbList) a['name'] as String: a };

      final result = <Map<String, dynamic>>[];
      for (final a in builtinAbilities) {
        // Skip builtins that were deleted/renamed via DevMode
        if (deletedBuiltinAbilityNames.contains(a.name)) continue;
        if (dbMap.containsKey(a.name)) {
          final d = dbMap[a.name]!;
          final dbTypes = d['types'];
          result.add({
            'name':        a.name,
            'description': d['description'] ?? a.desc,
            'cost':        d['cost'] ?? a.cost,
            'cp_cost':     d['cp_cost'] ?? a.cpCost,
            'condition':   d['condition'] as String? ?? '',
            'types':       (dbTypes != null && (dbTypes as List).isNotEmpty)
                             ? List<String>.from(dbTypes)
                             : a.types,
            // Has a DB entry → treat like a user-created ability
            '_builtin':    false,
          });
        } else {
          result.add({
            'name':        a.name,
            'description': a.desc,
            'cost':        a.cost,
            'cp_cost':     a.cpCost,
            'condition':   '',
            'types':       a.types,
            '_builtin':    true,
          });
        }
      }
      // Custom-only abilities (not matching any builtin name)
      for (final a in dbList) {
        if (!builtinAbilities.any((b) => b.name == a['name'])) {
          result.add({...a, '_builtin': false,
            'types': List<String>.from(a['types'] ?? [])});
        }
      }
      abilities = result;
    } catch (_) {
      abilities = builtinAbilities.map((a) => {
        'name': a.name, 'description': a.desc,
        'cost': a.cost, 'cp_cost': 0, 'types': a.types, '_builtin': true,
      }).toList();
    }
  }

  // â”€â”€ USER CONTENT â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static Future<void> _loadUserContent() async {
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) {
        userFactions = []; userUnits = []; userAbilities = [];
        return;
      }
      final r = await Future.wait([
        _sb.from('user_factions').select('*').eq('user_id', uid).order('name'),
        _sb.from('user_units').select('*').eq('user_id', uid).order('name'),
        _sb.from('user_abilities').select('*').eq('user_id', uid).order('name'),
      ]);
      userFactions  = List<Map<String, dynamic>>.from(r[0])
          .map((f) => {...f, '_source': 'user'}).toList();
      final rawUserAbilities = List<Map<String, dynamic>>.from(r[2]);
      userAbilities = rawUserAbilities.map((a) => ({
        ...a,
        'types':    List<String>.from(a['types'] ?? []),
        '_builtin': false,
      })).toList();
      // Build ability-cost map including user abilities for cost calculation
      final allAbCosts = {
        for (final a in [...abilities, ...userAbilities])
          if (a['name'] != null) a['name'] as String: (a['cost'] as int? ?? 0),
      };
      userUnits = List<Map<String, dynamic>>.from(r[1]).map((u) {
        final abs  = List<String>.from(u['abilities'] ?? []);
        final type = (u['type'] as String?) == 'Ranged' ? 'Shooting' : (u['type'] as String? ?? 'Infantry');
        final storedCost = u['cost'] as int? ?? 0;
        final cost = storedCost > 0
            ? storedCost
            : CostConfig.calcCost(
                a:     (u['atk']     as int? ?? 0),
                d:     (u['def_val'] as int? ?? 0),
                s:     (u['rng']     as int? ?? 0),
                m:     (u['mob']     as int? ?? 6),
                str:   (u['con_val'] as int? ?? 3),
                type:  type,
                cpVal: (u['cp']      as int? ?? 0),
                abilities:      abs,
                allAbilityCosts: allAbCosts,
              );
        return {...u, 'abilities': abs, 'type': type, 'cost': cost};
      }).toList();

      // Merge into shared lists so army builder sees user content
      factions  = [...factions,  ...userFactions];
      units     = [...units,     ...userUnits.map(_fromDb)];
      abilities = [...abilities, ...userAbilities];
    } catch (_) {
      userFactions = []; userUnits = []; userAbilities = [];
    }
  }

  // â”€â”€ HELPERS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static Map<String, dynamic> _fromBuiltin(GameUnit u) => {
    'id': u.id, 'name': u.name, 'faction_id': u.faction,
    'type': u.type, 'atk': u.atk, 'def_val': u.def,
    'rng': u.rng, 'mob': u.mob, 'con_val': u.con,
    'cp': u.cp, 'cost': u.cost, 'abilities': u.abilities,
    'unique_unit': u.unique,
  };

  static Map<String, dynamic> _fromDb(Map<String, dynamic> u) => {
    'id':          u['id'],
    'name':        u['name'],
    'faction_id':  u['faction_id'],
    'type':        (u['type'] as String?) == 'Ranged' ? 'Shooting' : u['type'],
    'atk':         u['atk']     ?? 0,
    'def_val':     u['def_val'] ?? 0,
    'rng':         u['rng']     ?? 0,
    'mob':         u['mob']     ?? 6,
    'con_val':     u['con_val'] ?? 3,
    'cp':          u['cp']      ?? 0,
    'cost':        u['cost']    ?? 0,
    'abilities':   List<String>.from(u['abilities'] ?? []),
    'unique_unit': u['unique_unit'] ?? false,
    'image_b64':   u['image_b64'],
    'lore':        u['lore'],
    'bg_color':    u['bg_color'],
  };

  // â”€â”€ LOOKUP HELPERS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static Map<String, dynamic>? unitById(String id) =>
      units.where((u) => u['id'] == id).firstOrNull;

  static Map<String, dynamic>? factionById(String id) =>
      factions.where((f) => f['id'] == id).firstOrNull;

  static Map<String, int> get abilityCosts => {
    for (final a in abilities)
      a['name'] as String: a['cost'] as int,
  };

  // Convert to GameUnit for army usage
  static GameUnit? toGameUnit(String id) {
    final u = unitById(id);
    if (u == null) return null;
    return gameUnitFromMap(u);
  }

  // Reconstruct a GameUnit from a raw unit map (used for embedded shared units).
  static GameUnit? gameUnitFromMap(Map<String, dynamic> u) {
    try {
      int asInt(dynamic v, [int d = 0]) => v == null ? d : (v as num).toInt();
      return GameUnit(
        id:        u['id']          as String,
        name:      u['name']        as String,
        faction:   u['faction_id']  as String? ?? '',
        type:      u['type']        as String,
        atk:       asInt(u['atk']),
        def:       asInt(u['def_val']),
        rng:       asInt(u['rng']),
        mob:       asInt(u['mob'],    6),
        con:       asInt(u['con_val'], 3),
        cp:        asInt(u['cp']),
        cost:      asInt(u['cost']),
        unique:    u['unique_unit'] as bool? ?? false,
        abilities: List<String>.from(u['abilities'] ?? []),
        lore:      u['lore'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
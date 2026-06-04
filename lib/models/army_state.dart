import 'package:flutter/material.dart';
import 'game_data.dart';

class ArmyUnit {
  final String iid;
  final GameUnit unit;
  String customName;
  String groupName;
  String? photoBase64;
  String? bgColor;
  String? lore;   // unit lore / backstory — book icon, edited via dialog
  // True when reconstructed from a shared army's embedded unit definition.
  // The unit exists only within this army; editing requires Premium.
  bool isEmbedded;
  Map<String, dynamic>? embeddedDef;

  ArmyUnit({
    required this.iid,
    required this.unit,
    this.customName  = '',
    this.groupName   = '',
    this.photoBase64,
    this.bgColor,
    this.lore,
    this.isEmbedded  = false,
    this.embeddedDef,
  });

  Map<String, dynamic> toJson() => {
    'iid':     iid,
    'unitId':  unit.id,
    'name':    customName,
    'group':   groupName,
    'photo':   photoBase64,
    'bgColor': bgColor,
    'lore':    lore,
    if (embeddedDef != null) 'embedded_def': embeddedDef,
  };
}

class ArmyState extends ChangeNotifier {
  List<ArmyUnit> units  = [];
  List<String>  groups = []; // custom group names
  int    limit  = 2500;
  String name    = '';
  String? listId;
  List<String> factionIds = []; // selected factions

  int get totalPoints => units.fold(0, (s, u) => s + u.unit.cost);
  int get totalBases  => units.fold(0, (s, u) => s + u.unit.con);
  int get totalCP     => units.fold(0, (s, u) => s + u.unit.cp);
  bool get isOverLimit => totalPoints > limit;

  void addUnit(GameUnit u) {
    final alreadyUnique = units.any((x) => x.unit.id == u.id);
    if (u.unique && alreadyUnique) return;
    units.add(ArmyUnit(
      iid:  'u${DateTime.now().millisecondsSinceEpoch}'
            '${units.length}',
      unit: u,
    ));
    notifyListeners();
  }

  void removeUnit(String iid) {
    units.removeWhere((u) => u.iid == iid);
    notifyListeners();
  }

  void setName(String n)    { name = n; notifyListeners(); }
  void setLimit(int l)      { limit = l; notifyListeners(); }
  void setFactions(List<String> f) { factionIds = List.from(f); notifyListeners(); }
  // ignore: invalid_use_of_protected_member
  void refresh() => notifyListeners();

  void reorderUnit(int oldIndex, int newIndex) {
    if (units.isEmpty) return;
    oldIndex = oldIndex.clamp(0, units.length - 1);
    newIndex = newIndex.clamp(0, units.length - 1);
    if (oldIndex == newIndex) return;
    final u = units.removeAt(oldIndex);
    units.insert(newIndex, u);
    notifyListeners();
  }

  void addGroup(String name) {
    if (name.isNotEmpty && !groups.contains(name)) {
      groups.add(name);
      notifyListeners();
    }
  }

  void removeGroup(String name) {
    groups.remove(name);
    for (final u in units) { if (u.groupName == name) u.groupName = ''; }
    notifyListeners();
  }

  void clear() {
    units     = [];
    name      = '';
    listId    = null;
    factionIds = [];
    groups    = [];
    limit     = 2500;
    notifyListeners();
  }

  Map<String, dynamic> toJson() => {
    'units':      units.map((u) => u.toJson()).toList(),
    'limit':      limit,
    'factionIds': factionIds,
    'groups':     groups,
  };
}
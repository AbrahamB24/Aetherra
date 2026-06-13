import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/army_state.dart';
import '../services/game_data_service.dart';
import '../widgets/nav_btn.dart';
import '../app_theme.dart';

class RosterScreen extends StatefulWidget {
  final String? initialFaction;
  const RosterScreen({super.key, this.initialFaction});
  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  static const gold  = AppColors.gold;
        static const grey  = AppColors.greyLight;

  String _factionFilter = 'all';
  String _typeFilter    = 'all';

  @override
  void initState() {
    super.initState();
    if (widget.initialFaction != null) {
      _factionFilter = widget.initialFaction!;
    }
  }

  List<Map<String, dynamic>> get _filtered => GameDataService.units.where((u) {
    if (_factionFilter != 'all' && u['faction_id'] != _factionFilter) return false;
    if (_typeFilter    != 'all' && u['type']       != _typeFilter)    return false;
    return true;
  }).toList();

  Color _typeColor(String type) {
    if (type == 'Infantry')  return const Color(0xFF2255A8);
    if (type == 'Cavalry')   return const Color(0xFF2E7A40);
    if (type == 'Shooting')  return const Color(0xFFE05090);
    if (type == 'Artillery') return const Color(0xFFB83030);
    if (type == 'Hero')      return const Color(0xFFC9A84C);
    if (type == 'Monster')   return const Color(0xFF7B55C8);
    if (type == 'Flyer')     return const Color(0xFF00D4E8);
    if (type == 'Vehicle')   return const Color(0xFFAFC226);
    return grey;
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.45))),
      child: Text(label,
        style: GoogleFonts.cinzel(
          fontSize: 8, letterSpacing: 1, color: color)),
    );
  }

  Widget _statCell(String label, int value, bool highlight) {
    final display = (value == 0 && label == 'SHO') ? '—' : '$value';
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: gold.withValues(alpha: 0.18)))),
        child: Column(children: [
          Text(label,
            style: GoogleFonts.cinzel(
              fontSize: 8, color: grey, letterSpacing: 1)),
          const SizedBox(height: 2),
          Text(display,
            style: GoogleFonts.cinzel(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: highlight ? gold : Colors.white)),
        ]),
      ),
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap,
      {Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active
            ? (color ?? gold).withValues(alpha: 0.25)
            : AppColors.dark,
          border: Border.all(
            color: active
              ? (color ?? gold)
              : gold.withValues(alpha: 0.2))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
            style: GoogleFonts.cinzel(
              fontSize: 9, letterSpacing: 1,
              color: active ? (color ?? gold) : grey)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final army = context.watch<ArmyState>();

    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        leading: NavBtn(icon: Icons.arrow_back_ios_new, onPressed: () => Navigator.pop(context)),
        title: Text('Unit Roster',
          style: GoogleFonts.cinzel(
            color: gold, fontSize: 14, letterSpacing: 2)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Text('${army.totalPoints} pts',
                style: GoogleFonts.cinzel(
                  color: army.isOverLimit ? Colors.red : gold,
                  fontSize: 12)),
            ),
          ),
        ],
      ),
      body: Column(children: [

        // Filters
        Container(
          color: AppColors.dark,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _chip('All', _factionFilter == 'all',
                  () => setState(() => _factionFilter = 'all')),
                ...GameDataService.factions.map((f) {
                  final fid    = f['id']    as String;
                  final fname  = f['name']  as String;
                  final fColor = AppColors.parseHex(f['color'] as String? ?? '#888888');
                  return _chip(fname, _factionFilter == fid,
                    () => setState(() => _factionFilter = fid),
                    color: fColor);
                }),
              ]),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _chip('All Types', _typeFilter == 'all',
                  () => setState(() => _typeFilter = 'all')),
                _chip('Infantry', _typeFilter == 'Infantry',
                  () => setState(() => _typeFilter = 'Infantry')),
                _chip('Cavalry', _typeFilter == 'Cavalry',
                  () => setState(() => _typeFilter = 'Cavalry')),
                _chip('Shooting', _typeFilter == 'Shooting',
                  () => setState(() => _typeFilter = 'Shooting')),
                _chip('Artillery', _typeFilter == 'Artillery',
                  () => setState(() => _typeFilter = 'Artillery')),
                _chip('Hero', _typeFilter == 'Hero',
                  () => setState(() => _typeFilter = 'Hero')),
                _chip('Monster', _typeFilter == 'Monster',
                  () => setState(() => _typeFilter = 'Monster')),
                _chip('Flyer', _typeFilter == 'Flyer',
                  () => setState(() => _typeFilter = 'Flyer')),
                _chip('Vehicle', _typeFilter == 'Vehicle',
                  () => setState(() => _typeFilter = 'Vehicle')),
              ]),
            ),
          ]),
        ),

        // Unit list
        Expanded(
          child: Stack(children: [
            _filtered.isEmpty
              ? Center(child: Text('No units match this filter.',
                  style: GoogleFonts.cinzel(color: grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) => _unitCard(_filtered[i], army),
                ),
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
          ]),
        ),
      ]),
    );
  }

  Widget _unitCard(Map<String, dynamic> u, ArmyState army) {
    final uid       = u['id']          as String;
    final uname     = u['name']        as String;
    final utype     = u['type']        as String? ?? '';
    final fid       = u['faction_id']  as String? ?? '';
    final isUnique  = u['unique_unit'] as bool?   ?? false;
    final cost      = (u['cost']    as num?)?.toInt() ?? 0;
    final atk       = (u['atk']    as num?)?.toInt() ?? 0;
    final def       = (u['def_val'] as num?)?.toInt() ?? 0;
    final rng       = (u['rng']    as num?)?.toInt() ?? 0;
    final mob       = (u['mob']    as num?)?.toInt() ?? 6;
    final con       = (u['con_val'] as num?)?.toInt() ?? 3;
    final cp        = (u['cp']     as num?)?.toInt() ?? 0;
    final abilities = List<String>.from(u['abilities'] ?? []);

    final fac      = GameDataService.factions.where((f) => f['id'] == fid).firstOrNull;
    final facName  = fac?['name']  as String? ?? '';
    final facColor = AppColors.parseHex(fac?['color'] as String? ?? '#888888');
    final typeColor    = _typeColor(utype);
    final alreadyAdded = army.units.any((x) => x.unit.id == uid);
    final isDisabled   = isUnique && alreadyAdded;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.dark,
        border: Border.all(
          color: utype == 'Hero'
            ? const Color(0xFFC8A0E0).withValues(alpha: 0.35)
            : gold.withValues(alpha: 0.18))),
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // Name + cost
            Row(children: [
              Expanded(
                child: Text(uname,
                  style: GoogleFonts.cinzel(
                    color: AppColors.goldLight, fontSize: 14)),
              ),
              Text('$cost pts',
                style: GoogleFonts.cinzel(color: gold, fontSize: 12)),
            ]),
            const SizedBox(height: 6),

            // Badges
            Row(children: [
              _badge(utype, typeColor),
              const SizedBox(width: 6),
              _badge(facName, facColor),
              if (isUnique) ...[
                const SizedBox(width: 6),
                const Text('Unique',
                  style: TextStyle(
                    color: Color(0xFFC8A0E0),
                    fontSize: 9,
                    fontStyle: FontStyle.italic)),
              ],
              if (cp > 0) ...[
                const SizedBox(width: 6),
                _badge('$cp CP', const Color(0xFFC8A0E0)),
              ],
            ]),
            const SizedBox(height: 8),

            // Stats
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: gold.withValues(alpha: 0.18))),
              child: Row(children: [
                _statCell('ATK', atk, atk >= 5),
                _statCell('DEF', def, def >= 5),
                _statCell('SHO', rng, rng > 0),
                _statCell('MOB', mob, mob >= 10),
                _statCell('STR', con, false),
              ]),
            ),
            const SizedBox(height: 8),

            // Abilities inline
            ...abilities.map((a) {
              final ab   = GameDataService.abilities
                .where((x) => x['name'] == a).firstOrNull;
              final desc = ab?['description'] as String? ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: RichText(
                  text: TextSpan(children: [
                    TextSpan(text: '$a  ',
                      style: GoogleFonts.cinzel(
                        color: const Color(0xFF7A6430),
                        fontSize: 10)),
                    TextSpan(text: desc,
                      style: const TextStyle(
                        color: grey,
                        fontSize: 12,
                        fontStyle: FontStyle.italic)),
                  ]),
                ),
              );
            }),
            const SizedBox(height: 8),

            // Add button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: isDisabled ? null : () {
                  final gu = GameDataService.gameUnitFromMap(u);
                  if (gu == null) return;
                  army.addUnit(gu);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppColors.dark,
                      content: Text('$uname added!',
                        style: GoogleFonts.cinzel(color: gold)),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDisabled
                    ? grey : const Color(0xFF7A6430),
                  side: BorderSide(
                    color: isDisabled
                      ? gold.withValues(alpha: 0.15)
                      : gold.withValues(alpha: 0.45)),
                  shape: const RoundedRectangleBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                child: Text(
                  isDisabled ? '✓ Selected' : 'Add to Army',
                  style: GoogleFonts.cinzel(
                    fontSize: 10, letterSpacing: 2)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
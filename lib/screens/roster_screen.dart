import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/army_state.dart';
import '../models/game_data.dart';
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

  List<GameUnit> get _filtered => builtinUnits.where((u) {
    if (_factionFilter != 'all' && u.faction != _factionFilter) return false;
    if (_typeFilter    != 'all' && u.type    != _typeFilter)    return false;
    return true;
  }).toList();

  Color _typeColor(String type) {
    if (type == 'Infantry')  return const Color(0xFF4A90D0);
    if (type == 'Cavalry')   return const Color(0xFF5CAE68);
    if (type == 'Shooting')  return const Color(0xFFE05090);
    if (type == 'Artillery') return const Color(0xFFB83030);
    if (type == 'Hero')      return const Color(0xFFC9A84C);
    if (type == 'Monster')   return const Color(0xFF7B55C8);
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
                _chip('Uruk-Hai', _factionFilter == 'uruk',
                  () => setState(() => _factionFilter = 'uruk'),
                  color: const Color(0xFF8C4A4A)),
                _chip('Gondor', _factionFilter == 'gondor',
                  () => setState(() => _factionFilter = 'gondor'),
                  color: const Color(0xFF4A6E9C)),
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
              ]),
            ),
          ]),
        ),

        // Unit list
        Expanded(
          child: _filtered.isEmpty
            ? Center(child: Text('No units match this filter.',
                style: GoogleFonts.cinzel(color: grey)))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _filtered.length,
                itemBuilder: (_, i) => _unitCard(_filtered[i], army),
              ),
        ),
      ]),
    );
  }

  Widget _unitCard(GameUnit u, ArmyState army) {
    final faction = builtinFactions.firstWhere(
      (f) => f.id == u.faction,
      orElse: () => const Faction('', '', 0xFF888888));
    final typeColor   = _typeColor(u.type);
    final alreadyAdded = army.units.any((x) => x.unit.id == u.id);
    final isDisabled   = u.unique && alreadyAdded;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.dark,
        border: Border.all(
          color: u.type == 'Hero'
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
                child: Text(u.name,
                  style: GoogleFonts.cinzel(
                    color: AppColors.goldLight, fontSize: 14)),
              ),
              Text('${u.cost} pts',
                style: GoogleFonts.cinzel(color: gold, fontSize: 12)),
            ]),
            const SizedBox(height: 6),

            // Badges
            Row(children: [
              _badge(u.type, typeColor),
              const SizedBox(width: 6),
              _badge(faction.name, Color(faction.color)),
              if (u.unique) ...[
                const SizedBox(width: 6),
                const Text('Unique',
                  style: TextStyle(
                    color: Color(0xFFC8A0E0),
                    fontSize: 9,
                    fontStyle: FontStyle.italic)),
              ],
              if (u.cp > 0) ...[
                const SizedBox(width: 6),
                _badge('${u.cp} CP', const Color(0xFFC8A0E0)),
              ],
            ]),
            const SizedBox(height: 8),

            // Stats
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: gold.withValues(alpha: 0.18))),
              child: Row(children: [
                _statCell('ATK', u.atk, u.atk >= 5),
                _statCell('DEF', u.def, u.def >= 5),
                _statCell('SHO', u.rng, u.rng > 0),
                _statCell('MOB', u.mob, u.mob >= 10),
                _statCell('STR', u.con, false),
              ]),
            ),
            const SizedBox(height: 8),

            // Abilities inline
            ...u.abilities.map((a) {
              final ab = builtinAbilities
                .where((x) => x.name == a)
                .firstOrNull;
              return Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: RichText(
                  text: TextSpan(children: [
                    TextSpan(text: '$a  ',
                      style: GoogleFonts.cinzel(
                        color: const Color(0xFF7A6430),
                        fontSize: 10)),
                    TextSpan(text: ab?.desc ?? '',
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
                  army.addUnit(u);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppColors.dark,
                      content: Text('${u.name} added!',
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
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_theme.dart';
import '../services/stats_service.dart';
import '../widgets/nav_btn.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  static const gold = AppColors.gold;

  PlayerStats? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await StatsService.load();
    if (mounted) setState(() => _stats = s);
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        leading: NavBtn(icon: Icons.arrow_back_ios_new,
          onPressed: () => Navigator.pop(context)),
        title: Text('Statistics',
          style: GoogleFonts.cinzel(
            color: gold, fontSize: 17, letterSpacing: 2)),
      ),
      body: s == null
        ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
        : s.games == 0
          ? _empty()
          : _content(s),
    );
  }

  Widget _empty() => Center(child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.bar_chart, color: AppColors.grey.withValues(alpha: 0.25), size: 48),
      const SizedBox(height: 16),
      Text('No games played yet',
        style: GoogleFonts.cinzel(
          color: AppColors.grey.withValues(alpha: 0.4),
          fontSize: 14)),
    ]));

  Widget _content(PlayerStats s) {
    final avg = s.avgRounds.toStringAsFixed(1);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 40),
      children: [
        // Decorative line + section title
        Align(alignment: Alignment.centerLeft,
          child: Container(height: 1, width: 48, color: gold.withValues(alpha: 0.35))),
        const SizedBox(height: 20),
        Text('Battle Record',
          style: GoogleFonts.cinzel(
            color: gold, fontSize: 12, letterSpacing: 1.6)),
        const SizedBox(height: 16),

        // 2×2 grid
        Row(children: [
          Expanded(child: _Tile(value: '${s.games}',      label: 'Games Played')),
          const SizedBox(width: 8),
          Expanded(child: _Tile(value: avg,               label: 'Avg Rounds')),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _Tile(value: '${s.unitsLost}',  label: 'Units Lost')),
          const SizedBox(width: 8),
          Expanded(child: _Tile(value: '${s.totalStrLost}', label: 'STR Lost Total')),
        ]),

        // Favourite army
        if (s.favouriteArmy != null) ...[
          const SizedBox(height: 28),
          Align(alignment: Alignment.centerLeft,
            child: Container(height: 1, width: 48, color: gold.withValues(alpha: 0.35))),
          const SizedBox(height: 20),
          Text('Favourite Army',
            style: GoogleFonts.cinzel(
              color: gold, fontSize: 12, letterSpacing: 1.6)),
          const SizedBox(height: 16),
          _Tile(
            value: s.favouriteArmy!,
            label: 'Most Played',
            large: true),
        ],
      ],
    );
  }
}

// ── Stat tile ─────────────────────────────────────────────────────────────────

class _Tile extends StatelessWidget {
  final String value;
  final String label;
  final bool   large;
  const _Tile({required this.value, required this.label, this.large = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.gold.withValues(alpha: 0.18))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value,
        style: GoogleFonts.cinzel(
          color: AppColors.gold,
          fontSize: large ? 16 : 24,
          fontWeight: FontWeight.w700)),
      const SizedBox(height: 5),
      Text(label,
        style: GoogleFonts.cinzel(
          color: AppColors.grey.withValues(alpha: 0.5),
          fontSize: 10, letterSpacing: 1)),
    ]));
}

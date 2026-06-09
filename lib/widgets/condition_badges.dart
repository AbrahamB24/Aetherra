import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_theme.dart';

const List<(String, Color)> kConditions = [
  ('Stunned',   Color(0xFFE89C40)),
  ('Pinned',    Color(0xFF5B8DC0)),
  ('Wounded',   Color(0xFFCF4040)),
  ('Exhausted', Color(0xFF7A8090)),
  ('Hidden',    Color(0xFF5A9060)),
];

Color conditionColor(String name) => kConditions
    .firstWhere((c) => c.$1 == name, orElse: () => (name, AppColors.grey)).$2;

/// Condition badge row for game screens.
/// [onToggle] = null → read-only (opponent cards).
class ConditionBadges extends StatelessWidget {
  final List<String> conditions;
  final void Function(String)? onToggle;

  const ConditionBadges({super.key, required this.conditions, this.onToggle});

  bool get _interactive => onToggle != null;

  void _openPicker(BuildContext ctx) {
    final available =
        kConditions.where((c) => !conditions.contains(c.$1)).toList();
    if (available.isEmpty) return;
    showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: AppColors.dark,
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(ctx).padding.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.grey.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Text('Add Status',
            style: GoogleFonts.cinzel(
              color: AppColors.gold, fontSize: 15,
              fontWeight: FontWeight.w600, letterSpacing: 1)),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (name, color) in available)
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  onToggle!(name);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    border: Border.all(color: color.withValues(alpha: 0.55))),
                  child: Text(name,
                    style: GoogleFonts.cinzel(
                      color: color, fontSize: 13,
                      fontWeight: FontWeight.w600)))),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_interactive && conditions.isEmpty) return const SizedBox.shrink();

    final hasMore = _interactive &&
        conditions.length < kConditions.length;

    return Container(
      color: AppColors.dark,
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      child: Wrap(spacing: 4, runSpacing: 4, children: [
        ...conditions.map((c) {
          final color = conditionColor(c);
          return GestureDetector(
            onTap: _interactive ? () => onToggle!(c) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                border: Border.all(color: color.withValues(alpha: 0.5))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(c,
                  style: GoogleFonts.cinzel(
                    color: color, fontSize: 9,
                    fontWeight: FontWeight.w600)),
                if (_interactive) ...[
                  const SizedBox(width: 3),
                  Icon(Icons.close, size: 9,
                    color: color.withValues(alpha: 0.7)),
                ],
              ]),
            ),
          );
        }),
        if (hasMore)
          Builder(builder: (ctx) => GestureDetector(
            onTap: () => _openPicker(ctx),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppColors.grey.withValues(alpha: 0.3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add, size: 10,
                  color: AppColors.grey.withValues(alpha: 0.55)),
                const SizedBox(width: 2),
                Text('Status',
                  style: GoogleFonts.cinzel(
                    color: AppColors.grey.withValues(alpha: 0.55),
                    fontSize: 9)),
              ]),
            ),
          )),
      ]),
    );
  }
}

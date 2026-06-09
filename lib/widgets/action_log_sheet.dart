import 'dart:math' show max;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_theme.dart';
import '../game/models/game_state.dart';
import 'd20_icon.dart';

void showActionLogSheet(BuildContext ctx, List<ActionLogEntry> log) {
  showModalBottomSheet<void>(
    context: ctx,
    isScrollControlled: true,
    backgroundColor: AppColors.dark,
    builder: (_) => _ActionLogSheet(log: log));
}

// ── Sheet ─────────────────────────────────────────────────────────────────────
class _ActionLogSheet extends StatefulWidget {
  final List<ActionLogEntry> log;
  const _ActionLogSheet({required this.log});
  @override State<_ActionLogSheet> createState() => _ActionLogSheetState();
}

class _ActionLogSheetState extends State<_ActionLogSheet> {
  late final List<ActionLogEntry> _reversed;
  // displayed round number (from divider text "Round N") → key on that tile
  final _roundKeys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _reversed = widget.log.reversed.toList();
    for (final e in _reversed) {
      if (e.tag == 'round') {
        final n = _roundFromText(e.text);
        if (n != null && !_roundKeys.containsKey(n)) _roundKeys[n] = GlobalKey();
      }
    }
  }

  static int? _roundFromText(String text) {
    final m = RegExp(r'Round (\d+)').firstMatch(text);
    return m != null ? int.tryParse(m.group(1)!) : null;
  }

  void _jump(int round) {
    final ctx = _roundKeys[round]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
        alignment: 0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show newest round first in the chip bar
    final rounds = _roundKeys.keys.toList()..sort((a, b) => b.compareTo(a));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, scroll) => Column(children: [
        const SizedBox(height: 12),
        Center(child: Container(width: 40, height: 4,
          decoration: BoxDecoration(
            color: AppColors.grey.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 12),
        Text('Action Log',
          style: GoogleFonts.cinzel(
            color: AppColors.gold, fontSize: 15, letterSpacing: 1)),
        const SizedBox(height: 8),
        // Round-jump dropdown (only when multiple rounds played)
        if (rounds.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Row(children: [
              Theme(
                data: Theme.of(context).copyWith(
                  splashFactory:  NoSplash.splashFactory,
                  highlightColor: Colors.transparent,
                  splashColor:    Colors.transparent,
                  hoverColor:     Colors.transparent),
                child: PopupMenuButton<int>(
                  color:          AppColors.dark,
                  shape:          const RoundedRectangleBorder(),
                  tooltip:        '',
                  padding:        EdgeInsets.zero,
                  enableFeedback: false,
                  onSelected:     _jump,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.gold.withValues(alpha: 0.4))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('Jump to Round',
                        style: GoogleFonts.cinzel(
                          color: AppColors.gold.withValues(alpha: 0.75),
                          fontSize: 11, letterSpacing: 0.5)),
                      const SizedBox(width: 4),
                      Icon(Icons.keyboard_arrow_down,
                        color: AppColors.gold.withValues(alpha: 0.75), size: 15),
                    ])),
                  itemBuilder: (_) => [
                    for (final r in rounds)
                      PopupMenuItem<int>(
                        value:   r,
                        padding: EdgeInsets.zero,
                        child:   _RoundMenuItem(round: r)),
                  ])),
            ])),
        ],
        Expanded(child: _reversed.isEmpty
          ? Center(child: Text('No actions yet',
              style: GoogleFonts.cinzel(color: AppColors.grey, fontSize: 13)))
          : ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              children: _reversed.map((e) {
                GlobalKey? key;
                if (e.tag == 'round') {
                  final n = _roundFromText(e.text);
                  if (n != null) key = _roundKeys[n];
                }
                return ActionLogTile(key: key, entry: e);
              }).toList(),
            )),
      ]));
  }
}

// ── Tile ──────────────────────────────────────────────────────────────────────
class ActionLogTile extends StatelessWidget {
  final ActionLogEntry entry;
  const ActionLogTile({super.key, required this.entry});

  static const _tagIcons = <String, IconData>{
    'damage':    Icons.favorite,
    'heal':      Icons.favorite,
    'eliminate': Icons.highlight_off,
    'activate':  Icons.check_circle_outline,
    'condition': Icons.warning_amber_outlined,
    'cp':        Icons.bolt_outlined,
    'token':     Icons.casino_outlined,
    'round':     Icons.flag_outlined,
    'dice':      Icons.circle_outlined, // unused — _DiceTile renders D20Icon
  };

  static const _tagColors = <String, Color>{
    'damage':    Color(0xFFCF4040),
    'heal':      Color(0xFF5A9060),
    'eliminate': Color(0xFF888888),
    'activate':  Color(0xFFC9A84C),
    'condition': Color(0xFFE07828),
    'cp':        Color(0xFF8855CC),
    'token':     Color(0xFF9870CC),
    'round':     Color(0xFFC9A84C),
    'dice':      Color(0xFF70C0B8),
  };

  @override
  Widget build(BuildContext context) {
    final color = _tagColors[entry.tag] ?? AppColors.grey;
    final icon  = _tagIcons[entry.tag]  ?? Icons.circle_outlined;

    if (entry.tag == 'round') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Divider(
            color: AppColors.gold.withValues(alpha: 0.25), height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(entry.text,
              style: GoogleFonts.cinzel(
                color: AppColors.gold.withValues(alpha: 0.7),
                fontSize: 10, letterSpacing: 1))),
          Expanded(child: Divider(
            color: AppColors.gold.withValues(alpha: 0.25), height: 1)),
        ]));
    }

    if (entry.tag == 'dice') return _DiceTile(entry: entry, color: color);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(icon, size: 13, color: color.withValues(alpha: 0.8)),
        const SizedBox(width: 7),
        Expanded(child: Text(entry.text,
          style: GoogleFonts.cinzel(color: AppColors.grey, fontSize: 11))),
        if (entry.player != null) ...[
          const SizedBox(width: 6),
          _PlayerChip(name: entry.player!),
        ],
      ]));
  }
}

// ── Round menu item ───────────────────────────────────────────────────────────
class _RoundMenuItem extends StatefulWidget {
  final int round;
  const _RoundMenuItem({required this.round});
  @override State<_RoundMenuItem> createState() => _RoundMenuItemState();
}
class _RoundMenuItemState extends State<_RoundMenuItem> {
  bool _hovered = false;
  @override Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit:  (_) => setState(() => _hovered = false),
    cursor: SystemMouseCursors.click,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text('Round ${widget.round}',
        style: GoogleFonts.cinzel(
          color: _hovered
            ? AppColors.gold
            : AppColors.gold.withValues(alpha: 0.55),
          fontSize: 13))));
}

// ── Player chip ───────────────────────────────────────────────────────────────
class _PlayerChip extends StatelessWidget {
  final String name;
  const _PlayerChip({required this.name});

  @override
  Widget build(BuildContext context) {
    final label = name.length > 10 ? '${name.substring(0, 9)}…' : name;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35))),
      child: Text(label,
        style: GoogleFonts.cinzel(
          color: AppColors.gold.withValues(alpha: 0.65),
          fontSize: 8, letterSpacing: 0.5)));
  }
}

// ── Dice tile ─────────────────────────────────────────────────────────────────
class _DiceTile extends StatelessWidget {
  final ActionLogEntry entry;
  final Color color;
  const _DiceTile({required this.entry, required this.color});

  static List<int> _parse(String text) {
    final m = RegExp(r'Roll: ([\d, ]+)').firstMatch(text);
    if (m == null) return [];
    return m.group(1)!.split(', ').map(int.tryParse).whereType<int>().toList();
  }

  @override
  Widget build(BuildContext context) {
    final values = _parse(entry.text);
    final maxVal = values.isEmpty ? 0 : values.reduce(max);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(width: 13, height: 13, child: D20Icon(color: color, size: 13)),
        const SizedBox(width: 7),
        Expanded(
          child: Wrap(spacing: 4, runSpacing: 4, children: [
            for (final v in values)
              _DieChip(value: v, isMax: v == maxVal, highlightColor: color),
          ]),
        ),
        if (entry.player != null) ...[
          const SizedBox(width: 6),
          _PlayerChip(name: entry.player!),
        ],
      ]));
  }
}

// ── Die chip ──────────────────────────────────────────────────────────────────
class _DieChip extends StatelessWidget {
  final int   value;
  final bool  isMax;
  final Color highlightColor;
  const _DieChip(
      {required this.value, required this.isMax, required this.highlightColor});

  @override
  Widget build(BuildContext context) {
    final hi = highlightColor;
    const lo = AppColors.grey;
    return Container(
      width: 22, height: 22,
      decoration: BoxDecoration(
        color: isMax ? hi.withValues(alpha: 0.15) : lo.withValues(alpha: 0.06),
        border: Border.all(
          color: isMax ? hi.withValues(alpha: 0.75) : lo.withValues(alpha: 0.25),
          width: isMax ? 1.2 : 0.8)),
      alignment: Alignment.center,
      child: Text('$value',
        style: GoogleFonts.cinzel(
          color: isMax ? hi : lo.withValues(alpha: 0.65),
          fontSize: 10,
          fontWeight: isMax ? FontWeight.w700 : FontWeight.w400)));
  }
}

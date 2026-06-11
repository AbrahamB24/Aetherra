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

// ── Color & icon maps ─────────────────────────────────────────────────────────
//
// Palette (all distinct):
//   damage   → red     #CF4040  ❤  favorite
//   heal     → green   #5A9060  ❤  favorite
//   eliminate→ grey    #888888  ⊗  highlight_off
//   activate → gold    #C9A84C  ✓  check_circle_outline
//   reactive → purple  #8855CC  ■  solid square  (reactive = costs AP)
//   cp       → indigo  #4466BB  ⚡ bolt_outlined   (AP pool change)
//   condition→ orange  #E07828  ⚠  warning_amber_outlined
//   token    → sky     #3A8FC0  ■  solid square
//   dice     → teal    #70C0B8  D20
//   round    → gold    #C9A84C  (divider only)

const _tagColors = <String, Color>{
  'damage':    Color(0xFFCF4040),
  'heal':      Color(0xFF5A9060),
  'eliminate': Color(0xFF888888),
  'activate':  Color(0xFFC9A84C),
  'ready':     Color(0xFF6B7A8D),
  'reactive':  Color(0xFF8855CC),
  'condition': Color(0xFFE07828),
  'cp':        Color(0xFF4466BB),
  'token':     Color(0xFF3A8FC0),
  'round':     Color(0xFFC9A84C),
  'dice':      Color(0xFF70C0B8),
};

// Tags that use a solid square instead of an outlined icon
const _squareTags = {'token'};

const _tagIcons = <String, IconData>{
  'damage':    Icons.favorite,
  'heal':      Icons.favorite,
  'eliminate': Icons.highlight_off,
  'activate':  Icons.check_circle_outline,
  'ready':     Icons.radio_button_unchecked,
  'reactive':  Icons.bolt_outlined,
  'condition': Icons.warning_amber_outlined,
  'cp':        Icons.bolt_outlined,
  'token':     Icons.square,
  'round':     Icons.flag_outlined,
  'dice':      Icons.circle_outlined, // unused — _DiceTile renders D20Icon
};

// ── Filter groups ─────────────────────────────────────────────────────────────
const _filterGroups = <String, List<String>>{
  'STR':      ['damage', 'heal', 'eliminate'],
  'CP':       ['cp', 'reactive'],
  'Activate': ['activate', 'ready'],
  'Status':   ['condition'],
  'Tokens':   ['token'],
  'Dice':     ['dice'],
};

const _filterIcons = <String, IconData>{
  'STR':      Icons.favorite,
  'CP':       Icons.bolt_outlined, // cp = indigo bolt, reactive = purple bolt
  'Activate': Icons.check_circle_outline,
  'Status':   Icons.warning_amber_outlined,
  'Tokens':   Icons.square,
  'Dice':     Icons.circle_outlined,
};

const _filterColors = <String, Color>{
  'STR':      Color(0xFFCF4040),
  'CP':       Color(0xFF8855CC),
  'Activate': Color(0xFFC9A84C),
  'Status':   Color(0xFFE07828),
  'Tokens':   Color(0xFF3A8FC0),
  'Dice':     Color(0xFF70C0B8),
};

// ── Sheet ─────────────────────────────────────────────────────────────────────
class _ActionLogSheet extends StatefulWidget {
  final List<ActionLogEntry> log;
  const _ActionLogSheet({required this.log});
  @override State<_ActionLogSheet> createState() => _ActionLogSheetState();
}

class _ActionLogSheetState extends State<_ActionLogSheet> {
  late final List<ActionLogEntry> _reversed;
  final _roundKeys = <int, GlobalKey>{};
  String? _filterGroup; // null = All

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

  bool _isVisible(ActionLogEntry e) {
    if (_filterGroup == null) return true;
    if (e.tag == 'round') return true; // always show round dividers for context
    return (_filterGroups[_filterGroup] ?? []).contains(e.tag);
  }

  @override
  Widget build(BuildContext context) {
    final rounds  = _roundKeys.keys.toList()..sort((a, b) => b.compareTo(a));
    final visible = _reversed.where(_isVisible).toList();

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

        // ── Dropdowns row (round-jump + filter) ──────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Theme(
            data: Theme.of(context).copyWith(
              splashFactory:  NoSplash.splashFactory,
              highlightColor: Colors.transparent,
              splashColor:    Colors.transparent,
              hoverColor:     Colors.transparent),
            child: Row(children: [
              // Round jump
              if (rounds.isNotEmpty) ...[
                PopupMenuButton<int>(
                  color:          AppColors.dark,
                  shape:          const RoundedRectangleBorder(),
                  tooltip:        '',
                  padding:        EdgeInsets.zero,
                  enableFeedback: false,
                  onSelected:     _jump,
                  child: const _DropdownLabel(
                    label: 'Round',
                    active: false),
                  itemBuilder: (_) => [
                    for (final r in rounds)
                      PopupMenuItem<int>(
                        value:   r,
                        padding: EdgeInsets.zero,
                        child:   _RoundMenuItem(round: r)),
                  ]),
                const SizedBox(width: 8),
              ],
              // Filter — use 'all' sentinel because PopupMenuButton skips null onSelected
              PopupMenuButton<String>(
                color:          AppColors.dark,
                shape:          const RoundedRectangleBorder(),
                tooltip:        '',
                padding:        EdgeInsets.zero,
                enableFeedback: false,
                onSelected: (v) =>
                    setState(() => _filterGroup = v == 'all' ? null : v),
                child: _DropdownLabel(
                  label: _filterGroup ?? 'All',
                  active: _filterGroup != null),
                itemBuilder: (_) => [
                  PopupMenuItem<String>(
                    value:   'all',
                    padding: EdgeInsets.zero,
                    child:   _FilterMenuItem(
                      label: 'All', icon: Icons.list_outlined,
                      color: AppColors.grey, active: _filterGroup == null)),
                  for (final group in _filterGroups.keys)
                    PopupMenuItem<String>(
                      value:   group,
                      padding: EdgeInsets.zero,
                      child:   _FilterMenuItem(
                        label:  group,
                        icon:   _filterIcons[group]!,
                        color:  _filterColors[group]!,
                        active: _filterGroup == group,
                        isDice: group == 'Dice')),
                ]),
            ]))),

        // ── Log list ──────────────────────────────────────────────────────────
        Expanded(child: visible.isEmpty
          ? Center(child: Text('No entries',
              style: GoogleFonts.cinzel(color: AppColors.grey, fontSize: 13)))
          : ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              children: visible.map((e) {
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

// ── Dropdown trigger label ────────────────────────────────────────────────────
class _DropdownLabel extends StatelessWidget {
  final String label;
  final bool   active; // true when a non-default value is selected
  const _DropdownLabel({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    final col = active ? AppColors.gold : AppColors.gold.withValues(alpha: 0.65);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(
          color: active
              ? AppColors.gold.withValues(alpha: 0.6)
              : AppColors.gold.withValues(alpha: 0.35))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
          style: GoogleFonts.cinzel(
            color: col, fontSize: 11, letterSpacing: 0.5)),
        const SizedBox(width: 4),
        Icon(Icons.keyboard_arrow_down, color: col, size: 15),
      ]));
  }
}

// ── Filter dropdown menu item ─────────────────────────────────────────────────
class _FilterMenuItem extends StatefulWidget {
  final String   label;
  final IconData icon;
  final Color    color;
  final bool     active;
  final bool     isDice;
  const _FilterMenuItem({
    required this.label, required this.icon,
    required this.color, required this.active,
    this.isDice = false});
  @override State<_FilterMenuItem> createState() => _FilterMenuItemState();
}
class _FilterMenuItemState extends State<_FilterMenuItem> {
  bool _hovered = false;
  @override Widget build(BuildContext context) {
    final on  = widget.active || _hovered;
    final col = on ? widget.color : AppColors.grey.withValues(alpha: 0.6);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(children: [
          SizedBox(width: 12, height: 12,
            child: widget.isDice
              ? D20Icon(color: col, size: 12)
              : Icon(widget.icon, size: 12, color: col)),
          const SizedBox(width: 8),
          Text(widget.label,
            style: GoogleFonts.cinzel(
              color: col, fontSize: 12,
              fontWeight: on ? FontWeight.w600 : FontWeight.w400)),
        ])));
  }
}

// ── Tile ──────────────────────────────────────────────────────────────────────
class ActionLogTile extends StatelessWidget {
  final ActionLogEntry entry;
  const ActionLogTile({super.key, required this.entry});

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
        SizedBox(width: 13, height: 13,
          child: _squareTags.contains(entry.tag)
            ? Center(child: Container(
                width: 9, height: 9,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(2))))
            : Icon(icon, size: 13, color: color.withValues(alpha: 0.8))),
        const SizedBox(width: 7),
        Expanded(child: () {
          final keyword = entry.tag == 'activate' ? 'activated'
                        : entry.tag == 'ready'    ? 'ready'
                        : null;
          final base = GoogleFonts.cinzel(color: AppColors.grey, fontSize: 11);
          if (keyword == null) return Text(entry.text, style: base);
          final idx = entry.text.lastIndexOf(keyword);
          if (idx == -1)        return Text(entry.text, style: base);
          return Text.rich(TextSpan(style: base, children: [
            if (idx > 0) TextSpan(text: entry.text.substring(0, idx)),
            TextSpan(text: keyword,
              style: TextStyle(color: color.withValues(alpha: 0.9))),
            if (idx + keyword.length < entry.text.length)
              TextSpan(text: entry.text.substring(idx + keyword.length)),
          ]));
        }()),
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

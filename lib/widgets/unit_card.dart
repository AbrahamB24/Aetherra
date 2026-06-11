import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/game_data.dart';
import '../services/game_data_service.dart';
import '../app_theme.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget abilityBadge(String ability, {double fontSize = 11, Color? tColor, VoidCallback? onUse}) =>
  _AbilityBadge(ability: ability, fontSize: fontSize, tColor: tColor, onUse: onUse);

class _AbilityBadge extends StatefulWidget {
  final String ability;
  final double fontSize;
  final Color? tColor;
  final VoidCallback? onUse;
  const _AbilityBadge({required this.ability, required this.fontSize, this.tColor, this.onUse});
  @override State<_AbilityBadge> createState() => _AbilityBadgeState();
}
class _AbilityBadgeState extends State<_AbilityBadge> {
  bool _hovered = false;
  OverlayEntry? _overlay;
  Timer? _hideTimer;

  static const gold     = AppColors.gold;
  void _hideOverlay() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _overlay?.remove();
    _overlay = null;
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 80), _hideOverlay);
  }

  @override void dispose() {
    _hideTimer?.cancel();
    _overlay?.remove();
    super.dispose();
  }

  @override Widget build(BuildContext context) {
    final ab     = GameDataService.abilities.where((x) => x['name'] == widget.ability).firstOrNull;
    final desc   = ab?['description'] as String? ?? '';
    final cpCost = ab?['cp_cost'] as int? ?? 0;
    final isCmd  = cpCost > 0;
    final c      = isCmd ? gold : (widget.tColor ?? AppColors.grey);
    final textC  = Color.lerp(c, Colors.white, isCmd ? 0.15 : 0.55)!;
    final hasUse = widget.onUse != null;

    void showOverlay() {
      _hideOverlay();
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null) return;
      final pos = box.localToGlobal(Offset.zero);
      final sz  = box.size;

      final Widget content = Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(child: Text(widget.ability, style: GoogleFonts.cinzel(
                color: gold, fontSize: 11, fontWeight: FontWeight.w700))),
              if (isCmd) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: gold.withValues(alpha: 0.18),
                    border: Border.all(color: gold.withValues(alpha: 0.6))),
                  child: Text('$cpCost CP', style: GoogleFonts.cinzel(
                    color: gold, fontSize: 9,
                    fontWeight: FontWeight.w700, letterSpacing: 1))),
              ],
            ]),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(desc, style: GoogleFonts.cinzel(
                color: const Color(0xFFD8D0C0), fontSize: 11, height: 1.4)),
            ],
            if (hasUse) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: PressBtn(
                  label: 'Use',
                  onTap: () { _hideOverlay(); widget.onUse!(); },
                  bg: gold,
                  fg: AppColors.dark,
                  fontSize: 10,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
              ),
            ],
          ],
        ),
      );

      _overlay = OverlayEntry(builder: (ctx) {
        final screen = MediaQuery.of(ctx).size;
        const maxW = 284.0;
        final left = pos.dx.clamp(0.0, (screen.width - maxW).clamp(0.0, screen.width));
        final spaceBelow = screen.height - (pos.dy + sz.height);
        final showAbove  = spaceBelow < 180 && pos.dy > spaceBelow;
        final topPos     = pos.dy + sz.height + 5;
        final botPos     = screen.height - pos.dy + 5;
        return Stack(children: [
          Positioned.fill(child: Listener(
            onPointerDown: (_) => _hideOverlay(),
            behavior: HitTestBehavior.translucent,
            child: const SizedBox.expand())),
          Positioned(
            left: left,
            top:    showAbove ? null : topPos,
            bottom: showAbove ? botPos : null,
            child: Material(
              color: Colors.transparent,
              child: MouseRegion(
                onEnter: hasUse ? (_) { _hideTimer?.cancel(); } : null,
                onExit:  hasUse ? (_) => _hideOverlay() : null,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 280, minWidth: 160),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(color: gold.withValues(alpha: 0.5))),
                  child: content)))),
        ]);
      });
      Overlay.of(context).insert(_overlay!);
    }

    final badge = AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: ShapeDecoration(
        color: isCmd
            ? c.withValues(alpha: _hovered ? 1.0 : 0.82)
            : c.withValues(alpha: _hovered ? 0.26 : 0.15),
        shape: BeveledRectangleBorder(
          side: BorderSide.none,
          borderRadius: BorderRadius.circular(4))),
      child: Text(widget.ability,
        style: GoogleFonts.cinzel(
          color: isCmd
              ? (_hovered ? Colors.white : Colors.black)
              : (_hovered ? Colors.white : textC),
          fontSize: widget.fontSize,
          fontWeight: isCmd ? FontWeight.w800 : FontWeight.normal,
          letterSpacing: isCmd ? 0.3 : null),
        overflow: TextOverflow.ellipsis, maxLines: 1));

    return GestureDetector(
      onTap: () {
        if (_overlay != null) { _hideOverlay(); }
        else { showOverlay(); }
      },
      child: MouseRegion(
        onEnter: (_) {
          setState(() => _hovered = true);
          showOverlay();
        },
        onExit: (_) {
          setState(() => _hovered = false);
          if (hasUse) { _scheduleHide(); }
          else { _hideOverlay(); }
        },
        cursor: SystemMouseCursors.click,
        child: badge));
  }
}

IconData typeIcon(String type) {
  switch (type.toLowerCase()) {
    case 'infantry':  return Icons.sports_martial_arts;
    case 'cavalry':   return Icons.directions_run;
    case 'shooting':  return Icons.adjust;
    case 'artillery': return Icons.architecture;
    case 'hero':      return Icons.star;
    case 'monster':   return Icons.pets;
    case 'flyer':     return Icons.air;
    default:          return Icons.shield_outlined;
  }
}

Widget typeIconWidget(String type, {double size = 24, Color? color}) {
  final c = color ?? AppColors.grey;
  final asset = switch (type.toLowerCase()) {
    'infantry'  => 'assets/icons/infantry.svg',
    'cavalry'   => 'assets/icons/cavalry.svg',
    'shooting'  => 'assets/icons/shooting.svg',
    'artillery' => 'assets/icons/artillery.svg',
    'hero'      => 'assets/icons/hero.svg',
    'monster'   => 'assets/icons/monster.svg',
    'flyer'     => 'assets/icons/flyer.svg',
    _           => null,
  };
  if (asset != null) {
    return SvgPicture.asset(asset,
      width: size, height: size,
      colorFilter: ColorFilter.mode(c, BlendMode.srcIn));
  }
  return Icon(typeIcon(type), size: size, color: c);
}

Color typeColor(String type) {
  switch (type.toLowerCase()) {
    case 'infantry':  return const Color(0xFF3D78C0);
    case 'cavalry':   return const Color(0xFF5CAE68);
    case 'shooting':  return const Color(0xFFE05090);
    case 'artillery': return const Color(0xFFB83030);
    case 'hero':      return const Color(0xFFC9A84C);
    case 'monster':   return const Color(0xFF7B55C8);
    case 'flyer':     return const Color(0xFF18D8EC);
    default:          return AppColors.grey;
  }
}

Widget _statBox(String label, String value, bool dimmed, Color grey, {
  Color? valueColor,
  VoidCallback? onTap,
}) {
  final textColor = dimmed
      ? Colors.white.withValues(alpha: 0.2)
      : (valueColor ?? Colors.white);
  Widget box = Container(
    margin: const EdgeInsets.only(right: 1),
    padding: const EdgeInsets.symmetric(vertical: 3),
    color: AppColors.dark,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(label, textAlign: TextAlign.center, style: GoogleFonts.cinzel(
        fontSize: 10,
        color: dimmed ? grey.withValues(alpha: 0.35) : grey)),
      Text(value, textAlign: TextAlign.center, style: GoogleFonts.cinzel(
        fontSize: 16, fontWeight: FontWeight.w600,
        color: textColor,
        decoration: onTap != null && !dimmed ? TextDecoration.underline : null,
        decorationColor: textColor.withValues(alpha: 0.4),
        decorationStyle: TextDecorationStyle.dotted,
        fontFeatures: const [ui.FontFeature.tabularFigures()])),
    ]));
  if (onTap != null && !dimmed) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: box));
  }
  return box;
}

// 2-row ability layout — row 2 uses an inner LayoutBuilder so the trailing
// widget's actual rendered width is automatically subtracted.
Widget _abilityRows(List<String> abs, {
  Color? tColor,
  Widget? trailing,
  VoidCallback? Function(String)? onAbilityUse}) {

  if (abs.isEmpty) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 29),
        Row(children: [
          const Expanded(child: SizedBox()),
          if (trailing != null) trailing,
        ]),
      ]);
  }

  return LayoutBuilder(builder: (ctx, bc) {
    final w      = bc.maxWidth;
    const rowH   = 27.0;
    const sp     = 4.0;
    const rsp    = 5.0;
    const padH   = 14.0;
    const plusW  = 26.0;
    final tc     = tColor ?? AppColors.gold;

    // Per-char estimates for Cinzel at fontSize 10: spaces ~3.5px, uppercase ~8px, rest ~6.5px.
    double bwEst(String s) {
      var w = 0.0;
      for (final r in s.runes) {
        final c = String.fromCharCode(r);
        if (c == ' ') { w += 3.5; }
        else if (c == c.toUpperCase() && c != c.toLowerCase()) { w += 8.0; }
        else { w += 6.5; }
      }
      return (w + padH + 4).ceilToDouble();
    }

    // Row 1: pack into full width
    final row1Idx = <int>[];
    double x1 = 0;
    for (int i = 0; i < abs.length; i++) {
      final fw   = bwEst(abs[i]);
      final next = x1 == 0 ? fw : x1 + sp + fw;
      if (next <= w + 1) { row1Idx.add(i); x1 = next; }
    }

    final row1        = row1Idx.map((i) => abs[i]).toList();
    final remainingIdx = abs.asMap().keys.where((i) => !row1Idx.contains(i)).toList();

    // Row 2 widget: inner LayoutBuilder gives the true available width
    // (Flutter subtracts trailing's natural width via Expanded).
    Widget row2 = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: LayoutBuilder(builder: (_, bc2) {
        final row2W = bc2.maxWidth;

        final row2Idx = <int>[];
        double x2 = 0;
        for (final i in remainingIdx) {
          final fw      = bwEst(abs[i]);
          final hasMore = remainingIdx.indexOf(i) < remainingIdx.length - 1;
          final space   = row2W - (hasMore ? plusW + sp : 0);
          final next    = x2 == 0 ? fw : x2 + sp + fw;
          if (next <= space + 1) { row2Idx.add(i); x2 = next; } else { break; }
        }

        final shownAll = {...row1Idx, ...row2Idx};
        final hidden   = abs.asMap().keys
            .where((i) => !shownAll.contains(i))
            .map((i) => abs[i]).toList();

        final plusN = hidden.isEmpty ? const SizedBox.shrink() : _PlusNBadge(
          hidden: hidden,
          tc: tc,
          onAbilityUse: onAbilityUse);

        return SizedBox(height: rowH,
          child: ClipRect(child: Wrap(spacing: sp, children: [
            ...row2Idx.map((i) => abilityBadge(abs[i], fontSize: 10, tColor: tColor,
              onUse: onAbilityUse?.call(abs[i]))),
            if (hidden.isNotEmpty) plusN,
          ])));
      })),
      if (trailing != null) trailing,
    ]);

    return SizedBox(height: rowH * 2 + rsp,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(height: rowH,
          child: ClipRect(child: Wrap(spacing: sp,
            children: row1.map((a) => abilityBadge(a, fontSize: 10, tColor: tColor,
              onUse: onAbilityUse?.call(a))).toList()))),
        const SizedBox(height: rsp),
        SizedBox(height: rowH, child: row2),
      ]));
  });
}

/// Public wrapper so other screens can render the same 2-row ability layout.
Widget abilityRows(List<String> abs, {
  Color? tColor,
  Widget? trailing,
  VoidCallback? Function(String)? onAbilityUse}) =>
    _abilityRows(abs, tColor: tColor, trailing: trailing, onAbilityUse: onAbilityUse);

// ── UnitCard ──────────────────────────────────────────────────────────────────
class UnitCard extends StatefulWidget {
  final GameUnit unit;
  final String? customName;
  final String? photoBase64;
  final String? bgColor;
  final String? lore;              // unit lore (ArmyUnit.lore) — book icon, read-only
  final String? note;              // battle note — sticky-note icon, bottom-right of photo
  final VoidCallback? onNoteTap;   // if null, note icon is hidden
  final int? currentCon;           // live STR value — shows instead of unit.con when set
  final VoidCallback? onStrTap;    // if set, STR stat box is tappable
  final Key? strStatKey;
  final bool dimmed;
  final Color? accentColor;
  final List<Widget>? actions;
  final VoidCallback? onEdit;
  final Widget? trailing;
  final bool locked;
  final bool hideBorder;
  final VoidCallback? Function(String)? onAbilityUse;
  final Widget? activateOverlay;
  const UnitCard({super.key,
    required this.unit, this.customName, this.photoBase64,
    this.bgColor, this.lore, this.note, this.onNoteTap,
    this.currentCon, this.onStrTap, this.strStatKey,
    this.dimmed = false,
    this.accentColor, this.actions, this.onEdit,
    this.trailing, this.locked = false, this.hideBorder = false,
    this.onAbilityUse, this.activateOverlay});
  @override State<UnitCard> createState() => _UnitCardWidgetState();
}

class _UnitCardWidgetState extends State<UnitCard> with TickerProviderStateMixin {
  // official lore (unit.lore)
  bool _loreOpen        = false;
  bool _loreIconHovered = false;
  bool _noteIconHovered = false;
  late final AnimationController _loreHCtrl;
  late final AnimationController _loreFCtrl;
  late final CurvedAnimation     _loreHFactor;

  static const gold = AppColors.gold;
  static const grey = AppColors.grey;

  @override void initState() {
    super.initState();
    _loreHCtrl   = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _loreFCtrl   = AnimationController(vsync: this, duration: const Duration(milliseconds: 160));
    _loreHFactor = CurvedAnimation(parent: _loreHCtrl, curve: Curves.easeOut);
    _loreFCtrl.value = 1.0;
  }

  @override void dispose() {
    _loreHCtrl.dispose();  _loreFCtrl.dispose();
    super.dispose();
  }

  void _toggle(bool open, AnimationController hCtrl, AnimationController fCtrl,
      void Function(bool) setOpen) {
    if (!open) {
      setOpen(true);
      fCtrl.stop();
      fCtrl.value = 1.0;
      hCtrl.forward();
    } else {
      setOpen(false);
      hCtrl.stop();
      fCtrl.reverse().whenCompleteOrCancel(() {
        if (mounted) { hCtrl.value = 0.0; fCtrl.value = 1.0; setState(() {}); }
      });
    }
  }

  void _toggleLore() => _toggle(_loreOpen, _loreHCtrl, _loreFCtrl,
      (v) => setState(() => _loreOpen = v));

  @override Widget build(BuildContext context) {
    final unit = widget.unit;
    final tc   = typeColor(unit.type);
    final name = (widget.customName?.isNotEmpty == true) ? widget.customName! : unit.name;
    final abs  = unit.abilities;
    final hasPhoto    = widget.photoBase64 != null && widget.photoBase64!.isNotEmpty;
    final officialLore = (widget.lore?.isNotEmpty == true)  ? widget.lore!
                       : (unit.lore?.isNotEmpty  == true)  ? unit.lore!  : null;
    final hasLore = officialLore != null;

    Widget photoArea = hasPhoto
      ? ColoredBox(
          color: widget.bgColor != null ? AppColors.parseHex(widget.bgColor!) : AppColors.dark,
          child: CachedBase64Image(base64: widget.photoBase64!, width: 80, height: 143))
      : ColoredBox(
          color: widget.bgColor != null ? AppColors.parseHex(widget.bgColor!) : AppColors.dark,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            typeIconWidget(unit.type, size: 42, color: tc.withValues(alpha: 0.7)),
            const SizedBox(height: 4),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(unit.type,
                style: GoogleFonts.cinzel(
                  color: tc.withValues(alpha: 0.8), fontSize: 9),
                textAlign: TextAlign.center)),
          ]));

    return Container(
      constraints: const BoxConstraints(minWidth: 260, minHeight: 143),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: widget.dimmed ? AppColors.dark.withValues(alpha: 0.7) : AppColors.dark),
      foregroundDecoration: widget.hideBorder ? null : BoxDecoration(
        border: Border.all(
          color: widget.dimmed ? grey.withValues(alpha: 0.2)
            : (widget.accentColor ?? tc).withValues(alpha: 0.4),
          width: 1.5)),
      child: Opacity(
        opacity: widget.dimmed ? 0.55 : 1.0,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(height: 143, child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 80, height: 143,
              child: Stack(children: [
                Positioned.fill(child: photoArea),
                // Lore icon — bottom-left, always visible (dim if no official lore)
                Positioned(bottom: 8, left: 8,
                  child: GestureDetector(
                    onTap: hasLore ? _toggleLore : null,
                    child: MouseRegion(
                      cursor: hasLore ? SystemMouseCursors.click : MouseCursor.defer,
                      onEnter: hasLore ? (_) => setState(() => _loreIconHovered = true)  : null,
                      onExit:  hasLore ? (_) => setState(() => _loreIconHovered = false) : null,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 80),
                        opacity: hasLore
                          ? (_loreOpen || _loreIconHovered ? 1.0 : 0.55)
                          : 0.2,
                        child: Icon(
                          _loreOpen ? Icons.menu_book : Icons.menu_book_outlined,
                          color: gold, size: 17,
                          shadows: const [Shadow(color: Colors.black87, blurRadius: 8)]))))),
                // Note icon — bottom-right, only when onNoteTap is wired up
                if (widget.onNoteTap != null)
                  Positioned(bottom: 8, right: 8,
                    child: GestureDetector(
                      onTap: widget.onNoteTap,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) => setState(() => _noteIconHovered = true),
                        onExit:  (_) => setState(() => _noteIconHovered = false),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 80),
                          opacity: (widget.note?.isNotEmpty == true)
                            ? (_noteIconHovered ? 1.0 : 0.75)
                            : (_noteIconHovered ? 0.55 : 0.3),
                          child: Icon(
                            (widget.note?.isNotEmpty == true)
                              ? Icons.sticky_note_2
                              : Icons.sticky_note_2_outlined,
                            color: gold, size: 17,
                            shadows: const [Shadow(color: Colors.black87, blurRadius: 8)]))))),
                // Activate / Ready overlay — top-center of photo
                if (widget.activateOverlay != null)
                  Positioned(top: 6, left: 0, right: 0,
                    child: Center(child: widget.activateOverlay!)),
              ])),
            Expanded(child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 3, 6, 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(name,
                    style: GoogleFonts.cinzel(
                      color: gold, fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text('${unit.cost}pts',
                    style: GoogleFonts.cinzel(color: grey, fontSize: 13, fontWeight: FontWeight.w600)),
                  if (widget.locked) ...[
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.lock_outline, color: grey.withValues(alpha: 0.5), size: 17)),
                  ] else if (widget.onEdit != null) ...[
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: _EditIconBtn(onTap: widget.onEdit!)),
                  ],
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  Expanded(child: _statBox('ATK', '${unit.atk}', unit.atk == 0, grey)),
                  Expanded(child: _statBox('DEF', '${unit.def}', unit.def == 0, grey)),
                  Expanded(child: _statBox('SHO', '${unit.rng}', unit.rng == 0, grey)),
                  Expanded(child: _statBox('MOB', '${unit.mob}', unit.mob == 0, grey)),
                  Expanded(child: () {
                    final cur = widget.currentCon;
                    final Widget statBox;
                    if (cur == null) {
                      statBox = _statBox('STR', '${unit.con}', unit.con == 0, grey);
                    } else {
                      final col = cur >= unit.con
                          ? const Color(0xFF2ECC71)
                          : cur <= 1
                              ? const Color(0xFFEF5350)
                              : const Color(0xFFFF8C00);
                      statBox = _statBox('STR', '$cur', cur == 0, grey,
                          valueColor: col, onTap: widget.onStrTap);
                    }
                    return widget.strStatKey != null
                        ? SizedBox(key: widget.strStatKey, child: statBox)
                        : statBox;
                  }()),
                  Expanded(child: _statBox('CP',  '${unit.cp}',  unit.cp  == 0, grey)),
                ]),
                () {
                  final cur = widget.currentCon;
                  if (cur == null) return const SizedBox(height: 3);
                  final maxCon = unit.con;
                  final pct = maxCon > 0 ? (cur / maxCon).clamp(0.0, 1.0) : 0.0;
                  final col = cur >= maxCon
                      ? const Color(0xFF2ECC71)
                      : cur <= 1
                          ? const Color(0xFFEF5350)
                          : const Color(0xFFFF8C00);
                  return LayoutBuilder(builder: (_, c) => Stack(children: [
                    Container(height: 2, color: col.withValues(alpha: 0.15)),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 2,
                      width: c.maxWidth * pct,
                      color: col.withValues(alpha: widget.dimmed ? 0.25 : 0.75)),
                  ]));
                }(),
                _abilityRows(abs, tColor: tc, trailing: widget.trailing, onAbilityUse: widget.onAbilityUse),
                if (widget.actions != null && widget.actions!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(mainAxisSize: MainAxisSize.min, children: widget.actions!),
                ],
              ]))),
          ])),
          // Official lore (below)
          if (hasLore)
            ClipRect(child: AnimatedBuilder(
              animation: Listenable.merge([_loreHCtrl, _loreFCtrl]),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Divider(color: gold.withValues(alpha: 0.22), height: 14),
                  Text(officialLore,
                    style: GoogleFonts.cinzel(
                      color: grey, fontSize: 12, height: 1.6,
                      fontStyle: FontStyle.italic)),
                ])),
              builder: (_, child) => Align(
                heightFactor: _loreHFactor.value,
                alignment: Alignment.topCenter,
                child: FadeTransition(opacity: _loreFCtrl, child: child)))),
        ])));
  }
}

/// Color accent for an ability: command abilities (cost > 0) are gold, others grey.
Color abilityColor(int cost, {int cpCost = 0}) =>
    cost < 0    ? const Color(0xFFCF6679)
    : cpCost > 0 ? AppColors.gold
    :              AppColors.grey;

// ── AbilityCard ───────────────────────────────────────────────────────────────
class AbilityCard extends StatelessWidget {
  final Map<String, dynamic> abilityData;
  final Widget? trailing;
  const AbilityCard({super.key, required this.abilityData, this.trailing});

  static const grey = AppColors.grey;

  @override Widget build(BuildContext context) {
    final a       = abilityData;
    final name    = a['name']        as String?        ?? '';
    final desc    = a['description'] as String?        ?? '';
    final cost    = a['cost']        as int?           ?? 0;
    final cpCost  = a['cp_cost']     as int?           ?? 0;
    final types   = List<String>.from(a['types'] ?? []);
    final tc      = abilityColor(cost, cpCost: cpCost);
    final costStr = cost > 0 ? '+$cost' : '$cost';

    return Container(
      constraints: const BoxConstraints(minWidth: 260),
      decoration: BoxDecoration(
        color: AppColors.dark,
        border: Border(
          left:   BorderSide(color: tc.withValues(alpha: 0.7), width: 2),
          right:  BorderSide(color: tc.withValues(alpha: 0.35)),
          top:    BorderSide(color: tc.withValues(alpha: 0.35)),
          bottom: BorderSide(color: tc.withValues(alpha: 0.35)))),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Left column — cost accent, stretches to match content height
          SizedBox(width: 72,
            child: ColoredBox(color: tc.withValues(alpha: 0.10),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (cpCost > 0) ...[
                  Text('$cpCost CP',
                    style: GoogleFonts.cinzel(
                      color: tc, fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Container(width: 40, height: 1,
                    color: tc.withValues(alpha: 0.3)),
                  const SizedBox(height: 4),
                  Text(costStr,
                    style: GoogleFonts.cinzel(
                      color: tc.withValues(alpha: 0.75), fontSize: 13,
                      fontWeight: FontWeight.w600)),
                  Text('pts',
                    style: GoogleFonts.cinzel(
                      color: tc.withValues(alpha: 0.5), fontSize: 9)),
                ] else ...[
                  Text(costStr,
                    style: GoogleFonts.cinzel(
                      color: tc, fontSize: 15, fontWeight: FontWeight.w700)),
                  Text('pts',
                    style: GoogleFonts.cinzel(
                      color: tc.withValues(alpha: 0.6), fontSize: 9)),
                ],
              ]))),
          // Content
          Expanded(child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                  style: GoogleFonts.cinzel(
                    color: AppColors.goldLight,
                    fontSize: 14, fontWeight: FontWeight.w600),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(desc,
                  style: const TextStyle(
                    color: Color(0xFFD8D0C0), fontSize: 12,
                    fontStyle: FontStyle.italic, height: 1.35)),
                const SizedBox(height: 4),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(child: types.isEmpty
                    ? const SizedBox()
                    : Wrap(spacing: 4, runSpacing: 2,
                        children: types.map((t) {
                          final tc2 = typeColor(t);
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              border: Border.all(color: tc2.withValues(alpha: 0.55))),
                            child: Text(t, style: GoogleFonts.cinzel(
                              color: tc2.withValues(alpha: 0.85), fontSize: 9)));
                        }).toList())),
                  if (trailing != null) trailing!,
                ]),
              ]))),
        ])));
  }
}

// ── RosterCard ────────────────────────────────────────────────────────────────
class RosterCard extends StatefulWidget {
  final Map<String, dynamic> unitData;
  final bool isDisabled;
  final VoidCallback? onAdd;
  final Widget? trailing;
  const RosterCard({super.key,
    required this.unitData, this.isDisabled = false, this.onAdd,
    this.trailing});
  @override State<RosterCard> createState() => _RosterCardState();
}

class _RosterCardState extends State<RosterCard> with TickerProviderStateMixin {
  bool _loreOpen        = false;
  bool _loreIconHovered = false;
  late final AnimationController _heightCtrl;
  late final AnimationController _fadeCtrl;
  late final CurvedAnimation     _heightFactor;
  static const gold = AppColors.gold;
  static const grey = AppColors.grey;

  @override void initState() {
    super.initState();
    _heightCtrl   = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _fadeCtrl     = AnimationController(vsync: this, duration: const Duration(milliseconds: 160));
    _heightFactor = CurvedAnimation(parent: _heightCtrl, curve: Curves.easeOut);
    _fadeCtrl.value = 1.0;
  }

  @override void dispose() {
    _heightCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _toggleLore() {
    if (!_loreOpen) {
      setState(() => _loreOpen = true);
      _fadeCtrl.stop();
      _fadeCtrl.value = 1.0;
      _heightCtrl.forward();
    } else {
      setState(() => _loreOpen = false);
      _heightCtrl.stop();
      _fadeCtrl.reverse().whenCompleteOrCancel(() {
        if (mounted && !_loreOpen) {
          _heightCtrl.value = 0.0;
          _fadeCtrl.value   = 1.0;
          setState(() {});
        }
      });
    }
  }

  @override Widget build(BuildContext context) {
    final u          = widget.unitData;
    final tc         = typeColor(u['type'] as String? ?? '');
    final abs        = List<String>.from(u['abilities'] ?? []);
    final imageB64   = u['image_b64'] as String?;
    final bgColorHex = u['bg_color']  as String?;
    final hasPhoto   = imageB64 != null && imageB64.isNotEmpty;
    final lore       = u['lore'] as String?;
    final hasLore    = lore != null && lore.isNotEmpty;

    bool z(String k) => (u[k] ?? 0) == 0;

    final effectiveTrailing = widget.trailing ??
      ((widget.onAdd != null || widget.isDisabled)
        ? _AddButton(isDisabled: widget.isDisabled, onAdd: widget.onAdd)
        : null);

    Widget photoContent = hasPhoto
      ? ColoredBox(
          color: bgColorHex != null ? AppColors.parseHex(bgColorHex) : AppColors.dark,
          child: Opacity(
            opacity: widget.isDisabled ? 0.5 : 1.0,
            child: CachedBase64Image(base64: imageB64, width: 80, height: 143)))
      : ColoredBox(
          color: bgColorHex != null ? AppColors.parseHex(bgColorHex) : AppColors.dark,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            typeIconWidget(u['type'] as String? ?? '',
              size: 42,
              color: widget.isDisabled ? grey.withValues(alpha: 0.3) : tc.withValues(alpha: 0.7)),
            const SizedBox(height: 4),
            Text(u['type'] as String? ?? '',
              style: GoogleFonts.cinzel(
                color: widget.isDisabled ? grey.withValues(alpha: 0.3) : tc,
                fontSize: 9),
              textAlign: TextAlign.center),
          ]));

    return Container(
      constraints: const BoxConstraints(minWidth: 260, minHeight: 143),
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(color: AppColors.dark),
      foregroundDecoration: BoxDecoration(
        border: Border.all(
          color: widget.isDisabled ? gold.withValues(alpha: 0.1) : tc.withValues(alpha: 0.4))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(height: 143, child: Stack(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 80, height: 143,
              child: Stack(children: [
                Positioned.fill(child: photoContent),
                Positioned(bottom: 8, left: 8,
                  child: GestureDetector(
                    onTap: hasLore ? _toggleLore : null,
                    child: MouseRegion(
                      cursor: hasLore ? SystemMouseCursors.click : MouseCursor.defer,
                      onEnter: hasLore ? (_) => setState(() => _loreIconHovered = true)  : null,
                      onExit:  hasLore ? (_) => setState(() => _loreIconHovered = false) : null,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 80),
                        opacity: hasLore ? (_loreOpen || _loreIconHovered ? 1.0 : 0.55) : 0.2,
                        child: Icon(
                          _loreOpen ? Icons.menu_book : Icons.menu_book_outlined,
                          color: gold, size: 17,
                          shadows: const [Shadow(color: Colors.black87, blurRadius: 8)]))))),
              ])),
            Expanded(child: Opacity(
              opacity: widget.isDisabled ? 0.5 : 1.0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 6, 0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(u['name'] as String? ?? '',
                      style: GoogleFonts.cinzel(
                        color: widget.isDisabled ? grey : AppColors.goldLight,
                        fontSize: 14, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text('${u['cost']}pts',
                      style: GoogleFonts.cinzel(
                        color: widget.isDisabled ? grey : gold,
                        fontSize: 13, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 3),
                  Row(children: [
                    Expanded(child: _statBox('ATK', '${u['atk'] ?? 0}',     z('atk'),     grey)),
                    Expanded(child: _statBox('DEF', '${u['def_val'] ?? 0}',  z('def_val'), grey)),
                    Expanded(child: _statBox('SHO', '${u['rng'] ?? 0}',     z('rng'),     grey)),
                    Expanded(child: _statBox('MOB', '${u['mob'] ?? 0}',     z('mob'),     grey)),
                    Expanded(child: _statBox('STR', '${u['con_val'] ?? 0}',  z('con_val'), grey)),
                    Expanded(child: _statBox('CP',  '${u['cp'] ?? 0}',      z('cp'),      grey)),
                  ]),
                  const SizedBox(height: 3),
                  _abilityRows(abs, tColor: tc, trailing: effectiveTrailing),
                ])))),
          ]),
        ])),
        if (hasLore)
          ClipRect(child: AnimatedBuilder(
            animation: Listenable.merge([_heightCtrl, _fadeCtrl]),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Divider(color: gold.withValues(alpha: 0.22), height: 14),
                Text(lore,
                  style: GoogleFonts.cinzel(
                    color: grey, fontSize: 12, height: 1.6,
                    fontStyle: FontStyle.italic)),
              ])),
            builder: (_, child) => Align(
              heightFactor: _heightFactor.value,
              alignment: Alignment.topCenter,
              child: FadeTransition(opacity: _fadeCtrl, child: child)))),
      ]));
  }
}

// ── Cached base64 image ───────────────────────────────────────────────────────
class CachedBase64Image extends StatefulWidget {
  final String base64;
  final double width, height;
  const CachedBase64Image({super.key, required this.base64, required this.width, required this.height});
  @override State<CachedBase64Image> createState() => _CachedBase64ImageState();

  // Bytes + crop-info cache (fast re-decode skipping base64 parsing)
  static final _cache     = <String, (Uint8List, Map<String, dynamic>?)>{};
  // Decoded GPU image cache — keeps textures alive across scroll/rebuild
  static final _imgCache  = <String, ui.Image>{};
}

class _CachedBase64ImageState extends State<CachedBase64Image> {
  ui.Image?              _image;
  Map<String, dynamic>? _cropInfo;
  ui.Image?              _prevImage;
  Map<String, dynamic>? _prevCropInfo;
  String?                _decoding; // base64 currently being decoded

  @override void initState() {
    super.initState();
    _decode(widget.base64);
  }

  @override void didUpdateWidget(CachedBase64Image o) {
    super.didUpdateWidget(o);
    if (o.base64 != widget.base64) {
      _prevImage    = _image;
      _prevCropInfo = _cropInfo;
      _image    = null;
      _cropInfo = null;
      _decode(widget.base64);
    }
  }

  @override void dispose() {
    // Don't dispose _image — it lives in _imgCache for reuse when scrolling back
    _prevImage?.dispose();
    super.dispose();
  }

  Future<void> _decode(String b64) async {
    // If GPU texture is already cached, use it immediately (no async needed)
    final cachedImg = CachedBase64Image._imgCache[b64];
    if (cachedImg != null) {
      if (!mounted) return;
      setState(() {
        _image    = cachedImg;
        _cropInfo = CachedBase64Image._cache[b64]?.$2;
        _decoding = null;
      });
      return;
    }

    _decoding = b64;
    try {
      Uint8List bytes;
      Map<String, dynamic>? info;
      final cached = CachedBase64Image._cache[b64];
      if (cached != null) {
        (bytes, info) = cached;
      } else {
        try {
          final raw = base64Decode(b64);
          if (raw.isNotEmpty && raw[0] == 0x7B) {
            final m = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
            info  = m;
            bytes = base64Decode(m['src'] as String);
          } else {
            bytes = raw;
            info  = null;
          }
        } catch (_) {
          bytes = base64Decode(b64);
          info  = null;
        }
        CachedBase64Image._cache[b64] = (bytes, info);
      }
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted || _decoding != b64) { frame.image.dispose(); return; }
      CachedBase64Image._imgCache[b64] = frame.image; // keep texture alive
      final toDispose = _prevImage;
      setState(() {
        _image        = frame.image;
        _cropInfo     = info;
        _prevImage    = null;
        _prevCropInfo = null;
        _decoding     = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => toDispose?.dispose());
    } catch (_) {}
  }

  @override Widget build(BuildContext context) {
    final img  = _image ?? _prevImage;
    final info = _image != null ? _cropInfo : _prevCropInfo;
    if (img == null) {
      return SizedBox(width: widget.width, height: widget.height,
        child: const ColoredBox(color: AppColors.dark));
    }
    if (info == null) {
      return RawImage(image: img, fit: BoxFit.cover,
        width: widget.width, height: widget.height);
    }
    final scale   = (info['scale']    as num).toDouble();
    final offsetX = (info['offsetX']  as num).toDouble();
    final offsetY = (info['offsetY']  as num).toDouble();
    final scaleX  = widget.width  / (info['previewW'] as num).toDouble();
    final scaleY  = widget.height / (info['previewH'] as num).toDouble();
    return ClipRect(child: SizedBox(
      width: widget.width, height: widget.height,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: offsetX * scaleX,
          top:  offsetY * scaleY,
          child: SizedBox(
            width:  img.width  * scale * scaleX,
            height: img.height * scale * scaleY,
            child: RawImage(image: img, fit: BoxFit.fill))),
      ])));
  }
}

// ── +Add button with press feedback and flying dot ────────────────────────────
class _AddButton extends StatefulWidget {
  final bool isDisabled;
  final VoidCallback? onAdd;
  const _AddButton({required this.isDisabled, required this.onAdd});
  @override State<_AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends State<_AddButton>
    with SingleTickerProviderStateMixin {
  static const gold  = AppColors.gold;
  static const dark1 = AppColors.dark;

  bool _pressed = false;
  bool _hovered = false;

  void _tap() {
    if (widget.isDisabled || widget.onAdd == null) return;
    widget.onAdd!();
    _launchDot();
  }

  void _launchDot() {
    final ctx = context;
    if (!ctx.mounted) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final start = box.localToGlobal(
      Offset(box.size.width / 2, box.size.height / 2));
    // Target: army panel header area (upper-right, but adjusted for app/web)
    final screenSize = MediaQuery.of(ctx).size;
    final isNarrow   = screenSize.width < 700;
    // On narrow (tab view): fly to bottom tab bar army tab
    // On wide: fly toward right panel header
    final end = isNarrow
      ? Offset(screenSize.width * 0.75, screenSize.height - 30)
      : Offset(screenSize.width * 0.78, 50);

    final entry = OverlayEntry(builder: (_) => _FlyingDot(start: start, end: end));
    Overlay.of(ctx).insert(entry);
    Future.delayed(const Duration(milliseconds: 1000), entry.remove);
  }

  @override Widget build(BuildContext context) {
    if (widget.isDisabled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        color: gold.withValues(alpha: 0.15),
        child: Text('✓ Added', style: GoogleFonts.cinzel(
          color: gold, fontSize: 11, fontWeight: FontWeight.w700)));
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown:   (_) => setState(() => _pressed = true),
        onTapUp:     (_) { setState(() => _pressed = false); _tap(); },
        onTapCancel: ()  => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          alignment: Alignment.center,
          transform: _pressed
            ? (Matrix4.identity()..scaleByDouble(0.88, 0.88, 1.0, 1.0))
            : Matrix4.identity(),
          transformAlignment: Alignment.center,
          color: _pressed
            ? gold.withValues(alpha: 0.45)
            : (_hovered ? gold.withValues(alpha: 0.82) : gold),
          child: Text('Add', style: GoogleFonts.cinzel(
            color: dark1, fontSize: 12, fontWeight: FontWeight.w800)))));
  }
}

// Animates a gold dot flying from start to end position
class _FlyingDot extends StatefulWidget {
  final Offset start, end;
  const _FlyingDot({required this.start, required this.end});
  @override State<_FlyingDot> createState() => _FlyingDotState();
}

class _FlyingDotState extends State<_FlyingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override void initState() {
    super.initState();
    _c = AnimationController(vsync: this,
      duration: const Duration(milliseconds: 900))..forward();
  }
  @override void dispose() { _c.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t   = Curves.easeInOut.transform(_c.value);
        final pos = Offset.lerp(widget.start, widget.end, t)!;
        // Arced path — lift up then come down
        final arc = Offset(pos.dx, pos.dy - 80 * math.sin(t * math.pi));
        final opacity = t < 0.8 ? 1.0 : (1.0 - (t - 0.8) / 0.2);
        return Positioned(
          left: arc.dx - 7,
          top:  arc.dy - 7,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Container(
              width: 14, height: 14,
              decoration: const BoxDecoration(
                color: AppColors.gold,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                  color: AppColors.gold,
                  blurRadius: 10, spreadRadius: 3)]))));
      });
  }
}

// ── Reusable press button with hover + press effects ─────────────────────────
/// Use this everywhere in the app for consistent button feel.
class PressBtn extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final Color bg;
  final Color fg;
  final double fontSize;
  final EdgeInsets padding;
  final bool centered;
  final bool outlined;  // transparent bg, colored border only (like Sort button)
  const PressBtn({super.key,
    required this.label,
    required this.onTap,
    this.bg       = AppColors.gold,
    this.fg       = AppColors.dark,
    this.fontSize = 13,
    this.centered = false,
    this.outlined = false,
    this.padding  = const EdgeInsets.symmetric(horizontal: 10, vertical: 4)});
  @override State<PressBtn> createState() => _PressBtnState();
}

class _PressBtnState extends State<PressBtn> {
  bool _pressed = false;
  bool _hovered = false;

  @override Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    final isOutlined = widget.outlined;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown:   (_) { if (!disabled) setState(() => _pressed = true);  },
        onTapUp:     (_) { if (!disabled) { setState(() => _pressed = false); widget.onTap!(); }},
        onTapCancel: ()  { setState(() => _pressed = false); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: widget.padding,
          transform: _pressed ? (Matrix4.identity()..scaleByDouble(0.88, 0.88, 1.0, 1.0)) : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: isOutlined
            ? BoxDecoration(
                color: _pressed
                  ? widget.bg.withValues(alpha: 0.15)
                  : _hovered ? widget.bg.withValues(alpha: 0.12) : Colors.transparent,
                border: Border.all(
                  color: _hovered || _pressed ? widget.bg : widget.bg.withValues(alpha: 0.4)))
            : BoxDecoration(
                color: disabled ? widget.bg.withValues(alpha: 0.35)
                  : _pressed  ? widget.bg.withValues(alpha: 0.45)
                  : _hovered  ? widget.bg.withValues(alpha: 0.82)
                  : widget.bg),
          child: widget.centered
            ? Center(child: Text(widget.label,
                style: GoogleFonts.cinzel(
                  color: isOutlined
                    ? widget.bg
                    : (disabled ? widget.fg.withValues(alpha: 0.4) : widget.fg),
                  fontSize: widget.fontSize, fontWeight: FontWeight.w700)))
            : Text(widget.label,
                style: GoogleFonts.cinzel(
                  color: isOutlined
                    ? widget.bg
                    : (disabled ? widget.fg.withValues(alpha: 0.4) : widget.fg),
                  fontSize: widget.fontSize, fontWeight: FontWeight.w700)))));
  }
}

// ── Edit pencil with hover + press + flash animation ─────────────────────────
class _EditIconBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _EditIconBtn({required this.onTap});
  @override State<_EditIconBtn> createState() => _EditIconBtnState();
}
class _EditIconBtnState extends State<_EditIconBtn>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  bool _pressed = false;
  late AnimationController _ctrl;

  @override void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this,
      duration: const Duration(milliseconds: 300))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _ctrl.reverse();
      });
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  Color get _color {
    if (_ctrl.value > 0) {
      return Color.lerp(
      AppColors.gold, Colors.white, _ctrl.value * 0.5)!;
    }
    if (_hovered) return AppColors.goldBright;  // bright yellow
    return const Color(0xFF6A5A4A);
  }

  @override Widget build(BuildContext context) =>
    MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown:   (_) => setState(() => _pressed = true),
        onTapUp:     (_) {
          setState(() => _pressed = false);
          _ctrl.forward(from: 0);
          widget.onTap();
        },
        onTapCancel: ()  => setState(() => _pressed = false),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Transform.scale(
              scale: _pressed ? 0.72 : 1.0,
              child: Icon(Icons.edit_outlined, color: _color, size: 17))))));
}

// ── +N overflow badge with AP-aware overlay ───────────────────────────────────
class _PlusNBadge extends StatefulWidget {
  final List<String> hidden;
  final Color tc;
  final VoidCallback? Function(String)? onAbilityUse;
  const _PlusNBadge({required this.hidden, required this.tc, this.onAbilityUse});
  @override State<_PlusNBadge> createState() => _PlusNBadgeState();
}

class _PlusNBadgeState extends State<_PlusNBadge> {
  bool _hovered = false;
  OverlayEntry? _overlay;
  Timer? _hideTimer;

  static const gold = AppColors.gold;

  void _hideOverlay() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _overlay?.remove();
    _overlay = null;
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 120), _hideOverlay);
  }

  @override void dispose() {
    _hideTimer?.cancel();
    _overlay?.remove();
    super.dispose();
  }

  void _showOverlay() {
    _hideOverlay();
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    final sz  = box.size;

    final items = widget.hidden.map((a) {
      final ab     = GameDataService.abilities.where((x) => x['name'] == a).firstOrNull;
      final desc   = ab?['description'] as String? ?? '';
      final cpCost = ab?['cp_cost'] as int? ?? 0;
      final isAp   = cpCost > 0;
      final onUse  = widget.onAbilityUse?.call(a);
      return (name: a, desc: desc, cpCost: cpCost, isAp: isAp, onUse: onUse);
    }).toList();

    _overlay = OverlayEntry(builder: (ctx) {
      final screen = MediaQuery.of(ctx).size;
      const maxW = 304.0;
      final left       = pos.dx.clamp(0.0, (screen.width - maxW).clamp(0.0, screen.width));
      final spaceBelow = screen.height - (pos.dy + sz.height);
      final showAbove  = spaceBelow < 200 && pos.dy > spaceBelow;
      final topPos     = pos.dy + sz.height + 5;
      final botPos     = screen.height - pos.dy + 5;
      final maxH       = (showAbove
          ? pos.dy - 15
          : screen.height - topPos - 15)
          .clamp(80.0, 520.0);
      return Stack(children: [
        Positioned.fill(child: GestureDetector(
          onTap: _hideOverlay,
          behavior: HitTestBehavior.translucent,
          child: const SizedBox.expand())),
        Positioned(
          left: left,
          top:    showAbove ? null : topPos,
          bottom: showAbove ? botPos : null,
          child: Material(
            color: Colors.transparent,
            child: MouseRegion(
              onEnter: (_) { _hideTimer?.cancel(); },
              onExit:  (_) => _scheduleHide(),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 300, minWidth: 200),
                decoration: BoxDecoration(
                  color: AppColors.dark,
                  border: Border.all(color: gold.withValues(alpha: 0.5))),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxH),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (int i = 0; i < items.length; i++) ...[
                          if (i > 0) Divider(height: 1, color: gold.withValues(alpha: 0.15)),
                          _AbilityEntry(
                            item: items[i],
                            onUsed: items[i].onUse == null ? null : () {
                              _hideOverlay();
                              items[i].onUse!();
                            }),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          )),
      ]);
    });
    Overlay.of(context).insert(_overlay!);
  }

  @override Widget build(BuildContext context) =>
    GestureDetector(
      onTap: () { if (_overlay != null) { _hideOverlay(); } else { _showOverlay(); } },
      child: MouseRegion(
        onEnter: (_) { setState(() => _hovered = true); _showOverlay(); },
        onExit:  (_) { setState(() => _hovered = false); _scheduleHide(); },
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: ShapeDecoration(
            color: widget.tc.withValues(alpha: _hovered ? 0.26 : 0.15),
            shape: BeveledRectangleBorder(
              side: BorderSide(color: widget.tc.withValues(alpha: _hovered ? 0.9 : 0.5)),
              borderRadius: BorderRadius.circular(4))),
          child: Text('+${widget.hidden.length}',
            style: GoogleFonts.cinzel(
              color: _hovered ? Colors.white : widget.tc,
              fontSize: 10, fontWeight: FontWeight.w700)))));
}

// single ability row inside the +n overlay
// ── Shared banner widgets ─────────────────────────────────────────────────────

/// Compact unit-names list for banner panels, grouped by group name.
/// Pass [groupOrder] to control group ordering; if empty, order is derived
/// from first appearance in [entries].
class BannerUnitsPanel extends StatelessWidget {
  final List<Map<String, String>> entries;
  final List<String> groupOrder;
  const BannerUnitsPanel({
    super.key,
    required this.entries,
    this.groupOrder = const [],
  });

  @override
  Widget build(BuildContext context) {
    final derived = entries.fold<List<String>>(
      [''],
      (acc, e) {
        final g = e['group'] ?? '';
        if (!acc.contains(g)) acc.add(g);
        return acc;
      });
    final groups = groupOrder.isNotEmpty ? ['', ...groupOrder] : derived;
    final rows = <Widget>[];
    for (final g in groups) {
      final gUnits = entries.where((u) => u['group'] == g).toList();
      if (gUnits.isEmpty) continue;
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
      if (g.isNotEmpty) {
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(g.toUpperCase(),
            style: GoogleFonts.cinzel(
              color: AppColors.gold.withValues(alpha: 0.7),
              fontSize: 9, letterSpacing: 1.5,
              shadows: const [Shadow(color: Colors.black87, blurRadius: 4)]))));
      }
      for (final u in gUnits) {
        rows.add(Text(u['name']!,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.cinzel(
            color: Colors.white70, fontSize: 11, height: 1.45,
            shadows: const [Shadow(color: Colors.black87, blurRadius: 4)])));
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows));
  }
}

/// Small stat column: value on top, label below. Used in army banners.
class BannerStat extends StatelessWidget {
  final String value;
  final String label;
  const BannerStat(this.value, this.label, {super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 28,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(value, textAlign: TextAlign.center,
          style: GoogleFonts.cinzel(
            color: AppColors.gold, fontSize: 13, fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
            shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])),
        Text(label, textAlign: TextAlign.center,
          style: GoogleFonts.cinzel(
            color: AppColors.grey, fontSize: 8, letterSpacing: 0.8,
            shadows: const [Shadow(color: Colors.black87, blurRadius: 4)])),
      ]));
}

// ─────────────────────────────────────────────────────────────────────────────
class _AbilityEntry extends StatelessWidget {
  final ({String name, String desc, int cpCost, bool isAp, VoidCallback? onUse}) item;
  final VoidCallback? onUsed;
  const _AbilityEntry({required this.item, this.onUsed});

  static const gold = AppColors.gold;

  @override Widget build(BuildContext context) {
    return Container(
      decoration: item.isAp ? BoxDecoration(
        border: Border.all(color: gold, width: 1.5),
        color: gold.withValues(alpha: 0.05)) : null,
      child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(child: Text(item.name,
              style: GoogleFonts.cinzel(
                color: gold,
                fontSize: 11, fontWeight: FontWeight.w700))),
            if (item.isAp) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: gold.withValues(alpha: 0.18),
                  border: Border.all(color: gold.withValues(alpha: 0.6))),
                child: Text('${item.cpCost} CP',
                  style: GoogleFonts.cinzel(
                    color: gold, fontSize: 9,
                    fontWeight: FontWeight.w700, letterSpacing: 1))),
            ],
          ]),
          if (item.desc.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(item.desc,
              style: GoogleFonts.cinzel(
                color: const Color(0xFFD8D0C0), fontSize: 11, height: 1.4)),
          ],
          if (onUsed != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: PressBtn(
                label: 'Use',
                onTap: onUsed,
                bg: gold,
                fg: AppColors.dark,
                fontSize: 10,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5))),
          ],
        ],
      ),
    ));
  }
}

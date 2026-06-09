import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/material.dart';
import '../services/bg_remover.dart';
import '../widgets/photo_crop_dialog.dart';
import '../widgets/unit_card.dart';
import '../widgets/condition_badges.dart';
import '../widgets/nav_btn.dart';
import '../widgets/action_log_sheet.dart';
import '../widgets/d20_icon.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../game/models/game_state.dart';
import '../game/notifiers/game_notifier.dart';
import '../app_theme.dart';
import '../services/game_data_service.dart';
import '../widgets/aetherra_text_field.dart';
import '../widgets/aetherra_dialog.dart';
import '../widgets/hover_icon_btn.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _kUnitBgPresets = [
  '#0D0B09', '#08111E', '#0A1A08', '#1A0808',
  '#120820', '#14061A', '#1A1004', '#1A0C0C',
  '#2D1B0E', '#0C2244', '#112C11', '#3C1111',
  '#1D1142', '#113D3D', '#3D2008', '#2C1024',
  '#5C3C1E', '#1E4E82', '#1E5E1E', '#6E1E1E',
  '#3C1C6E', '#1E5E5E', '#6E3E0E', '#4E1C40',
  '#8C6040', '#3A74AA', '#3A7440', '#A43C3C',
  '#5C3CAA', '#3A9292', '#AA6C20', '#7C3468',
  '#C8A870', '#70AACC', '#70BC70', '#D48888',
  '#9870CC', '#70C0C0', '#CCAA38', '#C07898',
];

class GameScreen extends StatelessWidget {
  const GameScreen({super.key});

  static const gold  = AppColors.gold;
        static const grey  = AppColors.grey;

  @override
  Widget build(BuildContext context) {
    return Consumer<GameNotifier>(builder: (ctx, game, _) {
      final gs = game.state;
      if (gs == null) {
        return Scaffold(backgroundColor: AppColors.dark,
          body: Center(child: Text('No game active',
            style: GoogleFonts.cinzel(color: grey))));
      }

      final playerCol = AppColors.parseHex(gs.playerColor);
      final enemyCol  = AppColors.parseHex(gs.enemyColor);
      final isGM      = gs.role == PlayerRole.gamemaster;
      final groups    = game.groupedUnits();
      return Scaffold(
        backgroundColor: AppColors.dark,
        appBar: AppBar(
          leadingWidth: 48,
          leading: NavBtn(icon: Icons.home_outlined, onPressed: () {
              final ctrl = TextEditingController(
                text: game.state?.saveName ?? game.state?.armyName ?? 'Game Save');
              showAetherraSheet(ctx,
                title: 'Leave Battle?',
                body: game.isSaved
                  ? Text(
                      '"${game.state?.saveName}" is saved automatically.',
                      style: GoogleFonts.cinzel(color: grey, fontSize: 13, height: 1.5))
                  : AetherraTextField(controller: ctrl, hintText: 'Save name…'),
                actions: [
                  SheetAction('Cancel', grey, () => Navigator.pop(ctx), outlined: true),
                  SheetAction('Save & Exit', gold, () async {
                    Navigator.pop(ctx);
                    if (game.isSaved) {
                      await game.flushAutoSave();
                    } else {
                      final ok = await game.saveGame(ctrl.text.trim());
                      if (!ok || !ctx.mounted) return;
                    }
                    _GameGroupSectionState.clearState();
                    game.endGame();
                    if (ctx.mounted) Navigator.of(ctx).popUntil((r) => r.isFirst);
                  }),
                ]);
            }),
          title: Text(gs.saveName ?? gs.armyName ?? 'Game', style: GoogleFonts.cinzel(
            color: gold, fontSize: 14, letterSpacing: 1)),
          actions: [
            // Auto-save indicator
            if (game.autoSaving)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: gold))),
            // Action log button
            NavBtn(
              icon: Icons.history,
              onPressed: () => _showActionLog(ctx, game)),
            // Round indicator
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('Round ${gs.round}',
                style: GoogleFonts.cinzel(color: gold, fontSize: 12))),
          ],
        ),
        body: _GameDndOuter(
          game: game,
          child: Column(children: [
          // ── TOKEN BAG (GM only) — TOP ─────────────────────────────
          if (isGM)
            Container(
              margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              decoration: BoxDecoration(
                color: AppColors.dark,
                border: Border.all(color: gold.withValues(alpha: 0.35))),
              child: _TokenBagWidget(game: game, gs: gs,
                playerCol: playerCol, enemyCol: enemyCol)),

          // ── ARMY BANNER (hides on scroll) ────────────────────────
          _ScrollHiddenBanner(gs: gs, game: game),

          // ── HEADER BAR ───────────────────────────────────────────
          SizedBox(height: 70,
            child: Container(
              color: AppColors.dark,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                // CP — left
                _cpWidget(game, gs),
                // Dice — fixed same height as header content (58px)
                const Spacer(),
                const _DiceButton(),
                const Spacer(),
                // Next Round + Ready All — right, stacked, equal width
                SizedBox(width: 110, child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                _actionBtn('Next Round', Icons.skip_next, () {
                  showModalBottomSheet(
                    context: ctx,
                    isScrollControlled: true,
                    backgroundColor: AppColors.dark,
                    builder: (_) => DraggableScrollableSheet(
                      expand: false,
                      initialChildSize: 0.85,
                      builder: (_, scroll) => Padding(
                        padding: EdgeInsets.fromLTRB(16, 16, 16,
                          MediaQuery.of(ctx).viewInsets.bottom + 24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Center(child: Container(width: 40, height: 4,
                            decoration: BoxDecoration(
                              color: grey.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(2)))),
                          const SizedBox(height: 14),
                          Text('Round ${gs.round} – Summary',
                            style: GoogleFonts.cinzel(color: gold, fontSize: 17)),
                          const SizedBox(height: 16),
                          Expanded(child: SingleChildScrollView(
                            controller: scroll,
                            child: _RoundSummaryContent(gs: gs, game: game, isGM: isGM))),
                          const SizedBox(height: 24),
                          Row(children: [
                            Expanded(child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: grey,
                                side: BorderSide(color: grey.withValues(alpha: 0.4)),
                                shape: const RoundedRectangleBorder(),
                                padding: const EdgeInsets.symmetric(vertical: 14)),
                              child: Text('Cancel',
                                style: GoogleFonts.cinzel(fontSize: 14)))),
                            const SizedBox(width: 12),
                            Expanded(child: ElevatedButton(
                              onPressed: () { Navigator.pop(ctx); game.nextRound(); },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: gold,
                                foregroundColor: AppColors.dark,
                                shape: const RoundedRectangleBorder(),
                                padding: const EdgeInsets.symmetric(vertical: 14)),
                              child: Text('Next Round',
                                style: GoogleFonts.cinzel(
                                  fontSize: 14, fontWeight: FontWeight.w600)))),
                          ]),
                        ]))));
                }, color: gold),
                const SizedBox(height: 4),
                _actionBtn('End Game', Icons.flag_outlined, () =>
                  _showEndGameSummary(ctx, game),
                  color: AppColors.grey),

                ])),
              ]))),

          // ── UNIT LIST ────────────────────────────────────────────
          Expanded(child: Stack(children: [
            Listener(
              onPointerMove:   (e) { if (_GameDndOuterState._dragging != null) _GameDndOuterState._updateScroll(e.position.dy); },
              onPointerUp:     (_) => _GameDndOuterState._stopScroll(),
              onPointerCancel: (_) => _GameDndOuterState._stopScroll(),
              child: ListView.builder(
                controller: _GameDndOuterState._scrollCtrl,
                padding: const EdgeInsets.all(10),
              itemCount: groups.length,
              itemBuilder: (_, gi) {
                final entry     = groups[gi];
                final groupName = entry.key;
                final units     = entry.value;
                final isElimGrp = groupName == '__eliminated__';
                return _GameGroupSection(
                  key: ValueKey(groupName),
                  groupName: groupName,
                  units: units,
                  isElimGrp: isElimGrp,
                  game: game,
                  playerCol: playerCol,
                  topMargin: gi > 0 ? 12.0 : 0.0,
                );
              })),
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
          ])),
          ])),
          );  // Scaffold
    });
}

  Widget _cpWidget(GameNotifier game, GameState gs) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      _GlowIcon(icon: Icons.remove, color: const Color(0xFFC8A0E0),
        size: 18, onTap: () { HapticFeedback.selectionClick(); game.adjustCP(-1); }),
      const SizedBox(width: 10),
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${gs.commandPoints}',
          style: GoogleFonts.cinzel(color: const Color(0xFFC8A0E0), fontSize: 20)),
        Text('AP', style: GoogleFonts.cinzel(
          color: const Color(0xFFC8A0E0).withValues(alpha: 0.6), fontSize: 9, letterSpacing: 1)),
      ]),
      const SizedBox(width: 10),
      _GlowIcon(icon: Icons.add, color: const Color(0xFFC8A0E0),
        size: 18, onTap: () { HapticFeedback.selectionClick(); game.adjustCP(1); }),
    ]));

  Widget _actionBtn(String label, IconData icon, VoidCallback onTap,
      {Color color = AppColors.grey}) =>
    _ActionBtn(label: label, icon: icon, onTap: onTap, color: color);

  static void _showActionLog(BuildContext ctx, GameNotifier game) =>
      showActionLogSheet(ctx, game.actionLog);

  static Future<void> _showEndGameSummary(BuildContext ctx, GameNotifier game) async {
    final gs = game.state!;
    await showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: AppColors.dark,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (_, scroll) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16,
            MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(
                color: grey.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            Text('Game Summary',
              style: GoogleFonts.cinzel(color: gold, fontSize: 17)),
            const SizedBox(height: 16),
            Expanded(child: SingleChildScrollView(
              controller: scroll,
              child: _EndGameContent(gs: gs))),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: OutlinedButton.styleFrom(
                  foregroundColor: grey,
                  side: BorderSide(color: grey.withValues(alpha: 0.4)),
                  shape: const RoundedRectangleBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text('Continue',
                  style: GoogleFonts.cinzel(fontSize: 14)))),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await game.flushAutoSave();
                  _GameGroupSectionState.clearState();
                  game.endGame();
                  if (ctx.mounted) Navigator.of(ctx).popUntil((r) => r.isFirst);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: gold,
                  foregroundColor: AppColors.dark,
                  shape: const RoundedRectangleBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text('End Game',
                  style: GoogleFonts.cinzel(
                    fontSize: 14, fontWeight: FontWeight.w600)))),
            ]),
          ]))));
  }
}

// ── TOKEN BAG WIDGET ─────────────────────────────────────────────────
class _TokenBagWidget extends StatelessWidget {
  final GameNotifier game;
  final GameState gs;
  final Color playerCol, enemyCol;
  const _TokenBagWidget({required this.game, required this.gs,
    required this.playerCol, required this.enemyCol});

  static const gold  = AppColors.gold;
    static const grey  = AppColors.grey;

  @override
  Widget build(BuildContext context) {
    final bag = gs.tokenBag;
    final last = bag.lastDrawn;
    final playerRemaining = bag.playerCount;
    final enemyRemaining  = bag.enemyCount;
    return Container(
      color: AppColors.dark,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        Row(children: [
          Text('TOKEN BAG', style: GoogleFonts.cinzel(
            color: gold.withValues(alpha: 0.85), fontSize: 13, letterSpacing: 2, fontWeight: FontWeight.w600)),
          const Spacer(),
          if (last != null) Row(children: [
            Text(last.color == 'player' ? 'Your turn' : 'Opponent turn',
              style: GoogleFonts.cinzel(
                color: last.color == 'player' ? playerCol : enemyCol,
                fontSize: 11)),
          ]),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _BagBtn(label: 'Random', color: gold,
            count: playerRemaining + enemyRemaining,
            onTap: () { HapticFeedback.lightImpact(); game.drawRandom(); })),
          const SizedBox(width: 6),
          Expanded(child: _BagBtn(label: gs.armyName ?? 'Army', color: playerCol, dotColor: playerCol,
            count: playerRemaining,
            onTap: playerRemaining > 0 ? () { HapticFeedback.lightImpact(); game.drawByColor('player'); } : null)),
          const SizedBox(width: 6),
          Expanded(child: _BagBtn(label: 'Opponent', color: enemyCol, dotColor: enemyCol,
            count: enemyRemaining,
            onTap: enemyRemaining > 0 ? () { HapticFeedback.lightImpact(); game.drawByColor('enemy'); } : null)),
          const SizedBox(width: 6),
          Expanded(child: _BagBtn(label: 'Redo', color: grey,
            onTap: bag.lastDrawn != null ? () => game.undoLastDraw() : null)),
        ]),
      ]));
  }

}

// ── ENEMY ALIVE SELECTOR ─────────────────────────────────────────────
class _EnemyAliveSelector extends StatefulWidget {
  final GameNotifier game;
  final GameState gs;
  const _EnemyAliveSelector({required this.game, required this.gs});
  @override State<_EnemyAliveSelector> createState() => _EnemyAliveSelectorState();
}
class _EnemyAliveSelectorState extends State<_EnemyAliveSelector> {
  late int _count;
  @override void initState() { super.initState(); _count = widget.gs.currentEnemyAlive; }
  @override Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      HoverIconBtn(
        icon: Icons.remove,
        size: 24,
        padding: const EdgeInsets.all(12),
        onTap: _count > 0 ? () { setState(() => _count--); widget.game.setEnemyAlive(_count); } : null),
      Text('$_count', style: GoogleFonts.cinzel(color: AppColors.gold, fontSize: 22)),
      HoverIconBtn(
        icon: Icons.add,
        size: 24,
        padding: const EdgeInsets.all(12),
        onTap: _count < widget.gs.enemyUnitCount ? () { setState(() => _count++); widget.game.setEnemyAlive(_count); } : null),
    ]);
}

// ── UNIT CARD ────────────────────────────────────────────────────────
class _UnitCard extends StatelessWidget {
  final GameUnit unit;
  final GameNotifier game;
  final Color playerCol;
  const _UnitCard({required this.unit, required this.game, required this.playerCol});

  static const gold  = AppColors.gold;
  static const grey  = AppColors.grey;

  @override
  Widget build(BuildContext context) {
    final u              = unit.armyUnit.unit;
    final eliminated     = unit.isEliminated;
    final activated      = unit.activated;
    final conPct         = u.con > 0 ? unit.currentCon / u.con : 0.0;
    const activatedColor = Color(0xFF6B7A8D);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(
          color: (eliminated ? grey : typeColor(u.type)).withValues(alpha: eliminated ? 0.2 : 0.4),
          width: 1.5)),
      child: Column(children: [
        UnitCard(
          unit: u,
          customName: unit.armyUnit.customName,
          photoBase64: unit.armyUnit.photoBase64,
          bgColor: unit.armyUnit.bgColor,
          lore: unit.armyUnit.lore,
          dimmed: eliminated,
          onEdit: eliminated ? null : () => showGameEditDialog(context, unit, game),
          onAbilityUse: eliminated ? null : (String abilityName) {
            final ab = GameDataService.abilities
              .where((a) => a['name'] == abilityName).firstOrNull;
            final cpCost = ab?['cp_cost'] as int? ?? 0;
            if (cpCost <= 0) return null;
            return () => game.adjustCP(-cpCost);
          },
          hideBorder: true,
          actions: const []),
        LinearProgressIndicator(
          value: conPct,
          backgroundColor: AppColors.dark,
          valueColor: AlwaysStoppedAnimation(
            conPct > 0.5 ? const Color(0xFFA8C070)
            : conPct > 0.25 ? const Color(0xFFD4A870)
            : Colors.red),
          minHeight: 3),
        if (!eliminated)
          ConditionBadges(
            conditions: unit.conditions,
            onToggle: (c) => game.toggleCondition(unit.instanceId, c)),
        if (!eliminated)
          _NoteRow(
            note: unit.note,
            onEdit: () => _showNoteSheet(context, unit, game)),
        Container(
          color: AppColors.dark,
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
          child: Row(children: [
            Text('STR', style: GoogleFonts.cinzel(color: grey, fontSize: 10)),
            const SizedBox(width: 10),
            _GlowIcon(
              icon: Icons.remove_circle_outline,
              color: eliminated ? grey.withValues(alpha: 0.3) : Colors.red.withValues(alpha: 0.7),
              size: 22,
              onTap: eliminated ? () {} : () { HapticFeedback.lightImpact(); game.adjustCon(unit.instanceId, -1); }),
            const SizedBox(width: 8),
            Text('${unit.currentCon}/${u.con}',
              style: GoogleFonts.cinzel(
                color: eliminated ? grey : gold, fontSize: 14)),
            const SizedBox(width: 8),
            _GlowIcon(
              icon: Icons.add_circle_outline,
              color: unit.currentCon >= u.con
                ? grey.withValues(alpha: 0.3) : const Color(0xFFA8C070),
              size: 22,
              disabled: unit.currentCon >= u.con,
              onTap: unit.currentCon >= u.con ? () {}
                : () { HapticFeedback.lightImpact(); game.adjustCon(unit.instanceId, 1); }),
            const Spacer(),
            if (!eliminated && !activated)
              _ActivateBtn(
                label: 'Activate',
                color: gold,
                onTap: () { HapticFeedback.mediumImpact(); game.activateUnit(unit.instanceId); }),
            if (!eliminated && activated)
              _ActivateBtn(
                label: 'Ready',
                color: activatedColor,
                onTap: () { HapticFeedback.selectionClick(); game.deactivateUnit(unit.instanceId); }),
          ])),
      ]));
  }

  static void _showNoteSheet(BuildContext ctx, GameUnit unit, GameNotifier game) {
    final ctrl = TextEditingController(text: unit.note);
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: AppColors.dark,
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(
              color: grey.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Text(unit.displayName,
            style: GoogleFonts.cinzel(
              color: gold, fontSize: 14, letterSpacing: 0.5)),
          const SizedBox(height: 14),
          AetherraTextField(
            controller: ctrl,
            hintText: 'Battle notes…',
            maxLines: 4),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () { game.setNote(unit.instanceId, ''); Navigator.pop(ctx); },
              style: OutlinedButton.styleFrom(
                foregroundColor: grey,
                side: BorderSide(color: grey.withValues(alpha: 0.4)),
                shape: const RoundedRectangleBorder(),
                padding: const EdgeInsets.symmetric(vertical: 13)),
              child: Text('Clear', style: GoogleFonts.cinzel(fontSize: 13)))),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(
              onPressed: () { game.setNote(unit.instanceId, ctrl.text.trim()); Navigator.pop(ctx); },
              style: ElevatedButton.styleFrom(
                backgroundColor: gold,
                foregroundColor: AppColors.dark,
                shape: const RoundedRectangleBorder(),
                padding: const EdgeInsets.symmetric(vertical: 13)),
              child: Text('Save', style: GoogleFonts.cinzel(
                fontSize: 13, fontWeight: FontWeight.w600)))),
          ]),
        ])));
  }
}

// ── Note row ─────────────────────────────────────────────────────────────────
class _NoteRow extends StatelessWidget {
  final String note;
  final VoidCallback onEdit;
  const _NoteRow({required this.note, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final hasNote = note.isNotEmpty;
    return GestureDetector(
      onTap: onEdit,
      child: Container(
        color: AppColors.dark,
        padding: const EdgeInsets.fromLTRB(10, 3, 10, 3),
        child: Row(children: [
          Icon(
            hasNote ? Icons.sticky_note_2_outlined : Icons.add,
            size: 12,
            color: AppColors.grey.withValues(alpha: hasNote ? 0.55 : 0.35)),
          const SizedBox(width: 6),
          Expanded(child: Text(
            hasNote ? note : 'Add note…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.cinzel(
              color: hasNote
                  ? AppColors.grey.withValues(alpha: 0.7)
                  : AppColors.grey.withValues(alpha: 0.3),
              fontSize: 10,
              fontStyle: hasNote ? FontStyle.normal : FontStyle.italic))),
        ])));
  }
}

// ── Collapsible group section ─────────────────────────────────────────────
class _GameGroupSection extends StatefulWidget {
  final String groupName;
  final List<GameUnit> units;
  final bool isElimGrp;
  final GameNotifier game;
  final Color playerCol;
  final double topMargin;
  const _GameGroupSection({super.key, required this.groupName, required this.units,
    required this.isElimGrp, required this.game, required this.playerCol,
    required this.topMargin});
  @override State<_GameGroupSection> createState() => _GameGroupSectionState();
}

class _GameGroupSectionState extends State<_GameGroupSection> {
  static final Map<String, bool> _collapsedMap = {};
  static const gold = AppColors.gold;
  static const grey = AppColors.grey;

  static void clearState() => _collapsedMap.clear();

  bool get _collapsed => _collapsedMap[widget.groupName] ?? false;
  bool _hovered  = false;
  bool _dragOver = false;

  @override void initState() {
    super.initState();
    _GameDndOuterState._notifier.addListener(_onDndChange);
  }
  @override void dispose() {
    _GameDndOuterState._notifier.removeListener(_onDndChange);
    super.dispose();
  }
  void _onDndChange() {
    final active = _GameDndOuterState._dragging != null &&
        _GameDndOuterState._insertGrp == widget.groupName;
    if (active != _dragOver) setState(() => _dragOver = active);
  }

  int get _grpEndIdx {
    final units = widget.game.state?.units ?? [];
    final last = units.lastIndexWhere((u) => u.groupName == widget.groupName);
    return last < 0 ? units.length : last + 1;
  }

  void _toggle() => setState(() {
    _collapsedMap[widget.groupName] = !(_collapsedMap[widget.groupName] ?? false);
  });

  @override Widget build(BuildContext context) {
    final showDrop = _collapsed && !widget.isElimGrp;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.groupName.isNotEmpty)
        MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit:  (_) => setState(() => _hovered = false),
          child: GestureDetector(
          onTap: _toggle,
          child: showDrop
            ? DragTarget<GameUnit>(
                onWillAcceptWithDetails: (_) => false,
                onMove: (_) {
                  _GameDndOuterState.setInsert(_grpEndIdx, widget.groupName);
                  if (!_dragOver) setState(() => _dragOver = true);
                },
                onLeave: (_) => setState(() => _dragOver = false),
                builder: (_, __, ___) => _buildHeader(),
              )
            : _buildHeader(),
        ),              // GestureDetector
      ),                // MouseRegion
      if (!_collapsed)
        _GameGroupGrid(
          units: widget.units,
          game: widget.game,
          playerCol: widget.playerCol,
          grp: widget.isElimGrp ? '__eliminated__' : widget.groupName,
        ),
    ]);
  }

  Widget _buildHeader() {
    final dragAlpha  = _dragOver ? 0.22 : _hovered ? 0.14 : 0.07;
    final borderWidth = _dragOver ? 3.0 : 2.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      margin: EdgeInsets.only(bottom: 4, top: widget.topMargin),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: widget.isElimGrp
          ? Colors.red.withValues(alpha: dragAlpha)
          : gold.withValues(alpha: dragAlpha),
        border: Border(left: BorderSide(
          color: widget.isElimGrp
            ? Colors.red.withValues(alpha: 0.4) : gold,
          width: borderWidth))),
      child: Row(children: [
        Icon(_collapsed ? Icons.chevron_right : Icons.expand_more,
          color: widget.isElimGrp
            ? Colors.red.withValues(alpha: 0.85) : gold, size: 16),
        const SizedBox(width: 4),
        Text(widget.isElimGrp
            ? '☠ ELIMINATED' : widget.groupName.toUpperCase(),
          style: GoogleFonts.cinzel(
            color: widget.isElimGrp
              ? Colors.red.withValues(alpha: 0.85) : gold,
            fontSize: 10, letterSpacing: 1)),
        const Spacer(),
        if (widget.isElimGrp) ...[
          Text('${widget.units.length} unit${widget.units.length != 1 ? 's' : ''}',
            style: GoogleFonts.cinzel(color: Colors.red.withValues(alpha: 0.7), fontSize: 9)),
          const SizedBox(width: 6),
          Text('${widget.units.fold<int>(0, (s, u) => s + u.armyUnit.unit.cost)} pts',
            style: GoogleFonts.cinzel(color: Colors.red.withValues(alpha: 0.7), fontSize: 9)),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Units cannot be dragged here',
            child: Icon(Icons.lock_outline,
              color: Colors.red.withValues(alpha: 0.7), size: 13)),
        ]
        else ...[
          Text('${widget.units.length} unit${widget.units.length != 1 ? 's' : ''}',
            style: GoogleFonts.cinzel(color: grey, fontSize: 9)),
          const SizedBox(width: 6),
          Text('${widget.units.fold<int>(0, (s, u) => s + u.armyUnit.unit.cost)} pts',
            style: GoogleFonts.cinzel(color: grey, fontSize: 9)),
        ],
      ]),
    );
  }
}


// ── Game Group Grid with DnD placeholders ───────────────────────────────────
class _GameGroupGrid extends StatefulWidget {
  final List<GameUnit> units;
  final GameNotifier game;
  final Color playerCol;
  final String grp;
  const _GameGroupGrid({required this.units, required this.game,
    required this.playerCol, required this.grp});
  @override State<_GameGroupGrid> createState() => _GameGroupGridState();
}

class _GameGroupGridState extends State<_GameGroupGrid> {
  @override void initState() {
    super.initState();
    _GameDndOuterState._notifier.addListener(_rebuild);
  }
  @override void dispose() {
    _GameDndOuterState._notifier.removeListener(_rebuild);
    super.dispose();
  }
  void _rebuild() => setState(() {});

  @override Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final wg     = constraints.maxWidth - 10;
      final cols   = (wg / (300 + 8)).floor().clamp(1, 6);
      final cardWg = ((wg - (cols - 1) * 8) / cols).floorToDouble();

      final dragging  = _GameDndOuterState._dragging;
      final insertAt  = _GameDndOuterState._insertAt;
      final insertGrp = _GameDndOuterState._insertGrp;
      final allUnits  = widget.game.state!.units;

      final grpEndIdx = allUnits.lastIndexWhere((u) => u.groupName == widget.grp) + 1;

      // Build display with placeholder
      final display = <_GameItem>[];
      for (final u in widget.units) {
        final ai = allUnits.indexOf(u);
        if (insertGrp == widget.grp && insertAt == ai) {
          display.add(const _GameItem.ph());
        }
        if (u != dragging) display.add(_GameItem.unit(u, ai));
      }
      if (insertGrp == widget.grp && insertAt == grpEndIdx) {
        display.add(const _GameItem.ph());
      }

      final rows = <Widget>[];
      for (int r = 0; r * cols < display.length; r++) {
        final start    = r * cols;
        final end      = (start + cols).clamp(0, display.length);
        final rowItems = display.sublist(start, end);
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ...rowItems.asMap().entries.map((e) {
              final pad = EdgeInsets.only(left: e.key > 0 ? 8 : 0);
              if (e.value.isPlaceholder) {
                return Padding(padding: pad,
                child: SizedBox(width: cardWg, height: 157,
                  child: CustomPaint(painter: _DashedGamePainter(),
                    child: Container(color:
                      AppColors.gold.withValues(alpha: 0.07)))));
              }
              return Padding(padding: pad,
                child: SizedBox(width: cardWg,
                  child: _GameDndTile(
                    unit: e.value.unit!, absIdx: e.value.absIdx!,
                    grp: widget.grp, game: widget.game,
                    playerCol: widget.playerCol, allUnits: allUnits)));
            }),
            Expanded(child: DragTarget<GameUnit>(
              onWillAcceptWithDetails: (_) => false,
              onMove: (_) => _GameDndOuterState.setInsert(grpEndIdx, widget.grp),
              builder: (_, __, ___) => const SizedBox(height: 157))),
          ])));
      }

      // Empty group: show a large drop zone when dragging
      if (display.isEmpty) {
        final isTarget = insertGrp == widget.grp && dragging != null;
        return DragTarget<GameUnit>(
          onWillAcceptWithDetails: (_) => false,
          onMove: (_) => _GameDndOuterState.setInsert(grpEndIdx, widget.grp),
          builder: (_, __, ___) => AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: isTarget ? 160 : 60,
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: isTarget
                ? AppColors.gold.withValues(alpha: 0.07)
                : Colors.transparent,
              border: Border.all(
                color: AppColors.gold.withValues(
                  alpha: isTarget ? 0.5 : dragging != null ? 0.2 : 0.0))),
            child: Center(child: dragging != null
              ? Text('Drop here', style: GoogleFonts.cinzel(
                  color: AppColors.gold.withValues(alpha: 0.4),
                  fontSize: 11))
              : const SizedBox.shrink())));
      }

      // Bottom drop zone — below last row, catches "drop at end of group"
      rows.add(DragTarget<GameUnit>(
        onWillAcceptWithDetails: (_) => false,
        onMove: (_) {
          if (widget.grp != '__eliminated__') {
            _GameDndOuterState.setInsert(grpEndIdx, widget.grp);
          }
        },
        builder: (_, __, ___) => SizedBox(
          height: dragging != null ? 40 : 8,
          width: double.infinity)));

      return Column(children: rows);
    });
  }
}

class _GameItem {
  final GameUnit? unit; final int? absIdx; final bool isPlaceholder;
  const _GameItem.unit(this.unit, this.absIdx) : isPlaceholder = false;
  const _GameItem.ph() : unit = null, absIdx = null, isPlaceholder = true;
}

class _DashedGamePainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AppColors.gold.withValues(alpha: 0.8)
      ..strokeWidth = 1.5..style = PaintingStyle.stroke;
    const d = 7.0, g = 4.0;
    for (final m in (Path()..addRect(Rect.fromLTWH(0,0,size.width,size.height)))
        .computeMetrics()) {
      for (double x = 0; x < m.length; x += d + g) {
        canvas.drawPath(m.extractPath(x, (x+d).clamp(0,m.length)), p);
      }
    }
  }
  @override bool shouldRepaint(_DashedGamePainter o) => false;
}


// ── Game DnD outer drop catcher ─────────────────────────────────────────────
class _GameDndOuter extends StatefulWidget {
  final GameNotifier game;
  final Widget child;
  const _GameDndOuter({required this.game, required this.child});
  @override State<_GameDndOuter> createState() => _GameDndOuterState();
}

class _GameDndOuterState extends State<_GameDndOuter> {
  static GameUnit? _dragging;
  static int?      _insertAt;
  static String?   _insertGrp;
  static final _scrollCtrl = ScrollController();
  static Timer?   _scrollTimer;

  static const double _screenH = 800.0;

  static void _updateScroll(double globalY, [double? screenH]) {
    final sh = screenH ?? _screenH;
    if (!_scrollCtrl.hasClients || _dragging == null) return;
    final zone = sh * 0.20;
    const maxSpeed = 16.0;
    _scrollTimer?.cancel(); _scrollTimer = null;
    if (globalY < zone) {
      final t = 1.0 - (globalY / zone).clamp(0.0, 1.0);
      _scrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
        if (!_scrollCtrl.hasClients) return;
        _scrollCtrl.jumpTo((_scrollCtrl.offset - maxSpeed * t)
          .clamp(0, _scrollCtrl.position.maxScrollExtent));
      });
    } else if (globalY > sh - zone) {
      final t = ((globalY - (sh - zone)) / zone).clamp(0.0, 1.0);
      _scrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
        if (!_scrollCtrl.hasClients) return;
        _scrollCtrl.jumpTo((_scrollCtrl.offset + maxSpeed * t)
          .clamp(0, _scrollCtrl.position.maxScrollExtent));
      });
    }
  }

  static void _stopScroll() { _scrollTimer?.cancel(); _scrollTimer = null; }

  static void startDrag(GameUnit u) {
    _dragging = u; _insertAt = null; _insertGrp = null;
  }

  static final _notifier = ValueNotifier<int>(0);

  static void setInsert(int at, String g) {
    if (g == '__eliminated__') return;  // can't drag into eliminated
    if (_insertAt != at || _insertGrp != g) {
      _insertAt = at; _insertGrp = g;
      _notifier.value++;
    }
  }

  void drop(BuildContext context) {
    final u = _dragging;
    if (u != null && _insertAt != null && _insertGrp != null) {
      HapticFeedback.mediumImpact();
      final units = widget.game.state!.units;
      final from  = units.indexOf(u);
      if (from >= 0) {
        // Build new unit with updated group
        final newUnit = GameUnit(
          instanceId: u.instanceId, armyUnit: u.armyUnit,
          currentCon: u.currentCon, activated: u.activated,
          expanded: u.expanded, groupName: _insertGrp!,
          conditions: List.from(u.conditions));
        units.removeAt(from);
        final to = (_insertAt! > from ? _insertAt! - 1 : _insertAt!)
          .clamp(0, units.length);
        units.insert(to, newUnit);
        widget.game.notifyListenersPublic();
      }
    }
    _dragging = null; _insertAt = null; _insertGrp = null;
    _notifier.value++;
  }

  static void cancel() {
    // If we have a known insert position, complete the drop there
    if (_insertAt != null && _insertGrp != null && _dragging != null) {
      final notifier = _notifier; // trigger rebuild after drop
      _dragging = null; _insertAt = null; _insertGrp = null;
      notifier.value++;
    } else {
      _dragging = null; _insertAt = null; _insertGrp = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _GameDndOuterState._notifier,
      builder: (_, __, ___) => DragTarget<GameUnit>(
        onWillAcceptWithDetails: (_) => _dragging != null,
        onAcceptWithDetails: (_) => drop(context),
        builder: (_, __, ___) => widget.child));
  }
}

// ── Game DnD tile ─────────────────────────────────────────────────────────
class _GameDndTile extends StatelessWidget {
  final GameUnit unit;
  final int absIdx;
  final String grp;
  final GameNotifier game;
  final Color playerCol;
  final List<GameUnit> allUnits;
  const _GameDndTile({required this.unit, required this.absIdx,
    required this.grp, required this.game, required this.playerCol,
    required this.allUnits});

  @override
  Widget build(BuildContext context) {
    final isTouch = defaultTargetPlatform == TargetPlatform.android ||
                    defaultTargetPlatform == TargetPlatform.iOS;
    final draggable = !isTouch
      ? (Widget child) => Draggable<GameUnit>(
          data: unit,
          onDragStarted: () => _GameDndOuterState.startDrag(unit),
          onDragEnd: (det) { _GameDndOuterState._stopScroll(); if (!det.wasAccepted) _GameDndOuterState.cancel(); },
          onDraggableCanceled: (_, __) { _GameDndOuterState._stopScroll(); _GameDndOuterState.cancel(); },
          feedback: Material(color: Colors.transparent,
            child: Transform.scale(scale: 1.05,
              child: SizedBox(width: 260,
                child: _UnitCard(unit: unit, game: game, playerCol: playerCol)))),
          childWhenDragging: Opacity(opacity: 0.25,
            child: _UnitCard(unit: unit, game: game, playerCol: playerCol)),
          child: child)
      : (Widget child) => LongPressDraggable<GameUnit>(
          data: unit,
          delay: const Duration(milliseconds: 400),
          onDragStarted: () => _GameDndOuterState.startDrag(unit),
          onDragEnd: (det) { _GameDndOuterState._stopScroll(); if (!det.wasAccepted) _GameDndOuterState.cancel(); },
          onDraggableCanceled: (_, __) { _GameDndOuterState._stopScroll(); _GameDndOuterState.cancel(); },
          feedback: Material(color: Colors.transparent,
            child: Transform.scale(scale: 1.05,
              child: SizedBox(width: 260,
                child: _UnitCard(unit: unit, game: game, playerCol: playerCol)))),
          childWhenDragging: Opacity(opacity: 0.25,
            child: _UnitCard(unit: unit, game: game, playerCol: playerCol)),
          child: child);

    return DragTarget<GameUnit>(
      onWillAcceptWithDetails: (_) => false,
      onMove: (det) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final local = box.globalToLocal(det.offset);
        _GameDndOuterState.setInsert(
          local.dx < box.size.width / 2 ? absIdx : absIdx + 1, grp);
      },
      builder: (_, __, ___) => draggable(_UnitCard(unit: unit, game: game, playerCol: playerCol)));
  }
}

void showGameEditDialog(BuildContext context, GameUnit unit, GameNotifier game) {
  const gold = AppColors.gold;
  const grey = AppColors.grey;
  final nameCtrl = TextEditingController(
    text: unit.armyUnit.customName.isNotEmpty
      ? unit.armyUnit.customName : unit.armyUnit.unit.name);
  final loreCtrl = TextEditingController(text: unit.armyUnit.lore ?? '');
  bool removingBg = false;
  bool placeholderHovered = false;
  String selColor = unit.armyUnit.bgColor ?? '#1E1A15';

  Widget lbl(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(t, style: GoogleFonts.cinzel(color: grey, fontSize: 13, letterSpacing: 1.5)));

  showModalBottomSheet(
    context: context, isScrollControlled: true, backgroundColor: AppColors.dark,
    builder: (_) => StatefulBuilder(builder: (ctx, setSt) {
      final hasPhoto = (unit.armyUnit.photoBase64 ?? '').isNotEmpty;
      return DraggableScrollableSheet(
        expand: false, initialChildSize: 0.92,
        builder: (_, scroll) => SingleChildScrollView(
          controller: scroll,
          padding: EdgeInsets.fromLTRB(16, 16, 16,
            MediaQuery.of(context).viewInsets.bottom + 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // drag handle
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: grey.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),

            Text('Edit Unit',
              style: GoogleFonts.cinzel(color: gold, fontSize: 17)),
            const SizedBox(height: 16),

            AetherraTextField(
              controller: nameCtrl,
              hintText: 'Display Name…',
              style: GoogleFonts.cinzel(color: gold, fontSize: 13)),
            const SizedBox(height: 16),

            // photo (full-width, portrait-ratio)
            Container(
              width: double.infinity, height: 220,
              foregroundDecoration: BoxDecoration(
                border: Border.all(color: gold.withValues(alpha: 0.35))),
              color: AppColors.parseHex(selColor),
              child: Stack(children: [
                Positioned.fill(child: hasPhoto
                  ? Center(child: CachedBase64Image(
                      base64: unit.armyUnit.photoBase64!,
                      width: 220 * 80 / 140, height: 220))
                  : GestureDetector(
                      onTap: () async {
                        final b64 = await pickAndCropPhoto(ctx);
                        if (b64 != null) {
                          setSt(() { unit.armyUnit.photoBase64 = b64; placeholderHovered = false; });
                          game.notifyListenersPublic();
                        }
                      },
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) => setSt(() => placeholderHovered = true),
                        onExit:  (_) => setSt(() => placeholderHovered = false),
                        child: Center(child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 80),
                          opacity: placeholderHovered ? 1.0 : 0.35,
                          child: const Icon(Icons.add_photo_alternate_outlined,
                            color: gold, size: 44,
                            shadows: [Shadow(color: Colors.black87, blurRadius: 8)])))))),
                if (removingBg)
                  Positioned.fill(child: Container(
                    color: AppColors.dark.withValues(alpha: 0.75),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: gold),
                        const SizedBox(height: 12),
                        Text('Removing background…',
                          style: GoogleFonts.cinzel(color: gold, fontSize: 12)),
                      ]))),
              ])),

            // photo action icons + remove bg + color swatch
            const SizedBox(height: 8),
            Row(children: [
              _GamePhotoIcon(icon: Icons.add_photo_alternate_outlined,
                onTap: () async {
                  final b64 = await pickAndCropPhoto(ctx);
                  if (b64 != null) {
                    setSt(() => unit.armyUnit.photoBase64 = b64);
                    game.notifyListenersPublic();
                  }
                }),
              if (hasPhoto) ...[
                const SizedBox(width: 4),
                _GamePhotoIcon(icon: Icons.crop,
                  onTap: () async {
                    final b64 = await editCropPhoto(ctx, unit.armyUnit.photoBase64!);
                    if (b64 != null) {
                      setSt(() => unit.armyUnit.photoBase64 = b64);
                      game.notifyListenersPublic();
                    }
                  }),
                const SizedBox(width: 4),
                _GamePhotoIcon(icon: Icons.delete_outline,
                  color: Colors.red,
                  onTap: () {
                    setSt(() => unit.armyUnit.photoBase64 = null);
                    game.notifyListenersPublic();
                  }),
              ],
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                onPressed: (removingBg || !hasPhoto) ? null : () async {
                  setSt(() => removingBg = true);
                  try {
                    final bytes  = decodePhotoBytes(unit.armyUnit.photoBase64!);
                    final result = await removeBg(bytes);
                    if (result != null) {
                      String newB64;
                      try {
                        final raw = base64Decode(unit.armyUnit.photoBase64!);
                        if (raw.isNotEmpty && raw[0] == 0x7B) {
                          final info = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
                          newB64 = base64Encode(utf8.encode(
                            jsonEncode({...info, 'src': base64Encode(result)})));
                        } else {
                          newB64 = base64Encode(result);
                        }
                      } catch (_) { newB64 = base64Encode(result); }
                      setSt(() { unit.armyUnit.photoBase64 = newB64; removingBg = false; });
                      game.notifyListenersPublic();
                    } else {
                      setSt(() => removingBg = false);
                    }
                  } catch (e) {
                    setSt(() => removingBg = false);
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      backgroundColor: AppColors.dark,
                      content: Text('Background removal failed: $e',
                        style: GoogleFonts.cinzel(color: Colors.redAccent, fontSize: 12)),
                      duration: const Duration(seconds: 4),
                    ));
                    }
                  }
                },
                icon: const Icon(Icons.auto_fix_high_outlined, color: gold, size: 15),
                label: Text('Remove Background',
                  style: GoogleFonts.cinzel(fontSize: 13, letterSpacing: 1)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: gold,
                  side: BorderSide(color: gold.withValues(alpha: 0.5)),
                  shape: const RoundedRectangleBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 10)))),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () async {
                  final picked = await showAetherraDialogRaw<String>(
                    ctx,
                    Builder(builder: (dCtx) => aetherraDialogContainer(
                      title: 'Background Color',
                      content: Wrap(
                        spacing: 8, runSpacing: 8,
                        children: _kUnitBgPresets.map((hex) {
                          final isSel = selColor.toLowerCase() == hex.toLowerCase();
                          return GestureDetector(
                            onTap: () => Navigator.pop(dCtx, hex),
                            child: Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.parseHex(hex),
                                border: Border.all(
                                  color: isSel ? gold : gold.withValues(alpha: 0.25),
                                  width: isSel ? 3.0 : 1.0)),
                              child: isSel
                                ? const Center(child: Icon(Icons.check,
                                    color: Colors.white, size: 18,
                                    shadows: [Shadow(color: Colors.black87, blurRadius: 6)]))
                                : null));
                        }).toList()))));
                  if (picked != null) setSt(() => selColor = picked);
                },
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.parseHex(selColor),
                    border: Border.all(color: gold, width: 2)))),
            ]),
            const SizedBox(height: 6),
            Text('Tip: Upload a transparent PNG for better results.',
              style: GoogleFonts.cinzel(color: grey.withValues(alpha: 0.85),
                fontSize: 10, fontStyle: FontStyle.italic)),
            const SizedBox(height: 12),

            lbl('Lore (optional)'),
            AetherraTextField(
              controller: loreCtrl,
              hintText: 'History, origin, legend…',
              minLines: 4, maxLines: null,
              style: const TextStyle(color: AppColors.textLight, fontSize: 14, height: 1.5)),
            const SizedBox(height: 20),

            SizedBox(width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  unit.armyUnit.customName = nameCtrl.text.trim();
                  unit.armyUnit.bgColor    = selColor;
                  final l = loreCtrl.text.trim();
                  unit.armyUnit.lore = l.isEmpty ? null : l;
                  game.notifyListenersPublic();
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: gold, foregroundColor: AppColors.dark,
                  side: BorderSide.none,
                  shape: const RoundedRectangleBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text('Save Changes',
                  style: GoogleFonts.cinzel(
                    color: AppColors.dark, fontSize: 15, letterSpacing: 2,
                    fontWeight: FontWeight.w700)))),
          ])));
    }));
}

// ── D20 Dice Roller ──────────────────────────────────────────────────────────
class _DiceButton extends StatefulWidget {
  const _DiceButton();
  @override State<_DiceButton> createState() => _DiceButtonState();
}

class _DiceButtonState extends State<_DiceButton>
    with SingleTickerProviderStateMixin {
  static const gold = AppColors.gold;
  static const grey = AppColors.grey;

  int _diceCount  = 1;
  int? _lastResult;
  List<int> _rolls = [];
  bool _rolling    = false;
  late AnimationController _ctrl;
  late Animation<double> _shake;

  @override void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this,
      duration: const Duration(milliseconds: 600));
    _shake = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.15), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.15, end: 0.15), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.15, end: -0.10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -0.10, end: 0.10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.10, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  void _roll() async {
    if (_rolling) return;
    HapticFeedback.heavyImpact();
    final rng   = math.Random();
    final rolls = List.generate(_diceCount, (_) => rng.nextInt(10) + 1);
    final best  = rolls.reduce((a, b) => a > b ? a : b);
    setState(() { _rolling = true; _lastResult = null; _rolls = []; });
    _ctrl.forward(from: 0);

    Provider.of<GameNotifier>(context, listen: false).recordDiceRoll(rolls);

    // Show overlay animation
    final overlay = Overlay.of(context);
    final entry   = OverlayEntry(builder: (_) =>
      _DiceRollOverlay(diceCount: _diceCount, diceType: 10, results: rolls, best: best));
    overlay.insert(entry);

    await Future.delayed(const Duration(milliseconds: 2900));
    entry.remove();
    if (mounted) setState(() { _rolls = rolls; _lastResult = best; _rolling = false; });
  }

  void _showPicker() {
    int? hoveredN;
    showAetherraSheet<void>(context,
      title: 'How many d10?',
      body: StatefulBuilder(builder: (ctx, setSt) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Roll $_diceCount × d10 — keep highest',
            style: GoogleFonts.cinzel(color: grey, fontSize: 11)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final n in [1, 2, 3, 4, 5])
              MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setSt(() => hoveredN = n),
                onExit:  (_) => setSt(() => hoveredN = null),
                child: GestureDetector(
                  onTap: () => setSt(() => _diceCount = n),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 40, height: 40,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: _diceCount == n
                        ? gold.withValues(alpha: 0.2)
                        : hoveredN == n ? gold.withValues(alpha: 0.08) : Colors.transparent,
                      border: Border.all(
                        color: _diceCount == n ? gold
                          : hoveredN == n ? gold.withValues(alpha: 0.6)
                          : grey.withValues(alpha: 0.3),
                        width: _diceCount == n ? 1.5 : 1)),
                    child: Center(child: Text('$n',
                      style: GoogleFonts.cinzel(
                        color: _diceCount == n ? gold
                          : hoveredN == n ? gold.withValues(alpha: 0.85)
                          : grey,
                        fontSize: 16, fontWeight: FontWeight.bold)))))),
          ]),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final n in [6, 7, 8, 9, 10])
              MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setSt(() => hoveredN = n),
                onExit:  (_) => setSt(() => hoveredN = null),
                child: GestureDetector(
                  onTap: () => setSt(() => _diceCount = n),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 40, height: 40,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: _diceCount == n
                        ? gold.withValues(alpha: 0.2)
                        : hoveredN == n ? gold.withValues(alpha: 0.08) : Colors.transparent,
                      border: Border.all(
                        color: _diceCount == n ? gold
                          : hoveredN == n ? gold.withValues(alpha: 0.6)
                          : grey.withValues(alpha: 0.3),
                        width: _diceCount == n ? 1.5 : 1)),
                    child: Center(child: Text('$n',
                      style: GoogleFonts.cinzel(
                        color: _diceCount == n ? gold
                          : hoveredN == n ? gold.withValues(alpha: 0.85)
                          : grey,
                        fontSize: 16, fontWeight: FontWeight.bold)))))),
          ]),
        ])),
      actions: [
        SheetAction('Cancel', grey, () => Navigator.pop(context), outlined: true),
        SheetAction('Roll',   gold, () { Navigator.pop(context); _roll(); }),
      ]);
  }

  bool _hovered = false;

  @override Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _showPicker,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: SizedBox(
            width: 105, height: 87,
          child: Stack(children: [
            Positioned(left: 1, right: 1, top: 1, bottom: _rolls.isNotEmpty ? 16 : 1,
              child: FittedBox(
                fit: BoxFit.contain,
                child: AnimatedBuilder(
                  animation: _shake,
                  builder: (_, child) => Transform.rotate(
                    angle: _shake.value, child: child),
                  child: AnimatedOpacity(
                    opacity: _hovered ? 1.0 : 0.7,
                    duration: const Duration(milliseconds: 100),
                    child: _rolling
                      ? const D20Icon(color: gold)
                      : D20Icon(number: _lastResult, color: gold))))),
            // Numbers only after rolling
            if (_rolls.isNotEmpty)
              Positioned(left: 0, right: 0, bottom: 1,
                child: Text(
                  _rolls.join(' '),
                  style: GoogleFonts.cinzel(color: grey, fontSize: 9),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center)),
          ])))));
  }
}


// ── Dice Roll Overlay Animation ──────────────────────────────────────────────
class _DiceRollOverlay extends StatefulWidget {
  final int diceCount;
  final int diceType;
  final List<int> results;
  final int best;
  const _DiceRollOverlay({required this.diceCount, required this.diceType,
    required this.results, required this.best});
  @override State<_DiceRollOverlay> createState() => _DiceRollOverlayState();
}

class _DiceRollOverlayState extends State<_DiceRollOverlay>
    with TickerProviderStateMixin {
  final _rng = math.Random();
  late List<_DieState> _dice;
  late AnimationController _masterCtrl;
  bool _showResult = false;

  @override void initState() {
    super.initState();
    _masterCtrl = AnimationController(vsync: this,
      duration: const Duration(milliseconds: 2800));

    final n = widget.diceCount;
    _dice = List.generate(n, (i) {
      final spread = n == 1 ? [0.5] :
        List.generate(n, (j) => 0.18 + j * 0.64 / (n - 1));
      return _DieState(
        result: widget.results[i],
        isBest: widget.results[i] == widget.best,
        sx: 0.1 + _rng.nextDouble() * 0.8,
        sy: -0.18,
        ex: (spread[i]).clamp(0.1, 0.9),
        ey: 0.32 + _rng.nextDouble() * 0.10,
        totalSpin: (2.0 + _rng.nextDouble() * 2.5) *
          (_rng.nextBool() ? 1 : -1) * math.pi * 2,
        tiltX: (_rng.nextDouble() - 0.5) * 0.8,
        tiltY: (_rng.nextDouble() - 0.5) * 0.8,
        delay: i * 140,
      );
    });

    _masterCtrl.forward();
    Future.delayed(const Duration(milliseconds: 2150), () {
      if (mounted) setState(() => _showResult = true);
    });
  }

  @override void dispose() { _masterCtrl.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dieSize = math.min(size.width / widget.diceCount.clamp(1, 3) * 0.7,
                             size.height * 0.22).clamp(80.0, 160.0);

    return Material(color: Colors.black.withValues(alpha: 0.65),
      child: Stack(children: [

        ...List.generate(_dice.length, (i) {
          final d = _dice[i];
          return AnimatedBuilder(animation: _masterCtrl, builder: (_, __) {
            final raw = (_masterCtrl.value * 2800 - d.delay) / 1700;
            final t   = raw.clamp(0.0, 1.0);
            if (t <= 0) return const SizedBox();

            final tPos = Curves.easeOut.transform(t);
            final x = (d.sx + (d.ex - d.sx) * tPos) * size.width;
            double yFactor;
            if (t < 0.75) {
              yFactor = Curves.easeIn.transform(t / 0.75);
            } else {
              final bt = (t - 0.75) / 0.25;
              yFactor = 1.0 - math.sin(bt * math.pi) * 0.07 * (1 - bt);
            }
            final y = (d.sy + (d.ey - d.sy) * yFactor) * size.height;
            final spinT  = Curves.decelerate.transform(t);
            final angle  = d.totalSpin * spinT;
            final settled = t >= 0.90;
            // 3D tilt animates away as dice lands
            final tiltFade = settled ? 0.0 : (1.0 - t);
            final tiltX = d.tiltX * tiltFade;
            final tiltY = d.tiltY * tiltFade;
            final airScale = t < 0.75
              ? 1.0 + (1.0 - t / 0.75) * 0.3 : 1.0;
            final wobble = settled
              ? math.sin((t - 0.90) / 0.10 * math.pi * 5) *
                (1 - (t - 0.90) / 0.10) * 0.05 : 0.0;
            final displayVal = t < 0.87
              ? (_rng.nextInt(widget.diceType) + 1) : d.result;

            return Positioned(
              left: x - dieSize / 2, top: y - dieSize / 2,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateX(tiltX)
                  ..rotateY(tiltY)
                  ..rotateZ(angle + wobble)
                  ..scaleByDouble(airScale, airScale, 1.0, 1.0),
                child: _D203D(
                  value: displayVal,
                  size: dieSize,
                  highlight: settled && d.isBest,
                  rolling: !settled)));
          });
        }),

        if (_showResult)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 500),
            curve: Curves.elasticOut,
            builder: (_, v, __) {
              // Find best die position
              final bestIdx = widget.results.indexOf(widget.best);
              final bestDie = _dice.isNotEmpty && bestIdx < _dice.length
                ? _dice[bestIdx] : null;
              return Stack(children: [
                // Best die centered at top
                if (bestDie != null)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: bestDie.ey, end: 0.25),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    builder: (_, yv, __) {
                      final size = MediaQuery.of(context).size;
                      return Positioned(
                        left: size.width / 2 - 55,
                        top: yv * size.height - 55,
                        child: Transform.scale(scale: v * 1.5,
                          child: _D203D(
                            value: widget.best, size: 110,
                            highlight: true, rolling: false)));
                    }),
                // All results small at bottom
                Positioned(
                  bottom: MediaQuery.of(context).size.height * 0.1,
                  left: 0, right: 0,
                  child: Transform.scale(scale: v,
                    child: Center(child: Text(
                      widget.results.join('  '),
                      style: GoogleFonts.cinzel(
                        color: AppColors.grey, fontSize: 18,
                        letterSpacing: 4))))),
              ]);
            }),
      ]));
  }
}

class _DieState {
  final int result; final bool isBest;
  final double sx, sy, ex, ey, totalSpin, tiltX, tiltY;
  final int delay;
  const _DieState({required this.result, required this.isBest,
    required this.sx, required this.sy, required this.ex, required this.ey,
    required this.totalSpin, required this.tiltX, required this.tiltY,
    required this.delay});
}

// ── 3D D20 painted widget ─────────────────────────────────────────────────
class _D203D extends StatelessWidget {
  final int value;
  final double size;
  final bool highlight;
  final bool rolling;
  const _D203D({required this.value, required this.size,
    required this.highlight, required this.rolling});
  @override Widget build(BuildContext context) => CustomPaint(
    size: Size(size, size),
    painter: _D203DPainter(value: value, highlight: highlight,
      rolling: rolling));
}

class _D203DPainter extends CustomPainter {
  final int value;
  final bool highlight;
  final bool rolling;
  static const gold   = AppColors.gold;
  static const dark1  = AppColors.dark;
  const _D203DPainter({required this.value, required this.highlight,
    required this.rolling});

  @override void paint(Canvas canvas, Size sz) {
    final cx = sz.width  / 2;
    final cy = sz.height / 2;
    final r  = sz.width  * 0.44;

    // ── Build icosahedron-like faces ────────────────────────────────
    // Approximation: 3D d20 projected — top triangle, 5 upper, 5 lower, bottom
    // We draw a hexagon with inner triangles and 3D shading

    final verts = <Offset>[];
    for (int i = 0; i < 6; i++) {
      final a = i * math.pi / 3 - math.pi / 2;
      verts.add(Offset(cx + r * math.cos(a), cy + r * math.sin(a)));
    }
    final midR = r * 0.5;
    final midVerts = <Offset>[];
    for (int i = 0; i < 6; i++) {
      final a = i * math.pi / 3 - math.pi / 6;
      midVerts.add(Offset(cx + midR * math.cos(a), cy + midR * math.sin(a)));
    }
    final center = Offset(cx, cy);

    // ── Shadow/glow ─────────────────────────────────────────────────
    if (highlight) {
      final hex = _hexPath(cx, cy, r + 8);
      canvas.drawPath(hex, Paint()
        ..color = gold.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16)
        ..style = PaintingStyle.fill);
    } else {
      final hex = _hexPath(cx, cy, r + 4);
      canvas.drawPath(hex, Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
        ..style = PaintingStyle.fill);
    }

    // ── Draw 6 triangular faces with 3D shading ─────────────────────
    // Light source: top-right
    final faceShades = [0.85, 0.70, 0.55, 0.45, 0.60, 0.75];
    for (int i = 0; i < 6; i++) {
      final v1 = verts[i];
      final v2 = verts[(i + 1) % 6];
      final shade = faceShades[i];
      final tri = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(v1.dx, v1.dy)
        ..lineTo(v2.dx, v2.dy)
        ..close();
      canvas.drawPath(tri, Paint()
        ..color = Color.lerp(dark1, AppColors.dark, shade)!
        ..style = PaintingStyle.fill);
    }

    // ── Mid-ring faces (gives depth) ────────────────────────────────
    final midShades = [0.95, 0.80, 0.60, 0.50, 0.65, 0.80];
    for (int i = 0; i < 6; i++) {
      final v1 = verts[i];
      final v2 = verts[(i + 1) % 6];
      final m1 = midVerts[i];
      final tri = Path()
        ..moveTo(v1.dx, v1.dy)
        ..lineTo(v2.dx, v2.dy)
        ..lineTo(m1.dx, m1.dy)
        ..close();
      canvas.drawPath(tri, Paint()
        ..color = Color.lerp(AppColors.dark, const Color(0xFF3A3020), midShades[i])!
        ..style = PaintingStyle.fill);
    }

    // ── Edge lines ──────────────────────────────────────────────────
    for (int i = 0; i < 6; i++) {
      final v1 = verts[i];
      final v2 = verts[(i + 1) % 6];
      canvas.drawLine(v1, v2, Paint()
        ..color = gold.withValues(alpha: highlight ? 0.9 : 0.5)
        ..strokeWidth = highlight ? 2.0 : 1.3
        ..style = PaintingStyle.stroke);
      canvas.drawLine(center, v1, Paint()
        ..color = gold.withValues(alpha: 0.25)
        ..strokeWidth = 0.8..style = PaintingStyle.stroke);
    }

    // ── Specular highlight top-right ────────────────────────────────
    canvas.drawCircle(
      Offset(cx + r * 0.2, cy - r * 0.25), r * 0.18,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
        ..style = PaintingStyle.fill);

    // ── Number ──────────────────────────────────────────────────────
    final fs = value >= 10 ? sz.width * 0.27 : sz.width * 0.32;
    final tp = TextPainter(
      text: TextSpan(text: '$value',
        style: TextStyle(
          color: highlight ? gold
            : (rolling ? gold.withValues(alpha: 0.7) : gold.withValues(alpha: 0.95)),
          fontSize: fs,
          fontWeight: FontWeight.bold,
          shadows: highlight ? [const Shadow(color: gold, blurRadius: 12)] : null)),
      textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  Path _hexPath(double cx, double cy, double r) {
    final p = Path();
    for (int i = 0; i < 6; i++) {
      final a = i * math.pi / 3 - math.pi / 2;
      final v = Offset(cx + r * math.cos(a), cy + r * math.sin(a));
      i == 0 ? p.moveTo(v.dx, v.dy) : p.lineTo(v.dx, v.dy);
    }
    return p..close();
  }

  @override bool shouldRepaint(_D203DPainter o) =>
    o.value != value || o.highlight != highlight || o.rolling != rolling;
}


// ── Icon with hover glow, no layout shift ────────────────────────────────────
class _GlowIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onTap;
  final bool disabled;
  const _GlowIcon({required this.icon, required this.color,
    required this.size, required this.onTap, this.disabled = false});
  @override State<_GlowIcon> createState() => _GlowIconState();
}
class _GlowIconState extends State<_GlowIcon> {
  bool _hovered = false;
  bool _pressed = false;
  @override Widget build(BuildContext context) =>
    MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: widget.disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown:   (_) => setState(() => _pressed = true),
        onTapUp:     (_) { setState(() => _pressed = false); widget.onTap(); },
        onTapCancel: ()  => setState(() => _pressed = false),
        child: SizedBox(
          width: widget.size + 8, height: widget.size + 8,
          child: Center(child: AnimatedScale(
            scale: _pressed && !widget.disabled ? 0.80 : 1.0,
            duration: const Duration(milliseconds: 80),
            child: Icon(widget.icon,
              color: !widget.disabled && (_hovered || _pressed)
                ? widget.color
                : widget.color.withValues(alpha: 0.5),
              size: widget.size))))));
}




// ── Activate / Ready button — same style as +Add ──────────────────────────
class _ActivateBtn extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActivateBtn({required this.label, required this.color, required this.onTap});
  @override State<_ActivateBtn> createState() => _ActivateBtnState();
}
class _ActivateBtnState extends State<_ActivateBtn> {
  bool _hovered = false;
  bool _pressed = false;
  @override Widget build(BuildContext context) =>
    MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown:   (_) => setState(() => _pressed = true),
        onTapUp:     (_) { setState(() => _pressed = false); widget.onTap(); },
        onTapCancel: ()  => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          transform: _pressed ? (Matrix4.identity()..scaleByDouble(0.88, 0.88, 1.0, 1.0)) : Matrix4.identity(),
          transformAlignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _pressed
              ? widget.color.withValues(alpha: 0.45)
              : widget.color.withValues(alpha: _hovered ? 0.65 : 1.0)),
          child: Text(widget.label,
            style: GoogleFonts.cinzel(
              color: AppColors.dark,
              fontSize: 11, fontWeight: FontWeight.w600)))));
}

class _ActionBtn extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  const _ActionBtn({required this.label, required this.icon,
    required this.onTap, required this.color});
  @override State<_ActionBtn> createState() => _ActionBtnState();
}
class _ActionBtnState extends State<_ActionBtn> {
  bool _hovered = false;
  bool _pressed = false;
  @override Widget build(BuildContext context) =>
    MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown:   (_) => setState(() => _pressed = true),
        onTapUp:     (_) { setState(() => _pressed = false); widget.onTap(); },
        onTapCancel: ()  => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          transform: _pressed ? (Matrix4.identity()..scaleByDouble(0.92, 0.92, 1.0, 1.0)) : Matrix4.identity(),
          transformAlignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: _hovered ? widget.color.withValues(alpha: 0.1) : Colors.transparent),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(widget.icon,
              color: _hovered || _pressed ? widget.color : widget.color.withValues(alpha: 0.6),
              size: 13),
            const SizedBox(width: 4),
            Text(widget.label,
              style: GoogleFonts.cinzel(
                color: _hovered || _pressed ? widget.color : widget.color.withValues(alpha: 0.7),
                fontSize: 10),
              overflow: TextOverflow.ellipsis, maxLines: 1),
          ]))));
}

// ── Token bag button with Sort-style hover ────────────────────────────────
class _BagBtn extends StatefulWidget {
  final String label;
  final Color color;
  final Color? dotColor;
  final int? count;
  final VoidCallback? onTap;
  const _BagBtn({required this.label, required this.color, this.dotColor, this.count, this.onTap});
  @override State<_BagBtn> createState() => _BagBtnState();
}
class _BagBtnState extends State<_BagBtn> {
  bool _hovered = false;
  bool _pressed = false;
  @override Widget build(BuildContext context) {
    final active = widget.onTap != null;
    final c = widget.color;
    return MouseRegion(
      onEnter: (_) { if (active) setState(() => _hovered = true); },
      onExit:  (_) => setState(() => _hovered = false),
      cursor: active ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown:   (_) { if (active) setState(() => _pressed = true); },
        onTapUp:     (_) { setState(() => _pressed = false); widget.onTap?.call(); },
        onTapCancel: ()  => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          transform: _pressed ? (Matrix4.identity()..scaleByDouble(0.92, 0.92, 1.0, 1.0)) : Matrix4.identity(),
          transformAlignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: active
              ? (_pressed ? c.withValues(alpha: 0.45)
                : c.withValues(alpha: _hovered ? 0.65 : 1.0))
              : c.withValues(alpha: 0.2)),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              widget.count != null
                ? '${widget.label} (${widget.count})'
                : widget.label,
              style: GoogleFonts.cinzel(
                color: active ? AppColors.dark : AppColors.dark.withValues(alpha: 0.4),
                fontSize: 11, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center)))));

  }
}

// ── Banner wrapper — hides on scroll down, shows on scroll up ────────────────
class _ScrollHiddenBanner extends StatefulWidget {
  final GameState gs;
  final GameNotifier game;
  const _ScrollHiddenBanner({required this.gs, required this.game});
  @override State<_ScrollHiddenBanner> createState() => _ScrollHiddenBannerState();
}
class _ScrollHiddenBannerState extends State<_ScrollHiddenBanner> {
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    // Add listener after first frame — scroll controller is attached by then
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _GameDndOuterState._scrollCtrl.addListener(_onScroll);
    });
  }

  @override
  void dispose() {
    _GameDndOuterState._scrollCtrl.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!_GameDndOuterState._scrollCtrl.hasClients) return;
    final show = _GameDndOuterState._scrollCtrl.offset < 40;
    if (show != _visible) setState(() => _visible = show);
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    duration: const Duration(milliseconds: 220),
    opacity: _visible ? 1.0 : 0.0,
    child: ClipRect(
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOut,
        alignment: Alignment.bottomCenter,
        heightFactor: _visible ? 1.0 : 0.0,
        child: _GameBanner(gs: widget.gs, game: widget.game),
      ),
    ),
  );
}

// ── Army Banner ──────────────────────────────────────────────────────────────
class _GameBanner extends StatefulWidget {
  final GameState gs;
  final GameNotifier game;
  const _GameBanner({required this.gs, required this.game});
  @override State<_GameBanner> createState() => _GameBannerState();
}

class _GameBannerState extends State<_GameBanner> {
  bool _loreExpanded  = false;
  bool _loreHovered   = false;
  bool _unitsExpanded = false;
  bool _unitsHovered  = false;
  Widget? _cachedImg;
  static const gold = AppColors.gold;
  static const grey = AppColors.grey;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    // Fast path: image already threaded into GameState
    final b64 = widget.gs.armyImageB64;
    if (b64 != null && b64.isNotEmpty) {
      if (mounted) setState(() => _cachedImg = _buildImg(b64));
      return;
    }
    // Fallback: fetch from army_lists via armyListId (covers old saves)
    final listId = widget.gs.armyListId;
    if (listId == null) return;
    try {
      final row = await Supabase.instance.client
        .from('army_lists')
        .select('army_data')
        .eq('id', listId)
        .single();
      final raw = row['army_data'];
      final ad  = raw is String
        ? jsonDecode(raw) as Map<String, dynamic>
        : raw as Map<String, dynamic>? ?? {};
      final img = ad['image_b64'] as String?;
      if (img != null && img.isNotEmpty && mounted) {
        setState(() => _cachedImg = _buildImg(img));
      }
    } catch (_) {}
  }

  Widget? _buildImg(String b64) {
    try { return buildCroppedPhotoDisplay(b64, AppColors.bannerW, AppColors.bannerH); }
    catch (_) { return null; }
  }

  Widget _stat(String value, String label) => SizedBox(
    width: 28,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(value,
        textAlign: TextAlign.center,
        style: GoogleFonts.cinzel(
          color: gold, fontSize: 13, fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()])),
      Text(label,
        textAlign: TextAlign.center,
        style: GoogleFonts.cinzel(
          color: grey.withValues(alpha: 0.55), fontSize: 8, letterSpacing: 0.5)),
    ]));

  Widget _buildUnitsBtn(int count) => GestureDetector(
    onTap: () => setState(() => _unitsExpanded = !_unitsExpanded),
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _unitsHovered = true),
      onExit:  (_) => setState(() => _unitsHovered = false),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 80),
        opacity: _unitsExpanded || _unitsHovered ? 1.0 : 0.55,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$count',
            style: GoogleFonts.cinzel(
              color: gold, fontSize: 13,
              shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])),
          const SizedBox(width: 3),
          Icon(_unitsExpanded ? Icons.group : Icons.group_outlined,
            color: gold, size: 18,
            shadows: const [Shadow(color: Colors.black87, blurRadius: 6)]),
        ]))));

  Widget _buildLoreBtn(bool hasLore) => GestureDetector(
    onTap: hasLore ? () => setState(() => _loreExpanded = !_loreExpanded) : null,
    child: MouseRegion(
      cursor: hasLore ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: hasLore ? (_) => setState(() => _loreHovered = true)  : null,
      onExit:  hasLore ? (_) => setState(() => _loreHovered = false) : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 80),
        opacity: hasLore ? (_loreExpanded || _loreHovered ? 1.0 : 0.55) : 0.2,
        child: Icon(
          _loreExpanded ? Icons.menu_book : Icons.menu_book_outlined,
          color: gold, size: 18,
          shadows: const [Shadow(color: Colors.black87, blurRadius: 6)]))));

  @override
  Widget build(BuildContext context) {
    final gs       = widget.gs;
    final alive    = gs.units.where((u) => !u.isEliminated).toList();
    final alivePts = alive.fold(0, (s, u) => s + u.armyUnit.unit.cost);
    final totalPts = gs.units.fold(0, (s, u) => s + u.armyUnit.unit.cost);
    final aliveAtk = alive.fold(0, (s, u) => s + u.armyUnit.unit.atk);
    final aliveDef = alive.fold(0, (s, u) => s + u.armyUnit.unit.def);
    final aliveRng = alive.fold(0, (s, u) => s + u.armyUnit.unit.rng);
    final aliveMob = alive.fold(0, (s, u) => s + u.armyUnit.unit.mob);
    final aliveCon = alive.fold(0, (s, u) => s + u.currentCon);
    final aliveCP  = alive.fold(0, (s, u) => s + u.armyUnit.unit.cp);
    final hasLore  = gs.armyLore != null && gs.armyLore!.isNotEmpty;
    final bgColor  = gs.armyBgColor != null
      ? AppColors.parseHex(gs.armyBgColor!) : AppColors.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: gold.withValues(alpha: 0.35))),
      child: Container(
        color: bgColor,
        child: Stack(clipBehavior: Clip.hardEdge, children: [

          // Image — pinned to top 115px, full width, slides up when lore opens
          if (_cachedImg != null)
            Positioned(
              top: 0, left: 0, right: 0, height: 115,
              child: ClipRect(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: (_loreExpanded || _unitsExpanded) ? -40.0 : 0.0),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  builder: (_, dy, child) =>
                    Transform.translate(offset: Offset(0, dy), child: child),
                  child: Center(child: _cachedImg!)))),

          // Gradient overlay
          Positioned.fill(child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.4, 1.0],
                  colors: [
                    Colors.black.withValues(alpha: 0.45),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.55),
                  ]))))),

          // Content column
          Column(children: [
            SizedBox(
              height: 115,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top: name left | pts right
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: Text(gs.armyName ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cinzel(
                          color: gold, fontSize: 17, letterSpacing: 2,
                          shadows: const [Shadow(color: Colors.black87, blurRadius: 6)]))),
                      Text('$alivePts / $totalPts pts',
                        style: GoogleFonts.cinzel(
                          color: gold,
                          fontSize: 17,
                          shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])),
                    ]),
                    // Bottom: lore + units icons left | stats right
                    Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      _buildLoreBtn(hasLore),
                      const SizedBox(width: 10),
                      _buildUnitsBtn(widget.gs.units.length),
                      const Spacer(),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        _stat('$aliveCP',  'AP'),
                        _stat('$aliveAtk', 'ATK'),
                        _stat('$aliveDef', 'DEF'),
                        _stat('$aliveRng', 'SHO'),
                        _stat('$aliveMob', 'MOB'),
                        _stat('$aliveCon', 'STR'),
                      ]),
                    ]),
                  ]))),

            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              child: _unitsExpanded && widget.gs.units.isNotEmpty
                ? BannerUnitsPanel(
                    entries: widget.gs.units.map((u) => {
                      'name':  u.armyUnit.customName.isNotEmpty
                        ? u.armyUnit.customName
                        : u.armyUnit.unit.name,
                      'group': u.armyUnit.groupName,
                    }).toList(),
                  )
                : const SizedBox.shrink()),

            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              child: hasLore && _loreExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                    child: Text(gs.armyLore!,
                      style: GoogleFonts.cinzel(
                        color: Colors.white70, fontSize: 13, height: 1.6,
                        fontStyle: FontStyle.italic,
                        shadows: const [Shadow(color: Colors.black87, blurRadius: 8)])))
                : const SizedBox.shrink()),
          ]),
        ])));
  }
}

// ── ROUND SUMMARY ────────────────────────────────────────────────────
class _RoundSummaryContent extends StatelessWidget {
  final GameState gs;
  final GameNotifier game;
  final bool isGM;
  const _RoundSummaryContent({required this.gs, required this.game, required this.isGM});

  List<MapEntry<String, List<GameUnit>>> _grouped(List<GameUnit> units) {
    final order = <String>[''];
    for (final u in units) {
      if (!order.contains(u.groupName)) order.add(u.groupName);
    }
    return [
      for (final g in order)
        if (units.any((u) => u.groupName == g))
          MapEntry(g, units.where((u) => u.groupName == g).toList()),
    ];
  }

  Widget _armyTotalsBar(List<GameUnit> alive) {
    final totalAtk = alive.fold(0, (s, u) => s + u.armyUnit.unit.atk);
    final totalDef = alive.fold(0, (s, u) => s + u.armyUnit.unit.def);
    final totalRng = alive.fold(0, (s, u) => s + u.armyUnit.unit.rng);
    final totalMob = alive.fold(0, (s, u) => s + u.armyUnit.unit.mob);
    final totalCon = alive.fold(0, (s, u) => s + u.currentCon);
    final stats = [
      ('${alive.length}', 'Units'),
      ('$totalAtk', 'ATK'),
      ('$totalDef', 'DEF'),
      ('$totalRng', 'SHO'),
      ('$totalMob', 'MOB'),
      ('$totalCon', 'STR'),
    ];
    return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final s in stats)
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(s.$1,
                style: GoogleFonts.cinzel(
                  color: AppColors.gold,
                  fontSize: 13, fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()])),
              Text(s.$2,
                style: GoogleFonts.cinzel(
                  color: AppColors.grey, fontSize: 8, letterSpacing: 0.5)),
            ]),
        ]);
  }

  Widget _groupHeader(String name) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 3),
    child: Text(name,
      style: GoogleFonts.cinzel(
        color: AppColors.gold.withValues(alpha: 0.7),
        fontSize: 10, letterSpacing: 0.8)),
  );

  Widget _lostStatsRow(int atk, int def, int rng, int mob, int con) {
    final stats = [
      ('ATK', atk), ('DEF', def), ('SHO', rng), ('MOB', mob), ('STR', con),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [
        for (final s in stats)
          RichText(text: TextSpan(
            style: GoogleFonts.cinzel(fontSize: 10),
            children: [
              TextSpan(text: '${s.$1} ', style: const TextStyle(color: AppColors.grey)),
              TextSpan(text: '-${s.$2}',
                style: const TextStyle(color: Colors.red,
                  fontWeight: FontWeight.w600)),
            ])),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final alive           = gs.units.where((u) => !u.isEliminated).toList();
    final fallenThisRound = gs.units
      .where((u) => u.isEliminated && u.eliminatedOnRound == gs.round)
      .toList();
    final activatedCount  = alive.where((u) => u.activated).length;
    final cpSpent         = gs.initialCP - gs.commandPoints;

    final aliveGroups  = _grouped(alive);
    final fallenGroups = _grouped(fallenThisRound);

    final rolls = gs.roundDiceRolls;
    final avgRoll = rolls.isEmpty
      ? null
      : (rolls.reduce((a, b) => a + b) / rolls.length);

    int lostAtk = 0, lostDef = 0, lostRng = 0, lostMob = 0, lostCon = 0;
    for (final u in fallenThisRound) {
      lostAtk += u.armyUnit.unit.atk;
      lostDef += u.armyUnit.unit.def;
      lostRng += u.armyUnit.unit.rng;
      lostMob += u.armyUnit.unit.mob;
      lostCon += u.armyUnit.unit.con;
    }

    return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Army totals bar ──
            _armyTotalsBar(alive),
            const SizedBox(height: 12),
            Divider(color: AppColors.gold.withValues(alpha: 0.22), height: 1),
            const SizedBox(height: 10),
            // ── Stats chips ──
            Wrap(spacing: 8, runSpacing: 6, children: [
              _statChip(Icons.check_circle_outline,
                '$activatedCount / ${alive.length}', 'Activated', AppColors.gold),
              _statChip(Icons.flash_on,
                '$cpSpent', 'CP Spent', const Color(0xFFC8A0E0)),
              if (avgRoll != null)
                _statChip(Icons.casino_outlined,
                  avgRoll.toStringAsFixed(1), 'Avg Roll (${rolls.length}×)',
                  const Color(0xFF7ABFD4)),
            ]),
            const SizedBox(height: 12),
            Divider(color: AppColors.gold.withValues(alpha: 0.22), height: 1),
            const SizedBox(height: 4),
            // ── Alive units by group ──
            for (final entry in aliveGroups) ...[
              if (entry.key.isNotEmpty) _groupHeader(entry.key),
              ...entry.value.map(_unitRow),
            ],
            // ── Units fallen this round by group ──
            if (fallenThisRound.isNotEmpty) ...[
              const SizedBox(height: 6),
              Divider(color: Colors.red.withValues(alpha: 0.25), height: 1),
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 6),
                child: _lostStatsRow(lostAtk, lostDef, lostRng, lostMob, lostCon),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('Fallen this round',
                  style: GoogleFonts.cinzel(
                    color: AppColors.grey, fontSize: 9)),
              ),
              for (final entry in fallenGroups) ...[
                if (entry.key.isNotEmpty) _groupHeader(entry.key),
                ...entry.value.map(_unitRow),
              ],
            ],
            // ── GM: enemy alive selector ──
            if (isGM) ...[
              const SizedBox(height: 12),
              Divider(color: AppColors.gold.withValues(alpha: 0.22), height: 1),
              const SizedBox(height: 10),
              Text('Enemy units still alive:',
                style: GoogleFonts.cinzel(
                  color: AppColors.grey, fontSize: 12, height: 1.5)),
              const SizedBox(height: 8),
              _EnemyAliveSelector(game: game, gs: gs),
            ],
          ],
    );
  }

  Widget _statChip(IconData icon, String value, String label, Color color) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5)),
        color: color.withValues(alpha: 0.10),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(value, style: GoogleFonts.cinzel(
            color: AppColors.textLight, fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.cinzel(
          color: AppColors.grey, fontSize: 9)),
      ]),
    );

  Widget _unitRow(GameUnit u) {
    final maxCon   = u.armyUnit.unit.con;
    final pct      = maxCon > 0 ? u.currentCon / maxCon : 0.0;
    final conColor = pct > 0.5
      ? const Color(0xFFA8C070)
      : pct > 0.25 ? const Color(0xFFD4A870) : Colors.red;
    final isElim   = u.isEliminated;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Icon(
          isElim
            ? Icons.cancel_outlined
            : u.activated ? Icons.check_circle_outline : Icons.radio_button_unchecked,
          size: 14,
          color: isElim
            ? Colors.red
            : u.activated
              ? AppColors.gold.withValues(alpha: 0.9)
              : AppColors.greyLight.withValues(alpha: 0.4),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Expanded(
                  child: Text(u.displayName,
                    style: GoogleFonts.cinzel(
                      color: isElim
                        ? AppColors.grey
                        : u.activated ? AppColors.textLight : AppColors.grey,
                      fontSize: 11,
                      decoration: isElim ? TextDecoration.lineThrough : null,
                      decorationColor: AppColors.grey,
                    ),
                    overflow: TextOverflow.ellipsis),
                ),
                if (isElim)
                  Text('Fallen',
                    style: GoogleFonts.cinzel(
                      color: Colors.red, fontSize: 9)),
              ]),
              if (!isElim) ...[
                const SizedBox(height: 4),
                Row(children: [
                  SizedBox(
                    width: 80, height: 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: pct.toDouble(),
                        backgroundColor: AppColors.greyLight.withValues(alpha: 0.2),
                        valueColor: AlwaysStoppedAnimation(conColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${u.currentCon}/$maxCon',
                    style: GoogleFonts.cinzel(color: conColor, fontSize: 9)),
                ]),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}

class _GamePhotoIcon extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  const _GamePhotoIcon({required this.icon, required this.onTap, this.color = AppColors.gold});
  @override State<_GamePhotoIcon> createState() => _GamePhotoIconState();
}
class _GamePhotoIconState extends State<_GamePhotoIcon> {
  bool _hovered = false;
  @override Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit:  (_) => setState(() => _hovered = false),
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 80),
        opacity: _hovered ? 1.0 : 0.45,
        child: Icon(widget.icon, color: widget.color, size: 20))));
}

// ── End-game summary content ──────────────────────────────────────────────
class _EndGameContent extends StatelessWidget {
  final GameState gs;
  const _EndGameContent({required this.gs});

  @override
  Widget build(BuildContext context) {
    final eliminated = gs.units.where((u) => u.isEliminated).toList();
    final alive      = gs.units.where((u) => !u.isEliminated).toList();
    final totalSTR   = gs.units.fold(0, (s, u) => s + u.armyUnit.unit.con);
    final lostSTR    = gs.units.fold(0, (s, u) => s + (u.armyUnit.unit.con - u.currentCon));
    final cpSpent    = gs.initialCP - gs.commandPoints;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Stats tiles
      Row(children: [
        _StatTile('Round',     '${gs.round}'),
        _StatTile('Surviving', '${alive.length} / ${gs.units.length}'),
        _StatTile('STR Lost',  '$lostSTR / $totalSTR'),
        _StatTile('AP Spent',  '$cpSpent'),
      ]),

      // Eliminated units list
      if (eliminated.isNotEmpty) ...[
        const SizedBox(height: 24),
        Text('ELIMINATED',
          style: GoogleFonts.cinzel(
            color: AppColors.gold.withValues(alpha: 0.6),
            fontSize: 10, letterSpacing: 2)),
        const SizedBox(height: 10),
        ...eliminated.map((u) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(
              color: AppColors.gold.withValues(alpha: 0.12))),
          child: Row(children: [
            Expanded(child: Text(u.displayName,
              style: GoogleFonts.cinzel(
                color: Colors.white60, fontSize: 13))),
            if (u.eliminatedOnRound != null)
              Text('Round ${u.eliminatedOnRound}',
                style: GoogleFonts.cinzel(
                  color: AppColors.grey.withValues(alpha: 0.55),
                  fontSize: 11)),
          ]))),
      ],

      // Alive units — STR remaining
      if (alive.isNotEmpty) ...[
        const SizedBox(height: 24),
        Text('SURVIVING',
          style: GoogleFonts.cinzel(
            color: AppColors.gold.withValues(alpha: 0.6),
            fontSize: 10, letterSpacing: 2)),
        const SizedBox(height: 10),
        ...alive.map((u) {
          final maxCon = u.armyUnit.unit.con;
          final frac   = maxCon > 0 ? u.currentCon / maxCon : 1.0;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              border: Border.all(
                color: AppColors.gold.withValues(alpha: 0.12))),
            child: Row(children: [
              Expanded(child: Text(u.displayName,
                style: GoogleFonts.cinzel(
                  color: Colors.white70, fontSize: 13))),
              Text('${u.currentCon}/$maxCon STR',
                style: GoogleFonts.cinzel(
                  color: frac < 0.4
                    ? const Color(0xFFCC4444)
                    : AppColors.gold.withValues(alpha: 0.7),
                  fontSize: 11)),
            ]));
        }),
      ],
    ]);
  }
}

class _StatTile extends StatelessWidget {
  final String label, value;
  const _StatTile(this.label, this.value);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.2))),
      child: Column(children: [
        Text(value,
          style: GoogleFonts.cinzel(
            color: AppColors.gold, fontSize: 20,
            fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(label,
          style: GoogleFonts.cinzel(
            color: AppColors.grey, fontSize: 9, letterSpacing: 1)),
      ])));
}

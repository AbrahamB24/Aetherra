import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_theme.dart';
import '../game/models/game_state.dart';
import '../game/online/online_game_manager.dart';
import '../widgets/aetherra_dialog.dart';
import '../widgets/nav_btn.dart';

class OnlineGameScreen extends StatefulWidget {
  final OnlineGameManager manager;
  const OnlineGameScreen({super.key, required this.manager});
  @override State<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends State<OnlineGameScreen> {
  static const gold = AppColors.gold;
  static const grey = AppColors.grey;
  static const dark = AppColors.dark;

  bool _reactiveDialogShown  = false;
  bool _nextRoundDialogShown = false;
  bool _opponentPanelOpen    = false;
  bool _waitingForConfirm    = false;

  @override
  void initState() {
    super.initState();
    widget.manager.addListener(_onManagerChange);
  }

  @override
  void dispose() {
    widget.manager.removeListener(_onManagerChange);
    super.dispose();
  }

  void _onManagerChange() {
    if (!mounted) return;
    final m = widget.manager;

    // Reactive activation popup: only shown to the awaiting player
    final isAwaitingReactive = m.pendingType == OnlinePendingType.reactive &&
        m.pendingData?['awaitingPlayer'] == m.myRole?.name;
    if (isAwaitingReactive && !_reactiveDialogShown) {
      _reactiveDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showReactiveDialog();
      });
    }
    if (!isAwaitingReactive) _reactiveDialogShown = false;

    // Next-round confirmation popup: only shown to the non-requesting player
    final isAwaitingNextRound = m.pendingType == OnlinePendingType.nextRound &&
        m.pendingFrom != m.myRole?.name;
    if (isAwaitingNextRound && !_nextRoundDialogShown) {
      _nextRoundDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showNextRoundConfirmDialog();
      });
    }
    if (!isAwaitingNextRound) _nextRoundDialogShown = false;

    // Reset "waiting for confirm" flag once round advances
    if (_waitingForConfirm && m.pendingType == null) {
      _waitingForConfirm = false;
    }

    setState(() {});
  }

  // ── Reactive activation popup ─────────────────────────────────────────────
  void _showReactiveDialog() {
    final m = widget.manager;
    final drawingPlayer = m.pendingData?['fromPlayer'] == OnlineRole.host.name
        ? m.opponentArmyName : m.myArmyName;
    showAetherraDialogRaw<void>(context, aetherraDialogContainer(
      title: 'Reactive Activation',
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          '$drawingPlayer activated a unit.',
          style: GoogleFonts.cinzel(color: grey, fontSize: 13, height: 1.5)),
        const SizedBox(height: 8),
        Text(
          'Spend 1 AP to react?\nYou will draw your token immediately — no popup for your opponent.',
          style: GoogleFonts.cinzel(color: grey.withValues(alpha: 0.7),
              fontSize: 12, height: 1.6)),
        const SizedBox(height: 8),
        Text(
          'Your AP: ${m.myCP}',
          style: GoogleFonts.cinzel(
              color: m.myCP > 0 ? gold : Colors.red.shade400, fontSize: 13)),
      ]),
      actions: [
        aDialogBtn('No', grey, () {
          Navigator.pop(context);
          m.respondReactive(false);
        }),
        aDialogBtn('Yes (−1 AP)', gold, m.myCP > 0 ? () {
          Navigator.pop(context);
          m.respondReactive(true);
        } : null),
      ]));
  }

  // ── Next-round bottom sheet (requesting player) ───────────────────────────
  void _showNextRoundSheet() {
    final m = widget.manager;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: dark,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (_, scroll) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: grey.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            Text('Round ${m.round} – Summary',
                style: GoogleFonts.cinzel(color: gold, fontSize: 17)),
            const SizedBox(height: 16),
            Expanded(child: SingleChildScrollView(
                controller: scroll,
                child: _RoundSummary(manager: m))),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                    foregroundColor: grey,
                    side: BorderSide(color: grey.withValues(alpha: 0.4)),
                    shape: const RoundedRectangleBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text('Cancel',
                    style: GoogleFonts.cinzel(fontSize: 14)))),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  setState(() => _waitingForConfirm = true);
                  await m.requestNextRound();
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: gold,
                    foregroundColor: dark,
                    shape: const RoundedRectangleBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text('Request Next Round',
                    style: GoogleFonts.cinzel(
                        fontSize: 13, fontWeight: FontWeight.w600)))),
            ]),
          ]))));
  }

  // ── Next-round confirmation popup (opponent) ──────────────────────────────
  void _showNextRoundConfirmDialog() {
    final m = widget.manager;
    final who = m.pendingFrom == OnlineRole.host.name
        ? m.opponentArmyName : m.myArmyName;
    showAetherraDialogRaw<void>(context, aetherraDialogContainer(
      title: 'Next Round?',
      content: Text(
        '$who wants to start Round ${m.round + 1}.\nAre you ready?',
        style: GoogleFonts.cinzel(color: grey, fontSize: 13, height: 1.6)),
      actions: [
        aDialogBtn('Not yet', grey, () => Navigator.pop(context)),
        aDialogBtn('Confirm', gold, () {
          Navigator.pop(context);
          m.confirmNextRound();
        }),
      ]));
  }

  // ── Leave confirmation ────────────────────────────────────────────────────
  void _confirmLeave() {
    showAetherraDialogRaw<void>(context, aetherraDialogContainer(
      title: 'Leave Battle?',
      content: Text(
        'Leaving will end the game for both players.',
        style: GoogleFonts.cinzel(color: grey, fontSize: 13, height: 1.5)),
      actions: [
        aDialogBtn('Cancel', grey, () => Navigator.pop(context)),
        aDialogBtn('Leave', Colors.red.shade400, () async {
          Navigator.pop(context);
          await widget.manager.leaveGame();
          if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
        }),
      ]));
  }

  // ── Main build ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final m   = widget.manager;
    final bag = m.myPerspectiveBag;
    final myColor = AppColors.parseHex(m.myPlayerColor);
    return Scaffold(
      backgroundColor: dark,
      appBar: AppBar(
        backgroundColor: dark,
        leadingWidth: 48,
        leading: NavBtn(icon: Icons.exit_to_app_outlined, onPressed: _confirmLeave),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('Round ${m.round}',
              style: GoogleFonts.cinzel(color: gold, fontSize: 14)),
          const SizedBox(width: 10),
          Container(
              width: 1, height: 14,
              color: gold.withValues(alpha: 0.3)),
          const SizedBox(width: 10),
          Text(m.roomCode ?? '------',
              style: GoogleFonts.cinzel(
                  color: gold.withValues(alpha: 0.55), fontSize: 12,
                  letterSpacing: 2)),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _ConnectionDot(connected: m.opponentConnected, active: m.gameActive)),
        ],
      ),
      body: Column(children: [
        // Connection warning
        if (!m.opponentConnected && m.gameActive)
          Container(
            color: Colors.orange.withValues(alpha: 0.15),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              const Icon(Icons.wifi_off, color: Colors.orange, size: 14),
              const SizedBox(width: 8),
              Text('Opponent disconnected – waiting for reconnect…',
                  style: GoogleFonts.cinzel(
                      color: Colors.orange, fontSize: 11)),
            ])),

        // Waiting for opponent (host before guest joins)
        if (!m.gameActive)
          Expanded(child: Center(child: Column(
              mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(
                strokeWidth: 1.5, color: gold.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('Waiting for opponent…',
                style: GoogleFonts.cinzel(color: grey, fontSize: 13)),
            const SizedBox(height: 8),
            Text(m.roomCode ?? '',
                style: GoogleFonts.cinzel(
                    color: gold, fontSize: 22,
                    fontWeight: FontWeight.w700, letterSpacing: 6)),
          ]))),

        if (m.gameActive) ...[
          // ── Header bar: AP + Dice + Next Round ─────────────────────
          _HeaderBar(
            manager:          m,
            waitingForConfirm: _waitingForConfirm,
            onNextRound:       _showNextRoundSheet,
          ),

          // ── My unit list ────────────────────────────────────────────
          Expanded(child: Stack(children: [
            ListView.builder(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              itemCount: _groups(m).length,
              itemBuilder: (_, i) {
                final entry  = _groups(m)[i];
                final gName  = entry.key;
                final units  = entry.value;
                final isElim = gName == '__eliminated__';
                return _GroupSection(
                    key:       ValueKey(gName),
                    groupName: gName,
                    units:     units,
                    isElim:    isElim,
                    manager:   m,
                    myColor:   myColor,
                    topMargin: i > 0 ? 10.0 : 0.0);
              }),
            // Fade edges
            const Positioned(top: 0, left: 0, right: 0, height: 28,
                child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [AppColors.dark, Colors.transparent]))))),
            const Positioned(bottom: 0, left: 0, right: 0, height: 28,
                child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.bottomCenter, end: Alignment.topCenter,
                        colors: [AppColors.dark, Colors.transparent]))))),
          ])),

          // ── Token bag ───────────────────────────────────────────────
          _OnlineTokenBag(manager: m, bag: bag),

          // ── Opponent panel ──────────────────────────────────────────
          _OpponentPanel(
            manager:  m,
            expanded: _opponentPanelOpen,
            onToggle: () => setState(() => _opponentPanelOpen = !_opponentPanelOpen)),

          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ]));
  }

  List<MapEntry<String, List<GameUnit>>> _groups(OnlineGameManager m) {
    final alive = m.myUnits.where((u) => !u.isEliminated).toList();
    final dead  = m.myUnits.where((u) =>  u.isEliminated).toList();
    final order = <String>[''];
    for (final u in alive) {
      if (!order.contains(u.groupName)) order.add(u.groupName);
    }
    final res = <MapEntry<String, List<GameUnit>>>[];
    for (final g in order) {
      final members = alive.where((u) => u.groupName == g).toList();
      if (members.isNotEmpty) res.add(MapEntry(g, members));
    }
    if (dead.isNotEmpty) res.add(MapEntry('__eliminated__', dead));
    return res;
  }
}

// ── Header bar (AP + Dice + Next Round) ───────────────────────────────────────
class _HeaderBar extends StatelessWidget {
  final OnlineGameManager manager;
  final bool waitingForConfirm;
  final VoidCallback onNextRound;
  const _HeaderBar({
    required this.manager,
    required this.waitingForConfirm,
    required this.onNextRound,
  });

  @override
  Widget build(BuildContext context) {
    final m    = manager;
    final gold = AppColors.gold;
    final grey = AppColors.grey;
    return Container(
      height: 64,
      color: AppColors.dark,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // AP
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
              border: Border.all(color: gold.withValues(alpha: 0.3))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _SmBtn(Icons.remove, () => m.adjustCP(-1),
                enabled: m.myCP > 0),
            const SizedBox(width: 6),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${m.myCP}',
                  style: GoogleFonts.cinzel(
                      color: gold, fontSize: 16,
                      fontWeight: FontWeight.w700)),
              Text('AP', style: GoogleFonts.cinzel(
                  color: grey.withValues(alpha: 0.55),
                  fontSize: 9, letterSpacing: 1)),
            ]),
            const SizedBox(width: 6),
            _SmBtn(Icons.add, () => m.adjustCP(1),
                enabled: m.myCP < m.myInitialCP),
          ])),
        const Spacer(),
        // Dice
        const _DiceBtn(),
        const Spacer(),
        // Next Round
        SizedBox(width: 110, child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 34, child: ElevatedButton(
                onPressed: waitingForConfirm ? null : onNextRound,
                style: ElevatedButton.styleFrom(
                    backgroundColor: waitingForConfirm
                        ? grey.withValues(alpha: 0.2)
                        : gold.withValues(alpha: 0.15),
                    foregroundColor: gold,
                    elevation: 0,
                    shape: const RoundedRectangleBorder(),
                    padding: EdgeInsets.zero,
                    side: BorderSide(
                        color: waitingForConfirm
                            ? grey.withValues(alpha: 0.2)
                            : gold.withValues(alpha: 0.4))),
                child: Text(
                    waitingForConfirm ? 'Waiting…' : 'Next Round',
                    style: GoogleFonts.cinzel(
                        fontSize: 10, fontWeight: FontWeight.w600,
                        letterSpacing: 0.3)))),
            ])),
      ]));
  }
}

class _SmBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool enabled;
  const _SmBtn(this.icon, this.onTap, {this.enabled = true});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: Icon(icon,
        color: enabled
            ? AppColors.gold.withValues(alpha: 0.8)
            : AppColors.grey.withValues(alpha: 0.3),
        size: 16));
}

// ── Dice button ───────────────────────────────────────────────────────────────
class _DiceBtn extends StatefulWidget {
  const _DiceBtn();
  @override State<_DiceBtn> createState() => _DiceBtnState();
}

class _DiceBtnState extends State<_DiceBtn>
    with SingleTickerProviderStateMixin {
  static final _rng = math.Random();
  List<int> _rolls  = [];
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;

  @override void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  void _roll(int count) {
    setState(() => _rolls = List.generate(count, (_) => _rng.nextInt(6) + 1));
    _ctrl.forward(from: 0);
  }

  String get _diceLabel {
    if (_rolls.isEmpty) return '⚄';
    return _rolls.map((r) => _dieFace(r)).join(' ');
  }

  String _dieFace(int v) {
    const faces = ['⚀','⚁','⚂','⚃','⚄','⚅'];
    return faces[v - 1];
  }

  @override
  Widget build(BuildContext context) {
    final gold = AppColors.gold;
    final grey = AppColors.grey;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ScaleTransition(
        scale: Tween(begin: 0.8, end: 1.0).animate(_anim),
        child: GestureDetector(
          onTap: () => _roll(1),
          onLongPress: () => _showCountPicker(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                border: Border.all(color: gold.withValues(alpha: 0.3))),
            child: Text(_diceLabel,
                style: TextStyle(
                    fontSize: _rolls.isEmpty ? 20 : 16,
                    color: _rolls.isEmpty
                        ? grey.withValues(alpha: 0.5) : gold))))),
      if (_rolls.isNotEmpty) Text(
          'Σ ${_rolls.fold(0, (a, b) => a + b)}',
          style: GoogleFonts.cinzel(
              color: grey, fontSize: 9, letterSpacing: 0.5)),
    ]);
  }

  void _showCountPicker(BuildContext context) {
    showModalBottomSheet<int>(
        context: context,
        backgroundColor: AppColors.dark,
        builder: (_) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Roll how many dice?',
                style: GoogleFonts.cinzel(
                    color: AppColors.gold, fontSize: 14)),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              for (final n in [1, 2, 3, 4, 5, 6])
                GestureDetector(
                  onTap: () { Navigator.pop(context); _roll(n); },
                  child: Container(
                    width: 44, height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        border: Border.all(
                            color: AppColors.gold.withValues(alpha: 0.4))),
                    child: Text('$n',
                        style: GoogleFonts.cinzel(
                            color: AppColors.gold, fontSize: 16)))),
            ]),
            const SizedBox(height: 8),
          ])));
  }
}

// ── Online token bag ──────────────────────────────────────────────────────────
class _OnlineTokenBag extends StatelessWidget {
  final OnlineGameManager manager;
  final TokenBag bag;
  const _OnlineTokenBag({required this.manager, required this.bag});

  @override
  Widget build(BuildContext context) {
    final m         = manager;
    final gold      = AppColors.gold;
    final grey      = AppColors.grey;
    final canDraw   = m.canDraw;
    final last      = bag.lastDrawn;
    final isPending = m.pendingType != null;
    final myColor   = AppColors.parseHex(m.myPlayerColor);
    final oppColor  = AppColors.parseHex(m.opponentPlayerColor);

    // Status text
    String statusText;
    if (!m.gameActive) {
      statusText = 'Waiting for opponent…';
    } else if (isPending && m.pendingType == OnlinePendingType.reactive) {
      if (m.pendingData?['awaitingPlayer'] == m.myRole?.name) {
        statusText = 'Reactive activation offer…';
      } else {
        statusText = 'Waiting for opponent to decide…';
      }
    } else if (isPending && m.pendingType == OnlinePendingType.nextRound) {
      statusText = 'Waiting for next-round confirmation…';
    } else if (m.activePlayer == null) {
      statusText = 'First draw – either player may start';
    } else if (canDraw) {
      statusText = 'Your turn to draw';
    } else {
      statusText = 'Waiting for opponent to draw…';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          border: Border.all(color: gold.withValues(alpha: 0.25))),
      child: Row(children: [
        // Last drawn indicator
        if (last != null) ...[
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: last.color == 'player' ? myColor : oppColor)),
          const SizedBox(width: 6),
          Text(
              last.color == 'player' ? 'Yours' : 'Opponent',
              style: GoogleFonts.cinzel(
                  color: last.color == 'player' ? myColor : oppColor,
                  fontSize: 11)),
          const SizedBox(width: 8),
          Container(width: 1, height: 12, color: gold.withValues(alpha: 0.2)),
          const SizedBox(width: 8),
        ],
        // Status text
        Expanded(child: Text(statusText,
            style: GoogleFonts.cinzel(
                color: grey.withValues(alpha: 0.6), fontSize: 11))),
        const SizedBox(width: 8),
        // Bag count
        Text('${bag.bagCount}',
            style: GoogleFonts.cinzel(
                color: grey.withValues(alpha: 0.5), fontSize: 11)),
        const SizedBox(width: 12),
        // Draw Token button
        SizedBox(
          height: 36,
          child: ElevatedButton(
            onPressed: canDraw ? () => m.drawToken() : null,
            style: ElevatedButton.styleFrom(
                backgroundColor: canDraw
                    ? gold : grey.withValues(alpha: 0.1),
                foregroundColor: canDraw ? AppColors.dark : grey,
                elevation: 0,
                shape: const RoundedRectangleBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 14)),
            child: Text('Draw Token',
                style: GoogleFonts.cinzel(
                    fontSize: 11,
                    fontWeight: canDraw ? FontWeight.w700 : FontWeight.normal)))),
      ]));
  }
}

// ── Opponent panel ────────────────────────────────────────────────────────────
class _OpponentPanel extends StatelessWidget {
  final OnlineGameManager manager;
  final bool expanded;
  final VoidCallback onToggle;
  const _OpponentPanel({
      required this.manager, required this.expanded, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final m      = manager;
    final gold   = AppColors.gold;
    final grey   = AppColors.grey;
    final oppCol = AppColors.parseHex(m.opponentPlayerColor);
    final alive  = m.opponentUnits.where((u) => !u.isEliminated).length;
    final total  = m.opponentUnits.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      decoration: BoxDecoration(
          border: Border.all(color: gold.withValues(alpha: 0.15))),
      child: Column(children: [
        // Header (always visible)
        GestureDetector(
          onTap: onToggle,
          child: Container(
            color: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, color: oppCol)),
              const SizedBox(width: 8),
              Expanded(child: Text(
                  m.opponentArmyName.isEmpty ? 'Opponent' : m.opponentArmyName,
                  style: GoogleFonts.cinzel(
                      color: grey.withValues(alpha: 0.7), fontSize: 12))),
              Text('$alive/$total',
                  style: GoogleFonts.cinzel(
                      color: grey.withValues(alpha: 0.5), fontSize: 11)),
              const SizedBox(width: 6),
              Text('AP: ${m.opponentCP}',
                  style: GoogleFonts.cinzel(
                      color: grey.withValues(alpha: 0.5), fontSize: 11)),
              const SizedBox(width: 8),
              Icon(
                  expanded ? Icons.expand_more : Icons.chevron_right,
                  color: grey.withValues(alpha: 0.4), size: 16),
            ])),
        ),
        // Expanded unit list
        if (expanded) Container(
          constraints: const BoxConstraints(maxHeight: 200),
          child: m.opponentUnits.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('No unit data yet.',
                      style: GoogleFonts.cinzel(
                          color: grey.withValues(alpha: 0.4), fontSize: 11)))
              : ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  itemCount: m.opponentUnits.length,
                  itemBuilder: (_, i) =>
                      _OpponentUnitRow(unit: m.opponentUnits[i], color: oppCol))),
      ]));
  }
}

class _OpponentUnitRow extends StatelessWidget {
  final GameUnit unit;
  final Color color;
  const _OpponentUnitRow({required this.unit, required this.color});

  @override
  Widget build(BuildContext context) {
    final grey = AppColors.grey;
    final isDead = unit.isEliminated;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
          color: isDead
              ? Colors.transparent
              : color.withValues(alpha: 0.05),
          border: Border.all(
              color: isDead
                  ? grey.withValues(alpha: 0.08)
                  : color.withValues(alpha: 0.2))),
      child: Row(children: [
        // Activation indicator
        Container(
          width: 6, height: 6,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDead
                  ? Colors.transparent
                  : (unit.activated
                      ? color.withValues(alpha: 0.9)
                      : color.withValues(alpha: 0.25)))),
        // Name
        Expanded(child: Text(unit.displayName,
            style: GoogleFonts.cinzel(
                color: isDead
                    ? grey.withValues(alpha: 0.3)
                    : grey.withValues(alpha: 0.7),
                fontSize: 11,
                decoration: isDead ? TextDecoration.lineThrough : null))),
        // CON
        Text(isDead ? 'Elim.' : '${unit.currentCon}/${unit.armyUnit.unit.con}',
            style: GoogleFonts.cinzel(
                color: isDead
                    ? Colors.red.shade400.withValues(alpha: 0.5)
                    : grey.withValues(alpha: 0.5),
                fontSize: 10)),
      ]));
  }
}

// ── Group section ─────────────────────────────────────────────────────────────
class _GroupSection extends StatefulWidget {
  final String groupName;
  final List<GameUnit> units;
  final bool isElim;
  final OnlineGameManager manager;
  final Color myColor;
  final double topMargin;
  const _GroupSection({
    super.key,
    required this.groupName,
    required this.units,
    required this.isElim,
    required this.manager,
    required this.myColor,
    required this.topMargin,
  });
  @override State<_GroupSection> createState() => _GroupSectionState();
}

class _GroupSectionState extends State<_GroupSection> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final grey = AppColors.grey;
    final hasGroup = widget.groupName.isNotEmpty && !widget.isElim;

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.topMargin > 0) SizedBox(height: widget.topMargin),
      // Group header
      if (hasGroup || widget.isElim)
        GestureDetector(
          onTap: () => setState(() => _collapsed = !_collapsed),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Row(children: [
              Icon(
                  _collapsed ? Icons.chevron_right : Icons.expand_more,
                  color: grey.withValues(alpha: 0.4), size: 16),
              const SizedBox(width: 4),
              Expanded(child: Text(
                  widget.isElim ? 'Eliminated' : widget.groupName,
                  style: GoogleFonts.cinzel(
                      color: widget.isElim
                          ? Colors.red.shade400.withValues(alpha: 0.6)
                          : grey.withValues(alpha: 0.5),
                      fontSize: 10, letterSpacing: 1))),
              Text('${widget.units.length}',
                  style: GoogleFonts.cinzel(
                      color: grey.withValues(alpha: 0.35), fontSize: 10)),
            ]))),

      if (!_collapsed)
        ...widget.units.map((u) => _OnlineUnitCard(
            key:     ValueKey(u.instanceId),
            unit:    u,
            manager: widget.manager,
            color:   widget.myColor,
            isElim:  widget.isElim)),
    ]);
  }
}

// ── Online unit card (my units, interactive) ──────────────────────────────────
class _OnlineUnitCard extends StatefulWidget {
  final GameUnit unit;
  final OnlineGameManager manager;
  final Color color;
  final bool isElim;
  const _OnlineUnitCard({
    super.key,
    required this.unit,
    required this.manager,
    required this.color,
    required this.isElim,
  });
  @override State<_OnlineUnitCard> createState() => _OnlineUnitCardState();
}

class _OnlineUnitCardState extends State<_OnlineUnitCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final u    = widget.unit;
    final m    = widget.manager;
    final col  = widget.color;
    final grey = AppColors.grey;
    final isDead = u.isEliminated;

    final bgCol = u.armyUnit.bgColor != null
        ? AppColors.parseHex(u.armyUnit.bgColor!)
        : const Color(0xFF0D0B09);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
          color: isDead ? Colors.transparent : bgCol,
          border: Border.all(
              color: isDead
                  ? grey.withValues(alpha: 0.1)
                  : (u.activated
                      ? col.withValues(alpha: 0.6)
                      : col.withValues(alpha: 0.2)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Main row ──────────────────────────────────────────────────
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          // Color strip
          Container(
              width: 4,
              height: isDead ? 36 : (_expanded ? null : 48),
              constraints: isDead
                  ? null : BoxConstraints(minHeight: _expanded ? 60 : 48),
              color: isDead ? Colors.transparent : col.withValues(alpha: 0.6)),

          // Photo / icon
          if (u.armyUnit.photoBase64 != null) ...[
            const SizedBox(width: 8),
            ClipRect(child: SizedBox(
                width: 40, height: 40,
                child: Image.memory(
                    base64Decode(u.armyUnit.photoBase64!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Icon(Icons.shield_outlined, color: col, size: 20)))),
          ] else ...[
            const SizedBox(width: 8),
            SizedBox(width: 40, height: 40,
                child: Center(child: Icon(
                    isDead ? Icons.close : Icons.shield_outlined,
                    color: isDead
                        ? Colors.red.shade400.withValues(alpha: 0.35)
                        : col.withValues(alpha: 0.35),
                    size: 20))),
          ],
          const SizedBox(width: 10),

          // Name + stats
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, children: [
            Text(u.displayName,
                style: GoogleFonts.cinzel(
                    color: isDead
                        ? grey.withValues(alpha: 0.35)
                        : grey.withValues(alpha: 0.9),
                    fontSize: 12,
                    decoration: isDead ? TextDecoration.lineThrough : null)),
            if (!isDead) Text(
                'ATK:${u.armyUnit.unit.atk} DEF:${u.armyUnit.unit.def}'
                ' MOB:${u.armyUnit.unit.mob}',
                style: GoogleFonts.cinzel(
                    color: grey.withValues(alpha: 0.35), fontSize: 9)),
          ])),
          const SizedBox(width: 8),

          // Controls (only for alive units)
          if (!isDead) ...[
            // Activate toggle
            GestureDetector(
              onTap: () => u.activated
                  ? m.deactivateUnit(u.instanceId)
                  : m.activateUnit(u.instanceId),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: u.activated
                        ? col.withValues(alpha: 0.2) : Colors.transparent,
                    border: Border.all(
                        color: u.activated
                            ? col.withValues(alpha: 0.8)
                            : col.withValues(alpha: 0.3))),
                child: Text(
                    u.activated ? 'Active' : 'Activate',
                    style: GoogleFonts.cinzel(
                        color: u.activated ? col : col.withValues(alpha: 0.5),
                        fontSize: 9,
                        fontWeight: u.activated
                            ? FontWeight.w700 : FontWeight.normal)))),
            const SizedBox(width: 6),

            // CON tracker
            Row(mainAxisSize: MainAxisSize.min, children: [
              _ConBtn(Icons.remove, () => m.adjustCon(u.instanceId, -1),
                  enabled: u.currentCon > 0),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text('${u.currentCon}/${u.armyUnit.unit.con}',
                    style: GoogleFonts.cinzel(
                        color: u.currentCon <= (u.armyUnit.unit.con * 0.33).ceil()
                            ? Colors.red.shade400
                            : grey,
                        fontSize: 11,
                        fontWeight: FontWeight.w600))),
              _ConBtn(Icons.add, () => m.adjustCon(u.instanceId, 1),
                  enabled: u.currentCon < u.armyUnit.unit.con),
            ]),
            const SizedBox(width: 6),

            // Expand toggle
            if (u.armyUnit.unit.abilities.isNotEmpty)
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: grey.withValues(alpha: 0.35), size: 16)),
          ] else ...[
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text('Elim R${u.eliminatedOnRound ?? '?'}',
                  style: GoogleFonts.cinzel(
                      color: Colors.red.shade400.withValues(alpha: 0.45),
                      fontSize: 9))),
          ],
          const SizedBox(width: 6),
        ]),

        // ── Abilities row ────────────────────────────────────────────
        if (!isDead && _expanded && u.armyUnit.unit.abilities.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 8, 8),
            child: Wrap(spacing: 6, runSpacing: 4,
                children: u.armyUnit.unit.abilities.map((ab) =>
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          border: Border.all(
                              color: col.withValues(alpha: 0.25))),
                      child: Text(ab,
                          style: GoogleFonts.cinzel(
                              color: col.withValues(alpha: 0.6),
                              fontSize: 9)))).toList())),
      ]));
  }
}

class _ConBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool enabled;
  const _ConBtn(this.icon, this.onTap, {required this.enabled});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: Container(
      width: 22, height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          border: Border.all(
              color: enabled
                  ? AppColors.gold.withValues(alpha: 0.35)
                  : AppColors.grey.withValues(alpha: 0.1))),
      child: Icon(icon,
          color: enabled
              ? AppColors.gold.withValues(alpha: 0.8)
              : AppColors.grey.withValues(alpha: 0.2),
          size: 12)));
}

// ── Round summary content ─────────────────────────────────────────────────────
class _RoundSummary extends StatelessWidget {
  final OnlineGameManager manager;
  const _RoundSummary({required this.manager});

  @override
  Widget build(BuildContext context) {
    final m    = manager;
    final gold = AppColors.gold;
    final grey = AppColors.grey;
    final alive = m.myUnits.where((u) => !u.isEliminated).toList();
    final dead  = m.myUnits.where((u) =>  u.isEliminated).toList();
    final totalCon = alive.fold(0, (s, u) => s + u.currentCon);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SumRow('Round', '${m.round}'),
      _SumRow('Units alive', '${alive.length}/${m.myUnits.length}'),
      _SumRow('Total CON remaining', '$totalCon'),
      _SumRow('AP remaining', '${m.myCP} / ${m.myInitialCP}'),
      if (m.myDiceRolls.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Dice rolls this round',
            style: GoogleFonts.cinzel(color: grey, fontSize: 11,
                letterSpacing: 0.5)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4,
            children: m.myDiceRolls.map((r) => Container(
                width: 28, height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    border: Border.all(
                        color: gold.withValues(alpha: 0.35))),
                child: Text('$r',
                    style: GoogleFonts.cinzel(
                        color: gold, fontSize: 13)))).toList()),
      ],
      if (dead.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Eliminated units',
            style: GoogleFonts.cinzel(color: grey, fontSize: 11,
                letterSpacing: 0.5)),
        const SizedBox(height: 6),
        ...dead.map((u) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Icon(Icons.close, color: Colors.red.shade400, size: 12),
              const SizedBox(width: 6),
              Text(u.displayName,
                  style: GoogleFonts.cinzel(
                      color: grey.withValues(alpha: 0.5), fontSize: 12)),
              const Spacer(),
              Text('R${u.eliminatedOnRound ?? '?'}',
                  style: GoogleFonts.cinzel(
                      color: grey.withValues(alpha: 0.35), fontSize: 10)),
            ]))),
      ],
    ]);
  }
}

class _SumRow extends StatelessWidget {
  final String label;
  final String value;
  const _SumRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Text(label, style: GoogleFonts.cinzel(
          color: AppColors.grey.withValues(alpha: 0.55), fontSize: 12)),
      const Spacer(),
      Text(value, style: GoogleFonts.cinzel(
          color: AppColors.gold, fontSize: 13, fontWeight: FontWeight.w600)),
    ]));
}

// ── Connection dot ────────────────────────────────────────────────────────────
class _ConnectionDot extends StatefulWidget {
  final bool connected;
  final bool active;
  const _ConnectionDot({required this.connected, required this.active});
  @override State<_ConnectionDot> createState() => _ConnectionDotState();
}

class _ConnectionDotState extends State<_ConnectionDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final color = !widget.active
        ? Colors.orange
        : (widget.connected ? Colors.green : Colors.red);
    return FadeTransition(
      opacity: widget.connected
          ? const AlwaysStoppedAnimation(1.0)
          : Tween(begin: 0.3, end: 1.0).animate(_ctrl),
      child: Tooltip(
          message: !widget.active
              ? 'Waiting for opponent'
              : (widget.connected ? 'Connected' : 'Opponent disconnected'),
          child: Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: color))));
  }
}

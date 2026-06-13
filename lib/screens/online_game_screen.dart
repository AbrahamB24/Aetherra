import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_theme.dart';
import '../game/models/game_state.dart';
import '../game/online/online_game_manager.dart';
import '../services/game_data_service.dart';
import '../widgets/aetherra_dialog.dart';
import '../widgets/nav_btn.dart';
import '../widgets/photo_crop_dialog.dart';
import '../widgets/unit_card.dart';
import '../widgets/action_log_sheet.dart';
import '../widgets/aetherra_text_field.dart';
import '../widgets/tutorial_overlay.dart';

class OnlineGameScreen extends StatefulWidget {
  final OnlineGameManager manager;
  const OnlineGameScreen({super.key, required this.manager});
  @override State<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends State<OnlineGameScreen>
    with WidgetsBindingObserver {
  static const gold = AppColors.gold;
  static const grey = AppColors.grey;
  static const dark = AppColors.dark;

  // Token-ID of the last reactive event for which each popup was shown.
  // Showing is keyed to the draw, not a per-game flag — each new draw gets a popup.
  String? _shownReactiveAwaiterForToken;
  String? _shownReactiveActiveForToken;
  bool    _wasWaitingForReactive = false;
  int _lastNotifiedDrawSerial = -1; // prevents double-firing for the same draw
  // After the first reactive wait popup, subsequent waits show a spinner on the button instead.
  bool    _hasSeenActiveReactivePopup = false;
  bool _shownOpponentLeftPopup    = false;
  bool _waitingForEndGame         = false;
  bool _waitingDialogOpen         = false;
  bool _nextRoundSheetOpen        = false;
  bool _endGameSheetOpen          = false;
  int  _waitingForConfirmRound    = 0;
  int  _confirmedNextRoundAtRound = -1; // suppress stale Realtime after confirming
  OnlinePendingType? _prevPendingType;
  bool   _waitingForConfirm = false;
  int    _unitTabIdx        = 0; // 0 = My Army, 1 = Opponent
  Timer? _waitingPollTimer;

  final _myScrollCtrl  = ScrollController();
  final _oppScrollCtrl = ScrollController();

  // Tutorial keys
  final _keyBanner  = GlobalKey(debugLabel: 'tut-banner');
  final _keyTokens  = GlobalKey(debugLabel: 'tut-tokens');
  final _keyCP      = GlobalKey(debugLabel: 'tut-cp');
  final _keyDice    = GlobalKey(debugLabel: 'tut-dice');
  final _keyNextRnd = GlobalKey(debugLabel: 'tut-nextRnd');
  final _keyTabBar  = GlobalKey(debugLabel: 'tut-tabBar');
  final _keyUnits   = GlobalKey(debugLabel: 'tut-units');
  final _keyLog     = GlobalKey(debugLabel: 'tut-log');
  static final _keyStr = GlobalKey(debugLabel: 'tut-str-online');

  List<TutorialStep> _tutorialSteps() => [
    TutorialStep(targetKey: _keyTokens,
      title: 'Activation Bag',
      body: 'Draw a token to determine which side activates next.'),
    TutorialStep(targetKey: _keyBanner,
      title: 'Army Banner',
      body: 'Shows live stats for the currently displayed army — switch armies using the tabs at the bottom.'),
    TutorialStep(targetKey: _keyCP,
      title: 'Command Points (CP)',
      body: 'Your CP pool. Reactive activations and Command abilities both deduct CP automatically. Use +/− to adjust manually if needed.'),
    TutorialStep(targetKey: _keyDice,
      title: 'Dice',
      body: 'Choose how many dice to roll, then tap to roll them. Results appear on screen and are saved to the action log.'),
    TutorialStep(targetKey: _keyNextRnd,
      title: 'Round Controls',
      body: 'Tap \'Next Round\' to send a request to your opponent — both must confirm before the round advances. \'End Game\' ends the session the same way.'),
    TutorialStep(targetKey: _keyTabBar,
      title: 'My Army / Opponent',
      body: 'Switch between your army and your opponent\'s army.'),
    TutorialStep(targetKey: _keyUnits,
      title: 'Unit Cards',
      body: 'Tap Activate in the unit photo to activate a unit — only available on your turn. Tap Ready to deactivate. Add notes or drag to reorder.'),
    TutorialStep(targetKey: _keyStr,
      title: 'STR',
      body: 'Tap the STR value to open a number picker and set it directly.'),
    TutorialStep(targetKey: _keyLog,
      title: 'Action Log',
      body: 'Full shared log of all rolls and events from both players. Filter by type or jump to a specific round.'),
  ];

  @override
  void initState() {
    super.initState();
    _lastNotifiedDrawSerial = widget.manager.drawSerial;
    widget.manager.addListener(_onManagerChange);
    WidgetsBinding.instance.addObserver(this);
    // Poll every 3 s while waiting for the guest to join — fallback for missed Realtime events.
    if (!widget.manager.gameActive) {
      _waitingPollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!mounted || widget.manager.gameActive) {
          _waitingPollTimer?.cancel();
          _waitingPollTimer = null;
          return;
        }
        widget.manager.pollForStart();
      });
    }
  }

  @override
  void dispose() {
    _waitingPollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.manager.removeListener(_onManagerChange);
    _myScrollCtrl.dispose();
    _oppScrollCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.manager.gameActive) {
      widget.manager.resubscribeAndRefresh();
    }
  }

  void _onManagerChange() {
    if (!mounted) return;
    final m = widget.manager;

    // Each reactive event gets a unique eventId (timestamp) written by drawToken.
    // Keying on eventId (not drawnTokenId) ensures tokens put back into the bag
    // and redrawn later still trigger fresh popups.
    final reactiveEventId = m.pendingData?['eventId'] as String?;
    if (m.pendingType == OnlinePendingType.reactive &&
        m.pendingData?['awaitingPlayer'] == m.myRole?.name &&
        reactiveEventId != null &&
        reactiveEventId != _shownReactiveAwaiterForToken) {
      _shownReactiveAwaiterForToken = reactiveEventId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showReactiveDialog();
      });
    }

    // Active-player popup: first wait → explain with popup; subsequent waits → spinner on button.
    final iAmWaitingNow = m.pendingType == OnlinePendingType.reactive &&
        m.pendingData?['fromPlayer'] == m.myRole?.name;
    if (iAmWaitingNow &&
        reactiveEventId != null &&
        reactiveEventId != _shownReactiveActiveForToken) {
      _shownReactiveActiveForToken = reactiveEventId;
      if (!_hasSeenActiveReactivePopup) {
        _hasSeenActiveReactivePopup = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showReactiveActiveDialog();
        });
      }
      // 2nd+ waits: no popup — the token-bag widget shows a spinner on the button.
    }

    // Opponent accepted reactive — I was waiting, now they are active
    if (_wasWaitingForReactive &&
        !iAmWaitingNow &&
        m.pendingType == null &&
        m.activePlayer != null &&
        m.activePlayer != m.myRole?.name) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showOpponentReactedDialog();
      });
    }
    _wasWaitingForReactive = iAmWaitingNow;

    // Next-round confirmation — only on the transition null → nextRound,
    // and never for a round we already confirmed (guards stale Realtime echoes).
    if (_prevPendingType != OnlinePendingType.nextRound &&
        m.pendingType == OnlinePendingType.nextRound &&
        m.pendingFrom != m.myRole?.name &&
        m.round != _confirmedNextRoundAtRound) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showNextRoundConfirmDialog();
      });
    }

    // My next-round request: accepted (round advanced) or declined (round unchanged)
    if (_waitingForConfirm && m.pendingType == null) {
      if (m.round > _waitingForConfirmRound) {
        // Accepted — clear flag and close waiting dialog silently
        _waitingForConfirm = false;
        if (_waitingDialogOpen) {
          _waitingDialogOpen = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop();
          });
        }
      } else {
        // Declined
        _waitingForConfirm = false;
        _waitingDialogOpen = false;
        if (!_nextRoundSheetOpen) {
          // Sheet already closed (user swiped away) — show dialog directly
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showDeclinedDialog('Next Round');
          });
        }
        // If sheet is open its ListenableBuilder handles pop + dialog
      }
    }

    // End-game request from opponent — only on the transition null → endGame
    if (_prevPendingType != OnlinePendingType.endGame &&
        m.pendingType == OnlinePendingType.endGame &&
        m.pendingFrom != m.myRole?.name) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showEndGameConfirmDialog();
      });
    }

    // My end-game request was confirmed → navigate home (guard before declined check)
    if (m.endGameConfirmed) {
      m.clearEndGameConfirmed();
      _waitingForEndGame = false;
      _waitingDialogOpen = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      });
    }

    // My end-game request was declined — only fires when not confirmed
    if (_waitingForEndGame && m.pendingType == null && !m.endGameConfirmed) {
      _waitingForEndGame = false;
      _waitingDialogOpen = false;
      if (!_endGameSheetOpen) {
        // Sheet already closed (user swiped away) — show dialog directly
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showDeclinedDialog('End Game');
        });
      }
      // If sheet is open its ListenableBuilder handles pop + dialog
    }

    _prevPendingType = m.pendingType;

    // Opponent left or saved — show once per event
    if (m.opponentLeft && !_shownOpponentLeftPopup) {
      _shownOpponentLeftPopup = true;
      m.clearOpponentLeft();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showOpponentLeftDialog();
      });
    }

    // Token drawn → notify the inactive player via snackbar.
    // Use drawSerial (not token ID) so the same token redrawn after reactive still fires.
    // lastDrawn.color == 'enemy' already excludes reactive draws (where my token was drawn).
    final lastDrawn = m.myPerspectiveBag.lastDrawn;
    if (lastDrawn != null &&
        m.drawSerial != _lastNotifiedDrawSerial &&
        lastDrawn.color == 'enemy') {
      _lastNotifiedDrawSerial = m.drawSerial;
      final oppName = m.opponentCreatorName ??
          (m.opponentArmyName.isNotEmpty ? m.opponentArmyName : 'Opponent');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(
              backgroundColor: AppColors.dark,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              duration: const Duration(seconds: 3),
              shape: const RoundedRectangleBorder(),
              content: Text("$oppName's token — their turn",
                style: GoogleFonts.cinzel(
                  color: AppColors.gold, fontSize: 12))));
        }
      });
    }

    setState(() {});
  }

  // ── Reactive activation popup ─────────────────────────────────────────────
  void _showReactiveDialog() {
    final m = widget.manager;
    const apColor = Color(0xFFC8A0E0);
    showAetherraSheet<void>(context,
      title: 'Reactive Activation',
      body: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(
          "Your opponent's token was drawn.\n"
          "Spend 1 CP to become the active player\n"
          "and activate one of your units first.",
          style: GoogleFonts.cinzel(color: grey, fontSize: 13, height: 1.6))),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(
              color: apColor.withValues(alpha: m.myCP > 0 ? 0.55 : 0.25))),
          child: Text('${m.myCP} CP',
            style: GoogleFonts.cinzel(
              color: m.myCP > 0 ? apColor : apColor.withValues(alpha: 0.4),
              fontSize: 11))),
      ]),
      actions: [
        SheetAction('Pass', grey, () {
          Navigator.pop(context);
          m.respondReactive(false);
        }, outlined: true),
        SheetAction('React  −1 CP', gold, m.myCP > 0 ? () {
          Navigator.pop(context);
          m.respondReactive(true);
        } : null),
      ]);
  }

  // ── Reactive info popup for the active player (shown once per game) ──────
  void _showReactiveActiveDialog() {
    showAetherraSheet<void>(context,
      title: 'Reactive Activation',
      body: Text(
        'Your token was drawn. Your opponent is now deciding\n'
        'whether to spend 1 CP to activate one of their units first.',
        style: GoogleFonts.cinzel(color: grey, fontSize: 13, height: 1.6)),
      actions: [SheetAction('OK', gold, () => Navigator.pop(context))]);
  }

  // ── Opponent left / saved notification ───────────────────────────────────
  void _showOpponentLeftDialog() {
    showAetherraSheet<void>(context,
      title: 'Opponent Left',
      body: Text(
        'Your opponent has left the battle. The game is saved and '
        'you can both rejoin at any time.',
        style: GoogleFonts.cinzel(color: grey, fontSize: 13, height: 1.6)),
      actions: [
        SheetAction('Continue', grey, () => Navigator.pop(context), outlined: true),
        SheetAction('Save & Exit', gold, () async {
          Navigator.pop(context);
          await widget.manager.saveGame();
          if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
        }),
      ]);
  }

  // ── Opponent's end-game confirmation sheet (shown to the receiving player) ──
  void _showEndGameConfirmDialog() {
    final m = widget.manager;
    final who = m.pendingFrom == OnlineRole.host.name
        ? m.opponentArmyName : m.myArmyName;
    bool showingOpponent = false;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: dark,
      builder: (_) => StatefulBuilder(
        builder: (_, setS) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          builder: (_, scroll) => Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16,
              MediaQuery.of(context).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(
                  color: grey.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Text('Game Summary',
                style: GoogleFonts.cinzel(color: gold, fontSize: 17)),
              const SizedBox(height: 4),
              Text('$who wants to end the battle',
                style: GoogleFonts.cinzel(color: grey, fontSize: 12)),
              const SizedBox(height: 12),
              _OnlineArmyPicker(
                myName: m.myArmyName,
                opponentName: m.opponentArmyName,
                showingOpponent: showingOpponent,
                onToggle: (v) => setS(() => showingOpponent = v)),
              Expanded(child: SingleChildScrollView(
                controller: scroll,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: showingOpponent
                    ? _OnlineEndGameSummaryContent(
                        units: m.opponentUnits, round: m.round)
                    : _OnlineEndGameSummaryContent(
                        units: m.myUnits, round: m.round,
                        cpSpent: m.myInitialCP - m.myCP)))),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    m.declineEndGame();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: grey,
                    side: BorderSide(color: grey.withValues(alpha: 0.4)),
                    shape: const RoundedRectangleBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text('Decline', style: GoogleFonts.cinzel(fontSize: 14)))),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await m.confirmEndGame();
                    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: gold,
                    foregroundColor: dark,
                    shape: const RoundedRectangleBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text('End Game',
                    style: GoogleFonts.cinzel(
                      fontSize: 14, fontWeight: FontWeight.w600)))),
              ]),
            ])))));
  }


  // ── Shown when opponent declines a Next Round or End Game request ─────────
  void _showDeclinedDialog(String action) {
    showAetherraSheet<void>(context,
      title: '$action Declined',
      body: Text(
        'Your opponent declined the $action request.',
        style: GoogleFonts.cinzel(color: grey, fontSize: 13, height: 1.6)),
      actions: [SheetAction('OK', gold, () => Navigator.pop(context))]);
  }

  // ── Opponent accepted reactive — notify the "from" player ────────────────
  void _showOpponentReactedDialog() {
    showAetherraSheet<void>(context,
      title: 'Reactive Activation',
      body: Text(
        'Your opponent spent 1 CP for a Reactive Activation.\n'
        'They are now the active player and will activate\n'
        'one of their units first.',
        style: GoogleFonts.cinzel(color: grey, fontSize: 13, height: 1.6)),
      actions: [SheetAction('OK', gold, () => Navigator.pop(context))]);
  }

  // ── Next-round bottom sheet (requesting player) ───────────────────────────
  void _showNextRoundSheet() {
    final m = widget.manager;
    bool showingOpponent = false;
    final waitingNotifier = ValueNotifier<bool>(false);
    bool popScheduled = false;
    setState(() => _nextRoundSheetOpen = true);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: dark,
      builder: (_) => StatefulBuilder(
        builder: (_, setS) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          builder: (_, scroll) => Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16,
              MediaQuery.of(context).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(
                  color: grey.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Text('Round ${m.round} – Summary',
                style: GoogleFonts.cinzel(color: gold, fontSize: 17)),
              const SizedBox(height: 12),
              _OnlineArmyPicker(
                myName: m.myArmyName,
                opponentName: m.opponentArmyName,
                showingOpponent: showingOpponent,
                onToggle: (v) => setS(() => showingOpponent = v)),
              Expanded(child: SingleChildScrollView(
                controller: scroll,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: showingOpponent
                    ? _OnlineRoundSummaryContent(
                        units: m.opponentUnits, round: m.round)
                    : _OnlineRoundSummaryContent(
                        units: m.myUnits, round: m.round,
                        cpSpent: m.myInitialCP - m.myCP,
                        diceRolls: m.myDiceRolls)))),
              const SizedBox(height: 20),
              ListenableBuilder(
                listenable: Listenable.merge([waitingNotifier, m]),
                builder: (_, __) {
                  final isWaiting = waitingNotifier.value;
                  if (isWaiting &&
                      m.pendingType != OnlinePendingType.nextRound &&
                      !popScheduled) {
                    popScheduled = true;
                    final accepted = m.round > _waitingForConfirmRound;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      if (Navigator.canPop(context)) Navigator.pop(context);
                      if (!accepted) _showDeclinedDialog('Next Round');
                    });
                  }
                  if (isWaiting) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(
                              color: gold, strokeWidth: 2)),
                          const SizedBox(width: 12),
                          Text('Waiting for opponent…',
                            style: GoogleFonts.cinzel(color: grey, fontSize: 13)),
                        ]));
                  }
                  return Row(children: [
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
                        setState(() {
                          _waitingForConfirm = true;
                          _waitingForConfirmRound = m.round;
                        });
                        await m.requestNextRound();
                        if (mounted) waitingNotifier.value = true;
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: gold,
                        foregroundColor: dark,
                        shape: const RoundedRectangleBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: Text('Request Next Round',
                        style: GoogleFonts.cinzel(
                          fontSize: 13, fontWeight: FontWeight.w600)))),
                  ]);
                }),
            ]))))).whenComplete(() {
      if (mounted) setState(() => _nextRoundSheetOpen = false);
    });
  }

  // ── End Game sheet ────────────────────────────────────────────────────────
  void _showOnlineEndGameSheet(BuildContext ctx, OnlineGameManager m) {
    bool showingOpponent = false;
    final waitingNotifier = ValueNotifier<bool>(false);
    bool popScheduled = false;
    setState(() => _endGameSheetOpen = true);
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: dark,
      builder: (_) => StatefulBuilder(
        builder: (_, setS) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          builder: (_, scroll) => Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16,
              MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(
                  color: grey.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Text('Game Summary',
                style: GoogleFonts.cinzel(color: gold, fontSize: 17)),
              const SizedBox(height: 12),
              _OnlineArmyPicker(
                myName: m.myArmyName,
                opponentName: m.opponentArmyName,
                showingOpponent: showingOpponent,
                onToggle: (v) => setS(() => showingOpponent = v)),
              Expanded(child: SingleChildScrollView(
                controller: scroll,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: showingOpponent
                    ? _OnlineEndGameSummaryContent(
                        units: m.opponentUnits, round: m.round)
                    : _OnlineEndGameSummaryContent(
                        units: m.myUnits, round: m.round,
                        cpSpent: m.myInitialCP - m.myCP)))),
              const SizedBox(height: 20),
              ListenableBuilder(
                listenable: Listenable.merge([waitingNotifier, m]),
                builder: (_, __) {
                  final isWaiting = waitingNotifier.value;
                  if (isWaiting &&
                      m.pendingType != OnlinePendingType.endGame &&
                      !popScheduled) {
                    popScheduled = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      // If accepted: _onManagerChange's popUntil(isFirst) already
                      // ran → mounted is false → skip. Declined: pop sheet + dialog.
                      if (!mounted) return;
                      if (Navigator.canPop(context)) Navigator.pop(context);
                      _showDeclinedDialog('End Game');
                    });
                  }
                  if (isWaiting) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(
                              color: gold, strokeWidth: 2)),
                          const SizedBox(width: 12),
                          Text('Waiting for opponent…',
                            style: GoogleFonts.cinzel(color: grey, fontSize: 13)),
                        ]));
                  }
                  return Column(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => _saveAndExit(ctx),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: gold,
                          side: BorderSide(color: gold.withValues(alpha: 0.45)),
                          shape: const RoundedRectangleBorder(),
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: Text('Save & Exit',
                          style: GoogleFonts.cinzel(fontSize: 14)))),
                    const SizedBox(height: 8),
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
                          setState(() => _waitingForEndGame = true);
                          await m.requestEndGame();
                          if (mounted) waitingNotifier.value = true;
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: gold,
                          foregroundColor: dark,
                          shape: const RoundedRectangleBorder(),
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: Text('End Game',
                          style: GoogleFonts.cinzel(
                            fontSize: 14, fontWeight: FontWeight.w600)))),
                    ]),
                  ]);
                }),
            ]))))).whenComplete(() {
      if (mounted) setState(() => _endGameSheetOpen = false);
    });
  }

  // ── Next-round confirmation sheet (opponent) ─────────────────────────────
  void _showNextRoundConfirmDialog() {
    final m = widget.manager;
    final who = m.pendingFrom == OnlineRole.host.name
        ? m.opponentArmyName : m.myArmyName;
    bool showingOpponent = false;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: dark,
      builder: (_) => StatefulBuilder(
        builder: (_, setS) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          builder: (_, scroll) => Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16,
              MediaQuery.of(context).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(
                  color: grey.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Text('Round ${m.round} Summary',
                style: GoogleFonts.cinzel(color: gold, fontSize: 17)),
              const SizedBox(height: 4),
              Text('$who wants to start Round ${m.round + 1}',
                style: GoogleFonts.cinzel(color: grey, fontSize: 12)),
              const SizedBox(height: 12),
              _OnlineArmyPicker(
                myName: m.myArmyName,
                opponentName: m.opponentArmyName,
                showingOpponent: showingOpponent,
                onToggle: (v) => setS(() => showingOpponent = v)),
              Expanded(child: SingleChildScrollView(
                controller: scroll,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: showingOpponent
                    ? _OnlineRoundSummaryContent(
                        units: m.opponentUnits, round: m.round)
                    : _OnlineRoundSummaryContent(
                        units: m.myUnits, round: m.round,
                        cpSpent: m.myInitialCP - m.myCP,
                        diceRolls: m.myDiceRolls)))),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    m.declineNextRound();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: grey,
                    side: BorderSide(color: grey.withValues(alpha: 0.4)),
                    shape: const RoundedRectangleBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text('Not yet', style: GoogleFonts.cinzel(fontSize: 14)))),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  onPressed: () {
                    setState(() => _confirmedNextRoundAtRound = m.round);
                    Navigator.pop(context);
                    m.confirmNextRound();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: gold,
                    foregroundColor: dark,
                    shape: const RoundedRectangleBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text('Start Round ${m.round + 1}',
                    style: GoogleFonts.cinzel(
                      fontSize: 14, fontWeight: FontWeight.w600)))),
              ]),
            ])))));
  }

  // ── Save & exit ──────────────────────────────────────────────────────────
  Future<void> _saveAndExit(BuildContext ctx) async {
    Navigator.pop(ctx);
    await widget.manager.saveGame();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  // ── Leave confirmation ────────────────────────────────────────────────────
  void _confirmLeave() {
    showAetherraSheet<void>(context,
      title: 'Leave Battle?',
      body: Text(
        'Your progress will be saved and you can continue later.',
        style: GoogleFonts.cinzel(color: grey, fontSize: 13, height: 1.5)),
      actions: [
        SheetAction('Cancel', grey, () => Navigator.pop(context), outlined: true),
        SheetAction('Save & Exit', gold, () async {
          Navigator.pop(context);
          await widget.manager.saveGame();
          if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
        }),
      ]);
  }

  // ── Main build ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final m        = widget.manager;
    final myColor  = AppColors.parseHex(m.myPlayerColor);
    final oppColor = AppColors.parseHex(m.opponentPlayerColor);
    final bag      = m.myPerspectiveBag;

    return Scaffold(
      backgroundColor: dark,
      appBar: AppBar(
        toolbarHeight: 62,
        leadingWidth: 48,
        leading: NavBtn(icon: Icons.home_outlined, onPressed: _confirmLeave),
        actions: [
          if (m.gameActive) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Center(child: Text('Round ${m.round}',
                style: GoogleFonts.cinzel(color: gold, fontSize: 12)))),
            KeyedSubtree(key: _keyLog,
              child: NavBtn(
                icon: Icons.history, width: 36,
                onPressed: () => showActionLogSheet(
                  context,
                  m.combinedActionLog,
                  myPlayerName:       m.myCreatorName ?? m.myArmyName,
                  opponentPlayerName: m.opponentCreatorName ?? (m.opponentArmyName.isNotEmpty ? m.opponentArmyName : 'Opponent'),
                ))),
            NavBtn(
              icon: Icons.help_outline, width: 36,
              onPressed: () => showTutorial(context, _tutorialSteps())),
          ],
        ],
      ),
      body: Column(children: [
        // ── Connection warnings ───────────────────────────────────────────
        if (m.gameActive && !m.channelOk)
          Container(
            color: Colors.red.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Row(children: [
              const SizedBox(width: 2,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: Colors.orange)),
              const SizedBox(width: 10),
              Expanded(child: Text('Reconnecting…',
                style: GoogleFonts.cinzel(color: Colors.orange, fontSize: 11))),
              TextButton(
                onPressed: () => m.resubscribeAndRefresh(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: Text('Retry',
                  style: GoogleFonts.cinzel(color: Colors.orange, fontSize: 11))),
            ])),
        if (m.gameActive && m.channelOk && !m.opponentConnected)
          Container(
            color: Colors.orange.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            child: Row(children: [
              const Icon(Icons.wifi_off, color: Colors.orange, size: 13),
              const SizedBox(width: 8),
              Expanded(child: Text('Opponent disconnected – waiting for reconnect…',
                style: GoogleFonts.cinzel(color: Colors.orange, fontSize: 11))),
            ])),

        // ── Waiting for opponent ──────────────────────────────────────────
        if (!m.gameActive)
          Expanded(child: Center(child: Column(
            mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(
              strokeWidth: 1.5, color: gold.withValues(alpha: 0.5)),
            const SizedBox(height: 28),
            Text('Waiting for opponent…',
              style: GoogleFonts.cinzel(color: grey, fontSize: 13)),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              decoration: BoxDecoration(
                border: Border.all(color: gold.withValues(alpha: 0.45))),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('ROOM CODE',
                  style: GoogleFonts.cinzel(
                    color: grey.withValues(alpha: 0.55),
                    fontSize: 10, letterSpacing: 2)),
                const SizedBox(height: 6),
                Text(m.roomCode ?? '------',
                  style: GoogleFonts.cinzel(
                    color: gold, fontSize: 32,
                    fontWeight: FontWeight.w700, letterSpacing: 8)),
              ])),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: m.roomCode ?? ''));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  duration: const Duration(seconds: 1),
                  backgroundColor: dark,
                  content: Text('Code copied!',
                    style: GoogleFonts.cinzel(color: gold))));
              },
              icon: const Icon(Icons.copy, color: AppColors.grey, size: 15),
              label: Text('Copy',
                style: GoogleFonts.cinzel(color: grey, fontSize: 12))),
            const SizedBox(height: 8),
            Text('Share this code with your opponent',
              style: GoogleFonts.cinzel(
                color: grey.withValues(alpha: 0.4), fontSize: 11)),
          ]))),

        // ── Game active ───────────────────────────────────────────────────
        if (m.gameActive) ...[
          // TOKEN BAG
          KeyedSubtree(key: _keyTokens,
            child: Container(
              margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              decoration: BoxDecoration(
                color: dark,
                border: Border.all(color: gold.withValues(alpha: 0.35))),
              child: _OnlineTokenBagWidget(
                manager: m, bag: bag, myColor: myColor, oppColor: oppColor,
                activeWaitSeen: _hasSeenActiveReactivePopup))),

          // ARMY BANNER (hides on scroll, switches with tab)
          KeyedSubtree(key: _keyBanner,
            child: _OnlineScrollHiddenBanner(
              manager: m,
              scrollCtrl: _unitTabIdx == 0 ? _myScrollCtrl : _oppScrollCtrl,
              tabIdx: _unitTabIdx)),

          // HEADER BAR (same as offline)
          SizedBox(height: 70,
            child: Container(
              color: dark,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                // AP — left: own (editable) or opponent (read-only)
                KeyedSubtree(key: _keyCP,
                  child: _unitTabIdx == 0 ? _onlineCpWidget(m) : _onlineOppCpWidget(m)),
                const Spacer(),
                // Dice
                KeyedSubtree(key: _keyDice,
                  child: _OnlineDiceButton(manager: m)),
                const Spacer(),
                // Next Round + End Game — right
                SizedBox(key: _keyNextRnd, width: 110, child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ActionBtn(
                      label: _waitingForConfirm ? 'Waiting…' : 'Next Round',
                      icon: Icons.skip_next,
                      onTap: _waitingForConfirm ? () {} : _showNextRoundSheet,
                      color: _waitingForConfirm ? grey : gold),
                    const SizedBox(height: 4),
                    _ActionBtn(
                      label: _waitingForEndGame ? 'Awaiting...' : 'End Game',
                      icon: Icons.flag_outlined,
                      onTap: _waitingForEndGame
                          ? () {}
                          : () => _showOnlineEndGameSheet(context, m),
                      color: grey),
                  ])),
              ]))),

          // UNIT AREA: tab-switched (My Army / Opponent)
          Expanded(child: KeyedSubtree(key: _keyUnits, child: Stack(children: [
            IndexedStack(
              index: _unitTabIdx,
              children: [
                // Tab 0: my army (wrapped in DnD outer drop catcher)
                _OnlineDndOuter(
                  manager:    m,
                  scrollCtrl: _myScrollCtrl,
                  child: ListView.builder(
                    controller: _myScrollCtrl,
                    padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                    itemCount: _myGroups(m).length,
                    itemBuilder: (_, gi) {
                      final entry     = _myGroups(m)[gi];
                      final groupName = entry.key;
                      final units     = entry.value;
                      final isElimGrp = groupName == '__eliminated__';
                      return _MyGroupSection(
                        key:       ValueKey('my_$groupName'),
                        groupName: groupName,
                        units:     units,
                        isElimGrp: isElimGrp,
                        manager:   m,
                        myColor:   myColor,
                        topMargin: gi > 0 ? 12.0 : 0.0);
                    })),
                // Tab 1: opponent army
                ListView.builder(
                  controller: _oppScrollCtrl,
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                  itemCount: _oppGroups(m).length,
                  itemBuilder: (_, gi) {
                    final entry     = _oppGroups(m)[gi];
                    final groupName = entry.key;
                    final units     = entry.value;
                    final isElimGrp = groupName == '__eliminated__';
                    return _OppGroupSection(
                      key:       ValueKey('opp_$groupName'),
                      groupName: groupName,
                      units:     units,
                      isElimGrp: isElimGrp,
                      oppColor:  oppColor,
                      topMargin: gi > 0 ? 12.0 : 0.0);
                  }),
              ]),
            // Fade top
            const Positioned(top: 0, left: 0, right: 0, height: 36,
              child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [AppColors.dark, Colors.transparent]))))),
            // Fade bottom
            const Positioned(bottom: 0, left: 0, right: 0, height: 36,
              child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter, end: Alignment.topCenter,
                  colors: [AppColors.dark, Colors.transparent]))))),
          ]))),

          // TAB BAR
          KeyedSubtree(key: _keyTabBar,
            child: Container(
              color: AppColors.dark,
              child: Row(children: [
                Expanded(child: _OnlineTab(
                  icon: Icons.shield_outlined,
                  label: '${m.myCreatorName ?? m.myArmyName} (${m.myUnits.where((u) => !u.isEliminated).length})',
                  selected: _unitTabIdx == 0,
                  onTap: () => setState(() => _unitTabIdx = 0))),
                Expanded(child: _OnlineTab(
                  icon: Icons.people_outline,
                  label: '${m.opponentCreatorName ?? (m.opponentArmyName.isNotEmpty ? m.opponentArmyName : 'Opponent')} (${m.opponentUnits.where((u) => !u.isEliminated).length})',
                  selected: _unitTabIdx == 1,
                  onTap: () => setState(() => _unitTabIdx = 1))),
              ]))),
        ],
      ]));
  }

  // AP widget — same style as offline _cpWidget
  Widget _onlineCpWidget(OnlineGameManager m) =>
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _GlowIcon(icon: Icons.remove, color: const Color(0xFFC8A0E0),
          size: 18, onTap: () { HapticFeedback.selectionClick(); m.adjustCP(-1); }),
        const SizedBox(width: 10),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${m.myCP}',
            style: GoogleFonts.cinzel(
              color: const Color(0xFFC8A0E0), fontSize: 20)),
          Text('CP', style: GoogleFonts.cinzel(
            color: const Color(0xFFC8A0E0).withValues(alpha: 0.6),
            fontSize: 9, letterSpacing: 1)),
        ]),
        const SizedBox(width: 10),
        _GlowIcon(icon: Icons.add, color: const Color(0xFFC8A0E0),
          size: 18, onTap: () { HapticFeedback.selectionClick(); m.adjustCP(1); }),
      ]));

  // Opponent AP — same position/size as _onlineCpWidget but no +/- buttons
  Widget _onlineOppCpWidget(OnlineGameManager m) =>
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 26), // _GlowIcon(size:18) renders at size+8 = 26
        const SizedBox(width: 10),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${m.opponentCP}',
            style: GoogleFonts.cinzel(
              color: const Color(0xFFC8A0E0), fontSize: 20)),
          Text('CP', style: GoogleFonts.cinzel(
            color: const Color(0xFFC8A0E0).withValues(alpha: 0.6),
            fontSize: 9, letterSpacing: 1)),
        ]),
        const SizedBox(width: 10),
        const SizedBox(width: 26), // _GlowIcon(size:18) renders at size+8 = 26
      ]));

  List<MapEntry<String, List<GameUnit>>> _myGroups(OnlineGameManager m) {
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

  List<MapEntry<String, List<GameUnit>>> _oppGroups(OnlineGameManager m) {
    final alive = m.opponentUnits.where((u) => !u.isEliminated).toList();
    final dead  = m.opponentUnits.where((u) =>  u.isEliminated).toList();
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


// ── Online Token Bag Widget ───────────────────────────────────────────────────
class _OnlineTokenBagWidget extends StatelessWidget {
  final OnlineGameManager manager;
  final TokenBag bag;
  final Color myColor;
  final Color oppColor;
  final bool activeWaitSeen;
  const _OnlineTokenBagWidget({
    required this.manager, required this.bag,
    required this.myColor, required this.oppColor,
    required this.activeWaitSeen});

  static const gold = AppColors.gold;
  static const grey = AppColors.grey;

  @override
  Widget build(BuildContext context) {
    final m           = manager;
    final last        = bag.lastDrawn;
    final canDraw     = m.canDraw;
    final remaining   = bag.bagCount;
    final myRoleName = m.myRole?.name;
    final isReactive = m.pendingType == OnlinePendingType.reactive;
    final iAmActive  = isReactive &&
        m.pendingData?['fromPlayer']    == myRoleName; // my token was drawn, I must wait
    return Container(
      color: AppColors.dark,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row: label + last drawn
        Row(children: [
          Text('TOKEN BAG', style: GoogleFonts.cinzel(
            color: gold.withValues(alpha: 0.85),
            fontSize: 13, letterSpacing: 2, fontWeight: FontWeight.w600)),
          const Spacer(),
          if (last != null) Row(children: [
            Text(
              last.color == 'player'
                ? "${m.myCreatorName ?? m.myArmyName}'s Turn"
                : "${m.opponentCreatorName ?? (m.opponentArmyName.isNotEmpty ? m.opponentArmyName : 'Opponent')}'s Turn",
              style: GoogleFonts.cinzel(
                color: last.color == 'player' ? myColor : oppColor,
                fontSize: 11)),
          ]),
        ]),
        const SizedBox(height: 8),
        // Draw Token button — or waiting spinner when opponent is deciding (2nd+ event)
        if (iAmActive && activeWaitSeen)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              border: Border.all(color: gold.withValues(alpha: 0.28))),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(width: 13, height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2, color: gold.withValues(alpha: 0.5))),
              const SizedBox(width: 10),
              Text("Waiting for Opponent’s Decision",
                style: GoogleFonts.cinzel(
                  color: gold.withValues(alpha: 0.55), fontSize: 11)),
            ]))
        else
          Row(children: [
            Expanded(child: _BagBtn(
              label: "Draw Token ($remaining)",
              color: canDraw ? gold : grey,
              onTap: canDraw ? () { HapticFeedback.lightImpact(); m.drawToken(); } : null)),
          ]),
        // Spinner below button for first reactive wait (popup was shown, user dismissed it)
        if (iAmActive && !activeWaitSeen) ...[
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(
              width: 11, height: 11,
              child: CircularProgressIndicator(
                strokeWidth: 1.5, color: gold.withValues(alpha: 0.45))),
            const SizedBox(width: 8),
            Text("Waiting for opponent’s decision...",
              style: GoogleFonts.cinzel(
                color: gold.withValues(alpha: 0.55), fontSize: 10)),
          ]),
        ],
      ]));
  }
}


// ── Scroll-hidden banner ──────────────────────────────────────────────────────
class _OnlineScrollHiddenBanner extends StatefulWidget {
  final OnlineGameManager manager;
  final ScrollController scrollCtrl;
  final int tabIdx;
  const _OnlineScrollHiddenBanner(
      {required this.manager, required this.scrollCtrl, required this.tabIdx});
  @override State<_OnlineScrollHiddenBanner> createState() =>
    _OnlineScrollHiddenBannerState();
}

class _OnlineScrollHiddenBannerState extends State<_OnlineScrollHiddenBanner> {
  bool _visible = true;

  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.scrollCtrl.addListener(_onScroll);
    });
  }

  @override void didUpdateWidget(_OnlineScrollHiddenBanner old) {
    super.didUpdateWidget(old);
    if (old.scrollCtrl != widget.scrollCtrl) {
      old.scrollCtrl.removeListener(_onScroll);
      widget.scrollCtrl.addListener(_onScroll);
      setState(() => _visible = true);
    }
  }

  @override void dispose() {
    widget.scrollCtrl.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!widget.scrollCtrl.hasClients) return;
    final show = widget.scrollCtrl.offset < 40;
    if (show != _visible) setState(() => _visible = show);
  }

  @override Widget build(BuildContext context) => AnimatedOpacity(
    duration: const Duration(milliseconds: 220),
    opacity: _visible ? 1.0 : 0.0,
    child: ClipRect(child: AnimatedAlign(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
      alignment: Alignment.bottomCenter,
      heightFactor: _visible ? 1.0 : 0.0,
      child: widget.tabIdx == 0
        ? _OnlineGameBanner(manager: widget.manager)
        : _OnlineOppBanner(manager: widget.manager))));
}

// ── Shared lore/units toggle buttons for both army banners ───────────────────
mixin _BannerBtns<T extends StatefulWidget> on State<T> {
  bool _loreExpanded  = false;
  bool _loreHovered   = false;
  bool _unitsExpanded = false;
  bool _unitsHovered  = false;

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
          color: AppColors.gold, size: 18,
          shadows: const [Shadow(color: Colors.black87, blurRadius: 6)]))));

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
              color: AppColors.gold, fontSize: 13,
              shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])),
          const SizedBox(width: 3),
          Icon(_unitsExpanded ? Icons.group : Icons.group_outlined,
            color: AppColors.gold, size: 18,
            shadows: const [Shadow(color: Colors.black87, blurRadius: 6)]),
        ]))));
}


// ── My army banner (matches _GameBanner from game_screen.dart exactly) ────────
class _OnlineGameBanner extends StatefulWidget {
  final OnlineGameManager manager;
  const _OnlineGameBanner({required this.manager});
  @override State<_OnlineGameBanner> createState() => _OnlineGameBannerState();
}

class _OnlineGameBannerState extends State<_OnlineGameBanner> with _BannerBtns<_OnlineGameBanner> {
  Widget? _cachedImg;
  static const gold = AppColors.gold;

  @override void initState() {
    super.initState();
    final b64 = widget.manager.myImageB64;
    if (b64 != null && b64.isNotEmpty) {
      try { _cachedImg = buildCroppedPhotoDisplay(b64, AppColors.bannerW, AppColors.bannerH); }
      catch (_) {}
    }
  }

  @override Widget build(BuildContext context) {
    final m        = widget.manager;
    final alive    = m.myUnits.where((u) => !u.isEliminated).toList();
    final alivePts = alive.fold(0, (s, u) => s + u.armyUnit.unit.cost);
    final totalPts = m.myUnits.fold(0, (s, u) => s + u.armyUnit.unit.cost);
    final aliveAtk = alive.fold(0, (s, u) => s + u.armyUnit.unit.atk);
    final aliveDef = alive.fold(0, (s, u) => s + u.armyUnit.unit.def);
    final aliveRng = alive.fold(0, (s, u) => s + u.armyUnit.unit.rng);
    final aliveMob = alive.fold(0, (s, u) => s + u.armyUnit.unit.mob);
    final aliveCon = alive.fold(0, (s, u) => s + u.currentCon);
    final hasLore  = m.myArmyLore != null && m.myArmyLore!.isNotEmpty;
    final creator  = m.myCreatorName;
    final bgColor  = AppColors.parseHex(m.myBgColor);

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: gold.withValues(alpha: 0.35))),
      child: Container(
        color: bgColor,
        child: Stack(clipBehavior: Clip.hardEdge, children: [
          if (_cachedImg != null)
            Positioned(top: 0, left: 0, right: 0, height: 115,
              child: ClipRect(child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0,
                    end: (_loreExpanded || _unitsExpanded) ? -40.0 : 0.0),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                builder: (_, dy, child) =>
                    Transform.translate(offset: Offset(0, dy), child: child),
                child: Center(child: _cachedImg!)))),
          Positioned.fill(child: IgnorePointer(child: DecoratedBox(
            decoration: BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              stops: const [0.0, 0.4, 1.0],
              colors: [
                Colors.black.withValues(alpha: 0.45),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.55),
              ]))))),
          Column(children: [
            SizedBox(
              height: 115,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(m.myArmyName,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.cinzel(
                              color: gold, fontSize: 17, letterSpacing: 2,
                              shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])),
                          if (creator != null && creator.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(creator,
                              style: GoogleFonts.cinzel(
                                color: Colors.white54, fontSize: 12,
                                shadows: const [Shadow(color: Colors.black87, blurRadius: 4)])),
                          ],
                          if ((m.opponentCreatorName ?? m.opponentArmyName).isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text('vs ${m.opponentCreatorName ?? m.opponentArmyName}',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cinzel(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                                shadows: const [Shadow(color: Colors.black87, blurRadius: 4)])),
                          ],
                        ])),
                      Text('$alivePts / $totalPts pts',
                        style: GoogleFonts.cinzel(
                          color: gold, fontSize: 17,
                          shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])),
                    ]),
                    Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      _buildLoreBtn(hasLore),
                      const SizedBox(width: 10),
                      _buildUnitsBtn(m.myUnits.length),
                      const Spacer(),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        BannerStat('${m.myCP}',  'CP'),
                        BannerStat('$aliveAtk', 'ATK'),
                        BannerStat('$aliveDef', 'DEF'),
                        BannerStat('$aliveRng', 'SHO'),
                        BannerStat('$aliveMob', 'MOB'),
                        BannerStat('$aliveCon', 'STR'),
                      ]),
                    ]),
                  ]))),
            AnimatedSize(
              duration: const Duration(milliseconds: 260), curve: Curves.easeOut,
              child: _unitsExpanded && m.myUnits.isNotEmpty
                ? BannerUnitsPanel(entries: m.myUnits.map((u) => {
                    'name':  u.armyUnit.customName.isNotEmpty
                        ? u.armyUnit.customName : u.armyUnit.unit.name,
                    'group': u.armyUnit.groupName,
                  }).toList())
                : const SizedBox.shrink()),
            AnimatedSize(
              duration: const Duration(milliseconds: 260), curve: Curves.easeOut,
              child: hasLore && _loreExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                    child: Text(m.myArmyLore!,
                      style: GoogleFonts.cinzel(
                        color: Colors.white70, fontSize: 13, height: 1.6,
                        fontStyle: FontStyle.italic,
                        shadows: const [Shadow(color: Colors.black87, blurRadius: 8)])))
                : const SizedBox.shrink()),
          ]),
        ])));
  }
}


// ── Opponent army banner (same style as _OnlineGameBanner) ────────────────────
class _OnlineOppBanner extends StatefulWidget {
  final OnlineGameManager manager;
  const _OnlineOppBanner({required this.manager});
  @override State<_OnlineOppBanner> createState() => _OnlineOppBannerState();
}

class _OnlineOppBannerState extends State<_OnlineOppBanner> with _BannerBtns<_OnlineOppBanner> {
  Widget? _cachedImg;
  String? _lastB64;
  static const gold = AppColors.gold;

  @override void initState() {
    super.initState();
    _rebuildImg(widget.manager.opponentImageB64);
  }

  @override void didUpdateWidget(_OnlineOppBanner old) {
    super.didUpdateWidget(old);
    final b64 = widget.manager.opponentImageB64;
    if (b64 != _lastB64) _rebuildImg(b64);
  }

  void _rebuildImg(String? b64) {
    _lastB64 = b64;
    if (b64 != null && b64.isNotEmpty) {
      try { _cachedImg = buildCroppedPhotoDisplay(b64, AppColors.bannerW, AppColors.bannerH); }
      catch (_) { _cachedImg = null; }
    } else { _cachedImg = null; }
  }

  @override Widget build(BuildContext context) {
    final m        = widget.manager;
    final alive    = m.opponentUnits.where((u) => !u.isEliminated).toList();
    final alivePts = alive.fold(0, (s, u) => s + u.armyUnit.unit.cost);
    final totalPts = m.opponentUnits.fold(0, (s, u) => s + u.armyUnit.unit.cost);
    final aliveAtk = alive.fold(0, (s, u) => s + u.armyUnit.unit.atk);
    final aliveDef = alive.fold(0, (s, u) => s + u.armyUnit.unit.def);
    final aliveRng = alive.fold(0, (s, u) => s + u.armyUnit.unit.rng);
    final aliveMob = alive.fold(0, (s, u) => s + u.armyUnit.unit.mob);
    final aliveCon = alive.fold(0, (s, u) => s + u.currentCon);
    final hasLore  = m.opponentArmyLore != null && m.opponentArmyLore!.isNotEmpty;
    final creator  = m.opponentCreatorName;
    final bgColor  = AppColors.parseHex(m.opponentBgColor);

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: gold.withValues(alpha: 0.35))),
      child: Container(
        color: bgColor,
        child: Stack(clipBehavior: Clip.hardEdge, children: [
          if (_cachedImg != null)
            Positioned(top: 0, left: 0, right: 0, height: 115,
              child: ClipRect(child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0,
                    end: (_loreExpanded || _unitsExpanded) ? -40.0 : 0.0),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                builder: (_, dy, child) =>
                    Transform.translate(offset: Offset(0, dy), child: child),
                child: Center(child: _cachedImg!)))),
          Positioned.fill(child: IgnorePointer(child: DecoratedBox(
            decoration: BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              stops: const [0.0, 0.4, 1.0],
              colors: [
                Colors.black.withValues(alpha: 0.45),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.55),
              ]))))),
          Column(children: [
            SizedBox(
              height: 115,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            m.opponentArmyName.isNotEmpty ? m.opponentArmyName : 'Opponent',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.cinzel(
                              color: gold, fontSize: 17, letterSpacing: 2,
                              shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])),
                          if (creator != null && creator.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(creator,
                              style: GoogleFonts.cinzel(
                                color: Colors.white54, fontSize: 12,
                                shadows: const [Shadow(color: Colors.black87, blurRadius: 4)])),
                          ],
                        ])),
                      Text('$alivePts / $totalPts pts',
                        style: GoogleFonts.cinzel(
                          color: gold, fontSize: 17,
                          shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])),
                    ]),
                    Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      _buildLoreBtn(hasLore),
                      const SizedBox(width: 10),
                      _buildUnitsBtn(m.opponentUnits.length),
                      const Spacer(),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        BannerStat('${m.opponentCP}', 'CP'),
                        BannerStat('$aliveAtk', 'ATK'),
                        BannerStat('$aliveDef', 'DEF'),
                        BannerStat('$aliveRng', 'SHO'),
                        BannerStat('$aliveMob', 'MOB'),
                        BannerStat('$aliveCon', 'STR'),
                      ]),
                    ]),
                  ]))),
            AnimatedSize(
              duration: const Duration(milliseconds: 260), curve: Curves.easeOut,
              child: _unitsExpanded && m.opponentUnits.isNotEmpty
                ? BannerUnitsPanel(entries: m.opponentUnits.map((u) => {
                    'name':  u.armyUnit.customName.isNotEmpty
                        ? u.armyUnit.customName : u.armyUnit.unit.name,
                    'group': u.armyUnit.groupName,
                  }).toList())
                : const SizedBox.shrink()),
            AnimatedSize(
              duration: const Duration(milliseconds: 260), curve: Curves.easeOut,
              child: hasLore && _loreExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                    child: Text(m.opponentArmyLore!,
                      style: GoogleFonts.cinzel(
                        color: Colors.white70, fontSize: 13, height: 1.6,
                        fontStyle: FontStyle.italic,
                        shadows: const [Shadow(color: Colors.black87, blurRadius: 8)])))
                : const SizedBox.shrink()),
          ]),
        ])));
  }
}


// ── Online DnD — static state ─────────────────────────────────────────────────
class _OnlineDndState {
  static GameUnit? _dragging;
  static int?      _insertAt;
  static String?   _insertGrp;
  static ScrollController? _scrollCtrl;
  static Timer?    _scrollTimer;

  static final _notifier = ValueNotifier<int>(0);

  static void _stopScroll() { _scrollTimer?.cancel(); _scrollTimer = null; }

  static void updateScroll(double globalY, double screenH) {
    if (_scrollCtrl == null || !_scrollCtrl!.hasClients || _dragging == null) return;
    final zone = screenH * 0.20;
    const maxSpeed = 16.0;
    _scrollTimer?.cancel(); _scrollTimer = null;
    if (globalY < zone) {
      final t = 1.0 - (globalY / zone).clamp(0.0, 1.0);
      _scrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
        if (_scrollCtrl == null || !_scrollCtrl!.hasClients) return;
        _scrollCtrl!.jumpTo((_scrollCtrl!.offset - maxSpeed * t)
          .clamp(0, _scrollCtrl!.position.maxScrollExtent));
      });
    } else if (globalY > screenH - zone) {
      final t = ((globalY - (screenH - zone)) / zone).clamp(0.0, 1.0);
      _scrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
        if (_scrollCtrl == null || !_scrollCtrl!.hasClients) return;
        _scrollCtrl!.jumpTo((_scrollCtrl!.offset + maxSpeed * t)
          .clamp(0, _scrollCtrl!.position.maxScrollExtent));
      });
    }
  }

  static void startDrag(GameUnit u) {
    _dragging = u; _insertAt = null; _insertGrp = null;
  }

  static void setInsert(int at, String g) {
    if (g == '__eliminated__') return;
    if (_insertAt != at || _insertGrp != g) {
      _insertAt = at; _insertGrp = g;
      _notifier.value++;
    }
  }

  static void cancel() {
    _dragging = null; _insertAt = null; _insertGrp = null;
    _notifier.value++;
  }

  static void drop(OnlineGameManager manager) {
    final u = _dragging;
    if (u != null && _insertAt != null && _insertGrp != null) {
      HapticFeedback.mediumImpact();
      manager.moveUnit(u, _insertAt!, _insertGrp!);
    }
    _dragging = null; _insertAt = null; _insertGrp = null;
    _notifier.value++;
  }
}

// ── Online DnD outer drop catcher ─────────────────────────────────────────────
class _OnlineDndOuter extends StatefulWidget {
  final OnlineGameManager manager;
  final ScrollController scrollCtrl;
  final Widget child;
  const _OnlineDndOuter({required this.manager, required this.scrollCtrl,
    required this.child});
  @override State<_OnlineDndOuter> createState() => _OnlineDndOuterState();
}

class _OnlineDndOuterState extends State<_OnlineDndOuter> {
  @override void initState() {
    super.initState();
    _OnlineDndState._scrollCtrl = widget.scrollCtrl;
  }
  @override void dispose() {
    _OnlineDndState._stopScroll();
    if (_OnlineDndState._scrollCtrl == widget.scrollCtrl) {
      _OnlineDndState._scrollCtrl = null;
    }
    super.dispose();
  }

  @override Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _OnlineDndState._notifier,
      builder: (_, __, ___) => DragTarget<GameUnit>(
        onWillAcceptWithDetails: (_) => _OnlineDndState._dragging != null,
        onAcceptWithDetails: (_) => _OnlineDndState.drop(widget.manager),
        builder: (ctx, __, ___) => widget.child));
  }
}

// ── Online DnD group grid ──────────────────────────────────────────────────────
class _OnlineGroupGrid extends StatefulWidget {
  final List<GameUnit> units;
  final OnlineGameManager manager;
  final Color myColor;
  final String grp;
  const _OnlineGroupGrid({required this.units, required this.manager,
    required this.myColor, required this.grp});
  @override State<_OnlineGroupGrid> createState() => _OnlineGroupGridState();
}

class _OnlineGroupGridState extends State<_OnlineGroupGrid> {
  @override void initState() {
    super.initState();
    _OnlineDndState._notifier.addListener(_rebuild);
  }
  @override void dispose() {
    _OnlineDndState._notifier.removeListener(_rebuild);
    super.dispose();
  }
  void _rebuild() => setState(() {});

  @override Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final wg     = constraints.maxWidth;
      final cols   = (wg / 308).floor().clamp(1, 6);
      final cardWg = ((wg - (cols - 1) * 8) / cols).floorToDouble();

      final dragging  = _OnlineDndState._dragging;
      final insertAt  = _OnlineDndState._insertAt;
      final insertGrp = _OnlineDndState._insertGrp;
      final allUnits  = widget.manager.myUnits;

      final grpEndIdx = allUnits.lastIndexWhere(
        (u) => u.groupName == widget.grp) + 1;

      // Build display with placeholder
      final display = <_OnlineItem>[];
      for (final u in widget.units) {
        final ai = allUnits.indexOf(u);
        if (insertGrp == widget.grp && insertAt == ai) {
          display.add(const _OnlineItem.ph());
        }
        if (u != dragging) display.add(_OnlineItem.unit(u, ai));
      }
      if (insertGrp == widget.grp && insertAt == grpEndIdx) {
        display.add(const _OnlineItem.ph());
      }

      final rows = <Widget>[];
      for (int r = 0; r * cols < display.length; r++) {
        final start    = r * cols;
        final end      = (start + cols).clamp(0, display.length);
        final rowItems = display.sublist(start, end);
        rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ...rowItems.asMap().entries.map((e) {
              final pad = EdgeInsets.only(left: e.key > 0 ? 8 : 0);
              if (e.value.isPlaceholder) {
                return Padding(padding: pad,
                  child: SizedBox(width: cardWg, height: 157,
                    child: CustomPaint(painter: _OnlineDashedPainter(),
                      child: Container(color:
                        AppColors.gold.withValues(alpha: 0.07)))));
              }
              return Padding(padding: pad,
                child: SizedBox(width: cardWg,
                  child: _OnlineDndTile(
                    unit: e.value.unit!, absIdx: e.value.absIdx!,
                    grp: widget.grp, manager: widget.manager,
                    myColor: widget.myColor, allUnits: allUnits)));
            }),
            Expanded(child: DragTarget<GameUnit>(
              onWillAcceptWithDetails: (_) => false,
              onMove: (_) => _OnlineDndState.setInsert(grpEndIdx, widget.grp),
              builder: (_, __, ___) => SizedBox(height: dragging != null ? 157 : 0))),
          ]));
      }

      if (display.isEmpty) {
        final isTarget = insertGrp == widget.grp && dragging != null;
        return DragTarget<GameUnit>(
          onWillAcceptWithDetails: (_) => false,
          onMove: (_) => _OnlineDndState.setInsert(grpEndIdx, widget.grp),
          builder: (_, __, ___) => AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: isTarget ? 160 : 60,
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: isTarget
                ? AppColors.gold.withValues(alpha: 0.07) : Colors.transparent,
              border: Border.all(color: AppColors.gold.withValues(
                alpha: isTarget ? 0.5 : dragging != null ? 0.2 : 0.0))),
            child: Center(child: dragging != null
              ? Text('Drop here', style: GoogleFonts.cinzel(
                  color: AppColors.gold.withValues(alpha: 0.4), fontSize: 11))
              : const SizedBox.shrink())));
      }

      rows.add(DragTarget<GameUnit>(
        onWillAcceptWithDetails: (_) => false,
        onMove: (_) {
          if (widget.grp != '__eliminated__') {
            _OnlineDndState.setInsert(grpEndIdx, widget.grp);
          }
        },
        builder: (_, __, ___) => SizedBox(
          height: dragging != null ? 40 : 8,
          width: double.infinity)));

      return Column(children: rows);
    });
  }
}

class _OnlineItem {
  final GameUnit? unit; final int? absIdx; final bool isPlaceholder;
  const _OnlineItem.unit(this.unit, this.absIdx) : isPlaceholder = false;
  const _OnlineItem.ph() : unit = null, absIdx = null, isPlaceholder = true;
}

class _OnlineDashedPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AppColors.gold.withValues(alpha: 0.8)
      ..strokeWidth = 1.5..style = PaintingStyle.stroke;
    const d = 7.0, g = 4.0;
    for (final m in (Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)))
        .computeMetrics()) {
      for (double x = 0; x < m.length; x += d + g) {
        canvas.drawPath(m.extractPath(x, (x + d).clamp(0, m.length)), p);
      }
    }
  }
  @override bool shouldRepaint(_OnlineDashedPainter o) => false;
}

// ── Online DnD tile ────────────────────────────────────────────────────────────
class _OnlineDndTile extends StatelessWidget {
  final GameUnit unit;
  final int absIdx;
  final String grp;
  final OnlineGameManager manager;
  final Color myColor;
  final List<GameUnit> allUnits;
  const _OnlineDndTile({required this.unit, required this.absIdx,
    required this.grp, required this.manager, required this.myColor,
    required this.allUnits});

  @override Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final isTouch = defaultTargetPlatform == TargetPlatform.android ||
                    defaultTargetPlatform == TargetPlatform.iOS;

    final feedbackCard = Material(color: Colors.transparent,
      child: Transform.scale(scale: 1.05,
        child: SizedBox(width: 260,
          child: _MyUnitCard(unit: unit, manager: manager, myColor: myColor))));

    final ghostCard = Opacity(opacity: 0.25,
      child: _MyUnitCard(unit: unit, manager: manager, myColor: myColor));

    final draggable = !isTouch
      ? (Widget child) => Draggable<GameUnit>(
          data: unit,
          onDragStarted: () => _OnlineDndState.startDrag(unit),
          onDragUpdate: (d) => _OnlineDndState.updateScroll(
            d.globalPosition.dy, screenH),
          onDragEnd: (det) {
            _OnlineDndState._stopScroll();
            if (!det.wasAccepted) _OnlineDndState.cancel();
          },
          onDraggableCanceled: (_, __) {
            _OnlineDndState._stopScroll();
            _OnlineDndState.cancel();
          },
          feedback: feedbackCard,
          childWhenDragging: ghostCard,
          child: child)
      : (Widget child) => LongPressDraggable<GameUnit>(
          data: unit,
          delay: const Duration(milliseconds: 400),
          onDragStarted: () => _OnlineDndState.startDrag(unit),
          onDragUpdate: (d) => _OnlineDndState.updateScroll(
            d.globalPosition.dy, screenH),
          onDragEnd: (det) {
            _OnlineDndState._stopScroll();
            if (!det.wasAccepted) _OnlineDndState.cancel();
          },
          onDraggableCanceled: (_, __) {
            _OnlineDndState._stopScroll();
            _OnlineDndState.cancel();
          },
          feedback: feedbackCard,
          childWhenDragging: ghostCard,
          child: child);

    return DragTarget<GameUnit>(
      onWillAcceptWithDetails: (_) => false,
      onMove: (det) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final local = box.globalToLocal(det.offset);
        _OnlineDndState.setInsert(
          local.dx < box.size.width / 2 ? absIdx : absIdx + 1, grp);
      },
      builder: (_, __, ___) => draggable(
        _MyUnitCard(unit: unit, manager: manager, myColor: myColor,
          strStatKey: unit == (allUnits.where((u) => !u.isEliminated && u.groupName == '').firstOrNull
              ?? allUnits.where((u) => !u.isEliminated).firstOrNull)
              ? _OnlineGameScreenState._keyStr : null)));
  }
}

// ── My army group section ─────────────────────────────────────────────────────
class _MyGroupSection extends StatefulWidget {
  final String groupName;
  final List<GameUnit> units;
  final bool isElimGrp;
  final OnlineGameManager manager;
  final Color myColor;
  final double topMargin;
  const _MyGroupSection({super.key, required this.groupName, required this.units,
    required this.isElimGrp, required this.manager, required this.myColor,
    required this.topMargin});
  @override State<_MyGroupSection> createState() => _MyGroupSectionState();
}

class _MyGroupSectionState extends State<_MyGroupSection> {
  static final Map<String, bool> _collapsedMap = {};
  static const gold = AppColors.gold;
  static const grey = AppColors.grey;

  bool get _collapsed => _collapsedMap[widget.groupName] ?? false;
  bool _hovered  = false;
  bool _dragOver = false;

  @override void initState() {
    super.initState();
    _OnlineDndState._notifier.addListener(_onDndChange);
  }
  @override void dispose() {
    _OnlineDndState._notifier.removeListener(_onDndChange);
    super.dispose();
  }
  void _onDndChange() {
    final active = _OnlineDndState._dragging != null &&
        _OnlineDndState._insertGrp == widget.groupName;
    if (active != _dragOver) setState(() => _dragOver = active);
  }

  int get _grpEndIdx {
    final units = widget.manager.myUnits;
    final last  = units.lastIndexWhere((u) => u.groupName == widget.groupName);
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
                    _OnlineDndState.setInsert(_grpEndIdx, widget.groupName);
                    if (!_dragOver) setState(() => _dragOver = true);
                  },
                  onLeave: (_) => setState(() => _dragOver = false),
                  builder: (_, __, ___) => _buildHeader())
              : _buildHeader(),
          ),
        ),

      if (!_collapsed)
        _OnlineGroupGrid(
          units:   widget.units,
          manager: widget.manager,
          myColor: widget.myColor,
          grp: widget.isElimGrp ? '__eliminated__' : widget.groupName),
    ]);
  }

  Widget _buildHeader() {
    final dragAlpha   = _dragOver ? 0.22 : _hovered ? 0.14 : 0.07;
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
            style: GoogleFonts.cinzel(
              color: Colors.red.withValues(alpha: 0.7), fontSize: 9)),
          const SizedBox(width: 6),
          Text('${widget.units.fold<int>(0, (s, u) => s + u.armyUnit.unit.cost)} pts',
            style: GoogleFonts.cinzel(
              color: Colors.red.withValues(alpha: 0.7), fontSize: 9)),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Units cannot be dragged here',
            child: Icon(Icons.lock_outline,
              color: Colors.red.withValues(alpha: 0.7), size: 13)),
        ] else ...[
          Text('${widget.units.length} unit${widget.units.length != 1 ? 's' : ''}',
            style: GoogleFonts.cinzel(color: grey, fontSize: 9)),
          const SizedBox(width: 6),
          Text('${widget.units.fold<int>(0, (s, u) => s + u.armyUnit.unit.cost)} pts',
            style: GoogleFonts.cinzel(color: grey, fontSize: 9)),
        ],
      ]));
  }
}

// ── My army unit card (interactive) ──────────────────────────────────────────
class _MyUnitCard extends StatelessWidget {
  final GameUnit unit;
  final OnlineGameManager manager;
  final Color myColor;
  final Key? strStatKey;
  const _MyUnitCard({required this.unit, required this.manager,
    required this.myColor, this.strStatKey});

  static const gold = AppColors.gold;
  static const grey = AppColors.grey;

  @override Widget build(BuildContext context) {
    final u               = unit.armyUnit.unit;
    final eliminated      = unit.isEliminated;
    final activated       = unit.activated;
    final isCurrentlyActive = !eliminated &&
        manager.activeUnitInstanceId == unit.instanceId;
    final isMyTurn        = !eliminated &&
        manager.activePlayer == manager.myRole?.name;
    // Reactive pending from MY draw — must wait for opponent's decision first
    final reactiveBlocking = manager.pendingType == OnlinePendingType.reactive &&
        manager.pendingData?['fromPlayer'] == manager.myRole?.name;
    const activatedColor  = Color(0xFF6B7A8D);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(
          color: (eliminated ? grey : typeColor(u.type)).withValues(alpha: eliminated ? 0.2 : 0.4),
          width: 1.5)),
      child: UnitCard(
          unit: u,
          strStatKey: strStatKey,
          customName: unit.armyUnit.customName,
          photoBase64: unit.armyUnit.photoBase64,
          bgColor: unit.armyUnit.bgColor,
          lore: unit.armyUnit.lore,
          note: eliminated ? null : unit.note,
          onNoteTap: eliminated ? null : () => _showNoteSheet(context, unit, manager),
          currentCon: unit.currentCon,
          onStrTap: eliminated ? null : () {
            final maxCon = u.con;
            final curCon = unit.currentCon;
            showModalBottomSheet<void>(
              context: context,
              backgroundColor: AppColors.dark,
              builder: (_) {
                var hovered = -1;
                return StatefulBuilder(
                  builder: (ctx, setSt) => Padding(
                    padding: EdgeInsets.fromLTRB(
                        16, 16, 16, MediaQuery.of(context).padding.bottom + 20),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Center(child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: grey.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2)))),
                      const SizedBox(height: 14),
                      Text('STR — ${unit.displayName}',
                        style: GoogleFonts.cinzel(
                          color: gold, fontSize: 14,
                          fontWeight: FontWeight.w600, letterSpacing: 1)),
                      const SizedBox(height: 16),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (int v = 0; v <= maxCon; v++)
                          MouseRegion(
                            cursor: SystemMouseCursors.click,
                            onEnter: (_) => setSt(() => hovered = v),
                            onExit:  (_) => setSt(() => hovered = -1),
                            child: GestureDetector(
                              onTap: () {
                                Navigator.pop(ctx);
                                manager.adjustCon(unit.instanceId, v - curCon);
                              },
                              child: Container(
                                width: 48, height: 48,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: v == curCon
                                      ? gold.withValues(alpha: 0.12) : Colors.transparent,
                                  border: Border.all(
                                    color: v == curCon
                                        ? gold : grey.withValues(alpha: 0.3),
                                    width: v == curCon ? 1.5 : 1)),
                                child: Text('$v',
                                  style: GoogleFonts.cinzel(
                                    color: v == curCon
                                        ? gold
                                        : hovered == v
                                            ? Colors.white
                                            : grey.withValues(alpha: 0.7),
                                    fontSize: 18,
                                    fontWeight: v == curCon
                                        ? FontWeight.w700 : FontWeight.w400))))),
                      ]),
                    ]),
                  ),
                );
              },
            );
          },
          dimmed: eliminated,
          onEdit: null,
          onAbilityUse: eliminated ? null : (String abilityName) {
            final ab = GameDataService.abilities
              .where((a) => a['name'] == abilityName).firstOrNull;
            final cpCost = ab?['cp_cost'] as int? ?? 0;
            if (cpCost <= 0) return null;
            return () => manager.adjustCP(-cpCost);
          },
          hideBorder: true,
          actions: const [],
          activateOverlay: eliminated ? null : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isCurrentlyActive) ...[
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.flag, color: gold, size: 10,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 6)]),
                  const SizedBox(width: 2),
                  Text('ACTIVE', style: GoogleFonts.cinzel(
                    color: gold, fontSize: 8, letterSpacing: 1,
                    shadows: [const Shadow(color: Colors.black87, blurRadius: 6)])),
                ]),
                const SizedBox(height: 3),
              ],
              if (!activated)
                _ActivateBtn(
                  label: 'Activate', color: gold,
                  onTap: isMyTurn && manager.activeUnitInstanceId == null && !reactiveBlocking
                    ? () { HapticFeedback.mediumImpact(); manager.activateUnit(unit.instanceId); }
                    : null),
              if (activated && isCurrentlyActive)
                _ActivateBtn(
                  label: 'Ready', color: activatedColor,
                  onTap: () { HapticFeedback.selectionClick(); manager.deactivateUnit(unit.instanceId); }),
            ])));
  }

  static void _showNoteSheet(BuildContext ctx, GameUnit unit, OnlineGameManager manager) {
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
              color: AppColors.grey.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Text(unit.displayName,
            style: GoogleFonts.cinzel(
              color: AppColors.gold, fontSize: 14, letterSpacing: 0.5)),
          const SizedBox(height: 14),
          AetherraTextField(
            controller: ctrl,
            hintText: 'Battle notes…',
            maxLines: 4),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () { manager.setNote(unit.instanceId, ''); Navigator.pop(ctx); },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.grey,
                side: BorderSide(color: AppColors.grey.withValues(alpha: 0.4)),
                shape: const RoundedRectangleBorder(),
                padding: const EdgeInsets.symmetric(vertical: 13)),
              child: Text('Clear', style: GoogleFonts.cinzel(fontSize: 13)))),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(
              onPressed: () { manager.setNote(unit.instanceId, ctrl.text.trim()); Navigator.pop(ctx); },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.dark,
                shape: const RoundedRectangleBorder(),
                padding: const EdgeInsets.symmetric(vertical: 13)),
              child: Text('Save', style: GoogleFonts.cinzel(
                fontSize: 13, fontWeight: FontWeight.w600)))),
          ]),
        ])));
  }
}


// ── Opponent army group section ───────────────────────────────────────────────
class _OppGroupSection extends StatefulWidget {
  final String groupName;
  final List<GameUnit> units;
  final bool isElimGrp;
  final Color oppColor;
  final double topMargin;
  const _OppGroupSection({super.key, required this.groupName, required this.units,
    required this.isElimGrp, required this.oppColor, required this.topMargin});
  @override State<_OppGroupSection> createState() => _OppGroupSectionState();
}

class _OppGroupSectionState extends State<_OppGroupSection> {
  static final Map<String, bool> _collapsedMap = {};
  static const gold = AppColors.gold;
  static const grey = AppColors.grey;

  bool get _collapsed => _collapsedMap[widget.groupName] ?? false;
  bool _hovered = false;

  @override Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.groupName.isNotEmpty)
        MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit:  (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: () => setState(() {
              _collapsedMap[widget.groupName] =
                  !(_collapsedMap[widget.groupName] ?? false);
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              margin: EdgeInsets.only(bottom: 4, top: widget.topMargin),
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              decoration: BoxDecoration(
                color: widget.isElimGrp
                  ? Colors.red.withValues(alpha: _hovered ? 0.14 : 0.07)
                  : gold.withValues(alpha: _hovered ? 0.14 : 0.07),
                border: Border(left: BorderSide(
                  color: widget.isElimGrp
                    ? Colors.red.withValues(alpha: 0.4) : gold,
                  width: 2))),
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
                Text('${widget.units.length} unit${widget.units.length != 1 ? 's' : ''}',
                  style: GoogleFonts.cinzel(
                    color: widget.isElimGrp
                      ? Colors.red.withValues(alpha: 0.7) : grey,
                    fontSize: 9)),
                const SizedBox(width: 6),
                Text('${widget.units.fold<int>(0, (s, u) => s + u.armyUnit.unit.cost)} pts',
                  style: GoogleFonts.cinzel(
                    color: widget.isElimGrp
                      ? Colors.red.withValues(alpha: 0.7) : grey,
                    fontSize: 9)),
              ]))),
        ),

      if (!_collapsed)
        LayoutBuilder(builder: (ctx, constraints) {
          final cols   = (constraints.maxWidth / 308).floor().clamp(1, 6);
          final cardWg = ((constraints.maxWidth - (cols - 1) * 8) / cols).floorToDouble();
          final rows   = <Widget>[];
          for (int r = 0; r * cols < widget.units.length; r++) {
            final start = r * cols;
            final end   = (start + cols).clamp(0, widget.units.length);
            rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (int i = start; i < end; i++)
                Padding(
                  padding: EdgeInsets.only(left: i > start ? 8 : 0),
                  child: SizedBox(width: cardWg,
                    child: _OppUnitCard(
                      key:      ValueKey(widget.units[i].instanceId),
                      unit:     widget.units[i],
                      oppColor: widget.oppColor))),
            ]));
          }
          return Column(mainAxisSize: MainAxisSize.min, children: rows);
        }),
    ]);
  }
}

// ── Opponent unit card (read-only) ────────────────────────────────────────────
class _OppUnitCard extends StatelessWidget {
  final GameUnit unit;
  final Color oppColor;
  const _OppUnitCard({super.key, required this.unit, required this.oppColor});

  static const grey = AppColors.grey;

  @override Widget build(BuildContext context) {
    final u          = unit.armyUnit.unit;
    final eliminated = unit.isEliminated;
    final activated  = unit.activated;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(
          color: (eliminated ? grey : typeColor(u.type)).withValues(alpha: eliminated ? 0.2 : 0.4),
          width: 1.5)),
      child: UnitCard(
        unit: u,
        customName: unit.armyUnit.customName,
        photoBase64: unit.armyUnit.photoBase64,
        bgColor: unit.armyUnit.bgColor,
        lore: unit.armyUnit.lore,
        currentCon: unit.currentCon,
        dimmed: eliminated,
        onEdit: null,
        onAbilityUse: null,
        hideBorder: true,
        actions: const [],
        activateOverlay: (!eliminated && activated)
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.flag, color: AppColors.gold, size: 10,
                shadows: [Shadow(color: Colors.black87, blurRadius: 6)]),
              const SizedBox(width: 2),
              Text('ACTIVE', style: GoogleFonts.cinzel(
                color: AppColors.gold, fontSize: 8, letterSpacing: 1,
                shadows: [const Shadow(color: Colors.black87, blurRadius: 6)])),
            ])
          : null));
  }
}


// ── Icon with hover glow ──────────────────────────────────────────────────────
class _GlowIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onTap;
  const _GlowIcon({required this.icon, required this.color,
    required this.size, required this.onTap});
  @override State<_GlowIcon> createState() => _GlowIconState();
}
class _GlowIconState extends State<_GlowIcon> {
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
        child: SizedBox(
          width: widget.size + 8, height: widget.size + 8,
          child: Center(child: AnimatedScale(
            scale: _pressed ? 0.80 : 1.0,
            duration: const Duration(milliseconds: 80),
            child: Icon(widget.icon,
              color: (_hovered || _pressed)
                ? widget.color
                : widget.color.withValues(alpha: 0.5),
              size: widget.size))))));
}


// ── Activate / Ready button ───────────────────────────────────────────────────
class _ActivateBtn extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap; // null = grayed-out / disabled
  const _ActivateBtn({required this.label, required this.color, this.onTap});
  @override State<_ActivateBtn> createState() => _ActivateBtnState();
}
class _ActivateBtnState extends State<_ActivateBtn> {
  bool _hovered = false;
  bool _pressed = false;
  @override Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return MouseRegion(
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit:  (_) => setState(() => _hovered = false),
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTapDown:   enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp:     enabled ? (_) { setState(() => _pressed = false); widget.onTap!(); } : null,
        onTapCancel: enabled ? ()  => setState(() => _pressed = false) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          transform: _pressed
            ? (Matrix4.identity()..scaleByDouble(0.88, 0.88, 1.0, 1.0))
            : Matrix4.identity(),
          transformAlignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: !enabled
              ? widget.color.withValues(alpha: 0.12)
              : _pressed
                ? widget.color.withValues(alpha: 0.65)
                : widget.color.withValues(alpha: _hovered ? 0.85 : 0.45)),
          child: Text(widget.label,
            style: GoogleFonts.cinzel(
              color: enabled ? AppColors.dark : AppColors.dark.withValues(alpha: 0.35),
              fontSize: 11, fontWeight: FontWeight.w600)))));
  }
}


// ── Action button (Next Round etc.) ──────────────────────────────────────────
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
          transform: _pressed
            ? (Matrix4.identity()..scaleByDouble(0.92, 0.92, 1.0, 1.0))
            : Matrix4.identity(),
          transformAlignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: _hovered
              ? widget.color.withValues(alpha: 0.1) : Colors.transparent),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(widget.icon,
              color: _hovered || _pressed
                ? widget.color : widget.color.withValues(alpha: 0.6),
              size: 13),
            const SizedBox(width: 4),
            Text(widget.label,
              style: GoogleFonts.cinzel(
                color: _hovered || _pressed
                  ? widget.color : widget.color.withValues(alpha: 0.7),
                fontSize: 10),
              overflow: TextOverflow.ellipsis, maxLines: 1),
          ]))));
}


// ── Token bag button ──────────────────────────────────────────────────────────
class _BagBtn extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _BagBtn({required this.label, required this.color, this.onTap});
  @override State<_BagBtn> createState() => _BagBtnState();
}
class _BagBtnState extends State<_BagBtn> {
  bool _hovered = false;
  bool _pressed = false;
  @override Widget build(BuildContext context) {
    final active = widget.onTap != null;
    final c = widget.color;
    final bg = active
        ? (_pressed ? c.withValues(alpha: 0.45)
            : c.withValues(alpha: _hovered ? 0.65 : 1.0))
        : c.withValues(alpha: 0.2);
    final textColor = active ? AppColors.dark : c.withValues(alpha: 0.55);
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
          transform: _pressed
            ? (Matrix4.identity()..scaleByDouble(0.92, 0.92, 1.0, 1.0))
            : Matrix4.identity(),
          transformAlignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bg),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              widget.label,
              style: GoogleFonts.cinzel(
                color: textColor,
                fontSize: 11, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center)))));
  }
}


// ── D20 Dice Button (online — passes rolls to manager) ───────────────────────
class _OnlineDiceButton extends StatefulWidget {
  final OnlineGameManager manager;
  const _OnlineDiceButton({required this.manager});
  @override State<_OnlineDiceButton> createState() => _OnlineDiceButtonState();
}

class _OnlineDiceButtonState extends State<_OnlineDiceButton>
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

    widget.manager.recordDiceRolls(rolls);

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
              Positioned(left: 1, right: 1, top: 1,
                bottom: _rolls.isNotEmpty ? 16 : 1,
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
                        ? const _D20Icon(number: null, gold: gold)
                        : _D20Icon(number: _lastResult, gold: gold))))),
              if (_rolls.isNotEmpty)
                Positioned(left: 0, right: 0, bottom: 1,
                  child: Text(_rolls.join(' '),
                    style: GoogleFonts.cinzel(color: grey, fontSize: 9),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center)),
            ])))));
  }
}

class _D20Icon extends StatelessWidget {
  final int? number;
  final Color gold;
  const _D20Icon({required this.number, required this.gold});
  @override Widget build(BuildContext context) => CustomPaint(
    size: const Size(28, 28),
    painter: _D20Painter(gold: gold, number: number));
}

class _D20Painter extends CustomPainter {
  final Color gold;
  final int? number;
  const _D20Painter({required this.gold, this.number});

  @override void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = size.width * 0.45;

    final path = Path();
    const sides = 6;
    for (int i = 0; i < sides; i++) {
      final angle = (i * 2 * math.pi / sides) - math.pi / 2;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();

    final inner = r * 0.55;
    for (int i = 0; i < sides; i++) {
      final a1 = (i * 2 * math.pi / sides) - math.pi / 2;
      final a2 = ((i + 1) * 2 * math.pi / sides) - math.pi / 2;
      canvas.drawLine(
        Offset(cx + r * math.cos(a1), cy + r * math.sin(a1)),
        Offset(cx, cy),
        Paint()..color = gold.withValues(alpha: 0.25)..strokeWidth = 0.8
          ..style = PaintingStyle.stroke);
      canvas.drawLine(
        Offset(cx + r * math.cos(a1), cy + r * math.sin(a1)),
        Offset(cx + inner * math.cos(a2), cy + inner * math.sin(a2)),
        Paint()..color = gold.withValues(alpha: 0.15)..strokeWidth = 0.6
          ..style = PaintingStyle.stroke);
    }

    canvas.drawPath(path,
      Paint()..color = gold.withValues(alpha: 0.15)..style = PaintingStyle.fill);
    canvas.drawPath(path,
      Paint()..color = gold..strokeWidth = 1.5..style = PaintingStyle.stroke);

    if (number != null) {
      final tp = TextPainter(
        text: TextSpan(text: '$number',
          style: TextStyle(color: gold, fontSize: number! >= 10 ? 8.5 : 10,
            fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
    } else {
      final tp = TextPainter(
        text: TextSpan(text: 'd10',
          style: TextStyle(color: gold.withValues(alpha: 0.7), fontSize: 7,
            fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
    }
  }

  @override bool shouldRepaint(_D20Painter o) =>
    o.number != number || o.gold != gold;
}

// ── Dice Roll Overlay ─────────────────────────────────────────────────────────
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
    final size    = MediaQuery.of(context).size;
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
            final y        = (d.sy + (d.ey - d.sy) * yFactor) * size.height;
            final spinT    = Curves.decelerate.transform(t);
            final angle    = d.totalSpin * spinT;
            final settled  = t >= 0.90;
            final tiltFade = settled ? 0.0 : (1.0 - t);
            final tiltX    = d.tiltX * tiltFade;
            final tiltY    = d.tiltY * tiltFade;
            final airScale = t < 0.75 ? 1.0 + (1.0 - t / 0.75) * 0.3 : 1.0;
            final wobble   = settled
              ? math.sin((t - 0.90) / 0.10 * math.pi * 5) *
                (1 - (t - 0.90) / 0.10) * 0.05 : 0.0;
            final displayVal = t < 0.87 ? (_rng.nextInt(widget.diceType) + 1) : d.result;

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
              final bestIdx = widget.results.indexOf(widget.best);
              final bestDie = _dice.isNotEmpty && bestIdx < _dice.length
                ? _dice[bestIdx] : null;
              return Stack(children: [
                if (bestDie != null)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: bestDie.ey, end: 0.25),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    builder: (_, yv, __) {
                      final s = MediaQuery.of(context).size;
                      return Positioned(
                        left: s.width / 2 - 55,
                        top: yv * s.height - 55,
                        child: Transform.scale(scale: v * 1.5,
                          child: _D203D(
                            value: widget.best, size: 110,
                            highlight: true, rolling: false)));
                    }),
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
  static const gold  = AppColors.gold;
  static const dark1 = AppColors.dark;
  const _D203DPainter({required this.value, required this.highlight,
    required this.rolling});

  @override void paint(Canvas canvas, Size sz) {
    final cx = sz.width  / 2;
    final cy = sz.height / 2;
    final r  = sz.width  * 0.44;

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

    final faceShades = [0.85, 0.70, 0.55, 0.45, 0.60, 0.75];
    for (int i = 0; i < 6; i++) {
      final v1    = verts[i];
      final v2    = verts[(i + 1) % 6];
      final shade = faceShades[i];
      final tri   = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(v1.dx, v1.dy)
        ..lineTo(v2.dx, v2.dy)
        ..close();
      canvas.drawPath(tri, Paint()
        ..color = Color.lerp(dark1, AppColors.dark, shade)!
        ..style = PaintingStyle.fill);
    }

    final midShades = [0.95, 0.80, 0.60, 0.50, 0.65, 0.80];
    for (int i = 0; i < 6; i++) {
      final v1  = verts[i];
      final v2  = verts[(i + 1) % 6];
      final m1  = midVerts[i];
      final tri = Path()
        ..moveTo(v1.dx, v1.dy)
        ..lineTo(v2.dx, v2.dy)
        ..lineTo(m1.dx, m1.dy)
        ..close();
      canvas.drawPath(tri, Paint()
        ..color = Color.lerp(AppColors.dark,
            const Color(0xFF3A3020), midShades[i])!
        ..style = PaintingStyle.fill);
    }

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

    canvas.drawCircle(
      Offset(cx + r * 0.2, cy - r * 0.25), r * 0.18,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
        ..style = PaintingStyle.fill);

    final fs = value >= 10 ? sz.width * 0.27 : sz.width * 0.32;
    final tp = TextPainter(
      text: TextSpan(text: '$value',
        style: TextStyle(
          color: highlight ? gold
            : (rolling ? gold.withValues(alpha: 0.7) : gold.withValues(alpha: 0.95)),
          fontSize: fs,
          fontWeight: FontWeight.bold,
          shadows: highlight ? const [Shadow(color: gold, blurRadius: 12)] : null)),
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


// ── Online round-summary content ──────────────────────────────────────────────
class _OnlineRoundSummaryContent extends StatelessWidget {
  final List<GameUnit> units;
  final int round;
  final int? cpSpent;
  final List<int> diceRolls;
  const _OnlineRoundSummaryContent({
    required this.units, required this.round,
    this.cpSpent, this.diceRolls = const [],
  });

  List<MapEntry<String, List<GameUnit>>> _grouped(List<GameUnit> us) {
    final order = <String>[''];
    for (final u in us) {
      if (!order.contains(u.groupName)) order.add(u.groupName);
    }
    return [
      for (final g in order)
        if (us.any((u) => u.groupName == g))
          MapEntry(g, us.where((u) => u.groupName == g).toList()),
    ];
  }

  Widget _armyTotalsBar(List<GameUnit> alive) {
    final totalAtk = alive.fold(0, (s, u) => s + u.armyUnit.unit.atk);
    final totalDef = alive.fold(0, (s, u) => s + u.armyUnit.unit.def);
    final totalRng = alive.fold(0, (s, u) => s + u.armyUnit.unit.rng);
    final totalMob = alive.fold(0, (s, u) => s + u.armyUnit.unit.mob);
    final totalCon = alive.fold(0, (s, u) => s + u.currentCon);
    final stats = [
      ('${alive.length}', 'Units'), ('$totalAtk', 'ATK'), ('$totalDef', 'DEF'),
      ('$totalRng', 'SHO'), ('$totalMob', 'MOB'), ('$totalCon', 'STR'),
    ];
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      for (final s in stats)
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(s.$1, style: GoogleFonts.cinzel(
            color: AppColors.gold, fontSize: 13, fontWeight: FontWeight.w600)),
          Text(s.$2, style: GoogleFonts.cinzel(
            color: AppColors.grey, fontSize: 8, letterSpacing: 0.5)),
        ]),
    ]);
  }

  Widget _groupHeader(String name) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 3),
    child: Text(name, style: GoogleFonts.cinzel(
      color: AppColors.gold.withValues(alpha: 0.7), fontSize: 10, letterSpacing: 0.8)));

  Widget _lostStatsRow(int atk, int def, int rng, int mob, int con) =>
    Wrap(spacing: 10, runSpacing: 4, children: [
      for (final s in [('ATK', atk), ('DEF', def), ('SHO', rng), ('MOB', mob), ('STR', con)])
        RichText(text: TextSpan(style: GoogleFonts.cinzel(fontSize: 10), children: [
          TextSpan(text: '${s.$1} ', style: const TextStyle(color: AppColors.grey)),
          TextSpan(text: '-${s.$2}',
            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
        ])),
    ]);

  Widget _statChip(IconData icon, String value, String label, Color color) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5)),
        color: color.withValues(alpha: 0.10)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(value, style: GoogleFonts.cinzel(
            color: AppColors.textLight, fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.cinzel(color: AppColors.grey, fontSize: 9)),
      ]));

  Widget _unitRow(GameUnit u) {
    final maxCon   = u.armyUnit.unit.con;
    final conColor = u.currentCon >= maxCon
        ? const Color(0xFF2ECC71)
        : u.currentCon <= 1
            ? const Color(0xFFEF5350)
            : const Color(0xFFFF8C00);
    final isElim   = u.isEliminated;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Icon(
          isElim ? Icons.cancel_outlined
            : u.activated ? Icons.check_circle_outline : Icons.radio_button_unchecked,
          size: 14,
          color: isElim ? Colors.red
            : u.activated
              ? AppColors.gold.withValues(alpha: 0.9)
              : AppColors.greyLight.withValues(alpha: 0.4)),
        const SizedBox(width: 8),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(child: Text(u.displayName,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cinzel(
                  color: isElim ? AppColors.grey
                    : u.activated ? AppColors.textLight : AppColors.grey,
                  fontSize: 11,
                  decoration: isElim ? TextDecoration.lineThrough : null,
                  decorationColor: AppColors.grey))),
              if (isElim)
                Text('Fallen', style: GoogleFonts.cinzel(color: Colors.red, fontSize: 9)),
            ]),
            if (!isElim) ...[
              const SizedBox(height: 4),
              Row(children: [
                SizedBox(width: 80, height: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: maxCon > 0 ? u.currentCon / maxCon : 0.0,
                      backgroundColor: AppColors.greyLight.withValues(alpha: 0.2),
                      valueColor: AlwaysStoppedAnimation(conColor)))),
                const SizedBox(width: 8),
                Text('${u.currentCon}/$maxCon',
                  style: GoogleFonts.cinzel(color: conColor, fontSize: 9)),
              ]),
            ],
          ])),
      ]));
  }

  @override
  Widget build(BuildContext context) {
    final alive           = units.where((u) => !u.isEliminated).toList();
    final fallenThisRound = units
      .where((u) => u.isEliminated && u.eliminatedOnRound == round).toList();
    final activatedCount  = alive.where((u) => u.activated).length;
    final avgRoll = diceRolls.isEmpty ? null
      : diceRolls.reduce((a, b) => a + b) / diceRolls.length;

    int lostAtk = 0, lostDef = 0, lostRng = 0, lostMob = 0, lostCon = 0;
    for (final u in fallenThisRound) {
      lostAtk += u.armyUnit.unit.atk; lostDef += u.armyUnit.unit.def;
      lostRng += u.armyUnit.unit.rng; lostMob += u.armyUnit.unit.mob;
      lostCon += u.armyUnit.unit.con;
    }
    final aliveGroups  = _grouped(alive);
    final fallenGroups = _grouped(fallenThisRound);

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _armyTotalsBar(alive),
        const SizedBox(height: 12),
        Divider(color: AppColors.gold.withValues(alpha: 0.22), height: 1),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          _statChip(Icons.check_circle_outline,
            '$activatedCount / ${alive.length}', 'Activated', AppColors.gold),
          if (cpSpent != null)
            _statChip(Icons.flash_on, '$cpSpent', 'AP Spent', const Color(0xFFC8A0E0)),
          if (avgRoll != null)
            _statChip(Icons.casino_outlined, avgRoll.toStringAsFixed(1),
              'Avg Roll (${diceRolls.length}×)', const Color(0xFF7ABFD4)),
        ]),
        const SizedBox(height: 12),
        Divider(color: AppColors.gold.withValues(alpha: 0.22), height: 1),
        const SizedBox(height: 4),
        for (final entry in aliveGroups) ...[
          if (entry.key.isNotEmpty) _groupHeader(entry.key),
          ...entry.value.map(_unitRow),
        ],
        if (fallenThisRound.isNotEmpty) ...[
          const SizedBox(height: 6),
          Divider(color: Colors.red.withValues(alpha: 0.25), height: 1),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: _lostStatsRow(lostAtk, lostDef, lostRng, lostMob, lostCon)),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text('Fallen this round',
              style: GoogleFonts.cinzel(color: AppColors.grey, fontSize: 9))),
          for (final entry in fallenGroups) ...[
            if (entry.key.isNotEmpty) _groupHeader(entry.key),
            ...entry.value.map(_unitRow),
          ],
        ],
      ]);
  }
}


// ── Tab bar button ────────────────────────────────────────────────────────────
class _OnlineTab extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _OnlineTab({required this.icon, required this.label,
    required this.selected, required this.onTap});
  @override State<_OnlineTab> createState() => _OnlineTabState();
}
class _OnlineTabState extends State<_OnlineTab> {
  bool _hovered = false;
  static const gold = AppColors.gold;
  static const grey = AppColors.grey;
  @override Widget build(BuildContext context) {
    final color = widget.selected ? gold
        : _hovered ? gold.withValues(alpha: 0.7) : grey;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(
              color: widget.selected ? gold : Colors.transparent,
              width: 2))),
          child: Column(children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 120),
              child: Icon(widget.icon,
                key: ValueKey(color), color: color, size: 18)),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 120),
              style: GoogleFonts.cinzel(color: color, fontSize: 13),
              child: Text(widget.label)),
          ]))));
  }
}


// ── Online end-game summary content ──────────────────────────────────────────
class _OnlineEndGameSummaryContent extends StatelessWidget {
  final List<GameUnit> units;
  final int round;
  final int? cpSpent;
  const _OnlineEndGameSummaryContent({
    required this.units, required this.round, this.cpSpent,
  });

  @override
  Widget build(BuildContext context) {
    final eliminated = units.where((u) => u.isEliminated).toList();
    final alive      = units.where((u) => !u.isEliminated).toList();
    final totalSTR   = units.fold(0, (s, u) => s + u.armyUnit.unit.con);
    final lostSTR    = units.fold(0, (s, u) => s + (u.armyUnit.unit.con - u.currentCon));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _SummaryStatTile('Round',     '$round'),
        _SummaryStatTile('Surviving', '${alive.length} / ${units.length}'),
        _SummaryStatTile('STR Lost',  '$lostSTR / $totalSTR'),
        _SummaryStatTile('CP Spent', '${cpSpent ?? 0}'),
      ]),
      if (eliminated.isNotEmpty) ...[
        const SizedBox(height: 24),
        Text('ELIMINATED', style: GoogleFonts.cinzel(
          color: AppColors.gold.withValues(alpha: 0.6),
          fontSize: 10, letterSpacing: 2)),
        const SizedBox(height: 10),
        ...eliminated.map((u) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.12))),
          child: Row(children: [
            Expanded(child: Text(u.displayName,
              style: GoogleFonts.cinzel(color: Colors.white60, fontSize: 13))),
            if (u.eliminatedOnRound != null)
              Text('Round ${u.eliminatedOnRound}', style: GoogleFonts.cinzel(
                color: AppColors.grey.withValues(alpha: 0.55), fontSize: 11)),
          ]))),
      ],
      if (alive.isNotEmpty) ...[
        const SizedBox(height: 24),
        Text('SURVIVING', style: GoogleFonts.cinzel(
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
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.12))),
            child: Row(children: [
              Expanded(child: Text(u.displayName,
                style: GoogleFonts.cinzel(color: Colors.white70, fontSize: 13))),
              Text('${u.currentCon}/$maxCon STR', style: GoogleFonts.cinzel(
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

// ── Shared stat tile ──────────────────────────────────────────────────────────
class _SummaryStatTile extends StatelessWidget {
  final String label, value;
  const _SummaryStatTile(this.label, this.value);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.2))),
      child: Column(children: [
        Text(value, style: GoogleFonts.cinzel(
          color: AppColors.gold, fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.cinzel(
          color: AppColors.grey, fontSize: 9, letterSpacing: 1)),
      ])));
}

// ── Army picker (tab strip near the title of summary sheets) ─────────────────
class _OnlineArmyPicker extends StatelessWidget {
  final String myName;
  final String opponentName;
  final bool showingOpponent;
  final ValueChanged<bool> onToggle;
  const _OnlineArmyPicker({
    required this.myName, required this.opponentName,
    required this.showingOpponent, required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    Widget tab(String name, bool isOpp) {
      final sel = showingOpponent == isOpp;
      return Expanded(child: GestureDetector(
        onTap: () => onToggle(isOpp),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(
              color: sel ? AppColors.gold : AppColors.grey.withValues(alpha: 0.25),
              width: sel ? 2 : 1))),
          alignment: Alignment.center,
          child: Text(name,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.cinzel(
              color: sel ? AppColors.gold : AppColors.grey,
              fontSize: 12,
              fontWeight: sel ? FontWeight.w600 : FontWeight.w400)))));
    }
    return Row(children: [
      tab(myName, false),
      tab(opponentName, true),
    ]);
  }
}

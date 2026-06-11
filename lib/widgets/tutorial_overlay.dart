import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_theme.dart';

// ── Public API ────────────────────────────────────────────────────────────────

class TutorialStep {
  final GlobalKey targetKey;
  final String title;
  final String body;
  const TutorialStep({required this.targetKey, required this.title, required this.body});
}

void showTutorial(BuildContext context, List<TutorialStep> steps) {
  if (steps.isEmpty) return;
  late OverlayEntry entry;
  entry = OverlayEntry(
      builder: (_) => _TutorialOverlay(
          steps: steps, onDismiss: () => entry.remove()));
  Overlay.of(context).insert(entry);
}

// ── Overlay stateful widget ───────────────────────────────────────────────────

class _TutorialOverlay extends StatefulWidget {
  final List<TutorialStep> steps;
  final VoidCallback onDismiss;
  const _TutorialOverlay({required this.steps, required this.onDismiss});
  @override State<_TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<_TutorialOverlay>
    with SingleTickerProviderStateMixin {
  int   _step = 0;
  Rect? _from;
  Rect? _to;
  late final AnimationController _ctrl;
  late final Animation<double>    _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _readAndAnimate(null));
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _readAndAnimate(Rect? previous) {
    if (!mounted) return;
    final r = _rectOf(widget.steps[_step].targetKey);
    if (r == null) return;
    setState(() { _from = previous; _to = r; });
    _ctrl.forward(from: 0);
  }

  void _goTo(int idx) {
    final prev = _to;
    setState(() => _step = idx);
    WidgetsBinding.instance.addPostFrameCallback((_) => _readAndAnimate(prev));
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final step   = widget.steps[_step];
    final from   = _from;
    final to     = _to;

    return Material(
      color: Colors.transparent,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final t  = Curves.easeInOut.transform(_ctrl.value);
          final hl = (from != null && to != null)
              ? Rect.lerp(from, to, t)!
              : to;

          // ── Callout position ──────────────────────────────────────────────
          const pad  = _SpotlightPainter._pad;
          const gap  = pad + 8.0;
          const boxW = 280.0;

          final hlMidY    = hl != null ? hl.top + hl.height / 2 : 0.0;
          final showAbove = hlMidY > screen.height * 0.55;
          final hlBottom  = (hl?.bottom ?? 0) + gap;
          final hlTop     = (hl?.top    ?? 0) - gap;
          final cx        = hl != null ? hl.left + hl.width / 2 : screen.width / 2;
          final left      = (cx - boxW / 2).clamp(12.0, screen.width - boxW - 12);

          return Stack(children: [
            // ── Dark backdrop with spotlight cutout ────────────────────────
            if (hl != null)
              CustomPaint(size: screen, painter: _SpotlightPainter(highlight: hl)),
            // ── Tap outside dismisses ──────────────────────────────────────
            Positioned.fill(child: GestureDetector(
                onTap: widget.onDismiss,
                behavior: HitTestBehavior.translucent)),
            // ── Callout box ────────────────────────────────────────────────
            if (hl != null)
              Positioned(
                left:   left,
                width:  boxW,
                top:    showAbove ? null : hlBottom,
                bottom: showAbove ? screen.height - hlTop : null,
                child: FadeTransition(
                  opacity: _fade,
                  child: _CalloutBox(
                    step:      step,
                    stepIndex: _step,
                    stepCount: widget.steps.length,
                    onNext: _step < widget.steps.length - 1
                        ? () => _goTo(_step + 1)
                        : widget.onDismiss,
                    onPrev: _step > 0 ? () => _goTo(_step - 1) : null,
                    onSkip: widget.onDismiss))),
          ]);
        }));
  }
}

// ── Spotlight painter ─────────────────────────────────────────────────────────

class _SpotlightPainter extends CustomPainter {
  static const _pad = 10.0;
  static const _r   = Radius.circular(8);
  final Rect highlight;
  const _SpotlightPainter({required this.highlight});

  @override
  void paint(Canvas canvas, Size size) {
    final hl = highlight.inflate(_pad);
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(hl, _r))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = const Color(0xDD000000));
    canvas.drawRRect(
      RRect.fromRectAndRadius(hl, _r),
      Paint()
        ..color       = AppColors.gold.withValues(alpha: 0.55)
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 1.5);
  }

  @override bool shouldRepaint(_SpotlightPainter o) => o.highlight != highlight;
}

// ── Callout box ───────────────────────────────────────────────────────────────

class _CalloutBox extends StatelessWidget {
  final TutorialStep  step;
  final int           stepIndex;
  final int           stepCount;
  final VoidCallback  onNext;
  final VoidCallback? onPrev;
  final VoidCallback  onSkip;

  const _CalloutBox({
    required this.step,    required this.stepIndex, required this.stepCount,
    required this.onNext,  required this.onSkip,    this.onPrev});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: AppColors.dark,
      border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.5), width: 1.2)),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Title + Skip ──────────────────────────────────────────────────
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(step.title,
            style: GoogleFonts.cinzel(
              color: AppColors.gold,
              fontSize: 13, fontWeight: FontWeight.w700))),
          const SizedBox(width: 8),
          _SkipBtn(onTap: onSkip),
        ]),
        const SizedBox(height: 8),
        // ── Body ──────────────────────────────────────────────────────────
        Text(step.body,
          style: GoogleFonts.cinzel(
            color: AppColors.grey.withValues(alpha: 0.82),
            fontSize: 11, height: 1.55)),
        const SizedBox(height: 12),
        // ── Navigation ────────────────────────────────────────────────────
        Row(children: [
          if (onPrev != null)
            _NavChip(label: '← Back', onTap: onPrev!, isAccent: false)
          else
            const SizedBox.shrink(),
          const Spacer(),
          Text('${stepIndex + 1} / $stepCount',
            style: GoogleFonts.cinzel(
              color: AppColors.grey.withValues(alpha: 0.4), fontSize: 10)),
          const Spacer(),
          _NavChip(
            label: stepIndex == stepCount - 1 ? 'Done' : 'Next →',
            onTap: onNext,
            isAccent: true),
        ]),
      ]));
}

// ── Skip button ───────────────────────────────────────────────────────────────

class _SkipBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _SkipBtn({required this.onTap});
  @override State<_SkipBtn> createState() => _SkipBtnState();
}
class _SkipBtnState extends State<_SkipBtn> {
  bool _h = false;
  @override Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _h = true),
    onExit:  (_) => setState(() => _h = false),
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: widget.onTap,
      child: Text('Skip',
        style: GoogleFonts.cinzel(
          color: _h
            ? AppColors.grey.withValues(alpha: 0.75)
            : AppColors.grey.withValues(alpha: 0.35),
          fontSize: 10))));
}

// ── Navigation chip ───────────────────────────────────────────────────────────

class _NavChip extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool isAccent;
  const _NavChip({required this.label, required this.onTap, required this.isAccent});
  @override State<_NavChip> createState() => _NavChipState();
}
class _NavChipState extends State<_NavChip> {
  bool _h = false;
  @override Widget build(BuildContext context) {
    final on  = _h || widget.isAccent;
    final col = widget.isAccent ? AppColors.gold : AppColors.grey;
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: on ? col.withValues(alpha: 0.12) : Colors.transparent,
            border: Border.all(
              color: on ? col.withValues(alpha: 0.65) : col.withValues(alpha: 0.3))),
          child: Text(widget.label,
            style: GoogleFonts.cinzel(
              color: on ? col : col.withValues(alpha: 0.6),
              fontSize: 11,
              fontWeight: widget.isAccent ? FontWeight.w600 : FontWeight.w400)))));
  }
}

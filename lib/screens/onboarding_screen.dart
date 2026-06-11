import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const OnboardingScreen({super.key, required this.onComplete});
  @override State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _ctrl = PageController();
  int _page = 0;

  static const _steps = [
    _Step(
      icon: Icons.auto_awesome,
      title: 'Welcome to Aetherra',
      body: 'Your digital war council for tabletop battles. Track armies, manage activations and roll dice — all in one place.',
    ),
    _Step(
      icon: Icons.shield_outlined,
      title: 'Build your Army',
      body: 'Create armies from factions, pick units, customise names and photos. Your armies are saved and ready whenever you play.',
    ),
    _Step(
      icon: Icons.flag_outlined,
      title: 'Go to Battle',
      body: 'Play a local game to track your battle, or challenge a friend online using a room code — live and in sync.',
    ),
    _Step(
      icon: Icons.help_outline,
      title: 'Built-in Tutorial',
      body: 'Each game screen has a ? button in the top bar. Tap it anytime to get a guided tour of every control.',
    ),
  ];

  void _next() {
    if (_page < _steps.length - 1) {
      _ctrl.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut);
    } else {
      widget.onComplete();
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _steps.length - 1;
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(
        child: Column(children: [
          // Skip button
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 16, 0),
              child: isLast
                ? const SizedBox(height: 36)
                : _SkipBtn(onTap: widget.onComplete))),

          // Pages
          Expanded(
            child: PageView.builder(
              controller: _ctrl,
              onPageChanged: (i) => setState(() => _page = i),
              itemCount: _steps.length,
              itemBuilder: (_, i) => _StepPage(step: _steps[i]))),

          // Dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_steps.length, (i) =>
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 20),
                width:  _page == i ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _page == i
                    ? AppColors.gold
                    : AppColors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(3))))),

          // Button
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
            child: _NextBtn(
              label: isLast ? 'Get Started' : 'Next',
              onTap: _next)),
        ])));
  }
}

// ── Step data ─────────────────────────────────────────────────────────────────

class _Step {
  final IconData icon;
  final String   title;
  final String   body;
  const _Step({required this.icon, required this.title, required this.body});
}

// ── Step page ─────────────────────────────────────────────────────────────────

class _StepPage extends StatelessWidget {
  final _Step step;
  const _StepPage({required this.step});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 40),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Icon
        Container(
          width: 88, height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.gold.withValues(alpha: 0.35), width: 1.5),
            color: AppColors.gold.withValues(alpha: 0.07)),
          child: Icon(step.icon, color: AppColors.gold, size: 40)),
        const SizedBox(height: 36),
        // Title
        Text(step.title,
          textAlign: TextAlign.center,
          style: GoogleFonts.cinzel(
            color: AppColors.gold,
            fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 1)),
        const SizedBox(height: 20),
        // Body
        Container(height: 1, width: 40,
          color: AppColors.gold.withValues(alpha: 0.3)),
        const SizedBox(height: 20),
        Text(step.body,
          textAlign: TextAlign.center,
          style: GoogleFonts.cinzel(
            color: AppColors.grey.withValues(alpha: 0.75),
            fontSize: 13, height: 1.7)),
      ]));
}

// ── Next / Get Started button ─────────────────────────────────────────────────

class _NextBtn extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _NextBtn({required this.label, required this.onTap});
  @override State<_NextBtn> createState() => _NextBtnState();
}
class _NextBtnState extends State<_NextBtn> {
  bool _hovered = false, _pressed = false;
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
          duration: const Duration(milliseconds: 100),
          transform: _pressed
            ? (Matrix4.identity()..scaleByDouble(0.97, 0.97, 1.0, 1.0))
            : Matrix4.identity(),
          transformAlignment: Alignment.center,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _pressed
              ? AppColors.gold.withValues(alpha: 0.45)
              : AppColors.gold.withValues(alpha: _hovered ? 0.65 : 1.0)),
          child: Text(widget.label,
            textAlign: TextAlign.center,
            style: GoogleFonts.cinzel(
              color: AppColors.dark,
              fontSize: 13, letterSpacing: 3, fontWeight: FontWeight.w600)))));
}

// ── Skip button ───────────────────────────────────────────────────────────────

class _SkipBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _SkipBtn({required this.onTap});
  @override State<_SkipBtn> createState() => _SkipBtnState();
}
class _SkipBtnState extends State<_SkipBtn> {
  bool _hovered = false;
  @override Widget build(BuildContext context) =>
    MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          height: 36,
          child: Center(
            child: Text('Skip',
              style: GoogleFonts.cinzel(
                color: _hovered
                  ? AppColors.grey.withValues(alpha: 0.65)
                  : AppColors.grey.withValues(alpha: 0.35),
                fontSize: 12, letterSpacing: 1))))));
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_theme.dart';

/// Gold "New …" button used at the bottom of dev/my-factions tabs.
class CrudCreateBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const CrudCreateBtn({super.key, required this.icon, required this.label, required this.onTap});
  @override State<CrudCreateBtn> createState() => _CrudCreateBtnState();
}
class _CrudCreateBtnState extends State<CrudCreateBtn> {
  bool _hovered = false;
  bool _pressed = false;
  @override Widget build(BuildContext context) => Center(
    child: MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown:   (_) => setState(() => _pressed = true),
        onTapUp:     (_) { setState(() => _pressed = false); widget.onTap(); },
        onTapCancel: ()  => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28),
          decoration: BoxDecoration(
            color: _pressed
                ? AppColors.gold.withValues(alpha: 0.75)
                : _hovered
                    ? AppColors.gold.withValues(alpha: 0.88)
                    : AppColors.gold,
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
            ]),
          child: Text(widget.label, style: GoogleFonts.cinzel(
            color: AppColors.dark, fontSize: 13, letterSpacing: 1.1,
            fontWeight: FontWeight.w600))))));
}

/// Small icon button with hover-opacity used in row-card action menus.
class CrudActionBtn extends StatefulWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const CrudActionBtn({super.key, required this.icon, required this.color, required this.onTap});
  @override State<CrudActionBtn> createState() => _CrudActionBtnState();
}
class _CrudActionBtnState extends State<CrudActionBtn> {
  bool _hovered = false;
  @override Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit:  (_) => setState(() => _hovered = false),
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Icon(widget.icon,
          color: widget.color.withValues(alpha: _hovered ? 1.0 : widget.color.a),
          size: 17))));
}

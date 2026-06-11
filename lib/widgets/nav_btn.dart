import '../app_theme.dart';
import 'package:flutter/material.dart';

class NavBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double? width;
  const NavBtn({super.key, required this.icon, required this.onPressed, this.size = 48, this.width});
  @override State<NavBtn> createState() => _NavBtnState();
}

class _NavBtnState extends State<NavBtn> {
  bool _hovered = false;
  bool _pressed = false;

  @override Widget build(BuildContext context) =>
    Theme(
      data: Theme.of(context).copyWith(
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        hoverColor: Colors.transparent),
      child: InkWell(
        onTap: widget.onPressed,
        onHover: (v) => setState(() => _hovered = v),
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: SizedBox(
          width: widget.width ?? widget.size, height: widget.size,
          child: Center(child: AnimatedOpacity(
            opacity: widget.onPressed == null ? 0.25 : _pressed ? 0.4 : _hovered ? 1.0 : 0.7,
            duration: const Duration(milliseconds: 80),
            child: Icon(widget.icon, color: AppColors.gold, size: widget.size * 0.46))))));
}

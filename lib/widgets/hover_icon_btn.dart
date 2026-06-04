import '../app_theme.dart';
import 'package:flutter/material.dart';

/// Clickable icon with no hover background â€” icon opacity animates on hover.
/// Normal: [normalOpacity]. Hover: 1.0. Press: 0.55. Disabled: 0.25.
class HoverIconBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final double size;
  final double normalOpacity;
  final EdgeInsetsGeometry padding;

  const HoverIconBtn({
    super.key,
    required this.icon,
    this.onTap,
    this.color = AppColors.gold,
    this.size = 20,
    this.normalOpacity = 0.45,
    this.padding = EdgeInsets.zero,
  });

  @override State<HoverIconBtn> createState() => _HoverIconBtnState();
}

class _HoverIconBtnState extends State<HoverIconBtn> {
  bool _hovered = false;
  bool _pressed = false;

  @override Widget build(BuildContext context) =>
    MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: widget.onTap != null
        ? SystemMouseCursors.click
        : MouseCursor.defer,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown:   (_) => setState(() => _pressed = true),
        onTapUp:     (_) => setState(() => _pressed = false),
        onTapCancel: ()  => setState(() => _pressed = false),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Center(
            child: Padding(
              padding: widget.padding,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 80),
                opacity: widget.onTap == null ? 0.25
                  : _pressed ? 0.55
                  : _hovered  ? 1.0
                  : widget.normalOpacity,
                child: Icon(widget.icon, color: widget.color, size: widget.size)))))));
}

import 'package:flutter/material.dart';
import '../app_theme.dart';

/// Standard text field for the app with hover-sensitive border.
/// Default: gold(0.2) border. Hover: gold(0.55). Focused: gold.
class AetherraTextField extends StatefulWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final TextStyle? style;
  final TextStyle? hintStyle;
  final TextInputType? keyboardType;
  final bool readOnly;
  final bool autofocus;
  final int? minLines;
  final int? maxLines;
  final bool isDense;
  final TextAlign textAlign;
  final EdgeInsetsGeometry contentPadding;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final bool clearable;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;

  const AetherraTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.style,
    this.hintStyle,
    this.keyboardType,
    this.readOnly = false,
    this.autofocus = false,
    this.minLines,
    this.maxLines = 1,
    this.isDense = false,
    this.textAlign = TextAlign.start,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.clearable = false,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  State<AetherraTextField> createState() => _AetherraTextFieldState();
}

class _AetherraTextFieldState extends State<AetherraTextField> {
  bool _hovered      = false;
  bool _clearHovered = false;

  @override
  void initState() {
    super.initState();
    if (widget.clearable) widget.controller?.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(AetherraTextField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller || old.clearable != widget.clearable) {
      old.controller?.removeListener(_rebuild);
      if (widget.clearable) widget.controller?.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final hasText = widget.clearable &&
        (widget.controller?.text.isNotEmpty ?? false);
    final effectiveSuffix = hasText
        ? MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _clearHovered = true),
            onExit:  (_) => setState(() => _clearHovered = false),
            child: GestureDetector(
              onTap: () {
                widget.controller?.clear();
                widget.onChanged?.call('');
              },
              child: Icon(Icons.close, size: 16,
                color: _clearHovered ? AppColors.textLight : AppColors.grey)))
        : widget.suffixIcon;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.text,
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        keyboardType: widget.keyboardType,
        readOnly: widget.readOnly,
        autofocus: widget.autofocus,
        obscureText: widget.obscureText,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        textAlign: widget.textAlign,
        style: widget.style ?? const TextStyle(color: AppColors.textLight, fontSize: 17),
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: widget.hintStyle ?? const TextStyle(color: AppColors.grey),
          prefixIcon: widget.prefixIcon,
          suffixIcon: effectiveSuffix,
          suffixIconConstraints: (!hasText && widget.suffixIcon != null)
            ? const BoxConstraints(maxWidth: 44, maxHeight: 44)
            : null,
          filled: true,
          fillColor: AppColors.dark,
          isDense: widget.isDense,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: AppColors.gold.withValues(alpha: 0.2))),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(
              color: _hovered
                ? AppColors.gold.withValues(alpha: 0.55)
                : AppColors.gold.withValues(alpha: 0.2))),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: AppColors.gold)),
          contentPadding: widget.contentPadding),
      ),
    );
  }
}

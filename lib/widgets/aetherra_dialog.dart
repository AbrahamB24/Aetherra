import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_theme.dart';

// â”€â”€ Animated show helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

/// Show a simple titled dialog with the Aetherra animation + style.
Future<T?> showAetherraDialog<T>(BuildContext context, {
  required String title,
  required Widget content,
  List<Widget> actions = const [],
  bool barrierDismissible = true,
}) => _show<T>(context,
      aetherraDialogContainer(title: title, content: content, actions: actions),
      barrierDismissible: barrierDismissible);

/// Show any widget as a dialog with the Aetherra animation.
Future<T?> showAetherraDialogRaw<T>(BuildContext context, Widget dialog,
    {bool barrierDismissible = true}) =>
  _show<T>(context, dialog, barrierDismissible: barrierDismissible);

Future<T?> _show<T>(BuildContext context, Widget dialog,
    {bool barrierDismissible = true}) =>
  showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: '',
    barrierColor: Colors.black.withValues(alpha: 0.72),
    transitionDuration: const Duration(milliseconds: 200),
    transitionBuilder: (_, anim, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween(begin: 0.94, end: 1.0).animate(
          CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child)),
    pageBuilder: (_, __, ___) => dialog);

// â”€â”€ Styled container â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Widget aetherraDialogContainer({
  required String title,
  required Widget content,
  List<Widget> actions = const [],
  Color? titleColor,
}) =>
  Dialog(
    backgroundColor: Colors.transparent,
    elevation: 0,
    insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1208),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.55), width: 1.5),
        boxShadow: [BoxShadow(
          color: AppColors.gold.withValues(alpha: 0.10), blurRadius: 32)]),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.cinzel(
            color: titleColor ?? AppColors.gold, fontSize: 16)),
          const SizedBox(height: 12),
          content,
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
          ],
        ])));

// â”€â”€ Styled button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

/// Text-only button for dialogs: hover brightens, no background.
Widget aDialogBtn(String label, Color color, VoidCallback? onPressed) =>
  TextButton(
    style: ButtonStyle(
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      foregroundColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.hovered) ? color : color.withValues(alpha: 0.75))),
    onPressed: onPressed,
    child: Text(label, style: GoogleFonts.cinzel()));

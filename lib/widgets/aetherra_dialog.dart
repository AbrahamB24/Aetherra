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

// ── Confirmation bottom sheet ─────────────────────────────────────────────────

/// One button in a [showAetherraSheet] bottom sheet.
class SheetAction {
  final String        label;
  final Color         color;
  final VoidCallback? onTap;
  final bool          outlined;
  const SheetAction(this.label, this.color, this.onTap, {this.outlined = false});
}

/// Show a confirmation bottom sheet in the same style as the edit-unit sheet:
/// drag handle → Cinzel title → body → full-width (or side-by-side) buttons.
Future<T?> showAetherraSheet<T>(
  BuildContext context, {
  required String       title,
  required Widget       body,
  List<SheetAction>     actions       = const [],
  bool                  isDismissible = true,
  Color?                titleColor,
}) {
  final safeBottom = MediaQuery.of(context).padding.bottom;
  return showModalBottomSheet<T>(
    context:            context,
    isScrollControlled: true,
    isDismissible:      isDismissible,
    backgroundColor:    AppColors.dark,
    builder: (ctx) {
      final kb = MediaQuery.of(ctx).viewInsets.bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, safeBottom + kb + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.grey.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(title, style: GoogleFonts.cinzel(
              color: titleColor ?? AppColors.gold, fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            body,
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 20),
              if (actions.length == 2)
                Row(children: [
                  Expanded(child: _sheetBtn(actions[0])),
                  const SizedBox(width: 12),
                  Expanded(child: _sheetBtn(actions[1])),
                ])
              else
                ...actions.map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(width: double.infinity, child: _sheetBtn(a)))),
            ],
          ]));
    });
}

Widget _sheetBtn(SheetAction a) => a.outlined
  ? OutlinedButton(
      onPressed: a.onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: a.color,
        side: BorderSide(color: a.color.withValues(alpha: 0.4)),
        shape: const RoundedRectangleBorder(),
        padding: const EdgeInsets.symmetric(vertical: 14)),
      child: Text(a.label, style: GoogleFonts.cinzel(fontSize: 14)))
  : ElevatedButton(
      onPressed: a.onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: a.color,
        foregroundColor: a.color == AppColors.gold ? AppColors.dark : Colors.white,
        shape: const RoundedRectangleBorder(),
        padding: const EdgeInsets.symmetric(vertical: 14)),
      child: Text(a.label, style: GoogleFonts.cinzel(
        fontSize: 14, fontWeight: FontWeight.w600)));

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_theme.dart';
import 'aetherra_dialog.dart';

class GroupTrashBtn extends StatefulWidget {
  final String groupName;
  final VoidCallback onDelete;
  const GroupTrashBtn({super.key, required this.groupName, required this.onDelete});
  @override State<GroupTrashBtn> createState() => _GroupTrashBtnState();
}

class _GroupTrashBtnState extends State<GroupTrashBtn> {
  bool _hovered = false;

  void _tap() {
    showAetherraSheet<bool>(
      context,
      title: 'Delete Cohort?',
      body: Text(
        'Delete "${widget.groupName}"? All units in this cohort will be disbanded.',
        style: GoogleFonts.cinzel(color: AppColors.grey, fontSize: 13, height: 1.5),
      ),
      actions: [
        SheetAction('Cancel', AppColors.grey, () => Navigator.pop(context, false), outlined: true),
        SheetAction('Delete', Colors.red,     () => Navigator.pop(context, true)),
      ],
    ).then((ok) { if (ok ?? false) widget.onDelete(); });
  }

  @override Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _tap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Center(
            child: Icon(
              Icons.delete_outline,
              color: Colors.red.withValues(alpha: _hovered ? 1.0 : 0.45),
              size: 14,
            ),
          ),
        ),
      ),
    );
  }
}

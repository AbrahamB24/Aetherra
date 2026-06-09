import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_theme.dart';

/// Generic multi-select filter button with animated overlay dropdown.
/// Mirrors the _FilterDropdown pattern from builder_screen.dart.
class FilterBtn extends StatefulWidget {
  final String allLabel;
  final List<MapEntry<String, String>> options;
  final Map<String, Color>? dotColors;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool compact;
  const FilterBtn({
    super.key,
    required this.allLabel,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.dotColors,
    this.compact = false,
  });
  @override State<FilterBtn> createState() => _FilterBtnState();
}
class _FilterBtnState extends State<FilterBtn> {
  static const gold = AppColors.gold;
  OverlayEntry? _entry;
  final _link = LayerLink();
  late final ValueNotifier<Set<String>> _sel =
      ValueNotifier(Set<String>.from(widget.selected));

  @override void didUpdateWidget(FilterBtn old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sel.value = Set<String>.from(widget.selected);
    });
  }

  @override void dispose() {
    _entry?.remove(); _entry = null;
    _sel.dispose();
    super.dispose();
  }

  void _toggle() => _entry == null ? _open() : _close();

  void _open() {
    _entry = OverlayEntry(builder: (_) => _FilterDropMenu(
      link: _link,
      options: widget.options,
      dotColors: widget.dotColors,
      sel: _sel,
      onToggle: (key) {
        final next = Set<String>.from(_sel.value);
        if (next.contains(key)) { next.remove(key); } else { next.add(key); }
        _sel.value = next;
        widget.onChanged(Set<String>.from(next));
      },
      onClose: _close,
    ));
    Overlay.of(context).insert(_entry!);
    setState(() {});
  }

  void _close() {
    _entry?.remove(); _entry = null;
    if (mounted) setState(() {});
  }

  bool _hovered = false;

  @override Widget build(BuildContext context) => CompositedTransformTarget(
    link: _link,
    child: MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _toggle,
        child: ValueListenableBuilder<Set<String>>(
          valueListenable: _sel,
          builder: (_, sel, __) {
            final label = sel.isEmpty ? widget.allLabel
              : sel.length == 1
                ? (widget.options
                    .firstWhere((e) => e.key == sel.first,
                      orElse: () => MapEntry(sel.first, sel.first))
                    .value)
              : '${sel.length} selected';
            final hPad = widget.compact ? 5.0 : 10.0;
            final iconSz = widget.compact ? 12.0 : 15.0;
            final chevSz = widget.compact ? 11.0 : 14.0;
            final fs = widget.compact ? 11.0 : 12.0;
            final gap1 = widget.compact ? 3.0 : 5.0;
            final gap2 = widget.compact ? 2.0 : 4.0;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 5),
              decoration: BoxDecoration(
                color: (_hovered || sel.isNotEmpty)
                  ? gold.withValues(alpha: 0.12) : Colors.transparent),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.filter_list, color: gold, size: iconSz),
                SizedBox(width: gap1),
                Text(label,
                  style: GoogleFonts.cinzel(color: gold, fontSize: fs),
                  maxLines: 1),
                SizedBox(width: gap2),
                Icon(_entry != null ? Icons.expand_less : Icons.expand_more,
                  color: gold, size: chevSz),
              ]));
          }))));
}

/// Sort popup button — identical to the sort button in builder_screen.dart.
class SortBtn extends StatefulWidget {
  final String sortBy;
  final bool ascending;
  final List<List<String>> options; // [[key, label], ...]
  final ValueChanged<String> onSelected;
  final bool compact;
  const SortBtn({
    super.key,
    required this.sortBy,
    required this.ascending,
    required this.options,
    required this.onSelected,
    this.compact = false,
  });
  @override State<SortBtn> createState() => _SortBtnState();
}
class _SortBtnState extends State<SortBtn> {
  static const gold = AppColors.gold;
  bool _hovered = false;

  @override Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit:  (_) => setState(() => _hovered = false),
    cursor: SystemMouseCursors.click,
    child: Theme(
      data: Theme.of(context).copyWith(
        splashFactory:  NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        splashColor:    Colors.transparent,
        hoverColor:     Colors.transparent),
      child: PopupMenuButton<String>(
        color: AppColors.dark,
        enableFeedback: false,
        tooltip: '',
        iconSize: 0,
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.under,
        onSelected: widget.onSelected,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 6 : 10, vertical: 4),
          decoration: BoxDecoration(
            color: _hovered ? gold.withValues(alpha: 0.12) : Colors.transparent),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.sort, color: gold, size: widget.compact ? 14 : 16),
            if (!widget.compact) ...[
              const SizedBox(width: 4),
              Text('Sort', style: GoogleFonts.cinzel(color: gold, fontSize: 13)),
            ],
          ])),
        itemBuilder: (_) => [
          for (final s in widget.options)
            PopupMenuItem(
              value: s[0],
              padding: EdgeInsets.zero,
              child: FilterSortItem(
                label: s[1],
                active: widget.sortBy == s[0],
                ascending: widget.sortBy == s[0] && widget.ascending)),
        ])));
}

// ── Overlay drop menu ──────────────────────────────────────────────────────
class _FilterDropMenu extends StatelessWidget {
  final LayerLink link;
  final List<MapEntry<String, String>> options;
  final Map<String, Color>? dotColors;
  final ValueNotifier<Set<String>> sel;
  final void Function(String) onToggle;
  final VoidCallback onClose;
  const _FilterDropMenu({
    required this.link, required this.options, required this.sel,
    required this.onToggle, required this.onClose, this.dotColors,
  });

  @override Widget build(BuildContext context) => Stack(children: [
    Positioned.fill(child: GestureDetector(
      behavior: HitTestBehavior.opaque, onTap: onClose,
      child: const SizedBox.expand())),
    CompositedTransformFollower(
      link: link,
      showWhenUnlinked: false,
      offset: const Offset(0, 36),
      child: Material(color: Colors.transparent,
        child: Container(
          width: 180,
          decoration: BoxDecoration(
            color: AppColors.dark,
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.4))),
          child: ValueListenableBuilder<Set<String>>(
            valueListenable: sel,
            builder: (_, current, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: options.map<Widget>((e) => FilterCheckItem(
                text: e.value,
                dotColor: dotColors?[e.key],
                checked: current.contains(e.key),
                onTap: () => onToggle(e.key),
              )).toList()))))),
  ]);
}

/// Hover-aware checkbox row used inside FilterBtn dropdown.
class FilterCheckItem extends StatefulWidget {
  final String text;
  final Color? dotColor;
  final bool checked;
  final VoidCallback onTap;
  const FilterCheckItem({
    super.key,
    required this.text,
    required this.checked,
    required this.onTap,
    this.dotColor,
  });
  @override State<FilterCheckItem> createState() => _FilterCheckItemState();
}
class _FilterCheckItemState extends State<FilterCheckItem> {
  static const _gold = AppColors.gold;
  bool _hovered = false;

  @override Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit:  (_) => setState(() => _hovered = false),
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Container(
        width: double.infinity,
        color: _hovered && !widget.checked
          ? _gold.withValues(alpha: 0.06) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(children: [
          Container(
            width: 14, height: 14,
            decoration: BoxDecoration(
              color: widget.checked ? _gold : Colors.transparent,
              border: Border.all(
                color: _gold.withValues(
                  alpha: _hovered && !widget.checked ? 0.75 : 0.5))),
            child: widget.checked
              ? const Icon(Icons.check, color: AppColors.dark, size: 11)
              : _hovered
                ? Icon(Icons.check, color: _gold.withValues(alpha: 0.3), size: 11)
                : null),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.text,
            style: GoogleFonts.cinzel(
              color: widget.checked ? _gold
                : _hovered ? _gold.withValues(alpha: 0.65)
                : AppColors.grey,
              fontSize: 12),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]))));
}

/// Magnifier toggle button — highlights when open or has an active query.
class SearchToggleBtn extends StatefulWidget {
  final bool isOpen;
  final bool hasQuery;
  final VoidCallback onTap;
  final bool compact;
  const SearchToggleBtn({
    super.key,
    required this.isOpen,
    required this.hasQuery,
    required this.onTap,
    this.compact = false,
  });
  @override State<SearchToggleBtn> createState() => _SearchToggleBtnState();
}
class _SearchToggleBtnState extends State<SearchToggleBtn> {
  static const gold = AppColors.gold;
  bool _hovered = false;
  @override Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit:  (_) => setState(() => _hovered = false),
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 5 : 8, vertical: 5),
        decoration: BoxDecoration(
          color: (_hovered || widget.isOpen || widget.hasQuery)
            ? gold.withValues(alpha: 0.12) : Colors.transparent),
        child: Icon(Icons.search, color: gold,
          size: widget.compact ? 13 : 15))));
}

/// Hover-aware sort popup item used inside SortBtn.
class FilterSortItem extends StatefulWidget {
  final String label;
  final bool   active;
  final bool   ascending;
  const FilterSortItem({
    super.key,
    required this.label,
    required this.active,
    this.ascending = true,
  });
  @override State<FilterSortItem> createState() => _FilterSortItemState();
}
class _FilterSortItemState extends State<FilterSortItem> {
  static const _gold = AppColors.gold;
  bool _hovered = false;
  @override Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit:  (_) => setState(() => _hovered = false),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      color: _hovered && !widget.active
        ? _gold.withValues(alpha: 0.08) : null,
      child: Row(children: [
        Expanded(child: Text(widget.label, style: GoogleFonts.cinzel(
          color: widget.active ? _gold
            : _hovered ? _gold.withValues(alpha: 0.75)
            : AppColors.greyLight,
          fontSize: 13))),
        if (widget.active)
          Icon(
            widget.ascending ? Icons.arrow_upward : Icons.arrow_downward,
            color: _gold, size: 11),
      ])));
}

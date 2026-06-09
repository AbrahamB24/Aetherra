import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_theme.dart';
import 'aetherra_text_field.dart';
import 'unit_card.dart';

class AbilityPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> allAbilities;
  final List<String> initialSelected;
  final Map<String, dynamic> Function(List<String>) unitDataBuilder;

  const AbilityPickerSheet({
    super.key,
    required this.allAbilities,
    required this.initialSelected,
    required this.unitDataBuilder,
  });

  @override
  State<AbilityPickerSheet> createState() => _AbilityPickerSheetState();
}

class _AbilityPickerSheetState extends State<AbilityPickerSheet> {
  late List<String> _selected;
  final _searchCtrl = TextEditingController();
  String _search   = '';
  String _sortMode    = 'name';
  bool   _sortAsc     = true;
  bool   _sortHovered = false;

  static const _sortOptions = [
    ('name',  'Name'),
    ('cost',  'Points'),
  ];

  String get _sortLabel {
    final label = _sortOptions
        .firstWhere((o) => o.$1 == _sortMode, orElse: () => _sortOptions.first)
        .$2;
    return '$label ${_sortAsc ? '↑' : '↓'}';
  }

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.initialSelected);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.toLowerCase();
    var list = widget.allAbilities.where((a) {
      if (q.isEmpty) return true;
      return (a['name'] as String).toLowerCase().contains(q) ||
          (a['description'] as String? ?? '').toLowerCase().contains(q);
    }).toList();

    if (_sortMode == 'cost') {
      list.sort((a, b) =>
          (a['cost'] as int? ?? 0).compareTo(b['cost'] as int? ?? 0));
    } else {
      list.sort((a, b) =>
          (a['name'] as String).compareTo(b['name'] as String));
    }
    if (!_sortAsc) list = list.reversed.toList();

    // Selected abilities always come first within the chosen sort order
    list.sort((a, b) {
      final aOn = _selected.contains(a['name'] as String);
      final bOn = _selected.contains(b['name'] as String);
      if (aOn && !bOn) return -1;
      if (!aOn && bOn) return 1;
      return 0;
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final unitData = widget.unitDataBuilder(_selected);
    final filtered = _filtered;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.93,
      builder: (_, scroll) => Column(children: [
        // ── Sticky header ─────────────────────────────────────────
        Container(
          color: AppColors.dark,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                        color: AppColors.grey.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2)))),
            Text('Manage Abilities',
                style: GoogleFonts.cinzel(
                    color: AppColors.gold,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1)),
            const SizedBox(height: 12),
            RosterCard(unitData: unitData),
            // ── Selected abilities (reorderable) ───────────────────
            if (_selected.isNotEmpty) ...[
              const SizedBox(height: 10),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                padding: EdgeInsets.zero,
                proxyDecorator: (child, _, __) => Material(
                  color: Colors.transparent, child: child),
                onReorder: (oldIdx, newIdx) {
                  setState(() {
                    if (newIdx > oldIdx) newIdx--;
                    final item = _selected.removeAt(oldIdx);
                    _selected.insert(newIdx, item);
                  });
                },
                itemCount: _selected.length,
                itemBuilder: (_, i) {
                  final name = _selected[i];
                  final ab = widget.allAbilities.firstWhere(
                    (a) => a['name'] == name,
                    orElse: () => <String, dynamic>{});
                  final cost   = ab['cost']    as int? ?? 0;
                  final cpCost = ab['cp_cost'] as int? ?? 0;
                  final Color c = cost < 0
                    ? const Color(0xFFCF6679)
                    : cpCost > 0 ? AppColors.gold : AppColors.grey;
                  return Container(
                    key: ValueKey(name),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(
                        color: AppColors.grey.withValues(alpha: 0.08)))),
                    child: Row(children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(Icons.drag_handle,
                            color: AppColors.grey.withValues(alpha: 0.45), size: 18))),
                      const SizedBox(width: 6),
                      Expanded(child: Text(name, style: GoogleFonts.cinzel(
                        color: c, fontSize: 12, fontWeight: FontWeight.w600))),
                      GestureDetector(
                        onTap: () => setState(() => _selected.remove(name)),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.close,
                            color: AppColors.grey.withValues(alpha: 0.4), size: 14))),
                    ]),
                  );
                },
              ),
            ],
            const SizedBox(height: 12),
            // ── Search + Sort row ──────────────────────────────────
            Row(children: [
              Expanded(
                  child: AetherraTextField(
                      controller: _searchCtrl,
                      hintText: 'Search abilities…',
                      isDense: true,
                      clearable: true,
                      prefixIcon: const Icon(Icons.search,
                          color: AppColors.grey, size: 16),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 6, horizontal: 10),
                      onChanged: (v) => setState(() => _search = v))),
              const SizedBox(width: 8),
              // Sort dropdown — same style as builder_screen
              MouseRegion(
                  onEnter: (_) => setState(() => _sortHovered = true),
                  onExit:  (_) => setState(() => _sortHovered = false),
                  cursor: SystemMouseCursors.click,
                  child: Theme(
                      data: Theme.of(context).copyWith(
                          splashFactory:  NoSplash.splashFactory,
                          highlightColor: Colors.transparent,
                          splashColor:    Colors.transparent,
                          hoverColor:     Colors.transparent),
                      child: PopupMenuButton<String>(
                          color:          AppColors.dark,
                          enableFeedback: false,
                          tooltip:        '',
                          iconSize:       0,
                          padding:        EdgeInsets.zero,
                          position:       PopupMenuPosition.under,
                          onSelected: (v) => setState(() {
                            if (v == _sortMode) { _sortAsc = !_sortAsc; }
                            else { _sortMode = v; _sortAsc = true; }
                          }),
                          itemBuilder: (_) => [
                            for (final opt in _sortOptions)
                              PopupMenuItem<String>(
                                  value:   opt.$1,
                                  padding: EdgeInsets.zero,
                                  child:   _SortItem(
                                      label:     opt.$2,
                                      active:    _sortMode == opt.$1,
                                      ascending: _sortMode == opt.$1 && _sortAsc)),
                          ],
                          child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                  color: _sortHovered
                                      ? AppColors.gold.withValues(alpha: 0.08)
                                      : Colors.transparent),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.sort,
                                        color: _sortHovered
                                            ? AppColors.gold
                                            : AppColors.grey,
                                        size: 16),
                                    const SizedBox(width: 4),
                                    Text(_sortLabel,
                                        style: GoogleFonts.cinzel(
                                            color: _sortHovered
                                                ? AppColors.gold
                                                : AppColors.grey,
                                            fontSize: 11)),
                                  ]))))),
            ]),
          ])),
        const Divider(color: Color(0xFF2D2820), height: 1),
        // ── Ability list ──────────────────────────────────────────
        Expanded(
            child: ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final a       = filtered[i];
                  final name    = a['name'] as String;
                  final on      = _selected.contains(name);
                  final cost    = a['cost'] as int? ?? 0;
                  final cpCost  = a['cp_cost'] as int? ?? 0;
                  final Color c = cost < 0
                      ? const Color(0xFFCF6679)
                      : cpCost > 0
                          ? AppColors.gold
                          : AppColors.grey;
                  final desc      = a['description'] as String? ?? '';
                  final costLabel = cost != 0
                      ? '${cost > 0 ? '+' : ''}$cost pts'
                      : cpCost != 0
                          ? '${cpCost > 0 ? '+' : ''}$cpCost AP'
                          : '';

                  return InkWell(
                      onTap: () => setState(() {
                            if (on) {
                              _selected.remove(name);
                            } else {
                              _selected.add(name);
                            }
                          }),
                      child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                              border: Border(
                                  bottom: BorderSide(
                                      color: AppColors.grey
                                          .withValues(alpha: 0.08)))),
                          child: Row(children: [
                            Icon(
                                on
                                    ? Icons.check_box
                                    : Icons.check_box_outline_blank,
                                color: on
                                    ? AppColors.gold
                                    : AppColors.grey.withValues(alpha: 0.35),
                                size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(name,
                                      style: GoogleFonts.cinzel(
                                          color: on ? c : AppColors.grey,
                                          fontSize: 13,
                                          fontWeight: on
                                              ? FontWeight.w600
                                              : FontWeight.w400)),
                                  if (desc.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(desc,
                                        style: GoogleFonts.cinzel(
                                            color: AppColors.grey
                                                .withValues(alpha: 0.55),
                                            fontSize: 10,
                                            height: 1.4)),
                                  ],
                                ])),
                            if (costLabel.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(costLabel,
                                  style: GoogleFonts.cinzel(
                                      color: on
                                          ? c
                                          : c.withValues(alpha: 0.5),
                                      fontSize: 11)),
                            ],
                          ])));
                })),
        // ── Done button (sticky) ──────────────────────────────────
        Container(
            color: AppColors.dark,
            padding: EdgeInsets.fromLTRB(
                16, 8, 16, MediaQuery.of(context).padding.bottom + 16),
            child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: AppColors.dark,
                        shape: const RoundedRectangleBorder(),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14)),
                    child: Text(
                        _selected.isEmpty
                            ? 'Done — no abilities'
                            : 'Done (${_selected.length} selected)',
                        style: GoogleFonts.cinzel(
                            fontSize: 14,
                            fontWeight: FontWeight.w600))))),
      ]),
    );
  }
}

// ── Sort popup item ───────────────────────────────────────────────────────────
class _SortItem extends StatefulWidget {
  final String label;
  final bool   active;
  final bool   ascending;
  const _SortItem({required this.label, required this.active,
      this.ascending = true});
  @override State<_SortItem> createState() => _SortItemState();
}

class _SortItemState extends State<_SortItem> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: _hovered && !widget.active
              ? AppColors.gold.withValues(alpha: 0.08)
              : null,
          child: Row(children: [
            Expanded(child: Text(widget.label,
                style: GoogleFonts.cinzel(
                    color: widget.active
                        ? AppColors.gold
                        : _hovered
                            ? AppColors.gold.withValues(alpha: 0.75)
                            : AppColors.greyLight,
                    fontSize: 15))),
            if (widget.active)
              Icon(widget.ascending
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  color: AppColors.gold, size: 11),
          ])));
}

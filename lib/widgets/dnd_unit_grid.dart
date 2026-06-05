import 'dart:async';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/army_state.dart';
import '../services/subscription_service.dart';
import 'unit_card.dart';
import '../app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Architecture:
//  • One outer DragTarget wraps the whole grid → catches ALL drops
//  • Per-card inner DragTarget: onMove only (onWillAccept=false) → tracks cursor
//  • Edge ghost zones at row ends → also track cursor, create phantom position
//  • Placeholder card shown at _insertAt position
// ─────────────────────────────────────────────────────────────────────────────

class DndUnitGrid extends StatefulWidget {
  final List<ArmyUnit> units;
  final List<String> groups;
  final double cardW;
  final int cols;
  final VoidCallback onReorder;
  final Widget Function(String group, bool isDragOver)? groupHeader;
  final Widget Function(ArmyUnit unit)? badge;
  final Widget Function(ArmyUnit unit)? trailingBuilder;
  final void Function(ArmyUnit unit)? onEdit;
  final Set<String> collapsedGroups;

  const DndUnitGrid({super.key,
    required this.units, required this.groups,
    required this.cardW, required this.cols,
    required this.onReorder, this.groupHeader, this.badge, this.trailingBuilder,
    this.onEdit,
    this.collapsedGroups = const {}});

  @override State<DndUnitGrid> createState() => DndUnitGridState();
}

class DndUnitGridState extends State<DndUnitGrid> {
  static const gold = AppColors.gold;

  ArmyUnit? _dragging;
  int?      _insertAt;
  String?   _insertGrp;
  final _scrollCtrl = ScrollController();
  final _listKey    = GlobalKey();
  Timer?    _scrollTimer;

  // Notifier so group headers can subscribe directly (avoids rebuild-order issues)
  final _insertGrpNotifier = ValueNotifier<String?>(null);

  @override void dispose() {
    _insertGrpNotifier.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void startDrag(ArmyUnit u) {
    _insertGrpNotifier.value = null;
    setState(() { _dragging = u; _insertAt = null; _insertGrp = null; });
  }

  void setInsert(int at, String g) {
    if (_insertAt != at || _insertGrp != g) {
      _insertGrpNotifier.value = g;
      setState(() { _insertAt = at; _insertGrp = g; });
    }
  }

  void drop() {
    final u = _dragging;
    if (u != null && _insertAt != null && _insertGrp != null) {
      u.groupName = _insertGrp!;
      final from = widget.units.indexOf(u);
      if (from >= 0) {
        widget.units.removeAt(from);
        final to = (_insertAt! > from ? _insertAt! - 1 : _insertAt!)
          .clamp(0, widget.units.length);
        widget.units.insert(to, u);
        widget.onReorder();
      }
    }
    _insertGrpNotifier.value = null;
    setState(() { _dragging = null; _insertAt = null; _insertGrp = null; });
  }

  double _screenH = 800.0;

  void updateDragY(double globalY) {
    if (!_scrollCtrl.hasClients) return;
    final zone    = _screenH * 0.20;
    const maxSpeed = 16.0;

    _scrollTimer?.cancel();
    _scrollTimer = null;

    if (globalY < zone) {
      final t = 1.0 - (globalY / zone).clamp(0.0, 1.0);
      _scrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
        if (!_scrollCtrl.hasClients) return;
        _scrollCtrl.jumpTo(
          (_scrollCtrl.offset - maxSpeed * t).clamp(0, _scrollCtrl.position.maxScrollExtent));
      });
    } else if (globalY > _screenH - zone) {
      final t = ((globalY - (_screenH - zone)) / zone).clamp(0.0, 1.0);
      _scrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
        if (!_scrollCtrl.hasClients) return;
        _scrollCtrl.jumpTo(
          (_scrollCtrl.offset + maxSpeed * t).clamp(0, _scrollCtrl.position.maxScrollExtent));
      });
    }
  }

  void stopScroll() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
  }

  void cancel() {
    if (_insertAt != null && _insertGrp != null) {
      drop();
    } else {
      _insertGrpNotifier.value = null;
      setState(() { _dragging = null; _insertAt = null; _insertGrp = null; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final allGroups = ['', ...widget.groups];
    // Cache screen height for auto-scroll
    _screenH = MediaQuery.of(context).size.height;
    final rows = <Widget>[];

    // Wrap in Listener to capture drag position globally (web-reliable)
    Widget buildBody() {

    for (final grp in allGroups) {
      final grpUnits = widget.units.where((u) => u.groupName == grp).toList();
      if (grpUnits.isEmpty && grp.isEmpty) continue;

      // Build display: skip dragged, insert placeholder
      final lastIdx = widget.units.lastIndexWhere((u) => u.groupName == grp);
      final endIdx  = lastIdx >= 0 ? lastIdx + 1 : widget.units.length;

      if (grp.isNotEmpty && widget.groupHeader != null) {
        if (widget.collapsedGroups.contains(grp)) {
          rows.add(_collapsedGroupTarget(grp, endIdx));
          continue;
        }
        rows.add(ValueListenableBuilder<String?>(
          valueListenable: _insertGrpNotifier,
          builder: (_, insertGrp, __) =>
            widget.groupHeader!(grp, insertGrp == grp),
        ));
      }

      if (grp.isNotEmpty && widget.collapsedGroups.contains(grp)) continue;

      final display = <_Item>[];
      for (final u in grpUnits) {
        final i = widget.units.indexOf(u);
        if (_insertGrp == grp && _insertAt == i) display.add(const _Item.ph());
        if (u != _dragging) display.add(_Item.card(u, i));
      }
      if (_insertGrp == grp && _insertAt == endIdx) display.add(const _Item.ph());

      final visibleCards = display.where((i) => !i.ph).length;
      if (visibleCards == 0) {
        rows.add(_emptyZone(grp, endIdx));
        continue;
      }

      // Render tile rows
      final totalRows = (display.length / widget.cols).ceil();
      for (int r = 0; r * widget.cols < display.length; r++) {
        final start   = r * widget.cols;
        final end     = (start + widget.cols).clamp(0, display.length);
        final rowItems = display.sublist(start, end);
        final isLastRow = r == totalRows - 1;

        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: ClipRect(child: Row(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cards + placeholders
              ...rowItems.asMap().entries.map((e) {
                final pad = EdgeInsets.only(left: e.key == 0 ? 0 : 8);
                if (e.value.ph) {
                  return Padding(padding: pad,
                  child: _PhCard(cardW: widget.cardW));
                }
                return Padding(padding: pad,
                  child: _Tile(unit: e.value.unit!, absIdx: e.value.absIdx!,
                    grp: grp, cardW: widget.cardW, grid: this,
                    badge: widget.badge, trailingBuilder: widget.trailingBuilder,
                    onEdit: widget.onEdit));
              }),

              // Right ghost zone — Expanded takes remaining space, no overflow
              Expanded(child: DragTarget<ArmyUnit>(
                onWillAcceptWithDetails: (_) => false,
                onMove: (_) => setInsert(
                  isLastRow ? endIdx
                    : (rowItems.last.absIdx != null ? rowItems.last.absIdx! + 1 : endIdx),
                  grp),
                builder: (_, __, ___) => const SizedBox(height: 113))),
            ]))));

      }

      // Bottom drop zone below last row
      rows.add(DragTarget<ArmyUnit>(
        onWillAcceptWithDetails: (_) => false,
        onMove: (_) => setInsert(endIdx, grp),
        builder: (_, __, ___) => SizedBox(
          height: _dragging != null ? 36 : 6,
          width: double.infinity)));
    }

    // Outer DragTarget catches ALL drops — this is the key fix
    return DragTarget<ArmyUnit>(
      onWillAcceptWithDetails: (_) => _dragging != null,
      onAcceptWithDetails: (_) => drop(),
      onLeave: (_) {},
      builder: (ctx, __, ___) => ListView(
        key: _listKey,
        controller: _scrollCtrl,
        padding: const EdgeInsets.all(10),
        children: rows));
    }

    return Listener(
      onPointerMove: (e) {
        if (_dragging != null) updateDragY(e.position.dy);
      },
      onPointerUp: (_) => stopScroll(),
      onPointerCancel: (_) => stopScroll(),
      child: buildBody());
  }

  // ── Collapsed group drop target ───────────────────────────────────
  Widget _collapsedGroupTarget(String grp, int endIdx) {
    return DragTarget<ArmyUnit>(
      onWillAcceptWithDetails: (_) => false,
      onMove: (_) => setInsert(endIdx, grp),
      builder: (_, __, ___) => ValueListenableBuilder<String?>(
        valueListenable: _insertGrpNotifier,
        builder: (_, insertGrp, __) =>
          widget.groupHeader!(grp, insertGrp == grp),
      ),
    );
  }

  // ── Empty group zone ──────────────────────────────────────────────
  Widget _emptyZone(String grp, int insertAt) {
    return DragTarget<ArmyUnit>(
      onWillAcceptWithDetails: (_) => false,
      onMove: (_) => setInsert(insertAt, grp),
      builder: (_, cands, __) {
        final active = _insertGrp == grp && _dragging != null;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: active ? 113 : 18,
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 6),
          child: active ? CustomPaint(
            painter: const _Dashed(gold),
            child: Container(
              color: gold.withValues(alpha: 0.07),
              child: Center(child: Text('Drop here',
                style: GoogleFonts.cinzel(
                  color: gold.withValues(alpha: 0.8), fontSize: 11))))) : null);
      });
  }
}

// ── Item types ────────────────────────────────────────────────────────────
class _Item {
  final ArmyUnit? unit; final int? absIdx; final bool ph;
  const _Item.card(this.unit, this.absIdx) : ph = false;
  const _Item.ph() : unit = null, absIdx = null, ph = true;
}

// ── Placeholder card ──────────────────────────────────────────────────────
class _PhCard extends StatelessWidget {
  final double cardW;
  const _PhCard({required this.cardW});
  @override Widget build(BuildContext context) => SizedBox(
    width: cardW, height: 113,
    child: CustomPaint(painter: const _Dashed(AppColors.gold),
      child: Container(color: AppColors.gold.withValues(alpha: 0.07))));
}

// ── Draggable tile card ────────────────────────────────────────────────────
class _Tile extends StatelessWidget {
  final ArmyUnit unit; final int absIdx; final String grp;
  final double cardW; final DndUnitGridState grid;
  final Widget Function(ArmyUnit)? badge;
  final Widget Function(ArmyUnit)? trailingBuilder;
  final void Function(ArmyUnit)? onEdit;
  const _Tile({required this.unit, required this.absIdx, required this.grp,
    required this.cardW, required this.grid, this.badge, this.trailingBuilder,
    this.onEdit});

  @override Widget build(BuildContext context) {
    final w = cardW < 260 ? 260.0 : cardW;

    return SizedBox(width: w,
      child: DragTarget<ArmyUnit>(
        onWillAcceptWithDetails: (_) => false,
        onMove: (det) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          final local = box.globalToLocal(det.offset);
          grid.setInsert(local.dx < box.size.width / 2 ? absIdx : absIdx + 1, grp);
        },
        builder: (_, __, ___) {
          final feedback = Material(color: Colors.transparent,
            child: Transform.scale(scale: 1.06,
              child: SizedBox(width: w,
                child: UnitCard(unit: unit.unit, customName: unit.customName,
                  photoBase64: unit.photoBase64, bgColor: unit.bgColor,
                  accentColor: AppColors.gold))));
          final ghost = AnimatedOpacity(opacity: 0.2,
            duration: const Duration(milliseconds: 180),
            child: UnitCard(unit: unit.unit, customName: unit.customName,
              photoBase64: unit.photoBase64, bgColor: unit.bgColor));
          final child = Stack(children: [
            UnitCard(unit: unit.unit, customName: unit.customName,
              photoBase64: unit.photoBase64, bgColor: unit.bgColor,
              lore: unit.lore,
              trailing: trailingBuilder != null ? trailingBuilder!(unit) : null,
              onEdit: onEdit != null ? () => onEdit!(unit) : null,
              locked: unit.isEmbedded && !SubscriptionService.isPremium),
            if (badge != null && trailingBuilder == null) badge!(unit),
          ]);
          final isTouch = defaultTargetPlatform == TargetPlatform.android ||
                          defaultTargetPlatform == TargetPlatform.iOS;
          if (!isTouch) {
            return Draggable<ArmyUnit>(
              data: unit,
              onDragStarted: () => grid.startDrag(unit),
              onDragUpdate: (det) => grid.updateDragY(det.globalPosition.dy),
              onDragEnd: (det) { grid.stopScroll(); if (!det.wasAccepted) grid.cancel(); },
              onDraggableCanceled: (_, __) { grid.stopScroll(); grid.cancel(); },
              feedback: feedback, childWhenDragging: ghost, child: child);
          }
          return LongPressDraggable<ArmyUnit>(
            data: unit,
            delay: const Duration(milliseconds: 400),
            onDragStarted: () => grid.startDrag(unit),
            onDragUpdate: (det) => grid.updateDragY(det.globalPosition.dy),
            onDragEnd: (det) { grid.stopScroll(); if (!det.wasAccepted) grid.cancel(); },
            onDraggableCanceled: (_, __) { grid.stopScroll(); grid.cancel(); },
            feedback: feedback, childWhenDragging: ghost, child: child);
        }));
  }
}

// ── Dashed border painter ─────────────────────────────────────────────────
class _Dashed extends CustomPainter {
  final Color color;
  const _Dashed(this.color);
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 1.5..style = PaintingStyle.stroke;
    const d = 7.0, g = 4.0;
    for (final m in (Path()..addRect(Rect.fromLTWH(0,0,size.width,size.height)))
        .computeMetrics()) {
      for (double x = 0; x < m.length; x += d + g) {
        canvas.drawPath(m.extractPath(x, (x+d).clamp(0,m.length)), p);
      }
    }
  }
  @override bool shouldRepaint(_Dashed o) => o.color != color;
}
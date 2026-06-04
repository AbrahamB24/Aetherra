import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/army_state.dart';
import '../services/army_service.dart';
import '../services/game_data_service.dart';
import 'builder_screen.dart';
import '../widgets/aetherra_dialog.dart';
import '../widgets/unit_card.dart';
import '../widgets/hover_icon_btn.dart';
import '../widgets/nav_btn.dart';
import '../widgets/aetherra_text_field.dart';
import '../app_theme.dart';

class NewArmyScreen extends StatefulWidget {
  const NewArmyScreen({super.key});
  @override
  State<NewArmyScreen> createState() => _NewArmyScreenState();
}

class _NewArmyScreenState extends State<NewArmyScreen> {
  static const gold  = AppColors.gold;
      static const grey  = AppColors.grey;

  // Step 0 = Name, Step 1 = Faction, Step 2 = Points
  int    _step = 0;
  String _armyName = '';
  bool   _nameError = false;
  final Set<String> _selectedFactions = {};
  int    _selectedLimit = 2500;
  bool   _customLimit   = false;
  String _creatorName   = '';

  final _nameCtrl   = TextEditingController();
  final _customCtrl = TextEditingController(text: '2500');
  final List<int> _presets = [500, 1000, 1500, 2000, 2500];

  @override
  void initState() {
    super.initState();
    // Refresh faction data in the background while user is on step 0 (Name).
    // By the time they reach step 1 (Faction), images/lore are up-to-date.
    GameDataService.load().then((_) {
      if (mounted) setState(() {});
    });
    final meta = Supabase.instance.client.auth.currentUser?.userMetadata ?? {};
    _creatorName = meta['display_name'] as String?
        ?? meta['full_name'] as String?
        ?? meta['name'] as String?
        ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _customCtrl.dispose();
    super.dispose();
  }

  Future<void> _importArmy() async {
    final codeCtrl = TextEditingController();
    String? errorMsg;
    bool loading = false;

    await showAetherraDialogRaw<void>(context, StatefulBuilder(builder: (ctx, setS) =>
      aetherraDialogContainer(
        title: 'Import Army',
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Enter the 6-character share code:',
            style: GoogleFonts.cinzel(color: grey, fontSize: 13)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(
              controller: codeCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              style: GoogleFonts.cinzel(color: gold, fontSize: 22, letterSpacing: 4),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                counterText: '',
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: gold.withValues(alpha: 0.4))),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: gold)),
                filled: true,
                fillColor: AppColors.dark),
              onChanged: (_) { if (errorMsg != null) setS(() => errorMsg = null); })),
            HoverIconBtn(
              icon: Icons.content_paste_outlined,
              onTap: () async {
                final data = await Clipboard.getData('text/plain');
                final text = (data?.text ?? '').trim().toUpperCase()
                    .replaceAll(RegExp(r'[^A-Z0-9]'), '');
                if (text.isNotEmpty) {
                  codeCtrl.text = text.substring(0, text.length.clamp(0, 6));
                  setS(() => errorMsg = null);
                }
              }),
          ]),
          if (errorMsg != null) ...[
            const SizedBox(height: 8),
            Text(errorMsg!, style: GoogleFonts.cinzel(color: Colors.redAccent, fontSize: 12)),
          ],
        ]),
        actions: [
          aDialogBtn('Cancel', grey, loading ? null : () => Navigator.of(ctx).pop()),
          loading
            ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.gold))
            : aDialogBtn('Import', gold, () async {
                final code = codeCtrl.text.trim().toUpperCase();
                if (code.length != 6) {
                  setS(() => errorMsg = 'Code must be 6 characters.');
                  return;
                }
                setS(() { loading = true; errorMsg = null; });
                final row = await ArmyService.fetchShared(code);
                if (row == null) {
                  setS(() { loading = false; errorMsg = 'Code not found. Check and try again.'; });
                  return;
                }
                await ArmyService.importArmy(row);
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (mounted) Navigator.of(context).pop();
              }),
        ],
      )));
  }

  void _startBuilding() {
    final army  = context.read<ArmyState>();
    final limit = _customLimit
      ? (int.tryParse(_customCtrl.text) ?? 2500)
      : _selectedLimit;
    army.clear();
    army.setLimit(limit);
    army.setFactions(_selectedFactions.toList());
    if (_armyName.trim().isNotEmpty) army.setName(_armyName.trim());
    Navigator.pushReplacement(context,
      MaterialPageRoute(builder: (_) =>
        BuilderScreen(initialFactions: _selectedFactions.toList())));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        leading: NavBtn(
          icon: _step == 0 ? Icons.home_outlined : Icons.arrow_back_ios_new,
          onPressed: () {
            if (_step > 0) {
              setState(() => _step--);
            } else {
              Navigator.of(context).pop();
            }
          }),
        title: Text(
          _step == 0 ? 'Army Name'
          : _step == 1 ? 'Choose Faction'
          : 'Set Points Limit',
          style: GoogleFonts.cinzel(color: gold, fontSize: 17, letterSpacing: 2)),
        actions: [
          NavBtn(icon: Icons.file_download_outlined, onPressed: _importArmy),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(children: [
        // Step indicator
        Container(
          color: AppColors.dark,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            _stepDot(0, 'Name'),
            Expanded(child: Container(height: 1,
              color: _step >= 1
                ? gold.withValues(alpha: 0.5)
                : gold.withValues(alpha: 0.15))),
            _stepDot(1, 'Faction'),
            Expanded(child: Container(height: 1,
              color: _step >= 2
                ? gold.withValues(alpha: 0.5)
                : gold.withValues(alpha: 0.15))),
            _stepDot(2, 'Points'),
          ]),
        ),
        // Content
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _step == 0 ? _nameStep()
            : _step == 1 ? _factionStep()
            : _pointsStep())),
        // Nav buttons
        Container(
          color: AppColors.dark,
          padding: const EdgeInsets.all(14),
          child: PressBtn(
              label: _step == 0 ? 'Next: Choose Faction'
                : _step == 1 ? 'Next: Set Points'
                : 'Start Building',
              onTap: () {
                if (_step == 0 && _armyName.trim().isEmpty) {
                  setState(() => _nameError = true);
                  return;
                }
                if (_step < 2) {
                  setState(() => _step++);
                } else {
                  _startBuilding();
                }
              },
              bg: AppColors.gold,
              fg: AppColors.dark,
              centered: true,
              fontSize: 15,
              padding: const EdgeInsets.symmetric(vertical: 14))),
      ]),
    );
  }

  Widget _stepDot(int step, String label) {
    final active = _step >= step;
    return Column(children: [
      Container(width: 28, height: 28,
        decoration: BoxDecoration(shape: BoxShape.circle,
          color: active ? gold.withValues(alpha: 0.2) : AppColors.dark,
          border: Border.all(
            color: active ? gold : gold.withValues(alpha: 0.2),
            width: 1.5)),
        child: Center(child: Text('${step + 1}',
          style: GoogleFonts.cinzel(fontSize: 15,
            color: active ? gold : grey)))),
      const SizedBox(height: 4),
      Text(label, style: GoogleFonts.cinzel(
        fontSize: 13, letterSpacing: 1,
        color: active ? gold : grey)),
    ]);
  }

  // ── STEP 0: NAME ─────────────────────────────────────
  Widget _nameStep() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Give your army a name:',
        style: GoogleFonts.cinzel(color: grey, fontSize: 12, letterSpacing: 1)),
      const SizedBox(height: 20),
      AetherraTextField(
        controller: _nameCtrl,
        autofocus: true,
        style: GoogleFonts.cinzel(color: AppColors.goldLight, fontSize: 22),
        hintText: 'e.g. Army of Gondor',
        hintStyle: GoogleFonts.cinzel(color: grey, fontSize: 18),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onChanged: (v) => setState(() { _armyName = v; _nameError = false; }),
        onSubmitted: (_) {
          if (_armyName.trim().isNotEmpty) {
            setState(() => _step = 1);
          } else {
            setState(() => _nameError = true);
          }
        }),
      if (_nameError) ...[
        const SizedBox(height: 8),
        Text('A name is required.',
          style: TextStyle(color: Colors.red.shade300, fontSize: 14)),
      ],
    ]);
  }

  // ── STEP 1: FACTION ──────────────────────────────────
  Widget _factionStep() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Choose faction(s) — tap to select multiple:',
        style: GoogleFonts.cinzel(color: grey, fontSize: 12, letterSpacing: 1)),
      const SizedBox(height: 20),
      ...GameDataService.factions.map((f) => _factionCardMap(f)),
      const SizedBox(height: 10),
      _AllFactionsTile(
        active: _selectedFactions.isEmpty,
        onTap: () => setState(() => _selectedFactions.clear()),
      ),
    ]);
  }

  Widget _factionCardMap(Map<String, dynamic> f) {
    final id       = f['id'] as String;
    final selected = _selectedFactions.contains(id);
    return _FacSelectCard(
      f: f,
      selected: selected,
      creatorName: _creatorName,
      onToggle: () => setState(() {
        if (selected) { _selectedFactions.remove(id); }
        else          { _selectedFactions.add(id); }
      }),
    );
  }

  // ── STEP 2: POINTS ───────────────────────────────────
  Widget _pointsStep() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Choose the maximum points for this army:',
        style: GoogleFonts.cinzel(color: grey, fontSize: 12, letterSpacing: 1)),
      const SizedBox(height: 20),
      GridView.count(
        crossAxisCount: 3, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 2.2,
        children: [
          ..._presets.map((p) => _presetTile(p)),
          _customTile(),
        ],
      ),
      if (_customLimit) ...[
        const SizedBox(height: 16),
        Text('Custom Points Limit:',
          style: GoogleFonts.cinzel(
            color: grey, fontSize: 14, letterSpacing: 1.2)),
        const SizedBox(height: 6),
        AetherraTextField(
          controller: _customCtrl,
          keyboardType: TextInputType.number,
          style: GoogleFonts.cinzel(color: AppColors.goldLight, fontSize: 22),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
      ],
      const SizedBox(height: 20),
    ]);
  }

  Widget _presetTile(int pts) {
    final active = !_customLimit && _selectedLimit == pts;
    return _PointsTile(
      active: active,
      label: '$pts',
      onTap: () => setState(() { _selectedLimit = pts; _customLimit = false; }),
    );
  }

  Widget _customTile() => _PointsTile(
    active: _customLimit,
    label: 'Custom',
    onTap: () => setState(() => _customLimit = true),
  );
}

class _PointsTile extends StatefulWidget {
  final bool active;
  final String label;
  final VoidCallback onTap;
  const _PointsTile({required this.active, required this.label, required this.onTap});
  @override State<_PointsTile> createState() => _PointsTileState();
}

class _PointsTileState extends State<_PointsTile> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown:   (_) => setState(() => _pressed = true),
        onTapUp:     (_) { setState(() => _pressed = false); widget.onTap(); },
        onTapCancel: ()  => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          transform: _pressed
            ? (Matrix4.identity()..scaleByDouble(0.97, 0.97, 1, 1))
            : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.active
              ? AppColors.gold.withValues(alpha: 0.15)
              : _hovered
                ? AppColors.gold.withValues(alpha: 0.08)
                : Colors.transparent,
            border: Border.all(
              color: widget.active || _hovered
                ? AppColors.gold
                : AppColors.gold.withValues(alpha: 0.35))),
          child: Center(child: Text(widget.label,
            style: GoogleFonts.cinzel(
              fontSize: widget.label == 'Custom' ? 16 : 18,
              color: widget.active || _hovered
                ? AppColors.gold
                : AppColors.grey))))));
  }
}

class _AllFactionsTile extends StatefulWidget {
  final bool active;
  final VoidCallback onTap;
  const _AllFactionsTile({required this.active, required this.onTap});
  @override State<_AllFactionsTile> createState() => _AllFactionsTileState();
}

class _AllFactionsTileState extends State<_AllFactionsTile> {
  bool _hovered = false;
  bool _pressed = false;
  static const gold = AppColors.gold;
  static const grey = AppColors.grey;
  static final _kIdentity = Matrix4.identity();

  @override
  Widget build(BuildContext context) {
    final lit = widget.active || _hovered;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown:   (_) => setState(() => _pressed = true),
        onTapUp:     (_) => setState(() => _pressed = false),
        onTapCancel: ()  => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          transform: _pressed
            ? (Matrix4.identity()..scaleByDouble(0.98, 0.98, 1, 1))
            : _kIdentity,
          transformAlignment: Alignment.center,
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: widget.active
              ? gold.withValues(alpha: 0.08)
              : _hovered ? gold.withValues(alpha: 0.08) : Colors.transparent,
            border: Border.all(color: lit ? gold : gold.withValues(alpha: 0.15))),
          child: Row(children: [
            Container(width: 14, height: 14,
              decoration: BoxDecoration(shape: BoxShape.circle,
                border: Border.all(color: lit ? gold : grey, width: 1.5)),
              child: widget.active
                ? Center(child: Container(width: 6, height: 6,
                    decoration: const BoxDecoration(
                      color: gold, shape: BoxShape.circle)))
                : null),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('All Factions',
                style: GoogleFonts.cinzel(
                  color: lit ? gold : grey,
                  fontSize: 16, letterSpacing: 1.2)),
              const Text('Show all available units',
                style: TextStyle(color: grey, fontSize: 15)),
            ]),
          ]))));
  }
}

class _FacSelectCard extends StatefulWidget {
  final Map<String, dynamic> f;
  final bool selected;
  final String creatorName;
  final VoidCallback onToggle;
  const _FacSelectCard({required this.f, required this.selected,
    required this.creatorName, required this.onToggle});
  @override State<_FacSelectCard> createState() => _FacSelectCardState();
}

class _FacSelectCardState extends State<_FacSelectCard> {
  bool _loreExpanded  = false;
  bool _loreHovered   = false;
  bool _unitsExpanded = false;
  bool _unitsHovered  = false;
  bool _hovered = false;
  bool _pressed = false;
  Widget? _cachedImg;

  static const gold = AppColors.gold;
  // Stable reference so AnimatedContainer never animates the identity transform.
  static final _kIdentity = Matrix4.identity();

  @override
  void initState() {
    super.initState();
    final b64 = widget.f['image_b64'] as String?;
    if (b64 != null && b64.isNotEmpty) {
      _cachedImg = CachedBase64Image(base64: b64, width: AppColors.bannerW, height: AppColors.bannerH);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id        = widget.f['id'] as String;
    final name      = widget.f['name'] as String;
    final lore      = widget.f['lore'] as String?;
    final bgColor   = AppColors.parseHex(widget.f['color'] as String? ?? '#0D0B09');
    final hasLogo   = _cachedImg != null;
    final hasLore   = lore != null && lore.isNotEmpty;
    final unitNames = GameDataService.units
        .where((u) => u['faction_id'] == id)
        .map((u) => u['name'] as String)
        .toList();
    final unitCount = unitNames.length;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onToggle,
        onTapDown:   (_) => setState(() => _pressed = true),
        onTapUp:     (_) => setState(() => _pressed = false),
        onTapCancel: ()  => setState(() => _pressed = false),
        // AnimatedContainer drives the press-scale only.
        // Decoration is on an inner Container so the border width stays
        // constant (no layout-shift animation that would cause a blink).
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          transform: _pressed
            ? (Matrix4.identity()..scaleByDouble(0.98, 0.98, 1, 1))
            : _kIdentity,
          transformAlignment: Alignment.center,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: bgColor,
              border: Border.all(
                color: widget.selected || _hovered
                  ? gold
                  : gold.withValues(alpha: 0.2),
                width: 1.5)),
            child: Stack(clipBehavior: Clip.hardEdge, children: [

          if (hasLogo) Positioned(
            top: 0, left: 0, right: 0, height: 115,
            child: ClipRect(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: (_loreExpanded || _unitsExpanded) ? -70.0 : 0.0),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                builder: (_, dy, child) =>
                  Transform.translate(offset: Offset(0, dy), child: child),
                child: Center(child: _cachedImg!)))),

          if (!hasLogo) Positioned.fill(
            child: Center(child: Icon(Icons.shield_outlined,
              color: gold.withValues(alpha: 0.15), size: 36))),

          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.45),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55),
                    ],
                    stops: const [0.0, 0.4, 1.0]))))),

          Column(children: [
            SizedBox(
              height: 115,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(name,
                            style: GoogleFonts.cinzel(color: Colors.white, fontSize: 16,
                              shadows: [const Shadow(color: Colors.black54, blurRadius: 6)])),
                          Text(
                            widget.f['_source'] == 'user' && widget.creatorName.isNotEmpty
                              ? 'by ${widget.creatorName}' : 'by Aetherra',
                            style: GoogleFonts.cinzel(color: Colors.white54, fontSize: 12,
                              shadows: [const Shadow(color: Colors.black87, blurRadius: 4)])),
                        ])),
                    ]),
                    Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      GestureDetector(
                        onTap: hasLore ? () => setState(() => _loreExpanded = !_loreExpanded) : null,
                        child: MouseRegion(
                          cursor: hasLore ? SystemMouseCursors.click : MouseCursor.defer,
                          onEnter: hasLore ? (_) => setState(() => _loreHovered = true)  : null,
                          onExit:  hasLore ? (_) => setState(() => _loreHovered = false) : null,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 80),
                            opacity: hasLore ? (_loreExpanded || _loreHovered ? 1.0 : 0.55) : 0.2,
                            child: Icon(
                              _loreExpanded ? Icons.menu_book : Icons.menu_book_outlined,
                              color: gold, size: 17,
                              shadows: const [Shadow(color: Colors.black87, blurRadius: 8)])))),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: unitNames.isNotEmpty
                          ? () => setState(() => _unitsExpanded = !_unitsExpanded) : null,
                        child: MouseRegion(
                          cursor: unitNames.isNotEmpty ? SystemMouseCursors.click : MouseCursor.defer,
                          onEnter: (_) => setState(() => _unitsHovered = true),
                          onExit:  (_) => setState(() => _unitsHovered = false),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 80),
                            opacity: unitNames.isEmpty ? 0.2
                              : (_unitsExpanded || _unitsHovered ? 1.0 : 0.55),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text('$unitCount',
                                style: GoogleFonts.cinzel(color: gold, fontSize: 13,
                                  shadows: const [Shadow(color: Colors.black87, blurRadius: 6)])),
                              const SizedBox(width: 3),
                              Icon(_unitsExpanded ? Icons.group : Icons.group_outlined,
                                color: gold, size: 18,
                                shadows: const [Shadow(color: Colors.black87, blurRadius: 6)]),
                            ])))),
                      const Spacer(),
                      NavBtn(
                        icon: widget.selected ? Icons.check_box : Icons.check_box_outline_blank,
                        onPressed: widget.onToggle),
                    ]),
                  ]))),

            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              child: _unitsExpanded && unitNames.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: unitNames.map((n) => Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('· $n',
                          style: GoogleFonts.cinzel(
                            color: Colors.white70, fontSize: 11, height: 1.4,
                            shadows: [const Shadow(color: Colors.black87, blurRadius: 4)])))).toList()))
                : const SizedBox.shrink()),

            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              child: hasLore && _loreExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                    child: Text(lore,
                      style: GoogleFonts.cinzel(
                        color: Colors.white70, fontSize: 13, height: 1.6,
                        fontStyle: FontStyle.italic,
                        shadows: [const Shadow(color: Colors.black87, blurRadius: 8)])))
                : const SizedBox.shrink()),

          ]),

        ])))));
  }
}




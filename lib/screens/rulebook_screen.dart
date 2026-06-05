import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/nav_btn.dart';
import '../app_theme.dart';

class RulebookScreen extends StatefulWidget {
  const RulebookScreen({super.key});
  @override
  State<RulebookScreen> createState() => _RulebookScreenState();
}

class _RulebookScreenState extends State<RulebookScreen> {
  static const gold  = AppColors.gold;
      static const grey  = AppColors.grey;

  // PDF
  PdfDocument? _doc;
  final Map<int, Uint8List> _pages = {};
  final Set<int> _rendering = {};
  int  _page  = 1;
  int  _total = 20;
  Size _containerSize = Size.zero;

  // Download state
  bool   _downloading       = false;
  double _downloadProgress  = 0.0;
  String? _downloadError;

  // Zoom / pan
  double _zoom      = 1.0;
  Offset _pan       = Offset.zero;

  // Sidebar / search
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _index   = [];
  List<Map<String, dynamic>> _results = [];
  bool   _searching   = false;
  bool   _showSidebar = true;
  String _searchQuery = '';
  String _jumpedFrom   = '';
  int?   _activeId;
  final Set<String> _collapsed = {};
  final _activeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _openPdf();
    _initIndex();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _doc?.close();
    super.dispose();
  }

  // ── PDF LOADING ────────────────────────────────────────────────────
  static const _pdfBucket = 'rulebook';
  static const _pdfFile   = 'rulebook.pdf';

  String get _pdfUrl => Supabase.instance.client.storage
      .from(_pdfBucket).getPublicUrl(_pdfFile);

  Future<void> _openPdf() async {
    setState(() { _downloading = true; _downloadProgress = 0; _downloadError = null; });
    try {
      PdfDocument doc;
      if (kIsWeb) {
        // Web: no file system — download bytes into memory
        final bytes = await _downloadBytes();
        if (!mounted) return;
        doc = await PdfDocument.openData(bytes);
      } else {
        // Native: cache on disk, stream with progress
        final dir  = await getApplicationCacheDirectory();
        final file = File('${dir.path}/$_pdfFile');
        if (!await file.exists()) {
          await _downloadToFile(file);
          if (!mounted) return;
        }
        doc = await PdfDocument.openFile(file.path);
      }
      if (!mounted) return;
      setState(() { _doc = doc; _total = doc.pagesCount; _downloading = false; });
      await _renderPage(1);
      _prefetch(1);
    } catch (e) {
      if (mounted) setState(() { _downloadError = e.toString(); _downloading = false; });
    }
  }

  // Web: full download into memory via Supabase client (no dart:io)
  Future<Uint8List> _downloadBytes() async {
    return Supabase.instance.client.storage
        .from(_pdfBucket).download(_pdfFile);
  }

  // Native: stream to file with progress indicator
  Future<void> _downloadToFile(File dest) async {
    final req  = await HttpClient().getUrl(Uri.parse(_pdfUrl));
    final resp = await req.close();
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    final total = resp.contentLength;
    int received = 0;
    final sink = dest.openWrite();
    try {
      await for (final chunk in resp) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && mounted) {
          setState(() => _downloadProgress = received / total);
        }
      }
    } catch (e) {
      await sink.close();
      await dest.delete().catchError((_) => dest);
      rethrow;
    }
    await sink.close();
  }

  Future<void> _deleteCacheAndReload() async {
    if (!kIsWeb) {
      final dir  = await getApplicationCacheDirectory();
      final file = File('${dir.path}/$_pdfFile');
      await file.delete().catchError((_) => file);
    }
    _doc?.close();
    setState(() { _doc = null; _pages.clear(); _downloadError = null; });
    _openPdf();
  }

  void _prefetch(int around) {
    for (final p in [around - 1, around + 1, around + 2]) {
      if (p >= 1 && p <= _total) _renderPage(p);
    }
  }

  Future<void> _renderPage(int num) async {
    if (_pages.containsKey(num) || _rendering.contains(num)) return;
    if (_doc == null) return;
    _rendering.add(num);
    try {
      final page = await _doc!.getPage(num);
      final w = _containerSize.width  > 0 ? _containerSize.width  : 800.0;
      final scaleW = (w * 2) / page.width;
      final scale  = scaleW.clamp(1.5, 6.0);
      final img = await page.render(
        width:  page.width  * scale,
        height: page.height * scale);
      await page.close();
      if (img != null && mounted) {
        setState(() => _pages[num] = img.bytes);
      }
    } catch (_) {}
    _rendering.remove(num);
  }

  // ── NAVIGATION ─────────────────────────────────────────────────────
  void _goPage(int p) {
    if (p < 1 || p > _total) return;
    setState(() { _page = p; _pan = Offset.zero; _applyActiveForPage(p); });
    _renderPage(p);
    _prefetch(p);
    _scrollSidebarToActive();
  }

  void _zoomIn()  => setState(() => _zoom = (_zoom * 1.35).clamp(1.0, 5.0));
  void _zoomOut() => setState(() {
    _zoom = (_zoom / 1.35).clamp(1.0, 5.0);
    if (_zoom <= 1.0) {
      _pan = Offset.zero;
    } else {
      _clampPan();
    }
  });
  void _zoomReset() => setState(() { _zoom = 1.0; _pan = Offset.zero; });

  void _clampPan() {
    final maxX = _containerSize.width  * (_zoom - 1) / 2;
    final maxY = _containerSize.height * (_zoom - 1) / 2;
    _pan = Offset(
      _pan.dx.clamp(-maxX, maxX),
      _pan.dy.clamp(-maxY, maxY));
  }

  // Find the best matching index entry for a given page (sub-chapters preferred
  // over main chapters when on the same page).
  void _applyActiveForPage(int page) {
    if (_index.isEmpty) return;
    Map<String, dynamic>? best;
    for (final e in _index) {
      final ep = e['page_number'] as int;
      if (ep > page) continue;
      if (best == null || ep > (best['page_number'] as int)) {
        best = e;
      } else if (ep == (best['page_number'] as int) &&
                 (best['parent_chapter'] as String?) == null &&
                 (e['parent_chapter']   as String?) != null) {
        best = e; // prefer sub-chapter on same page
      }
    }
    if (best == null) return;
    _activeId = best['id'] as int;
    final parent = best['parent_chapter'] as String?;
    if (parent != null) _collapsed.remove(parent);
  }

  void _scrollSidebarToActive() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _activeKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 220), alignment: 0.35);
      }
    });
  }

  // ── INDEX / SEARCH ─────────────────────────────────────────────────
  void _initIndex() {
    var id = 0;
    Map<String, dynamic> e(String chapter, int page, [String? parent]) => {
      'id': ++id, 'chapter': chapter, 'parent_chapter': parent,
      'page_number': page, 'content': '',
    };
    _index = [
      e('Introduction',               1),
      e('What You Need to Play',      2),
      e('General Definitions & Rules',3),
      e('Dice Rolls',                 3,  'General Definitions & Rules'),
      e('Rounding',                   3,  'General Definitions & Rules'),
      e('Measuring',                  3,  'General Definitions & Rules'),
      e('Facing',                     4,  'General Definitions & Rules'),
      e('Field of View',              4,  'General Definitions & Rules'),
      e('Line of Sight (LoS)',        5,  'General Definitions & Rules'),
      e('Units, Ranks & Bases',       5,  'General Definitions & Rules'),
      e('Army Building',              6),
      e('Prepare the Battlefield',    7),
      e('Sequence of Play',           8),
      e('Activation Phase',           8,  'Sequence of Play'),
      e('Cleanup Phase',              8,  'Sequence of Play'),
      e('Ending the Game',            8,  'Sequence of Play'),
      e('Movement & Terrain',         9),
      e('Movement Basics',            9,  'Movement & Terrain'),
      e('Pivoting',                   9,  'Movement & Terrain'),
      e('Retreat',                   10,  'Movement & Terrain'),
      e('Terrain',                   11,  'Movement & Terrain'),
      e('Melee Combat',              13),
      e('Moving into Melee',         13,  'Melee Combat'),
      e('Reaction Pivot',            13,  'Melee Combat'),
      e('Melee Basics',              13,  'Melee Combat'),
      e('Melee Sequence',            14,  'Melee Combat'),
      e('Casualties & Removed Units',14,  'Melee Combat'),
      e('Positioning & Supports',    14,  'Melee Combat'),
      e('Shooting',                  15),
      e('Shooting Basics',           15,  'Shooting'),
      e('Shooting Sequence',         15,  'Shooting'),
      e('Shooting into Melee',       15,  'Shooting'),
      e('Shooting Modifiers',        16,  'Shooting'),
      e('Heroes and Command Points', 17),
      e('Heroes',                    17,  'Heroes and Command Points'),
      e('Command Points',            17,  'Heroes and Command Points'),
      e('Command Abilities',         18,  'Heroes and Command Points'),
      e('Starter Armies',            19),
    ];
    final mains  = _index.where((x) => x['parent_chapter'] == null)
        .map((x) => x['chapter'] as String).toSet();
    final hasSub = _index.where((x) => x['parent_chapter'] != null)
        .map((x) => x['parent_chapter'] as String).toSet();
    _collapsed.addAll(mains.intersection(hasSub));
    _applyActiveForPage(_page);
  }

  void _search(String q) {
    final trimmed = q.trim().toLowerCase();
    setState(() => _searchQuery = trimmed);
    if (trimmed.isEmpty) { setState(() => _results = []); return; }
    final words = trimmed.split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
    final hits = _index.where((e) {
      final text  = ((e['content'] as String?) ?? '').toLowerCase();
      final title = ((e['chapter'] as String?) ?? '').toLowerCase();
      if (text.contains(trimmed) || title.contains(trimmed)) return true;
      return words.any((w) => text.contains(w) || title.contains(w));
    }).toList();
    hits.sort((a, b) {
      final aE = ((a['chapter'] as String?)??'').toLowerCase().contains(trimmed) ? 0 : 1;
      final bE = ((b['chapter'] as String?)??'').toLowerCase().contains(trimmed) ? 0 : 1;
      if (aE != bE) return aE.compareTo(bE);
      return (a['page_number'] as int).compareTo(b['page_number'] as int);
    });
    setState(() => _results = hits);
  }

  String get _currentChapter {
    final mains = _index.where((c) => c['parent_chapter'] == null).toList()
      ..sort((a,b) => (a['page_number'] as int).compareTo(b['page_number'] as int));
    for (int i = mains.length - 1; i >= 0; i--) {
      if (_page >= (mains[i]['page_number'] as int)) {
        return mains[i]['chapter'] as String;
      }
    }
    return '';
  }

  // ── BUILD ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 700;
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        leading: NavBtn(icon: Icons.home_outlined,
          onPressed: () => Navigator.pop(context)),
        title: _searching
          ? TextField(
              controller: _searchCtrl, autofocus: true,
              style: GoogleFonts.cinzel(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Search rulebook…',
                hintStyle: GoogleFonts.cinzel(color: grey, fontSize: 14),
                border: InputBorder.none),
              onChanged: _search)
          : Text('Rulebook', style: GoogleFonts.cinzel(
              color: gold, fontSize: 16, letterSpacing: 2)),
        actions: [
          NavBtn(
            icon: _searching ? Icons.close : Icons.search,
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) { _searchCtrl.clear(); _results = []; _searchQuery = ''; }
            })),
        ],
      ),
      body: Column(children: [
        // Jump banner
        if (_jumpedFrom.isNotEmpty)
          GestureDetector(
            onTap: () => setState(() => _jumpedFrom = ''),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: gold.withValues(alpha: 0.15),
              child: Row(children: [
                const Icon(Icons.search, color: gold, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text('Jumped from search: "$_jumpedFrom"',
                  style: GoogleFonts.cinzel(color: gold, fontSize: 12))),
                Icon(Icons.close, color: gold.withValues(alpha: 0.5), size: 14),
              ]))),

        Expanded(child: _downloadError != null
          ? _errorView()
          : _downloading
          ? _downloadView()
          : _searchQuery.isNotEmpty
          ? _searchResults()
          : _showSidebar
            ? Row(children: [
                SizedBox(width: wide ? 220.0 : 200.0, child: _sidebar()),
                Container(width: 1, color: gold.withValues(alpha: 0.15)),
                Expanded(child: _pdfViewer()),
              ])
            : Column(children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: wide ? 220.0 : 200.0, child: _sidebarHeader())),
                Container(height: 1, color: gold.withValues(alpha: 0.15)),
                Expanded(child: _pdfViewer()),
              ])),

        // Bottom nav
        if (_searchQuery.isEmpty)
          Container(
            color: AppColors.dark,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(children: [
              // Balance the zoom controls on the right
              const Expanded(child: SizedBox()),
              // Page navigation — centered
              NavBtn(
                icon: Icons.chevron_left,
                onPressed: _page > 1 ? () => _goPage(_page - 1) : null),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('$_page / $_total', textAlign: TextAlign.center,
                    style: GoogleFonts.cinzel(color: gold, fontSize: 13)),
                  if (_currentChapter.isNotEmpty)
                    Text(_currentChapter, textAlign: TextAlign.center,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cinzel(color: grey, fontSize: 11)),
                ])),
              NavBtn(
                icon: Icons.chevron_right,
                onPressed: _page < _total ? () => _goPage(_page + 1) : null),
              // Zoom controls on the right
              Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Container(width: 1, height: 20,
                  color: gold.withValues(alpha: 0.3),
                  margin: const EdgeInsets.symmetric(horizontal: 6)),
                NavBtn(icon: Icons.zoom_out, onPressed: _zoomOut, size: 36),
                NavBtn(
                  icon: Icons.zoom_out_map,
                  onPressed: (_zoom - 1.0).abs() > 0.05 ? _zoomReset : null,
                  size: 36),
                NavBtn(icon: Icons.zoom_in, onPressed: _zoomIn, size: 36),
              ])),
            ])),
      ]),
    );
  }

  // ── DOWNLOAD / ERROR VIEWS ────────────────────────────────────────
  Widget _downloadView() => Center(child: Padding(
    padding: const EdgeInsets.all(40),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.download_outlined, color: gold, size: 48),
      const SizedBox(height: 20),
      Text('Downloading Rulebook…',
        style: GoogleFonts.cinzel(color: gold, fontSize: 15, letterSpacing: 1)),
      const SizedBox(height: 24),
      ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: _downloadProgress > 0 ? _downloadProgress : null,
          backgroundColor: gold.withValues(alpha: 0.15),
          valueColor: const AlwaysStoppedAnimation(gold),
          minHeight: 4)),
      const SizedBox(height: 12),
      if (_downloadProgress > 0)
        Text('${(_downloadProgress * 100).toStringAsFixed(0)}%',
          style: GoogleFonts.cinzel(color: grey, fontSize: 12)),
    ])));

  Widget _errorView() => Center(child: Padding(
    padding: const EdgeInsets.all(40),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.cloud_off_outlined, color: gold.withValues(alpha: 0.5), size: 48),
      const SizedBox(height: 20),
      Text('Failed to load Rulebook',
        style: GoogleFonts.cinzel(color: gold, fontSize: 15)),
      const SizedBox(height: 8),
      Text(_downloadError ?? '', textAlign: TextAlign.center,
        style: GoogleFonts.cinzel(color: grey.withValues(alpha: 0.6), fontSize: 11)),
      const SizedBox(height: 24),
      GestureDetector(
        onTap: _deleteCacheAndReload,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: gold.withValues(alpha: 0.5))),
          child: Text('Retry', style: GoogleFonts.cinzel(color: gold, fontSize: 13)))),
    ])));

  // ── SIDEBAR HEADER ─────────────────────────────────────────────────
  Widget _sidebarHeader() => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(14, 10, 6, 8),
    decoration: BoxDecoration(
      color: AppColors.dark,
      border: Border(bottom: BorderSide(color: gold.withValues(alpha: 0.2)))),
    child: Row(children: [
      Expanded(child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => setState(() => _showSidebar = !_showSidebar),
          child: Text('CHAPTERS', style: GoogleFonts.cinzel(
            color: gold, fontSize: 11, letterSpacing: 2))))),
      NavBtn(
        icon: _showSidebar ? Icons.chevron_left : Icons.chevron_right,
        onPressed: () => setState(() => _showSidebar = !_showSidebar)),
    ]));

  // ── SIDEBAR ────────────────────────────────────────────────────────
  Widget _sidebar() {
    final mains = _index.where((e) => e['parent_chapter'] == null).toList()
      ..sort((a,b) {
        final pg = (a['page_number'] as int).compareTo(b['page_number'] as int);
        if (pg != 0) return pg;
        return (a['id'] as int).compareTo(b['id'] as int);
      });

    return Container(color: AppColors.dark, child: Column(children: [
      _sidebarHeader(),
      Expanded(child: Builder(builder: (_) {
        final items = _sidebarItems(mains);
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (_, i) => items[i]);
      })),
    ]));
  }

  // ── PDF VIEWER ─────────────────────────────────────────────────────
  Widget _pdfViewer() => LayoutBuilder(builder: (ctx, constraints) {
    _containerSize = Size(constraints.maxWidth, constraints.maxHeight);
    return Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) {
          if (_zoom > 1.0) return;
          if (e.scrollDelta.dy > 0) { _goPage(_page + 1); }
          else if (e.scrollDelta.dy < 0) { _goPage(_page - 1); }
        }
      },
      child: Stack(children: [
        Positioned.fill(
          child: AbsorbPointer(
            absorbing: _zoom > 1.0,
            child: GestureDetector(
              onHorizontalDragEnd: (d) {
                if (_zoom > 1.0) return;
                if ((d.primaryVelocity ?? 0) < -300) { _goPage(_page + 1); }
                else if ((d.primaryVelocity ?? 0) > 300) { _goPage(_page - 1); }
              },
              child: ClipRect(child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..translateByDouble(_pan.dx, _pan.dy, 0, 1)
                  ..scaleByDouble(_zoom, _zoom, 1.0, 1.0),
                child: _pages.containsKey(_page)
                  ? Image.memory(_pages[_page]!, fit: BoxFit.contain, gaplessPlayback: true)
                  : Center(child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: gold, strokeWidth: 2),
                        const SizedBox(height: 12),
                        Text('Loading page $_page...',
                          style: GoogleFonts.cinzel(color: grey, fontSize: 12)),
                      ]))))))),
        if (_zoom > 1.0)
          Positioned.fill(child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleUpdate: (d) => setState(() {
              if (d.pointerCount >= 2) {
                _zoom = (_zoom * d.scale).clamp(1.0, 5.0);
              }
              _pan += d.focalPointDelta;
              _clampPan();
            }),
            child: const SizedBox.expand())),
        const Positioned(
          top: 0, left: 0, right: 0, height: 36,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.dark, Colors.transparent]))))),
        const Positioned(
          bottom: 0, left: 0, right: 0, height: 36,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [AppColors.dark, Colors.transparent]))))),
      ]));
  });

  List<Widget> _sidebarItems(List<Map<String,dynamic>> mains) {
    final items = <Widget>[];

    for (final ch in mains) {
      final chPage    = ch['page_number'] as int;
      final chName    = ch['chapter']     as String;
      final chId      = ch['id']          as int;
      final subs      = _index.where((e) => e['parent_chapter'] == chName).toList()
        ..sort((a,b) {
          final pg = (a['page_number'] as int).compareTo(b['page_number'] as int);
          if (pg != 0) return pg;
          return (a['id'] as int).compareTo(b['id'] as int);
        });
      final hasSubs   = subs.isNotEmpty;
      final collapsed = _collapsed.contains(chName);
      final active    = _activeId == chId;

      // ── Hauptkapitel ──────────────────────────────────
      items.add(_ChTile(
        key: active ? _activeKey : ValueKey('ch_$chId'),
        chName: chName, chPage: chPage, hasSubs: hasSubs,
        collapsed: collapsed, active: active,
        onNavigate: () {
          setState(() {
            _page = chPage; _pan = Offset.zero; _activeId = chId;
            if (hasSubs) _collapsed.remove(chName);
          });
          _renderPage(chPage);
        },
        onToggle: () => setState(() {
          if (collapsed) { _collapsed.remove(chName); }
          else           { _collapsed.add(chName); }
        })));

      // ── Unterkapitel ──────────────────────────────────
      if (!collapsed) {
        for (final sub in subs) {
          final subPage   = sub['page_number'] as int;
          final subName   = sub['chapter']     as String;
          final subId     = sub['id']          as int;
          final subActive = _activeId == subId;
          items.add(_SubTile(
            key: subActive ? _activeKey : ValueKey('sub_$subId'),
            subName: subName, subPage: subPage, subActive: subActive,
            onNavigate: () {
              setState(() {
                _page = subPage; _pan = Offset.zero; _activeId = subId;
                _collapsed.remove(chName);
              });
              _renderPage(subPage);
            }));
        }
      }
    }
    return items;
  }

  // ── SEARCH RESULTS ─────────────────────────────────────────────────
  Widget _highlightSnippet(String text, String query) {
    if (query.isEmpty) {
      return Text(text,
      style: const TextStyle(color: grey, fontSize: 12, height: 1.5));
    }
    final idx = text.toLowerCase().indexOf(query.toLowerCase());
    if (idx < 0) {
      return Text(text,
      style: const TextStyle(color: grey, fontSize: 12, height: 1.5));
    }
    return RichText(text: TextSpan(
      style: const TextStyle(color: grey, fontSize: 12, height: 1.5),
      children: [
        TextSpan(text: text.substring(0, idx)),
        TextSpan(text: text.substring(idx, idx + query.length),
          style: TextStyle(color: gold, fontWeight: FontWeight.bold,
            backgroundColor: gold.withValues(alpha: 0.15))),
        TextSpan(text: text.substring(idx + query.length)),
      ]));
  }

  Widget _searchResults() {
    if (_results.isEmpty) {
      return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.search_off, color: gold.withValues(alpha: 0.3), size: 40),
        const SizedBox(height: 12),
        Text('No results for "$_searchQuery"',
          style: GoogleFonts.cinzel(color: grey, fontSize: 14)),
      ]));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _results.length,
      itemBuilder: (_, i) {
        final r       = _results[i];
        final chapter = r['chapter'] as String;
        final page    = r['page_number'] as int;
        final parent  = r['parent_chapter'] as String?;
        final content = (r['content'] as String?) ?? '';
        final idx = content.toLowerCase().indexOf(_searchQuery.toLowerCase());
        final snippet = idx >= 0
          ? '…${content.substring((idx-40).clamp(0,content.length),(idx+80).clamp(0,content.length))}…'
          : content.substring(0, content.length.clamp(0, 120));

        return GestureDetector(
          onTap: () {
            setState(() {
              _searching = false;
              _jumpedFrom = _searchQuery;
              _searchQuery = '';
              _searchCtrl.clear();
              _results = [];
              _activeId = r['id'] as int;
            });
            _goPage(page);
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.dark,
              border: Border.all(color: gold.withValues(alpha: 0.2))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(chapter,
                  style: GoogleFonts.cinzel(color: gold, fontSize: 14))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: gold.withValues(alpha: 0.12),
                    border: Border.all(color: gold.withValues(alpha: 0.3))),
                  child: Text('p.$page',
                    style: GoogleFonts.cinzel(color: gold, fontSize: 11))),
              ]),
              if (parent != null) ...[
                const SizedBox(height: 2),
                Text('in $parent',
                  style: GoogleFonts.cinzel(color: grey, fontSize: 11)),
              ],
              const SizedBox(height: 6),
              _highlightSnippet(snippet, _searchQuery),
              const SizedBox(height: 4),
              Text('Tap to open page $page →',
                style: GoogleFonts.cinzel(
                  color: gold.withValues(alpha: 0.5), fontSize: 10)),
            ])));
      });
  }
}

// ── Chapter sidebar tiles ──────────────────────────────────────────────────

class _ChTile extends StatefulWidget {
  final String chName;
  final int chPage;
  final bool hasSubs, collapsed, active;
  final VoidCallback onNavigate, onToggle;
  const _ChTile({super.key, required this.chName, required this.chPage,
    required this.hasSubs, required this.collapsed, required this.active,
    required this.onNavigate, required this.onToggle});
  @override State<_ChTile> createState() => _ChTileState();
}
class _ChTileState extends State<_ChTile> {
  bool _hovered = false;
  static const gold = AppColors.gold;
  @override Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: widget.active ? gold.withValues(alpha: 0.10) : Colors.transparent,
      border: Border(left: BorderSide(
        color: widget.active ? gold : Colors.transparent, width: 2))),
    child: Row(children: [
      if (widget.hasSubs)
        GestureDetector(
          onTap: widget.onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 4, 12),
            child: Icon(
              widget.collapsed ? Icons.chevron_right : Icons.expand_more,
              color: widget.active ? gold : gold.withValues(alpha: 0.5), size: 16)))
      else
        const SizedBox(width: 30),
      Expanded(child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit:  (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onNavigate,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 4, 12),
            child: Text(widget.chName, style: GoogleFonts.cinzel(
              color: widget.active || _hovered ? gold : gold.withValues(alpha: 0.72),
              fontSize: 12, fontWeight: FontWeight.w600)))))),
      Text('p.${widget.chPage}', style: GoogleFonts.cinzel(
        color: gold.withValues(alpha: 0.35), fontSize: 10)),
      const SizedBox(width: 8),
    ]));
}

class _SubTile extends StatefulWidget {
  final String subName;
  final int subPage;
  final bool subActive;
  final VoidCallback onNavigate;
  const _SubTile({super.key, required this.subName, required this.subPage,
    required this.subActive, required this.onNavigate});
  @override State<_SubTile> createState() => _SubTileState();
}
class _SubTileState extends State<_SubTile> {
  bool _hovered = false;
  static const gold = AppColors.gold;
  static const grey = AppColors.grey;
  @override Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovered = true),
    onExit:  (_) => setState(() => _hovered = false),
    child: GestureDetector(
      onTap: widget.onNavigate,
      child: Container(
        padding: const EdgeInsets.fromLTRB(32, 8, 10, 8),
        decoration: BoxDecoration(
          color: widget.subActive ? gold.withValues(alpha: 0.08) : Colors.transparent,
          border: Border(left: BorderSide(
            color: widget.subActive ? gold : gold.withValues(alpha: 0.2),
            width: widget.subActive ? 2 : 1))),
        child: Row(children: [
          Expanded(child: Text(widget.subName, style: GoogleFonts.cinzel(
            color: widget.subActive || _hovered ? gold : grey.withValues(alpha: 0.65),
            fontSize: 11))),
          Text('p.${widget.subPage}', style: GoogleFonts.cinzel(
            color: gold.withValues(alpha: 0.3), fontSize: 10)),
        ]))));
}




import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_theme.dart';
import '../models/app_state.dart';
import 'new_army_screen.dart';
import 'armies_screen.dart';
import 'game_setup_screen.dart';
import 'rulebook_screen.dart';
import 'my_factions_screen.dart';
import 'online_lobby_screen.dart';
import 'dev_screen.dart';
import 'profile_settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const gold  = AppColors.gold;
  static const grey  = AppColors.grey;

  bool _isDev = false;
  bool   _gearHovered = false;

  @override void initState() { super.initState(); _loadUser(); }

  void _loadUser() {
    if (Supabase.instance.client.auth.currentUser != null) {
      setState(() => _isDev = AppState.isDeveloper);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(child: Column(children: [
        // â”€â”€ TOP BAR â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Row(children: [
            const Spacer(),
            MouseRegion(
              onEnter: (_) => setState(() => _gearHovered = true),
              onExit:  (_) => setState(() => _gearHovered = false),
              cursor: SystemMouseCursors.click,
              child: Theme(
                data: Theme.of(context).copyWith(
                  splashFactory:  NoSplash.splashFactory,
                  highlightColor: Colors.transparent,
                  splashColor:    Colors.transparent,
                  hoverColor:     Colors.transparent),
                child: PopupMenuButton(
                  tooltip: '',
                  padding: EdgeInsets.zero,
                  color: AppColors.dark,
                  shape: const RoundedRectangleBorder(),
                  itemBuilder: (_) => [
                    PopupMenuItem(enabled: false,
                      child: Text(Supabase.instance.client.auth.currentUser?.email ?? '',
                        style: GoogleFonts.cinzel(color: grey, fontSize: 12))),
                    PopupMenuItem(
                      padding: EdgeInsets.zero,
                      onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const ProfileSettingsScreen())),
                      child: const _PopupHoverItem(label: 'Profile Settings', color: AppColors.gold)),
                    PopupMenuItem(
                      padding: EdgeInsets.zero,
                      onTap: () async {
                        try {
                          await Supabase.instance.client.auth.signOut();
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              backgroundColor: AppColors.dark,
                              content: Text('Sign out failed. Please try again.',
                                style: GoogleFonts.cinzel(color: Colors.red))));
                          }
                        }
                      },
                      child: _PopupHoverItem(label: 'Sign Out', color: Colors.red)),
                  ],
                  child: Icon(Icons.settings_outlined,
                    color: _gearHovered ? gold : gold.withValues(alpha: 0.5),
                    size: 22)))),
          ])),

        // â”€â”€ HERO TITLE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 32),

            // Decorative line
            Container(height: 1, width: 48, color: gold.withValues(alpha: 0.35)),
            const SizedBox(height: 16),

            // Title
            Text('AETHERRA',
              style: GoogleFonts.cinzel(
                color: gold, fontSize: 42,
                fontWeight: FontWeight.w700, letterSpacing: 6,
                shadows: [Shadow(color: gold.withValues(alpha: 0.3), blurRadius: 20)])),
            const SizedBox(height: 6),
            Text('War Council',
              style: GoogleFonts.cinzel(
                color: grey.withValues(alpha: 0.6), fontSize: 14, letterSpacing: 4)),
            const SizedBox(height: 8),

            // â”€â”€ NAV CARDS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            _NavCard(
              icon: Icons.shield,
              title: 'New Army',
              subtitle: 'Build a new force from scratch',
              onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const NewArmyScreen()))),
            const SizedBox(height: 10),
            _NavCard(
              icon: Icons.list_alt,
              title: 'My Armies',
              subtitle: 'View and edit saved armies',
              onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ArmiesScreen()))),
            const SizedBox(height: 10),
            _NavCard(
              icon: Icons.casino,
              title: 'Game Mode',
              subtitle: 'Start or continue a battle',
              onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const GameSetupScreen()))),
            const SizedBox(height: 10),
            _NavCard(
              icon: Icons.wifi_outlined,
              title: 'Online Battle',
              subtitle: 'Challenge another commander via room code',
              onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const OnlineLobbyScreen()))),
            const SizedBox(height: 10),
            _NavCard(
              icon: Icons.menu_book,
              title: 'Rulebook',
              subtitle: 'Browse the game rules',
              onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const RulebookScreen()))),
            const SizedBox(height: 10),
            _NavCard(
              icon: Icons.auto_awesome,
              title: 'Workshop',
              subtitle: 'Build custom factions, units & abilities',
              onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const MyFactionsScreen()))),

            if (_isDev) ...[
              const SizedBox(height: 10),
              _NavCard(
                icon: Icons.developer_mode,
                title: 'Developer',
                subtitle: 'Internal tools',
                onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const DevScreen()))),
            ],

            const SizedBox(height: 32),
            Container(height: 1, color: gold.withValues(alpha: 0.1)),
            const SizedBox(height: 16),
            const Center(child: _InstagramLink()),
            const SizedBox(height: 16),
          ])))
      ])));
  }
}

class _NavCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _NavCard({required this.icon, required this.title,
    required this.subtitle, required this.onTap});
  @override State<_NavCard> createState() => _NavCardState();
}

class _NavCardState extends State<_NavCard> {
  bool _hovered = false;
  bool _pressed = false;
  static const gold = AppColors.gold;
  static const grey = AppColors.grey;

  @override Widget build(BuildContext context) =>
    MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown:   (_) => setState(() => _pressed = true),
        onTapUp:     (_) { setState(() => _pressed = false); widget.onTap(); },
        onTapCancel: ()  => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          transform: _pressed ? (Matrix4.identity()..scaleByDouble(0.98, 0.98, 1.0, 1.0)) : Matrix4.identity(),
          transformAlignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _hovered ? gold.withValues(alpha: 0.05) : Colors.transparent,
            border: Border.all(
              color: _hovered
                ? gold.withValues(alpha: 0.7)
                : gold.withValues(alpha: 0.18))),
          child: Row(children: [
            Icon(widget.icon, color: gold, size: 28),
            const SizedBox(width: 16),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, children: [
              Text(widget.title, style: GoogleFonts.cinzel(
                color: _hovered ? gold : gold.withValues(alpha: 0.75),
                fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 1)),
              const SizedBox(height: 2),
              Text(widget.subtitle, style: GoogleFonts.cinzel(
                color: grey.withValues(alpha: _hovered ? 0.7 : 0.45),
                fontSize: 11)),
            ])),
            Icon(Icons.chevron_right,
              color: _hovered ? gold.withValues(alpha: 0.8) : gold.withValues(alpha: 0.2),
              size: 18),
          ]))));
}

class _InstagramLink extends StatefulWidget {
  const _InstagramLink();
  @override State<_InstagramLink> createState() => _InstagramLinkState();
}
class _InstagramLinkState extends State<_InstagramLink> {
  bool _hovered = false;
  @override Widget build(BuildContext context) =>
    MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => launchUrl(
          Uri.parse('https://www.instagram.com/aetherra_tabletop/'),
          mode: LaunchMode.externalApplication),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 80),
          opacity: _hovered ? 1.0 : 0.4,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.camera_alt_outlined, color: AppColors.grey, size: 14),
              const SizedBox(width: 6),
              Text('@aetherra_tabletop',
                style: GoogleFonts.cinzel(
                  color: AppColors.grey, fontSize: 11, letterSpacing: 0.5)),
            ]))));
}

class _PopupHoverItem extends StatefulWidget {
  final String label;
  final Color color;
  const _PopupHoverItem({required this.label, required this.color});
  @override State<_PopupHoverItem> createState() => _PopupHoverItemState();
}

class _PopupHoverItemState extends State<_PopupHoverItem> {
  bool _hovered = false;
  @override Widget build(BuildContext context) =>
    MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(widget.label,
          style: GoogleFonts.cinzel(
            color: _hovered ? widget.color : widget.color.withValues(alpha: 0.55),
            fontSize: 13))));
}
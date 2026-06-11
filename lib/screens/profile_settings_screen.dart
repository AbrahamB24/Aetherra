import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/army_service.dart';
import '../services/subscription_service.dart';
import '../widgets/nav_btn.dart';
import '../widgets/unit_card.dart';
import '../widgets/aetherra_text_field.dart';
import '../widgets/hover_icon_btn.dart';
import '../widgets/aetherra_dialog.dart';
import '../app_theme.dart';

const _kPrivacyUrl   = 'https://aetherra.netlify.app/privacy';
const _kTermsUrl     = 'https://aetherra.netlify.app/terms';
const _kSupportEmail = 'mailto:aetherra.support@gmail.com';
const _kUpgradeUrl   = 'https://buy.stripe.com/fZu7sLeoSg6ae8jfOWb3q00';
const _kStripePortal = 'https://billing.stripe.com/p/login/fZu7sLeoSg6ae8jfOWb3q00';
const _kAppVersion   = '1.0.0';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});
  @override State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  static const gold = AppColors.gold;
  static const grey = AppColors.grey;

  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _pw0Ctrl   = TextEditingController();
  final _pw1Ctrl   = TextEditingController();
  final _pw2Ctrl   = TextEditingController();

  bool _pw0Visible  = false;
  bool _pw1Visible  = false;
  bool _pw2Visible  = false;
  bool _savingName  = false;
  bool _savingEmail = false;
  bool _savingPw    = false;
  bool _exporting   = false;

  String? _nameMsg;  bool _nameOk  = false;
  String? _emailMsg; bool _emailOk = false;
  String? _pwMsg;    bool _pwOk    = false;

  bool _isPremium      = false;
  int? _daysRemaining;

  @override
  void initState() {
    super.initState();
    final user = Supabase.instance.client.auth.currentUser;
    _emailCtrl.text = user?.email ?? '';
    final meta = user?.userMetadata ?? {};
    _nameCtrl.text = meta['display_name'] as String?
        ?? meta['full_name'] as String?
        ?? meta['name']      as String?
        ?? '';
    _loadPremium();
  }

  Future<void> _loadPremium() async {
    await SubscriptionService.load();
    if (mounted) { setState(() {
      _isPremium     = SubscriptionService.isPremium;
      _daysRemaining = SubscriptionService.daysRemaining;
    }); }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _pw0Ctrl.dispose();
    _pw1Ctrl.dispose();
    _pw2Ctrl.dispose();
    super.dispose();
  }

  // ── Account actions ───────────────────────────────────────────────────────

  Future<void> _saveName() async {
    final newName = _nameCtrl.text.trim();
    setState(() { _savingName = true; _nameMsg = null; _nameOk = false; });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {'display_name': newName}));
      await ArmyService.updateCreatorName(newName);
      if (mounted) { setState(() { _savingName = false; _nameOk = true; _nameMsg = 'Name updated.'; }); }
    } catch (e) {
      if (mounted) { setState(() { _savingName = false; _nameMsg = _errMsg(e); }); }
    }
  }

  Future<void> _saveEmail() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;
    setState(() { _savingEmail = true; _emailMsg = null; _emailOk = false; });
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(email: email));
      if (mounted) { setState(() {
        _savingEmail = false; _emailOk = true;
        _emailMsg = 'Confirmation link sent to the new address.';
      }); }
    } catch (e) {
      if (mounted) { setState(() { _savingEmail = false; _emailMsg = _errMsg(e); }); }
    }
  }

  Future<void> _savePassword() async {
    if (_pw0Ctrl.text.isEmpty) {
      setState(() { _pwMsg = 'Enter your current password.'; _pwOk = false; }); return;
    }
    if (_pw1Ctrl.text.isEmpty) {
      setState(() { _pwMsg = 'Enter a new password.'; _pwOk = false; }); return;
    }
    if (_pw1Ctrl.text.length < 6) {
      setState(() { _pwMsg = 'Minimum 6 characters.'; _pwOk = false; }); return;
    }
    if (_pw1Ctrl.text != _pw2Ctrl.text) {
      setState(() { _pwMsg = 'Passwords do not match.'; _pwOk = false; }); return;
    }
    setState(() { _savingPw = true; _pwMsg = null; _pwOk = false; });
    try {
      final email = Supabase.instance.client.auth.currentUser?.email ?? '';
      await Supabase.instance.client.auth.signInWithPassword(
        email: email, password: _pw0Ctrl.text);
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _pw1Ctrl.text));
      if (mounted) {
        _pw0Ctrl.clear(); _pw1Ctrl.clear(); _pw2Ctrl.clear();
        setState(() { _savingPw = false; _pwOk = true; _pwMsg = 'Password changed.'; });
      }
    } catch (e) {
      if (mounted) { setState(() { _savingPw = false; _pwMsg = _errMsg(e); }); }
    }
  }


  Future<void> _exportData() async {
    setState(() => _exporting = true);
    try {
      final armies = await ArmyService.loadAll();
      final json = const JsonEncoder.withIndent('  ').convert({
        'exported_at': DateTime.now().toIso8601String(),
        'armies': armies,
      });
      await SharePlus.instance.share(ShareParams(
        text: json,
        subject: 'Aetherra — My Army Data'));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.dark,
        content: Text('Export failed: ${_errMsg(e)}',
          style: GoogleFonts.cinzel(color: Colors.red))));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _deleteProfile() async {
    final confirmed = await showAetherraSheet<bool>(context,
      title: 'Delete Profile',
      titleColor: Colors.red,
      body: Text(
        'This will permanently delete your account and all data. This cannot be undone.',
        style: GoogleFonts.cinzel(color: grey, fontSize: 13, height: 1.6)),
      actions: [
        SheetAction('Cancel', grey,               () => Navigator.pop(context, false), outlined: true),
        SheetAction('Delete', Colors.red, () => Navigator.pop(context, true)),
      ]);
    if (confirmed != true || !mounted) return;
    try {
      await Supabase.instance.client.rpc('delete_user');
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.dark,
        content: Text(_errMsg(e),
          style: GoogleFonts.cinzel(color: Colors.red))));
      }
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.dark,
        content: Text('Could not open link.',
          style: GoogleFonts.cinzel(color: grey))));
      }
    }
  }

  String _errMsg(Object e) {
    final s = e.toString();
    if (s.contains('AuthApiException:')) return s.split('AuthApiException:').last.trim();
    return s;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      appBar: AppBar(
        leading: NavBtn(
          icon: Icons.arrow_back_ios_new,
          onPressed: () => Navigator.pop(context)),
        title: Text('Profile',
          style: GoogleFonts.cinzel(color: gold, fontSize: 17, letterSpacing: 2)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
        children: [

          // ── Display Name ─────────────────────────────────────────────────
          _label('Display Name'),
          const SizedBox(height: 8),
          AetherraTextField(controller: _nameCtrl, hintText: 'Your name'),
          _feedback(_nameMsg, _nameOk),
          PressBtn(
            label: _savingName ? 'Saving...' : 'Save Name',
            onTap: _savingName ? () {} : _saveName,
            bg: gold, fg: AppColors.dark, centered: true,
            padding: const EdgeInsets.symmetric(vertical: 12)),

          _gap(),

          // ── Email ─────────────────────────────────────────────────────────
          _label('Email Address'),
          const SizedBox(height: 8),
          AetherraTextField(
            controller: _emailCtrl,
            hintText: 'your@email.com',
            keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 6),
          Text('A confirmation link will be sent to the new address.',
            style: TextStyle(
              color: grey.withValues(alpha: 0.55),
              fontSize: 13, fontStyle: FontStyle.italic)),
          _feedback(_emailMsg, _emailOk),
          PressBtn(
            label: _savingEmail ? 'Sending...' : 'Change Email',
            onTap: _savingEmail ? () {} : _saveEmail,
            bg: gold, fg: AppColors.dark, centered: true,
            padding: const EdgeInsets.symmetric(vertical: 12)),

          _gap(),

          // ── Password ──────────────────────────────────────────────────────
          _label('Change Password'),
          const SizedBox(height: 8),
          AetherraTextField(
            controller: _pw0Ctrl,
            hintText: 'Current password',
            obscureText: !_pw0Visible,
            suffixIcon: HoverIconBtn(
              icon: _pw0Visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: grey, size: 18, padding: const EdgeInsets.all(10),
              onTap: () => setState(() => _pw0Visible = !_pw0Visible))),
          const SizedBox(height: 8),
          AetherraTextField(
            controller: _pw1Ctrl,
            hintText: 'New password',
            obscureText: !_pw1Visible,
            suffixIcon: HoverIconBtn(
              icon: _pw1Visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: grey, size: 18, padding: const EdgeInsets.all(10),
              onTap: () => setState(() => _pw1Visible = !_pw1Visible))),
          const SizedBox(height: 8),
          AetherraTextField(
            controller: _pw2Ctrl,
            hintText: 'Confirm new password',
            obscureText: !_pw2Visible,
            suffixIcon: HoverIconBtn(
              icon: _pw2Visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: grey, size: 18, padding: const EdgeInsets.all(10),
              onTap: () => setState(() => _pw2Visible = !_pw2Visible))),
          _feedback(_pwMsg, _pwOk),
          PressBtn(
            label: _savingPw ? 'Saving...' : 'Change Password',
            onTap: _savingPw ? () {} : _savePassword,
            bg: gold, fg: AppColors.dark, centered: true,
            padding: const EdgeInsets.symmetric(vertical: 12)),

          _gap(),

          // ── Premium ───────────────────────────────────────────────────────
          Row(children: [
            _label('Premium'),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _isPremium ? gold : grey.withValues(alpha: 0.4)),
                color: _isPremium ? gold.withValues(alpha: 0.12) : Colors.transparent),
              child: Text(
                _isPremium
                  ? (_daysRemaining != null ? '$_daysRemaining days left' : 'Active')
                  : 'Free',
                style: GoogleFonts.cinzel(
                  color: _isPremium ? gold : grey,
                  fontSize: 10, letterSpacing: 1))),
          ]),
          const SizedBox(height: 12),

          if (!_isPremium) ...[
            // Feature list
            ...[
              'Custom unit photos & lore',
              'Unit background colors',
              'Unlimited army sharing',
            ].map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Icon(Icons.check, color: gold.withValues(alpha: 0.7), size: 14),
                const SizedBox(width: 8),
                Text(f, style: GoogleFonts.cinzel(color: grey, fontSize: 12)),
              ]))),
            const SizedBox(height: 12),
            PressBtn(
              label: 'Upgrade to Premium',
              onTap: () => _openUrl(_kUpgradeUrl),
              bg: gold, fg: AppColors.dark, centered: true,
              padding: const EdgeInsets.symmetric(vertical: 12)),
          ] else ...[
            _linkRow(
              icon: Icons.manage_accounts_outlined,
              label: 'Manage Subscription',
              onTap: () => _openUrl(_kStripePortal)),
          ],

          _gap(),

          // ── About ─────────────────────────────────────────────────────────
          _label('About'),
          const SizedBox(height: 12),
          _linkRow(
            icon: Icons.shield_outlined,
            label: 'Privacy Policy',
            onTap: () => _openUrl(_kPrivacyUrl)),
          const SizedBox(height: 2),
          _linkRow(
            icon: Icons.description_outlined,
            label: 'Terms of Service',
            onTap: () => _openUrl(_kTermsUrl)),
          const SizedBox(height: 2),
          _linkRow(
            icon: Icons.mail_outline,
            label: 'Contact Support',
            onTap: () => _openUrl(_kSupportEmail)),
          const SizedBox(height: 2),
          _infoRow(icon: Icons.info_outline, label: 'Version', value: _kAppVersion),

          const SizedBox(height: 40),
          Align(alignment: Alignment.centerLeft,
            child: Container(height: 1, width: 48,
              color: AppColors.gold.withValues(alpha: 0.35))),
          const SizedBox(height: 24),

          // ── Danger Zone ───────────────────────────────────────────────────
          _label('Data & Account'),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _exporting ? null : _exportData,
            style: OutlinedButton.styleFrom(
              foregroundColor: grey,
              side: BorderSide(color: grey.withValues(alpha: 0.4)),
              shape: const RoundedRectangleBorder(),
              padding: const EdgeInsets.symmetric(vertical: 12)),
            child: Center(child: _exporting
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.gold))
              : Text('Export My Data',
                  style: GoogleFonts.cinzel(fontSize: 14, letterSpacing: 1)))),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _deleteProfile,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
              shape: const RoundedRectangleBorder(),
              padding: const EdgeInsets.symmetric(vertical: 12)),
            child: Center(child: Text('Delete Profile',
              style: GoogleFonts.cinzel(fontSize: 14, letterSpacing: 1)))),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _label(String text, {bool danger = false}) => Text(text,
    style: GoogleFonts.cinzel(
      color: danger ? Colors.red : gold,
      fontSize: 12, letterSpacing: 1.6));

  Widget _gap() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const SizedBox(height: 28),
    Container(height: 1, width: 48, color: gold.withValues(alpha: 0.35)),
    const SizedBox(height: 28),
  ]);

  Widget _feedback(String? msg, bool ok) {
    if (msg == null) return const SizedBox(height: 10);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(msg,
        style: TextStyle(
          color: ok ? Colors.green.shade400 : Colors.red,
          fontSize: 13)));
  }

  Widget _linkRow({required IconData icon, required String label, required VoidCallback onTap}) {
    bool hovered = false;
    return StatefulBuilder(builder: (_, set) =>
      MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => set(() => hovered = true),
        onExit:  (_) => set(() => hovered = false),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: hovered
                  ? gold.withValues(alpha: 0.35)
                  : gold.withValues(alpha: 0.1))),
            child: Row(children: [
              Icon(icon, color: gold.withValues(alpha: 0.6), size: 16),
              const SizedBox(width: 10),
              Expanded(child: Text(label,
                style: GoogleFonts.cinzel(color: grey, fontSize: 13))),
              Icon(Icons.chevron_right,
                color: gold.withValues(alpha: hovered ? 0.6 : 0.25), size: 16),
            ])))));
  }

  Widget _infoRow({required IconData icon, required String label, required String value}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: gold.withValues(alpha: 0.1))),
      child: Row(children: [
        Icon(icon, color: gold.withValues(alpha: 0.6), size: 16),
        const SizedBox(width: 10),
        Expanded(child: Text(label,
          style: GoogleFonts.cinzel(color: grey, fontSize: 13))),
        Text(value,
          style: GoogleFonts.cinzel(color: gold.withValues(alpha: 0.55), fontSize: 13)),
      ]));
}


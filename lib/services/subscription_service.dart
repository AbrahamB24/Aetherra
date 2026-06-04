import 'package:supabase_flutter/supabase_flutter.dart';

class SubscriptionService {
  static final _sb = Supabase.instance.client;

  static bool      _manualPremium = false;
  static DateTime? _premiumUntil;

  // true if manually set OR if stripe subscription is still active
  static bool get isPremium =>
      _manualPremium ||
      (_premiumUntil != null &&
       _premiumUntil!.isAfter(DateTime.now().toUtc()));

  // Remaining days (null if not premium via Stripe)
  static int? get daysRemaining {
    if (_premiumUntil == null) return null;
    final diff = _premiumUntil!.difference(DateTime.now().toUtc()).inDays;
    return diff > 0 ? diff : null;
  }

  static Future<void> load() async {
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) { _manualPremium = false; _premiumUntil = null; return; }
      final r = await _sb
          .from('profiles')
          .select('is_premium, premium_until')
          .eq('id', uid)
          .maybeSingle();
      _manualPremium = (r?['is_premium'] as bool?) ?? false;
      final until = r?['premium_until'] as String?;
      _premiumUntil = until != null ? DateTime.parse(until).toUtc() : null;
    } catch (_) {
      _manualPremium = false;
      _premiumUntil  = null;
    }
  }

  static void reset() {
    _manualPremium = false;
    _premiumUntil  = null;
  }
}

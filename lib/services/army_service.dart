import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/army_state.dart';
import 'game_data_service.dart';

class ArmyService {
  static final _sb = Supabase.instance.client;

  static Future<String?> save(
      ArmyState army, String name, String? listId) async {
    final user = _sb.auth.currentUser;
    if (user == null) return null;

    final armyJson = army.toJson();

    final meta = user.userMetadata ?? {};
    final creatorName = meta['display_name'] as String?
        ?? meta['full_name'] as String?
        ?? meta['name'] as String?
        ?? '';

    if (listId != null) {
      // Preserve metadata (image_b64, bg_color, lore, creator_name) stored alongside unit data
      Map<String, dynamic> existing = {};
      try {
        final row = await _sb.from('army_lists')
          .select('army_data').eq('id', listId).single();
        existing = Map<String, dynamic>.from(row['army_data'] as Map? ?? {});
      } catch (_) {}
      final merged = {
        ...armyJson,
        for (final key in ['image_b64', 'bg_color', 'lore', 'creator_name'])
          if (existing.containsKey(key)) key: existing[key],
      };
      await _sb.from('army_lists').update({
        'name':         name,
        'army_data':    merged,
        'total_points': army.totalPoints,
        'updated_at':   DateTime.now().toIso8601String(),
      }).eq('id', listId).eq('user_id', user.id);
      return listId;
    } else {
      final r = await _sb.from('army_lists')
        .insert({
          'name':         name,
          'army_data':    {
            ...armyJson,
            if (creatorName.isNotEmpty) 'creator_name': creatorName,
          },
          'total_points': army.totalPoints,
          'updated_at':   DateTime.now().toIso8601String(),
          'user_id':      user.id,
        })
        .select()
        .single();
      return r['id'] as String?;
    }
  }

  static Future<List<Map<String, dynamic>>> loadAll() async {
    final user = _sb.auth.currentUser;
    if (user == null) return [];
    final r = await _sb.from('army_lists')
      .select('*')
      .eq('user_id', user.id)
      .order('updated_at', ascending: false);
    return List<Map<String, dynamic>>.from(r);
  }

  /// Updates `creator_name` in army_data for every army owned by the current user.
  /// Called after the user changes their display name in Profile Settings.
  static Future<void> updateCreatorName(String newName) async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    final rows = await _sb
      .from('army_lists')
      .select('id, army_data')
      .eq('user_id', user.id);
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final ad = Map<String, dynamic>.from(row['army_data'] as Map? ?? {});
      if (newName.isNotEmpty) {
        ad['creator_name'] = newName;
      } else {
        ad.remove('creator_name');
      }
      await _sb.from('army_lists')
        .update({'army_data': ad})
        .eq('id', row['id'] as String)
        .eq('user_id', user.id);
    }
  }

  static Future<void> delete(String id) async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    await _sb.from('army_lists')
      .delete()
      .eq('id', id)
      .eq('user_id', user.id);
  }

  /// Decodes a stored photoBase64 string into raw image bytes.
  /// Handles both plain base64 PNG/JPEG and the JSON-envelope format
  /// produced by the crop dialog ({imageBase64: ..., ...}).
  static Uint8List _decodePhoto(String photoBase64) {
    try {
      final raw = base64Decode(photoBase64);
      if (raw.isNotEmpty && raw[0] == 0x7B) {
        final info = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
        return base64Decode(info['src'] as String);
      }
      return raw;
    } catch (_) {}
    return base64Decode(photoBase64);
  }

  static String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  /// Publishes the army to `shared_armies` and returns the 6-char code.
  /// Unit photos are uploaded to the `unit-photos` Storage bucket;
  /// only the storage path (not base64) goes into the payload.
  static Future<String?> shareArmy(ArmyState army, String? listId) async {
    final user = _sb.auth.currentUser;
    if (user == null) return null;

    // Pull metadata (lore, bg_color, image_b64, creator_name) from DB
    String? lore;
    String? bgColor;
    String? imageB64;
    String? creatorName;
    if (listId != null) {
      try {
        final row = await _sb.from('army_lists')
          .select('army_data').eq('id', listId).single();
        final ad = Map<String, dynamic>.from(row['army_data'] as Map? ?? {});
        lore        = ad['lore']         as String?;
        bgColor     = ad['bg_color']     as String?;
        imageB64    = ad['image_b64']    as String?;
        creatorName = ad['creator_name'] as String?;
      } catch (_) {}
    }
    creatorName ??= () {
      final meta = user.userMetadata ?? {};
      return meta['display_name'] as String?
          ?? meta['full_name'] as String?
          ?? meta['name'] as String?
          ?? '';
    }();

    final code = _generateCode();

    // Upload unit photos + army logo to Storage in parallel
    final unitsFuture = Future.wait(army.units.map((u) async {
      final j = u.toJson();
      j.remove('photo');
      // Embed definition for user-created units so recipients can use them
      if (j['embedded_def'] == null) {
        final isUserUnit = GameDataService.userUnits.any((r) => r['id'] == u.unit.id);
        if (isUserUnit) {
          final raw = GameDataService.units.firstWhere(
            (r) => r['id'] == u.unit.id, orElse: () => {});
          if (raw.isNotEmpty) j['embedded_def'] = raw;
        }
      }
      if (u.photoBase64 != null && u.photoBase64!.isNotEmpty) {
        try {
          final bytes = _decodePhoto(u.photoBase64!);
          final path = '$code/${u.iid}';
          await _sb.storage.from('unit-photos').uploadBinary(
            path, bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true));
          j['photo_path'] = path;
        } catch (_) {}
      }
      return j;
    }));

    String? logoPath;
    if (imageB64 != null && imageB64.isNotEmpty) {
      try {
        final bytes = _decodePhoto(imageB64);
        logoPath = '$code/logo';
        await _sb.storage.from('unit-photos').uploadBinary(
          logoPath, bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true));
      } catch (_) {
        logoPath = null;
      }
    }

    final units = await unitsFuture;

    final armyData = {
      'units':      units,
      'limit':      army.limit,
      'factionIds': army.factionIds,
      'groups':     army.groups,
      if (lore        != null && lore.isNotEmpty)        'lore':         lore,
      if (bgColor     != null && bgColor.isNotEmpty)     'bg_color':     bgColor,
      if (logoPath    != null)                           'logo_path':    logoPath,
      if (creatorName.isNotEmpty) 'creator_name': creatorName,
    };

    await _sb.from('shared_armies').insert({
      'id':         code,
      'army_name':  army.name.isEmpty ? 'Unnamed Army' : army.name,
      'army_data':  armyData,
      'created_by': user.id,
    });
    return code;
  }

  /// Fetches a shared army row by its 6-char code. Returns null if not found.
  static Future<Map<String, dynamic>?> fetchShared(String code) async {
    try {
      final row = await _sb.from('shared_armies')
        .select('*')
        .eq('id', code.toUpperCase().trim())
        .single();
      return Map<String, dynamic>.from(row);
    } catch (_) {
      return null;
    }
  }

  /// Imports a fetched shared army row into the current user's army_lists.
  /// Downloads unit photos from Storage and stores them as base64.
  static Future<String?> importArmy(Map<String, dynamic> row) async {
    final user = _sb.auth.currentUser;
    if (user == null) return null;
    final armyData = Map<String, dynamic>.from(row['army_data'] as Map? ?? {});

    // Download unit photos + army logo from Storage in parallel
    final logoPath = armyData.remove('logo_path') as String?;
    final rawUnits = armyData['units'] as List? ?? [];

    Future<Uint8List?> downloadSafe(String path) async {
      try {
        final bytes = await _sb.storage.from('unit-photos').download(path);
        return bytes.isNotEmpty ? bytes : null;
      } catch (_) {
        return null;
      }
    }

    final results = await Future.wait<dynamic>([
      Future.wait(rawUnits.map<Future<Map<String, dynamic>>>((u) async {
        final unit = Map<String, dynamic>.from(u as Map);
        final path = unit.remove('photo_path') as String?;
        if (path != null && path.isNotEmpty) {
          final bytes = await downloadSafe(path);
          if (bytes != null) unit['photo'] = base64Encode(bytes);
        }
        return unit;
      })),
      if (logoPath != null) downloadSafe(logoPath),
    ]);

    final units = (results[0] as List).cast<Map<String, dynamic>>();
    final logoBytes = logoPath != null ? results[1] as Uint8List? : null;

    armyData['units'] = units;
    if (logoBytes != null && logoBytes.isNotEmpty) {
      armyData['image_b64'] = base64Encode(logoBytes);
    }

    final totalPoints = units.fold<int>(0, (sum, u) {
      final unit = GameDataService.toGameUnit(u['unitId'] as String? ?? '');
      return sum + (unit?.cost ?? 0);
    });

    final r = await _sb.from('army_lists').insert({
      'name':         row['army_name'] as String? ?? 'Imported Army',
      'army_data':    armyData,
      'total_points': totalPoints,
      'updated_at':   DateTime.now().toIso8601String(),
      'user_id':      user.id,
    }).select().single();
    return r['id'] as String?;
  }
}

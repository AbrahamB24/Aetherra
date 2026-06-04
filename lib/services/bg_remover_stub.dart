import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<Uint8List?> removeBg(Uint8List imageBytes) async {
  try {
    final response = await Supabase.instance.client.functions.invoke(
      'remove-bg',
      body: {'image': base64Encode(imageBytes)},
    );
    final result = response.data?['result'] as String?;
    if (result == null) return null;
    return base64Decode(result);
  } catch (e) {
    return null;
  }
}

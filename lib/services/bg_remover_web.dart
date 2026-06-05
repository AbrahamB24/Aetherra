import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<Uint8List?> removeBg(Uint8List imageBytes) async {
  final response = await Supabase.instance.client.functions.invoke(
    'remove-bg',
    body: {'image': base64Encode(imageBytes)},
  );
  final error = response.data?['error'] as String?;
  if (error != null) throw Exception(error);
  final result = response.data?['result'] as String?;
  if (result == null) throw Exception('No result returned');
  return base64Decode(result);
}

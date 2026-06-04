import 'package:flutter/material.dart';

class AppColors {
  static const gold       = Color(0xFFC9A84C);
  static const goldLight  = Color(0xFFE8C96A);
  static const goldBright = Color(0xFFFFE87A);
  static const dark       = Color(0xFF0D0B08);
  static const grey       = Color(0xFFB0A090);
  static const greyLight  = Color(0xFF8A7D70);
  static const textLight  = Color(0xFFF0E8D8);

  // Banner dimensions used across all army/faction banner widgets
  static const double bannerW = 200.0;
  static const double bannerH = 115.0;

  static Color parseHex(String hex) {
    try { return Color(int.parse(hex.replaceFirst('#', '0xFF'))); }
    catch (_) { return dark; }
  }
}

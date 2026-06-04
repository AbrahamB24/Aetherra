class AppState {
  static String userRole = 'user';
  static bool get isDeveloper => userRole == 'developer';
  static void reset() => userRole = 'user';
}
import 'package:shared_preferences/shared_preferences.dart';

enum AppMode { online, offline }

/// Small persistent preference so the app remembers whether the user chose
/// cloud mode or local-only mode. Authentication itself remains in Supabase.
class AppModeStore {
  const AppModeStore();

  static const _key = 'tunas_app_mode_v1';

  Future<AppMode?> read() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return switch (preferences.getString(_key)) {
        'online' => AppMode.online,
        'offline' => AppMode.offline,
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> write(AppMode mode) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _key,
        mode == AppMode.online ? 'online' : 'offline',
      );
    } catch (_) {
      // The in-memory choice still works if the platform store is unavailable.
    }
  }
}

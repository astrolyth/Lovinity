import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lov_palette.dart';

const _key = 'lovinity-theme';

/// Loaded once in main() so the first frame already has the saved theme.
/// Null in tests and before startup; the theme then stays on Midnight.
final sharedPreferencesProvider = Provider<SharedPreferences?>((_) => null);

/// The user's chosen theme; a device preference, so it survives sign-out.
final themeProvider = NotifierProvider<ThemeController, LovThemeId>(
  ThemeController.new,
);

class ThemeController extends Notifier<LovThemeId> {
  @override
  LovThemeId build() =>
      LovThemeId.fromName(ref.read(sharedPreferencesProvider)?.getString(_key));

  Future<void> select(LovThemeId id) async {
    state = id;
    await ref.read(sharedPreferencesProvider)?.setString(_key, id.name);
  }
}

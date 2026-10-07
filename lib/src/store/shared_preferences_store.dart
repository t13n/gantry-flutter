import 'package:shared_preferences/shared_preferences.dart';

import 'gantry_store.dart';

/// The default [GantryStore], backed by `shared_preferences`.
class SharedPreferencesGantryStore implements GantryStore {
  Future<SharedPreferences> get _preferences => SharedPreferences.getInstance();

  @override
  Future<String?> read(String key) async => (await _preferences).getString(key);

  @override
  Future<void> write(String key, String value) async {
    await (await _preferences).setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await (await _preferences).remove(key);
  }
}

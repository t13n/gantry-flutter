/// Small persistent key-value storage used by the SDK.
///
/// The default implementation uses `shared_preferences`. Implement this to
/// keep the data elsewhere and pass it as `store` to `Gantry`. The SDK stores
/// one value: which interstitials were shown and when.
abstract interface class GantryStore {
  /// Returns the value saved under [key], or null.
  Future<String?> read(String key);

  /// Saves [value] under [key].
  Future<void> write(String key, String value);

  /// Deletes the value saved under [key].
  Future<void> remove(String key);
}

/// A [GantryStore] that forgets everything when the app closes. For tests.
class MemoryGantryStore implements GantryStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);
}

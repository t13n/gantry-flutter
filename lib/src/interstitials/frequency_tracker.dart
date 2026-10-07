import 'dart:convert';

import '../log/gantry_log.dart';
import '../store/gantry_store.dart';
import 'interstitial.dart';

/// Remembers which campaigns were shown on this device and when, and decides
/// whether a campaign's frequency allows showing it again.
///
/// The record is kept per campaign id and per device; it is shared by
/// campaigns from Remote Config and from the API and survives a logout.
class FrequencyTracker {
  /// Creates a tracker that persists to [store].
  FrequencyTracker({
    required GantryStore store,
    required DateTime Function() now,
    required LogSink log,
  })  : _store = store,
        _now = now,
        _log = log;

  /// Key of the display record in the store.
  static const String storeKey = 'gantry.shown';

  /// How many campaign ids are remembered; the oldest display is dropped first.
  static const int maxEntries = 200;

  final GantryStore _store;
  final DateTime Function() _now;
  final LogSink _log;
  final Set<String> _shownThisLaunch = {};

  // What this launch knows: displays made since launch, plus the saved record
  // once it has been read.
  Map<String, DateTime> _shown = {};
  bool _loaded = false;
  Future<void>? _loading;

  /// Whether [interstitial] may be shown now under its frequency.
  Future<bool> canShow(Interstitial interstitial) async {
    final id = interstitial.id;
    switch (interstitial.frequency) {
      case InterstitialFrequency.everyLaunch:
        return !_shownThisLaunch.contains(id);
      case InterstitialFrequency.once:
        return !(await _load()).containsKey(id);
      case InterstitialFrequency.daily:
        final last = (await _load())[id];
        return last == null || !_sameLocalDay(last, _now());
    }
  }

  /// Records that [interstitial] was shown just now. Never throws.
  ///
  /// The display counts from the moment of the call, before anything is
  /// saved.
  Future<void> markShown(Interstitial interstitial) async {
    final at = _now();
    _shownThisLaunch.add(interstitial.id);
    _shown[interstitial.id] = at;

    final shown = await _load();
    while (shown.length > maxEntries) {
      final oldest =
          shown.entries.reduce((a, b) => a.value.isAfter(b.value) ? b : a);
      shown.remove(oldest.key);
    }
    // Saving without having read the record would overwrite earlier displays.
    if (!_loaded) return;
    try {
      final json = {
        for (final entry in shown.entries)
          entry.key: entry.value.toUtc().toIso8601String(),
      };
      await _store.write(storeKey, jsonEncode(json));
    } catch (error) {
      _log.warning('Could not save which interstitials were shown', error);
    }
  }

  /// Returns the current record, reading the saved one first if needed.
  ///
  /// Callers that arrive together share one read. A read that fails is tried
  /// again on the next call.
  Future<Map<String, DateTime>> _load() async {
    if (_loaded) return _shown;
    final loading = _loading ??= _readStore();
    await loading;
    if (identical(_loading, loading)) _loading = null;
    return _shown;
  }

  Future<void> _readStore() async {
    try {
      final saved = _parse(await _store.read(storeKey));
      _shown = {...saved, ..._shown};
      _loaded = true;
    } catch (error) {
      _log.warning('Could not read which interstitials were shown', error);
    }
  }

  /// Reads the saved record; anything unreadable counts as never shown.
  static Map<String, DateTime> _parse(String? raw) {
    final shown = <String, DateTime>{};
    if (raw == null) return shown;
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return shown;
    }
    if (json is Map) {
      for (final entry in json.entries) {
        final id = entry.key;
        final value = entry.value;
        final at = value is String ? DateTime.tryParse(value) : null;
        if (id is String && at != null) shown[id] = at;
      }
    }
    return shown;
  }

  static bool _sameLocalDay(DateTime a, DateTime b) {
    final first = a.toLocal();
    final second = b.toLocal();
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }
}

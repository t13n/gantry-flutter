import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gantry/src/interstitials/frequency_tracker.dart';
import 'package:gantry/src/interstitials/interstitial.dart';
import 'package:gantry/src/log/gantry_log.dart';
import 'package:gantry/src/store/gantry_store.dart';

import '../support/fixtures.dart';

class _FailingStore implements GantryStore {
  @override
  Future<String?> read(String key) => throw StateError('read failed');

  @override
  Future<void> write(String key, String value) =>
      throw StateError('write failed');

  @override
  Future<void> remove(String key) => throw StateError('remove failed');
}

void main() {
  late DateTime now;
  late GantryStore store;
  late List<GantryLogEvent> logs;

  Interstitial campaign(String frequency, {String id = 'campaign-1'}) {
    final json = interstitialJson(overrides: {
      'id': id,
      'frequency': {'type': frequency},
    });
    return Interstitial.fromJson(json)!;
  }

  FrequencyTracker tracker() =>
      FrequencyTracker(store: store, now: () => now, log: LogSink(logs.add));

  setUp(() {
    now = DateTime(2026, 10, 7, 12);
    store = MemoryGantryStore();
    logs = [];
  });

  test('once: shown a single time, also after a restart', () async {
    final first = tracker();
    expect(await first.canShow(campaign('once')), isTrue);
    await first.markShown(campaign('once'));
    expect(await first.canShow(campaign('once')), isFalse);

    now = now.add(const Duration(days: 400));
    expect(await tracker().canShow(campaign('once')), isFalse);
  });

  test('daily: once per local calendar day, not per 24 hours', () async {
    now = DateTime(2026, 10, 7, 23);
    await tracker().markShown(campaign('daily'));

    now = DateTime(2026, 10, 7, 23, 30);
    expect(await tracker().canShow(campaign('daily')), isFalse);

    now = DateTime(2026, 10, 8, 8);
    expect(await tracker().canShow(campaign('daily')), isTrue);
  });

  test('everyLaunch: once per tracker, again after a restart', () async {
    final first = tracker();
    expect(await first.canShow(campaign('everyLaunch')), isTrue);
    await first.markShown(campaign('everyLaunch'));
    expect(await first.canShow(campaign('everyLaunch')), isFalse);

    expect(await tracker().canShow(campaign('everyLaunch')), isTrue);
  });

  test('records are per campaign id', () async {
    final frequency = tracker();
    await frequency.markShown(campaign('once', id: 'a'));
    expect(await frequency.canShow(campaign('once', id: 'a')), isFalse);
    expect(await frequency.canShow(campaign('once', id: 'b')), isTrue);
  });

  test('not marking leaves the campaign showable', () async {
    final frequency = tracker();
    expect(await frequency.canShow(campaign('once')), isTrue);
    expect(await frequency.canShow(campaign('once')), isTrue);
  });

  test('keeps the 200 most recently shown campaigns', () async {
    final frequency = tracker();
    for (var i = 0; i <= FrequencyTracker.maxEntries; i++) {
      now = now.add(const Duration(minutes: 1));
      await frequency.markShown(campaign('once', id: 'campaign-$i'));
    }

    final saved = jsonDecode((await store.read(FrequencyTracker.storeKey))!)
        as Map<String, dynamic>;
    expect(saved, hasLength(FrequencyTracker.maxEntries));
    expect(saved.containsKey('campaign-0'), isFalse);
    expect(saved.containsKey('campaign-200'), isTrue);
    expect(await tracker().canShow(campaign('once', id: 'campaign-0')), isTrue);
    expect(
        await tracker().canShow(campaign('once', id: 'campaign-1')), isFalse);
  });

  test('a corrupt record counts as never shown and is replaced', () async {
    for (final corrupt in [
      'not json',
      '[]',
      '{"campaign-1": 5}',
      '{"campaign-1": "yesterday"}'
    ]) {
      await store.write(FrequencyTracker.storeKey, corrupt);
      final frequency = tracker();
      expect(await frequency.canShow(campaign('once')), isTrue,
          reason: corrupt);
      await frequency.markShown(campaign('once'));
      expect(await tracker().canShow(campaign('once')), isFalse,
          reason: corrupt);
    }
  });

  test('a store that fails does not throw and is remembered in memory',
      () async {
    store = _FailingStore();
    final frequency = tracker();

    expect(await frequency.canShow(campaign('once')), isTrue);
    await frequency.markShown(campaign('once'));
    expect(await frequency.canShow(campaign('once')), isFalse);
    expect(
        logs.map((event) => event.level), everyElement(GantryLogLevel.warning));
    expect(logs, isNotEmpty);
  });
}

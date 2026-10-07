// Behaviour found missing by the pre-release review: values that must not leak
// into errors, races around a customer change, and bad data that must not
// replace good data.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gantry/gantry.dart';
import 'package:gantry/src/api/gantry_api.dart';
import 'package:gantry/src/common/response_cache.dart';
import 'package:gantry/src/interstitials/frequency_tracker.dart';
import 'package:gantry/src/log/gantry_log.dart' show LogSink;
import 'package:gantry/src/session.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fixtures.dart';
import 'support/http.dart';

/// A store whose first read waits until [gate] is completed.
class _GatedStore implements GantryStore {
  final gate = Completer<void>();
  int reads = 0;

  @override
  Future<String?> read(String key) async {
    reads++;
    await gate.future;
    return null;
  }

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> remove(String key) async {}
}

/// A store whose first [failures] reads throw, as a busy disk might.
class _FlakyStore extends MemoryGantryStore {
  _FlakyStore(this.failures);

  int failures;

  @override
  Future<String?> read(String key) {
    if (failures > 0) {
      failures--;
      throw StateError('read failed');
    }
    return super.read(key);
  }
}

Interstitial _campaign(String id, {String frequency = 'once'}) {
  return Interstitial.fromJson(interstitialJson(overrides: {
    'id': id,
    'frequency': {'type': frequency},
  }))!;
}

GantryApi _api(Future<http.Response> Function(http.Request request) respond) {
  return GantryApi(
    client: MockClient(respond),
    baseUrl: Uri.parse('https://gantry.test'),
    apiKey: 'k',
    userAgent: 'test',
  );
}

void main() {
  group('values that must not leak', () {
    test('a rejected customer id is not repeated in the error', () {
      final gantry = Gantry(
        apiKey: 'gk_dev_test',
        appVersion: '1',
        platform: GantryPlatform.ios,
        store: MemoryGantryStore(),
      );
      try {
        gantry.identify('ayse@example.com');
        fail('identify accepted a malformed id');
      } on ArgumentError catch (error) {
        expect(error.name, 'customerId');
        expect(error.toString(), isNot(contains('ayse')));
      }
    });

    test('a key that cannot be sent in a header is rejected up front', () {
      for (final key in [
        'gk_dev_abc\n',
        'gk_dev_abc\r\n',
        'gk dev',
        'gk_dev_ö'
      ]) {
        try {
          Gantry(apiKey: key, appVersion: '1', platform: GantryPlatform.ios);
          fail('accepted ${jsonEncode(key)}');
        } on ArgumentError catch (error) {
          expect(error.name, 'apiKey');
          expect(error.toString(), isNot(contains('gk')));
        }
      }
    });
  });

  test(
      'a targeted campaign is dropped when the customer changes while the display record loads',
      () async {
    final now = DateTime.utc(2026, 10, 7, 12);
    final session = Session()..identify('cust-a');
    final store = _GatedStore();
    const log = LogSink(null);
    final targeted = jsonEncode(interstitialJson(overrides: {
      'id': 'targeted-a',
      'audience': {'type': 'customers'},
    }));
    final interstitials = Interstitials(
      api: _api((_) async => jsonResponse(targeted)),
      session: session,
      remoteConfig: (key) => key == Interstitials.targetedParameterKey
          ? 'true'
          : jsonEncode(interstitialJson(overrides: {'id': 'general-1'})),
      frequency: FrequencyTracker(store: store, now: () => now, log: log),
      platform: GantryPlatform.ios,
      appVersion: '2.3.1',
      now: () => now,
      log: log,
    );

    final pending = interstitials.next();
    while (store.reads == 0) {
      await pumpEventQueue();
    }
    session.identify('cust-b');
    store.gate.complete();

    expect((await pending)?.id, 'general-1');
  });

  test('an empty English text reads as missing', () {
    final text = LocalizedText.fromJson({'tr': 'Merhaba', 'en': ''})!;
    expect(text.en, isNull);
    expect(text.en ?? text.tr, 'Merhaba');
  });

  group('bad data does not replace good data', () {
    late DateTime now;
    late List<GantryLogEvent> logs;

    setUp(() {
      now = DateTime.utc(2026, 10, 7, 12);
      logs = [];
    });

    test('cards: an unreadable refresh keeps serving the previous cards',
        () async {
      final bodies = [
        fixture('contents.json'),
        '<html>captive portal</html>',
        '{"items":[]}'
      ];
      final log = LogSink(logs.add);
      final contents = Contents(
        api: _api((_) async => jsonResponse(bodies.removeAt(0),
            headers: {'cache-control': 'max-age=60'})),
        cache: ResponseCache(now: () => now, log: log),
        platform: GantryPlatform.ios,
        log: log,
      );

      expect(await contents.list(), hasLength(2));

      now = now.add(const Duration(seconds: 61));
      expect(await contents.list(), hasLength(2));
      expect(logs.single.level, GantryLogLevel.warning);

      // The bad body was not cached: the next call asks again and recovers.
      expect(await contents.list(), isEmpty);
    });

    test('pages: a page this SDK version cannot read is skipped and logged',
        () async {
      final log = LogSink(logs.add);
      final pages = Pages(
        api:
            _api((_) async => jsonResponse('{"key":"kvkk","schemaVersion":2}')),
        cache: ResponseCache(now: () => now, log: log),
        log: log,
      );

      expect(await pages.get('kvkk'), isNull);
      expect(logs.single.level, GantryLogLevel.warning);
    });
  });

  group('display record', () {
    final now = DateTime(2026, 10, 7, 12);
    const log = LogSink(null);

    test('a read that fails once does not wipe the saved history', () async {
      final store = _FlakyStore(1);
      await store.write(
          FrequencyTracker.storeKey, '{"old":"2026-10-01T09:00:00.000Z"}');
      final tracker = FrequencyTracker(store: store, now: () => now, log: log);

      expect(await tracker.canShow(_campaign('new')), isTrue);
      await tracker.markShown(_campaign('new'));

      final saved = jsonDecode((await store.read(FrequencyTracker.storeKey))!)
          as Map<String, dynamic>;
      expect(saved.keys, containsAll(['old', 'new']));
      expect(await tracker.canShow(_campaign('old')), isFalse);
    });

    test('while the store cannot be read, nothing is written over it',
        () async {
      final store = _FlakyStore(100);
      await store.write(
          FrequencyTracker.storeKey, '{"old":"2026-10-01T09:00:00.000Z"}');
      final tracker = FrequencyTracker(store: store, now: () => now, log: log);

      await tracker.markShown(_campaign('new'));
      expect(await tracker.canShow(_campaign('new')), isFalse);

      store.failures = 0;
      expect(await store.read(FrequencyTracker.storeKey),
          '{"old":"2026-10-01T09:00:00.000Z"}');
    });

    test('two campaigns marked at the same time are both saved', () async {
      final store = MemoryGantryStore();
      final tracker = FrequencyTracker(store: store, now: () => now, log: log);

      await Future.wait([
        tracker.markShown(_campaign('a')),
        tracker.markShown(_campaign('b'))
      ]);

      final saved = jsonDecode((await store.read(FrequencyTracker.storeKey))!)
          as Map<String, dynamic>;
      expect(saved.keys, containsAll(['a', 'b']));
    });

    test('a campaign counts as shown as soon as markShown is called', () async {
      final tracker = FrequencyTracker(
          store: MemoryGantryStore(), now: () => now, log: log);
      final campaign = _campaign('launch', frequency: 'everyLaunch');

      final marking = tracker.markShown(campaign);
      expect(await tracker.canShow(campaign), isFalse);
      await marking;
    });
  });
}

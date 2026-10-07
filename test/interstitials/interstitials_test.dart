import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gantry/src/api/gantry_api.dart';
import 'package:gantry/src/common/gantry_platform.dart';
import 'package:gantry/src/interstitials/frequency_tracker.dart';
import 'package:gantry/src/interstitials/interstitials.dart';
import 'package:gantry/src/log/gantry_log.dart';
import 'package:gantry/src/session.dart';
import 'package:gantry/src/store/gantry_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fixtures.dart';
import '../support/http.dart';

const flag = Interstitials.targetedParameterKey;
const general = Interstitials.parameterKey;

String campaign(String id,
    {String audience = 'all', String frequency = 'once', bool enabled = true}) {
  return jsonEncode(interstitialJson(overrides: {
    'id': id,
    'enabled': enabled,
    'audience': {'type': audience},
    'frequency': {'type': frequency},
  }));
}

void main() {
  final now = DateTime.utc(2026, 10, 7, 12);
  late List<http.Request> requests;
  late List<GantryLogEvent> logs;
  late Session session;
  late MemoryGantryStore store;

  Interstitials build({
    Map<String, String?> remoteConfig = const {},
    RemoteConfigReader? reader,
    bool withReader = true,
    Future<http.Response> Function(http.Request request)? respond,
    Duration interstitialTimeout = const Duration(seconds: 2),
  }) {
    final client = MockClient((request) {
      requests.add(request);
      return respond == null
          ? Future.value(jsonResponse('{}'))
          : respond(request);
    });
    final log = LogSink(logs.add);
    return Interstitials(
      api: GantryApi(
        client: client,
        baseUrl: Uri.parse('https://gantry.test'),
        apiKey: 'gk_dev_test',
        userAgent: 'test',
        interstitialTimeout: interstitialTimeout,
      ),
      session: session,
      remoteConfig: withReader ? (reader ?? (key) => remoteConfig[key]) : null,
      frequency: FrequencyTracker(store: store, now: () => now, log: log),
      platform: GantryPlatform.ios,
      appVersion: '2.3.1',
      now: () => now,
      log: log,
    );
  }

  setUp(() {
    requests = [];
    logs = [];
    session = Session();
    store = MemoryGantryStore();
  });

  group('without a targeted campaign', () {
    test('returns the general campaign from Remote Config', () async {
      final interstitials =
          build(remoteConfig: {flag: 'false', general: campaign('general-1')});

      expect((await interstitials.next())!.id, 'general-1');
      expect(requests, isEmpty);
    });

    test('returns null when Remote Config has nothing to show', () async {
      for (final value in [null, '', '{}', 'not json']) {
        expect(await build(remoteConfig: {general: value}).next(), isNull,
            reason: '$value');
      }
    });

    test('logs a campaign it cannot read, but not an empty one', () async {
      await build(remoteConfig: {general: '{}'}).next();
      expect(logs, isEmpty);

      await build(remoteConfig: {general: '{"id":"x","schemaVersion":2}'})
          .next();
      expect(logs.single.level, GantryLogLevel.warning);
    });

    test('applies the eligibility filter to the general campaign', () async {
      final interstitials =
          build(remoteConfig: {general: campaign('general-1', enabled: false)});
      expect(await interstitials.next(), isNull);
    });

    test('does not call the API while the flag is off', () async {
      session.identify('cust-1001');
      for (final value in [null, '', 'false', '0', 'yes']) {
        await build(remoteConfig: {flag: value}).next();
      }
      expect(requests, isEmpty);
    });

    test('does not call the API before identify', () async {
      final interstitials =
          build(remoteConfig: {flag: 'true', general: campaign('general-1')});

      expect((await interstitials.next())!.id, 'general-1');
      expect(requests, isEmpty);
    });

    test('without a reader returns null and says why', () async {
      session.identify('cust-1001');
      expect(await build(withReader: false).next(), isNull);
      expect(requests, isEmpty);
      expect(logs.single.level, GantryLogLevel.warning);
    });

    test('a reader that throws yields null', () async {
      session.identify('cust-1001');
      final interstitials = build(
          reader: (key) => throw StateError('Firebase is not initialized'));

      expect(await interstitials.next(), isNull);
      expect(logs, isNotEmpty);
    });
  });

  group('with the flag on and a customer', () {
    setUp(() => session.identify('cust-1001'));

    test('prefers the targeted campaign', () async {
      final interstitials = build(
        remoteConfig: {flag: 'true', general: campaign('general-1')},
        respond: (_) async =>
            jsonResponse(campaign('targeted-1', audience: 'customers')),
      );

      expect((await interstitials.next())!.id, 'targeted-1');
      final request = requests.single;
      expect(request.url.path, '/api/v1/interstitial');
      expect(request.url.queryParameters,
          {'platform': 'ios', 'appVersion': '2.3.1'});
      expect(request.headers['x-customer-id'], 'cust-1001');
    });

    test('reads the flag case-insensitively', () async {
      for (final value in ['TRUE', 'True', ' true ']) {
        await build(remoteConfig: {flag: value}).next();
      }
      expect(requests, hasLength(3));
    });

    test('falls back to the general campaign when the API has none', () async {
      final interstitials = build(
        remoteConfig: {flag: 'true', general: campaign('general-1')},
        respond: (_) async => jsonResponse('{}'),
      );
      expect((await interstitials.next())!.id, 'general-1');
    });

    test('falls back to the general campaign when the API fails', () async {
      for (final status in [400, 429, 500, 503]) {
        final interstitials = build(
          remoteConfig: {flag: 'true', general: campaign('general-1')},
          respond: (_) async => http.Response('', status),
        );
        expect((await interstitials.next())!.id, 'general-1',
            reason: '$status');
      }
      expect(logs.map((event) => event.level),
          everyElement(GantryLogLevel.warning));
    });

    test('falls back and logs an error when the key is rejected', () async {
      final interstitials = build(
        remoteConfig: {flag: 'true', general: campaign('general-1')},
        respond: (_) async => http.Response('', 401),
      );

      expect((await interstitials.next())!.id, 'general-1');
      expect(logs.single.level, GantryLogLevel.error);
    });

    test('falls back when the API is too slow', () async {
      final interstitials = build(
        remoteConfig: {flag: 'true', general: campaign('general-1')},
        respond: (_) => Future.delayed(const Duration(milliseconds: 300),
            () => jsonResponse(campaign('targeted-1'))),
        interstitialTimeout: const Duration(milliseconds: 20),
      );
      expect((await interstitials.next())!.id, 'general-1');
    });

    test('falls back when the API returns a campaign it cannot read', () async {
      final interstitials = build(
        remoteConfig: {flag: 'true', general: campaign('general-1')},
        respond: (_) async => jsonResponse('{"id":"x","schemaVersion":2}'),
      );
      expect((await interstitials.next())!.id, 'general-1');
    });

    test('a targeted campaign already shown gives way to the general one',
        () async {
      final interstitials = build(
        remoteConfig: {flag: 'true', general: campaign('general-1')},
        respond: (_) async =>
            jsonResponse(campaign('targeted-1', audience: 'customers')),
      );

      final targeted = (await interstitials.next())!;
      await interstitials.markShown(targeted);
      final second = (await interstitials.next())!;
      expect(second.id, 'general-1');

      await interstitials.markShown(second);
      expect(await interstitials.next(), isNull);
    });

    test('next does not use up the frequency by itself', () async {
      final interstitials =
          build(remoteConfig: {general: campaign('general-1')});
      expect((await interstitials.next())!.id, 'general-1');
      expect((await interstitials.next())!.id, 'general-1');
    });

    test('revalidates with the etag and reuses the campaign on 304', () async {
      var calls = 0;
      final interstitials = build(
        remoteConfig: {flag: 'true'},
        respond: (request) async {
          calls++;
          return calls == 1
              ? jsonResponse(campaign('targeted-1', frequency: 'everyLaunch'),
                  headers: {'etag': 'W/"t1"'})
              : http.Response('', 304);
        },
      );

      expect((await interstitials.next())!.id, 'targeted-1');
      expect((await interstitials.next())!.id, 'targeted-1');
      expect(requests[0].headers.containsKey('if-none-match'), isFalse);
      expect(requests[1].headers['if-none-match'], 'W/"t1"');
    });

    test('forgets the cached campaign when the customer changes', () async {
      final interstitials = build(
        remoteConfig: {flag: 'true'},
        respond: (_) async =>
            jsonResponse(campaign('targeted-1'), headers: {'etag': 'W/"t1"'}),
      );

      await interstitials.next();
      session.reset();
      session.identify('cust-2002');
      await interstitials.next();

      expect(requests[1].headers.containsKey('if-none-match'), isFalse);
      expect(requests[1].headers['x-customer-id'], 'cust-2002');
    });

    test('drops a response that arrives after the customer changed', () async {
      final gate = Completer<http.Response>();
      final interstitials =
          build(remoteConfig: {flag: 'true'}, respond: (_) => gate.future);

      final pending = interstitials.next();
      session.identify('cust-2002');
      gate.complete(
          jsonResponse(campaign('targeted-1'), headers: {'etag': 'W/"t1"'}));

      expect(await pending, isNull);
      expect(session.targeted, isNull);
    });
  });

  test('markShown never throws', () async {
    final interstitials = build(remoteConfig: {general: campaign('general-1')});
    final interstitial = (await interstitials.next())!;
    await expectLater(interstitials.markShown(interstitial), completes);
  });
}

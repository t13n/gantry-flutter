// Public-API details settled before the first release: argument checks, value
// semantics of the models and readable errors.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gantry/gantry.dart';
import 'package:gantry/src/api/gantry_api.dart';
import 'package:gantry/src/common/response_cache.dart';
import 'package:gantry/src/log/gantry_log.dart' show LogSink;
import 'package:gantry/src/session.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fixtures.dart';

void main() {
  test('a base url must be an http or https address with a host', () {
    for (final url in [
      'localhost:3000',
      'ftp://example.com',
      'https://',
      '/relative',
      'app.gantryhq.net'
    ]) {
      expect(
        () => Gantry(
            apiKey: 'k',
            appVersion: '1',
            platform: GantryPlatform.ios,
            baseUrl: Uri.parse(url)),
        throwsA(isA<ArgumentError>()
            .having((error) => error.name, 'name', 'baseUrl')),
        reason: url,
      );
    }
  });

  test(
      'a lead is retried on a server error only, not on other unexpected answers',
      () async {
    for (final status in [302, 403, 404]) {
      final requests = <http.Request>[];
      final answers = [status, 201];
      final leads = Leads(
        api: GantryApi(
          client: MockClient((request) async {
            requests.add(request);
            return http.Response('', answers.removeAt(0));
          }),
          baseUrl: Uri.parse('https://gantry.test'),
          apiKey: 'k',
          userAgent: 'test',
        ),
        session: Session()..identify('cust-1'),
        platform: GantryPlatform.ios,
        appVersion: '1',
        log: const LogSink(null),
        delay: (_) async {},
      );

      await expectLater(
        leads.submit(campaignId: 'c'),
        throwsA(isA<GantryServerException>()
            .having((error) => error.statusCode, 'statusCode', status)),
      );
      expect(requests, hasLength(1), reason: '$status');
    }
  });

  test('errors print their own name, also in obfuscated builds', () {
    expect(const GantryNetworkException('offline').toString(),
        'GantryNetworkException: offline');
    expect(const GantryUnauthorizedException().toString(),
        startsWith('GantryUnauthorizedException: '));
    expect(const GantryRateLimitedException().toString(),
        startsWith('GantryRateLimitedException: '));
    expect(const GantryRequestException().toString(),
        startsWith('GantryRequestException: '));
    expect(const GantryNotIdentifiedException().toString(),
        startsWith('GantryNotIdentifiedException: '));
    expect(
      const GantryServerException(503).toString(),
      allOf(startsWith('GantryServerException: '), endsWith('(HTTP 503)')),
    );
  });

  group('interstitial platforms', () {
    Interstitial withPlatforms(List<String> platforms) {
      return Interstitial.fromJson(
          interstitialJson(overrides: {'platform': platforms}))!;
    }

    test('are typed, and "all" means both', () {
      expect(withPlatforms(['all']).platforms,
          {GantryPlatform.ios, GantryPlatform.android});
      expect(withPlatforms(['ios']).platforms, {GantryPlatform.ios});
      expect(withPlatforms(['android', 'ios']).platforms,
          {GantryPlatform.ios, GantryPlatform.android});
    });

    test('ignore a platform this SDK does not know', () {
      expect(withPlatforms(['ios', 'web']).platforms, {GantryPlatform.ios});
      expect(withPlatforms(['web']).platforms, isEmpty);
    });

    test('cannot be changed by the app', () {
      expect(() => withPlatforms(['ios']).platforms.add(GantryPlatform.android),
          throwsUnsupportedError);
    });
  });

  group('models compare by value and describe themselves', () {
    Map<String, dynamic> cardJson() {
      final json = jsonDecode(fixture('contents.json')) as Map<String, dynamic>;
      return (json['items'] as List).first as Map<String, dynamic>;
    }

    Map<String, dynamic> pageJson() =>
        jsonDecode(fixture('page.json')) as Map<String, dynamic>;

    test('interstitial', () {
      final a = Interstitial.fromJson(interstitialJson())!;
      final b = Interstitial.fromJson(interstitialJson())!;
      final other =
          Interstitial.fromJson(interstitialJson(overrides: {'priority': 1}))!;

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(other));
      expect(a.toString(), 'Interstitial(splash-deeplink)');
    });

    test('content card', () {
      final a = ContentCard.fromJson(cardJson())!;
      final b = ContentCard.fromJson(cardJson())!;
      final other =
          ContentCard.fromJson({...cardJson(), 'category': 'duyuru'})!;

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(other));
      expect(a.toString(), 'ContentCard(yaz-kampanyasi)');
    });

    test('content page and body', () {
      final a = ContentPage.fromJson(pageJson())!;
      final b = ContentPage.fromJson(pageJson())!;
      final other = ContentPage.fromJson({...pageJson(), 'key': 'sss'})!;

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.body, b.body);
      expect(a, isNot(other));
      expect(a.toString(), 'ContentPage(kvkk)');
    });

    test('actions', () {
      GantryAction read(Map<String, dynamic> json) =>
          GantryAction.fromJson(json)!;

      expect(read({'type': 'redirect', 'deeplink': 'a://b'}),
          read({'type': 'redirect', 'deeplink': 'a://b'}));
      expect(read({'type': 'redirect', 'deeplink': 'a://b'}),
          isNot(read({'type': 'redirect', 'deeplink': 'a://c'})));
      expect(read({'type': 'webPage', 'url': 'https://a.b'}),
          read({'type': 'webPage', 'url': 'https://a.b'}));
      expect(read({'type': 'lead'}), read({'type': 'lead'}));
      expect(read({'type': 'lead'}), isNot(read({'type': 'dismiss'})));
      expect(read({'type': 'lead'}),
          isNot(read({'type': 'lead', 'trackingEvent': 'x'})));
      expect(read({'type': 'redirect', 'deeplink': 'a://b'}).toString(),
          'GantryRedirectAction(a://b)');
      expect(read({'type': 'dismiss'}).toString(), 'GantryDismissAction()');
    });
  });

  test('a 304 with nothing cached is an unexpected answer', () async {
    final cache =
        ResponseCache(now: () => DateTime.utc(2026), log: const LogSink(null));
    await expectLater(
      cache.fetch(
          'k', (etag) async => const ApiResponse(statusCode: 304, body: '')),
      throwsA(isA<GantryServerException>()),
    );
  });

  test('log events never carry the key or the customer id, whatever fails',
      () async {
    const key = 'gk_dev_secretsecretsecret';
    const customer = 'cust-private-42';
    final failures = <Future<http.Response> Function(http.Request)>[
      (_) async => http.Response('', 401),
      (_) async => http.Response('', 500),
      (_) async => throw http.ClientException('connection refused'),
      (request) async => throw Exception('failed for ${request.url}'),
      (_) async => http.Response('not json', 200),
    ];

    for (final respond in failures) {
      final events = <GantryLogEvent>[];
      final gantry = Gantry(
        apiKey: key,
        appVersion: '1',
        platform: GantryPlatform.ios,
        remoteConfig: (name) =>
            name == 'bo_interstitial_targeted' ? 'true' : 'not json',
        httpClient: MockClient(respond),
        store: MemoryGantryStore(),
        onLog: events.add,
      )..identify(customer);

      await gantry.interstitials.next();

      expect(events, isNotEmpty);
      for (final event in events) {
        final text = '$event ${event.error}';
        expect(text, isNot(contains(key)));
        expect(text, isNot(contains(customer)));
      }
    }
  });
}

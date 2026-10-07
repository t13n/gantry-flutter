import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gantry/gantry.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fixtures.dart';
import 'support/http.dart';

class _TrackingClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
        Stream.value(utf8.encode('{"items":[]}')), 200);
  }

  @override
  void close() => closed = true;
}

void main() {
  late List<http.Request> requests;

  Gantry build({
    Future<http.Response> Function(http.Request request)? respond,
    Map<String, String?> remoteConfig = const {},
    Uri? baseUrl,
    GantryLogger? onLog,
  }) {
    return Gantry(
      apiKey: 'gk_dev_test',
      appVersion: '2.3.1',
      platform: GantryPlatform.ios,
      remoteConfig: (key) => remoteConfig[key],
      baseUrl: baseUrl,
      httpClient: MockClient((request) {
        requests.add(request);
        return respond == null
            ? Future.value(jsonResponse('{}'))
            : respond(request);
      }),
      store: MemoryGantryStore(),
      onLog: onLog,
    );
  }

  setUp(() => requests = []);

  group('construction', () {
    test('rejects an empty key and a malformed version', () {
      expect(
          () => Gantry(
              apiKey: ' ', appVersion: '1.0.0', platform: GantryPlatform.ios),
          throwsArgumentError);
      expect(
          () => Gantry(
              apiKey: 'k', appVersion: 'v1', platform: GantryPlatform.ios),
          throwsArgumentError);
    });

    test('detects the platform when none is given', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final gantry = Gantry(
          apiKey: 'k',
          appVersion: '1',
          httpClient: MockClient((request) async {
            requests.add(request);
            return jsonResponse('{"items":[]}');
          }),
          store: MemoryGantryStore(),
        );
        await gantry.contents.list();
        expect(requests.single.url.queryParameters['platform'], 'android');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('asks for the platform where it cannot detect one', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        expect(() => Gantry(apiKey: 'k', appVersion: '1'), throwsArgumentError);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('talks to app.gantryhq.net unless told otherwise', () async {
      await build(respond: (_) async => jsonResponse('{"items":[]}'))
          .contents
          .list();
      await build(
        respond: (_) async => jsonResponse('{"items":[]}'),
        baseUrl: Uri.parse('http://localhost:3000'),
      ).contents.list();

      expect(requests.map((request) => request.url.origin),
          ['https://app.gantryhq.net', 'http://localhost:3000']);
    });

    test('sends the package version as the user agent', () async {
      await build(respond: (_) async => jsonResponse('{"items":[]}'))
          .contents
          .list();
      expect(requests.single.headers['user-agent'],
          matches(r'^gantry-flutter/\d+\.\d+\.\d+$'));
    });
  });

  group('identity', () {
    test('identify and reset drive isIdentified', () {
      final gantry = build();
      expect(gantry.isIdentified, isFalse);
      gantry.identify('cust-1001');
      expect(gantry.isIdentified, isTrue);
      gantry.reset();
      expect(gantry.isIdentified, isFalse);
    });

    test('identify rejects a malformed customer id', () {
      expect(() => build().identify('not valid!'), throwsArgumentError);
    });

    test('a lead needs a customer', () async {
      final gantry = build(respond: (_) async => http.Response('', 201));

      await expectLater(gantry.leads.submit(campaignId: 'c'),
          throwsA(isA<GantryNotIdentifiedException>()));
      gantry.identify('cust-1001');
      await gantry.leads.submit(campaignId: 'c');
      gantry.reset();
      await expectLater(gantry.leads.submit(campaignId: 'c'),
          throwsA(isA<GantryNotIdentifiedException>()));
      expect(requests, hasLength(1));
    });
  });

  test('walks the whole interstitial flow through the public API', () async {
    final targeted = jsonEncode(interstitialJson(overrides: {
      'id': 'coaching-lead',
      'audience': {'type': 'customers'},
    }));
    // Gantry uses the real clock, so the general campaign gets a window that
    // does not expire with the fixture's dates.
    final general = jsonEncode(interstitialJson(overrides: {
      'startAt': '2020-01-01T00:00:00.000Z',
      'endAt': '2099-01-01T00:00:00.000Z',
    }));
    final gantry = build(
      remoteConfig: {
        'bo_interstitial_targeted': 'true',
        'bo_interstitial': general
      },
      respond: (request) async {
        return request.method == 'POST'
            ? http.Response('', 201)
            : jsonResponse(targeted);
      },
    );

    expect((await gantry.interstitials.next())!.id, 'splash-deeplink');

    gantry.identify('cust-1001');
    final interstitial = (await gantry.interstitials.next())!;
    expect(interstitial.id, 'coaching-lead');
    expect(interstitial.audience, InterstitialAudience.customers);

    await gantry.interstitials.markShown(interstitial);
    final description = switch (interstitial.secondaryAction) {
      GantryLeadAction() => 'lead',
      GantryRedirectAction() ||
      GantryWebPageAction() ||
      GantryDismissAction() ||
      null =>
        'other',
    };
    expect(description, 'lead');
    await gantry.leads.submit(campaignId: interstitial.id);

    expect(requests.last.method, 'POST');
    expect((await gantry.interstitials.next())!.id, 'splash-deeplink');
  });

  test('loads cards and pages through the public API', () async {
    final gantry = build(
      respond: (request) async {
        return jsonResponse(fixture(request.url.path.endsWith('/contents')
            ? 'contents.json'
            : 'page.json'));
      },
    );

    final List<ContentCard> cards =
        await gantry.contents.list(category: 'kampanya');
    final ContentPage? page = await gantry.pages.get('kvkk');

    expect(cards.first.title.resolve('en'), 'Summer deal');
    expect(page!.body.html.resolve('tr'), startsWith('<h2>'));
  });

  test('reports problems to onLog without the key or the customer id',
      () async {
    final events = <GantryLogEvent>[];
    final gantry = build(
      remoteConfig: {'bo_interstitial_targeted': 'true'},
      respond: (_) async => http.Response('', 401),
      onLog: events.add,
    )..identify('cust-1001');

    expect(await gantry.interstitials.next(), isNull);
    expect(events.single.level, GantryLogLevel.error);
    expect(events.single.toString(), isNot(contains('gk_dev_test')));
    expect(events.single.toString(), isNot(contains('cust-1001')));
  });

  test('close leaves a client it was given open', () {
    final client = _TrackingClient();
    Gantry(
            apiKey: 'k',
            appVersion: '1',
            platform: GantryPlatform.ios,
            httpClient: client,
            store: MemoryGantryStore())
        .close();
    expect(client.closed, isFalse);
  });
}

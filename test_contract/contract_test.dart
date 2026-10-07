@Tags(['contract'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gantry/gantry.dart';
import 'package:gantry/src/api/gantry_api.dart';
import 'package:http/http.dart' as http;

// Runs against a local Gantry: bin/rails db:seed && bin/dev in the backoffice
// repository, then `flutter test test_contract` here.
const baseUrl = String.fromEnvironment('GANTRY_BASE_URL',
    defaultValue: 'http://localhost:3000');
const apiKey = String.fromEnvironment('GANTRY_API_KEY',
    defaultValue: 'gk_dev_seedseedseedseedseedseedseedseed');

void main() {
  late List<GantryLogEvent> logs;
  late Gantry gantry;
  late http.Client client;

  Gantry build({String key = apiKey}) {
    return Gantry(
      apiKey: key,
      appVersion: '9.0.0',
      platform: GantryPlatform.ios,
      baseUrl: Uri.parse(baseUrl),
      remoteConfig: (key) => key == 'bo_interstitial_targeted' ? 'true' : null,
      store: MemoryGantryStore(),
      onLog: logs.add,
    );
  }

  setUp(() {
    logs = [];
    gantry = build();
    client = http.Client();
  });

  tearDown(() {
    gantry.close();
    client.close();
  });

  test('the server is reachable', () async {
    final response = await client.get(Uri.parse('$baseUrl/up'));
    expect(response.statusCode, 200,
        reason: 'Start the backoffice with bin/dev first');
  });

  test(
      'the interstitial endpoint answers with a campaign this SDK reads, or {}',
      () async {
    final api = GantryApi(
        client: client,
        baseUrl: Uri.parse(baseUrl),
        apiKey: apiKey,
        userAgent: 'gantry-contract');
    final response = await api.getInterstitial(
        customerId: 'cust-1001', platform: 'ios', appVersion: '9.0.0');

    expect(response.statusCode, 200);
    expect(response.etag, isNotNull);
    if (response.body.trim() != '{}') {
      final interstitial = Interstitial.tryParse(response.body);
      expect(interstitial, isNotNull, reason: response.body);
      expect(interstitial!.audience, InterstitialAudience.customers);
    }

    final again = await api.getInterstitial(
      customerId: 'cust-1001',
      platform: 'ios',
      appVersion: '9.0.0',
      etag: response.etag,
    );
    expect(again.statusCode, 304);
  });

  test('next() completes without warnings for an identified customer',
      () async {
    gantry.identify('cust-1001');
    await gantry.interstitials.next();
    expect(logs.where((event) => event.level != GantryLogLevel.debug), isEmpty);
  });

  test('a lead is accepted, also when repeated', () async {
    gantry.identify('cust-contract-1');
    await gantry.leads.submit(campaignId: 'coaching-lead');
    await gantry.leads.submit(campaignId: 'coaching-lead');
  });

  test('a lead for an unknown campaign is a rejected request', () async {
    gantry.identify('cust-contract-1');
    await expectLater(
      gantry.leads.submit(campaignId: 'no-such-campaign'),
      throwsA(isA<GantryRequestException>()),
    );
  });

  test('the card list is read without skipping a card', () async {
    final cards = await gantry.contents.list();

    expect(cards, isA<List<ContentCard>>());
    expect(logs.where((event) => event.level != GantryLogLevel.debug), isEmpty);
    for (final card in cards) {
      expect(card.title.tr, isNotEmpty);
    }
  });

  test('the card endpoint sends an etag and max-age, and honours If-None-Match',
      () async {
    final api = GantryApi(
        client: client,
        baseUrl: Uri.parse(baseUrl),
        apiKey: apiKey,
        userAgent: 'gantry-contract');
    final response = await api.getContents(platform: 'ios');

    expect(response.maxAge, const Duration(seconds: 60));
    expect(response.etag, isNotNull);
    expect(
        (await api.getContents(platform: 'ios', etag: response.etag))
            .statusCode,
        304);
  });

  test('a page is read when published and is null otherwise', () async {
    final page = await gantry.pages.get('kvkk');
    if (page != null) {
      expect(page.title.tr, isNotEmpty);
      expect(page.body.html.tr, contains('<'));
    }
    expect(await gantry.pages.get('no-such-page'), isNull);
  });

  test('a wrong key is unauthorized', () async {
    final wrong = build(key: 'gk_dev_wrongwrongwrongwrongwrongwrongwr');
    addTearDown(wrong.close);
    await expectLater(
        wrong.contents.list(), throwsA(isA<GantryUnauthorizedException>()));
  });
}

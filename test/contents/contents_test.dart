import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gantry/src/api/gantry_api.dart';
import 'package:gantry/src/api/gantry_exception.dart';
import 'package:gantry/src/common/gantry_platform.dart';
import 'package:gantry/src/common/response_cache.dart';
import 'package:gantry/src/contents/contents.dart';
import 'package:gantry/src/log/gantry_log.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fixtures.dart';
import '../support/http.dart';

void main() {
  late DateTime now;
  late List<http.Request> requests;
  late List<GantryLogEvent> logs;

  Contents build(Future<http.Response> Function(http.Request request) respond) {
    final client = MockClient((request) {
      requests.add(request);
      return respond(request);
    });
    final log = LogSink(logs.add);
    return Contents(
      api: GantryApi(
          client: client,
          baseUrl: Uri.parse('https://gantry.test'),
          apiKey: 'k',
          userAgent: 'test'),
      cache: ResponseCache(now: () => now, log: log),
      platform: GantryPlatform.ios,
      log: log,
    );
  }

  http.Response cards() {
    return jsonResponse(fixture('contents.json'),
        headers: {'etag': '"c1"', 'cache-control': 'max-age=60, private'});
  }

  setUp(() {
    now = DateTime.utc(2026, 10, 7, 12);
    requests = [];
    logs = [];
  });

  test('lists the cards in the order the server sent them', () async {
    final list = await build((_) async => cards()).list();

    expect(list.map((card) => card.key), ['yaz-kampanyasi', 'bakim-duyurusu']);
    expect(requests.single.url.queryParameters, {'platform': 'ios'});
    expect(requests.single.headers.containsKey('x-customer-id'), isFalse);
  });

  test('an empty list is a result, not an error', () async {
    expect(
        await build((_) async => jsonResponse('{"items":[]}')).list(), isEmpty);
  });

  test('filters by category and caches each category separately', () async {
    final contents = build((_) async => cards());

    await contents.list(category: 'kampanya');
    await contents.list(category: 'kampanya');
    await contents.list(category: 'duyuru');
    await contents.list();

    expect(requests.map((request) => request.url.queryParameters['category']),
        ['kampanya', 'duyuru', null]);
  });

  test('rejects a malformed category before sending', () async {
    final contents = build((_) async => cards());
    for (final category in ['', 'Kampanya', 'yaz kampanyası', 'a/b', 'a&b=c']) {
      await expectLater(contents.list(category: category), throwsArgumentError,
          reason: category);
    }
    expect(requests, isEmpty);
  });

  test('revalidates after max-age and reuses the cards on 304', () async {
    var calls = 0;
    final contents =
        build((_) async => ++calls == 1 ? cards() : http.Response('', 304));

    await contents.list();
    now = now.add(const Duration(seconds: 61));
    final list = await contents.list();

    expect(list, hasLength(2));
    expect(requests[1].headers['if-none-match'], '"c1"');
  });

  test('skips a card it cannot read and keeps the rest', () async {
    final json = jsonDecode(fixture('contents.json')) as Map<String, dynamic>;
    (json['items'] as List)
        .insert(1, {'key': 'future-card', 'schemaVersion': 2});

    final list =
        await build((_) async => jsonResponse(jsonEncode(json))).list();

    expect(list.map((card) => card.key), ['yaz-kampanyasi', 'bakim-duyurusu']);
    expect(logs.single.level, GantryLogLevel.warning);
  });

  test('throws a server error for a body that is not a card list', () async {
    for (final body in ['<html>', '[]', '{"cards":[]}', '{"items":{}}']) {
      await expectLater(
        build((_) async => jsonResponse(body)).list(),
        throwsA(isA<GantryServerException>()),
        reason: body,
      );
    }
  });

  test('throws when the request fails and nothing is cached', () async {
    await expectLater(
      build((_) async => http.Response('', 401)).list(),
      throwsA(isA<GantryUnauthorizedException>()),
    );
    await expectLater(
      build((_) async => throw http.ClientException('offline')).list(),
      throwsA(isA<GantryNetworkException>()),
    );
  });

  test('serves the previous cards when a later request fails', () async {
    var calls = 0;
    final contents =
        build((_) async => ++calls == 1 ? cards() : http.Response('', 503));

    await contents.list();
    now = now.add(const Duration(seconds: 61));

    expect(await contents.list(), hasLength(2));
    expect(logs.single.level, GantryLogLevel.warning);
  });
}

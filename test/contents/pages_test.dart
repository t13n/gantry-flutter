import 'package:flutter_test/flutter_test.dart';
import 'package:gantry/src/api/gantry_api.dart';
import 'package:gantry/src/api/gantry_exception.dart';
import 'package:gantry/src/common/response_cache.dart';
import 'package:gantry/src/contents/pages.dart';
import 'package:gantry/src/log/gantry_log.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fixtures.dart';
import '../support/http.dart';

void main() {
  late DateTime now;
  late List<http.Request> requests;

  Pages build(Future<http.Response> Function(http.Request request) respond) {
    final client = MockClient((request) {
      requests.add(request);
      return respond(request);
    });
    return Pages(
      api: GantryApi(
          client: client,
          baseUrl: Uri.parse('https://gantry.test'),
          apiKey: 'k',
          userAgent: 'test'),
      cache: ResponseCache(now: () => now, log: const LogSink(null)),
      log: const LogSink(null),
    );
  }

  http.Response page() {
    return jsonResponse(fixture('page.json'),
        headers: {'etag': '"p1"', 'cache-control': 'max-age=60, private'});
  }

  setUp(() {
    now = DateTime.utc(2026, 10, 7, 12);
    requests = [];
  });

  test('returns the page', () async {
    final content = await build((_) async => page()).get('kvkk');

    expect(content!.title.tr, 'KVKK Aydınlatma Metni');
    expect(requests.single.url.path, '/api/v1/pages/kvkk');
  });

  test('returns null for a page that is not published', () async {
    expect(await build((_) async => http.Response('', 404)).get('sss'), isNull);
  });

  test('rejects a malformed key before sending', () async {
    final pages = build((_) async => page());
    for (final key in ['', 'KVKK', 'a b', '../leads', 'a/b', 'kvkk?x=1']) {
      await expectLater(pages.get(key), throwsArgumentError, reason: key);
    }
    expect(requests, isEmpty);
  });

  test('caches each page for max-age', () async {
    final pages = build((_) async => page());

    await pages.get('kvkk');
    await pages.get('kvkk');
    await pages.get('sss');
    expect(requests.map((request) => request.url.path),
        ['/api/v1/pages/kvkk', '/api/v1/pages/sss']);

    now = now.add(const Duration(seconds: 61));
    await pages.get('kvkk');
    expect(requests.last.headers['if-none-match'], '"p1"');
  });

  test('throws a server error for a page it cannot read', () async {
    await expectLater(
      build((_) async => jsonResponse('<html>')).get('kvkk'),
      throwsA(isA<GantryServerException>()),
    );
  });

  test('throws when the request fails and nothing is cached', () async {
    await expectLater(
      build((_) async => http.Response('', 500)).get('kvkk'),
      throwsA(isA<GantryServerException>()),
    );
  });
}

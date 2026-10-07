import 'package:flutter_test/flutter_test.dart';
import 'package:gantry/src/api/gantry_api.dart';
import 'package:gantry/src/api/gantry_exception.dart';
import 'package:gantry/src/common/response_cache.dart';
import 'package:gantry/src/log/gantry_log.dart';

void main() {
  late DateTime now;
  late ResponseCache cache;
  late List<String?> etags;

  /// A request that records the etag it was given and then runs [answer].
  Future<ApiResponse> Function(String? etag) request(
      ApiResponse Function() answer) {
    return (etag) async {
      etags.add(etag);
      return answer();
    };
  }

  ApiResponse ok(String body, {String? etag = '"e1"', int maxAge = 60}) {
    return ApiResponse(
        statusCode: 200,
        body: body,
        etag: etag,
        maxAge: Duration(seconds: maxAge));
  }

  setUp(() {
    now = DateTime.utc(2026, 10, 7, 12);
    cache = ResponseCache(now: () => now, log: const LogSink(null));
    etags = [];
  });

  test('serves from memory until max-age passes', () async {
    expect(await cache.fetch('k', request(() => ok('first'))), 'first');

    now = now.add(const Duration(seconds: 59));
    expect(await cache.fetch('k', request(() => ok('second'))), 'first');
    expect(etags, [null]);
  });

  test('revalidates with the etag once stale and keeps the body on 304',
      () async {
    await cache.fetch('k', request(() => ok('first')));

    now = now.add(const Duration(seconds: 60));
    const notModified =
        ApiResponse(statusCode: 304, body: '', maxAge: Duration(seconds: 60));
    expect(await cache.fetch('k', request(() => notModified)), 'first');
    expect(etags, [null, '"e1"']);

    now = now.add(const Duration(seconds: 30));
    expect(await cache.fetch('k', request(() => ok('unused'))), 'first');
    expect(etags, hasLength(2));
  });

  test('replaces the body when the server sends a new one', () async {
    await cache.fetch('k', request(() => ok('first')));
    now = now.add(const Duration(seconds: 61));

    expect(await cache.fetch('k', request(() => ok('second', etag: '"e2"'))),
        'second');
    now = now.add(const Duration(seconds: 61));
    await cache.fetch('k', request(() => ok('third')));
    expect(etags, [null, '"e1"', '"e2"']);
  });

  test('without max-age every call revalidates', () async {
    const noCache = ApiResponse(statusCode: 200, body: 'first', etag: '"e1"');
    await cache.fetch('k', request(() => noCache));
    await cache.fetch('k', request(() => noCache));
    expect(etags, [null, '"e1"']);
  });

  test('keys are independent', () async {
    await cache.fetch('a', request(() => ok('A')));
    expect(await cache.fetch('b', request(() => ok('B'))), 'B');
    expect(etags, [null, null]);
  });

  test('returns null and forgets the entry on 404', () async {
    await cache.fetch('k', request(() => ok('first')));
    now = now.add(const Duration(seconds: 61));

    const missing = ApiResponse(statusCode: 404, body: '');
    expect(await cache.fetch('k', request(() => missing)), isNull);
    await cache.fetch('k', request(() => ok('again')));
    expect(etags.last, isNull);
  });

  test('serves the stale body when the network, the limit or the server fails',
      () async {
    await cache.fetch('k', request(() => ok('first')));
    final failures = <GantryException>[
      const GantryNetworkException('offline'),
      const GantryRateLimitedException(),
      const GantryServerException(503),
    ];
    for (final failure in failures) {
      now = now.add(const Duration(seconds: 61));
      expect(await cache.fetch('k', request(() => throw failure)), 'first',
          reason: '$failure');
    }
  });

  test('rethrows when there is nothing cached', () async {
    await expectLater(
      cache.fetch(
          'k', request(() => throw const GantryNetworkException('offline'))),
      throwsA(isA<GantryNetworkException>()),
    );
  });

  test('never hides a rejected key or a rejected request behind stale data',
      () async {
    await cache.fetch('k', request(() => ok('first')));
    now = now.add(const Duration(seconds: 61));

    await expectLater(
      cache.fetch(
          'k', request(() => throw const GantryUnauthorizedException())),
      throwsA(isA<GantryUnauthorizedException>()),
    );
    await expectLater(
      cache.fetch('k', request(() => throw const GantryRequestException())),
      throwsA(isA<GantryRequestException>()),
    );
  });
}

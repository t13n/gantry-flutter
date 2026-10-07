import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gantry/src/api/gantry_api.dart';
import 'package:gantry/src/api/gantry_exception.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/http.dart';

void main() {
  late List<http.Request> requests;

  GantryApi api(
    Future<http.Response> Function(http.Request request) respond, {
    String baseUrl = 'https://app.gantryhq.net',
    Duration interstitialTimeout = const Duration(seconds: 2),
    Duration timeout = const Duration(seconds: 5),
  }) {
    final client = MockClient((request) {
      requests.add(request);
      return respond(request);
    });
    return GantryApi(
      client: client,
      baseUrl: Uri.parse(baseUrl),
      apiKey: 'gk_dev_test',
      userAgent: 'gantry-flutter/9.9.9',
      interstitialTimeout: interstitialTimeout,
      timeout: timeout,
    );
  }

  Future<ApiResponse> interstitial(GantryApi api, {String? etag}) {
    return api.getInterstitial(
        customerId: 'cust-1001',
        platform: 'ios',
        appVersion: '2.3.1',
        etag: etag);
  }

  setUp(() => requests = []);

  group('getInterstitial', () {
    test('sends the key, the customer id in a header and the client info',
        () async {
      await interstitial(api((_) async => jsonResponse('{}')));

      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.url.toString(),
          'https://app.gantryhq.net/api/v1/interstitial?platform=ios&appVersion=2.3.1');
      expect(request.headers['authorization'], 'Bearer gk_dev_test');
      expect(request.headers['x-customer-id'], 'cust-1001');
      expect(request.headers['user-agent'], 'gantry-flutter/9.9.9');
      expect(request.headers.containsKey('if-none-match'), isFalse);
      expect(request.url.toString(), isNot(contains('cust-1001')));
    });

    test('revalidates with If-None-Match and reports 304', () async {
      final response = await interstitial(
          api((_) async => http.Response('', 304)),
          etag: 'W/"abc"');

      expect(requests.single.headers['if-none-match'], 'W/"abc"');
      expect(response.statusCode, 304);
    });

    test('returns the body and the etag', () async {
      final response = await interstitial(api((_) async =>
          jsonResponse('{"id":"a"}', headers: {'etag': 'W/"abc"'})));

      expect(response.statusCode, 200);
      expect(response.body, '{"id":"a"}');
      expect(response.etag, 'W/"abc"');
      expect(response.maxAge, isNull);
    });

    test('decodes the body as UTF-8 without a charset', () async {
      final bytes = utf8.encode('{"title":"Sağlıklı Şehirler"}');
      final response = await interstitial(
        api((_) async => http.Response.bytes(bytes, 200,
            headers: {'content-type': 'application/json'})),
      );

      expect(response.body, '{"title":"Sağlıklı Şehirler"}');
    });

    test('times out after the interstitial timeout', () async {
      final slow = api(
        (_) => Future.delayed(
            const Duration(milliseconds: 300), () => jsonResponse('{}')),
        interstitialTimeout: const Duration(milliseconds: 20),
      );

      await expectLater(
          interstitial(slow), throwsA(isA<GantryNetworkException>()));
    });
  });

  group('status codes', () {
    Future<void> expectError(int status, Matcher matcher) async {
      await expectLater(
          interstitial(api((_) async => http.Response('', status))),
          throwsA(matcher));
    }

    test('401 is unauthorized',
        () => expectError(401, isA<GantryUnauthorizedException>()));
    test('429 is rate limited',
        () => expectError(429, isA<GantryRateLimitedException>()));
    test('400 is a rejected request',
        () => expectError(400, isA<GantryRequestException>()));
    test('5xx is a server error', () {
      return expectError(
          503,
          isA<GantryServerException>()
              .having((e) => e.statusCode, 'statusCode', 503));
    });
    test('an unexpected code is a server error', () {
      return expectError(
          302,
          isA<GantryServerException>()
              .having((e) => e.statusCode, 'statusCode', 302));
    });
    test('404 on a customer endpoint is a server error',
        () => expectError(404, isA<GantryServerException>()));
  });

  group('connection problems', () {
    test('a client exception is a network error', () async {
      final failing =
          api((_) async => throw http.ClientException('connection refused'));
      await expectLater(
          interstitial(failing), throwsA(isA<GantryNetworkException>()));
    });

    test('any other exception is a network error that keeps the cause',
        () async {
      final cause = Exception('handshake failed');
      final failing = api((_) async => throw cause);
      await expectLater(
        interstitial(failing),
        throwsA(isA<GantryNetworkException>()
            .having((e) => e.cause, 'cause', same(cause))),
      );
    });
  });

  group('getContents', () {
    test('asks for the platform and sends no customer id', () async {
      final response = await api(
        (_) async => jsonResponse('{"items":[]}',
            headers: {'etag': '"e1"', 'cache-control': 'max-age=60, private'}),
      ).getContents(platform: 'android');

      final request = requests.single;
      expect(request.url.toString(),
          'https://app.gantryhq.net/api/v1/contents?platform=android');
      expect(request.headers.containsKey('x-customer-id'), isFalse);
      expect(response.maxAge, const Duration(seconds: 60));
      expect(response.etag, '"e1"');
    });

    test('adds the category and the etag when given', () async {
      await api((_) async => http.Response('', 304))
          .getContents(platform: 'ios', category: 'kampanya', etag: '"e1"');

      final request = requests.single;
      expect(request.url.queryParameters,
          {'platform': 'ios', 'category': 'kampanya'});
      expect(request.headers['if-none-match'], '"e1"');
    });
  });

  group('getPage', () {
    test('requests the page by key', () async {
      await api((_) async => jsonResponse('{"key":"kvkk"}')).getPage('kvkk');

      expect(requests.single.url.toString(),
          'https://app.gantryhq.net/api/v1/pages/kvkk');
      expect(requests.single.headers.containsKey('x-customer-id'), isFalse);
    });

    test('returns 404 instead of throwing', () async {
      final response =
          await api((_) async => http.Response('', 404)).getPage('missing');
      expect(response.statusCode, 404);
    });
  });

  group('postLead', () {
    Future<void> post(GantryApi api) {
      return api.postLead(
          customerId: 'cust-1004',
          campaignId: 'coaching-lead',
          platform: 'ios',
          appVersion: '2.3.1');
    }

    test('posts the campaign as JSON with the customer id in a header',
        () async {
      await post(api((_) async => http.Response('', 201)));

      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://app.gantryhq.net/api/v1/leads');
      expect(request.headers['content-type'], startsWith('application/json'));
      expect(request.headers['x-customer-id'], 'cust-1004');
      expect(jsonDecode(request.body), {
        'campaignId': 'coaching-lead',
        'platform': 'ios',
        'appVersion': '2.3.1'
      });
    });

    test('accepts 200 for a repeated lead', () async {
      await expectLater(
          post(api((_) async => http.Response('', 200))), completes);
    });

    test('throws on 400', () async {
      await expectLater(post(api((_) async => http.Response('', 400))),
          throwsA(isA<GantryRequestException>()));
    });

    test('times out after the general timeout', () async {
      final slow = api(
        (_) => Future.delayed(
            const Duration(milliseconds: 300), () => http.Response('', 201)),
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(post(slow), throwsA(isA<GantryNetworkException>()));
    });
  });

  group('base url', () {
    test('keeps a base path and ignores a trailing slash', () async {
      await api((_) async => jsonResponse('{}'),
              baseUrl: 'https://example.com/gantry/')
          .getPage('kvkk');
      await api((_) async => jsonResponse('{}'),
              baseUrl: 'http://localhost:3000/')
          .getPage('kvkk');
      await api((_) async => jsonResponse('{}'),
              baseUrl: 'http://localhost:3000')
          .getContents(platform: 'ios');

      expect(requests.map((request) => request.url.toString()), [
        'https://example.com/gantry/api/v1/pages/kvkk',
        'http://localhost:3000/api/v1/pages/kvkk',
        'http://localhost:3000/api/v1/contents?platform=ios',
      ]);
    });
  });
}

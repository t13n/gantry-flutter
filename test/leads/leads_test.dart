import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gantry/src/api/gantry_api.dart';
import 'package:gantry/src/api/gantry_exception.dart';
import 'package:gantry/src/common/gantry_platform.dart';
import 'package:gantry/src/leads/leads.dart';
import 'package:gantry/src/log/gantry_log.dart';
import 'package:gantry/src/session.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late List<http.Request> requests;
  late List<Duration> delays;
  late Session session;

  /// Builds Leads whose server answers with [statuses] in order; a null entry
  /// is a connection failure.
  Leads build(List<int?> statuses) {
    final answers = [...statuses];
    final client = MockClient((request) async {
      requests.add(request);
      final status = answers.removeAt(0);
      if (status == null) throw http.ClientException('connection refused');
      return http.Response('', status);
    });
    return Leads(
      api: GantryApi(
        client: client,
        baseUrl: Uri.parse('https://gantry.test'),
        apiKey: 'gk_dev_test',
        userAgent: 'test',
      ),
      session: session,
      platform: GantryPlatform.android,
      appVersion: '2.3.1',
      log: const LogSink(null),
      delay: (duration) async => delays.add(duration),
    );
  }

  setUp(() {
    requests = [];
    delays = [];
    session = Session()..identify('cust-1004');
  });

  test('posts the lead for the identified customer', () async {
    await build([201]).submit(campaignId: 'coaching-lead');

    final request = requests.single;
    expect(request.url.path, '/api/v1/leads');
    expect(request.headers['x-customer-id'], 'cust-1004');
    expect(jsonDecode(request.body), {
      'campaignId': 'coaching-lead',
      'platform': 'android',
      'appVersion': '2.3.1'
    });
    expect(delays, isEmpty);
  });

  test('a repeated lead is a success too', () async {
    await expectLater(
        build([200]).submit(campaignId: 'coaching-lead'), completes);
  });

  test('throws without a customer and sends nothing', () async {
    session.reset();
    await expectLater(
      build([201]).submit(campaignId: 'coaching-lead'),
      throwsA(isA<GantryNotIdentifiedException>()),
    );
    expect(requests, isEmpty);
  });

  test('rejects an empty campaign id before sending', () async {
    await expectLater(
        build([201]).submit(campaignId: '  '), throwsArgumentError);
    expect(requests, isEmpty);
  });

  test('retries once after one second on a server error', () async {
    await build([503, 201]).submit(campaignId: 'coaching-lead');

    expect(requests, hasLength(2));
    expect(delays, [const Duration(seconds: 1)]);
  });

  test('retries once after one second on a connection failure', () async {
    await build([null, 200]).submit(campaignId: 'coaching-lead');

    expect(requests, hasLength(2));
    expect(delays, [const Duration(seconds: 1)]);
  });

  test('retries once after two seconds when rate limited', () async {
    await build([429, 201]).submit(campaignId: 'coaching-lead');

    expect(requests, hasLength(2));
    expect(delays, [const Duration(seconds: 2)]);
  });

  test('gives up after the second failure', () async {
    await expectLater(
      build([null, null, 201]).submit(campaignId: 'coaching-lead'),
      throwsA(isA<GantryNetworkException>()),
    );
    expect(requests, hasLength(2));

    requests.clear();
    await expectLater(
      build([429, 429, 201]).submit(campaignId: 'coaching-lead'),
      throwsA(isA<GantryRateLimitedException>()),
    );
    expect(requests, hasLength(2));
  });

  test('reports the second failure when it differs from the first', () async {
    await expectLater(
      build([503, 401]).submit(campaignId: 'coaching-lead'),
      throwsA(isA<GantryUnauthorizedException>()),
    );
  });

  test('does not retry a rejected request or a rejected key', () async {
    await expectLater(
      build([400, 201]).submit(campaignId: 'unknown'),
      throwsA(isA<GantryRequestException>()),
    );
    await expectLater(
      build([401, 201]).submit(campaignId: 'coaching-lead'),
      throwsA(isA<GantryUnauthorizedException>()),
    );
    expect(requests, hasLength(2));
    expect(delays, isEmpty);
  });

  test('a retry still goes to the customer who pressed the button', () async {
    final answers = [503, 201];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response('', answers.removeAt(0));
    });
    final leads = Leads(
      api: GantryApi(
          client: client,
          baseUrl: Uri.parse('https://gantry.test'),
          apiKey: 'k',
          userAgent: 'test'),
      session: session,
      platform: GantryPlatform.ios,
      appVersion: '1',
      log: const LogSink(null),
      delay: (_) async => session.identify('cust-other'),
    );

    await leads.submit(campaignId: 'coaching-lead');
    expect(requests.map((request) => request.headers['x-customer-id']),
        ['cust-1004', 'cust-1004']);
  });
}

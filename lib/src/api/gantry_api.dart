import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'gantry_exception.dart';

/// A successful answer from the Gantry API.
class ApiResponse {
  /// Creates a response.
  const ApiResponse(
      {required this.statusCode, required this.body, this.etag, this.maxAge});

  /// HTTP status code; one of the codes the endpoint treats as success.
  final int statusCode;

  /// Response body decoded as UTF-8; empty for 304 and 404.
  final String body;

  /// Value of the `ETag` header, if any.
  final String? etag;

  /// `max-age` from the `Cache-Control` header, if any.
  final Duration? maxAge;
}

/// Talks HTTP to the Gantry API: builds requests, sends the key and the
/// customer id in headers, applies timeouts and turns failures into
/// [GantryException]s. Knows nothing about caching, retries or priorities.
class GantryApi {
  /// Creates a client for the API at [baseUrl].
  GantryApi({
    required http.Client client,
    required Uri baseUrl,
    required String apiKey,
    required String userAgent,
    this.interstitialTimeout = const Duration(seconds: 2),
    this.timeout = const Duration(seconds: 5),
  })  : _client = client,
        _baseUrl = baseUrl,
        _apiKey = apiKey,
        _userAgent = userAgent;

  static final RegExp _maxAge = RegExp(r'max-age=(\d+)');

  final http.Client _client;
  final Uri _baseUrl;
  final String _apiKey;
  final String _userAgent;

  /// How long the interstitial request may take; app launch waits on it.
  final Duration interstitialTimeout;

  /// How long every other request may take.
  final Duration timeout;

  /// The targeted interstitial for [customerId]: 200 with a campaign or `{}`,
  /// or 304 when [etag] is still current.
  Future<ApiResponse> getInterstitial({
    required String customerId,
    required String platform,
    required String appVersion,
    String? etag,
  }) {
    return _send(
      'GET',
      'interstitial',
      query: {'platform': platform, 'appVersion': appVersion},
      customerId: customerId,
      etag: etag,
      timeout: interstitialTimeout,
      success: const {200, 304},
    );
  }

  /// The cards published for [platform]: 200 with `{ "items": [...] }`, or 304.
  Future<ApiResponse> getContents(
      {required String platform, String? category, String? etag}) {
    return _send(
      'GET',
      'contents',
      query: {'platform': platform, if (category != null) 'category': category},
      etag: etag,
      timeout: timeout,
      success: const {200, 304},
    );
  }

  /// The page published under [key]: 200, 304, or 404 when it is not published.
  Future<ApiResponse> getPage(String key, {String? etag}) {
    return _send('GET', 'pages/$key',
        etag: etag, timeout: timeout, success: const {200, 304, 404});
  }

  /// Records a lead; completes on 201 (new) and 200 (repeated).
  Future<void> postLead({
    required String customerId,
    required String campaignId,
    required String platform,
    required String appVersion,
  }) async {
    await _send(
      'POST',
      'leads',
      customerId: customerId,
      body: jsonEncode({
        'campaignId': campaignId,
        'platform': platform,
        'appVersion': appVersion
      }),
      timeout: timeout,
      success: const {200, 201},
    );
  }

  Future<ApiResponse> _send(
    String method,
    String path, {
    Map<String, String>? query,
    String? customerId,
    String? etag,
    String? body,
    required Duration timeout,
    required Set<int> success,
  }) async {
    final request = http.Request(method, _uri(path, query));
    request.headers['Authorization'] = 'Bearer $_apiKey';
    request.headers['User-Agent'] = _userAgent;
    request.headers['Accept'] = 'application/json';
    if (customerId != null) request.headers['X-Customer-Id'] = customerId;
    if (etag != null) request.headers['If-None-Match'] = etag;
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.bodyBytes = utf8.encode(body);
    }

    final http.Response response;
    try {
      response = await _fetch(request).timeout(timeout);
    } on TimeoutException {
      throw const GantryNetworkException('The request timed out');
    } on Exception catch (error) {
      throw GantryNetworkException('The request could not be sent',
          cause: error);
    }

    final status = response.statusCode;
    if (!success.contains(status)) {
      throw switch (status) {
        400 => const GantryRequestException(),
        401 => const GantryUnauthorizedException(),
        429 => const GantryRateLimitedException(),
        _ => GantryServerException(status),
      };
    }

    final seconds =
        _maxAge.firstMatch(response.headers['cache-control'] ?? '')?.group(1);
    return ApiResponse(
      statusCode: status,
      // The http package falls back to latin1 without a charset; the API is always UTF-8.
      body: utf8.decode(response.bodyBytes, allowMalformed: true),
      etag: response.headers['etag'],
      maxAge: seconds == null
          ? null
          : Duration(seconds: int.tryParse(seconds) ?? 0),
    );
  }

  Future<http.Response> _fetch(http.Request request) async {
    return http.Response.fromStream(await _client.send(request));
  }

  Uri _uri(String path, Map<String, String>? query) {
    final base = _baseUrl.path;
    final prefix =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return _baseUrl.replace(
      path: '$prefix/api/v1/$path',
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }
}

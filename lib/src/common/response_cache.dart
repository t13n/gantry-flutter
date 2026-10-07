import '../api/gantry_api.dart';
import '../api/gantry_exception.dart';
import '../log/gantry_log.dart';

class _Entry {
  const _Entry(
      {required this.body, required this.etag, required this.freshUntil});

  final String body;
  final String? etag;
  final DateTime freshUntil;
}

/// In-memory cache for responses that are the same for every customer.
///
/// A body is reused without a request until the server's `max-age` passes;
/// after that it is revalidated with its ETag. When revalidation fails because
/// of the network, a rate limit or a server error, the last body is served.
/// Nothing is written to disk and nothing here depends on who is signed in.
class ResponseCache {
  /// Creates an empty cache.
  ResponseCache({required DateTime Function() now, required LogSink log})
      : _now = now,
        _log = log;

  final DateTime Function() _now;
  final LogSink _log;
  final Map<String, _Entry> _entries = {};

  /// Returns the body for [key], calling [request] only when needed.
  ///
  /// [request] receives the ETag to revalidate with, if any. Returns null when
  /// the server answers 404.
  ///
  /// [validate] is called with a new body before it is kept and throws a
  /// [GantryException] when the body is unusable. An unusable body never
  /// replaces a good one: the previous body is served instead.
  Future<String?> fetch(
    String key,
    Future<ApiResponse> Function(String? etag) request, {
    void Function(String body)? validate,
  }) async {
    final cached = _entries[key];
    if (cached != null && _now().isBefore(cached.freshUntil)) {
      return cached.body;
    }

    final ApiResponse response;
    try {
      response = await request(cached?.etag);
    } on GantryUnauthorizedException {
      rethrow;
    } on GantryRequestException {
      rethrow;
    } on GantryException catch (error) {
      if (cached == null) rethrow;
      _log.warning('Could not refresh; serving the previous response', error);
      return cached.body;
    }

    if (response.statusCode == 404) {
      _entries.remove(key);
      return null;
    }
    final freshUntil = _now().add(response.maxAge ?? Duration.zero);
    if (response.statusCode == 304) {
      if (cached == null) throw GantryServerException(response.statusCode);
      _entries[key] = _Entry(
          body: cached.body,
          etag: response.etag ?? cached.etag,
          freshUntil: freshUntil);
      return cached.body;
    }
    if (validate != null) {
      try {
        validate(response.body);
      } on GantryException catch (error) {
        if (cached == null) rethrow;
        _log.warning(
            'The refreshed response could not be read; serving the previous one',
            error);
        return cached.body;
      }
    }
    _entries[key] = _Entry(
        body: response.body, etag: response.etag, freshUntil: freshUntil);
    return response.body;
  }
}

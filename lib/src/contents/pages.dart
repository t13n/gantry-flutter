import 'package:meta/meta.dart';

import 'dart:convert';

import '../api/gantry_api.dart';
import '../api/gantry_exception.dart';
import '../common/response_cache.dart';
import '../log/gantry_log.dart';
import 'content.dart';

/// Loads the static pages published in Gantry. Get it from `Gantry.pages`.
class Pages {
  /// Creates the page loader; apps use `Gantry.pages` instead.
  @internal
  Pages({
    required GantryApi api,
    required ResponseCache cache,
    required LogSink log,
  })  : _api = api,
        _cache = cache,
        _log = log;

  static final RegExp _keyFormat = RegExp(r'^[a-z0-9-]+$');

  final GantryApi _api;
  final ResponseCache _cache;
  final LogSink _log;

  /// Returns the page published under [key], or null when there is none or it
  /// is in a format this SDK version cannot read.
  ///
  /// Pages are not personal, so this works before `Gantry.identify`. Results
  /// are kept in memory for as long as the server allows (a minute) and then
  /// refreshed. If a refresh fails, the previous page is returned.
  ///
  /// Throws a [GantryException] when the page cannot be loaded and there is no
  /// earlier result, and always when the API key is rejected.
  Future<ContentPage?> get(String key) async {
    if (!_keyFormat.hasMatch(key)) {
      throw ArgumentError.value(
          key, 'key', 'must be lowercase letters, digits and hyphens');
    }
    final body = await _cache.fetch(
      'pages:$key',
      (etag) => _api.getPage(key, etag: etag),
      validate: _object,
    );
    if (body == null) return null;

    final page = ContentPage.fromJson(_object(body));
    if (page == null) {
      _log.warning('Skipped a page this SDK version cannot read');
    }
    return page;
  }

  /// The JSON object of a response body. Throws when the body is not an
  /// object at all; a page in a newer format is dealt with by the caller.
  static Map<Object?, Object?> _object(String body) {
    Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      json = null;
    }
    if (json is! Map) {
      throw const GantryServerException(200, 'The page could not be read');
    }
    return json;
  }
}

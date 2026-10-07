import 'package:meta/meta.dart';

import 'dart:convert';

import '../api/gantry_api.dart';
import '../api/gantry_exception.dart';
import '../common/gantry_platform.dart';
import '../common/response_cache.dart';
import '../log/gantry_log.dart';
import 'content.dart';

/// Loads the content cards published in Gantry. Get it from `Gantry.contents`.
class Contents {
  /// Creates the card loader; apps use `Gantry.contents` instead.
  @internal
  Contents({
    required GantryApi api,
    required ResponseCache cache,
    required GantryPlatform platform,
    required LogSink log,
  })  : _api = api,
        _cache = cache,
        _platform = platform,
        _log = log;

  static final RegExp _categoryFormat = RegExp(r'^[a-z0-9-]+$');

  final GantryApi _api;
  final ResponseCache _cache;
  final GantryPlatform _platform;
  final LogSink _log;

  /// Returns the cards to show now, in the order set in Gantry.
  ///
  /// With [category], only cards with that label are returned. The list can be
  /// empty. Cards are not personal, so this works before `Gantry.identify`.
  ///
  /// Results are kept in memory for as long as the server allows (a minute)
  /// and then refreshed. If a refresh fails, the previous cards are returned.
  ///
  /// Throws a [GantryException] when the cards cannot be loaded and there is
  /// no earlier result, and always when the API key is rejected.
  Future<List<ContentCard>> list({String? category}) async {
    if (category != null && !_categoryFormat.hasMatch(category)) {
      throw ArgumentError.value(category, 'category',
          'must be lowercase letters, digits and hyphens');
    }
    final body = await _cache.fetch(
      'contents:${category ?? ''}',
      (etag) => _api.getContents(
          platform: _platform.name, category: category, etag: etag),
      validate: _items,
    );

    final cards = <ContentCard>[];
    for (final item in _items(body ?? '')) {
      final card = ContentCard.fromJson(item);
      if (card == null) {
        _log.warning('Skipped a content card this SDK version cannot read');
      } else {
        cards.add(card);
      }
    }
    return cards;
  }

  /// The `items` list of a response body. Throws when the body is not a card
  /// list at all; single unreadable cards are dealt with by the caller.
  static List<Object?> _items(String body) {
    Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      json = null;
    }
    final items = json is Map ? json['items'] : null;
    if (items is! List) {
      throw const GantryServerException(200, 'The card list could not be read');
    }
    return items;
  }
}

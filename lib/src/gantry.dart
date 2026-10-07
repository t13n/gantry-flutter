import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api/gantry_api.dart';
import 'common/app_version.dart';
import 'common/gantry_platform.dart';
import 'common/response_cache.dart';
import 'contents/contents.dart';
import 'contents/pages.dart';
import 'interstitials/frequency_tracker.dart';
import 'interstitials/interstitials.dart';
import 'leads/leads.dart';
import 'log/gantry_log.dart';
import 'session.dart';
import 'store/gantry_store.dart';
import 'store/shared_preferences_store.dart';
import 'version.dart';

/// The entry point of the Gantry SDK.
///
/// Create one instance when the app starts and keep it for the app's
/// lifetime:
///
/// ```dart
/// final gantry = Gantry(
///   apiKey: 'gk_prod_...',
///   appVersion: '2.3.1',
///   remoteConfig: (key) => FirebaseRemoteConfig.instance.getString(key),
/// );
///
/// gantry.identify(customerId); // after sign-in
/// gantry.reset();              // after sign-out
/// ```
class Gantry {
  /// Creates the SDK for one Gantry environment.
  ///
  /// * [apiKey] is the key of the environment (dev, preprod or prod) this
  ///   build talks to. It decides which environment's data is returned.
  /// * [appVersion] is the app's own version as `1`, `1.2` or `1.2.3`.
  /// * [platform] is detected on iOS and Android; pass it anywhere else.
  /// * [remoteConfig] reads a Remote Config value. Without it
  ///   [interstitials] has nothing to show.
  /// * [baseUrl] defaults to [defaultBaseUrl].
  /// * [httpClient] replaces the HTTP client; the SDK does not close a client
  ///   it was given.
  /// * [store] replaces `shared_preferences` as the place where the SDK
  ///   remembers which interstitials were shown.
  /// * [onLog] receives the SDK's log events. Nothing is printed without it.
  ///
  /// Throws an [ArgumentError] for a malformed key, version or address, or a
  /// platform that cannot be detected.
  factory Gantry({
    required String apiKey,
    required String appVersion,
    GantryPlatform? platform,
    RemoteConfigReader? remoteConfig,
    Uri? baseUrl,
    http.Client? httpClient,
    GantryStore? store,
    GantryLogger? onLog,
  }) {
    if (!_apiKeyFormat.hasMatch(apiKey)) {
      // The value is left out on purpose: errors end up in crash reports.
      throw ArgumentError(
        'must be a Gantry API key without spaces or line breaks',
        'apiKey',
      );
    }
    AppVersion.parse(appVersion);
    if (baseUrl != null &&
        (!const {'http', 'https'}.contains(baseUrl.scheme) ||
            baseUrl.host.isEmpty)) {
      throw ArgumentError.value(
          baseUrl, 'baseUrl', 'must be an http or https address');
    }
    final resolvedPlatform = platform ?? _detectPlatform();

    DateTime now() => DateTime.now();
    final log = LogSink(onLog);
    final client = httpClient ?? http.Client();
    final session = Session();
    final api = GantryApi(
      client: client,
      baseUrl: baseUrl ?? defaultBaseUrl,
      apiKey: apiKey,
      userAgent: 'gantry-flutter/$packageVersion',
    );
    final cache = ResponseCache(now: now, log: log);

    return Gantry._(
      client: client,
      ownsClient: httpClient == null,
      session: session,
      interstitials: Interstitials(
        api: api,
        session: session,
        remoteConfig: remoteConfig,
        frequency: FrequencyTracker(
            store: store ?? SharedPreferencesGantryStore(), now: now, log: log),
        platform: resolvedPlatform,
        appVersion: appVersion,
        now: now,
        log: log,
      ),
      leads: Leads(
          api: api,
          session: session,
          platform: resolvedPlatform,
          appVersion: appVersion,
          log: log),
      contents: Contents(
          api: api, cache: cache, platform: resolvedPlatform, log: log),
      pages: Pages(api: api, cache: cache, log: log),
    );
  }

  Gantry._({
    required http.Client client,
    required bool ownsClient,
    required Session session,
    required this.interstitials,
    required this.leads,
    required this.contents,
    required this.pages,
  })  : _client = client,
        _ownsClient = ownsClient,
        _session = session;

  // What can travel in an Authorization header; the server accepts no more.
  static final RegExp _apiKeyFormat = RegExp(r'^[\x21-\x7E]+$');

  /// The address of the hosted Gantry service.
  static final Uri defaultBaseUrl = Uri.parse('https://app.gantryhq.net');

  final http.Client _client;
  final bool _ownsClient;
  final Session _session;

  /// Picks the interstitial to show.
  final Interstitials interstitials;

  /// Records leads.
  final Leads leads;

  /// Loads content cards.
  final Contents contents;

  /// Loads static pages.
  final Pages pages;

  /// Whether a customer is currently identified.
  bool get isIdentified => _session.customerId != null;

  /// Tells the SDK who is signed in. Call it after sign-in and on app start
  /// when a session already exists.
  ///
  /// [customerId] is the id Gantry's target lists use: 1 to 64 letters,
  /// digits or `_ - . :`. Throws an [ArgumentError] otherwise.
  void identify(String customerId) => _session.identify(customerId);

  /// Forgets the customer and their cached data. Call it on sign-out.
  ///
  /// The record of shown interstitials is kept: it belongs to the device.
  void reset() => _session.reset();

  /// Releases the HTTP client the SDK created. Call it when the SDK is no
  /// longer needed; do not use this instance afterwards.
  void close() {
    if (_ownsClient) _client.close();
  }

  static GantryPlatform _detectPlatform() {
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => GantryPlatform.ios,
      TargetPlatform.android => GantryPlatform.android,
      _ => throw ArgumentError.notNull('platform'),
    };
  }
}

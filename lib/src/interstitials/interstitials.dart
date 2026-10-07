import 'package:meta/meta.dart';

import '../api/gantry_api.dart';
import '../api/gantry_exception.dart';
import '../common/app_version.dart';
import '../common/gantry_platform.dart';
import '../log/gantry_log.dart';
import '../session.dart';
import 'frequency_tracker.dart';
import 'interstitial.dart';
import 'interstitial_eligibility.dart';

/// Reads a Remote Config value by key. Return null or an empty string when the
/// key has no value.
///
/// ```dart
/// remoteConfig: (key) => FirebaseRemoteConfig.instance.getString(key)
/// ```
typedef RemoteConfigReader = String? Function(String key);

/// Picks the interstitial to show. Get it from `Gantry.interstitials`.
class Interstitials {
  /// Creates the interstitial picker; apps use `Gantry.interstitials` instead.
  @internal
  Interstitials({
    required GantryApi api,
    required Session session,
    required RemoteConfigReader? remoteConfig,
    required FrequencyTracker frequency,
    required GantryPlatform platform,
    required String appVersion,
    required DateTime Function() now,
    required LogSink log,
  })  : _api = api,
        _session = session,
        _remoteConfig = remoteConfig,
        _frequency = frequency,
        _platform = platform,
        _appVersion = appVersion,
        _now = now,
        _log = log;

  /// Remote Config key of the campaign published to everyone.
  static const String parameterKey = 'bo_interstitial';

  /// Remote Config key of the flag that says targeted campaigns exist.
  static const String targetedParameterKey = 'bo_interstitial_targeted';

  final GantryApi _api;
  final Session _session;
  final RemoteConfigReader? _remoteConfig;
  final FrequencyTracker _frequency;
  final GantryPlatform _platform;
  final String _appVersion;
  final DateTime Function() _now;
  final LogSink _log;

  /// Returns the interstitial to show now, or null when there is none.
  ///
  /// A campaign targeted at the identified customer wins over the one
  /// published to everyone. If the targeted campaign was already shown as
  /// often as its frequency allows, the general one is considered instead.
  ///
  /// Never throws: any problem results in null and a log event. The request
  /// for the targeted campaign is given at most two seconds.
  ///
  /// Call [markShown] once the interstitial is actually on screen.
  Future<Interstitial?> next() async {
    try {
      if (_remoteConfig == null) {
        _log.warning(
            'No remoteConfig reader was given, so there are no interstitials to show');
        return null;
      }
      final generation = _session.generation;
      final targeted = await _targeted();
      if (targeted != null &&
          await _frequency.canShow(targeted) &&
          // The customer may have changed while the display record was read.
          _session.generation == generation) {
        return targeted;
      }
      final general = _general();
      if (general != null && await _frequency.canShow(general)) return general;
      return null;
    } catch (error) {
      _log.warning('Could not pick an interstitial', error);
      return null;
    }
  }

  /// Records that [interstitial] was shown, so its frequency is respected.
  /// Never throws.
  Future<void> markShown(Interstitial interstitial) =>
      _frequency.markShown(interstitial);

  Future<Interstitial?> _targeted() async {
    if (_read(targetedParameterKey)?.trim().toLowerCase() != 'true') {
      return null;
    }
    final customerId = _session.customerId;
    if (customerId == null) return null;

    final generation = _session.generation;
    final cached = _session.targeted;
    try {
      final response = await _api.getInterstitial(
        customerId: customerId,
        platform: _platform.name,
        appVersion: _appVersion,
        etag: cached?.etag,
      );
      if (_session.generation != generation) return null;

      final String body;
      if (response.statusCode == 304) {
        if (cached == null) return null;
        body = cached.body;
      } else {
        body = response.body;
        final etag = response.etag;
        _session.targeted =
            etag == null ? null : TargetedCache(etag: etag, body: body);
      }
      final interstitial = Interstitial.tryParse(body);
      if (interstitial == null && body.trim() != '{}') {
        _log.warning(
            'The targeted interstitial could not be read by this SDK version');
      }
      return interstitial;
    } on GantryUnauthorizedException catch (error) {
      _log.error(
          'The Gantry API key was rejected; targeted interstitials are unavailable',
          error);
      return null;
    } on GantryException catch (error) {
      _log.warning('Could not load the targeted interstitial', error);
      return null;
    }
  }

  Interstitial? _general() {
    final raw = _read(parameterKey);
    if (raw == null || raw.trim().isEmpty) return null;
    final interstitial = Interstitial.tryParse(raw);
    if (interstitial == null) {
      if (raw.trim() != '{}') {
        _log.warning('$parameterKey could not be read by this SDK version');
      }
      return null;
    }
    final eligible = isEligible(
      interstitial,
      now: _now(),
      platform: _platform,
      appVersion: AppVersion.parse(_appVersion),
    );
    return eligible ? interstitial : null;
  }

  String? _read(String key) {
    try {
      return _remoteConfig?.call(key);
    } catch (error) {
      _log.warning('The remoteConfig reader failed for $key', error);
      return null;
    }
  }
}

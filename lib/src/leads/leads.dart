import 'package:meta/meta.dart';

import '../api/gantry_api.dart';
import '../api/gantry_exception.dart';
import '../common/gantry_platform.dart';
import '../log/gantry_log.dart';
import '../session.dart';

/// Records leads: "this customer wants to be contacted about this campaign".
/// Get it from `Gantry.leads`.
class Leads {
  /// Creates the lead sender; apps use `Gantry.leads` instead.
  @internal
  Leads({
    required GantryApi api,
    required Session session,
    required GantryPlatform platform,
    required String appVersion,
    required LogSink log,
    Future<void> Function(Duration duration)? delay,
  })  : _api = api,
        _session = session,
        _platform = platform,
        _appVersion = appVersion,
        _log = log,
        _delay = delay ?? Future<void>.delayed;

  static const Duration _retryDelay = Duration(seconds: 1);
  static const Duration _rateLimitDelay = Duration(seconds: 2);

  final GantryApi _api;
  final Session _session;
  final GantryPlatform _platform;
  final String _appVersion;
  final LogSink _log;
  final Future<void> Function(Duration duration) _delay;

  /// Sends a lead for the identified customer and [campaignId], which is the
  /// `id` of the interstitial whose lead button was tapped.
  ///
  /// Sending the same lead again is harmless. A connection failure, a timeout
  /// or a server error is retried once after a second; a rate limit once after
  /// two seconds. The call can take about twelve seconds in the worst case.
  ///
  /// Throws a [GantryNotIdentifiedException] before `Gantry.identify`, a
  /// [GantryRequestException] when Gantry does not know the campaign, and
  /// another [GantryException] when the lead could not be delivered.
  Future<void> submit({required String campaignId}) async {
    final customerId = _session.customerId;
    if (customerId == null) throw const GantryNotIdentifiedException();
    if (campaignId.trim().isEmpty) {
      throw ArgumentError.value(campaignId, 'campaignId', 'must not be empty');
    }

    Future<void> send() {
      return _api.postLead(
        customerId: customerId,
        campaignId: campaignId,
        platform: _platform.name,
        appVersion: _appVersion,
      );
    }

    try {
      await send();
    } on GantryRateLimitedException {
      _log.debug('Lead was rate limited; retrying once');
      await _delay(_rateLimitDelay);
      await send();
    } on GantryNetworkException {
      _log.debug('Lead could not be sent; retrying once');
      await _delay(_retryDelay);
      await send();
    } on GantryServerException {
      _log.debug('Lead hit a server error; retrying once');
      await _delay(_retryDelay);
      await send();
    }
  }
}

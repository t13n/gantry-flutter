import '../common/app_version.dart';
import '../common/gantry_platform.dart';
import 'interstitial.dart';

/// Whether a campaign read from Remote Config may be shown right now.
///
/// Campaigns from the Gantry API are already filtered by the server; this is
/// the same rule applied on the device.
bool isEligible(
  Interstitial interstitial, {
  required DateTime now,
  required GantryPlatform platform,
  required AppVersion appVersion,
}) {
  final minimum = AppVersion.tryParse(interstitial.minAppVersion);
  return interstitial.enabled &&
      !now.isBefore(interstitial.startAt) &&
      now.isBefore(interstitial.endAt) &&
      interstitial.platforms.contains(platform) &&
      minimum != null &&
      appVersion >= minimum;
}

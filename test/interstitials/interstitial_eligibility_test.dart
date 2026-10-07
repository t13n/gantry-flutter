import 'package:flutter_test/flutter_test.dart';
import 'package:gantry/src/common/app_version.dart';
import 'package:gantry/src/common/gantry_platform.dart';
import 'package:gantry/src/interstitials/interstitial.dart';
import 'package:gantry/src/interstitials/interstitial_eligibility.dart';

import '../support/fixtures.dart';

void main() {
  final inside = DateTime.utc(2026, 10, 7, 12);

  bool eligible(
    Map<String, dynamic> overrides, {
    DateTime? now,
    GantryPlatform platform = GantryPlatform.ios,
    String appVersion = '2.3.1',
  }) {
    final interstitial =
        Interstitial.fromJson(interstitialJson(overrides: overrides))!;
    return isEligible(interstitial,
        now: now ?? inside,
        platform: platform,
        appVersion: AppVersion.parse(appVersion));
  }

  test('an enabled campaign inside its window is eligible', () {
    expect(eligible({}), isTrue);
  });

  test('a disabled campaign is not eligible', () {
    expect(eligible({'enabled': false}), isFalse);
  });

  test('the window includes its start and excludes its end', () {
    expect(eligible({}, now: DateTime.utc(2026, 9, 30, 20, 59, 59)), isFalse);
    expect(eligible({}, now: DateTime.utc(2026, 9, 30, 21)), isTrue);
    expect(eligible({}, now: DateTime.utc(2026, 11, 1, 20, 58, 59)), isTrue);
    expect(eligible({}, now: DateTime.utc(2026, 11, 1, 20, 59)), isFalse);
  });

  test('the platform must be all or this platform', () {
    expect(
        eligible({
          'platform': ['ios']
        }),
        isTrue);
    expect(
        eligible({
          'platform': ['android']
        }),
        isFalse);
    expect(
        eligible({
          'platform': ['android']
        }, platform: GantryPlatform.android),
        isTrue);
    expect(
        eligible({
          'platform': ['ios', 'android']
        }, platform: GantryPlatform.android),
        isTrue);
  });

  test('the app must be at least the minimum version', () {
    expect(eligible({'minAppVersion': '2.3.1'}), isTrue);
    expect(eligible({'minAppVersion': '2.3.2'}), isFalse);
    expect(eligible({'minAppVersion': '2.10'}, appVersion: '2.9'), isFalse);
    expect(eligible({'minAppVersion': '2.9'}, appVersion: '2.10'), isTrue);
  });
}

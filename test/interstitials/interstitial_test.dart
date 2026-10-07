import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gantry/src/common/gantry_action.dart';
import 'package:gantry/src/common/gantry_platform.dart';
import 'package:gantry/src/interstitials/interstitial.dart';

import '../support/fixtures.dart';

void main() {
  test('reads every field of the contract', () {
    final interstitial = Interstitial.tryParse(fixture('interstitial.json'))!;

    expect(interstitial.id, 'splash-deeplink');
    expect(interstitial.enabled, isTrue);
    expect(interstitial.startAt, DateTime.utc(2026, 9, 30, 21));
    expect(interstitial.endAt, DateTime.utc(2026, 11, 1, 20, 59));
    expect(interstitial.platforms, GantryPlatform.values.toSet());
    expect(interstitial.minAppVersion, '2.0.0');
    expect(interstitial.frequency, InterstitialFrequency.once);
    expect(interstitial.audience, InterstitialAudience.all);
    expect(interstitial.priority, 100);
    expect(interstitial.title.tr, 'Sağlıklı Şehirler');
    expect(interstitial.title.en, 'Healthy Cities');
    expect(interstitial.description.en, 'Take the survey for your city.');
    expect(interstitial.imageUrl,
        Uri.parse('https://cdn.example.com/healthy-cities.png'));
    expect(interstitial.a11yLabel.en, 'Healthy Cities campaign image');
    expect(interstitial.primaryButtonLabel.en, 'Join Now');
    expect(interstitial.primaryAction, isA<GantryRedirectAction>());
    expect(
        interstitial.primaryAction.trackingEvent, 'healthy_cities_join_click');
    expect(interstitial.secondaryButtonLabel!.en, 'Call me');
    expect(interstitial.secondaryAction, isA<GantryLeadAction>());
  });

  test('reads the targeted audience and the other frequencies', () {
    final json = interstitialJson(overrides: {
      'audience': {'type': 'customers'},
      'frequency': {'type': 'everyLaunch'},
      'platform': ['ios', 'android'],
    });
    final interstitial = Interstitial.fromJson(json)!;
    expect(interstitial.audience, InterstitialAudience.customers);
    expect(interstitial.frequency, InterstitialFrequency.everyLaunch);
    expect(interstitial.platforms, GantryPlatform.values.toSet());
  });

  test('the secondary button is optional', () {
    final json = interstitialJsonWithContent(
        {'secondaryButtonLabel': null, 'secondaryAction': null});
    final interstitial = Interstitial.fromJson(json)!;
    expect(interstitial.secondaryButtonLabel, isNull);
    expect(interstitial.secondaryAction, isNull);
  });

  test('ignores fields it does not know', () {
    final json = interstitialJson(overrides: {'theme': 'dark'});
    expect(Interstitial.fromJson(json), isNotNull);
  });

  test('tryParse returns null for nothing to show', () {
    for (final raw in [
      null,
      '',
      '   ',
      '{}',
      'null',
      '[]',
      'not json',
      '{"id":'
    ]) {
      expect(Interstitial.tryParse(raw), isNull, reason: '$raw');
    }
  });

  test('skips a schema version it does not know', () {
    expect(
        Interstitial.fromJson(
            interstitialJson(overrides: {'schemaVersion': 2})),
        isNull);
  });

  test('skips a record with a missing or malformed required field', () {
    final broken = <Map<String, dynamic>>[
      interstitialJson(overrides: {'id': ''}),
      interstitialJson(overrides: {'enabled': 'yes'}),
      interstitialJson(overrides: {'startAt': 'tomorrow'}),
      interstitialJson(overrides: {'endAt': null}),
      interstitialJson(overrides: {'platform': <String>[]}),
      interstitialJson(overrides: {'minAppVersion': 'latest'}),
      interstitialJson(overrides: {
        'frequency': {'type': 'weekly'}
      }),
      interstitialJson(overrides: {
        'audience': {'type': 'segment'}
      }),
      interstitialJson(overrides: {'priority': 'high'}),
      interstitialJson(overrides: {'content': null}),
      interstitialJsonWithContent({'title': null}),
      interstitialJsonWithContent({'imageUrl': 'ftp://example.com/a.png'}),
      interstitialJsonWithContent({
        'primaryAction': {'type': 'share'}
      }),
      interstitialJsonWithContent({'secondaryAction': null}),
      interstitialJsonWithContent({
        'secondaryAction': {'type': 'share'}
      }),
    ];
    for (final json in broken) {
      expect(Interstitial.fromJson(json), isNull, reason: jsonEncode(json));
    }
  });
}

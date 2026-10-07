// Apps import this package next to Flutter's own libraries. A public name that
// Flutter also exports would force every app to hide or prefix one of them, so
// every exported type is named here with both imports in scope.
import 'package:flutter/cupertino.dart';
// ignore: unnecessary_import
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gantry/gantry.dart';

void main() {
  test('exported names do not clash with Flutter', () {
    const names = <Type>[
      Gantry,
      GantryPlatform,
      GantryException,
      GantryNetworkException,
      GantryUnauthorizedException,
      GantryRateLimitedException,
      GantryServerException,
      GantryRequestException,
      GantryNotIdentifiedException,
      Interstitial,
      InterstitialFrequency,
      InterstitialAudience,
      Interstitials,
      RemoteConfigReader,
      Leads,
      Contents,
      Pages,
      ContentCard,
      ContentPage,
      ContentBody,
      LocalizedText,
      GantryAction,
      GantryRedirectAction,
      GantryWebPageAction,
      GantryLeadAction,
      GantryDismissAction,
      GantryStore,
      MemoryGantryStore,
      GantryLogEvent,
      GantryLogLevel,
      GantryLogger,
    ];
    expect(names.toSet(), hasLength(names.length));
    expect(const SizedBox(), isA<Widget>());
    expect(const CupertinoPageScaffold(child: SizedBox()), isA<Widget>());
  });
}

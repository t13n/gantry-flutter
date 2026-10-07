import 'package:flutter_test/flutter_test.dart';
import 'package:gantry/src/common/gantry_action.dart';

void main() {
  test('reads a redirect action', () {
    final action = GantryAction.fromJson({
      'type': 'redirect',
      'deeplink': 'blua://app/x',
      'trackingEvent': 'join_click'
    });
    expect(
        action,
        isA<GantryRedirectAction>()
            .having((a) => a.deeplink, 'deeplink', 'blua://app/x'));
    expect(action!.trackingEvent, 'join_click');
  });

  test('reads a web page action', () {
    final action = GantryAction.fromJson(
        {'type': 'webPage', 'url': 'https://example.com/summer'});
    expect(
        action,
        isA<GantryWebPageAction>().having(
            (a) => a.url, 'url', Uri.parse('https://example.com/summer')));
    expect(action!.trackingEvent, isNull);
  });

  test('reads lead and dismiss actions', () {
    expect(GantryAction.fromJson({'type': 'lead', 'trackingEvent': 'call_me'}),
        isA<GantryLeadAction>());
    expect(
        GantryAction.fromJson({'type': 'dismiss'}), isA<GantryDismissAction>());
  });

  test('returns null for unknown types and missing targets', () {
    expect(GantryAction.fromJson(null), isNull);
    expect(GantryAction.fromJson({'type': 'share'}), isNull);
    expect(GantryAction.fromJson({'type': 'redirect'}), isNull);
    expect(GantryAction.fromJson({'type': 'redirect', 'deeplink': ''}), isNull);
    expect(
        GantryAction.fromJson({'type': 'webPage', 'url': 'http://example.com'}),
        isNull);
    expect(
        GantryAction.fromJson({'type': 'webPage', 'url': 'not a url'}), isNull);
  });

  test('can be switched over exhaustively', () {
    String describe(GantryAction action) => switch (action) {
          GantryRedirectAction(:final deeplink) => 'open $deeplink',
          GantryWebPageAction(:final url) => 'browse $url',
          GantryLeadAction() => 'lead',
          GantryDismissAction() => 'dismiss',
        };
    expect(describe(const GantryLeadAction()), 'lead');
    expect(
        describe(const GantryRedirectAction(deeplink: 'a://b')), 'open a://b');
  });
}

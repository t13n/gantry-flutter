/// What should happen when the user taps a button or a card.
///
/// The SDK only describes the action; the app carries it out. Switch over the
/// subtypes to handle every case:
///
/// ```dart
/// switch (action) {
///   case GantryRedirectAction(:final deeplink): openDeeplink(deeplink);
///   case GantryWebPageAction(:final url): launchUrl(url);
///   case GantryLeadAction(): gantry.leads.submit(campaignId: interstitial.id);
///   case GantryDismissAction(): break;
/// }
/// ```
sealed class GantryAction {
  /// Creates an action with an optional analytics event name.
  const GantryAction({this.trackingEvent});

  /// Analytics event name entered in Gantry, if any. The SDK does not send it.
  final String? trackingEvent;

  /// Reads an action object; returns null when the type is unknown or its
  /// target is missing.
  static GantryAction? fromJson(Object? json) {
    if (json is! Map) return null;
    final tracking = json['trackingEvent'];
    final trackingEvent = tracking is String ? tracking : null;
    switch (json['type']) {
      case 'redirect':
        final deeplink = json['deeplink'];
        if (deeplink is! String || deeplink.isEmpty) return null;
        return GantryRedirectAction(
            deeplink: deeplink, trackingEvent: trackingEvent);
      case 'webPage':
        final raw = json['url'];
        final url = raw is String ? Uri.tryParse(raw) : null;
        if (url == null || url.scheme != 'https' || url.host.isEmpty) {
          return null;
        }
        return GantryWebPageAction(url: url, trackingEvent: trackingEvent);
      case 'lead':
        return GantryLeadAction(trackingEvent: trackingEvent);
      case 'dismiss':
        return GantryDismissAction(trackingEvent: trackingEvent);
      default:
        return null;
    }
  }
}

/// Open a screen inside the app.
final class GantryRedirectAction extends GantryAction {
  /// Creates a redirect to [deeplink].
  const GantryRedirectAction({required this.deeplink, super.trackingEvent});

  /// The deeplink to open, in the app's own scheme.
  final String deeplink;
}

/// Open an https web page.
final class GantryWebPageAction extends GantryAction {
  /// Creates an action that opens [url].
  const GantryWebPageAction({required this.url, super.trackingEvent});

  /// The https address to open.
  final Uri url;
}

/// Record that the user wants to be contacted; call `gantry.leads.submit`.
final class GantryLeadAction extends GantryAction {
  /// Creates a lead action.
  const GantryLeadAction({super.trackingEvent});
}

/// Close the interstitial.
final class GantryDismissAction extends GantryAction {
  /// Creates a dismiss action.
  const GantryDismissAction({super.trackingEvent});
}

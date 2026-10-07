# gantry

Client SDK for [Gantry](https://gantryhq.net). It lets a Flutter app

- pick the **interstitial** campaign to show when the app opens,
- send a **lead** when the user asks to be contacted,
- load **content cards** (announcements, campaigns, banners) and
- load **static pages** (FAQ, privacy notice),

with caching, retries, campaign priority and display frequency handled for you.
The SDK gives you typed data; your app draws the UI.

Supports iOS and Android. It does not depend on Firebase.

## Install

```yaml
dependencies:
  gantry: ^0.1.0
```

Android release builds need the internet permission in
`android/app/src/main/AndroidManifest.xml`; Flutter adds it to debug builds
only:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

## Set up

Create one `Gantry` when the app starts and keep it for the app's lifetime.

```dart
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:gantry/gantry.dart';

final gantry = Gantry(
  apiKey: 'gk_prod_...',   // the key of the Gantry environment this build uses
  appVersion: '2.3.1',     // your app's version: 1, 1.2 or 1.2.3
  remoteConfig: (key) => FirebaseRemoteConfig.instance.getString(key),
);
```

Each Gantry environment (dev, preprod, prod) has its own API key; put the
matching key in each build. Create keys on the **API keys** screen in Gantry.

`remoteConfig` is how the SDK reads the two Remote Config parameters Gantry
manages, `bo_interstitial` and `bo_interstitial_targeted`. Fetch and activate
Remote Config before asking for an interstitial. If your app only uses cards
and pages, leave `remoteConfig` out.

Tell the SDK who is signed in:

```dart
gantry.identify(customerId); // after sign-in, and on start if a session exists
gantry.reset();              // after sign-out
```

The customer id is the one your Gantry target lists use: 1 to 64 letters,
digits or `_ - . :`.

## Interstitials

```dart
final interstitial = await gantry.interstitials.next();
if (interstitial != null) {
  await gantry.interstitials.markShown(interstitial); // it goes on screen now
  await showMyInterstitial(interstitial);             // your UI
}
```

`next()` never throws and takes at most about two seconds. It returns null
when there is nothing to show.

**Which campaign is returned**

1. If `bo_interstitial_targeted` is `true` and a customer is identified, the
   SDK asks Gantry for a campaign targeted at that customer.
2. Otherwise, or if there is none, or the request fails or is slow, it uses
   the campaign published to everyone in `bo_interstitial`, provided it is
   enabled, inside its date range, meant for this platform and for this app
   version or older.
3. A campaign that was already shown as often as its frequency allows is
   skipped. If that happens to the targeted campaign, the general one is
   considered.

**Frequency**

| Value | Meaning |
| --- | --- |
| `once` | Once per device. |
| `daily` | Once per calendar day in the device's time zone. |
| `everyLaunch` | Once each time the app is launched. |

The SDK counts a display only when you call `markShown`. Call it as the
interstitial goes on screen, not after the user closes it: if the app is killed
while the interstitial is open, a `once` campaign would otherwise show again. The record is kept per device, not per
customer, and survives `reset()`.

**Buttons**

Each button has a label and an action. The SDK describes the action and your
app carries it out:

```dart
switch (interstitial.primaryAction) {
  case GantryRedirectAction(:final deeplink):
    openDeeplink(deeplink);
  case GantryWebPageAction(:final url):
    launchUrl(url);
  case GantryLeadAction():
    await gantry.leads.submit(campaignId: interstitial.id);
  case GantryDismissAction():
    break;
}
```

Every action may carry a `trackingEvent` name for your analytics. The SDK does
not send analytics itself.

## Leads

```dart
try {
  await gantry.leads.submit(campaignId: interstitial.id);
  showThanks();
} on GantryNotIdentifiedException {
  askToSignIn();
} on GantryException {
  showTryAgain();
}
```

A lead tells Gantry that the identified customer wants to be contacted about a
campaign. It carries no contact details. Sending the same lead twice is
harmless. The SDK retries once on a connection problem, a server error or a
rate limit, so the call can take up to about twelve seconds; show progress.

Only show a lead button while `gantry.isIdentified` is true.

## Content cards

```dart
final cards = await gantry.contents.list();                 // all cards
final deals = await gantry.contents.list(category: 'kampanya');
```

Cards come in the order set in Gantry and are already filtered for the
platform and the current date. Cards are not personal and work without
`identify`.

## Pages

```dart
final page = await gantry.pages.get('kvkk');   // null if it is not published
if (page != null) {
  render(page.body.html.resolve(languageCode));
}
```

A body is available as `markdown` and as sanitized `html`; render whichever
suits your app.

Cards and pages are cached in memory for a minute. After that the SDK checks
for changes, and if that check fails it returns the previous result.

## Texts in two languages

Texts are `LocalizedText` values with a Turkish text and an optional English
one:

```dart
card.title.resolve('en');      // English, or Turkish if no English was entered
card.title.resolve('en-US');   // locale tags work too
card.title.tr;
```

## Errors

| Call | When something goes wrong |
| --- | --- |
| `interstitials.next()` | Returns null. |
| `interstitials.markShown()` | Does nothing. |
| `contents.list()`, `pages.get()` | Returns the previous result if there is one, otherwise throws. A rejected API key always throws. |
| `leads.submit()` | Throws after one retry. |

Everything thrown for a runtime problem is a `GantryException`:

| Type | Meaning |
| --- | --- |
| `GantryNetworkException` | No connection, or the server did not answer in time. |
| `GantryUnauthorizedException` | The API key is wrong or was revoked. |
| `GantryRateLimitedException` | Too many requests in a short time. |
| `GantryServerException` | The server failed or sent something unexpected. |
| `GantryRequestException` | The server rejected the request; for a lead, the campaign id is unknown. |
| `GantryNotIdentifiedException` | The call needs `identify()` first. |

A malformed argument (customer id, app version, page key, category) throws an
`ArgumentError` straight away; that is a bug to fix, not a condition to handle.

To see what the SDK is doing, pass `onLog`:

```dart
Gantry(
  // ...
  onLog: (event) => debugPrint(event.toString()),
);
```

Log events never contain the API key or a customer id. A rejected API key is
reported at `GantryLogLevel.error`; watch for it, because `next()` hides the
failure by design.

## Options

| Option | Default | Use |
| --- | --- | --- |
| `platform` | detected from the device | Override the detected platform, for example in tests. |
| `baseUrl` | `https://app.gantryhq.net` | A self-hosted or local Gantry. |
| `httpClient` | a new `http.Client` | Your own client, for example with certificate pinning. |
| `store` | `shared_preferences` | Where the record of shown interstitials is kept. |

## About the API key

The key ships inside your app, so treat it as an identifier, not a secret. It
can read published content and campaigns and write leads for one environment.
You can have two active keys per environment: create a new one, ship it, and
revoke the old one once old app versions have faded out.

## Example

`example/` is a small app that makes every call in this README. See the
comments at the top of `example/lib/main.dart`.

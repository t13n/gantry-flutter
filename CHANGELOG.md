## 0.2.0

- `Gantry.push.sync()`: puts the device into a push bucket, so Gantry can send
  a topic push in parts. Pass `subscribeToTopic` to `Gantry`; the SDK still
  does not depend on Firebase.

## 0.1.0

First release.

- `Gantry.interstitials`: targeted and general campaigns with priority,
  eligibility and display frequency.
- `Gantry.leads`: lead submission with a single retry.
- `Gantry.contents` and `Gantry.pages`: content cards and static pages with
  in-memory caching.

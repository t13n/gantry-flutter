# gantry example

A small app that makes every call of the `gantry` package: it picks and shows
an interstitial, sends a lead, and loads content cards and a page.

It talks to a Gantry server. By default that is a local one at
`http://localhost:3000` with the development seed data.

```
flutter run                                                       # iOS simulator
flutter run --dart-define=GANTRY_BASE_URL=http://10.0.2.2:3000    # Android emulator
```

Against another server:

```
flutter run --dart-define=GANTRY_BASE_URL=https://app.gantryhq.net \
            --dart-define=GANTRY_API_KEY=gk_dev_...
```

The app does not use Firebase. A real app passes
`(key) => FirebaseRemoteConfig.instance.getString(key)` as `remoteConfig`; the
example returns fixed values so the flow can be tried without a Firebase
project.

Plain `http://` is allowed for the local network only: see
`NSAllowsLocalNetworking` in `ios/Runner/Info.plist` and
`usesCleartextTraffic` in `android/app/src/debug/AndroidManifest.xml`. An app
that talks to `https://app.gantryhq.net` needs neither.

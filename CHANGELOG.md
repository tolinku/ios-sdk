# Changelog

## 0.5.0

### Added

- `trackLinkOpen(url)` reports a link that opened the app without the browser
  being involved. A Universal Link or App Link hands the app the URL directly,
  so Tolinku is never contacted and the tap is not counted. The taps that go
  missing are the ones from people who already have the app, so a campaign aimed
  at existing customers reads as a failure exactly when it worked.

  Call it wherever the app receives a link. Both arrivals need it: a link that
  launches the app cold arrives somewhere different from one tapped while it is
  already running, and instrumenting only the second misses the more common
  case. Wiring both is safe, since the same link inside a few seconds is
  reported once.

  Only http and https links are sent. A custom scheme means Tolinku's own
  hand-off page opened the app, and that tap was already counted when the page
  was served.

  These count and bill as clicks. An Appspace set to attribute app opens only
  when reported, or never, is answered on the first call and nothing further is
  sent for the rest of the launch.

- `claimBySignals` accepts the signals as parameters, overriding what the device
  reports. The Flutter, React Native and web SDKs already did; these two took
  none, so an app holding a better value than the SDK could read had nowhere to
  put it. Overriding one signal keeps the rest: matching compares only what both
  sides supplied, so dropping the others would leave less to compare on than
  passing nothing at all.

## 0.4.0

### Added

- `claimDeferredLink(appspaceId:force:)` recovers the link that led to this
  install and remembers that it did. There is no Play Install Referrer on iOS,
  so this is signal matching with the bookkeeping that makes calling it safe,
  matching the call of the same name on the Android, React Native, Flutter and
  web SDKs.

  The bookkeeping is the point. A claim is consumed the first time it succeeds,
  so an app calling `claimBySignals` on every launch asks again after the answer
  is already spent, and each of those is recorded as a miss. The match rate in
  the dashboard then falls towards zero while the integration is working
  correctly, which is close to impossible to diagnose from outside.

  Only a settled answer is remembered. A response of "nothing waiting for this
  device" counts, because no amount of asking will change it. A thrown error
  does not, so a bad connection or an `appspaceId` that is about to be corrected
  leaves the next launch free to try again rather than spending the install's
  one chance at attribution.

- `destroy()` tears the SDK down. The name every Tolinku SDK uses for this.
  `shutdown()` does the same thing and still works; it is what this SDK shipped
  and breaking it would serve nobody. It is meant for deprecation later, once
  moving off it is a one-line change rather than a surprise.

### Unchanged

- `claimBySignals(appspaceId:)` behaves exactly as before and is not deprecated.
  It asks every time it is called; remembering is what `claimDeferredLink` adds.

## 0.3.0

### Fixed

- **Deferred deep link signal matching.** The signals sent for `claimBySignals` did not
  match the values recorded by the landing page, so some of them could never contribute
  to a match. See the per-SDK notes below.
- `claimBySignals` no longer reports a configuration error as a plain "no match". A `403`
  (wrong `appspaceId`) is now surfaced with an explanation instead of being swallowed.

  Note `appspaceId` is your Appspace ID, copied from the dashboard under Settings. It is
  not your subdomain or slug. Sending the slug was the cause of the report behind this
  release, and now produces an explicit error rather than a silent null.
- iOS sent a bare primary language subtag (`ko`) where the landing page records a full
  BCP-47 tag (`ko-KR`), so the language signal never scored. Now sends the full tag.
- `Tolinku.sdkVersion` reported `1.0.0`, a version that was never released. It now matches
  the package version, so the User-Agent is truthful.
- Matching now also compares device pixel ratio and OS version, and reports them
  automatically where the platform exposes them.

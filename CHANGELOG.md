# Changelog

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

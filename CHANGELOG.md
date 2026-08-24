# Changelog

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

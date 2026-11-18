# Changelog

## 0.8.1

### Added

- `DeferredDeepLinkResponse.url`, the absolute URL for a claimed link.

### Fixed

- The deferred open documented in 0.8.0 could never actually be reported.

  0.8.0 added the flag, and the only documented way to use it passed
  `deepLinkPath`, a path. Every SDK drops anything without an http or https
  scheme before it reaches the network, and the call never throws, so it failed
  in silence on every platform. The server could not have accepted a path
  either: the host is how it finds your Appspace and the only thing proving the
  link is yours, and your device has no way to know it.

  A claim now answers with `url` as well as `deep_link_path`, built from your
  Appspace's own host. Report that. The scheme check is unchanged, because it is
  the ownership check and not a validation nicety.

  Older servers do not send the field, so it is optional.

## 0.8.0

### Added

- `trackLinkOpen` now takes an optional flag saying whether the open followed a
  deferred install.

  Until now every reported open looked the same to the server, so it could only
  record one thing: an open by somebody who already had the app, where the
  operating system handed the link straight over and no browser was involved.
  That population can never convert to an install, which is why it is kept out
  of the install funnel.

  The other end of the same journey had no way to be reported at all. An app
  that has just claimed a deferred link and then taken the person to what the
  link pointed at is the final stage of the install funnel, the one that shows
  deep linking worked end to end rather than only that an install was
  attributed. The dashboard has always counted that stage and nothing could
  ever produce it.

  Only your app knows which of the two it is, so your app says. Call it with
  the flag set after you have routed somebody using a link you claimed on first
  run, and leave it alone everywhere else.

- Nothing changes if you do nothing. The flag defaults to off, the request body
  is unchanged when it is off, and the server still records an ordinary app
  open for anything that does not say otherwise.

## 0.7.1

### Added

- A privacy manifest, `PrivacyInfo.xcprivacy`, shipped as a resource of the
  `TolinkuSDK` target.

  The package calls `UserDefaults` in three places: message frequency capping
  in `MessagePresenter`, the cart id in `Ecommerce`, and the claim once marker
  in `DeferredDeepLink`. `UserDefaults` is on Apple's required reason API list,
  so an app that embedded this package inherited those calls with nothing
  declaring them. App Store Connect answers an upload in that state with
  ITMS-91053, naming the API but not the dependency, which left you to work out
  that it was us. The manifest declares the category with reason `CA92.1`,
  access to information available only to the app itself, which is what all
  three call sites do.

  It also declares `NSPrivacyTracking` as false with no tracking domains. That
  is a statement rather than a default: the SDK does not read the advertising
  identifier, does not call App Tracking Transparency, and does not join a
  person's activity to another company's data. Deferred matching compares
  coarse device signals inside Tolinku and discards them.

  Beyond what Apple requires, it declares the data the SDK sends, so you can
  fill in your own App Store privacy label without reading our source. The
  declaration covers the SDK's whole surface, and most integrations use less of
  it than that, so README.md maps each entry to the call that causes it. Nothing
  is sent on your behalf: `links.resolve` does not track, and `trackLinkOpen` is
  something you call, so an integration that only resolves links triggers none
  of the six.

  The Flutter plugin has carried a manifest since 0.6.2 and this package did
  not, which is the asymmetry that prompted the audit. Its declaration has been
  widened in the same release, because the Dart side of that package makes the
  same calls this one does.

- `PrivacyManifestTests`, which fails if a source file starts calling a required
  reason API that the manifest does not declare.

  A declaration kept beside the code it describes drifts from it. The test
  scans `Sources` for the five API categories Apple requires a reason for and
  checks each one it finds against the manifest, so the next person to reach
  for `FileManager` attributes or `systemUptime` is told before App Store
  Connect tells them. It also checks that `Package.swift` still names the file,
  because a manifest that is not declared as a resource is never copied into a
  bundle and reaches no app at all while looking correct in the repository.

### Changed

- `Tolinku.sdkVersion` reports `0.7.1`.

## 0.7.0

Maintenance only. Nothing in `Sources` changed except the reported SDK version,
so there is nothing here you need to act on. It carries a version because all
five SDKs moved to 0.7.0 together.

### Changed

- CI records the toolchain it used, and a second job builds and tests the
  package under the Swift 6 language mode on every push.

  That mode turns the data race checks that are warnings today into errors.
  The sources are already written for it, with `Sendable` conformances,
  `@MainActor`, and explicit `nonisolated(unsafe)` on the two stored
  observers, but nobody had ever run it. The job passes the language mode on
  the command line rather than setting it in `Package.swift`, so consumers
  resolve this package exactly as they do now, and it is allowed to fail so it
  reports rather than blocks.

  Once it has been green for a while, the setting moves into `Package.swift`
  behind `swift-tools-version: 6.0` and the job goes away. That is a real
  release when it happens; this is not.

## 0.6.1

### Fixed

- A call to action in an in-app message could not open a deep link into your
  own app.

  The button's URL was checked against an http and https allowlist, so
  `myapp://order/4821`, which on a deep linking product is the most natural
  button a message can have, was refused before anything happened: no
  navigation, and your own action callback was never called either. The server
  that renders these messages has always allowed the link; only the SDK
  declined to follow it.

  The rule is now the denylist the platform itself applies. The schemes that
  can run code or forge an origin are named and refused, and everything else is
  left to open, because no list could hold every customer's scheme.

  To be exact about the blast radius, since an earlier draft of this note was
  not: the message action was the only thing in this SDK that used the http and
  https rule, so `isSafeUrl` now has no callers here. It is kept, and still
  means what it meant, but nothing in this package is guarded by it. Message
  artwork is not: that is rendered server side and its image sources are
  checked there.

- A message with only a title and a body rendered as an empty screen, because
  the server answered nothing for a message with no designed content. That is
  a server side fix and needs no change here beyond this note.
- A deep link carrying a space or a non-ASCII character was refused below
  iOS 17, where `URL(string:)` returns nil for both, and the refusal was
  logged as an unsafe scheme rather than what it was.
- A scheme containing an underscore was refused. Those are not RFC 3986, but
  iOS registers them and real apps use them.

## 0.6.0

### Added

- `Tolinku.links.resolve(url)` turns a link the system handed the app into the
  route and token it means.

  An app receives the URL that was tapped, exactly as written. That is fine
  while the URL is readable: `/order/4821` says "order" and the app can route
  it. A short link is the same route written as a code, `/s7k2p9q/4821`, and
  nothing in it says "order", nor can the code be worked out on the device. An
  app parsing the path itself sees a first segment it has never heard of and
  does nothing, so the link opens the app and then appears to fail: no error, no
  screen, no clue. Short links are what the dashboard offers for sharing and
  what a QR code carries, so this is not a rare path.

  A readable URL comes back unchanged, so an app can resolve everything rather
  than guessing which kind it has. The question goes to the link's own host,
  which is how the platform knows the Appspace, so a link on someone else's
  domain answers nothing. Never throws: this runs during a cold start, and an
  exception there is the difference between a link that did not route and an app
  that did not start.

  Needs a platform new enough to answer for a whole path on `/v1/api/path`.

### Fixed

- Referral links shared in short form could open the app without the referral
  code reaching it. Resolve incoming links with `links.resolve` and the code arrives
  with the rest of the link.

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

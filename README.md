# FeatureBoard for iOS

A SwiftUI screen for a [Feedbapp](https://feedbapp.beltech.es) feature request board: people read, post, vote and comment without leaving your app. The board is web content in a locked-down `WKWebView`; sessions stay in memory and last five minutes.

Requires iOS 16+.

## Install

In Xcode, **File → Add Package Dependencies**, enter `https://github.com/itsbauza/feature-board-ios`, and add the `FeatureBoard` product. Or in `Package.swift`:

```swift
.package(url: "https://github.com/itsbauza/feature-board-ios", from: "1.0.0")
```

## Apps with an App Store subscription: no backend needed

Turn on **App Store subscriptions** in your board's settings (bundle ID and your app's Apple ID from App Store Connect). The SDK sends the subscription StoreKit 2 has verified on the device; the board checks Apple's signature, the product and the expiry, then issues the session.

```swift
import FeatureBoard

FeatureBoardView(
    url: URL(string: "https://feedbapp.beltech.es/board/my-app")!,
    appStoreProductIDs: nil, // or only some of your subscriptions
    contactSupport: ("Email support", { openURL(supportMailto) })
)
.navigationTitle("Feature requests")
```

Anyone can read the board. Without an active subscription, or when a session can't be had, the board stays readable and a notice explains that posting is for members, with **Try again** and your `contactSupport` action. If the board itself can't load (offline), a full screen offers the same two actions.

## Apps with their own backend

Your backend authenticates the user, checks their entitlement and exchanges the board's server API key for a session (`POST /api/v1/boards/<id>/sessions`). Never ship that key in the app; pass a provider that calls your backend instead:

```swift
FeatureBoardView(url: boardURL, contactSupport: support) {
    try await myBackend.featureBoardToken()
}
.id(accountID) // a new account discards the previous session
```

The provider runs when the board first needs a session and whenever it asks for a fresh one.

## Notes

- Present it inside your own navigation or sheet; keep the normal safe area and keyboard layout.
- Only the board's own origin can load or talk to the bridge; other links, frames and windows are blocked.
- For a simulator against a local board, pass `allowLocalhostHTTP: true` (loopback hosts only).

## License

MIT

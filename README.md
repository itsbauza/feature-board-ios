# FeatureBoard for SwiftUI

Add this directory as a local Swift package in Xcode and link the `FeatureBoard` product. Requires iOS 16+. Present `FeatureBoardView(url:tokenProvider:)` in your existing navigation or sheet. The async provider returns a short-lived session from your trusted app backend, never a board API key. Apps that sell an auto-renewable subscription can skip the backend: turn on App Store subscriptions for the board and use `FeatureBoardView(url:appStoreProductIDs:contactSupport:)`.

See the [complete integration guide](../../docs/integration.md) for authentication, the Firebase issuer, account switching, keyboard/safe-area handling, and production verification.

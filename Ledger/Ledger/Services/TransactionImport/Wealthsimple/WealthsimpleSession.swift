import Foundation

/// Everything needed to talk to Wealthsimple's API on the user's behalf after a successful login.
///
/// This is the *direct* connection: instead of paying a third-party aggregator (Plaid), the app
/// authenticates straight against Wealthsimple's own production API with the user's credentials,
/// exactly the way the Wealthsimple web app does. The pieces here are the OAuth tokens plus the
/// two device/session identifiers Wealthsimple expects on every request.
///
/// Persisted as a single JSON blob in the Keychain (see `WealthsimpleCredentialStore`); nothing
/// here ever touches UserDefaults or source control.
struct WealthsimpleSession: Sendable, Codable {
    /// OAuth client id of the Wealthsimple web app, scraped during bootstrap (it can rotate, so
    /// it isn't hard-coded).
    var clientId: String
    /// Short-lived bearer token used to authenticate API calls.
    var accessToken: String
    /// Long-lived token used to mint a fresh `accessToken` when it expires.
    var refreshToken: String
    /// Per-install session id (`x-ws-session-id`); any stable UUID works.
    var sessionId: String
    /// Device id (`x-ws-device-id`), the `wssdi` cookie handed out by the login page.
    var deviceId: String
    /// The identity the tokens belong to, needed to scope GraphQL account queries. Filled in
    /// lazily from `/token/info` on the first sync and cached thereafter.
    var identityId: String?
}

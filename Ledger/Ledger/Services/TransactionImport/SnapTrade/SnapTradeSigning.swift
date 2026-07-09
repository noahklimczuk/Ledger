import CryptoKit
import Foundation

/// Implements SnapTrade's request-signing scheme: https://docs.snaptrade.com/docs/request-signatures
/// (verified against SnapTrade's published docs; re-check field names/casing against the live
/// API once real credentials are available, since this was written without a real account to
/// test against).
enum SnapTradeSigning {
    /// Builds `{"content": <body-or-null>, "path": "/api/v1/...", "query": "..."}`, serializes
    /// it to canonical JSON (keys sorted at every level, no whitespace), HMAC-SHA256s it with
    /// the consumer key, and base64-encodes the digest. The result goes in the `Signature`
    /// header alongside `clientId`/`timestamp` query params on every request.
    static func signature(consumerKey: String, path: String, query: String, jsonBody: Data?) -> String {
        let contentValue: Any
        if let jsonBody, let object = try? JSONSerialization.jsonObject(with: jsonBody) {
            contentValue = object
        } else {
            contentValue = NSNull()
        }

        let signaturePayload: [String: Any] = [
            "content": contentValue,
            "path": path,
            "query": query
        ]

        guard let canonicalData = try? JSONSerialization.data(
            withJSONObject: signaturePayload,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ) else {
            return ""
        }

        let key = SymmetricKey(data: Data(consumerKey.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: canonicalData, using: key)
        return Data(mac).base64EncodedString()
    }
}

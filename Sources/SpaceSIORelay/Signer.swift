import CryptoKit
import Foundation

/// The station's identity: an Ed25519 keypair generated on first run and kept
/// in the Keychain. Every confirmation is signed with it so the network can
/// verify WHICH relay station put a signal on the air.
struct Signer {
    let privateKey: Curve25519.Signing.PrivateKey

    static func load() -> Signer {
        if let b64 = Keychain.get(account: "station-key"),
           let raw = Data(base64Encoded: b64),
           let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) {
            return Signer(privateKey: key)
        }
        let key = Curve25519.Signing.PrivateKey()
        Keychain.set(key.rawRepresentation.base64EncodedString(), account: "station-key")
        return Signer(privateKey: key)
    }

    /// Base64 of the raw 32-byte public key — sent with every confirmation.
    var publicKeyBase64: String {
        privateKey.publicKey.rawRepresentation.base64EncodedString()
    }

    /// Signs the canonical confirmation payload; returns base64 signature.
    func sign(_ payload: String) -> String? {
        (try? privateKey.signature(for: Data(payload.utf8)))?.base64EncodedString()
    }

    /// Canonical payload — MUST stay in sync with /api/radio/complete.
    static func confirmationPayload(
        id: String, payloadHash: String?, at date: Date, lat: String, lon: String
    ) -> String {
        let iso = ISO8601DateFormatter().string(from: date)
        return "spacesio-confirm-v1\nid:\(id)\nhash:\(payloadHash ?? "")\nat:\(iso)\nlat:\(lat)\nlon:\(lon)"
    }
}

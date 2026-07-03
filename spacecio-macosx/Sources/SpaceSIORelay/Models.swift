import Foundation

/// `GET /api/radio/next` response.
struct FeedResponse: Decodable {
    let transmission: Transmission?
    let retry: Bool?
}

struct Transmission: Decodable, Identifiable {
    let id: String
    let slug: String?
    let type: String?
    let title: String?
    let body: String?
    let bytes: Int?
    let packet: String?        // base64 proof packet — this is what goes on air
    let packet_bytes: Int?
    let payload_hash: String?
    let callsign: String?
    let created_at: String?
    let permalink: String?
}

/// `POST /api/radio/complete` response.
struct CompleteResponse: Decodable {
    let ok: Bool?
    let permalink: String?
    let certificate_url: String?
    let signature_verified: Bool?
    let signature_stored: Bool?
    let error: String?
}

struct LogEntry: Identifiable {
    enum Kind { case info, success, error }
    let id = UUID()
    let date: Date
    let text: String
    let kind: Kind
}

/// The receipt shown after a successful signed confirmation.
struct Confirmation {
    let title: String
    let permalink: String?
    let certificateURL: String?
    let lat: Double?
    let lon: Double?
    let signaturePrefix: String
    let verified: Bool
    let date: Date
}

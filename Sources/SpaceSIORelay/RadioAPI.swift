import Foundation

enum RadioAPIError: LocalizedError {
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .http(let code, let msg): return "Server \(code): \(msg)"
        case .badResponse: return "Unexpected server response."
        }
    }
}

/// Thin client for the SpaceSIO radio feed API.
struct RadioAPI {
    let baseURL: URL
    let apiKey: String

    /// Claims the next queued transmission for this station.
    func next(rig: String) async throws -> FeedResponse {
        guard var comps = URLComponents(
            url: baseURL.appending(path: "api/radio/next"),
            resolvingAgainstBaseURL: false
        ) else { throw RadioAPIError.badResponse }
        comps.queryItems = [URLQueryItem(name: "rig", value: rig)]
        guard let url = comps.url else { throw RadioAPIError.badResponse }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.check(resp, data: data)
        return try JSONDecoder().decode(FeedResponse.self, from: data)
    }

    /// Sends the signed confirmation back after broadcasting.
    func complete(
        id: String, signedPayload: String, signature: String, pubkey: String
    ) async throws -> CompleteResponse {
        var req = URLRequest(url: baseURL.appending(path: "api/radio/complete"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "id": id,
            "status": "transmitted",
            "signed_payload": signedPayload,
            "signature": signature,
            "pubkey": pubkey,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.check(resp, data: data)
        return try JSONDecoder().decode(CompleteResponse.self, from: data)
    }

    private struct ErrBody: Decodable { let error: String? }

    private static func check(_ resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(ErrBody.self, from: data))?.error
                ?? "unexpected response"
            throw RadioAPIError.http(http.statusCode, msg)
        }
    }
}

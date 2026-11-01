import Foundation

// Zero-config conversion: pages go to the built-in MathNotes conversion service, which
// runs a managed vision model (Gemini) plus a validate-and-fix loop server-side.
// No API key, no model download. Override UserDefaults "cloudEndpoint" to self-host.

nonisolated struct CloudResult: Decodable, Sendable {
    var id: String
    var title: String
    var latex_body: String
    var full_document: String
    var status: String        // "verified" | "best_effort" | "empty"
    var issues: [String]
    var attempts: Int
    var model: String

    enum CodingKeys: String, CodingKey {
        case id, title
        case latex_body = "latex_body"
        case full_document = "full_document"
        case status, issues, attempts, model
    }
}

nonisolated struct CloudError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

// No stored state (the endpoint is read from UserDefaults, which is thread-safe), so it is Sendable.
nonisolated final class CloudConverter: Sendable {
    static let shared = CloudConverter()

    /// Default: the built-in service. Override with UserDefaults "cloudEndpoint" for self-hosting.
    var endpoint: URL {
        if let stored = UserDefaults.standard.string(forKey: "cloudEndpoint"), let u = URL(string: stored) {
            return u
        }
        return URL(string: "https://math-notes-latex.preview.emergentagent.com/api/convert")!
    }

    func convert(imageData: Data, mime: String, context: String?) async throws -> CloudResult {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 300
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "image_b64": imageData.base64EncodedString(),
            "mime": mime,
            "source": "ios",
        ]
        if let context, !context.isEmpty { body["context"] = context }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw CloudError(message: "The conversion service did not respond.")
        }
        guard http.statusCode == 200 else {
            throw CloudError(message: "The conversion service returned code \(http.statusCode). Try again in a moment.")
        }
        return try JSONDecoder().decode(CloudResult.self, from: data)
    }
}

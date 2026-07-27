import Foundation
import Combine

public enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case openAI
    case gemini

    public var id: String { rawValue }
    public var displayName: String { self == .openAI ? "OpenAI" : "Google Gemini" }
}

@MainActor
public final class AIEngine: ObservableObject {
    @Published public var apiKey = ""
    @Published public var provider: AIProvider = .openAI
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastError: String?

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Sends the error log to the selected provider. The key stays in memory only.
    public func explainError(_ errorLog: String) async -> String {
        let trimmedLog = errorLog.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLog.isEmpty else { return "Please paste an error log first." }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Enter an API key before requesting an analysis."
        }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            switch provider {
            case .openAI:
                return try await requestOpenAI(errorLog: trimmedLog)
            case .gemini:
                return try await requestGemini(errorLog: trimmedLog)
            }
        } catch {
            let message = error.localizedDescription
            lastError = message
            return "AI request failed: \(message)"
        }
    }

    private func requestOpenAI(errorLog: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        let requestBody = OpenAIRequest(
            model: "gpt-4.1-mini",
            messages: [
                .init(role: "system", content: "You are a concise Apple-platform debugging assistant."),
                .init(role: "user", content: "Explain this build or runtime error, identify the likely cause, and propose concrete next steps:\n\n\(errorLog)")
            ],
            temperature: 0.2
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let data = try await send(request)
        let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = response.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
            throw AIEngineError.emptyResponse
        }
        return content
    }

    private func requestGemini(errorLog: String) async throws -> String {
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GeminiRequest(
            contents: [.init(parts: [.init(text: "Explain this Apple-platform build or runtime error and give concise concrete remediation steps:\n\n\(errorLog)")])],
            generationConfig: .init(temperature: 0.2)
        ))

        let data = try await send(request)
        let response = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let content = response.candidates?
            .first?
            .content?
            .parts?
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let content, !content.isEmpty else { throw AIEngineError.emptyResponse }
        return content
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw AIEngineError.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.error.message
            throw AIEngineError.httpStatus(httpResponse.statusCode, apiError ?? "No error body returned")
        }
        return data
    }
}

private enum AIEngineError: LocalizedError {
    case invalidResponse
    case emptyResponse
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The server returned an invalid response."
        case .emptyResponse: return "The model returned no text."
        case .httpStatus(let code, let message): return "HTTP \(code): \(message)"
        }
    }
}

private struct OpenAIRequest: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    let model: String
    let messages: [Message]
    let temperature: Double
}

private struct OpenAIResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }
    let choices: [Choice]
}

private struct GeminiRequest: Encodable {
    struct Content: Encodable { let parts: [Part] }
    struct Part: Encodable { let text: String }
    struct GenerationConfig: Encodable { let temperature: Double }
    let contents: [Content]
    let generationConfig: GenerationConfig
}

private struct GeminiResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable { let text: String? }
            let parts: [Part]?
        }
        let content: Content?
    }
    let candidates: [Candidate]?
}

private struct APIErrorEnvelope: Decodable {
    struct APIError: Decodable { let message: String }
    let error: APIError
}

import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case serverError(statusCode: Int, message: String)
    case decodingError(Error)
    case unauthorizedSessionRevoked

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL de servicio inválida."
        case .networkError(let error):
            return "Error de red: \(error.localizedDescription)"
        case .serverError(_, let message):
            return message
        case .decodingError:
            return "Error al procesar la respuesta del servidor."
        case .unauthorizedSessionRevoked:
            return "Tu sesión se ha abierto en otro dispositivo. Por favor ingresa nuevamente."
        }
    }
}

final class APIClient: ObservableObject {
    static let shared = APIClient()

    /// URL del backend (Servidor Cloud: 34.61.17.233 o local en desarrollo)
    @Published var baseURLString: String

    private var baseURL: URL {
        URL(string: baseURLString) ?? URL(string: "http://34.61.17.233/api/v1")!
    }

    var canReachRemoteBackend: Bool {
        return !baseURLString.isEmpty
    }

    func updateBaseURL(_ newURL: String) {
        let trimmed = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/api/v1") {
            baseURLString = trimmed
        } else if trimmed.hasSuffix("/") {
            baseURLString = "\(trimmed)api/v1"
        } else {
            baseURLString = "\(trimmed)/api/v1"
        }
        UserDefaults.standard.set(baseURLString, forKey: "bc_backend_url")
    }

    private let session: URLSession

    private init() {
        let savedURL = UserDefaults.standard.string(forKey: "bc_backend_url")
        self.baseURLString = savedURL ?? "http://34.61.17.233/api/v1"

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 4.0
        configuration.timeoutIntervalForResource = 8.0
        self.session = URLSession(configuration: configuration)
    }

    func request<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if requiresAuth, let token = KeychainService.shared.get(key: "access_token") {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = body
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidURL
            }

            if httpResponse.statusCode == 401 {
                KeychainService.shared.delete(key: "access_token")
                throw APIError.unauthorizedSessionRevoked
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                if let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let detail = jsonObj["detail"] as? String {
                    throw APIError.serverError(statusCode: httpResponse.statusCode, message: detail)
                }
                let errorMsg = String(data: data, encoding: .utf8) ?? "Error en el servidor"
                throw APIError.serverError(statusCode: httpResponse.statusCode, message: errorMsg)
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: data)
        } catch let apiError as APIError {
            throw apiError
        } catch {
            throw APIError.networkError(error)
        }
    }
}

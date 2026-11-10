import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case serverError(statusCode: Int, message: String)
    case decodingError(Error)
    case unauthorizedSessionRevoked // Sesión única estilo Yape

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
    #if DEBUG
    @Published var baseURLString: String = "http://localhost:8000/api/v1"
    #else
    @Published var baseURLString: String = "https://api.bc-tacna.pe/api/v1"
    #endif

    private var baseURL: URL {
        URL(string: baseURLString) ?? URL(string: "http://localhost:8000/api/v1")!
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
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15.0
        configuration.timeoutIntervalForResource = 30.0
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
                // Notificar revocación de sesión única
                KeychainService.shared.delete(key: "access_token")
                throw APIError.unauthorizedSessionRevoked
            }

            guard (200...299).contains(httpResponse.statusCode) else {
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


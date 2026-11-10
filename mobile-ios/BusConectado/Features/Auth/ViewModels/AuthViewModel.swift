import Foundation
import Combine
import UIKit

enum OnboardingStep {
    case splash
    case phoneInput
    case otpVerification
    case success
}

struct UserAuth: Codable, Identifiable {
    let id: String
    let phone: String
    let name: String?
    let role: String
    var pointsBalance: Int
    let isNewUser: Bool
}

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep = .splash
    @Published var phoneNumber: String = ""
    @Published var otpCode: String = ""
    @Published var isGuestMode: Bool = false
    @Published var isLoggedIn: Bool = false
    @Published var currentUser: UserAuth? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var countdownSeconds: Int = 59
    @Published var backendHost: String = "localhost:8000"

    private var countdownTimer: AnyCancellable?

    init() {
        // Cargar URL guardada
        if let savedHost = UserDefaults.standard.string(forKey: "bc_backend_host") {
            self.backendHost = savedHost
            APIClient.shared.updateBaseURL("http://\(savedHost)")
        }

        // Verificar si existe sesión previa
        if let token = KeychainService.shared.get(key: "access_token"), !token.isEmpty {
            self.isLoggedIn = true
            // Cargar usuario en memoria si existe
            if let userData = UserDefaults.standard.data(forKey: "bc_user_profile"),
               let profile = try? JSONDecoder().decode(UserAuth.self, from: userData) {
                self.currentUser = profile
            }
        }
    }

    var isValidPhone: Bool {
        let cleaned = phoneNumber.filter { $0.isNumber }
        return cleaned.count == 9 && cleaned.hasPrefix("9")
    }

    func updateBackendHost(_ host: String) {
        self.backendHost = host
        UserDefaults.standard.set(host, forKey: "bc_backend_host")
        APIClient.shared.updateBaseURL("http://\(host)")
    }

    func sendOtp() async {
        guard isValidPhone else {
            errorMessage = "Ingresa un número peruano de 9 dígitos que inicie con 9"
            return
        }

        isLoading = true
        errorMessage = nil

        struct SendRequest: Encodable {
            let phone: String
        }

        struct SendResponse: Decodable {
            let success: Bool
            let expiresInSeconds: Int
        }

        do {
            let body = try JSONEncoder().encode(SendRequest(phone: phoneNumber))
            let _: SendResponse = try await APIClient.shared.request(
                endpoint: "auth/otp/send",
                method: "POST",
                body: body,
                requiresAuth: false
            )
            isLoading = false
            currentStep = .otpVerification
            startCountdown()
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    func verifyOtp() async {
        guard otpCode.count == 6 else {
            errorMessage = "El código debe tener 6 dígitos"
            return
        }

        isLoading = true
        errorMessage = nil

        struct VerifyRequest: Encodable {
            let phone: String
            let code: String
            let deviceId: String
            let deviceName: String
        }

        struct TokenResponse: Decodable {
            let accessToken: String
            let refreshToken: String
            let user: UserAuth
        }

        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "IOS-PHONE-001"
        let deviceName = UIDevice.current.name

        do {
            let req = VerifyRequest(phone: phoneNumber, code: otpCode, deviceId: deviceId, deviceName: deviceName)
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let body = try encoder.encode(req)
            let res: TokenResponse = try await APIClient.shared.request(
                endpoint: "auth/otp/verify",
                method: "POST",
                body: body,
                requiresAuth: false
            )

            // Guardar tokens en Keychain seguro
            _ = KeychainService.shared.save(key: "access_token", value: res.accessToken)
            _ = KeychainService.shared.save(key: "refresh_token", value: res.refreshToken)

            // Guardar usuario en memoria y persistencia
            self.currentUser = res.user
            if let encoded = try? JSONEncoder().encode(res.user) {
                UserDefaults.standard.set(encoded, forKey: "bc_user_profile")
            }

            isLoading = false
            currentStep = .success
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    func completeOnboarding() {
        self.isLoggedIn = true
        self.isGuestMode = false
    }

    func continueAsGuest() {
        self.isGuestMode = true
        self.isLoggedIn = false
    }

    func logout() async {
        isLoading = true
        struct LogoutResponse: Decodable {
            let success: Bool
            let message: String
        }

        do {
            let _: LogoutResponse = try await APIClient.shared.request(
                endpoint: "auth/logout",
                method: "DELETE",
                requiresAuth: true
            )
        } catch {
            print("[WARN] Error al revocar sesión en servidor: \(error.localizedDescription)")
        }

        // Limpiar tokens y estado local
        _ = KeychainService.shared.delete(key: "access_token")
        _ = KeychainService.shared.delete(key: "refresh_token")
        UserDefaults.standard.removeObject(forKey: "bc_user_profile")

        self.currentUser = nil
        self.isLoggedIn = false
        self.isGuestMode = false
        self.phoneNumber = ""
        self.otpCode = ""
        self.currentStep = .splash
        self.isLoading = false
    }

    private func startCountdown() {
        countdownSeconds = 59
        countdownTimer?.cancel()
        countdownTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.countdownSeconds > 0 {
                    self.countdownSeconds -= 1
                } else {
                    self.countdownTimer?.cancel()
                }
            }
    }
}

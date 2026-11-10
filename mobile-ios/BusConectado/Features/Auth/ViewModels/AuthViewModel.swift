import Foundation
import Combine

enum OnboardingStep {
    case splash
    case phoneInput
    case otpVerification
    case success
}

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep = .splash
    @Published var phoneNumber: String = ""
    @Published var otpCode: String = ""
    @Published var isGuestMode: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var countdownSeconds: Int = 59

    private var countdownTimer: AnyCancellable?

    var isValidPhone: Bool {
        let cleaned = phoneNumber.filter { $0.isNumber }
        return cleaned.count == 9 && cleaned.hasPrefix("9")
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

        struct UserAuth: Decodable {
            let id: String
            let phone: String
            let name: String?
            let role: String
            let pointsBalance: Int
            let isNewUser: Bool
        }

        struct TokenResponse: Decodable {
            let accessToken: String
            let refreshToken: String
            let user: UserAuth
        }

        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "IOS-UNKNOWN"
        let deviceName = UIDevice.current.name

        do {
            let req = VerifyRequest(phone: phoneNumber, code: otpCode, deviceId: deviceId, deviceName: deviceName)
            let body = try JSONEncoder().encode(req)
            let res: TokenResponse = try await APIClient.shared.request(
                endpoint: "auth/otp/verify",
                method: "POST",
                body: body,
                requiresAuth: false
            )

            // Guardar tokens en Keychain seguro
            _ = KeychainService.shared.save(key: "access_token", value: res.accessToken)
            _ = KeychainService.shared.save(key: "refresh_token", value: res.refreshToken)

            isLoading = false
            currentStep = .success
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    func continueAsGuest() {
        isGuestMode = true
        currentStep = .splash
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

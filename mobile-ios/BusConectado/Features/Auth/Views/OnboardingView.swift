import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: AuthViewModel
    @FocusState private var isPhoneFocused: Bool
    @FocusState private var isOtpFocused: Bool

    var body: some View {
        ZStack {
            // Fondo oscuro estilo Tacna Night (#0B111E)
            Color(red: 11/255, green: 17/255, blue: 30/255)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header con botón Modo Invitado
                HStack {
                    Spacer()
                    if viewModel.currentStep != .success {
                        Button {
                            withAnimation(.easeInOut) {
                                viewModel.continueAsGuest()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("Modo Invitado")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Image(systemName: "arrow.right")
                                    .font(.caption)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                Spacer()

                // Contenido dinámico según el paso
                switch viewModel.currentStep {
                case .splash:
                    splashStepView
                case .phoneInput:
                    phoneInputStepView
                case .otpVerification:
                    otpVerificationStepView
                case .success:
                    successStepView
                }

                Spacer()
            }
        }
    }

    // MARK: - Paso 1: Splash
    private var splashStepView: some View {
        VStack(spacing: 28) {
            // Icono con resplandor neón
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.18))
                    .frame(width: 140, height: 140)
                    .blur(radius: 20)

                RoundedRectangle(cornerRadius: 32)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.85), Color.cyan.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 110, height: 110)
                    .overlay(
                        RoundedRectangle(cornerRadius: 32)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                    )

                Image(systemName: "bus.fill")
                    .font(.system(size: 52))
                    .foregroundColor(.white)
            }

            VStack(spacing: 8) {
                Text("Bus Conectado")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)

                Text("Tacna · Transporte Urbano Digital")
                    .font(.subheadline)
                    .foregroundColor(.gray)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.emerald)
                        .frame(width: 8, height: 8)
                    Text("Línea 10 en tiempo real")
                        .font(.caption)
                        .foregroundColor(.emerald)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.emerald.opacity(0.12))
                .clipShape(Capsule())
                .padding(.top, 4)
            }

            VStack(spacing: 14) {
                Button {
                    withAnimation(.easeInOut) {
                        viewModel.currentStep = .phoneInput
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "phone.fill")
                        Text("Iniciar Sesión / Registrarse")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.emerald)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Button {
                    withAnimation(.easeInOut) {
                        viewModel.continueAsGuest()
                    }
                } label: {
                    Text("Explorar sin registrarse")
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                }

                Text("Al continuar aceptas los Términos y Privacidad de BC")
                    .font(.caption2)
                    .foregroundColor(.gray.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Paso 2: Teléfono
    private var phoneInputStepView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Ingresa tu número celular")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Te enviaremos un código de seguridad por SMS para verificar tu identidad.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            // Input peruano +51
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text("🇵🇪")
                    Text("+51")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                TextField("952 123 456", text: $viewModel.phoneNumber)
                    .keyboardType(.numberPad)
                    .focused($isPhoneFocused)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(viewModel.isValidPhone ? Color.emerald : Color.white.opacity(0.15), lineWidth: 1.5)
                    )
            }
            .padding(.horizontal, 28)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Button {
                Task {
                    await viewModel.sendOtp()
                }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                } else {
                    Text("Continuar")
                        .fontWeight(.semibold)
                        .foregroundColor(viewModel.isValidPhone ? .black : .white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
            }
            .background(viewModel.isValidPhone ? Color.emerald : Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .disabled(!viewModel.isValidPhone || viewModel.isLoading)
            .padding(.horizontal, 28)

            Button {
                withAnimation {
                    viewModel.currentStep = .splash
                }
            } label: {
                Text("Volver")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
        .onAppear {
            isPhoneFocused = true
        }
    }

    // MARK: - Paso 3: Verificación OTP (6 casillas fintech)
    private var otpVerificationStepView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Verifica tu código")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Ingresa los 6 dígitos enviados al +51 \(viewModel.phoneNumber)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            // 6 casillas interactivas
            ZStack {
                // TextField invisible para capturar el teclado numérico
                TextField("", text: $viewModel.otpCode)
                    .keyboardType(.numberPad)
                    .focused($isOtpFocused)
                    .opacity(0.01)
                    .onChange(of: viewModel.otpCode) { _, newValue in
                        if newValue.count > 6 {
                            viewModel.otpCode = String(newValue.prefix(6))
                        }
                        if viewModel.otpCode.count == 6 {
                            Task {
                                await viewModel.verifyOtp()
                            }
                        }
                    }

                HStack(spacing: 10) {
                    ForEach(0..<6, id: \.self) { index in
                        let char = getDigit(at: index)
                        let isCurrent = viewModel.otpCode.count == index

                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 46, height: 56)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(isCurrent ? Color.emerald : (char.isEmpty ? Color.white.opacity(0.15) : Color.white.opacity(0.4)), lineWidth: 1.5)
                                )

                            Text(char)
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .onTapGesture {
                isOtpFocused = true
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            // Temporizador de reenvío
            if viewModel.countdownSeconds > 0 {
                Text("Reenviar código en \(viewModel.countdownSeconds)s")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                Button {
                    Task {
                        await viewModel.sendOtp()
                    }
                } label: {
                    Text("Reenviar código por SMS")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.emerald)
                }
            }

            Button {
                Task {
                    await viewModel.verifyOtp()
                }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                } else {
                    Text("Verificar y Acceder")
                        .fontWeight(.semibold)
                        .foregroundColor(viewModel.otpCode.count == 6 ? .black : .white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
            }
            .background(viewModel.otpCode.count == 6 ? Color.emerald : Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .disabled(viewModel.otpCode.count != 6 || viewModel.isLoading)
            .padding(.horizontal, 28)

            Button {
                withAnimation {
                    viewModel.currentStep = .phoneInput
                }
            } label: {
                Text("Cambiar número")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
        .onAppear {
            isOtpFocused = true
        }
    }

    // MARK: - Paso 4: Éxito
    private var successStepView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.emerald.opacity(0.2))
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.emerald)
            }

            VStack(spacing: 8) {
                Text("¡Bienvenido a Bus Conectado!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Tu cuenta ha sido verificada. Tu monedero ha sido inicializado con 0 puntos.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Button {
                withAnimation(.easeInOut) {
                    viewModel.completeOnboarding()
                }
            } label: {
                Text("Comenzar a viajar")
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.emerald)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
        }
    }

    private func getDigit(at index: Int) -> String {
        let digits = Array(viewModel.otpCode)
        if index < digits.count {
            return String(digits[index])
        }
        return ""
    }
}

// Color Extension para Emerald (#10B981)
extension Color {
    static let emerald = Color(red: 16/255, green: 185/255, blue: 129/255)
}

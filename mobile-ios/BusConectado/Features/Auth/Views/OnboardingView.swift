import SwiftUI
import AuthenticationServices

struct OnboardingView: View {
    @ObservedObject var viewModel: AuthViewModel
    @FocusState private var isPhoneFocused: Bool
    @FocusState private var isOtpFocused: Bool
    @State private var showGoogleInputSheet: Bool = false
    @State private var googleNameInput: String = ""
    @State private var googleLastNameInput: String = ""
    @State private var googleEmailInput: String = ""
    @State private var googleIsRegistration: Bool = true

    var body: some View {
        ZStack {
            BCTheme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Barra superior minimalista (sin botón Modo Invitado)
                HStack {
                    if viewModel.currentStep != .splash && viewModel.currentStep != .success {
                        Button {
                            BCFeedbackManager.shared.impactLight()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                viewModel.errorMessage = nil
                                switch viewModel.currentStep {
                                case .otpVerification:
                                    viewModel.currentStep = .phoneInput
                                case .phoneInput:
                                    viewModel.currentStep = viewModel.isLinkingPhoneFlow ? .profileSetup : .splash
                                case .profileSetup:
                                    viewModel.currentStep = .registerSocial
                                default:
                                    viewModel.currentStep = .splash
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.subheadline.weight(.semibold))
                                Text("Atrás")
                                    .font(.subheadline)
                            }
                            .foregroundColor(.white.opacity(0.8))
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .frame(minHeight: 38)

                Spacer()

                switch viewModel.currentStep {
                case .splash:
                    splashStepView
                case .registerSocial:
                    registerSocialStepView
                case .profileSetup:
                    profileSetupStepView
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
        .sheet(isPresented: $showGoogleInputSheet) {
            googleSignInSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Paso 1: Splash (Iniciar Sesión, Registrarse o Iniciar como Invitado)
    private var splashStepView: some View {
        VStack(spacing: 30) {
            ZStack {
                Circle()
                    .fill(BCTheme.royalBlue.opacity(0.18))
                    .frame(width: 148, height: 148)
                    .blur(radius: 26)

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(red: 12/255, green: 20/255, blue: 38/255))
                    .frame(width: 98, height: 98)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [BCTheme.cyanAccent.opacity(0.8), BCTheme.royalBlue.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.8
                            )
                    )

                Image(systemName: "bus.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 96/255, green: 165/255, blue: 250/255), BCTheme.cyanAccent],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            VStack(spacing: 10) {
                Text("Bus Conectado")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Tacna · Transporte Urbano Digital")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.55))

                HStack(spacing: 7) {
                    Circle()
                        .fill(BCTheme.emerald)
                        .frame(width: 7, height: 7)
                    Text("Rutas urbanas de Tacna en tiempo real")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white.opacity(0.75))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.05))
                .overlay(
                    Capsule()
                        .stroke(BCTheme.hairlineBorder, lineWidth: 1)
                )
                .clipShape(Capsule())
                .padding(.top, 2)
            }

            VStack(spacing: 12) {
                Button {
                    BCFeedbackManager.shared.impactLight()
                    viewModel.errorMessage = nil
                    googleIsRegistration = false
                    showGoogleInputSheet = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "g.circle.fill")
                            .font(.title3)
                            .foregroundColor(.black)
                        Text("Continuar con Google")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleAppleAuthResult(result, isRegistration: false)
                }
                .signInWithAppleButtonStyle(.whiteOutline)
                .frame(height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        viewModel.continueAsGuest()
                    }
                } label: {
                    Text("Iniciar como Invitado")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.78))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(BCTheme.hairlineBorder, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(BCTheme.destructiveRed)
                        .multilineTextAlignment(.center)
                }

                Text("Al continuar aceptas los Términos y Privacidad de Bus Conectado")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Registro: Solo Google y Apple ID
    private var registerSocialStepView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "person.badge.shield.checkmark.fill")
                    .font(.system(size: 40))
                    .foregroundColor(BCTheme.cyanAccent)
                    .padding(.bottom, 4)

                Text("Crear cuenta")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Regístrate de forma rápida y segura con tu cuenta de Google o Apple ID.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            VStack(spacing: 14) {
                Button {
                    BCFeedbackManager.shared.impactLight()
                    googleIsRegistration = true
                    showGoogleInputSheet = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "g.circle.fill")
                            .font(.title3)
                            .foregroundColor(.black)
                        Text("Continuar con Google")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                SignInWithAppleButton(.signUp) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleAppleAuthResult(result, isRegistration: true)
                }
                .signInWithAppleButtonStyle(.whiteOutline)
                .frame(height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 28)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(BCTheme.destructiveRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
        }
    }

    // MARK: - Edición de Datos Básicos (Nombre, Apellido, Correo)
    private var profileSetupStepView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Confirma tus datos")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Verifica o edita tu nombre y apellido tal como aparecerán en tu perfil.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.58))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nombre")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.65))
                    TextField("Ej: Aron", text: $viewModel.draftFirstName)
                        .textContentType(.givenName)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 50)
                        .background(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(BCTheme.hairlineBorder, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Apellido")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.65))
                    TextField("Ej: Quispe", text: $viewModel.draftLastName)
                        .textContentType(.familyName)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 50)
                        .background(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(BCTheme.hairlineBorder, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Correo")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.65))
                    TextField("correo@ejemplo.com", text: $viewModel.draftEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 14)
                        .frame(height: 50)
                        .background(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(BCTheme.hairlineBorder, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.horizontal, 28)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(BCTheme.destructiveRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Button {
                Task { await viewModel.saveProfileSetupAndContinue() }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                } else {
                    Text("Continuar")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
            }
            .background(BCTheme.emerald)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .disabled(viewModel.isLoading)
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Paso Celular (Inicio de Sesión o Vinculación Post-Registro)
    private var phoneInputStepView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(viewModel.isLinkingPhoneFlow ? "Vincula tu celular" : "Iniciar Sesión")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(
                    viewModel.isLinkingPhoneFlow
                    ? "Si desea hacer pagos dentro de la app o acceder a los beneficios como descuentos o promociones, registre su celular."
                    : "Ingresa tu número celular para recibir un código de verificación por WhatsApp o SMS."
                )
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)

            // Selector de canal: WhatsApp o SMS
            HStack(spacing: 10) {
                channelChip(id: "whatsapp", title: "WhatsApp", icon: "message.fill")
                channelChip(id: "sms", title: "SMS normal", icon: "bubble.left.fill")
            }
            .padding(.horizontal, 28)

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Text("🇵🇪")
                    Text("+51")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 14)
                .frame(height: 56)
                .background(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(BCTheme.hairlineBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                TextField("9XX XXX XXX", text: $viewModel.phoneNumber)
                    .keyboardType(.numberPad)
                    .focused($isPhoneFocused)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .background(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(viewModel.isValidPhone ? BCTheme.emerald : BCTheme.hairlineBorder, lineWidth: 1.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onChange(of: viewModel.phoneNumber) { _, newValue in
                        let digits = newValue.filter { $0.isNumber }
                        if digits.count > 9 {
                            viewModel.phoneNumber = String(digits.prefix(9))
                        } else if digits != newValue {
                            viewModel.phoneNumber = digits
                        }
                    }
            }
            .padding(.horizontal, 28)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(BCTheme.destructiveRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Button {
                Task { await viewModel.sendOtp() }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                } else {
                    Text(viewModel.otpChannel == "whatsapp" ? "Enviar código por WhatsApp" : "Enviar código por SMS")
                        .font(.body.weight(.semibold))
                        .foregroundColor(viewModel.isValidPhone ? .black : .white.opacity(0.35))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
            }
            .background(viewModel.isValidPhone ? BCTheme.emerald : Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .disabled(!viewModel.isValidPhone || viewModel.isLoading)
            .padding(.horizontal, 28)

            if viewModel.isLinkingPhoneFlow {
                Button {
                    viewModel.skipPhoneLinking()
                } label: {
                    Text("Omitir por ahora")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.75))
                        .padding(.vertical, 8)
                }
            } else {
                VStack(spacing: 10) {
                    Text("o continúa con tu cuenta")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.45))

                    HStack(spacing: 12) {
                        Button {
                            googleIsRegistration = false
                            showGoogleInputSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "g.circle.fill")
                                Text("Google")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            handleAppleAuthResult(result, isRegistration: false)
                        }
                        .signInWithAppleButtonStyle(.whiteOutline)
                        .frame(height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(.horizontal, 28)
                }
                .padding(.top, 4)
            }
        }
        .onAppear {
            isPhoneFocused = true
        }
    }

    // MARK: - Paso 3: Verificación OTP (6 Casillas)
    private var otpVerificationStepView: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text("Código de verificación")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(
                    viewModel.otpInfoMessage
                    ?? "Enviado por \(viewModel.otpChannel == "whatsapp" ? "WhatsApp" : "SMS") a +51 \(viewModel.phoneNumber)"
                )
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            ZStack {
                TextField("", text: $viewModel.otpCode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($isOtpFocused)
                    .opacity(0.01)
                    .onChange(of: viewModel.otpCode) { _, newValue in
                        let clean = newValue.filter { $0.isNumber }
                        if clean.count > 6 {
                            viewModel.otpCode = String(clean.prefix(6))
                        } else if clean != newValue {
                            viewModel.otpCode = clean
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
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .frame(width: 46, height: 56)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(
                                            isCurrent ? BCTheme.emerald : (char.isEmpty ? BCTheme.hairlineBorder : Color.white.opacity(0.35)),
                                            lineWidth: 1.5
                                        )
                                )

                            Text(char)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
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
                    .foregroundColor(BCTheme.destructiveRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            if viewModel.countdownSeconds > 0 {
                Text("Reenviar código en \(viewModel.countdownSeconds)s")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.45))
            } else {
                Button {
                    Task { await viewModel.sendOtp() }
                } label: {
                    Text("Reenviar código")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(BCTheme.emerald)
                }
            }

            Button {
                Task { await viewModel.verifyOtp() }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                } else {
                    Text("Continuar")
                        .font(.body.weight(.semibold))
                        .foregroundColor(viewModel.otpCode.count == 6 ? .black : .white.opacity(0.35))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
            }
            .background(viewModel.otpCode.count == 6 ? BCTheme.emerald : Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .disabled(viewModel.otpCode.count != 6 || viewModel.isLoading)
            .padding(.horizontal, 28)

            if viewModel.isLinkingPhoneFlow {
                Button {
                    viewModel.skipPhoneLinking()
                } label: {
                    Text("Omitir por ahora")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.75))
                }
            }
        }
        .onAppear {
            isOtpFocused = true
        }
    }

    // MARK: - Paso 4: Confirmación de Cuenta
    private var successStepView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(BCTheme.emerald.opacity(0.15))
                    .frame(width: 110, height: 110)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(BCTheme.emerald)
            }

            VStack(spacing: 8) {
                Text("¡Sesión verificada!")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                if let user = viewModel.currentUser {
                    Text(user.displayFullName)
                        .font(.headline)
                        .foregroundColor(BCTheme.emerald)

                    Text("\(user.roleType.badgeLabel) · Saldo: \(user.pointsBalance) pts")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    viewModel.completeOnboarding()
                }
            } label: {
                Text("Entrar a Bus Conectado")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(BCTheme.emerald)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 28)
        }
    }

    private func channelChip(id: String, title: String, icon: String) -> some View {
        let selected = viewModel.otpChannel == id
        return Button {
            BCFeedbackManager.shared.impactLight()
            viewModel.otpChannel = id
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(selected ? .black : .white.opacity(0.8))
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(selected ? BCTheme.emerald : Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? BCTheme.emerald : BCTheme.hairlineBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Sheet de Google Sign-In
    private var googleSignInSheet: some View {
        NavigationStack {
            ZStack {
                BCTheme.elevatedSurface.ignoresSafeArea()
                VStack(spacing: 14) {
                    Text("Ingresa los datos de tu cuenta Google para continuar.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.65))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    TextField("Nombre", text: $googleNameInput)
                        .foregroundColor(.white)
                        .padding(14)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    TextField("Apellido", text: $googleLastNameInput)
                        .foregroundColor(.white)
                        .padding(14)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    TextField("Correo Google (@gmail.com)", text: $googleEmailInput)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .foregroundColor(.white)
                        .padding(14)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Button {
                        let mail = googleEmailInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        let fname = googleNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        let lname = googleLastNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        showGoogleInputSheet = false
                        Task {
                            await viewModel.signInWithSocial(
                                provider: "google",
                                providerUserId: mail.isEmpty ? UUID().uuidString : mail,
                                email: mail,
                                firstName: fname,
                                lastName: lname,
                                isRegistration: googleIsRegistration
                            )
                        }
                    } label: {
                        Text("Continuar con Google")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(googleEmailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.top, 6)

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Cuenta Google")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancelar") { showGoogleInputSheet = false }
                        .foregroundColor(.white)
                }
            }
        }
    }

    private func handleAppleAuthResult(_ result: Result<ASAuthorization, Error>, isRegistration: Bool) {
        switch result {
        case .success(let auth):
            if let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                let uid = credential.user
                let email = credential.email ?? ""
                let first = credential.fullName?.givenName ?? ""
                let last = credential.fullName?.familyName ?? ""
                Task {
                    await viewModel.signInWithSocial(
                        provider: "apple",
                        providerUserId: uid,
                        email: email,
                        firstName: first,
                        lastName: last,
                        isRegistration: isRegistration
                    )
                }
            }
        case .failure(let error):
            viewModel.errorMessage = "No se pudo autenticar con Apple ID: \(error.localizedDescription)"
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

// MARK: - Sheet Modal para Vincular Celular desde PayQR / Monedero / Perfil
struct PhoneLinkSheetView: View {
    @ObservedObject var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                BCTheme.background.ignoresSafeArea()
                VStack(spacing: 20) {
                    if viewModel.currentStep == .otpVerification {
                        Text("Código de verificación")
                            .font(.title2.weight(.bold))
                            .foregroundColor(.white)

                        Text(
                            viewModel.otpInfoMessage
                            ?? "Enviado por \(viewModel.otpChannel == "whatsapp" ? "WhatsApp" : "SMS") a +51 \(viewModel.phoneNumber)"
                        )
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.65))
                        .multilineTextAlignment(.center)

                        TextField("000000", text: $viewModel.otpCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(height: 56)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .onChange(of: viewModel.otpCode) { _, val in
                                let clean = String(val.filter { $0.isNumber }.prefix(6))
                                if clean != val { viewModel.otpCode = clean }
                            }

                        if let err = viewModel.errorMessage {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(BCTheme.destructiveRed)
                                .multilineTextAlignment(.center)
                        }

                        Button {
                            Task { await viewModel.verifyOtp() }
                        } label: {
                            Text("Verificar y vincular")
                                .font(.body.weight(.semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(BCTheme.emerald)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(viewModel.otpCode.count != 6 || viewModel.isLoading)
                    } else {
                        Text("Vincular número celular")
                            .font(.title2.weight(.bold))
                            .foregroundColor(.white)

                        Text("Si desea hacer pagos dentro de la app o acceder a los beneficios como descuentos o promociones, registre su celular.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.65))
                            .multilineTextAlignment(.center)

                        HStack(spacing: 10) {
                            ForEach([("whatsapp", "WhatsApp"), ("sms", "SMS normal")], id: \.0) { id, label in
                                let selected = viewModel.otpChannel == id
                                Button {
                                    viewModel.otpChannel = id
                                } label: {
                                    Text(label)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(selected ? .black : .white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 42)
                                        .background(selected ? BCTheme.emerald : Color.white.opacity(0.08))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }

                        HStack(spacing: 10) {
                            Text("🇵🇪 +51")
                                .font(.body.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .frame(height: 54)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            TextField("9XX XXX XXX", text: $viewModel.phoneNumber)
                                .keyboardType(.numberPad)
                                .font(.title3.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .frame(height: 54)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .onChange(of: viewModel.phoneNumber) { _, val in
                                    let clean = String(val.filter { $0.isNumber }.prefix(9))
                                    if clean != val { viewModel.phoneNumber = clean }
                                }
                        }

                        if let err = viewModel.errorMessage {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(BCTheme.destructiveRed)
                                .multilineTextAlignment(.center)
                        }

                        Button {
                            Task { await viewModel.sendOtp() }
                        } label: {
                            Text("Enviar código")
                                .font(.body.weight(.semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(viewModel.isValidPhone ? BCTheme.emerald : Color.white.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(!viewModel.isValidPhone || viewModel.isLoading)
                    }

                    Spacer()
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") {
                        viewModel.showPhoneLinkSheet = false
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

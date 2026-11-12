import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: AuthViewModel
    @FocusState private var isPhoneFocused: Bool
    @FocusState private var isOtpFocused: Bool
    @State private var showTestAccountsSheet: Bool = false

    var body: some View {
        ZStack {
            BCTheme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Barra superior minimalista
                HStack {
                    if viewModel.currentStep != .splash && viewModel.currentStep != .success {
                        Button {
                            BCFeedbackManager.shared.impactLight()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                viewModel.errorMessage = nil
                                viewModel.currentStep = viewModel.currentStep == .otpVerification ? .phoneInput : .splash
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

                    if viewModel.currentStep != .success {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                viewModel.continueAsGuest()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("Modo Invitado")
                                    .font(.footnote.weight(.medium))
                                Image(systemName: "arrow.right")
                                    .font(.caption2.weight(.semibold))
                            }
                            .foregroundColor(BCTheme.royalBlue)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(BCTheme.royalBlue.opacity(0.14))
                            .overlay(
                                Capsule()
                                    .stroke(BCTheme.royalBlue.opacity(0.35), lineWidth: 1)
                            )
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                Spacer()

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

                // Acceso discreto a Cuentas de Prueba (Modo Dev)
                if viewModel.currentStep == .splash || viewModel.currentStep == .phoneInput {
                    Button {
                        BCFeedbackManager.shared.impactLight()
                        showTestAccountsSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.badge.key.fill")
                                .font(.caption)
                                .foregroundColor(BCTheme.emerald)
                            Text("Cuentas de Prueba (Modo Dev)")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white.opacity(0.75))
                            Image(systemName: "chevron.up")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.05))
                        .overlay(
                            Capsule()
                                .stroke(BCTheme.hairlineBorder, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .sheet(isPresented: $showTestAccountsSheet) {
            testAccountsPickerSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Paso 1: Splash (Fiel al Mockup y Apple HIG)
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
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        viewModel.currentStep = .phoneInput
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "phone.fill")
                            .font(.subheadline)
                        Text("Iniciar Sesión / Registrarse")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundColor(Color(red: 4/255, green: 18/255, blue: 12/255))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(BCTheme.emerald)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        viewModel.continueAsGuest()
                    }
                } label: {
                    Text("Explorar sin registrarse")
                        .font(.body.weight(.medium))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(BCTheme.hairlineBorder, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Text("Al continuar aceptas los Términos y Privacidad de BC")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Paso 2: Ingreso de Celular (+51)
    private var phoneInputStepView: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text("Ingresa tu celular")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Recibirás un código de 6 dígitos para validar tu sesión única en este iPhone.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

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

                TextField("952 000 002", text: $viewModel.phoneNumber)
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
                Task {
                    await viewModel.sendOtp()
                }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                } else {
                    Text("Enviar código SMS")
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

                Text("Enviado a +51 \(viewModel.phoneNumber) · (Demo: 123456)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.55))
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

            Button {
                viewModel.otpCode = "123456"
            } label: {
                Text("Autocompletar código demo (123456)")
                    .font(.caption.weight(.medium))
                    .foregroundColor(BCTheme.cyanAccent)
            }

            if viewModel.countdownSeconds > 0 {
                Text("Reenviar código en \(viewModel.countdownSeconds)s")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.45))
            } else {
                Button {
                    Task { await viewModel.sendOtp() }
                } label: {
                    Text("Reenviar código SMS")
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
                    Text("Verificar y continuar")
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
                    Text(user.name ?? "Pasajero BC")
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

    // MARK: - Hoja de Selección de Cuentas de Prueba (Modo Dev)
    private var testAccountsPickerSheet: some View {
        NavigationStack {
            ZStack {
                BCTheme.elevatedSurface.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Selecciona un perfil de prueba para iniciar sesión con 1 toque. Todas las cuentas de prueba inician con 0 Puntos BC, 0 movimientos y sin paraderos ni buses simulados en el mapa.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        ForEach(TestAccountPreset.officialPresets) { preset in
                            Button {
                                showTestAccountsSheet = false
                                Task {
                                    await viewModel.selectTestAccount(preset)
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle()
                                            .fill(preset.role == .student ? BCTheme.amber.opacity(0.18) : (preset.role == .conadis ? BCTheme.cyanAccent.opacity(0.18) : BCTheme.royalBlue.opacity(0.18)))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: preset.role.iconName)
                                            .font(.headline)
                                            .foregroundColor(preset.role == .student ? BCTheme.amber : (preset.role == .conadis ? BCTheme.cyanAccent : BCTheme.royalBlue))
                                    }

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(preset.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundColor(.white)
                                            Text(preset.formattedPhone)
                                                .font(.caption2.monospaced())
                                                .foregroundColor(.white.opacity(0.5))
                                        }
                                        Text(preset.subtitle)
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.65))
                                            .multilineTextAlignment(.leading)
                                    }

                                    Spacer()

                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(BCTheme.emerald)
                                }
                                .padding(14)
                                .background(Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(BCTheme.hairlineBorder, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Cuentas de Prueba")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") {
                        showTestAccountsSheet = false
                    }
                    .foregroundColor(.white)
                }
            }
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

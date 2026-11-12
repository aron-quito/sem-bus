import SwiftUI

struct ProfileSheetView: View {
    @ObservedObject var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var hostInput: String = ""
    @State private var showDeleteAccountAlert: Bool = false
    @State private var showCarnetReviewSheet: Bool = false
    @State private var showHelpSheet: Bool = false
    @State private var isDeveloperSectionExpanded: Bool = false

    // Estado del formulario de Solicitud de Revisión de Carné
    @State private var carnetType: String = "STUDENT"
    @State private var dniInput: String = ""
    @State private var institutionInput: String = "UNJBG - Universidad Nacional Jorge Basadre"
    @State private var documentCodeInput: String = ""
    @State private var expiryDateInput: Date = Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 31)) ?? Date().addingTimeInterval(86400 * 180)

    var body: some View {
        NavigationStack {
            ZStack {
                BCTheme.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        // 1. Cabecera de Identidad del Pasajero
                        profileHeaderCard

                        // 2. Estado y Caducidad de Carné + Solicitud de Revisión
                        if viewModel.isLoggedIn {
                            carnetStatusSection
                        }

                        // 3. Monedero BC y Acceso Rápido
                        if let user = viewModel.currentUser {
                            walletQuickCard(user: user)
                        }

                        // 4. Ayuda y Soporte al Pasajero
                        helpAndSupportSection

                        // 5. Sesión / Registro de Invitado
                        accountSessionSection

                        // 6. Opciones Avanzadas / Servidor (colapsado por defecto para vista limpia de producción)
                        advancedDeveloperSection
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Mi Cuenta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
            }
            .alert("¿Eliminar tu cuenta?", isPresented: $showDeleteAccountAlert) {
                Button("Eliminar", role: .destructive) {
                    Task {
                        await viewModel.logout()
                        dismiss()
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Esta acción desvinculará tu sesión y limpiará tus datos locales en este dispositivo.")
            }
            .sheet(isPresented: $showCarnetReviewSheet) {
                carnetReviewModalSheet
            }
            .sheet(isPresented: $showHelpSheet) {
                helpCenterModalSheet
            }
            .onAppear {
                hostInput = viewModel.backendHost
            }
        }
    }

    // MARK: - 1. Cabecera de Usuario
    private var profileHeaderCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [BCTheme.royalBlue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 62, height: 62)

                Text(userInitial)
                    .font(.title.weight(.bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(viewModel.currentUser?.name ?? (viewModel.isGuestMode ? "Modo Invitado" : "Pasajero BC"))
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if viewModel.isLoggedIn {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.subheadline)
                            .foregroundColor(BCTheme.emerald)
                    }
                }

                if let phone = viewModel.currentUser?.phone {
                    Text(phone)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.68))
                }

                if let user = viewModel.currentUser {
                    Text(user.roleType.badgeLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(roleAccentColor(for: user.roleType))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(roleAccentColor(for: user.roleType).opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            Spacer()
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BCTheme.hairlineBorder, lineWidth: 1))
    }

    // MARK: - 2. Carné, Tiempo de Caducidad y Petición de Revisión
    @ViewBuilder
    private var carnetStatusSection: some View {
        let role = viewModel.currentUser?.roleType ?? .adult

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("CARNÉ Y BENEFICIO TARIFARIO", systemImage: "person.text.rectangle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white.opacity(0.65))
                Spacer()
            }

            if role == .student, let sv = viewModel.currentUser?.studentVerification {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(BCTheme.amber.opacity(0.18))
                                .frame(width: 42, height: 42)
                            Image(systemName: "graduationcap.fill")
                                .foregroundColor(BCTheme.amber)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Carné Universitario SUNEDU")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.white)
                            Text(sv.university)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        Spacer()
                        Text("VIGENTE")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(BCTheme.emerald)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(BCTheme.emerald.opacity(0.16))
                            .clipShape(Capsule())
                    }

                    Divider().background(Color.white.opacity(0.1))

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TIEMPO DE CADUCIDAD")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.5))
                            Text("Vence el \(StudentVerificationInfo.formattedExpirationDate(sv.expiresAt))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                        }
                        Spacer()
                        if let days = sv.daysRemaining {
                            Text(days >= 0 ? "\(days) días restantes" : "Vencido")
                                .font(.caption.weight(.bold))
                                .foregroundColor(days <= 30 ? BCTheme.destructiveRed : BCTheme.amber)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background((days <= 30 ? BCTheme.destructiveRed : BCTheme.amber).opacity(0.16))
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 12) {
                        Text("DNI: \(sv.dni)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.65))
                        if let cycle = sv.academicCycle {
                            Text("· Ciclo \(cycle)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.65))
                        }
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BCTheme.amber.opacity(0.4), lineWidth: 1))
            } else if role == .conadis {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(BCTheme.cyanAccent.opacity(0.18))
                                .frame(width: 42, height: 42)
                            Image(systemName: "figure.roll")
                                .foregroundColor(BCTheme.cyanAccent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pase Libre CONADIS")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.white)
                            Text("Ley N° 30412 · Tarifa exonerada (0 pts)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.68))
                        }
                        Spacer()
                        Text("ACTIVO")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(BCTheme.cyanAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(BCTheme.cyanAccent.opacity(0.16))
                            .clipShape(Capsule())
                    }
                    Text("Vigencia permanente sujeta a padrón CONADIS vigente.")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(16)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BCTheme.cyanAccent.opacity(0.35), lineWidth: 1))
            } else if let pending = viewModel.carnetReviewRequest {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(BCTheme.cyanAccent.opacity(0.18))
                                .frame(width: 42, height: 42)
                            Image(systemName: "clock.badge.checkmark.fill")
                                .foregroundColor(BCTheme.cyanAccent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pending.carnetTypeDisplay)
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.white)
                            Text("Petición #\(pending.id) · DNI \(pending.dni)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.68))
                        }
                        Spacer()
                        Text(pending.statusDisplay.uppercased())
                            .font(.system(size: 9.5, weight: .black))
                            .foregroundColor(BCTheme.amber)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(BCTheme.amber.opacity(0.18))
                            .clipShape(Capsule())
                    }

                    Divider().background(Color.white.opacity(0.1))

                    HStack {
                        Text("Caducidad declarada: \(StudentVerificationInfo.formattedExpirationDate(pending.expiresAt))")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.75))
                        Spacer()
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BCTheme.cyanAccent.opacity(0.35), lineWidth: 1))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 42, height: 42)
                            Image(systemName: "person.text.rectangle")
                                .foregroundColor(.white.opacity(0.75))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sin carné acreditado")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.white)
                            Text("Actualmente usas Tarifa General (15 pts). Solicita revisión para medio pasaje universitario o pase libre CONADIS.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.65))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Button {
                        BCFeedbackManager.shared.impactLight()
                        showCarnetReviewSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.badge.plus")
                                .font(.subheadline.weight(.bold))
                            Text("Solicitar Revisión de Carné")
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(BCTheme.amber)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BCTheme.hairlineBorder, lineWidth: 1))
            }
        }
    }

    // MARK: - 3. Tarjeta de Monedero
    private func walletQuickCard(user: UserAuth) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("MONEDERO BC", systemImage: "wallet.pass.fill")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white.opacity(0.65))
                Spacer()
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(user.pointsBalance) Puntos BC")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white)
                    Text(String(format: "Equivalente: S/. %.2f · %d movimientos", user.balancePen, viewModel.transactions.count))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.65))
                }
                Spacer()
                Button {
                    dismiss()
                    viewModel.selectedTab = 3
                } label: {
                    Text("Abrir Monedero")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(BCTheme.royalBlue)
                        .clipShape(Capsule())
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BCTheme.hairlineBorder, lineWidth: 1))
        }
    }

    // MARK: - 4. Ayuda y Soporte
    private var helpAndSupportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AYUDA Y SOPORTE", systemImage: "questionmark.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundColor(.white.opacity(0.65))

            VStack(spacing: 0) {
                Button {
                    BCFeedbackManager.shared.impactLight()
                    showHelpSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "lifepreserver.fill")
                            .foregroundColor(BCTheme.cyanAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Centro de Ayuda y Preguntas Frecuentes")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                            Text("Pago QR, recargas Yape/Plin, vigencia de carné y tarifas")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(14)
                }

                Divider().background(BCTheme.hairlineBorder)

                HStack(spacing: 12) {
                    Image(systemName: "envelope.badge.shield.half.filled")
                        .foregroundColor(BCTheme.emerald)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Atención al Pasajero Tacna")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                        Text("soporte@busconectado.pe · Lunes a Domingo 06:00 - 22:00")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    Spacer()
                }
                .padding(14)
            }
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BCTheme.hairlineBorder, lineWidth: 1))
        }
    }

    // MARK: - 5. Sesión y Eliminación
    private var accountSessionSection: some View {
        VStack(spacing: 10) {
            if viewModel.isLoggedIn {
                Button {
                    Task {
                        await viewModel.logout()
                        dismiss()
                    }
                } label: {
                    Label("Cerrar Sesión", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(BCTheme.destructiveRed)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(BCTheme.destructiveRed.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Button {
                    showDeleteAccountAlert = true
                } label: {
                    Text("Eliminar Cuenta")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.48))
                        .padding(.vertical, 6)
                }
            } else {
                Button {
                    dismiss()
                    viewModel.isGuestMode = false
                    viewModel.currentStep = .splash
                } label: {
                    Text("Crear Cuenta o Iniciar Sesión")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(BCTheme.emerald)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    // MARK: - 6. Ajustes Avanzados (Servidor)
    private var advancedDeveloperSection: some View {
        DisclosureGroup(
            isExpanded: $isDeveloperSectionExpanded,
            content: {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Host del backend (Producción / Local)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))

                    HStack(spacing: 8) {
                        TextField("Ej. 34.44.71.179.sslip.io", text: $hostInput)
                            .font(.caption)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 10)
                            .frame(height: 40)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .foregroundColor(.white)

                        Button {
                            viewModel.updateBackendHost(hostInput)
                        } label: {
                            Text("Guardar")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .frame(height: 40)
                                .background(BCTheme.emerald)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    if viewModel.isLoggedIn {
                        Button {
                            viewModel.resetCurrentAccountState()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.counterclockwise.circle")
                                Text("Reiniciar Saldo de Prueba a S/. 0.00")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundColor(BCTheme.cyanAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(BCTheme.cyanAccent.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(.top, 10)
            },
            label: {
                Label("Ajustes Avanzados de Conexión", systemImage: "gearshape.2")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.55))
            }
        )
        .padding(14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(BCTheme.hairlineBorder, lineWidth: 1))
    }

    // MARK: - Sheet de Solicitud de Revisión de Carné
    private var carnetReviewModalSheet: some View {
        NavigationStack {
            ZStack {
                BCTheme.elevatedSurface.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Envía tu solicitud para habilitar la tarifa reducida. Revisaremos la vigencia en el padrón oficial.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.75))

                        Picker("Tipo de carné", selection: $carnetType) {
                            Text("Universitario SUNEDU (7 pts)").tag("STUDENT")
                            Text("Pase Libre CONADIS (0 pts)").tag("CONADIS")
                        }
                        .pickerStyle(.segmented)

                        VStack(spacing: 10) {
                            TextField("DNI (8 dígitos)", text: $dniInput)
                                .keyboardType(.numberPad)
                                .padding(14)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundColor(.white)

                            TextField(
                                carnetType == "STUDENT" ? "Universidad / Instituto" : "N° Resolución CONADIS",
                                text: $institutionInput
                            )
                            .padding(14)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .foregroundColor(.white)

                            TextField(
                                carnetType == "STUDENT" ? "Código de Carné Universitario" : "Código de Registro CONADIS",
                                text: $documentCodeInput
                            )
                            .padding(14)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .foregroundColor(.white)

                            DatePicker("Fecha de caducidad", selection: $expiryDateInput, displayedComponents: .date)
                                .tint(BCTheme.amber)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button {
                            let df = DateFormatter()
                            df.dateFormat = "yyyy-MM-dd"
                            let cleanDni = dniInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            let cleanCode = documentCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            viewModel.submitCarnetReviewRequest(
                                type: carnetType,
                                dni: cleanDni.isEmpty ? "74829103" : cleanDni,
                                institution: institutionInput,
                                documentCode: cleanCode.isEmpty ? "SUN-2026-0842" : cleanCode,
                                expiresAt: df.string(from: expiryDateInput)
                            )
                            showCarnetReviewSheet = false
                        } label: {
                            Label("Enviar Petición de Revisión", systemImage: "paperplane.fill")
                                .font(.headline)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(BCTheme.amber)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Solicitud de Carné")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { showCarnetReviewSheet = false }
                        .foregroundColor(.white.opacity(0.75))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Sheet de Centro de Ayuda
    private var helpCenterModalSheet: some View {
        NavigationStack {
            ZStack {
                BCTheme.elevatedSurface.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        helpFaqItem(
                            q: "¿Cómo pago mi pasaje en el bus con QR?",
                            a: "Abre la pestaña 'Pagar QR' al subir a una ruta ordinaria autorizada, escanea el código de la unidad e indica si viajas con acompañantes. El débito en puntos es instantáneo."
                        )
                        helpFaqItem(
                            q: "¿Cómo acredito mi Carné Universitario o CONADIS?",
                            a: "En 'Mi Cuenta' o en 'Monedero' selecciona 'Solicitar Revisión de Carné', ingresa tu DNI, código de carné y fecha de vencimiento. Mientras se aprueba verás el estado en tiempo real."
                        )
                        helpFaqItem(
                            q: "¿Cómo funciona la recarga con Yape, Plin o Tarjeta?",
                            a: "1 PEN equivale a 10 Puntos BC. En la pasarela de recarga eliges tu monto, método de pago y al confirmar obtienes un comprobante inmediato reflejado en tu historial."
                        )
                        helpFaqItem(
                            q: "¿Cuáles son las tarifas vigentes en Tacna?",
                            a: "Pasajero Adulto: 15 pts (S/. 1.50) · Universitario SUNEDU vigente: 7 pts (S/. 0.70) · Pase Libre CONADIS: 0 pts (S/. 0.00)."
                        )
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Centro de Ayuda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { showHelpSheet = false }
                        .foregroundColor(.white.opacity(0.75))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func helpFaqItem(q: String, a: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(q)
                .font(.subheadline.weight(.bold))
                .foregroundColor(.white)
            Text(a)
                .font(.caption)
                .foregroundColor(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(BCTheme.hairlineBorder, lineWidth: 1))
    }

    private func roleAccentColor(for role: UserRoleType) -> Color {
        switch role {
        case .student: return BCTheme.amber
        case .conadis: return BCTheme.cyanAccent
        default: return BCTheme.emerald
        }
    }

    private var userInitial: String {
        if let name = viewModel.currentUser?.name, let first = name.first {
            return String(first).uppercased()
        }
        return viewModel.isGuestMode ? "I" : "P"
    }
}

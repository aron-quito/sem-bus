import SwiftUI

struct ProfileSheetView: View {
    @ObservedObject var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var hostInput: String = ""
    @State private var showDeleteAccountAlert: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                BCTheme.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // 1. Identidad Estilo Google Account (#modal-google-profile)
                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [BCTheme.royalBlue, Color.purple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 76, height: 76)

                                Text(userInitial)
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }

                            Text(viewModel.currentUser?.name ?? (viewModel.isGuestMode ? "Modo Invitado" : "Pasajero BC"))
                                .font(.title3.weight(.bold))
                                .foregroundColor(.white)

                            if let phone = viewModel.currentUser?.phone {
                                Text(phone)
                                    .font(.subheadline.monospaced())
                                    .foregroundColor(.white.opacity(0.6))
                            }

                            if let user = viewModel.currentUser {
                                HStack(spacing: 6) {
                                    Image(systemName: user.roleType.iconName)
                                    Text(user.roleType.displayName)
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundColor(user.roleType == .student ? BCTheme.amber : BCTheme.emerald)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background((user.roleType == .student ? BCTheme.amber : BCTheme.emerald).opacity(0.14))
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.top, 12)

                        // 2. Resumen Rápido de Monedero
                        if let user = viewModel.currentUser {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("SALDO DISPONIBLE")
                                        .font(.caption2.weight(.bold))
                                        .foregroundColor(.white.opacity(0.5))
                                    Text("\(user.pointsBalance) Puntos BC (\(String(format: "S/. %.2f", user.balancePen)))")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundColor(.white)
                                }

                                Spacer()

                                Button {
                                    viewModel.selectedTab = 3
                                    dismiss()
                                } label: {
                                    Text("Ver Monedero")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(BCTheme.royalBlue)
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(16)
                            .background(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(BCTheme.hairlineBorder, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .padding(.horizontal, 20)
                        }

                        // 3. Herramientas de Cuenta de Prueba y Conexión Backend
                        VStack(alignment: .leading, spacing: 10) {
                            Text("ENTORNO DE PRUEBAS & SERVIDOR")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.white.opacity(0.45))
                                .padding(.horizontal, 4)

                            HStack(spacing: 8) {
                                TextField("IP Mac (ej. 192.168.1.15:8000)", text: $hostInput)
                                    .font(.caption.monospaced())
                                    .foregroundColor(.white)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)

                                Button("Guardar") {
                                    viewModel.updateBackendHost(hostInput)
                                }
                                .font(.caption.weight(.bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(BCTheme.emerald)
                                .clipShape(Capsule())
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            if viewModel.isLoggedIn {
                                Button {
                                    viewModel.resetCurrentAccountState()
                                } label: {
                                    HStack {
                                        Image(systemName: "arrow.counterclockwise")
                                        Text("Restablecer cuenta de prueba a 0 pts y 0 viajes")
                                        Spacer()
                                    }
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(BCTheme.cyanAccent)
                                    .padding(12)
                                    .background(Color.white.opacity(0.04))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        // 4. Acciones de Sesión y Baja de Cuenta (CU-11)
                        VStack(spacing: 10) {
                            if viewModel.isLoggedIn {
                                Button(role: .destructive) {
                                    Task {
                                        await viewModel.logout()
                                        dismiss()
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "rectangle.portrait.and.arrow.right")
                                        Text("Cerrar Sesión")
                                            .fontWeight(.semibold)
                                    }
                                    .foregroundColor(BCTheme.destructiveRed)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(BCTheme.destructiveRed.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }

                                Button {
                                    showDeleteAccountAlert = true
                                } label: {
                                    Text("Solicitar eliminación de cuenta (CU-11)")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.4))
                                        .padding(.top, 4)
                                }
                            } else {
                                Button {
                                    withAnimation {
                                        viewModel.isGuestMode = false
                                        viewModel.currentStep = .splash
                                        dismiss()
                                    }
                                } label: {
                                    Text("Iniciar Sesión / Registrarse")
                                        .fontWeight(.semibold)
                                        .foregroundColor(.black)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 50)
                                        .background(BCTheme.emerald)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Cuenta BC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .alert("Eliminar Cuenta (CU-11)", isPresented: $showDeleteAccountAlert) {
                Button("Confirmar Baja y Cerrar Sesión", role: .destructive) {
                    Task {
                        await viewModel.logout()
                        dismiss()
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Tu cuenta entrará en un período de gracia de 15 días conforme a la política de Bus Conectado antes de su purga definitiva.")
            }
            .onAppear {
                hostInput = viewModel.backendHost
            }
        }
    }

    private var userInitial: String {
        if let name = viewModel.currentUser?.name, let first = name.first {
            return String(first).uppercased()
        }
        return viewModel.isGuestMode ? "I" : "P"
    }
}

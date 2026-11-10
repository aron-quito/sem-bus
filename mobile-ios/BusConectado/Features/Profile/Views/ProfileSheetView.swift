import SwiftUI

struct ProfileSheetView: View {
    @ObservedObject var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var hostInput: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 11/255, green: 17/255, blue: 30/255)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    // Avatar e Información
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 80, height: 80)

                            Text(userInitial)
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }

                        Text(viewModel.currentUser?.name ?? (viewModel.isGuestMode ? "Modo Invitado" : "Pasajero BC"))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        if let phone = viewModel.currentUser?.phone {
                            Text(phone)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }

                        // Badge de Rol / Tarifa
                        HStack(spacing: 6) {
                            Image(systemName: "graduationcap.fill")
                            Text(viewModel.currentUser?.role == "STUDENT" ? "Tarifa Universitaria (7 pts)" : "Tarifa General (15 pts)")
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.amber)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.amber.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .padding(.top, 16)

                    Divider()
                        .background(Color.white.opacity(0.1))

                    // Configuración de Servidor Backend (Para pruebas físicas con iPhone)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CONEXIÓN DE BACKEND (PRUEBAS IPHONE)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.gray)

                        HStack {
                            TextField("192.168.1.X:8000 o ngrok", text: $hostInput)
                                .foregroundColor(.white)
                                .font(.subheadline)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)

                            Button("Guardar") {
                                viewModel.updateBackendHost(hostInput)
                            }
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.emerald)
                            .clipShape(Capsule())
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Text("Servidor actual: \(viewModel.backendHost)")
                            .font(.caption2)
                            .foregroundColor(.cyan.opacity(0.8))
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    // Botón Cerrar Sesión
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
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.red.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 24)
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
                                .frame(height: 52)
                                .background(Color.emerald)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Mi Perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
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
        return "P"
    }
}

extension Color {
    static let amber = Color(red: 245/255, green: 158/255, blue: 11/255)
}

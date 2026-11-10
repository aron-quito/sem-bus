import SwiftUI

struct MainTabView: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var showProfileSheet: Bool = false

    var body: some View {
        ZStack {
            BCTheme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Barra Superior Minimalista Estilo Google Maps / Apple HIG
                topNavigationHeader

                // TabView Principal de 4 Pestañas (Fiel al Mockup)
                TabView(selection: $viewModel.selectedTab) {
                    ExploreMapView(viewModel: viewModel)
                        .tabItem {
                            Label("Explorar", systemImage: "globe.americas.fill")
                        }
                        .tag(0)

                    LinesView(viewModel: viewModel)
                        .tabItem {
                            Label("Líneas", systemImage: "bus.fill")
                        }
                        .tag(1)

                    PayQrView(viewModel: viewModel)
                        .tabItem {
                            Label("Pagar QR", systemImage: "qrcode.viewfinder")
                        }
                        .tag(2)

                    WalletView(viewModel: viewModel)
                        .tabItem {
                            Label("Monedero", systemImage: "wallet.pass.fill")
                        }
                        .tag(3)
                }
                .tint(BCTheme.royalBlue)
            }

            // Overlay de Viaje en Curso (CU-06 In-Trip Sheet Minimizable)
            if let trip = viewModel.activeTrip {
                inTripFloatingOverlay(trip)
            }
        }
        .sheet(isPresented: $showProfileSheet) {
            ProfileSheetView(viewModel: viewModel)
        }
        .alert("Saldo Insuficiente", isPresented: $viewModel.showInsufficientBalanceModal) {
            Button("Ir a Recargar Monedero") {
                viewModel.selectedTab = 3
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            let current = viewModel.currentUser?.pointsBalance ?? 0
            Text("Tu saldo actual es de \(current) pts y necesitas \(viewModel.requiredPointsForAttempt) pts para este abordaje. Recarga al instante con Yape o Plin.")
        }
    }

    // MARK: - Header Superior con Buscador en Explorar y Avatar de Perfil
    private var topNavigationHeader: some View {
        HStack(spacing: 10) {
            if viewModel.selectedTab == 0 {
                // Píldora de Búsqueda estilo Mockup en Pestaña Explorar
                HStack(spacing: 10) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title3)
                        .foregroundColor(BCTheme.royalBlue)

                    TextField("Buscar paradero o línea en Tacna...", text: $viewModel.searchQuery)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .autocorrectionDisabled()

                    if !viewModel.searchQuery.isEmpty {
                        Button {
                            viewModel.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Color.white.opacity(0.06))
                .overlay(
                    Capsule()
                        .stroke(BCTheme.hairlineBorder, lineWidth: 1)
                )
                .clipShape(Capsule())
            } else {
                // Header Limpio en Líneas, Pagar QR y Monedero
                HStack(spacing: 8) {
                    Image(systemName: "bus.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(BCTheme.royalBlue)

                    Text("Bus Conectado")
                        .font(.headline.weight(.bold))
                        .foregroundColor(.white)
                }

                Spacer()

                if let user = viewModel.currentUser {
                    Button {
                        viewModel.selectedTab = 3
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "wallet.pass.fill")
                                .font(.caption2)
                                .foregroundColor(BCTheme.emerald)
                            Text("\(user.pointsBalance) pts")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Capsule())
                    }
                }
            }

            // Botón Circular de Perfil Estilo Google (#modal-google-profile)
            Button {
                BCFeedbackManager.shared.impactLight()
                showProfileSheet = true
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [BCTheme.royalBlue, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)

                    Text(userInitial)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(BCTheme.background)
    }

    // MARK: - Hoja Flotante de Viaje en Curso (CU-06)
    private func inTripFloatingOverlay(_ trip: ActiveTripState) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(BCTheme.emerald.opacity(0.2))
                        .frame(width: 40, height: 40)
                    Image(systemName: "bus.fill")
                        .foregroundColor(BCTheme.emerald)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("En viaje · \(trip.busUnit)")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                        Text(trip.busPlate)
                            .font(.caption2.monospaced())
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text("Cobrado: -\(trip.totalPointsDebited) pts · Alarma 400m activa")
                        .font(.caption2)
                        .foregroundColor(BCTheme.emerald)
                }

                Spacer()

                Button {
                    withAnimation {
                        viewModel.finishActiveTrip()
                    }
                } label: {
                    Text("Bajar")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(BCTheme.destructiveRed.opacity(0.85))
                        .clipShape(Capsule())
                }
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(BCTheme.emerald.opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 64)
        }
    }

    private var userInitial: String {
        if let name = viewModel.currentUser?.name, let first = name.first {
            return String(first).uppercased()
        }
        return viewModel.isGuestMode ? "I" : "P"
    }
}

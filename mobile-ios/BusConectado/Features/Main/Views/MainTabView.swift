import SwiftUI

struct MainTabView: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var selectedTab: Int = 0
    @State private var showProfileSheet: Bool = false

    var body: some View {
        ZStack {
            Color(red: 11/255, green: 17/255, blue: 30/255)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header Superior Global
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "bus.fill")
                            .font(.headline)
                            .foregroundColor(.blue)

                        Text("Bus Conectado")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }

                    Spacer()

                    // Píldora de Saldo Rápido
                    HStack(spacing: 6) {
                        Image(systemName: "wallet.pass.fill")
                            .font(.caption2)
                            .foregroundColor(.emerald)

                        Text("\(viewModel.currentUser?.pointsBalance ?? (viewModel.isGuestMode ? 0 : 42)) pts")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())

                    // Botón de Perfil
                    Button {
                        showProfileSheet = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 34, height: 34)

                            Text(userInitial)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(red: 11/255, green: 17/255, blue: 30/255))

                // Contenido de Tabs
                TabView(selection: $selectedTab) {
                    ExploreMapView()
                        .tabItem {
                            Label("Explorar", systemImage: "globe.americas.fill")
                        }
                        .tag(0)

                    LinesView()
                        .tabItem {
                            Label("Líneas", systemImage: "bus.doubledecker.fill")
                        }
                        .tag(1)

                    PayQrView(viewModel: viewModel)
                        .tabItem {
                            Label("Pagar QR", systemImage: "qrcode")
                        }
                        .tag(2)

                    WalletView(viewModel: viewModel)
                        .tabItem {
                            Label("Monedero", systemImage: "wallet.pass.fill")
                        }
                        .tag(3)
                }
                .tint(.emerald)
            }
        }
        .sheet(isPresented: $showProfileSheet) {
            ProfileSheetView(viewModel: viewModel)
        }
    }

    private var userInitial: String {
        if let name = viewModel.currentUser?.name, let first = name.first {
            return String(first).uppercased()
        }
        return viewModel.isGuestMode ? "?" : "P"
    }
}

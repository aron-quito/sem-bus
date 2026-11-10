import SwiftUI

struct MainTabView: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var showProfileSheet: Bool = false
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            BCTheme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Barra Superior Minimalista Estilo Google Maps / Apple HIG
                topNavigationHeader
                    .zIndex(60)

                // TabView Principal de 4 Pestañas (Fiel al Mockup)
                TabView(selection: $viewModel.selectedTab) {
                    ExploreMapView(
                        viewModel: viewModel,
                        onDismissSearchFocus: {
                            isSearchFieldFocused = false
                            viewModel.isSearchDropdownVisible = false
                        }
                    )
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

            // Menú Desplegable Predictivo Sólido (#0F172A - Cero Transparencias con las calles del mapa)
            if viewModel.selectedTab == 0 && (isSearchFieldFocused || viewModel.isSearchDropdownVisible) {
                predictiveSearchDropdownOverlay
                    .padding(.top, 60)
                    .zIndex(55)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Overlay de Viaje en Curso (CU-06 In-Trip Sheet Minimizable)
            if let trip = viewModel.activeTrip {
                inTripFloatingOverlay(trip)
                    .zIndex(45)
            }
        }
        .onChange(of: isSearchFieldFocused) { _, focused in
            withAnimation(.easeInOut(duration: 0.18)) {
                if focused {
                    viewModel.isSearchDropdownVisible = true
                }
            }
        }
        .sheet(isPresented: $showProfileSheet) {
            ProfileSheetView(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $viewModel.showRoutePlannerFullScreen) {
            RoutePlannerView(viewModel: viewModel)
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

    // MARK: - Header Superior con Buscador Predictivo en Explorar, Botón [✕] y Avatar de Perfil
    private var topNavigationHeader: some View {
        HStack(spacing: 10) {
            if viewModel.selectedTab == 0 {
                // Píldora de Búsqueda estilo Mockup en Pestaña Explorar
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(BCTheme.royalBlue)
                            .frame(width: 28, height: 28)
                        Image(systemName: "mappin.and.ellipse")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white)
                    }

                    TextField("Buscar paradero o línea en Tacna...", text: $viewModel.searchQuery)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .focused($isSearchFieldFocused)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                viewModel.isSearchDropdownVisible = true
                            }
                        }

                    // Botón [✕] (Cancelar / Limpiar) visible al escribir O al enfocar el buscador
                    if isSearchFieldFocused || viewModel.isSearchDropdownVisible || !viewModel.searchQuery.isEmpty || viewModel.searchedDestinationPin != nil {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isSearchFieldFocused = false
                                viewModel.clearSearchAndDismiss()
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.14))
                                    .frame(width: 26, height: 26)
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                        .accessibilityLabel("Cancelar búsqueda")
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 44)
                .background(BCTheme.elevatedSurface)
                .overlay(
                    Capsule()
                        .stroke(
                            (isSearchFieldFocused || viewModel.isSearchDropdownVisible)
                                ? BCTheme.royalBlue.opacity(0.75)
                                : BCTheme.hairlineBorder,
                            lineWidth: 1
                        )
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
                isSearchFieldFocused = false
                viewModel.isSearchDropdownVisible = false
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

    // MARK: - Buscador Predictivo con Menú Sólido (#0F172A - Sección 4.B del Mockup)
    private var predictiveSearchDropdownOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DESTINOS Y PARADEROS EN TACNA")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(0.6)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isSearchFieldFocused = false
                        viewModel.isSearchDropdownVisible = false
                    }
                } label: {
                    Text("Cerrar ✕")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(BCTheme.cyanAccent)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 2)

            if viewModel.filteredSearchDestinations.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    Text("No se encontraron coincidencias para \"\(viewModel.searchQuery)\"")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(14)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 7) {
                        ForEach(viewModel.filteredSearchDestinations) { place in
                            HStack(spacing: 10) {
                                // Pulsar en la fila: Centra el mapa y suelta un pin rojo en la ubicación
                                Button {
                                    isSearchFieldFocused = false
                                    viewModel.selectPlaceFromSearch(place, startRouteImmediately: false)
                                } label: {
                                    HStack(spacing: 10) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .fill(Color(hex: place.iconColorHex).opacity(0.18))
                                                .frame(width: 34, height: 34)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                        .stroke(Color(hex: place.iconColorHex).opacity(0.45), lineWidth: 1)
                                                )
                                            Image(systemName: place.iconName)
                                                .font(.caption.weight(.bold))
                                                .foregroundColor(Color(hex: place.iconColorHex))
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(place.name)
                                                .font(.caption.weight(.bold))
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                            Text(place.subtitle)
                                                .font(.system(size: 10.5))
                                                .foregroundColor(.white.opacity(0.55))
                                                .lineLimit(1)
                                        }

                                        Spacer(minLength: 4)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                // Botón Circular Azul [Ir] con flecha de dirección (Abre Pantalla Completa "Cómo Llegar")
                                Button {
                                    isSearchFieldFocused = false
                                    viewModel.selectPlaceFromSearch(place, startRouteImmediately: true)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.turn.up.right")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("Ir")
                                            .font(.system(size: 11, weight: .bold))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .frame(height: 30)
                                    .background(BCTheme.royalBlue)
                                    .clipShape(Capsule())
                                    .shadow(color: BCTheme.royalBlue.opacity(0.45), radius: 4)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(Color(hex: "#1E293B"))
                            .overlay(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                    }
                }
                .frame(maxHeight: 270)
            }
        }
        .padding(12)
        // Caja Sólida Opaca #0F172A (Cero transparencias con los elementos del mapa)
        .background(Color(hex: "#0F172A"))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(hex: "#334155"), lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.75), radius: 22, y: 10)
        .padding(.horizontal, 16)
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

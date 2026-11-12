import SwiftUI

struct MainTabView: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var showProfileSheet: Bool = false
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            BCTheme.background
                .ignoresSafeArea()

            // TabView Principal a Pantalla Completa (El mapa en Explorar llega hasta el borde superior de la hora/batería)
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

                VStack(spacing: 0) {
                    nonMapTabTopHeader(title: "Líneas y Rutas de Tacna", icon: "bus.fill")
                    LinesView(viewModel: viewModel)
                }
                .tabItem {
                    Label("Líneas", systemImage: "bus.fill")
                }
                .tag(1)

                PayQrView(viewModel: viewModel)
                    .tabItem {
                        Label("Pagar QR", systemImage: "qrcode.viewfinder")
                    }
                    .tag(2)

                VStack(spacing: 0) {
                    nonMapTabTopHeader(title: "Monedero BC", icon: "wallet.pass.fill")
                    WalletView(viewModel: viewModel)
                }
                .tabItem {
                    Label("Monedero", systemImage: "wallet.pass.fill")
                }
                .tag(3)
            }
            .tint(BCTheme.royalBlue)

            // Cabecera Flotante Estilo Google Maps en la pestaña Explorar (Sin fondo sólido, mostrando el mapa detrás y blur en status bar)
            if viewModel.selectedTab == 0 {
                VStack(spacing: 0) {
                    googleMapsFloatingSearchBar
                        .padding(.horizontal, 14)
                        .padding(.top, 6)

                    // Menú Desplegable Predictivo Sólido (#0F172A) con los 34 Paraderos de Tacna + Lugares del Mapa (MapKit)
                    if isSearchFieldFocused || viewModel.isSearchDropdownVisible {
                        predictiveSearchDropdownOverlay
                            .padding(.top, 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .zIndex(60)
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

    // MARK: - Píldora Flotante Estilo Google Maps (Con Avatar Integrado a la Derecha y Cero Fondo Detrás)
    private var googleMapsFloatingSearchBar: some View {
        HStack(spacing: 10) {
            // Pin estilo Google Maps
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#3B82F6"), Color(hex: "#10B981")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.leading, 4)

            TextField("Buscar paradero o lugar en Tacna...", text: $viewModel.searchQuery)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.white)
                .focused($isSearchFieldFocused)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        viewModel.isSearchDropdownVisible = true
                    }
                }

            // Botón [✕] (Cancelar / Limpiar) visible al tocar el buscador o escribir
            if isSearchFieldFocused || viewModel.isSearchDropdownVisible || !viewModel.searchQuery.isEmpty || viewModel.searchedDestinationPin != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isSearchFieldFocused = false
                        viewModel.clearSearchAndDismiss()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.16))
                            .frame(width: 26, height: 26)
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .accessibilityLabel("Cancelar búsqueda")
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.trailing, 2)
            }

            // Avatar Circular de Perfil Integrado dentro de la Píldora (Idéntico a Google Maps)
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
                        .frame(width: 34, height: 34)
                        .overlay(
                            Circle()
                                .stroke(Color(hex: "#60A5FA"), lineWidth: 2)
                        )

                    Text(userInitial)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(.trailing, 3)
        }
        .padding(.horizontal, 8)
        .frame(height: 48)
        .background(
            Capsule()
                .fill(Color(hex: "#1F262E").opacity(0.94))
                .background(.ultraThinMaterial, in: Capsule())
        )
        .overlay(
            Capsule()
                .stroke(
                    (isSearchFieldFocused || viewModel.isSearchDropdownVisible)
                        ? BCTheme.royalBlue.opacity(0.85)
                        : Color.white.opacity(0.14),
                    lineWidth: 1
                )
        )
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.45), radius: 12, y: 5)
    }

    // MARK: - Header para Pestañas Líneas y Monedero
    private func nonMapTabTopHeader(title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(BCTheme.royalBlue)

            Text(title)
                .font(.headline.weight(.bold))
                .foregroundColor(.white)

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
                        .frame(width: 34, height: 34)

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

    // MARK: - Buscador Predictivo Sólido (#0F172A) con Paraderos Oficiales, Propuestas y Lugares del Mapa
    private var predictiveSearchDropdownOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PARADEROS DE TACNA Y LUGARES DEL MAPA (\(viewModel.filteredSearchDestinations.count))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
                    .tracking(0.5)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isSearchFieldFocused = false
                        viewModel.isSearchDropdownVisible = false
                    }
                } label: {
                    Text("Cerrar ✕")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(BCTheme.cyanAccent)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 2)

            if viewModel.filteredSearchDestinations.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    Text("Buscando \"\(viewModel.searchQuery)\" en el mapa de Tacna...")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(14)
            } else {
                ScrollView(showsIndicators: true) {
                    LazyVStack(spacing: 7) {
                        ForEach(viewModel.filteredSearchDestinations) { place in
                            HStack(spacing: 10) {
                                // Pulsar en la fila: Centra el mapa en la ubicación y coloca el Pin con opción [Ir]
                                Button {
                                    isSearchFieldFocused = false
                                    viewModel.selectPlaceFromSearch(place, startRouteImmediately: false)
                                } label: {
                                    HStack(spacing: 10) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(Color(hex: place.displayColorHex).opacity(0.18))
                                                .frame(width: 36, height: 36)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                        .stroke(Color(hex: place.displayColorHex).opacity(0.45), lineWidth: 1)
                                                )
                                            Image(systemName: place.displayIconName)
                                                .font(.caption.weight(.bold))
                                                .foregroundColor(Color(hex: place.displayColorHex))
                                        }

                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 6) {
                                                Text(place.name)
                                                    .font(.caption.weight(.bold))
                                                    .foregroundColor(.white)
                                                    .lineLimit(1)

                                                if place.isOfficialParadero {
                                                    Text("PARADERO")
                                                        .font(.system(size: 7.5, weight: .black))
                                                        .foregroundColor(.white)
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 1.5)
                                                        .background(Color(hex: "#2563EB"))
                                                        .clipShape(Capsule())
                                                } else if place.category.isProposedModernization {
                                                    Text("PROPUESTA")
                                                        .font(.system(size: 7.5, weight: .black))
                                                        .foregroundColor(.black)
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 1.5)
                                                        .background(BCTheme.amber)
                                                        .clipShape(Capsule())
                                                } else if place.category == .mapCustomPlace {
                                                    Text("UBICACIÓN API")
                                                        .font(.system(size: 7.5, weight: .black))
                                                        .foregroundColor(.black)
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 1.5)
                                                        .background(Color(hex: "#38BDF8"))
                                                        .clipShape(Capsule())
                                                }
                                            }

                                            Text(place.subtitle)
                                                .font(.system(size: 10.5))
                                                .foregroundColor(.white.opacity(0.55))
                                                .lineLimit(1)

                                            HStack(spacing: 4) {
                                                ForEach(place.routesPassing.prefix(3), id: \.self) { routeCode in
                                                    Text(routeCode)
                                                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                                        .foregroundColor(Color(hex: "#93C5FD"))
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 1.5)
                                                        .background(Color(hex: "#1E3A8A").opacity(0.65))
                                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                                }
                                                Text("• \(place.distanceLabel)")
                                                    .font(.system(size: 9.5, weight: .medium))
                                                    .foregroundColor(BCTheme.emerald)
                                            }
                                        }

                                        Spacer(minLength: 4)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                // Botón Azul [Ir] (Abre directamente el módulo de Cómo Llegar con ese paradero/lugar)
                                Button {
                                    isSearchFieldFocused = false
                                    viewModel.selectPlaceFromSearch(place, startRouteImmediately: true)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.turn.up.right")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("Ir")
                                            .font(.system(size: 11.5, weight: .bold))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .frame(height: 32)
                                    .background(BCTheme.royalBlue)
                                    .clipShape(Capsule())
                                    .shadow(color: BCTheme.royalBlue.opacity(0.45), radius: 4)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(Color(hex: "#1E293B"))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
                .frame(maxHeight: 330)
            }
        }
        .padding(12)
        .background(Color(hex: "#0F172A"))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(hex: "#334155"), lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.75), radius: 22, y: 10)
        .padding(.horizontal, 14)
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

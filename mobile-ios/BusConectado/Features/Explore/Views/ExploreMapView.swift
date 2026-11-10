import SwiftUI
import MapKit

struct ExploreMapView: View {
    @ObservedObject var viewModel: AuthViewModel
    var onDismissSearchFocus: (() -> Void)? = nil

    @State private var selectedStop: BusStopModel? = nil
    @State private var selectedCatalogStop: TacnaDestinationPlace? = nil
    @State private var selectedMapFeature: MapFeature? = nil
    @State private var selectedBus: ActiveBusModel? = nil
    @State private var selectedAdvanceMinutes: Int = 5
    @State private var imminentAlertEnabled: Bool = true

    // Estado de arrastre para retirar con un gesto el pop-up "Sin paraderos ni buses en camino"
    @State private var emptyBannerDragOffset: CGSize = .zero
    @State private var timerPulseAnimation: Bool = false

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -18.0128, longitude: -70.2512), // Centro Histórico de Tacna
            span: MKCoordinateSpan(latitudeDelta: 0.020, longitudeDelta: 0.020)
        )
    )

    /// Paraderos visibles sobre el mapa cuando el usuario filtra por "Paraderos" o proyecta una ruta
    private var visibleCatalogStopsOnMap: [TacnaDestinationPlace] {
        if let projectedRoute = viewModel.activeRouteOverlayOnMap {
            return projectedRoute.resolvedStops
        }
        if viewModel.mapCategory == .stops {
            return TacnaDestinationPlace.catalog
        }
        return []
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 1. Mapa Nativo de Tacna a Pantalla Completa hasta el borde superior (detrás de la hora/batería/Dynamic Island)
            Map(position: $cameraPosition, selection: $selectedMapFeature) {
                // Ubicación Real del Usuario en Tiempo Real (Punto azul nativo de Apple Maps con cono direccional)
                UserAnnotation()

                // Trazado de Ruta Oficial Proyectada desde la pestaña "Líneas" (Ej: Ruta 14, Ruta 10B, etc.)
                if let projectedRoute = viewModel.activeRouteOverlayOnMap {
                    let coords = projectedRoute.resolvedStops.map { $0.coordinate }
                    if coords.count >= 2 {
                        MapPolyline(coordinates: coords)
                            .stroke(
                                Color(hex: projectedRoute.colorHex),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                            )
                    }
                }

                // Marcadores Interactivos de los 34 Paraderos de Tacna (Cuando se activa filtro "Paraderos" o una Ruta)
                ForEach(visibleCatalogStopsOnMap) { catalogStop in
                    Annotation(catalogStop.shortName, coordinate: catalogStop.coordinate) {
                        Button {
                            BCFeedbackManager.shared.impactLight()
                            selectedCatalogStop = catalogStop
                        } label: {
                            VStack(spacing: 2) {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: catalogStop.iconColorHex))
                                        .frame(width: 30, height: 30)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 2)
                                        )
                                        .shadow(color: .black.opacity(0.45), radius: 4)
                                    Image(systemName: catalogStop.iconName)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                }

                                Text(catalogStop.shortName)
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(BCTheme.elevatedSurface.opacity(0.92))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
                    }
                }

                // Pin Rojo Dinámico cuando el usuario selecciona un Paradero o Lugar desde el Buscador Predictivo
                if let searchedPlace = viewModel.searchedDestinationPin {
                    Annotation(searchedPlace.shortName, coordinate: searchedPlace.coordinate) {
                        Button {
                            selectedCatalogStop = searchedPlace
                        } label: {
                            VStack(spacing: 3) {
                                HStack(spacing: 5) {
                                    Text(searchedPlace.shortName)
                                        .font(.system(size: 10, weight: .heavy))
                                        .foregroundColor(.white)
                                    Button {
                                        viewModel.openRoutePlanner(with: searchedPlace)
                                    } label: {
                                        Text("Ir ↱")
                                            .font(.system(size: 9, weight: .black))
                                            .foregroundColor(.black)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2.5)
                                            .background(BCTheme.cyanAccent)
                                            .clipShape(Capsule())
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(BCTheme.destructiveRed)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.65), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(color: .black.opacity(0.45), radius: 5)

                                ZStack {
                                    Circle()
                                        .fill(BCTheme.destructiveRed)
                                        .frame(width: 26, height: 26)
                                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                    Image(systemName: "mappin.and.ellipse")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                    }
                }

                // Trazado de Guía de Ruta Activa en Mapa Principal (Cuando el usuario pulsa [Iniciar] en Cómo Llegar)
                if let guidance = viewModel.activeRouteGuidance {
                    let dest = guidance.destination

                    // Tramo 1: Caminata hacia el paradero (Cian punteado)
                    MapPolyline(coordinates: dest.walkingToBoardCoordinates)
                        .stroke(
                            BCTheme.cyanAccent,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [6, 6])
                        )

                    // Tramo 2: Recorrido en Bus (Cian/Azul brillante continuo)
                    if dest.routeCase != .walkOnlyNearby && guidance.selectedOptionIndex != 3 {
                        MapPolyline(coordinates: dest.busTransitCoordinates)
                            .stroke(
                                Color(hex: "#00E5FF"),
                                style: StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round)
                            )

                        // Punto de abordaje
                        Annotation(dest.boardingStopName, coordinate: dest.boardingCoordinate) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(BCTheme.royalBlue)
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                Text("Subir en \(dest.boardingStopName)")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(BCTheme.elevatedSurface.opacity(0.95))
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    // Pin Rojo de Destino de la Guía Activa (#guide-dest-pin)
                    Annotation(dest.shortName, coordinate: dest.coordinate) {
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 9, weight: .bold))
                                Text(dest.shortName)
                                    .font(.system(size: 9.5, weight: .heavy))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(BCTheme.destructiveRed)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .shadow(radius: 5)

                            ZStack {
                                Circle()
                                    .fill(BCTheme.destructiveRed)
                                    .frame(width: 20, height: 20)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                }

                // Marcadores dinámicos del Servidor (Vacío en cuentas de prueba hasta que entren buses reales en operación)
                ForEach(viewModel.filteredStops) { stop in
                    Annotation(stop.name, coordinate: stop.coordinate) {
                        Button {
                            BCFeedbackManager.shared.impactLight()
                            selectedStop = stop
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(stop.isKeyStop ? BCTheme.royalBlue : BCTheme.emerald)
                                    .frame(width: 34, height: 34)
                                    .shadow(color: .black.opacity(0.35), radius: 5)
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }

                ForEach(viewModel.filteredBuses) { bus in
                    Annotation("\(bus.unitNumber) · \(bus.plate)", coordinate: bus.coordinate) {
                        Button {
                            BCFeedbackManager.shared.impactLight()
                            selectedBus = bus
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(BCTheme.emerald.opacity(0.28))
                                    .frame(width: 44, height: 44)
                                Circle()
                                    .fill(BCTheme.emerald)
                                    .frame(width: 28, height: 28)
                                Image(systemName: "bus.fill")
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(.black)
                            }
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea(edges: .top)
            .onMapCameraChange(frequency: .continuous) {
                onDismissSearchFocus?()
            }
            .onChange(of: selectedMapFeature) { _, newFeature in
                guard let feature = newFeature else { return }
                handleTappedAppleMapsFeature(feature)
            }
            .onChange(of: viewModel.mapFocusTrigger) { _, _ in
                if let coord = viewModel.mapFocusTargetCoordinate {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        cameraPosition = .region(
                            MKCoordinateRegion(
                                center: coord,
                                span: MKCoordinateSpan(
                                    latitudeDelta: viewModel.mapFocusSpanDelta,
                                    longitudeDelta: viewModel.mapFocusSpanDelta
                                )
                            )
                        )
                    }
                }
            }

            // 2. Blur Progresivo Estilo Google Maps en la Parte Superior (Hora / Señal / Batería / Dynamic Island)
            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(height: 112)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.95), location: 0.0),
                            .init(color: .black.opacity(0.68), location: 0.48),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)

            // 3. Capas Flotantes sobre el Mapa (Debajo de la Píldora Flotante de Búsqueda)
            VStack(spacing: 10) {
                // Espacio reservado para la píldora flotante de búsqueda de MainTabView
                Spacer()
                    .frame(height: 54)

                // Píldoras Flotantes de Categoría estilo Google Maps (Sin fondo sólido detrás)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(MapFilterCategory.allCases, id: \.self) { category in
                            let isSelected = viewModel.mapCategory == category
                            Button {
                                BCFeedbackManager.shared.impactLight()
                                onDismissSearchFocus?()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.mapCategory = category
                                    if category != .routes {
                                        viewModel.activeRouteOverlayOnMap = nil
                                    } else if viewModel.activeRouteOverlayOnMap == nil {
                                        viewModel.activeRouteOverlayOnMap = TacnaOfficialRouteCatalogItem.officialRoutes.first
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: iconForCategory(category))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(isSelected ? .white : colorForCategory(category))
                                    Text(category == .stops ? "Paraderos (34)" : category.rawValue)
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(isSelected ? .white : .white.opacity(0.9))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? BCTheme.royalBlue : Color(hex: "#1F262E").opacity(0.92))
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                            }
                        }

                        Button {
                            BCFeedbackManager.shared.impactLight()
                            onDismissSearchFocus?()
                            Task {
                                await viewModel.refreshStateFromBackendIfAvailable()
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .font(.caption)
                                Text("Sincronizar")
                                    .font(.caption2.weight(.semibold))
                            }
                            .foregroundColor(BCTheme.cyanAccent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color(hex: "#1F262E").opacity(0.92))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(BCTheme.cyanAccent.opacity(0.35), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                        }
                    }
                    .padding(.horizontal, 14)
                }

                // Píldora de Ruta Proyectada (Si el usuario seleccionó ver una ruta desde Líneas o desde el filtro Rutas)
                if let projectedRoute = viewModel.activeRouteOverlayOnMap {
                    HStack(spacing: 8) {
                        Text(projectedRoute.code)
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(hex: projectedRoute.colorHex))
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Text("\(projectedRoute.resolvedStops.count) paraderos en mapa · Toca uno para ir")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Spacer()

                        Button {
                            withAnimation {
                                viewModel.activeRouteOverlayOnMap = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.75))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#1F262E").opacity(0.95))
                    .clipShape(Capsule())
                    .padding(.horizontal, 14)
                }

                // Fila Superior Izquierda: Widget Circular Verde de Guía Activa + Botón Rojo [✕] (#guide-timer-widget)
                if let guidance = viewModel.activeRouteGuidance {
                    HStack(alignment: .top) {
                        guidedRouteTimerWidget(guidance)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .transition(.scale.combined(with: .opacity))
                }

                // Widget Circular de Alerta de Llegada (Si el usuario activó los 2 Timers de un paradero)
                if let alert = viewModel.activeArrivalAlert {
                    HStack {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(BCTheme.emerald)
                                .frame(width: 8, height: 8)
                            Text("\(alert.stopName) · \(formatSeconds(alert.remainingSeconds))")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white)
                            Button {
                                viewModel.cancelArrivalAlert()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(BCTheme.elevatedSurface.opacity(0.95))
                        .clipShape(Capsule())

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                }

                Spacer()

                // 4. Controles Flotantes Inferiores Derecha: Botón Ubicación + Botón Cian "Ir / Cómo Llegar"
                HStack(alignment: .bottom) {
                    Spacer()

                    VStack(spacing: 12) {
                        // Botón Centrar Mi Ubicación (Estilo Google Maps)
                        Button {
                            onDismissSearchFocus?()
                            viewModel.centerMapOnUserLocation()
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(hex: "#1F262E").opacity(0.95))
                                    .frame(width: 46, height: 46)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                                    )

                                ZStack {
                                    Circle()
                                        .stroke(Color.white.opacity(0.9), lineWidth: 2)
                                        .frame(width: 20, height: 20)
                                    Circle()
                                        .fill(BCTheme.royalBlue)
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                        }
                        .accessibilityLabel("Centrar mi ubicación")

                        // Botón FAB Cian Cuadrado Redondeado "Ir / Cómo Llegar" (Idéntico a Google Maps / Mockup)
                        Button {
                            onDismissSearchFocus?()
                            viewModel.openRoutePlanner(with: viewModel.searchedDestinationPin)
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(hex: "#38BDF8"))
                                    .frame(width: 54, height: 54)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.white.opacity(0.45), lineWidth: 1)
                                    )

                                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(Color(hex: "#090D16"))
                            }
                            .shadow(color: Color(hex: "#38BDF8").opacity(0.45), radius: 10, y: 4)
                        }
                        .accessibilityLabel("Ir / Cómo llegar")
                    }
                    .padding(.trailing, 14)
                }
                .padding(.bottom, (viewModel.stops.isEmpty && viewModel.activeBuses.isEmpty && !viewModel.isEmptyTransitBannerDismissed) ? 4 : 18)

                // 5. Pop-up "Sin paraderos ni buses en camino" Retirable con un Gesto (Deslizar o pulsar [✕])
                if viewModel.stops.isEmpty && viewModel.activeBuses.isEmpty && !viewModel.isEmptyTransitBannerDismissed {
                    emptyTransitStatusCard
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(item: $selectedCatalogStop) { catalogPlace in
            catalogStopDetailSheet(catalogPlace)
                .presentationDetents([.height(catalogPlace.statusNote != nil ? 315 : 270)])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedStop) { stop in
            stopDetailSheet(stop)
                .presentationDetents([.height(290)])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedBus) { bus in
            busTechnicalSheet(bus)
                .presentationDetents([.height(330)])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            LocationService.shared.requestPermissionAndStart()
        }
        .alert(
            "¿Cancelar guía de ruta?",
            isPresented: $viewModel.showCancelRouteGuidanceAlert
        ) {
            Button("Cancelar ruta y guía", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.confirmCancelGuidedRoute()
                }
            }
            Button("Continuar en ruta", role: .cancel) {}
        } message: {
            Text("¿Deseas cancelar la dirección de ruta establecida por el usuario y la guía?")
        }
    }

    // MARK: - Ficha Interactiva al Seleccionar cualquier Paradero o Lugar del Mapa de Tacna
    private func catalogStopDetailSheet(_ place: TacnaDestinationPlace) -> some View {
        ZStack {
            BCTheme.elevatedSurface.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.category.badgeTitle)
                            .font(.system(size: 9.5, weight: .heavy))
                            .foregroundColor(place.category.isProposedModernization ? BCTheme.amber : BCTheme.emerald)
                            .tracking(0.5)

                        Text(place.name)
                            .font(.title3.weight(.bold))
                            .foregroundColor(.white)

                        Text(place.subtitle)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.65))
                    }
                    Spacer()

                    Text(place.distanceLabel)
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundColor(BCTheme.cyanAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(BCTheme.cyanAccent.opacity(0.15))
                        .clipShape(Capsule())
                }

                // Rutas que conectan este paradero
                HStack(spacing: 6) {
                    Text("Rutas que abordan aquí:")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                    ForEach(place.routesPassing, id: \.self) { routeCode in
                        Text(routeCode)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(BCTheme.royalBlue)
                            .clipShape(Capsule())
                    }
                }

                if let note = place.statusNote {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundColor(BCTheme.amber)
                        Text(note)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BCTheme.amber.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Divider().background(BCTheme.hairlineBorder)

                // Botón Principal: Trazar Cómo Llegar ("Ir") a este Paradero
                Button {
                    let target = place
                    selectedCatalogStop = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        viewModel.openRoutePlanner(with: target)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.subheadline.weight(.bold))
                        Text("Ir / Cómo llegar a este paradero (\(place.totalDurationMinutes) min)")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(BCTheme.cyanAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                // Botón Secundario: Activar Alerta de Llegada (2 Timers)
                Button {
                    let asStop = BusStopModel(
                        id: place.id,
                        routeId: place.primaryRouteName,
                        name: place.shortName,
                        subtitle: place.subtitle,
                        latitude: place.latitude,
                        longitude: place.longitude,
                        sequenceOrder: 1,
                        direction: "UP",
                        isKeyStop: true
                    )
                    viewModel.activateStopArrivalAlert(
                        stop: asStop,
                        advanceMinutes: selectedAdvanceMinutes,
                        imminentEnabled: imminentAlertEnabled
                    )
                    selectedCatalogStop = nil
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.badge.fill")
                            .font(.caption.weight(.bold))
                        Text("Activar Alerta de Llegada (5 min + Vibración)")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(BCTheme.hairlineBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(20)
        }
    }

    private func handleTappedAppleMapsFeature(_ feature: MapFeature) {
        let coord = feature.coordinate
        // Coordenadas válidas en la cuenca de Tacna y alrededores
        let isTacna = (coord.latitude >= -18.35 && coord.latitude <= -17.75) &&
                      (coord.longitude >= -70.55 && coord.longitude <= -70.00)
        guard isTacna else { return }

        BCFeedbackManager.shared.impactMedium()
        let title = feature.title ?? "Punto de interés"
        let fallbackPlace = TacnaDestinationPlace(
            id: "apple_poi_\(abs(coord.latitude))_\(abs(coord.longitude))",
            name: title,
            shortName: title,
            subtitle: "Punto de interés en Tacna • Apple Maps",
            category: .plazasCentral,
            routesPassing: ["Ruta 14", "Ruta 10B", "Ruta A"],
            iconName: "mappin.and.ellipse",
            iconColorHex: "#38BDF8",
            latitude: coord.latitude,
            longitude: coord.longitude,
            routeCase: .busRoute14,
            totalDurationMinutes: 7,
            secondaryDurationMinutes: 12,
            walkingDirectMinutes: 15,
            distanceLabel: "Tacna",
            walkInitialMinutes: 2,
            busRideMinutes: 5,
            walkFinalMinutes: 0,
            boardingStopName: "Paradero cercano",
            alightingStopName: title,
            intermediateStopName: nil,
            statusNote: nil
        )
        selectedCatalogStop = fallbackPlace
        viewModel.searchedDestinationPin = fallbackPlace
    }

    // MARK: - Widget Circular Verde de Timer + Botón Rojo de Cancelación (#guide-timer-widget)
    private func guidedRouteTimerWidget(_ guidance: ActiveRouteGuidanceState) -> some View {
        VStack(spacing: 8) {
            Button {
                BCFeedbackManager.shared.impactLight()
                viewModel.openRoutePlanner(with: guidance.destination)
            } label: {
                ZStack {
                    Circle()
                        .fill(BCTheme.emerald.opacity(0.28))
                        .frame(width: 62, height: 62)
                        .scaleEffect(timerPulseAnimation ? 1.12 : 0.94)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: timerPulseAnimation)

                    VStack(spacing: 1) {
                        HStack(spacing: 2) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 7.5, weight: .bold))
                            Text("BUS")
                                .font(.system(size: 8, weight: .heavy))
                        }
                        .foregroundColor(Color(hex: "#D1FAE5"))

                        Text(formatSeconds(guidance.remainingBusArrivalSeconds))
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .frame(width: 54, height: 54)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "#10B981"), Color(hex: "#047857")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Circle()
                            .stroke(Color(hex: "#6EE7B7"), lineWidth: 2)
                    )
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                }
            }
            .onAppear {
                timerPulseAnimation = true
            }

            Button {
                viewModel.promptCancelGuidedRoute()
            } label: {
                ZStack {
                    Circle()
                        .fill(BCTheme.destructiveRed)
                        .frame(width: 34, height: 34)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.85), lineWidth: 2)
                        )
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(.white)
                }
                .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
            }
            .accessibilityLabel("Cancelar guía de ruta")
        }
    }

    // MARK: - Pop-up Minimalista Retirable con un Gesto ("Sin paraderos ni buses en camino")
    private var emptyTransitStatusCard: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 34, height: 4)
                .padding(.top, 8)

            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 40, height: 40)
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.65))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Sin unidades en camino (Cuenta Prueba)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)

                        Spacer()

                        Button {
                            BCFeedbackManager.shared.impactLight()
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                                viewModel.isEmptyTransitBannerDismissed = true
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.45))
                        }
                    }

                    Text("Desliza para ocultar. Puedes buscar cualquiera de los 34 paraderos de Tacna o tocar 'Paraderos (34)' arriba.")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(BCTheme.elevatedSurface.opacity(0.95))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(BCTheme.hairlineBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .offset(x: emptyBannerDragOffset.width, y: max(0, emptyBannerDragOffset.height))
        .opacity(Double(1.0 - min(abs(emptyBannerDragOffset.width) + max(0, emptyBannerDragOffset.height), 140) / 160.0))
        .gesture(
            DragGesture()
                .onChanged { value in
                    emptyBannerDragOffset = value.translation
                }
                .onEnded { value in
                    let shouldDismiss = value.translation.height > 32 || abs(value.translation.width) > 65
                    if shouldDismiss {
                        BCFeedbackManager.shared.impactLight()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            viewModel.isEmptyTransitBannerDismissed = true
                            emptyBannerDragOffset = .zero
                        }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            emptyBannerDragOffset = .zero
                        }
                    }
                }
        )
    }

    // MARK: - Ficha de Paradero del Servidor con Configurador de 2 Timers
    private func stopDetailSheet(_ stop: BusStopModel) -> some View {
        ZStack {
            BCTheme.elevatedSurface.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stop.name)
                            .font(.title3.weight(.bold))
                            .foregroundColor(.white)
                        Text(stop.subtitle)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Text("Ruta 14")
                        .font(.caption.weight(.bold))
                        .foregroundColor(BCTheme.royalBlue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(BCTheme.royalBlue.opacity(0.15))
                        .clipShape(Capsule())
                }

                Divider().background(BCTheme.hairlineBorder)

                Text("ALERTA INTELIGENTE DE LLEGADA (2 TIMERS)")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.gray)

                HStack(spacing: 10) {
                    ForEach([5, 10, 15], id: \.self) { mins in
                        Button {
                            selectedAdvanceMinutes = mins
                        } label: {
                            Text("\(mins) min antes")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(selectedAdvanceMinutes == mins ? .black : .white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(selectedAdvanceMinutes == mins ? BCTheme.emerald : Color.white.opacity(0.07))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }

                Toggle(isOn: $imminentAlertEnabled) {
                    Text("Timer 2: Vibración inminente al frenar en paradero")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                }
                .tint(BCTheme.emerald)

                Button {
                    viewModel.activateStopArrivalAlert(
                        stop: stop,
                        advanceMinutes: selectedAdvanceMinutes,
                        imminentEnabled: imminentAlertEnabled
                    )
                    selectedStop = nil
                } label: {
                    Text("Activar Alerta de Llegada")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(BCTheme.emerald)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Spacer()
            }
            .padding(22)
        }
    }

    // MARK: - Ficha Técnica del Bus
    private func busTechnicalSheet(_ bus: ActiveBusModel) -> some View {
        ZStack {
            BCTheme.elevatedSurface.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ruta \(bus.lineNumber) · \(bus.unitNumber)")
                            .font(.title3.weight(.bold))
                            .foregroundColor(.white)
                        Text("Placa oficial: \(bus.plate) · Conductor: \(bus.driverName) (\(String(format: "%.1f", bus.driverRating))★)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Aforo en tiempo real")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("\(bus.occupancyCurrent)/\(bus.occupancyMax) pasajeros (\(bus.occupancyPercentage)%)")
                            .font(.caption.weight(.bold))
                            .foregroundColor(BCTheme.emerald)
                    }
                    ProgressView(value: Double(bus.occupancyCurrent), total: Double(max(bus.occupancyMax, 1)))
                        .tint(BCTheme.emerald)
                }
                .padding(14)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                Text("Suscripción Automática activa: Tu app se vinculará a este bus en cuanto abordes o escanees tu QR en puerta.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.55))

                Spacer()
            }
            .padding(22)
        }
    }

    private func iconForCategory(_ category: MapFilterCategory) -> String {
        switch category {
        case .all: return "sparkles"
        case .routes: return "point.topleft.down.curvedto.point.bottomright.up"
        case .stops: return "mappin.and.ellipse"
        }
    }

    private func colorForCategory(_ category: MapFilterCategory) -> Color {
        switch category {
        case .all: return BCTheme.royalBlue
        case .routes: return BCTheme.emerald
        case .stops: return BCTheme.cyanAccent
        }
    }

    private func formatSeconds(_ total: Int) -> String {
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

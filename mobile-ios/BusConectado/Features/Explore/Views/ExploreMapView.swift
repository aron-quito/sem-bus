import SwiftUI
import MapKit

struct ExploreMapView: View {
    @ObservedObject var viewModel: AuthViewModel
    var onDismissSearchFocus: (() -> Void)? = nil

    @State private var selectedStop: BusStopModel? = nil
    @State private var selectedCatalogStop: TacnaDestinationPlace? = nil
    @State private var selectedBus: ActiveBusModel? = nil
    @State private var selectedAdvanceMinutes: Int = 5
    @State private var imminentAlertEnabled: Bool = true

    // Estado de arrastre para retirar con un gesto el pop-up "Sin paraderos ni buses en camino"
    @State private var emptyBannerDragOffset: CGSize = .zero
    @State private var timerPulseAnimation: Bool = false

    // Polilíneas alineadas nativamente a las calles de Tacna (Apple Maps MKDirections / OSRM)
    @State private var projectedRouteStreetCoords: [CLLocationCoordinate2D] = []
    @State private var ordinaryRoutesStreetCoords: [String: [CLLocationCoordinate2D]] = [:]
    @State private var guidedWalkStreetCoords: [CLLocationCoordinate2D] = []
    @State private var guidedBusStreetCoords: [CLLocationCoordinate2D] = []
    @State private var guidedFinalWalkStreetCoords: [CLLocationCoordinate2D] = []
    @State private var isPinDropModeActive: Bool = false

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -18.0128, longitude: -70.2512), // Centro Histórico de Tacna
            span: MKCoordinateSpan(latitudeDelta: 0.020, longitudeDelta: 0.020)
        )
    )

    private var ordinaryRoutesInService: [TacnaOfficialRouteCatalogItem] {
        viewModel.dynamicRoutes.filter { $0.isOrdinaryInService }
    }

    /// Paraderos visibles sobre el mapa cuando el usuario filtra por "Paraderos" o proyecta una ruta
    private var visibleCatalogStopsOnMap: [TacnaDestinationPlace] {
        if let projectedRoute = viewModel.activeRouteOverlayOnMap {
            return projectedRoute.resolvedStops(using: viewModel.dynamicCatalogStops)
        }
        if viewModel.mapCategory == .stops {
            return viewModel.dynamicCatalogStops
        }
        return []
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 1. Mapa Nativo de Tacna a Pantalla Completa hasta el borde superior (detrás de la hora/batería/Dynamic Island)
            interactiveMapLayer

            // 2. Blur Progresivo Estilo Google Maps en la Parte Superior (Hora / Señal / Batería / Dynamic Island)
            TopMapStatusBarFade()

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
                                    viewModel.activeRouteOverlayOnMap = nil
                                }
                                if category == .routes {
                                    Task {
                                        await preloadOrdinaryRoutesStreetAlignment()
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: iconForCategory(category))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(isSelected ? .white : colorForCategory(category))
                                    Text(chipTitle(for: category))
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
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isPinDropModeActive.toggle()
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: isPinDropModeActive ? "mappin.slash.circle.fill" : "hand.point.up.left.fill")
                                    .font(.caption)
                                Text(isPinDropModeActive ? "Toca el mapa..." : "Fijar punto")
                                    .font(.caption2.weight(.semibold))
                            }
                            .foregroundColor(isPinDropModeActive ? .black : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(isPinDropModeActive ? BCTheme.cyanAccent : Color(hex: "#1F262E").opacity(0.92))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(BCTheme.cyanAccent.opacity(0.45), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                        }

                        Button {
                            BCFeedbackManager.shared.impactLight()
                            onDismissSearchFocus?()
                            Task {
                                await viewModel.refreshStateFromBackendIfAvailable(isManual: true)
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
                    let stopsInRoute = projectedRoute.resolvedStops(using: viewModel.dynamicCatalogStops)
                    HStack(spacing: 8) {
                        Text(projectedRoute.code)
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(hex: projectedRoute.colorHex))
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Text(
                            projectedRoute.isOrdinary
                                ? (projectedRoute.isInService ? "🟢 En Servicio" : "⚠️ Fuera de Servicio")
                                : "🗺️ Externa (Sin GPS)"
                        )
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(
                            projectedRoute.isOrdinary
                                ? (projectedRoute.isInService ? BCTheme.emerald : BCTheme.amber)
                                : .white.opacity(0.75)
                        )

                        Text("· \(stopsInRoute.count) paraderos · ~\(projectedRoute.estimatedTotalMinutes)m")
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
                } else if viewModel.mapCategory == .routes {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(ordinaryRoutesInService.isEmpty ? BCTheme.amber : BCTheme.emerald)
                            .frame(width: 8, height: 8)
                        Text(
                            ordinaryRoutesInService.isEmpty
                                ? "Sin rutas ordinarias en circulación"
                                : "Rutas ordinarias en circulación (\(ordinaryRoutesInService.count)) · \(viewModel.filteredBuses.count) buses en vivo"
                        )
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#1F262E").opacity(0.95))
                    .clipShape(Capsule())
                    .padding(.horizontal, 14)
                }

                // Fila Superior Izquierda: Widget Circular Verde de Guía Activa + Banner de Aviso de 5 Minutos / Ruta Externa
                if let guidance = viewModel.activeRouteGuidance {
                    HStack(alignment: .top, spacing: 10) {
                        guidedRouteTimerWidget(guidance)

                        VStack(alignment: .leading, spacing: 6) {
                            if viewModel.showFiveMinuteBoardingBanner,
                               let cand = guidance.candidate,
                               cand.kind == .ordinaryInService {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "bell.badge.fill")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(BCTheme.emerald)
                                        .padding(.top, 2)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("¡\(cand.routeCode) a ≤ 5 min del paradero!")
                                            .font(.system(size: 11, weight: .heavy))
                                            .foregroundColor(BCTheme.emerald)
                                        Text("Dirígete al Paradero \(cand.boardingPointName) (~\(cand.walkInitialMinutes) min a pie) para abordar rumbo a \(guidance.destination.shortName).")
                                            .font(.system(size: 9.5, weight: .medium))
                                            .foregroundColor(.white.opacity(0.9))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    Spacer(minLength: 2)

                                    Button {
                                        withAnimation {
                                            viewModel.showFiveMinuteBoardingBanner = false
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                }
                                .padding(10)
                                .background(Color(hex: "#052E16").opacity(0.95))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(BCTheme.emerald.opacity(0.7), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
                            } else if let cand = guidance.candidate, cand.kind == .externalFreeBoarding {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(BCTheme.amber)
                                        .padding(.top, 2)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Guía en \(cand.routeCode) (Ruta Externa • Sin GPS)")
                                            .font(.system(size: 10.5, weight: .heavy))
                                            .foregroundColor(BCTheme.amber)
                                        Text("Abordaje libre en cualquier punto de la vía (\(cand.boardingPointName)). No cuenta con tracking ni avisos de paradero.")
                                            .font(.system(size: 9.5))
                                            .foregroundColor(.white.opacity(0.85))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .padding(10)
                                .background(Color(hex: "#1F262E").opacity(0.95))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(BCTheme.amber.opacity(0.6), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
                            }
                        }

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
                .presentationDetents([.height(catalogPlace.statusNote != nil ? 355 : 320)])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedStop) { stop in
            stopDetailSheet(stop)
                .presentationDetents([.height(260)])
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

    // MARK: - Ficha Interactiva al Seleccionar cualquier Paradero o Punto de Encuentro del Mapa de Tacna
    private func catalogStopDetailSheet(_ place: TacnaDestinationPlace) -> some View {
        let notificationAvailability = viewModel.stopNotificationAvailability(for: place)
        let isCustomMapPoint = (place.category == .mapCustomPlace)
        let autoEval = viewModel.evaluateAutomatedRoutes(
            from: viewModel.routePlannerInitialOrigin ?? .currentLocationPlace(),
            to: place
        )
        let estMinutes = autoEval.recommendedCandidate?.totalDurationMinutes ?? place.totalDurationMinutes

        return ZStack {
            BCTheme.elevatedSurface.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isCustomMapPoint ? "PUNTO DE ENCUENTRO EN EL MAPA" : place.category.badgeTitle)
                            .font(.system(size: 9.5, weight: .heavy))
                            .foregroundColor(
                                isCustomMapPoint
                                    ? BCTheme.cyanAccent
                                    : (place.category.isProposedModernization ? BCTheme.amber : BCTheme.emerald)
                            )
                            .tracking(0.5)

                        Text(place.name)
                            .font(.headline.weight(.bold))
                            .foregroundColor(.white)

                        Text(place.subtitle)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                    Spacer()

                    Text(place.distanceLabel)
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundColor(BCTheme.cyanAccent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(BCTheme.cyanAccent.opacity(0.15))
                        .clipShape(Capsule())
                }

                // Rutas que conectan este paradero (Clasificadas por Ordinarias en Servicio, Fuera de Servicio o Externas)
                if !place.routesPassing.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Text("Líneas:")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.6))
                            ForEach(place.routesPassing, id: \.self) { routeCode in
                                let matchedRoute = viewModel.routeItem(forCode: routeCode)
                                let isOrd = matchedRoute?.isOrdinary ?? false
                                let isOrdActive = matchedRoute?.isOrdinaryInService ?? false

                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(
                                            isOrd
                                                ? (isOrdActive ? BCTheme.emerald : BCTheme.amber)
                                                : Color.white.opacity(0.45)
                                        )
                                        .frame(width: 6, height: 6)
                                    Text(routeCode)
                                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    Text(isOrd ? (isOrdActive ? "ORD" : "SIN SERV.") : "EXT")
                                        .font(.system(size: 7.5, weight: .black))
                                        .opacity(0.85)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    isOrd
                                        ? (isOrdActive ? BCTheme.royalBlue : BCTheme.amber.opacity(0.28))
                                        : Color.white.opacity(0.12)
                                )
                                .clipShape(Capsule())
                            }
                        }
                    }
                }

                if let note = place.statusNote {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundColor(BCTheme.amber)
                        Text(note)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(2)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BCTheme.amber.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Evaluación de Regla de Negocio: Disponibilidad de Ruta Ordinaria y Estado En Servicio
                switch notificationAvailability {
                case .available(let activeOrdinaryRoutes):
                    // Hay ruta(s) ordinaria(s) en servicio que pasan por este paradero: mostrar botón "Ir" + opción de "Notificación"
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
                            Text("Ir / Cómo llegar a este paradero (~\(estMinutes) min)")
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(BCTheme.cyanAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Button {
                        let primaryOrdCode = activeOrdinaryRoutes.first?.code ?? place.primaryRouteName
                        let asStop = BusStopModel(
                            id: place.id,
                            routeId: primaryOrdCode,
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
                                .foregroundColor(BCTheme.emerald)
                            Text("Activar Notificación de Llegada (\(activeOrdinaryRoutes.map(\.code).joined(separator: ", ")))")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(BCTheme.emerald.opacity(0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(BCTheme.emerald.opacity(0.45), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                case .ordinaryOutOfService(let registeredRoutes):
                    // El paradero tiene ruta ordinaria registrada, pero NO hay ruta ordinaria en servicio actualmente
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundColor(BCTheme.amber)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sin rutas ordinarias en servicio para este paradero")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(BCTheme.amber)
                            Text("La línea ordinaria registrada (\(registeredRoutes.map(\.code).joined(separator: ", "))) no tiene unidades en servicio en este momento. Notificación deshabilitada.")
                                .font(.system(size: 9.5))
                                .foregroundColor(.white.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BCTheme.amber.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(BCTheme.amber.opacity(0.4), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

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
                            Text("Ir / Punto de encuentro (\(place.totalDurationMinutes) min)")
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(BCTheme.cyanAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                case .noOrdinaryRoutes:
                    // No figura ninguna ruta ordinaria en este punto (solo rutas externas o punto de encuentro):
                    // NO se muestra opción de notificación, únicamente la opción de "Ir / Punto de encuentro"
                    HStack(spacing: 7) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(BCTheme.cyanAccent)
                        Text(
                            place.routesPassing.isEmpty
                                ? "Punto de encuentro • Sin rutas ordinarias trackeadas en este punto."
                                : "Solo rutas externas de referencia (Sin tracking GPS ni notificación)."
                        )
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                    }
                    .padding(.vertical, 4)

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
                            Text("Ir / Punto de encuentro (~\(estMinutes) min)")
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(BCTheme.cyanAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }

                // Opción universal para fijar cualquier punto/POI/paradero como Punto de Inicio (Origen)
                Button {
                    let chosenOrigin = place
                    selectedCatalogStop = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        viewModel.openRoutePlanner(
                            with: viewModel.routePlannerInitialDestination,
                            origin: chosenOrigin
                        )
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "location.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundColor(BCTheme.cyanAccent)
                        Text("Establecer como Punto de Inicio (Origen)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Capa de Mapa Nativo Interactivo y Contenido Vectorial
    private var interactiveMapLayer: some View {
        MapReader { mapProxy in
            Map(position: $cameraPosition) {
                mainMapContent
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .all))
            .ignoresSafeArea(edges: .top)
            .simultaneousGesture(
                SpatialTapGesture().onEnded { event in
                    guard isPinDropModeActive else { return }
                    if let coord = mapProxy.convert(event.location, from: .local) {
                        isPinDropModeActive = false
                        BCFeedbackManager.shared.impactMedium()
                        Task {
                            let resolved = await viewModel.reverseGeocodeCoordinateInTacna(coord, roleLabel: "Punto seleccionado")
                            await MainActor.run {
                                viewModel.searchedDestinationPin = resolved
                                selectedCatalogStop = resolved
                            }
                        }
                    }
                }
            )
            .onMapCameraChange(frequency: .continuous) {
                onDismissSearchFocus?()
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
            .onChange(of: viewModel.activeRouteOverlayOnMap?.id) { _, _ in
                guard let route = viewModel.activeRouteOverlayOnMap else {
                    projectedRouteStreetCoords = []
                    return
                }
                let rawCoords = route.resolvedPolylineCoordinates(using: viewModel.dynamicCatalogStops)
                projectedRouteStreetCoords = rawCoords
                if rawCoords.count <= route.keyStopIds.count + 2 && rawCoords.count >= 2 {
                    Task {
                        let aligned = await NativeStreetRouter.alignPolylineToStreets(
                            waypoints: rawCoords,
                            transportType: .automobile
                        )
                        await MainActor.run {
                            if viewModel.activeRouteOverlayOnMap?.id == route.id {
                                projectedRouteStreetCoords = aligned
                            }
                        }
                    }
                }
            }
            .onChange(of: viewModel.activeRouteGuidance) { _, newGuidance in
                guard let guidance = newGuidance else {
                    guidedWalkStreetCoords = []
                    guidedBusStreetCoords = []
                    guidedFinalWalkStreetCoords = []
                    return
                }
                let dest = guidance.destination
                let rawWalk = guidance.candidate?.walkToBoardCLCoordinates ?? dest.walkingToBoardCoordinates
                let rawBus = guidance.candidate?.busTransitCLCoordinates ?? dest.busTransitCoordinates
                let rawFinalWalk = guidance.candidate?.walkFinalCLCoordinates ?? []

                guidedWalkStreetCoords = rawWalk
                guidedBusStreetCoords = rawBus
                guidedFinalWalkStreetCoords = rawFinalWalk

                Task {
                    async let walkAligned = NativeStreetRouter.alignPolylineToStreets(
                        waypoints: rawWalk,
                        transportType: .walking
                    )
                    async let busAligned = (rawBus.count > 6)
                        ? rawBus
                        : await NativeStreetRouter.alignPolylineToStreets(
                            waypoints: rawBus,
                            transportType: .automobile
                        )
                    async let finalAligned = NativeStreetRouter.alignPolylineToStreets(
                        waypoints: rawFinalWalk,
                        transportType: .walking
                    )
                    let (wResult, bResult, fResult) = await (walkAligned, busAligned, finalAligned)
                    await MainActor.run {
                        if viewModel.activeRouteGuidance?.destination.id == dest.id {
                            guidedWalkStreetCoords = wResult
                            guidedBusStreetCoords = bResult
                            guidedFinalWalkStreetCoords = fResult
                        }
                    }
                }
            }
        }
    }

    @MapContentBuilder
    private var mainMapContent: some MapContent {
        UserAnnotation {
            ZStack {
                Circle()
                    .fill(BCTheme.cyanAccent.opacity(0.28))
                    .frame(width: 30, height: 30)
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.35), radius: 2)
                Circle()
                    .fill(BCTheme.royalBlue)
                    .frame(width: 12, height: 12)
            }
        }

        if let projectedRoute = viewModel.activeRouteOverlayOnMap {
            let fallbackCoords = projectedRoute.resolvedPolylineCoordinates(using: viewModel.dynamicCatalogStops)
            let coords = projectedRouteStreetCoords.count >= 2 ? projectedRouteStreetCoords : fallbackCoords
            if coords.count >= 2 {
                MapPolyline(coordinates: coords)
                    .stroke(
                        Color(hex: projectedRoute.colorHex),
                        style: StrokeStyle(
                            lineWidth: projectedRoute.isOrdinaryInService ? 6 : 4.5,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: projectedRoute.isOrdinaryInService ? [] : [8, 6]
                        )
                    )
            }
        } else if viewModel.mapCategory == .routes {
            ForEach(ordinaryRoutesInService) { route in
                let fallbackCoords = route.resolvedPolylineCoordinates(using: viewModel.dynamicCatalogStops)
                let cached = ordinaryRoutesStreetCoords[route.id] ?? []
                let coords = cached.count >= 2 ? cached : fallbackCoords
                if coords.count >= 2 {
                    MapPolyline(coordinates: coords)
                        .stroke(
                            Color(hex: route.colorHex),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                        )
                }
            }
        }

        ForEach(visibleCatalogStopsOnMap) { catalogStop in
            Annotation(catalogStop.shortName, coordinate: catalogStop.coordinate) {
                catalogStopAnnotationBadge(catalogStop)
            }
        }

        if let searchedPlace = viewModel.searchedDestinationPin {
            Annotation(searchedPlace.shortName, coordinate: searchedPlace.coordinate) {
                searchedDestinationAnnotationBadge(searchedPlace)
            }
        }

        if let guidance = viewModel.activeRouteGuidance {
            guidanceMapContent(for: guidance)
        }

        ForEach(viewModel.filteredBuses) { bus in
            Annotation("\(bus.unitNumber) · \(bus.plate)", coordinate: bus.coordinate) {
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
                .contentShape(Circle())
                .simultaneousGesture(
                    TapGesture().onEnded {
                        BCFeedbackManager.shared.impactLight()
                        selectedBus = bus
                    }
                )
            }
        }
    }

    private func catalogStopAnnotationBadge(_ catalogStop: TacnaDestinationPlace) -> some View {
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
                Image(systemName: catalogStop.resolvedIconName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
            .contentShape(Circle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    BCFeedbackManager.shared.impactLight()
                    selectedCatalogStop = catalogStop
                }
            )

            Text(catalogStop.shortName)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(BCTheme.elevatedSurface.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .allowsHitTesting(false)
        }
    }

    private func searchedDestinationAnnotationBadge(_ searchedPlace: TacnaDestinationPlace) -> some View {
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
            .contentShape(Circle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    selectedCatalogStop = searchedPlace
                }
            )
        }
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

    // MARK: - Contenido del Mapa para Guía de Ruta Activa
    @MapContentBuilder
    private func guidanceMapContent(for guidance: ActiveRouteGuidanceState) -> some MapContent {
        let orig = guidance.origin
        let dest = guidance.destination
        let cand = guidance.candidate
        let fallbackWalk = cand?.walkToBoardCLCoordinates ?? dest.walkingToBoardCoordinates
        let fallbackBus = cand?.busTransitCLCoordinates ?? dest.busTransitCoordinates
        let fallbackFinalWalk = cand?.walkFinalCLCoordinates ?? []

        let walkCoords = guidedWalkStreetCoords.count >= 2 ? guidedWalkStreetCoords : fallbackWalk
        let busCoords = guidedBusStreetCoords.count >= 2 ? guidedBusStreetCoords : fallbackBus
        let finalWalkCoords = guidedFinalWalkStreetCoords.count >= 2 ? guidedFinalWalkStreetCoords : fallbackFinalWalk

        // Pin de Punto de Inicio (Origen establecido por el usuario o GPS)
        Annotation(orig.shortName, coordinate: orig.coordinate) {
            HStack(spacing: 4) {
                Circle()
                    .fill(BCTheme.royalBlue)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                Text("Inicio: \(orig.shortName)")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(BCTheme.elevatedSurface.opacity(0.95))
                    .clipShape(Capsule())
            }
        }

        // Tramo 1: Caminata hacia el paradero o punto de vía (Cian punteado siguiendo calles)
        if walkCoords.count >= 2 {
            MapPolyline(coordinates: walkCoords)
                .stroke(
                    BCTheme.cyanAccent,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [6, 6])
                )
        }

        // Tramo 2: Recorrido en Bus (Ordinaria o Externa)
        if let cand = cand, cand.kind != .walkingDirect, busCoords.count >= 2 {
            let isOrd = cand.kind == .ordinaryInService
            MapPolyline(coordinates: busCoords)
                .stroke(
                    Color(hex: isOrd ? "#00E5FF" : cand.colorHex),
                    style: StrokeStyle(
                        lineWidth: 6.5,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: isOrd ? [] : [10, 6]
                    )
                )

            // Punto de abordaje (solo punto con signo de paradero, sin texto)
            Annotation("", coordinate: cand.boardingCoordinate) {
                TransitStopDotMarker(accentColor: isOrd ? BCTheme.emerald : BCTheme.amber)
            }

            // Punto de bajada (solo punto con signo de paradero, sin texto)
            Annotation("", coordinate: cand.alightingCoordinate) {
                TransitStopDotMarker(accentColor: BCTheme.cyanAccent)
            }
        } else if cand == nil && dest.routeCase != .walkOnlyNearby && guidance.selectedOptionIndex != 3 {
            MapPolyline(coordinates: busCoords)
                .stroke(
                    Color(hex: "#00E5FF"),
                    style: StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round)
                )
        }

        // Tramo 3: Caminata final desde el paradero/punto de bajada hasta el destino final
        if finalWalkCoords.count >= 2 {
            MapPolyline(coordinates: finalWalkCoords)
                .stroke(
                    BCTheme.cyanAccent,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [6, 6])
                )
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

    private func chipTitle(for category: MapFilterCategory) -> String {
        switch category {
        case .live:
            return viewModel.activeBuses.isEmpty ? "En vivo" : "En vivo (\(viewModel.activeBuses.count))"
        case .routes:
            return "Rutas (\(ordinaryRoutesInService.count))"
        case .stops:
            return "Paraderos (\(viewModel.dynamicCatalogStops.count))"
        }
    }

    private func preloadOrdinaryRoutesStreetAlignment() async {
        let activeRoutes = ordinaryRoutesInService
        for route in activeRoutes {
            if ordinaryRoutesStreetCoords[route.id]?.count ?? 0 >= 2 {
                continue
            }
            let rawCoords = route.resolvedPolylineCoordinates(using: viewModel.dynamicCatalogStops)
            guard rawCoords.count >= 2 else { continue }
            if rawCoords.count <= route.keyStopIds.count + 2 {
                let aligned = await NativeStreetRouter.alignPolylineToStreets(
                    waypoints: rawCoords,
                    transportType: .automobile
                )
                await MainActor.run {
                    ordinaryRoutesStreetCoords[route.id] = aligned
                }
            } else {
                await MainActor.run {
                    ordinaryRoutesStreetCoords[route.id] = rawCoords
                }
            }
        }
    }

    private func iconForCategory(_ category: MapFilterCategory) -> String {
        switch category {
        case .live: return "dot.radiowaves.left.and.right"
        case .routes: return "point.topleft.down.curvedto.point.bottomright.up"
        case .stops: return "mappin.and.ellipse"
        }
    }

    private func colorForCategory(_ category: MapFilterCategory) -> Color {
        switch category {
        case .live: return BCTheme.royalBlue
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

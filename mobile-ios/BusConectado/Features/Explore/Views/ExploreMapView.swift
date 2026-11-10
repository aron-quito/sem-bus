import SwiftUI
import MapKit

struct ExploreMapView: View {
    @ObservedObject var viewModel: AuthViewModel
    var onDismissSearchFocus: (() -> Void)? = nil

    @State private var selectedStop: BusStopModel? = nil
    @State private var selectedBus: ActiveBusModel? = nil
    @State private var selectedAdvanceMinutes: Int = 5
    @State private var imminentAlertEnabled: Bool = true

    // Estado de arrastre para retirar con un gesto el pop-up "Sin paraderos ni buses en camino"
    @State private var emptyBannerDragOffset: CGSize = .zero
    @State private var timerPulseAnimation: Bool = false

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -18.0132, longitude: -70.2512), // Centro Histórico de Tacna
            span: MKCoordinateSpan(latitudeDelta: 0.022, longitudeDelta: 0.022)
        )
    )

    var body: some View {
        ZStack(alignment: .top) {
            // 1. Mapa Nativo de Tacna
            Map(position: $cameraPosition) {
                // Marcador Pulsante de Ubicación del Usuario ("Tu ubicación" en Tacna)
                Annotation("Tu ubicación", coordinate: TacnaDestinationPlace.userOriginCoordinate) {
                    ZStack {
                        Circle()
                            .fill(BCTheme.royalBlue.opacity(0.24))
                            .frame(width: 34, height: 34)
                        Circle()
                            .fill(BCTheme.royalBlue)
                            .frame(width: 15, height: 15)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 2.5)
                            )
                            .shadow(color: BCTheme.royalBlue.opacity(0.6), radius: 4)
                    }
                }

                // Pin Rojo Dinámico cuando el usuario selecciona un lugar desde el Buscador Predictivo
                if let searchedPlace = viewModel.searchedDestinationPin {
                    Annotation(searchedPlace.shortName, coordinate: searchedPlace.coordinate) {
                        Button {
                            viewModel.openRoutePlanner(with: searchedPlace)
                        } label: {
                            VStack(spacing: 3) {
                                HStack(spacing: 5) {
                                    Text(searchedPlace.shortName)
                                        .font(.system(size: 10, weight: .heavy))
                                        .foregroundColor(.white)
                                    Text("Ir ↱")
                                        .font(.system(size: 9, weight: .black))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(BCTheme.cyanAccent)
                                        .clipShape(Capsule())
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(BCTheme.destructiveRed)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
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

                    // Tramo 2: Recorrido en Bus Línea 10 (Cian/Azul brillante continuo)
                    if dest.routeCase != .walkOnlyPlazaZela && guidance.selectedOptionIndex != 3 {
                        MapPolyline(coordinates: dest.busTransitCoordinates)
                            .stroke(
                                Color(hex: "#00E5FF"),
                                style: StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round)
                            )

                        // Punto de abordaje en Plaza Zela
                        Annotation("Abordaje Plaza Zela", coordinate: TacnaDestinationPlace.plazaZelaCoordinate) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(BCTheme.royalBlue)
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                Text("Abordar aquí")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(BCTheme.elevatedSurface.opacity(0.95))
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    // Tramo 3: Caminata final al destino (si aplica)
                    if !dest.walkingFinalCoordinates.isEmpty {
                        MapPolyline(coordinates: dest.walkingFinalCoordinates)
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

                // Marcadores dinámicos de Paraderos Oficiales (Vacío en cuentas de prueba hasta que se implementen)
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

                // Marcadores dinámicos de Buses en Camino (Vacío en cuentas de prueba hasta que se implementen)
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
            .simultaneousGesture(
                TapGesture().onEnded {
                    onDismissSearchFocus?()
                }
            )
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

            // 2. Capas Flotantes Superiores e Inferiores sobre el Mapa
            VStack(spacing: 10) {
                // Barra Superior de Filtros (Todo, Rutas, Paraderos) + Botón Sincronizar
                HStack(spacing: 8) {
                    ForEach(MapFilterCategory.allCases, id: \.self) { category in
                        let isSelected = viewModel.mapCategory == category
                        Button {
                            BCFeedbackManager.shared.impactLight()
                            onDismissSearchFocus?()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.mapCategory = category
                            }
                        } label: {
                            Text(category.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(isSelected ? .white : .white.opacity(0.75))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(isSelected ? BCTheme.royalBlue : BCTheme.elevatedSurface.opacity(0.92))
                                .overlay(
                                    Capsule()
                                        .stroke(BCTheme.hairlineBorder, lineWidth: 1)
                                )
                                .clipShape(Capsule())
                        }
                    }

                    Spacer()

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
                        .background(BCTheme.elevatedSurface.opacity(0.94))
                        .overlay(
                            Capsule()
                                .stroke(BCTheme.cyanAccent.opacity(0.35), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

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

                // 3. Controles Flotantes Inferiores Derecha: Botón Ubicación + Botón Cian "Ir / Cómo Llegar"
                HStack(alignment: .bottom) {
                    Spacer()

                    VStack(spacing: 12) {
                        // Botón Centrar Mi Ubicación (Estilo Mockup)
                        Button {
                            onDismissSearchFocus?()
                            viewModel.centerMapOnUserLocation()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(BCTheme.elevatedSurface.opacity(0.96))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Circle()
                                            .stroke(Color(hex: "#334155"), lineWidth: 1.2)
                                    )

                                ZStack {
                                    Circle()
                                        .stroke(Color.white.opacity(0.85), lineWidth: 2)
                                        .frame(width: 20, height: 20)
                                    Circle()
                                        .fill(BCTheme.royalBlue)
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                        }
                        .accessibilityLabel("Centrar mi ubicación")

                        // Botón FAB Cian Cuadrado Redondeado "Ir / Cómo Llegar" (#fab-directions en el Mockup)
                        Button {
                            onDismissSearchFocus?()
                            viewModel.openRoutePlanner(with: viewModel.searchedDestinationPin)
                        } label: {
                            VStack(spacing: 2) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color(hex: "#090D16"))
                                        .frame(width: 24, height: 24)
                                    Image(systemName: "arrow.turn.up.right")
                                        .font(.system(size: 13, weight: .black))
                                        .foregroundColor(BCTheme.cyanAccent)
                                }
                                Text("Ir")
                                    .font(.system(size: 9.5, weight: .black))
                                    .foregroundColor(Color(hex: "#090D16"))
                            }
                            .frame(width: 52, height: 52)
                            .background(BCTheme.cyanAccent)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.55), lineWidth: 1.2)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: BCTheme.cyanAccent.opacity(0.45), radius: 10, y: 4)
                        }
                        .accessibilityLabel("Ir / Cómo llegar")
                    }
                    .padding(.trailing, 16)
                }
                .padding(.bottom, (viewModel.stops.isEmpty && viewModel.activeBuses.isEmpty && !viewModel.isEmptyTransitBannerDismissed) ? 4 : 18)

                // 4. Pop-up "Sin paraderos ni buses en camino" Retirable con un Gesto (Deslizar o pulsar [✕])
                if viewModel.stops.isEmpty && viewModel.activeBuses.isEmpty && !viewModel.isEmptyTransitBannerDismissed {
                    emptyTransitStatusCard
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(item: $selectedStop) { stop in
            stopDetailSheet(stop)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedBus) { bus in
            busTechnicalSheet(bus)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
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

    // MARK: - Widget Circular Verde de Timer + Botón Rojo de Cancelación (#guide-timer-widget)
    private func guidedRouteTimerWidget(_ guidance: ActiveRouteGuidanceState) -> some View {
        VStack(spacing: 8) {
            // Badge Circular Verde con Pulso
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

            // Botón Circular Rojo de Cancelación [✕] directamente debajo del Timer Verde
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
            // Indicador superior de gesto para deslizar
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
                        Text("Sin paraderos ni buses en camino")
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

                    Text("Cuenta de prueba activa. Desliza esta tarjeta hacia abajo o a los lados para ocultarla y explorar el mapa.")
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

    // MARK: - Ficha de Paradero con Configurador de 2 Timers (Lista para cuando existan paraderos)
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
                    Text("Línea 10")
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

    // MARK: - Ficha Técnica del Bus (Lista para cuando existan unidades en ruta)
    private func busTechnicalSheet(_ bus: ActiveBusModel) -> some View {
        ZStack {
            BCTheme.elevatedSurface.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Línea \(bus.lineNumber) · \(bus.unitNumber)")
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

    private func formatSeconds(_ total: Int) -> String {
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

import SwiftUI
import MapKit

enum RoutePlannerScreenState {
    case selector   // Estado 1: Selector de Origen/Destino y Recientes (#gm-state-selector)
    case search     // Estado 2: Buscador de Destino con Teclado (#gm-state-search)
    case routeMap   // Estados 3, 4 y 5: Mapa de Ruta + Bottom Sheet de 3 Niveles (#gm-state-route)
}

enum RouteSheetSnapLevel: CaseIterable {
    case compact    // Nivel 1: Compacto (Peek ~185pt)
    case medium     // Nivel 2: Detalle Intermedio (Medium ~380pt)
    case full       // Nivel 3: Todas las Opciones (Full ~600pt)

    func height(in totalHeight: CGFloat) -> CGFloat {
        switch self {
        case .compact:
            return 190
        case .medium:
            return min(max(totalHeight * 0.48, 360), 430)
        case .full:
            return totalHeight * 0.82
        }
    }

    var nextLevel: RouteSheetSnapLevel {
        switch self {
        case .compact: return .medium
        case .medium: return .full
        case .full: return .compact
        }
    }
}

enum RouteQuickFilter: String, CaseIterable {
    case fastest = "Más rápida"
    case fewerTransfers = "Menos trasbordos"
    case freeSeats = "Asientos libres"
}

struct RoutePlannerView: View {
    @ObservedObject var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var screenState: RoutePlannerScreenState = .selector
    @State private var selectedDestination: TacnaDestinationPlace = TacnaDestinationPlace.catalog[0] // Mercado Central por defecto
    @State private var isEndpointsSwapped: Bool = false
    @State private var selectedTransportTab: Int = 0 // 0 = Bus, 1 = A pie
    @State private var destinationSearchText: String = ""
    @FocusState private var isSearchInputFocused: Bool

    // Estado de la Hoja Inferior de 3 Niveles (Peek / Medium / Full)
    @State private var sheetSnap: RouteSheetSnapLevel = .compact
    @State private var sheetDragTranslation: CGFloat = 0
    @State private var selectedOptionIndex: Int = 1 // 1 = Ruta principal (Recomendada), 2 = Ruta alterna, 3 = Caminata directa
    @State private var selectedFilter: RouteQuickFilter = .fastest

    @State private var routeMapCamera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -18.0145, longitude: -70.2518),
            span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
        )
    )

    var body: some View {
        ZStack {
            Color(hex: "#1C1C1E")
                .ignoresSafeArea()

            switch screenState {
            case .selector:
                selectorScreenView
                    .transition(.opacity)
            case .search:
                searchScreenView
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .routeMap:
                routeMapScreenView
                    .transition(.opacity)
            }
        }
        .onAppear {
            if let initial = viewModel.routePlannerInitialDestination {
                selectedDestination = initial
                screenState = .routeMap
                updateCameraForDestination(initial)
            } else {
                screenState = .selector
            }
        }
    }

    // MARK: - ESTADO 1: Selector de Origen / Destino y Recientes (#gm-state-selector)
    private var selectorScreenView: some View {
        VStack(spacing: 0) {
            // Cabecera con botón Volver y Tarjeta de Origen / Destino
            HStack(alignment: .center, spacing: 10) {
                Button {
                    BCFeedbackManager.shared.impactLight()
                    dismiss()
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(Color(hex: "#2C2C2E"))
                        .clipShape(Circle())
                }

                VStack(spacing: 0) {
                    // Fila Origen
                    HStack(spacing: 10) {
                        Circle()
                            .stroke(Color(hex: "#60A5FA"), lineWidth: 2.5)
                            .frame(width: 10, height: 10)

                        Text(isEndpointsSwapped ? selectedDestination.shortName : "Tu ubicación")
                            .font(.footnote.weight(.medium))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Spacer()

                        Button {
                            BCFeedbackManager.shared.impactLight()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isEndpointsSwapped.toggle()
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white.opacity(0.65))
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    Divider()
                        .background(Color(hex: "#3A3A3C"))
                        .padding(.horizontal, 12)

                    // Fila Destino
                    Button {
                        BCFeedbackManager.shared.impactLight()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            screenState = .search
                            isSearchInputFocused = true
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.caption.weight(.bold))
                                .foregroundColor(Color(hex: "#FB7185"))

                            Text("Elige un destino ›")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.6))

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                }
                .background(Color(hex: "#2C2C2E"))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            // Pestañas de Modo de Transporte (Bus / A pie)
            HStack(spacing: 12) {
                Button {
                    BCFeedbackManager.shared.impactLight()
                    selectedTransportTab = 0
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "bus.fill")
                            .font(.subheadline)
                        Text("Bus")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(selectedTransportTab == 0 ? Color(hex: "#0A84FF") : Color(hex: "#2C2C2E"))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button {
                    BCFeedbackManager.shared.impactLight()
                    selectedTransportTab = 1
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "figure.walk")
                            .font(.subheadline)
                        Text("A pie")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(selectedTransportTab == 1 ? .white : .white.opacity(0.65))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(selectedTransportTab == 1 ? Color(hex: "#0A84FF") : Color(hex: "#2C2C2E"))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            // Accesos Rápidos (Casa / Trabajo)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    savedPlacePill(icon: "house.fill", title: "Casa", subtitle: "Definir lugar") {
                        selectDestinationAndShowRoute(TacnaDestinationPlace.catalog[1]) // Mercado 2 de Mayo
                    }
                    savedPlacePill(icon: "briefcase.fill", title: "Universidad / Trabajo", subtitle: "Campus UNJBG") {
                        selectDestinationAndShowRoute(TacnaDestinationPlace.catalog.first(where: { $0.id == "stop-unjbg" }) ?? TacnaDestinationPlace.catalog[0])
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 14)

            // Título Recientes
            HStack {
                Text("Recientes y Paraderos en Tacna")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.45))
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 8)

            // Lista de Destinos Recientes y Paraderos Sincronizados
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.dynamicCatalogStops) { place in
                        Button {
                            selectDestinationAndShowRoute(place)
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: "#2C2C2E"))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: "clock")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.65))
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(place.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.white)
                                        .lineLimit(1)

                                    if let note = place.statusNote {
                                        Text(note)
                                            .font(.caption)
                                            .foregroundColor(Color.orange)
                                            .lineLimit(1)
                                    } else {
                                        Text(place.subtitle)
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.5))
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                Image(systemName: "arrow.up.left")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.35))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                        }

                        Divider()
                            .background(Color(hex: "#2C2C2E"))
                            .padding(.leading, 68)
                    }
                }
            }
        }
    }

    // MARK: - ESTADO 2: Buscador de Destino con Teclado (#gm-state-search)
    private var searchScreenView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    BCFeedbackManager.shared.impactLight()
                    isSearchInputFocused = false
                    withAnimation(.easeInOut(duration: 0.2)) {
                        screenState = .selector
                    }
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(Color(hex: "#2C2C2E"))
                        .clipShape(Circle())
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))

                    TextField("Elige un destino en Tacna", text: $destinationSearchText)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .focused($isSearchInputFocused)
                        .autocorrectionDisabled()

                    if !destinationSearchText.isEmpty {
                        Button {
                            destinationSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.6))
                        }
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(Color(hex: "#2C2C2E"))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            // Opción "Elegir en el mapa"
            Button {
                selectDestinationAndShowRoute(selectedDestination)
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#2C2C2E"))
                            .frame(width: 36, height: 36)
                        Image(systemName: "mappin.and.ellipse")
                            .font(.subheadline)
                            .foregroundColor(BCTheme.cyanAccent)
                    }
                    Text("Elegir en el mapa")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(hex: "#1C1C1E"))
            }

            Divider().background(Color(hex: "#2C2C2E"))

            // Resultados Filtrados
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredDestinationsInPlanner) { place in
                        Button {
                            isSearchInputFocused = false
                            selectDestinationAndShowRoute(place)
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: "#2C2C2E"))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: place.iconName)
                                        .font(.subheadline)
                                        .foregroundColor(Color(hex: place.iconColorHex))
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(place.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.white)
                                    Text(place.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.55))
                                }

                                Spacer()

                                Text("\(place.totalDurationMinutes) min")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundColor(BCTheme.emerald)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }

                        Divider()
                            .background(Color(hex: "#2C2C2E"))
                            .padding(.leading, 68)
                    }
                }
            }
        }
    }

    // MARK: - ESTADOS 3, 4 y 5: Mapa de Ruta + Hoja Inferior Interactiva de 3 Niveles (#gm-state-route)
    private var routeMapScreenView: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // 1. Mapa de Fondo con Polilíneas Multimodales (Caminata + Bus + Pin Rojo)
                Map(position: $routeMapCamera) {
                    // Pin de Origen ("Tu ubicación")
                    Annotation("Tu ubicación", coordinate: TacnaDestinationPlace.userOriginCoordinate) {
                        VStack(spacing: 2) {
                            Text("Tu ubicación")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(BCTheme.royalBlue)
                                .clipShape(RoundedRectangle(cornerRadius: 5))

                            ZStack {
                                Circle()
                                    .fill(BCTheme.royalBlue.opacity(0.28))
                                    .frame(width: 28, height: 28)
                                Circle()
                                    .fill(BCTheme.royalBlue)
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            }
                        }
                    }

                    // Tramo 1: Caminata hacia el Paradero Plaza Zela (Punteado Cian)
                    MapPolyline(coordinates: selectedDestination.walkingToBoardCoordinates)
                        .stroke(
                            BCTheme.cyanAccent,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [6, 7])
                        )

                    // Si el destino usa Bus (Caso 2 y Caso 3) y no eligió la Opción 3 (Caminata Directa)
                    if selectedDestination.routeCase != .walkOnlyNearby && selectedOptionIndex != 3 {
                        // Tramo 2: Recorrido en Bus (Azul Eléctrico continuo)
                        MapPolyline(coordinates: selectedDestination.busTransitCoordinates)
                            .stroke(
                                BCTheme.royalBlue,
                                style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                            )

                        // Marcador de Paradero de Abordaje
                        Annotation(selectedDestination.boardingStopName, coordinate: selectedDestination.boardingCoordinate) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(BCTheme.royalBlue)
                                    .frame(width: 18, height: 18)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))

                                Text("Subir aquí: \(selectedRouteLabel)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(BCTheme.emerald)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color(hex: "#052E16").opacity(0.95))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(BCTheme.emerald.opacity(0.7), lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }

                        // Marcador de Parada Intermedia (si la ruta pasa por un paradero clave antes del destino)
                        if let intermediate = selectedDestination.intermediateStopName,
                           selectedDestination.busTransitCoordinates.count >= 2 {
                            Annotation(intermediate, coordinate: selectedDestination.busTransitCoordinates[1]) {
                                Text("Parada intermedia • \(intermediate)")
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.85))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(BCTheme.elevatedSurface.opacity(0.95))
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                        }
                    }

                    // Tramo 3: Caminata final desde el paradero de bajada hasta el destino (si aplica)
                    if !selectedDestination.walkingFinalCoordinates.isEmpty {
                        MapPolyline(coordinates: selectedDestination.walkingFinalCoordinates)
                            .stroke(
                                BCTheme.cyanAccent,
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [6, 7])
                            )
                    }

                    // Pin Rojo de Destino Final
                    Annotation(selectedDestination.shortName, coordinate: selectedDestination.coordinate) {
                        VStack(spacing: 3) {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 9, weight: .bold))
                                Text("\(selectedDestination.shortName) (Destino)")
                                    .font(.system(size: 9.5, weight: .heavy))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(BCTheme.destructiveRed)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .shadow(radius: 4)

                            ZStack {
                                Circle()
                                    .fill(BCTheme.destructiveRed)
                                    .frame(width: 22, height: 22)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 7, height: 7)
                            }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
                .ignoresSafeArea()

                // 2. Cabecera Flotante Opaca de Ruteo (Sin transparencias con la barra de estado)
                floatingRouteHeader

                // 3. Botón Flotante de Mi Ubicación en el Mapa de Ruta
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            BCFeedbackManager.shared.impactLight()
                            updateCameraForDestination(selectedDestination)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(BCTheme.elevatedSurface.opacity(0.96))
                                    .frame(width: 42, height: 42)
                                    .overlay(
                                        Circle()
                                            .stroke(BCTheme.hairlineBorder, lineWidth: 1)
                                    )
                                Image(systemName: "location.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(BCTheme.royalBlue)
                            }
                            .shadow(color: .black.opacity(0.45), radius: 6)
                        }
                        .padding(.trailing, 14)
                        .padding(.bottom, currentSheetHeight(in: geo.size.height) + 14)
                    }
                }

                // 4. Hoja Inferior Interactiva de 3 Niveles (Compacto / Medio / Completo)
                VStack {
                    Spacer()
                    interactiveBottomSheet(totalHeight: geo.size.height)
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    // MARK: - Cabecera Superior de Ruteo + Píldora Multimodal (#gm-route-steps-bar)
    private var floatingRouteHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                // Botón Retroceso [<]
                Button {
                    BCFeedbackManager.shared.impactLight()
                    if viewModel.routePlannerInitialDestination != nil {
                        dismiss()
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            screenState = .selector
                        }
                    }
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(Color(hex: "#1E293B"))
                        .overlay(Circle().stroke(Color(hex: "#334155"), lineWidth: 1))
                        .clipShape(Circle())
                }

                // Puntos guía verticales (Origen -> Destino)
                VStack(spacing: 3) {
                    Circle()
                        .stroke(Color(hex: "#60A5FA"), lineWidth: 2)
                        .frame(width: 9, height: 9)
                    Circle().fill(Color.gray.opacity(0.6)).frame(width: 2.5, height: 2.5)
                    Circle().fill(Color.gray.opacity(0.6)).frame(width: 2.5, height: 2.5)
                    Circle().fill(Color.gray.opacity(0.6)).frame(width: 2.5, height: 2.5)
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "#FB7185"))
                }

                // Textos de Origen y Destino
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation { screenState = .selector }
                    } label: {
                        Text(isEndpointsSwapped ? selectedDestination.shortName : "Tu ubicación")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color(hex: "#60A5FA"))
                            .lineLimit(1)
                    }

                    Divider().background(Color.white.opacity(0.1))

                    Button {
                        withAnimation {
                            screenState = .search
                            isSearchInputFocused = true
                        }
                    } label: {
                        HStack {
                            Text(isEndpointsSwapped ? "Tu ubicación" : selectedDestination.name)
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                }

                // Botones de Opciones [...] e Inversión [⇅]
                VStack(spacing: 6) {
                    Button {
                        BCFeedbackManager.shared.impactLight()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            sheetSnap = .full
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 28, height: 28)
                            .background(Color(hex: "#1E293B"))
                            .clipShape(Circle())
                    }

                    Button {
                        BCFeedbackManager.shared.impactLight()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isEndpointsSwapped.toggle()
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 28, height: 28)
                            .background(Color(hex: "#1E293B"))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(12)
            .background(BCTheme.elevatedSurface.opacity(0.98))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(BCTheme.hairlineBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            // Píldora Multimodal Flotante (#gm-route-steps-bar)
            HStack(spacing: 6) {
                if selectedDestination.routeCase == .walkOnlyNearby || selectedOptionIndex == 3 {
                    HStack(spacing: 5) {
                        Image(systemName: "figure.walk")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(BCTheme.cyanAccent)
                        Text("\(activeDurationMinutes) min a pie · \(selectedDestination.distanceLabel)")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(BCTheme.cyanAccent)
                    }
                    Spacer()
                    Text("Sin costo (Gratis)")
                        .font(.caption2.weight(.heavy).monospaced())
                        .foregroundColor(BCTheme.emerald)
                } else {
                    HStack(spacing: 5) {
                        Label("\(selectedDestination.walkInitialMinutes)m", systemImage: "figure.walk")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(BCTheme.cyanAccent)

                        Text("➔")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)

                        HStack(spacing: 4) {
                            Image(systemName: "bus.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("\(selectedRouteLabel) (\(selectedDestination.busRideMinutes)m)")
                                .font(.system(size: 10, weight: .bold).monospaced())
                        }
                        .foregroundColor(Color(hex: "#93C5FD"))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(hex: "#172554"))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(BCTheme.royalBlue.opacity(0.6), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 5))

                        if selectedDestination.walkFinalMinutes > 0 {
                            Text("➔")
                                .font(.system(size: 9))
                                .foregroundColor(.gray)

                            Label("\(selectedDestination.walkFinalMinutes)m", systemImage: "figure.walk")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(BCTheme.cyanAccent)
                        }
                    }

                    Spacer()

                    Text("\(activeDurationMinutes) min · \(formattedUserFare)")
                        .font(.caption2.weight(.heavy).monospaced())
                        .foregroundColor(BCTheme.emerald)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(BCTheme.elevatedSurface.opacity(0.96))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(BCTheme.hairlineBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(
            BCTheme.background.opacity(0.95)
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - Hoja Inferior Interactiva de 3 Niveles (#gmaps-bottom-sheet)
    private func interactiveBottomSheet(totalHeight: CGFloat) -> some View {
        let targetHeight = currentSheetHeight(in: totalHeight)

        return VStack(spacing: 0) {
            // Barra de Arrastre (Drag Handle + Toque para alternar entre los 3 niveles)
            Button {
                BCFeedbackManager.shared.impactLight()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    sheetSnap = sheetSnap.nextLevel
                }
            } label: {
                VStack(spacing: 4) {
                    Capsule()
                        .fill(Color(hex: "#48484A"))
                        .frame(width: 42, height: 5)
                        .padding(.top, 10)

                    Text(sheetSnapLabel)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.bottom, 4)
                }
                .frame(maxWidth: .infinity)
            }

            switch sheetSnap {
            case .compact:
                compactSheetContent
            case .medium:
                mediumSheetContent
            case .full:
                fullSheetContent
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: targetHeight)
        .background(Color(hex: "#1C1C1E"))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color(hex: "#2C2C2E"), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 18, y: -4)
        .gesture(
            DragGesture()
                .onChanged { value in
                    sheetDragTranslation = value.translation.height
                }
                .onEnded { value in
                    let dy = value.translation.height
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        if dy < -45 {
                            if sheetSnap == .compact {
                                sheetSnap = .medium
                            } else if sheetSnap == .medium {
                                sheetSnap = .full
                            }
                        } else if dy > 45 {
                            if sheetSnap == .full {
                                sheetSnap = .medium
                            } else if sheetSnap == .medium {
                                sheetSnap = .compact
                            }
                        }
                        sheetDragTranslation = 0
                    }
                    BCFeedbackManager.shared.impactLight()
                }
        )
    }

    // ——— NIVEL 1: COMPACTO (Peek) ———
    private var compactSheetContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Pestañas de Duración Rápida
            HStack(spacing: 18) {
                durationTabPill(minutes: selectedDestination.totalDurationMinutes, index: 1)
                if selectedDestination.routeCase != .walkOnlyNearby {
                    durationTabPill(minutes: selectedDestination.secondaryDurationMinutes, index: 2)
                    durationTabPill(minutes: selectedDestination.walkingDirectMinutes, index: 3)
                }
                Spacer()
            }

            // Fila de Tiempo, Distancia, Compartir y Cerrar
            HStack {
                HStack(spacing: 4) {
                    Text("\(activeDurationMinutes) min · ")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                    Text(selectedDestination.distanceLabel)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        BCFeedbackManager.shared.impactLight()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 34, height: 34)
                            .background(Color(hex: "#2C2C2E"))
                            .clipShape(Circle())
                    }

                    Button {
                        BCFeedbackManager.shared.impactLight()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 34, height: 34)
                            .background(Color(hex: "#2C2C2E"))
                            .clipShape(Circle())
                    }
                }
            }

            // Botones de Acción: [Iniciar] (Verde) + [ETA]
            HStack(spacing: 10) {
                Button {
                    viewModel.startGuidedRoute(to: selectedDestination, optionIndex: selectedOptionIndex)
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "location.north.fill")
                            .font(.subheadline.weight(.bold))
                        Text("Iniciar")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color(hex: "#34C759"))
                    .clipShape(Capsule())
                }

                Button {
                    BCFeedbackManager.shared.impactLight()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        sheetSnap = .medium
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.caption.weight(.bold))
                        Text("ETA")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Color(hex: "#2C2C2E"))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 18)
    }

    // ——— NIVEL 2: DETALLE INTERMEDIO (Medium) ———
    private var mediumSheetContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                // Selector de Modo
                HStack(spacing: 20) {
                    Button {
                        selectedOptionIndex = 1
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "bus.fill")
                                .foregroundColor(selectedOptionIndex != 3 ? Color(hex: "#0A84FF") : .gray)
                            Text("\(selectedDestination.totalDurationMinutes) min")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white)
                            Rectangle()
                                .fill(selectedOptionIndex != 3 ? Color(hex: "#0A84FF") : Color.clear)
                                .frame(width: 44, height: 2)
                        }
                    }

                    Button {
                        selectedOptionIndex = 3
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "figure.walk")
                                .foregroundColor(selectedOptionIndex == 3 ? Color(hex: "#0A84FF") : .gray)
                            Text("\(selectedDestination.walkingDirectMinutes) min")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.65))
                            Rectangle()
                                .fill(selectedOptionIndex == 3 ? Color(hex: "#0A84FF") : Color.clear)
                                .frame(width: 44, height: 2)
                        }
                    }

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            sheetSnap = .full
                        }
                    } label: {
                        Text("Todas las opciones ›")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color(hex: "#0A84FF"))
                    }
                }
                .padding(.bottom, 4)

                // Gran indicador de Tiempo y Ahorro Ecológico
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(activeDurationMinutes) min")
                        .font(.title2.weight(.black))
                        .foregroundColor(.white)
                    Text("Ruta recomendada · \(selectedDestination.distanceLabel) · 🌿 Ahorra 6% combustible")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.65))
                }

                // Tarjeta de Próximo Bus / Estado de Flota
                VStack(alignment: .leading, spacing: 4) {
                    if selectedDestination.routeCase == .walkOnlyNearby || selectedOptionIndex == 3 {
                        Text("🚶‍♂️ Trayecto directo a pie")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white)
                        Text("Camina directamente hacia \(selectedDestination.shortName) (\(selectedDestination.distanceLabel)) sin necesidad de abordar bus.")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.65))
                    } else {
                        HStack {
                            Text("🚌 Próximo bus · \(selectedRouteLabel)")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white)
                            Spacer()
                            if viewModel.activeBuses.isEmpty {
                                Text("Cuenta Prueba")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(BCTheme.amber)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(BCTheme.amber.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                        Text("Abordaje en \(selectedDestination.boardingStopName) · \(liveEtaShortLabel)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.75))
                        Text("Descenso en \(selectedDestination.alightingStopName) · Tarifa aplicable: \(formattedUserFare)")
                            .font(.caption2)
                            .foregroundColor(BCTheme.emerald)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "#2C2C2E"))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                // Desglose Paso a Paso Legible
                VStack(alignment: .leading, spacing: 8) {
                    stepRow(
                        icon: "figure.walk",
                        bgHex: "#1E3A8A",
                        iconColor: Color(hex: "#93C5FD"),
                        text: "Camina \(selectedDestination.walkInitialMinutes) min hasta \(selectedDestination.boardingStopName)"
                    )

                    if selectedDestination.routeCase != .walkOnlyNearby && selectedOptionIndex != 3 {
                        stepRow(
                            icon: "bus.fill",
                            bgHex: "#14532D",
                            iconColor: Color(hex: "#86EFAC"),
                            text: "Toma \(selectedRouteLabel) · \(formattedUserFare)"
                        )

                        stepRow(
                            icon: "mappin.and.ellipse",
                            bgHex: "#1E3A8A",
                            iconColor: Color(hex: "#93C5FD"),
                            text: selectedDestination.walkFinalMinutes > 0
                                ? "Baja en \(selectedDestination.alightingStopName) · Camina \(selectedDestination.walkFinalMinutes) min al destino"
                                : "Baja directamente en \(selectedDestination.alightingStopName)"
                        )
                    }
                }

                // Barra de Acción Inferior en Nivel Medio
                HStack(spacing: 10) {
                    Button {
                        viewModel.startGuidedRoute(to: selectedDestination, optionIndex: selectedOptionIndex)
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "location.north.fill")
                                .font(.subheadline.weight(.bold))
                            Text("Iniciar")
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color(hex: "#34C759"))
                        .clipShape(Capsule())
                    }

                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            sheetSnap = .full
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "list.bullet.below.rectangle")
                                .font(.caption.weight(.bold))
                            Text("Opciones")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(Color(hex: "#2C2C2E"))
                        .clipShape(Capsule())
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 22)
        }
    }

    // ——— NIVEL 3: TODAS LAS OPCIONES (Full) ———
    private var fullSheetContent: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    // Chips de Filtro Rápido (Más rápida, Menos trasbordos, Asientos libres)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(RouteQuickFilter.allCases, id: \.self) { filter in
                                let active = selectedFilter == filter
                                Button {
                                    BCFeedbackManager.shared.impactLight()
                                    selectedFilter = filter
                                    if filter == .freeSeats {
                                        selectedOptionIndex = 2
                                    } else if filter == .fastest {
                                        selectedOptionIndex = 1
                                    }
                                } label: {
                                    Text(filter.rawValue)
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(active ? .white : .white.opacity(0.75))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(active ? Color(hex: "#1D3461") : Color(hex: "#2C2C2E"))
                                        .overlay(
                                            Capsule()
                                                .stroke(active ? Color(hex: "#2563EB") : Color.clear, lineWidth: 1)
                                        )
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    // OPCIÓN 1: Recomendada (Ruta principal o Caminata Directa)
                    routeOptionCard(
                        index: 1,
                        badge: "BUS",
                        title: selectedDestination.routeCase == .walkOnlyNearby ? "Caminata Directa" : selectedDestination.primaryRouteName,
                        isRecommended: true,
                        subtitle: selectedDestination.routeCase == .walkOnlyNearby
                            ? "Paradero más próximo · \(selectedDestination.distanceLabel) a pie"
                            : "\(liveEtaShortLabel) · \(selectedDestination.boardingStopName) → \(selectedDestination.alightingStopName)",
                        durationMinutes: selectedDestination.totalDurationMinutes,
                        footerText: selectedDestination.routeCase == .walkOnlyNearby
                            ? "Sin costo (Gratis) · 0 emisiones"
                            : "Tarifa: \(formattedUserFare) · \(liveEtaShortLabel) · 🌿 Eco"
                    )

                    // OPCIÓN 2: Ruta alterna
                    if selectedDestination.routeCase != .walkOnlyNearby {
                        routeOptionCard(
                            index: 2,
                            badge: "BUS",
                            title: secondaryRouteName,
                            isRecommended: false,
                            subtitle: "Ruta alterna · \(liveEtaShortLabel)",
                            durationMinutes: selectedDestination.secondaryDurationMinutes,
                            footerText: "Tarifa: \(formattedUserFare) · Alternativa por otra vía"
                        )
                    }

                    // OPCIÓN 3: Caminata Directa
                    if selectedDestination.routeCase != .walkOnlyNearby {
                        routeOptionCard(
                            index: 3,
                            badge: "PIE",
                            title: "Caminata directa",
                            isRecommended: false,
                            subtitle: "\(selectedDestination.distanceLabel) · Cero emisiones",
                            durationMinutes: selectedDestination.walkingDirectMinutes,
                            footerText: "Sin costo (Gratis) · Ruta peatonal por Tacna"
                        )
                    }

                    // Tarjeta Visual del Destino
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundColor(Color(hex: "#FB7185"))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedDestination.name)
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.white)
                                Text(selectedDestination.subtitle)
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.55))
                            }
                            Spacer()
                        }
                        .padding(12)

                        ZStack {
                            LinearGradient(
                                colors: [Color(hex: "#1E3A8A"), Color(hex: "#0F172A")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            VStack(spacing: 3) {
                                Text(selectedDestination.shortName.uppercased())
                                    .font(.subheadline.weight(.black))
                                    .foregroundColor(.white)
                                Text("Red Oficial Bus Conectado · Tacna")
                                    .font(.caption2)
                                    .foregroundColor(BCTheme.cyanAccent)
                            }
                        }
                        .frame(height: 76)
                    }
                    .background(Color(hex: "#2C2C2E"))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }

            // Botón Inferior Fijo [Iniciar] en Nivel Completo
            VStack(spacing: 0) {
                Divider().background(Color(hex: "#2C2C2E"))
                Button {
                    viewModel.startGuidedRoute(to: selectedDestination, optionIndex: selectedOptionIndex)
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "location.north.fill")
                            .font(.subheadline.weight(.bold))
                        Text("Iniciar Guía en el Mapa")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(hex: "#34C759"))
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(hex: "#1C1C1E"))
        }
    }

    // MARK: - Subvistas Auxiliares
    private func savedPlacePill(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "#3A3A3C"))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(hex: "#2C2C2E"))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func durationTabPill(minutes: Int, index: Int) -> some View {
        let isSelected = selectedOptionIndex == index
        return Button {
            BCFeedbackManager.shared.impactLight()
            selectedOptionIndex = index
        } label: {
            VStack(spacing: 3) {
                Text("\(minutes) min")
                    .font(.caption.weight(isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.55))
                Rectangle()
                    .fill(isSelected ? Color(hex: "#0A84FF") : Color.clear)
                    .frame(width: 38, height: 2.5)
                    .clipShape(Capsule())
            }
        }
    }

    private func stepRow(icon: String, bgHex: String, iconColor: Color, text: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(hex: bgHex))
                    .frame(width: 26, height: 26)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(iconColor)
            }
            Text(text)
                .font(.caption)
                .foregroundColor(.white.opacity(0.88))
        }
    }

    private func routeOptionCard(
        index: Int,
        badge: String,
        title: String,
        isRecommended: Bool,
        subtitle: String,
        durationMinutes: Int,
        footerText: String
    ) -> some View {
        let isSelected = selectedOptionIndex == index
        return Button {
            BCFeedbackManager.shared.impactLight()
            selectedOptionIndex = index
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? Color(hex: "#1D3461") : Color(hex: "#2C2C2E"))
                                .frame(width: 34, height: 34)
                            Image(systemName: badge == "PIE" ? "figure.walk" : "bus.fill")
                                .font(.subheadline)
                                .foregroundColor(isSelected ? Color(hex: "#60A5FA") : .gray)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(badge)
                                    .font(.system(size: 10, weight: .black).monospaced())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(isSelected ? Color(hex: "#0A84FF") : Color(hex: "#334155"))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))

                                Text(title)
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.white)

                                if isRecommended {
                                    Text("★ Recomendada")
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundColor(Color(hex: "#4ADE80"))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(hex: "#4ADE80").opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }

                            Text(subtitle)
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.65))
                                .multilineTextAlignment(.leading)
                        }
                    }

                    Spacer()

                    Text("\(durationMinutes) min")
                        .font(.subheadline.weight(.black).monospacedDigit())
                        .foregroundColor(isRecommended ? Color(hex: "#4ADE80") : .white)
                }

                Divider().background(Color(hex: "#2C2C2E"))

                Text(footerText)
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.65))
            }
            .padding(12)
            .background(Color(hex: "#1C1C1E"))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color(hex: "#0A84FF") : Color(hex: "#2C2C2E"), lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Helpers de Estado
    private var filteredDestinationsInPlanner: [TacnaDestinationPlace] {
        let trimmed = destinationSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceList = viewModel.dynamicCatalogStops.isEmpty ? TacnaDestinationPlace.catalog : viewModel.dynamicCatalogStops
        if trimmed.isEmpty {
            return sourceList
        }
        return sourceList.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) ||
            $0.shortName.localizedCaseInsensitiveContains(trimmed) ||
            $0.subtitle.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var activeDurationMinutes: Int {
        switch selectedOptionIndex {
        case 2: return selectedDestination.secondaryDurationMinutes
        case 3: return selectedDestination.walkingDirectMinutes
        default: return selectedDestination.totalDurationMinutes
        }
    }

    /// Ruta principal o alterna según la opción elegida (Ej: "Ruta 14" / "Ruta 10B")
    private var selectedRouteLabel: String {
        selectedOptionIndex == 2 ? secondaryRouteName : selectedDestination.primaryRouteName
    }

    private var secondaryRouteName: String {
        selectedDestination.routesPassing.count > 1
            ? selectedDestination.routesPassing[1]
            : selectedDestination.primaryRouteName
    }

    /// ETA real solo cuando existen unidades en operación; en cuentas de prueba no se inventan buses
    private var liveEtaShortLabel: String {
        if let bus = viewModel.activeBuses.first {
            return "Próximo bus en ~\(bus.nextStopEtaMinutes) min · \(bus.occupancyPercentage)% aforo"
        }
        return "ETA en vivo al activarse unidades"
    }

    private var formattedUserFare: String {
        if let user = viewModel.currentUser {
            return String(format: "S/. %.2f", user.roleType.farePen)
        }
        return "S/. 0.70"
    }

    private var sheetSnapLabel: String {
        switch sheetSnap {
        case .compact: return "Desliza o toca para ver detalles de ruta"
        case .medium: return "Desliza hacia arriba para ver todas las opciones"
        case .full: return "Toca para contraer hoja de rutas"
        }
    }

    private func currentSheetHeight(in totalHeight: CGFloat) -> CGFloat {
        let base = sheetSnap.height(in: totalHeight)
        let adjusted = base - sheetDragTranslation
        return min(max(adjusted, 165), totalHeight * 0.86)
    }

    private func selectDestinationAndShowRoute(_ place: TacnaDestinationPlace) {
        BCFeedbackManager.shared.impactMedium()
        selectedDestination = place
        selectedOptionIndex = 1
        sheetSnap = .compact
        updateCameraForDestination(place)
        withAnimation(.easeInOut(duration: 0.25)) {
            screenState = .routeMap
        }
    }

    private func updateCameraForDestination(_ place: TacnaDestinationPlace) {
        let origin = TacnaDestinationPlace.userOriginCoordinate
        let midLat = (origin.latitude + place.latitude) / 2.0 - 0.0020
        let midLon = (origin.longitude + place.longitude) / 2.0
        let spanLat = max(abs(origin.latitude - place.latitude) * 2.2, 0.012)
        let spanLon = max(abs(origin.longitude - place.longitude) * 2.2, 0.012)

        withAnimation(.easeInOut(duration: 0.35)) {
            routeMapCamera = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: midLat, longitude: midLon),
                    span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon)
                )
            )
        }
    }
}


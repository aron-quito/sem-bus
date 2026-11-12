import SwiftUI
import MapKit

enum PlannerEndpointTarget: Equatable {
    case origin
    case destination
}

enum RoutePlannerScreenState: Equatable {
    case selector                              // Estado 1: Selector de Origen/Destino y Recientes
    case search(target: PlannerEndpointTarget) // Estado 2: Buscador en vivo por API (MKLocalSearch) + Paraderos
    case mapPicker(target: PlannerEndpointTarget) // Estado 2B: Fijar cualquier punto libre en el mapa de Tacna
    case routeMap                              // Estados 3, 4 y 5: Mapa de Ruta + Bottom Sheet de 3 Niveles
}

enum RouteSheetSnapLevel: CaseIterable {
    case compact    // Nivel 1: Compacto (Peek)
    case medium     // Nivel 2: Detalle Visual Intermedio (Medium)
    case full       // Nivel 3: Comparativa Detallada (Full)

    func height(in totalHeight: CGFloat, bottomInset: CGFloat) -> CGFloat {
        let safeBottom = max(bottomInset, 18)
        switch self {
        case .compact:
            return 192 + safeBottom
        case .medium:
            return min(max(totalHeight * 0.50, 380 + safeBottom), 485)
        case .full:
            return max(440, totalHeight - 192)
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
    case recommended = "Recomendadas"
    case ordinaryOnly = "Ordinarias (QR)"
    case lessWalking = "Menor caminata"
}

struct RoutePlannerView: View {
    @ObservedObject var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var screenState: RoutePlannerScreenState = .selector
    @State private var selectedOrigin: TacnaDestinationPlace = TacnaDestinationPlace.currentLocationPlace()
    @State private var selectedDestination: TacnaDestinationPlace = TacnaDestinationPlace.catalog[0]
    @State private var selectedTransportTab: Int = 0 // 0 = Bus + Caminata, 1 = Solo A pie

    // Buscador en vivo por API (MKLocalSearch) para Origen o Destino
    @State private var plannerSearchText: String = ""
    @State private var apiSearchResults: [TacnaDestinationPlace] = []
    @State private var isSearchingAPI: Bool = false
    @State private var searchTask: Task<Void, Never>? = nil
    @FocusState private var isSearchInputFocused: Bool

    // Estado del Selector Interactivo en el Mapa ("Fijar punto en el mapa")
    @State private var pickerCenterCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: -18.0135, longitude: -70.2519)
    @State private var pickerMapCamera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -18.0135, longitude: -70.2519),
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        )
    )
    @State private var pickerResolvedPlace: TacnaDestinationPlace? = nil
    @State private var isResolvingPickerPoint: Bool = false

    // Resultado del Motor de Automatización de Rutas (Ordinarias en servicio, Externas en vía y Caminata)
    @State private var evaluationResult: RouteAutomationEvaluationResult? = nil
    @State private var selectedCandidateIndex: Int = 0
    @State private var selectedFilter: RouteQuickFilter = .recommended

    // Estado de la Hoja Inferior de 3 Niveles (Peek / Medium / Full)
    @State private var sheetSnap: RouteSheetSnapLevel = .compact
    @State private var sheetDragTranslation: CGFloat = 0

    // Polilíneas alineadas nativamente a las calles de Apple Maps (MKDirections)
    @State private var plannerWalkStreetCoords: [CLLocationCoordinate2D] = []
    @State private var plannerBusStreetCoords: [CLLocationCoordinate2D] = []
    @State private var plannerFinalWalkStreetCoords: [CLLocationCoordinate2D] = []

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
            case .search(let target):
                searchScreenView(target: target)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .mapPicker(let target):
                mapPickerScreenView(target: target)
                    .transition(.opacity)
            case .routeMap:
                routeMapScreenView
                    .transition(.opacity)
            }
        }
        .onAppear {
            if let customOrigin = viewModel.routePlannerInitialOrigin {
                selectedOrigin = customOrigin
            } else {
                selectedOrigin = TacnaDestinationPlace.currentLocationPlace()
            }

            if let initialDest = viewModel.routePlannerInitialDestination {
                selectedDestination = initialDest
                recalculateAutomatedRoutes(resetSelection: true)
                screenState = .routeMap
            } else {
                screenState = .selector
            }
        }
        .onChange(of: plannerSearchText) { _, newValue in
            triggerLiveAPISearch(query: newValue)
        }
    }

    // MARK: - Candidatos Filtrados y Opción Activa
    private var displayedCandidates: [EvaluatedRouteCandidate] {
        guard let eval = evaluationResult else { return [] }
        if selectedTransportTab == 1 {
            return eval.candidates.filter { $0.kind == .walkingDirect }
        }
        switch selectedFilter {
        case .recommended:
            return eval.candidates
        case .ordinaryOnly:
            let ord = eval.candidates.filter { $0.kind == .ordinaryInService }
            return ord.isEmpty ? eval.candidates : ord
        case .lessWalking:
            return eval.candidates.sorted { $0.walkTotalMeters < $1.walkTotalMeters }
        }
    }

    private var activeCandidate: EvaluatedRouteCandidate? {
        let list = displayedCandidates
        guard !list.isEmpty else { return evaluationResult?.recommendedCandidate }
        if list.indices.contains(selectedCandidateIndex) {
            return list[selectedCandidateIndex]
        }
        return list.first
    }

    // MARK: - ESTADO 1: Selector de Punto de Inicio (Origen) y Punto de Llegada (Destino)
    private var selectorScreenView: some View {
        VStack(spacing: 0) {
            // Cabecera con botón Volver y Tarjeta Interactiva de Origen / Destino
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
                    // Fila Punto de Inicio (Origen)
                    HStack(spacing: 10) {
                        Button {
                            BCFeedbackManager.shared.impactLight()
                            plannerSearchText = ""
                            apiSearchResults = []
                            withAnimation(.easeInOut(duration: 0.2)) {
                                screenState = .search(target: .origin)
                                isSearchInputFocused = true
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .stroke(Color(hex: "#60A5FA"), lineWidth: 2.5)
                                    .frame(width: 10, height: 10)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text("PUNTO DE INICIO")
                                        .font(.system(size: 8.5, weight: .heavy))
                                        .foregroundColor(Color(hex: "#60A5FA"))
                                    Text(selectedOrigin.name)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                }

                                Spacer()
                            }
                        }

                        Button {
                            BCFeedbackManager.shared.impactLight()
                            openMapCrosshairPicker(for: .origin)
                        } label: {
                            Image(systemName: "scope")
                                .font(.caption.weight(.bold))
                                .foregroundColor(BCTheme.cyanAccent)
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Fijar origen en el mapa")

                        Button {
                            swapOriginAndDestination()
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white.opacity(0.75))
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)

                    Divider()
                        .background(Color(hex: "#3A3A3C"))
                        .padding(.horizontal, 12)

                    // Fila Punto de Llegada (Destino)
                    HStack(spacing: 10) {
                        Button {
                            BCFeedbackManager.shared.impactLight()
                            plannerSearchText = ""
                            apiSearchResults = []
                            withAnimation(.easeInOut(duration: 0.2)) {
                                screenState = .search(target: .destination)
                                isSearchInputFocused = true
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(Color(hex: "#FB7185"))

                                VStack(alignment: .leading, spacing: 1) {
                                    Text("PUNTO DE LLEGADA (DESTINO)")
                                        .font(.system(size: 8.5, weight: .heavy))
                                        .foregroundColor(Color(hex: "#FB7185"))
                                    Text("Buscar en API (ej. Plaza Vea) o elegir destino ›")
                                        .font(.footnote)
                                        .foregroundColor(.white.opacity(0.75))
                                        .lineLimit(1)
                                }

                                Spacer()
                            }
                        }

                        Button {
                            BCFeedbackManager.shared.impactLight()
                            openMapCrosshairPicker(for: .destination)
                        } label: {
                            Image(systemName: "scope")
                                .font(.caption.weight(.bold))
                                .foregroundColor(Color(hex: "#FB7185"))
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Fijar destino en el mapa")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                }
                .background(Color(hex: "#2C2C2E"))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            // Pestañas de Modo de Transporte (Bus / A pie) + Botones rápidos de Fijar en Mapa
            HStack(spacing: 10) {
                Button {
                    BCFeedbackManager.shared.impactLight()
                    selectedTransportTab = 0
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bus.fill")
                            .font(.caption)
                        Text("Bus + Caminata")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selectedTransportTab == 0 ? Color(hex: "#0A84FF") : Color(hex: "#2C2C2E"))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Button {
                    BCFeedbackManager.shared.impactLight()
                    selectedTransportTab = 1
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "figure.walk")
                            .font(.caption)
                        Text("Solo a pie")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(selectedTransportTab == 1 ? .white : .white.opacity(0.65))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selectedTransportTab == 1 ? Color(hex: "#0A84FF") : Color(hex: "#2C2C2E"))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Accesos Directos: Fijar Punto en el Mapa (Inicio o Llegada) y Buscador API
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    savedPlacePill(
                        icon: "mappin.and.ellipse",
                        title: "Fijar Destino en Mapa",
                        subtitle: "Cualquier calle o esquina"
                    ) {
                        openMapCrosshairPicker(for: .destination)
                    }

                    savedPlacePill(
                        icon: "location.north.circle.fill",
                        title: "Fijar Inicio en Mapa",
                        subtitle: "Cambiar punto de partida"
                    ) {
                        openMapCrosshairPicker(for: .origin)
                    }

                    savedPlacePill(
                        icon: "magnifyingglass.circle.fill",
                        title: "Buscar Lugar (API)",
                        subtitle: "Plaza Vea, Hospital, etc."
                    ) {
                        plannerSearchText = ""
                        apiSearchResults = []
                        withAnimation(.easeInOut(duration: 0.2)) {
                            screenState = .search(target: .destination)
                            isSearchInputFocused = true
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 12)

            // Título de Paraderos Sincronizados
            HStack {
                Text("Paraderos Sincronizados y Puntos de Referencia")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Text("\(viewModel.dynamicRoutes.filter { $0.isOrdinaryInService }.count) ord. activas")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(BCTheme.emerald)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Lista de Paraderos Sincronizados con cálculo dinámico de tiempo desde el Origen actual
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.dynamicCatalogStops) { place in
                        Button {
                            selectEndpointAndContinue(place, for: .destination)
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: "#2C2C2E"))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: place.displayIconName)
                                        .font(.subheadline)
                                        .foregroundColor(Color(hex: place.displayColorHex))
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(place.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text(place.displayBadgeText)
                                            .font(.system(size: 8, weight: .heavy))
                                            .foregroundColor(Color(hex: place.displayColorHex))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1.5)
                                            .background(Color(hex: place.displayColorHex).opacity(0.15))
                                            .clipShape(Capsule())
                                    }

                                    Text(place.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.55))
                                        .lineLimit(1)
                                }

                                Spacer()

                                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                    .font(.caption)
                                    .foregroundColor(BCTheme.cyanAccent)
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

    // MARK: - ESTADO 2: Buscador en Vivo conectado a la API de Mapas (MKLocalSearch) + Paraderos
    private func searchScreenView(target: PlannerEndpointTarget) -> some View {
        let isEditingOrigin = (target == .origin)

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    BCFeedbackManager.shared.impactLight()
                    isSearchInputFocused = false
                    withAnimation(.easeInOut(duration: 0.2)) {
                        screenState = evaluationResult != nil ? .routeMap : .selector
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
                        .foregroundColor(isEditingOrigin ? Color(hex: "#60A5FA") : Color(hex: "#FB7185"))

                    TextField(
                        isEditingOrigin
                            ? "Buscar punto de inicio en Tacna (ej. Plaza Vea, calle...)"
                            : "Buscar destino en la API (ej. Plaza Vea, Hospital...)",
                        text: $plannerSearchText
                    )
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .focused($isSearchInputFocused)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit {
                        triggerLiveAPISearch(query: plannerSearchText, immediate: true)
                    }

                    if !plannerSearchText.isEmpty {
                        Button {
                            plannerSearchText = ""
                            apiSearchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color(hex: "#2C2C2E"))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Acciones rápidas: Fijar cualquier punto en el mapa o usar mi ubicación GPS
            VStack(spacing: 0) {
                Button {
                    isSearchInputFocused = false
                    openMapCrosshairPicker(for: target)
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(BCTheme.cyanAccent.opacity(0.18))
                                .frame(width: 36, height: 36)
                            Image(systemName: "scope")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(BCTheme.cyanAccent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isEditingOrigin ? "Fijar punto de inicio en el mapa" : "Fijar punto de llegada en el mapa")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                            Text("Mueve el mapa para elegir cualquier calle, esquina o lugar exacto")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.55))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                if isEditingOrigin {
                    Divider().background(Color(hex: "#2C2C2E"))
                    Button {
                        isSearchInputFocused = false
                        selectEndpointAndContinue(TacnaDestinationPlace.currentLocationPlace(), for: .origin)
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(BCTheme.royalBlue.opacity(0.2))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "location.fill")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(Color(hex: "#60A5FA"))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Usar mi ubicación actual (GPS)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(Color(hex: "#60A5FA"))
                                Text("Punto de partida según tu ubicación en tiempo real")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.55))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
            }
            .background(Color(hex: "#1C1C1E"))

            Divider().background(Color(hex: "#2C2C2E"))

            // Lista combinada: 1º Resultados Reales de la API del Mapa (MKLocalSearch) + 2º Paraderos Oficiales
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if isSearchingAPI {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(BCTheme.cyanAccent)
                            Text("Consultando ubicaciones reales en la API del Mapa...")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.65))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }

                    if !apiSearchResults.isEmpty {
                        Text("UBICACIONES REALES DE LA API DEL MAPA (\(apiSearchResults.count))")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(BCTheme.cyanAccent)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 6)

                        ForEach(apiSearchResults) { apiPlace in
                            Button {
                                isSearchInputFocused = false
                                selectEndpointAndContinue(apiPlace, for: target)
                            } label: {
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle()
                                            .fill(BCTheme.cyanAccent.opacity(0.18))
                                            .frame(width: 38, height: 38)
                                        Image(systemName: "mappin.and.ellipse")
                                            .font(.subheadline.weight(.bold))
                                            .foregroundColor(BCTheme.cyanAccent)
                                    }

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(apiPlace.name)
                                                .font(.subheadline.weight(.bold))
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                            Text("PUNTO DE INTERÉS • API")
                                                .font(.system(size: 8, weight: .black))
                                                .foregroundColor(.black)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1.5)
                                                .background(BCTheme.cyanAccent)
                                                .clipShape(Capsule())
                                        }
                                        Text(apiPlace.subtitle)
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.65))
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Image(systemName: "arrow.up.right.circle.fill")
                                        .font(.subheadline)
                                        .foregroundColor(BCTheme.cyanAccent)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }

                            Divider()
                                .background(Color(hex: "#2C2C2E"))
                                .padding(.leading, 68)
                        }
                    }

                    Text("PARADEROS DE TRANSPORTE EN TACNA (\(filteredStopsInPlanner.count))")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 6)

                    ForEach(filteredStopsInPlanner) { stopPlace in
                        Button {
                            isSearchInputFocused = false
                            selectEndpointAndContinue(stopPlace, for: target)
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: "#2C2C2E"))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: "bus.fill")
                                        .font(.subheadline)
                                        .foregroundColor(Color(hex: stopPlace.displayColorHex))
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(stopPlace.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text("PARADERO")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(Color(hex: stopPlace.displayColorHex))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1.5)
                                            .background(Color(hex: stopPlace.displayColorHex).opacity(0.16))
                                            .clipShape(Capsule())
                                    }
                                    Text(stopPlace.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.55))
                                        .lineLimit(1)
                                }

                                Spacer()
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

    // MARK: - ESTADO 2B: Selector Interactivo en el Mapa ("Fijar Punto en el Mapa" para Inicio o Destino)
    private func mapPickerScreenView(target: PlannerEndpointTarget) -> some View {
        let isOrigin = (target == .origin)
        let accentColor = isOrigin ? Color(hex: "#60A5FA") : Color(hex: "#FB7185")

        return ZStack {
            Map(position: $pickerMapCamera) {
                ForEach(viewModel.dynamicCatalogStops) { stop in
                    Annotation(stop.shortName, coordinate: stop.coordinate) {
                        Circle()
                            .fill(Color(hex: "#2563EB"))
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .all))
            .ignoresSafeArea()
            .onMapCameraChange(frequency: .onEnd) { context in
                let center = context.region.center
                pickerCenterCoordinate = center
                isResolvingPickerPoint = true
                Task {
                    let resolved = await viewModel.reverseGeocodeCoordinateInTacna(
                        center,
                        roleLabel: isOrigin ? "Punto de inicio" : "Punto de destino"
                    )
                    await MainActor.run {
                        pickerResolvedPlace = resolved
                        isResolvingPickerPoint = false
                    }
                }
            }

            // Mira Central Fija (Pin de Selección en Calle o Punto de Interés)
            VStack(spacing: 4) {
                Text(isOrigin ? "FIJAR PUNTO DE INICIO" : "FIJAR PUNTO DE LLEGADA")
                    .font(.system(size: 9.5, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accentColor)
                    .clipShape(Capsule())
                    .shadow(radius: 4)

                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(accentColor)
                    .background(Circle().fill(Color.white).frame(width: 18, height: 18))
                    .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
            }
            .offset(y: -18)
            .allowsHitTesting(false)

            // Barra Superior e Inferior del Selector en Mapa
            VStack {
                HStack {
                    Button {
                        BCFeedbackManager.shared.impactLight()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            screenState = evaluationResult != nil ? .routeMap : .selector
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left")
                            Text("Volver")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(BCTheme.elevatedSurface.opacity(0.95))
                        .clipShape(Capsule())
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(accentColor.opacity(0.2))
                                .frame(width: 40, height: 40)
                            Image(systemName: isOrigin ? "location.fill" : "mappin.and.ellipse")
                                .foregroundColor(accentColor)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(isOrigin ? "Punto de Inicio seleccionado" : "Punto de Destino seleccionado")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(accentColor)
                            Text(
                                isResolvingPickerPoint
                                    ? "Identificando calle o lugar en Tacna..."
                                    : (pickerResolvedPlace?.name ?? "Mueve el mapa para ubicar el punto")
                            )
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                            Text(pickerResolvedPlace?.subtitle ?? String(format: "%.5f, %.5f", pickerCenterCoordinate.latitude, pickerCenterCoordinate.longitude))
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.65))
                                .lineLimit(1)
                        }
                        Spacer()
                    }

                    Button {
                        let finalPlace = pickerResolvedPlace ?? TacnaDestinationPlace.fromMapItem(
                            name: isOrigin ? "Inicio en mapa" : "Destino en mapa",
                            subtitle: "📍 Punto personalizado en Tacna",
                            coordinate: pickerCenterCoordinate
                        )
                        selectEndpointAndContinue(finalPlace, for: target)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.subheadline.weight(.bold))
                            Text(isOrigin ? "Establecer como Punto de Inicio" : "Establecer como Destino y Calcular Ruta")
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(BCTheme.cyanAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(16)
                .background(BCTheme.elevatedSurface.opacity(0.98))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
                .shadow(color: .black.opacity(0.5), radius: 14)
            }
        }
    }

    // MARK: - ESTADOS 3, 4 y 5: Mapa de Ruta + Hoja Inferior Interactiva de 3 Niveles (#gm-state-route)
    private var routeMapScreenView: some View {
        let cand = activeCandidate

        return GeometryReader { geo in
            ZStack(alignment: .top) {
                // 1. Mapa de Fondo con Polilíneas Multimodales Calculadas en Tiempo Real
                Map(position: $routeMapCamera) {
                    // Pin de Origen (Ubicación actual o Punto de inicio elegido por el usuario)
                    Annotation(selectedOrigin.shortName, coordinate: selectedOrigin.coordinate) {
                        VStack(spacing: 2) {
                            Text("Inicio: \(selectedOrigin.shortName)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(BCTheme.royalBlue)
                                .clipShape(RoundedRectangle(cornerRadius: 5))

                            ZStack {
                                Circle()
                                    .fill(BCTheme.royalBlue.opacity(0.28))
                                    .frame(width: 26, height: 26)
                                Circle()
                                    .fill(BCTheme.royalBlue)
                                    .frame(width: 13, height: 13)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            }
                        }
                    }

                    // Tramo 1: Caminata desde el Origen hasta el Paradero (Ordinaria) o hasta la Vía (Externa)
                    if plannerWalkStreetCoords.count >= 2 {
                        MapPolyline(coordinates: plannerWalkStreetCoords)
                            .stroke(
                                BCTheme.cyanAccent,
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [6, 7])
                            )
                    }

                    // Tramo 2: Recorrido en Bus (Ruta Ordinaria por Paraderos vs Ruta Externa en Vía)
                    if let cand = cand, cand.kind != .walkingDirect, plannerBusStreetCoords.count >= 2 {
                        let isOrd = cand.kind == .ordinaryInService
                        MapPolyline(coordinates: plannerBusStreetCoords)
                            .stroke(
                                Color(hex: cand.colorHex),
                                style: StrokeStyle(
                                    lineWidth: isOrd ? 7 : 5.5,
                                    lineCap: .round,
                                    lineJoin: .round,
                                    dash: isOrd ? [] : [9, 6]
                                )
                            )

                        // Marcador de Abordaje (solo punto con signo de paradero, sin texto)
                        Annotation("", coordinate: cand.boardingCoordinate) {
                            TransitStopDotMarker(accentColor: isOrd ? BCTheme.emerald : BCTheme.amber)
                        }

                        // Marcador de Descenso (solo punto con signo de paradero, sin texto)
                        Annotation("", coordinate: cand.alightingCoordinate) {
                            TransitStopDotMarker(accentColor: BCTheme.cyanAccent)
                        }
                    }

                    // Tramo 3: Caminata final desde el paradero/punto de bajada hasta el Destino final
                    if plannerFinalWalkStreetCoords.count >= 2 {
                        MapPolyline(coordinates: plannerFinalWalkStreetCoords)
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
                .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .all))
                .ignoresSafeArea()

                // 2. Degradado translúcido en la parte superior del mapa (idéntico a la pantalla principal)
                TopMapStatusBarFade()

                // 3. Cabecera Flotante Translúcida de Ruteo (Con edición de Origen y Destino + Píldora Multimodal)
                floatingRouteHeader

                // 3. Botón Flotante para Re-encuadrar la Ruta en el Mapa
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            BCFeedbackManager.shared.impactLight()
                            if let cand = activeCandidate {
                                updatePolylinesAndCamera(for: cand)
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(BCTheme.elevatedSurface.opacity(0.96))
                                    .frame(width: 42, height: 42)
                                    .overlay(
                                        Circle()
                                            .stroke(BCTheme.hairlineBorder, lineWidth: 1)
                                    )
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(BCTheme.cyanAccent)
                            }
                            .shadow(color: .black.opacity(0.45), radius: 6)
                        }
                        .padding(.trailing, 14)
                        .padding(.bottom, currentSheetHeight(in: geo.size.height, bottomInset: geo.safeAreaInsets.bottom) + 14)
                    }
                    .opacity(sheetSnap == .full ? 0 : 1)
                    .allowsHitTesting(sheetSnap != .full)
                    .animation(.easeInOut(duration: 0.2), value: sheetSnap)
                }

                // 4. Hoja Inferior Interactiva de 3 Niveles (Compacto / Medio / Completo)
                VStack {
                    Spacer()
                    interactiveBottomSheet(totalHeight: geo.size.height, bottomInset: geo.safeAreaInsets.bottom)
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    // MARK: - Cabecera Superior de Ruteo + Píldora Multimodal
    private var floatingRouteHeader: some View {
        let cand = activeCandidate

        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    BCFeedbackManager.shared.impactLight()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        screenState = .selector
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

                // Botones de Origen y Destino (Editables por búsqueda API o fijando en el mapa)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Button {
                            plannerSearchText = ""
                            apiSearchResults = []
                            withAnimation {
                                screenState = .search(target: .origin)
                                isSearchInputFocused = true
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("Desde: \(selectedOrigin.shortName)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Color(hex: "#60A5FA"))
                                    .lineLimit(1)
                                Spacer()
                            }
                        }

                        Button {
                            openMapCrosshairPicker(for: .origin)
                        } label: {
                            Image(systemName: "scope")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(BCTheme.cyanAccent)
                        }
                    }

                    Divider().background(Color.white.opacity(0.1))

                    HStack {
                        Button {
                            plannerSearchText = ""
                            apiSearchResults = []
                            withAnimation {
                                screenState = .search(target: .destination)
                                isSearchInputFocused = true
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("Hasta: \(selectedDestination.name)")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Spacer()
                            }
                        }

                        Button {
                            openMapCrosshairPicker(for: .destination)
                        } label: {
                            Image(systemName: "scope")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(hex: "#FB7185"))
                        }
                    }
                }

                // Botones de Todas las Opciones [...] e Inversión [⇅]
                VStack(spacing: 6) {
                    Button {
                        BCFeedbackManager.shared.impactLight()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            sheetSnap = .full
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 28, height: 28)
                            .background(Color(hex: "#1E293B"))
                            .clipShape(Circle())
                    }

                    Button {
                        swapOriginAndDestination()
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 28, height: 28)
                            .background(Color(hex: "#1E293B"))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(hex: "#1F262E").opacity(0.84))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)

            // Resumen Multimodal Flotante de la Opción Activa
            if let cand = cand {
                HStack(spacing: 6) {
                    if cand.kind == .walkingDirect {
                        HStack(spacing: 5) {
                            Image(systemName: "figure.walk")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(BCTheme.cyanAccent)
                            Text("\(cand.totalDurationMinutes) min a pie · \(cand.totalDistanceLabel)")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(BCTheme.cyanAccent)
                        }
                        Spacer()
                        Text("Caminata directa")
                            .font(.caption2.weight(.heavy))
                            .foregroundColor(BCTheme.emerald)
                    } else {
                        let isOrd = cand.kind == .ordinaryInService
                        HStack(spacing: 4) {
                            Label("\(cand.walkInitialMinutes)m", systemImage: "figure.walk")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(BCTheme.cyanAccent)

                            Text("➔")
                                .font(.system(size: 9))
                                .foregroundColor(.gray)

                            HStack(spacing: 4) {
                                Image(systemName: "bus.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text("\(cand.routeCode) (\(cand.busRideMinutes)m)")
                                    .font(.system(size: 10, weight: .bold).monospaced())
                                Text(isOrd ? "ORD" : "EXT")
                                    .font(.system(size: 7.5, weight: .black))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(isOrd ? BCTheme.emerald.opacity(0.28) : BCTheme.amber.opacity(0.28))
                                    .clipShape(Capsule())
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(hex: cand.colorHex).opacity(0.35))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color(hex: cand.colorHex), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 5))

                            if cand.walkFinalMinutes > 0 {
                                Text("➔")
                                    .font(.system(size: 9))
                                    .foregroundColor(.gray)

                                Label("\(cand.walkFinalMinutes)m", systemImage: "figure.walk")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(BCTheme.cyanAccent)
                            }
                        }

                        Spacer()

                        Text(isOrd ? "~\(cand.totalDurationMinutes) min · \(formattedUserFare)" : "~\(cand.totalDurationMinutes) min · Sin QR")
                            .font(.caption2.weight(.heavy).monospaced())
                            .foregroundColor(isOrd ? BCTheme.emerald : BCTheme.amber)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(hex: "#1F262E").opacity(0.84))
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Hoja Inferior Interactiva de 3 Niveles (Transición Fluida Estilo Apple)
    private func interactiveBottomSheet(totalHeight: CGFloat, bottomInset: CGFloat) -> some View {
        let safeBottom = max(bottomInset, 18)
        let targetHeight = currentSheetHeight(in: totalHeight, bottomInset: safeBottom)

        return VStack(spacing: 0) {
            // Barra de agarre minimalista estilo Apple + gesto fluido de arrastre
            VStack(spacing: 6) {
                Capsule()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 40, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                BCFeedbackManager.shared.impactLight()
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86, blendDuration: 0.12)) {
                    sheetSnap = sheetSnap.nextLevel
                }
            }
            .gesture(sheetDragGesture(totalHeight: totalHeight, bottomInset: safeBottom))

            ZStack(alignment: .top) {
                switch sheetSnap {
                case .compact:
                    compactSheetContent(bottomPadding: safeBottom)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                case .medium:
                    mediumSheetContent(bottomPadding: safeBottom)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                case .full:
                    fullSheetContent(bottomPadding: safeBottom)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.spring(response: 0.40, dampingFraction: 0.86), value: sheetSnap)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: targetHeight)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(hex: "#18191D").opacity(0.95))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.11), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 22, y: -6)
        .simultaneousGesture(
            sheetSnap == .compact ? sheetDragGesture(totalHeight: totalHeight, bottomInset: safeBottom) : nil
        )
    }

    private func sheetDragGesture(totalHeight: CGFloat, bottomInset: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width) || sheetDragTranslation != 0 else {
                    return
                }
                var dy = value.translation.height
                let minH = RouteSheetSnapLevel.compact.height(in: totalHeight, bottomInset: bottomInset)
                let maxH = RouteSheetSnapLevel.full.height(in: totalHeight, bottomInset: bottomInset)
                let baseH = sheetSnap.height(in: totalHeight, bottomInset: bottomInset)
                let rawH = baseH - dy
                // Efecto goma (rubber-band) nativo cuando pasa los límites superior o inferior
                if rawH < minH {
                    dy = baseH - (minH - (minH - rawH) * 0.28)
                } else if rawH > maxH {
                    dy = baseH - (maxH + (rawH - maxH) * 0.28)
                }
                withAnimation(.interactiveSpring(response: 0.16, dampingFraction: 0.9)) {
                    sheetDragTranslation = dy
                }
            }
            .onEnded { value in
                guard abs(value.translation.height) > abs(value.translation.width) || sheetDragTranslation != 0 else {
                    sheetDragTranslation = 0
                    return
                }
                let baseH = sheetSnap.height(in: totalHeight, bottomInset: bottomInset)
                let predictedH = baseH - value.predictedEndTranslation.height
                let levels = RouteSheetSnapLevel.allCases
                let closest = levels.min(by: {
                    abs($0.height(in: totalHeight, bottomInset: bottomInset) - predictedH)
                    < abs($1.height(in: totalHeight, bottomInset: bottomInset) - predictedH)
                }) ?? sheetSnap

                withAnimation(.spring(response: 0.42, dampingFraction: 0.85, blendDuration: 0.1)) {
                    sheetSnap = closest
                    sheetDragTranslation = 0
                }
                BCFeedbackManager.shared.impactLight()
            }
    }

    // ——— NIVEL 1: COMPACTO (Gráfico y minimalista) ———
    private func compactSheetContent(bottomPadding: CGFloat) -> some View {
        let cand = activeCandidate

        return VStack(alignment: .leading, spacing: 11) {
            // Pestañas rápidas de rutas evaluadas
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(displayedCandidates.prefix(5).enumerated()), id: \.element.id) { idx, item in
                        durationTabPill(candidate: item, index: idx)
                    }
                }
            }

            if let cand = cand {
                // Resumen visual: Tiempo + Cadena gráfica de tramos + Badge de servicio
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        Text("~\(cand.totalDurationMinutes) min")
                            .font(.title3.weight(.black).monospacedDigit())
                            .foregroundColor(.white)

                        Text("· \(cand.totalDistanceLabel)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.6))

                        Spacer()

                        modeBadgePill(for: cand)
                    }

                    journeyGraphicStrip(candidate: cand)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            // Botones de Acción con espacio cómodo respecto al borde inferior
            HStack(spacing: 10) {
                Button {
                    guard let chosen = cand else { return }
                    viewModel.startGuidedRoute(
                        from: selectedOrigin,
                        to: selectedDestination,
                        candidate: chosen,
                        optionIndex: selectedCandidateIndex
                    )
                    dismiss()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "location.north.fill")
                            .font(.subheadline.weight(.bold))
                        Text("Ir")
                            .font(.subheadline.weight(.bold))
                        if cand?.kind == .ordinaryInService {
                            Image(systemName: "bell.badge.fill")
                                .font(.caption.weight(.bold))
                                .opacity(0.9)
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color(hex: "#34C759"))
                    .clipShape(Capsule())
                }

                Button {
                    BCFeedbackManager.shared.impactLight()
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                        sheetSnap = .full
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet")
                            .font(.caption.weight(.bold))
                        Text("Opciones (\(displayedCandidates.count))")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 46)
                    .background(Color(hex: "#2C2C2E"))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, bottomPadding + 8)
    }

    // ——— NIVEL 2: DETALLE VISUAL INTERMEDIO (Timeline estilo Apple Maps) ———
    private func mediumSheetContent(bottomPadding: CGFloat) -> some View {
        let cand = activeCandidate

        return VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if let cand = cand {
                        HStack(alignment: .center, spacing: 8) {
                            Text("~\(cand.totalDurationMinutes) min")
                                .font(.title2.weight(.black).monospacedDigit())
                                .foregroundColor(.white)

                            Text("· \(cand.totalDistanceLabel)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white.opacity(0.6))

                            Spacer()

                            Button {
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                                    sheetSnap = .full
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Ver todas")
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .font(.caption.weight(.bold))
                                .foregroundColor(Color(hex: "#60A5FA"))
                            }
                        }

                        // Estado operativo minimalista con íconos en 1 sola línea
                        HStack(spacing: 8) {
                            modeBadgePill(for: cand)
                            if cand.kind == .ordinaryInService {
                                Label("Aviso 5m", systemImage: "bell.badge.fill")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundColor(BCTheme.emerald)
                                Spacer()
                                Text(formattedUserFare)
                                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                                    .foregroundColor(.white.opacity(0.9))
                            } else if cand.kind == .externalFreeBoarding {
                                Label("Sube/baja en vía", systemImage: "hand.raised.fill")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundColor(BCTheme.amber)
                                Spacer()
                                Text("Sin QR")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundColor(BCTheme.amber)
                            } else {
                                Spacer()
                                Text("Gratis")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(BCTheme.cyanAccent)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        // Timeline visual paso a paso (sin párrafos largos)
                        VStack(alignment: .leading, spacing: 0) {
                            if cand.kind == .walkingDirect {
                                visualTimelineRow(
                                    icon: "figure.walk",
                                    color: BCTheme.cyanAccent,
                                    title: "Caminar a \(selectedDestination.shortName)",
                                    subtitle: "\(cand.walkInitialMeters) m por calles",
                                    trailingValue: "\(cand.walkInitialMinutes)m",
                                    isLast: true
                                )
                            } else {
                                let isOrd = cand.kind == .ordinaryInService
                                visualTimelineRow(
                                    icon: "figure.walk",
                                    color: BCTheme.cyanAccent,
                                    title: isOrd ? "Paradero \(cand.boardingPointName)" : "Vía de \(cand.routeCode)",
                                    subtitle: "\(cand.walkInitialMeters) m a pie",
                                    trailingValue: "\(cand.walkInitialMinutes)m",
                                    isLast: false
                                )

                                visualTimelineRow(
                                    icon: "bus.fill",
                                    color: Color(hex: cand.colorHex),
                                    title: cand.routeCode,
                                    subtitle: isOrd
                                        ? "\(cand.intermediateStopsCount) paradas · Pago QR"
                                        : "Ruta Externa · Abordaje libre",
                                    trailingValue: "\(cand.busRideMinutes)m",
                                    isLast: false
                                )

                                visualTimelineRow(
                                    icon: "mappin.and.ellipse",
                                    color: BCTheme.destructiveRed,
                                    title: selectedDestination.shortName,
                                    subtitle: cand.walkFinalMinutes > 0
                                        ? "Baja en \(cand.alightingPointName) · \(cand.walkFinalMeters) m"
                                        : "Baja en \(cand.alightingPointName)",
                                    trailingValue: cand.walkFinalMinutes > 0 ? "\(cand.walkFinalMinutes)m" : "Llegada",
                                    isLast: true
                                )
                            }
                        }
                        .padding(12)
                        .background(Color(hex: "#23252B"))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 10)
            }

            if let cand = cand {
                sheetBottomCTABar(candidate: cand, bottomPadding: bottomPadding)
            }
        }
    }

    // ——— NIVEL 3: TODAS LAS OPCIONES (Detalle completo pero limpio y minimalista) ———
    private func fullSheetContent(bottomPadding: CGFloat) -> some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 11) {
                    // Aviso compacto único superior si aplica ruta externa por falta de ordinarias
                    if let warning = evaluationResult?.primaryBannerWarning {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundColor(BCTheme.amber)
                            Text(warning)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(BCTheme.amber.opacity(0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(BCTheme.amber.opacity(0.4), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Chips de Filtro Rápido
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(RouteQuickFilter.allCases, id: \.self) { filter in
                                let active = selectedFilter == filter
                                Button {
                                    BCFeedbackManager.shared.impactLight()
                                    selectedFilter = filter
                                    selectedCandidateIndex = 0
                                    if let first = displayedCandidates.first {
                                        updatePolylinesAndCamera(for: first)
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

                    Text("OPCIONES DISPONIBLES (\(displayedCandidates.count))")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top, 2)

                    ForEach(Array(displayedCandidates.enumerated()), id: \.element.id) { idx, candidate in
                        evaluatedCandidateCard(candidate: candidate, index: idx)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 14)
            }

            if let cand = activeCandidate {
                sheetBottomCTABar(candidate: cand, bottomPadding: bottomPadding)
            }
        }
    }

    private func sheetBottomCTABar(candidate: EvaluatedRouteCandidate, bottomPadding: CGFloat) -> some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.08))
            Button {
                viewModel.startGuidedRoute(
                    from: selectedOrigin,
                    to: selectedDestination,
                    candidate: candidate,
                    optionIndex: selectedCandidateIndex
                )
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "location.north.fill")
                        .font(.subheadline.weight(.bold))
                    Text(
                        candidate.kind == .walkingDirect
                            ? "Iniciar caminata"
                            : "Ir con \(candidate.routeCode)"
                    )
                    .font(.subheadline.weight(.bold))

                    if candidate.kind == .ordinaryInService {
                        HStack(spacing: 3) {
                            Image(systemName: "bell.badge.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("5m")
                                .font(.system(size: 10.5, weight: .heavy))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.22))
                        .clipShape(Capsule())
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color(hex: "#34C759"))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, bottomPadding + 10)
        }
        .background(Color(hex: "#18191D").opacity(0.98))
    }

    // MARK: - Tarjeta de Candidato Evaluado en Nivel Grande (Detalle Completo Minimalista)
    private func evaluatedCandidateCard(candidate: EvaluatedRouteCandidate, index: Int) -> some View {
        let isSelected = selectedCandidateIndex == index
        let isOrd = candidate.kind == .ordinaryInService
        let isExt = candidate.kind == .externalFreeBoarding

        return Button {
            BCFeedbackManager.shared.impactLight()
            selectedCandidateIndex = index
            updatePolylinesAndCamera(for: candidate)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                // Cabecera: Código + Tipo + Sugerida + Tiempo/Distancia
                HStack(alignment: .center, spacing: 8) {
                    Text(candidate.routeCode)
                        .font(.system(size: 11.5, weight: .black).monospaced())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: candidate.colorHex))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    modeBadgePill(for: candidate)

                    if candidate.isRecommendedPrimary {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                            Text("Sugerida")
                                .font(.system(size: 9.5, weight: .bold))
                        }
                        .foregroundColor(Color(hex: "#4ADE80"))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        Text("~\(candidate.totalDurationMinutes) min")
                            .font(.subheadline.weight(.black).monospacedDigit())
                            .foregroundColor(candidate.isRecommendedPrimary ? Color(hex: "#4ADE80") : .white)
                        Text(candidate.totalDistanceLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.55))
                    }
                }

                // Cadena gráfica de tramos (Caminata -> Bus -> Caminata)
                journeyGraphicStrip(candidate: candidate)

                // Detalle concreto de paraderos/vía y servicio en 2 líneas limpias
                VStack(alignment: .leading, spacing: 4) {
                    if candidate.kind == .walkingDirect {
                        Label(
                            "\(selectedOrigin.shortName) → \(selectedDestination.shortName) (\(candidate.walkInitialMeters) m)",
                            systemImage: "figure.walk"
                        )
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.78))
                        .lineLimit(1)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: isOrd ? "mappin.circle.fill" : "road.lanes")
                                .font(.system(size: 10.5))
                                .foregroundColor(isOrd ? BCTheme.emerald : BCTheme.amber)
                            Text(
                                isOrd
                                    ? "Sube: \(candidate.boardingPointName) · Baja: \(candidate.alightingPointName)"
                                    : "Vía: \(candidate.boardingPointName) · Baja en vía"
                            )
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.white.opacity(0.84))
                            .lineLimit(1)
                        }
                    }

                    HStack(spacing: 12) {
                        if isOrd {
                            Label("QR \(formattedUserFare)", systemImage: "qrcode")
                                .foregroundColor(BCTheme.emerald)
                            Label("Aviso 5m", systemImage: "bell.badge.fill")
                                .foregroundColor(BCTheme.emerald)
                            Label("\(candidate.intermediateStopsCount) paradas", systemImage: "bus.fill")
                                .foregroundColor(.white.opacity(0.65))
                        } else if isExt {
                            Label("Sin GPS", systemImage: "location.slash.fill")
                                .foregroundColor(BCTheme.amber)
                            Label("Sin QR", systemImage: "xmark.circle")
                                .foregroundColor(BCTheme.amber)
                            Label("Abordaje en vía", systemImage: "hand.raised.fill")
                                .foregroundColor(.white.opacity(0.7))
                        } else {
                            Label("Sin costo · Ruta peatonal", systemImage: "leaf.fill")
                                .foregroundColor(BCTheme.cyanAccent)
                        }
                        Spacer()
                    }
                    .font(.system(size: 10, weight: .semibold))
                }
            }
            .padding(12)
            .background(Color(hex: "#212329"))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color(hex: "#0A84FF") : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Subvistas Auxiliares Minimalistas
    private func modeBadgePill(for candidate: EvaluatedRouteCandidate) -> some View {
        let isOrd = candidate.kind == .ordinaryInService
        let isExt = candidate.kind == .externalFreeBoarding
        let tint: Color = isOrd ? BCTheme.emerald : (isExt ? BCTheme.amber : BCTheme.cyanAccent)
        let label = isOrd ? "Ordinaria" : (isExt ? "Externa" : "A pie")
        let icon = isOrd ? "dot.radiowaves.left.and.right" : (isExt ? "exclamationmark.triangle.fill" : "figure.walk")

        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8.5, weight: .bold))
            Text(label)
                .font(.system(size: 9.5, weight: .heavy))
        }
        .foregroundColor(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.15))
        .clipShape(Capsule())
    }

    private func journeyGraphicStrip(candidate: EvaluatedRouteCandidate) -> some View {
        HStack(spacing: 6) {
            if candidate.kind == .walkingDirect {
                HStack(spacing: 4) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(BCTheme.cyanAccent)
                    Text("\(candidate.walkInitialMinutes)m · \(candidate.totalDistanceLabel)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundColor(.white.opacity(0.9))
                }
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(BCTheme.cyanAccent)
                    Text("\(candidate.walkInitialMinutes)m")
                        .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                        .foregroundColor(.white.opacity(0.85))
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))

                HStack(spacing: 4) {
                    Image(systemName: "bus.fill")
                        .font(.system(size: 9.5, weight: .bold))
                    Text("\(candidate.routeCode) · \(candidate.busRideMinutes)m")
                        .font(.system(size: 10.5, weight: .bold).monospaced())
                }
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color(hex: candidate.colorHex).opacity(0.32))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(hex: candidate.colorHex).opacity(0.8), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))

                if candidate.walkFinalMinutes > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.white.opacity(0.35))

                    HStack(spacing: 3) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(BCTheme.cyanAccent)
                        Text("\(candidate.walkFinalMinutes)m")
                            .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func visualTimelineRow(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        trailingValue: String,
        isLast: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.22))
                        .frame(width: 26, height: 26)
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(color)
                }
                if !isLast {
                    Rectangle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 2, height: 18)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer()

            Text(trailingValue)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundColor(color)
                .padding(.top, 4)
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
                        .foregroundColor(BCTheme.cyanAccent)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(hex: "#2C2C2E"))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func durationTabPill(candidate: EvaluatedRouteCandidate, index: Int) -> some View {
        let isSelected = selectedCandidateIndex == index
        let isOrd = candidate.kind == .ordinaryInService
        return Button {
            BCFeedbackManager.shared.impactLight()
            selectedCandidateIndex = index
            updatePolylinesAndCamera(for: candidate)
        } label: {
            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(isOrd ? BCTheme.emerald : (candidate.kind == .externalFreeBoarding ? BCTheme.amber : BCTheme.cyanAccent))
                        .frame(width: 6, height: 6)
                    Text("\(candidate.routeCode) · \(candidate.totalDurationMinutes)m")
                        .font(.caption.weight(isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                }
                Rectangle()
                    .fill(isSelected ? Color(hex: "#0A84FF") : Color.clear)
                    .frame(width: 58, height: 2.5)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Lógica de Búsqueda API, Selector en Mapa y Evaluación Automática
    private var filteredStopsInPlanner: [TacnaDestinationPlace] {
        let trimmed = plannerSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceList = viewModel.dynamicCatalogStops.isEmpty ? TacnaDestinationPlace.catalog : viewModel.dynamicCatalogStops
        if trimmed.isEmpty {
            return sourceList
        }
        let folded = AuthViewModel.normalizeSearchFold(trimmed)
        let tokens = folded.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return sourceList.filter { place in
            let haystack = AuthViewModel.normalizeSearchFold("\(place.name) \(place.shortName) \(place.subtitle)")
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    private func triggerLiveAPISearch(query: String, immediate: Bool = false) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            apiSearchResults = []
            isSearchingAPI = false
            return
        }
        isSearchingAPI = true
        searchTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 220_000_000)
            }
            guard !Task.isCancelled else { return }
            let results = await viewModel.searchMapKitPlacesInTacna(query: trimmed)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.apiSearchResults = results
                self.isSearchingAPI = false
            }
        }
    }

    private func openMapCrosshairPicker(for target: PlannerEndpointTarget) {
        let basePlace = (target == .origin) ? selectedOrigin : selectedDestination
        pickerCenterCoordinate = basePlace.coordinate
        pickerResolvedPlace = basePlace
        pickerMapCamera = .region(
            MKCoordinateRegion(
                center: basePlace.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.010, longitudeDelta: 0.010)
            )
        )
        withAnimation(.easeInOut(duration: 0.25)) {
            screenState = .mapPicker(target: target)
        }
    }

    private func selectEndpointAndContinue(_ place: TacnaDestinationPlace, for target: PlannerEndpointTarget) {
        BCFeedbackManager.shared.impactMedium()
        switch target {
        case .origin:
            selectedOrigin = place
            viewModel.routePlannerInitialOrigin = place
        case .destination:
            selectedDestination = place
            viewModel.routePlannerInitialDestination = place
        }
        recalculateAutomatedRoutes(resetSelection: true)
        withAnimation(.easeInOut(duration: 0.25)) {
            screenState = .routeMap
        }
    }

    private func swapOriginAndDestination() {
        BCFeedbackManager.shared.impactLight()
        let temp = selectedOrigin
        selectedOrigin = selectedDestination
        selectedDestination = temp
        recalculateAutomatedRoutes(resetSelection: true)
    }

    private func recalculateAutomatedRoutes(resetSelection: Bool) {
        let result = viewModel.evaluateAutomatedRoutes(from: selectedOrigin, to: selectedDestination)
        evaluationResult = result
        if resetSelection {
            selectedCandidateIndex = 0
            selectedFilter = .recommended
            sheetSnap = .compact
        }
        if let first = displayedCandidates.first ?? result.recommendedCandidate {
            updatePolylinesAndCamera(for: first)
        }
    }

    private func updatePolylinesAndCamera(for candidate: EvaluatedRouteCandidate) {
        let orig = selectedOrigin.coordinate
        let dest = selectedDestination.coordinate
        let midLat = (orig.latitude + dest.latitude) / 2.0 - 0.0020
        let midLon = (orig.longitude + dest.longitude) / 2.0
        let spanLat = max(abs(orig.latitude - dest.latitude) * 2.2, 0.014)
        let spanLon = max(abs(orig.longitude - dest.longitude) * 2.2, 0.014)

        withAnimation(.easeInOut(duration: 0.35)) {
            routeMapCamera = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: midLat, longitude: midLon),
                    span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon)
                )
            )
        }

        let rawWalk = candidate.walkToBoardCLCoordinates
        let rawBus = candidate.busTransitCLCoordinates
        let rawFinal = candidate.walkFinalCLCoordinates

        plannerWalkStreetCoords = rawWalk
        plannerBusStreetCoords = rawBus
        plannerFinalWalkStreetCoords = rawFinal

        let candidateId = candidate.id
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
                waypoints: rawFinal,
                transportType: .walking
            )
            let (wCoords, bCoords, fCoords) = await (walkAligned, busAligned, finalAligned)
            await MainActor.run {
                if activeCandidate?.id == candidateId {
                    plannerWalkStreetCoords = wCoords
                    plannerBusStreetCoords = bCoords
                    plannerFinalWalkStreetCoords = fCoords
                }
            }
        }
    }

    private var formattedUserFare: String {
        if let user = viewModel.currentUser {
            return String(format: "S/. %.2f", user.roleType.farePen)
        }
        return "S/. 0.70"
    }

    private func currentSheetHeight(in totalHeight: CGFloat, bottomInset: CGFloat) -> CGFloat {
        let safeBottom = max(bottomInset, 18)
        let base = sheetSnap.height(in: totalHeight, bottomInset: safeBottom)
        let minH = RouteSheetSnapLevel.compact.height(in: totalHeight, bottomInset: safeBottom) - 24
        let maxH = RouteSheetSnapLevel.full.height(in: totalHeight, bottomInset: safeBottom) + 28
        return min(max(base - sheetDragTranslation, minH), maxH)
    }
}

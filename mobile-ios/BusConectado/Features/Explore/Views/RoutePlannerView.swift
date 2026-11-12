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
    case compact    // Nivel 1: Compacto (Peek ~215pt)
    case medium     // Nivel 2: Detalle Intermedio (Medium ~420pt)
    case full       // Nivel 3: Todas las Opciones (Full ~84%)

    func height(in totalHeight: CGFloat) -> CGFloat {
        switch self {
        case .compact:
            return 225
        case .medium:
            return min(max(totalHeight * 0.52, 390), 460)
        case .full:
            return totalHeight * 0.84
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

    // MARK: - Hoja Inferior Interactiva de 3 Niveles
    private func interactiveBottomSheet(totalHeight: CGFloat) -> some View {
        let targetHeight = currentSheetHeight(in: totalHeight)

        return VStack(spacing: 0) {
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
                        .foregroundColor(.white.opacity(0.45))
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
        let cand = activeCandidate

        return VStack(alignment: .leading, spacing: 10) {
            // Pestañas rápidas de las primeras opciones evaluadas
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(displayedCandidates.prefix(4).enumerated()), id: \.element.id) { idx, item in
                        durationTabPill(candidate: item, index: idx)
                    }
                }
            }

            // Aviso prominente si la opción sugerida/activa es una Ruta Externa o si es Ruta Ordinaria con aviso automático a 5 min
            if let cand = cand {
                if cand.kind == .externalFreeBoarding {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(BCTheme.amber)
                            .padding(.top, 1)
                        Text(
                            evaluationResult?.primaryBannerWarning
                                ?? "⚠️ Ruta Externa (\(cand.routeCode)): Abordaje en cualquier parte de la ruta • Sin tracking GPS ni aviso de paradero."
                        )
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(BCTheme.amber)
                        .lineLimit(2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(BCTheme.amber.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if cand.kind == .ordinaryInService {
                    HStack(spacing: 6) {
                        Image(systemName: "bell.badge.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(BCTheme.emerald)
                        Text("Subir en Paradero \(cand.boardingPointName) • Al iniciar recibirás aviso automático a 5 min del bus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(BCTheme.emerald)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(BCTheme.emerald.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // Botones de Acción: [Ir / Iniciar] + [Ver Opciones (Ordinarias y Externas)]
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
                    HStack(spacing: 6) {
                        Image(systemName: "location.north.fill")
                            .font(.subheadline.weight(.bold))
                        Text(
                            cand?.kind == .ordinaryInService
                                ? "Ir (Activa aviso a 5 min)"
                                : "Ir con esta ruta"
                        )
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
                        sheetSnap = .full
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.and.down.text.horizontal")
                            .font(.caption.weight(.bold))
                        Text("Ver todas (\(displayedCandidates.count))")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Color(hex: "#2C2C2E"))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    // ——— NIVEL 2: DETALLE INTERMEDIO (Medium) ———
    private var mediumSheetContent: some View {
        let cand = activeCandidate

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                if let cand = cand {
                    HStack(alignment: .firstTextBaseline) {
                        Text("~\(cand.totalDurationMinutes) min")
                            .font(.title2.weight(.black))
                            .foregroundColor(.white)

                        Text("· \(cand.totalDistanceLabel)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white.opacity(0.65))

                        Spacer()

                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                sheetSnap = .full
                            }
                        } label: {
                            Text("Comparar ordinarias y externas ›")
                                .font(.caption.weight(.bold))
                                .foregroundColor(Color(hex: "#0A84FF"))
                        }
                    }

                    // Aviso o Estado Operativo según Tipo de Ruta
                    if cand.kind == .externalFreeBoarding {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(BCTheme.amber)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ruta Externa de Tacna (\(cand.routeCode)) • Sin Tracking GPS")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(BCTheme.amber)
                                Text(
                                    evaluationResult?.primaryBannerWarning
                                        ?? "En las rutas externas no necesitas caminar a un paradero fijo: puedes subir y bajar en cualquier punto de la calle por donde pasa la ruta. No incluye pago QR ni notificaciones de llegada."
                                )
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.85))
                            }
                        }
                        .padding(10)
                        .background(BCTheme.amber.opacity(0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(BCTheme.amber.opacity(0.45), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else if cand.kind == .ordinaryInService {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "bell.badge.fill")
                                .foregroundColor(BCTheme.emerald)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ruta Ordinaria en Servicio (\(cand.routeCode)) • Tracking & Pago QR")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(BCTheme.emerald)
                                Text("Abordaje en Paradero Oficial \(cand.boardingPointName). Al presionar 'Ir', recibirás automáticamente una notificación cuando el bus se encuentre a 5 minutos del paradero establecido.")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.85))
                            }
                        }
                        .padding(10)
                        .background(BCTheme.emerald.opacity(0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(BCTheme.emerald.opacity(0.45), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Desglose Paso a Paso Calculado por el Motor
                    VStack(alignment: .leading, spacing: 8) {
                        if cand.kind == .walkingDirect {
                            stepRow(
                                icon: "figure.walk",
                                bgHex: "#1E3A8A",
                                iconColor: Color(hex: "#93C5FD"),
                                text: "Camina \(cand.walkInitialMinutes) min (\(cand.walkInitialMeters) m) desde \(selectedOrigin.shortName) hasta \(selectedDestination.shortName)"
                            )
                        } else {
                            let isOrd = cand.kind == .ordinaryInService
                            stepRow(
                                icon: "figure.walk",
                                bgHex: "#1E3A8A",
                                iconColor: Color(hex: "#93C5FD"),
                                text: isOrd
                                    ? "1. Camina \(cand.walkInitialMinutes) min (\(cand.walkInitialMeters) m) hasta el Paradero \(cand.boardingPointName)"
                                    : "1. Camina \(cand.walkInitialMinutes) min (\(cand.walkInitialMeters) m) hasta la vía de \(cand.routeCode) (\(cand.boardingPointName))"
                            )

                            stepRow(
                                icon: "bus.fill",
                                bgHex: isOrd ? "#14532D" : "#78350F",
                                iconColor: isOrd ? Color(hex: "#86EFAC") : Color(hex: "#FCD34D"),
                                text: isOrd
                                    ? "2. Sube a \(cand.routeCode) (Ordinaria • \(formattedUserFare)) · Viaja ~\(cand.busRideMinutes) min (\(cand.intermediateStopsCount) paradas intermedias)"
                                    : "2. Toma \(cand.routeCode) en cualquier punto de la calle (Externa • Sin QR) · Viaja ~\(cand.busRideMinutes) min"
                            )

                            stepRow(
                                icon: "mappin.and.ellipse",
                                bgHex: "#1E3A8A",
                                iconColor: Color(hex: "#93C5FD"),
                                text: cand.walkFinalMinutes > 0
                                    ? "3. Baja en \(cand.alightingPointName) y camina \(cand.walkFinalMinutes) min (\(cand.walkFinalMeters) m) hasta \(selectedDestination.shortName)"
                                    : "3. Baja en \(cand.alightingPointName) (frente a \(selectedDestination.shortName))"
                            )
                        }
                    }
                    .padding(12)
                    .background(Color(hex: "#2C2C2E"))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    HStack(spacing: 10) {
                        Button {
                            viewModel.startGuidedRoute(
                                from: selectedOrigin,
                                to: selectedDestination,
                                candidate: cand,
                                optionIndex: selectedCandidateIndex
                            )
                            dismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "location.north.fill")
                                    .font(.subheadline.weight(.bold))
                                Text(
                                    cand.kind == .ordinaryInService
                                        ? "Ir (Notificar a 5 min del paradero)"
                                        : "Ir con esta ruta"
                                )
                                .font(.subheadline.weight(.bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color(hex: "#34C759"))
                            .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    // ——— NIVEL 3: TODAS LAS OPCIONES (Rutas Ordinarias + Rutas Externas + Caminata) ———
    private var fullSheetContent: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    // Banner de advertencia general si se está sugiriendo una Ruta Externa por falta de Ordinarias o por exceso de tiempo/caminata
                    if let warning = evaluationResult?.primaryBannerWarning {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundColor(BCTheme.amber)
                                .padding(.top, 2)
                            Text(warning)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .background(BCTheme.amber.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(BCTheme.amber.opacity(0.5), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
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

                    Text("OPCIONES EVALUADAS ENTRE RUTAS ORDINARIAS, EXTERNAS Y CAMINATA (\(displayedCandidates.count))")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top, 2)

                    ForEach(Array(displayedCandidates.enumerated()), id: \.element.id) { idx, candidate in
                        evaluatedCandidateCard(candidate: candidate, index: idx)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 14)
            }

            // Botón Inferior Fijo [Ir / Iniciar Guía en el Mapa]
            if let cand = activeCandidate {
                VStack(spacing: 0) {
                    Divider().background(Color(hex: "#2C2C2E"))
                    Button {
                        viewModel.startGuidedRoute(
                            from: selectedOrigin,
                            to: selectedDestination,
                            candidate: cand,
                            optionIndex: selectedCandidateIndex
                        )
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "location.north.fill")
                                .font(.subheadline.weight(.bold))
                            Text(
                                cand.kind == .ordinaryInService
                                    ? "Ir con \(cand.routeCode) (Aviso auto. a 5 min del paradero)"
                                    : "Ir con \(cand.routeCode)"
                            )
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
    }

    // MARK: - Tarjeta de Candidato Evaluado (Ordinaria vs Externa vs A Pie)
    private func evaluatedCandidateCard(candidate: EvaluatedRouteCandidate, index: Int) -> some View {
        let isSelected = selectedCandidateIndex == index
        let isOrd = candidate.kind == .ordinaryInService
        let isExt = candidate.kind == .externalFreeBoarding

        return Button {
            BCFeedbackManager.shared.impactLight()
            selectedCandidateIndex = index
            updatePolylinesAndCamera(for: candidate)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(hex: candidate.colorHex).opacity(0.22))
                                .frame(width: 36, height: 36)
                            Image(systemName: candidate.kind == .walkingDirect ? "figure.walk" : "bus.fill")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(Color(hex: candidate.colorHex))
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(candidate.routeCode)
                                    .font(.system(size: 11, weight: .black).monospaced())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color(hex: candidate.colorHex))
                                    .clipShape(RoundedRectangle(cornerRadius: 5))

                                Text(
                                    isOrd
                                        ? "ORDINARIA • TRACKING & QR"
                                        : (isExt ? "EXTERNA • ABORDAJE EN VÍA" : "PEATONAL")
                                )
                                .font(.system(size: 8.5, weight: .heavy))
                                .foregroundColor(isOrd ? BCTheme.emerald : (isExt ? BCTheme.amber : BCTheme.cyanAccent))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background((isOrd ? BCTheme.emerald : (isExt ? BCTheme.amber : BCTheme.cyanAccent)).opacity(0.15))
                                .clipShape(Capsule())

                                if candidate.isRecommendedPrimary {
                                    Text("★ Sugerida")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(Color(hex: "#4ADE80"))
                                }
                            }

                            if candidate.kind == .walkingDirect {
                                Text("Caminata directa (\(candidate.totalDistanceLabel)) de \(selectedOrigin.shortName) a \(selectedDestination.shortName)")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.75))
                                    .multilineTextAlignment(.leading)
                            } else if isOrd {
                                Text("Subir en Paradero \(candidate.boardingPointName) (\(candidate.walkInitialMinutes)m a pie) → Bajar en Paradero \(candidate.alightingPointName) (\(candidate.walkFinalMinutes)m a pie)")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.8))
                                    .multilineTextAlignment(.leading)
                            } else {
                                Text("Subir en cualquier punto de la vía (\(candidate.boardingPointName), a \(candidate.walkInitialMinutes)m) → Bajar en vía (\(candidate.walkFinalMinutes)m a pie)")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.8))
                                    .multilineTextAlignment(.leading)
                            }
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("~\(candidate.totalDurationMinutes) min")
                            .font(.subheadline.weight(.black).monospacedDigit())
                            .foregroundColor(candidate.isRecommendedPrimary ? Color(hex: "#4ADE80") : .white)
                        Text(candidate.totalDistanceLabel)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(.white.opacity(0.55))
                    }
                }

                Divider().background(Color(hex: "#2C2C2E"))

                HStack {
                    if isOrd {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 10))
                            .foregroundColor(BCTheme.emerald)
                        Text("Tarifa QR: \(formattedUserFare) • Notificación automática a 5 min del paradero")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(BCTheme.emerald)
                    } else if isExt {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(BCTheme.amber)
                        Text("Ruta Externa referencial: Sin tracking GPS, sin pago QR ni avisos de paradero")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(BCTheme.amber)
                    } else {
                        Text("Sin costo (Gratis) · Ruta peatonal por las calles de Tacna")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.65))
                    }
                    Spacer()
                }
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

    private func stepRow(icon: String, bgHex: String, iconColor: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
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
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
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

    private var sheetSnapLabel: String {
        switch sheetSnap {
        case .compact: return "Desliza hacia arriba para ver pasos y todas las rutas (Ordinarias y Externas)"
        case .medium: return "Desliza hacia arriba para comparar todas las rutas disponibles"
        case .full: return "Toca para contraer hoja de rutas"
        }
    }

    private func currentSheetHeight(in totalHeight: CGFloat) -> CGFloat {
        let base = sheetSnap.height(in: totalHeight)
        let adjusted = base - sheetDragTranslation
        return min(max(adjusted, 195), totalHeight * 0.88)
    }
}

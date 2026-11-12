import Foundation
import Combine
import UIKit
import CoreLocation
import MapKit

enum OnboardingStep {
    case splash
    case phoneInput
    case otpVerification
    case success
}

enum MapFilterCategory: String, CaseIterable {
    case live = "En vivo"
    case routes = "Rutas"
    case stops = "Paraderos"
}

@MainActor
final class AuthViewModel: ObservableObject {
    // MARK: - Estado de Autenticación y Navegación
    @Published var currentStep: OnboardingStep = .splash
    @Published var selectedTab: Int = 0
    @Published var phoneNumber: String = ""
    @Published var otpCode: String = ""
    @Published var isGuestMode: Bool = false
    @Published var isLoggedIn: Bool = false
    @Published var currentUser: UserAuth? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var countdownSeconds: Int = 59
    @Published var backendHost: String = "34.44.71.179.sslip.io"
    @Published var isConnectedToBackend: Bool = false

    // MARK: - Estado del Monedero y Movimientos (CU-05 / CU-08)
    // Para cuentas de prueba o cuentas nuevas inicia estrictamente en [] (0 movimientos y 0 puntos)
    @Published var transactions: [LedgerTransactionItem] = []

    // MARK: - Estado de la Red de Transporte (CU-07)
    // Por requerimiento de cuentas de prueba: inicia vacío ([]), sin paraderos ni buses falsos.
    // Cuando el backend o el sistema registre rutas/paraderos/buses activos, se poblarán aquí y la UI los pintará automáticamente.
    @Published var routes: [BusRouteModel] = []
    @Published var stops: [BusStopModel] = []
    @Published var activeBuses: [ActiveBusModel] = []
    @Published var mapCategory: MapFilterCategory = .live
    @Published var searchQuery: String = ""

    // MARK: - Estado de Viaje en Curso (CU-06), Buscador Predictivo y Módulo "Ir / Cómo Llegar"
    @Published var activeTrip: ActiveTripState? = nil
    @Published var activeArrivalAlert: ArrivalAlertState? = nil
    @Published var showInsufficientBalanceModal: Bool = false
    @Published var requiredPointsForAttempt: Int = 0

    // Catálogo Dinámico de Paraderos y Rutas (Sincronizados con el Administrador Web y Servidor Cloud)
    @Published var dynamicCatalogStops: [TacnaDestinationPlace] = TacnaDestinationPlace.catalog
    @Published var dynamicRoutes: [TacnaOfficialRouteCatalogItem] = TacnaOfficialRouteCatalogItem.officialRoutes

    // Estado del Buscador Predictivo y Pin de Destino Buscado
    @Published var isSearchDropdownVisible: Bool = false
    @Published var searchedDestinationPin: TacnaDestinationPlace? = nil
    @Published var isEmptyTransitBannerDismissed: Bool = false
    @Published var liveMapSearchResults: [TacnaDestinationPlace] = []
    @Published var isSearchingMapPlaces: Bool = false
    @Published var activeRouteOverlayOnMap: TacnaOfficialRouteCatalogItem? = nil

    // Estado del Escenario Pantalla Completa "Ir / Cómo Llegar" (Automatización de Rutas)
    @Published var showRoutePlannerFullScreen: Bool = false
    @Published var routePlannerInitialOrigin: TacnaDestinationPlace? = nil
    @Published var routePlannerInitialDestination: TacnaDestinationPlace? = nil
    @Published var recentSearchedPlaces: [TacnaDestinationPlace] = []
    @Published var carnetReviewRequest: CarnetReviewRequest? = nil
    @Published var activeRouteGuidance: ActiveRouteGuidanceState? = nil
    @Published var showCancelRouteGuidanceAlert: Bool = false
    @Published var showFiveMinuteBoardingBanner: Bool = false
    @Published var showExternalGuidancePopup: Bool = false

    // Control de Cámara del Mapa en Tacna
    @Published var mapFocusTrigger: UUID = UUID()
    @Published var mapFocusTargetCoordinate: CLLocationCoordinate2D? = nil
    @Published var mapFocusSpanDelta: Double = 0.018

    private var countdownTimer: AnyCancellable?
    private var arrivalAlertTimer: AnyCancellable?
    private var routeGuidanceTimer: AnyCancellable?
    private var appForegroundCancellable: AnyCancellable?
    private var searchDebounceCancellable: AnyCancellable?
    private var liveSearchTask: Task<Void, Never>?
    private var liveSearchToken: Int = 0
    private var lastSyncDate: Date? = nil

    init() {
        if let savedHost = UserDefaults.standard.string(forKey: "bc_backend_host") {
            let host = (savedHost.contains("34.61.17.233") || savedHost == "34.44.71.179" || savedHost == "172.20.10.11:8000" || savedHost == "localhost:8000") ? "34.44.71.179.sslip.io" : savedHost
            self.backendHost = host
            APIClient.shared.updateBaseURL(host)
        } else {
            self.backendHost = "34.44.71.179.sslip.io"
            APIClient.shared.updateBaseURL("https://34.44.71.179.sslip.io")
        }

        // Cargar paraderos y rutas cacheados previamente de la última sincronización con el Administrador Web
        if let stopsData = UserDefaults.standard.data(forKey: "bc_cached_stops"),
           let cachedDTOs = try? JSONDecoder().decode([AdminStopDTO].self, from: stopsData),
           !cachedDTOs.isEmpty {
            self.dynamicCatalogStops = cachedDTOs.map { $0.toDestinationPlace() }
        }

        if let routesData = UserDefaults.standard.data(forKey: "bc_cached_routes"),
           let cachedRouteDTOs = try? JSONDecoder().decode([AdminRouteDTO].self, from: routesData),
           !cachedRouteDTOs.isEmpty {
            self.dynamicRoutes = cachedRouteDTOs.map { $0.toRouteCatalogItem() }
        }

        self.loadRecentSearchedPlaces()

        if let token = KeychainService.shared.get(key: "access_token"), !token.isEmpty {
            if let userData = UserDefaults.standard.data(forKey: "bc_active_user"),
               let profile = try? JSONDecoder().decode(UserAuth.self, from: userData) {
                self.currentUser = profile
                self.isLoggedIn = true
                self.loadLocalTransactions(for: profile.phone)
                self.loadCarnetReviewRequest(for: profile.phone)
            }
        }

        // Sincronización automática de paraderos al arrancar la app
        Task {
            await self.refreshStateFromBackendIfAvailable(isManual: false)
        }

        setupSmartSync()

        // Búsqueda en vivo de cualquier lugar del mapa de Tacna (Apple MapKit + Completer + OSM Photon/Nominatim)
        searchDebounceCancellable = $searchQuery
            .removeDuplicates()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] query in
                guard let self = self else { return }
                self.liveSearchTask?.cancel()
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 2 else {
                    self.liveMapSearchResults = []
                    self.isSearchingMapPlaces = false
                    return
                }
                self.liveSearchTask = Task { [weak self] in
                    await self?.performLiveMapKitSearchInTacna(query: trimmed)
                }
            }
    }

    var isValidPhone: Bool {
        let cleaned = phoneNumber.filter { $0.isNumber }
        return cleaned.count == 9 && cleaned.hasPrefix("9")
    }

    var normalizedPhone: String {
        let cleaned = phoneNumber.filter { $0.isNumber }
        return "+51\(cleaned)"
    }

    // MARK: - Filtros Dinámicos del Mapa (Listos para cuando existan paraderos y buses)
    var filteredStops: [BusStopModel] {
        guard mapCategory == .stops else { return [] }
        if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            return stops
        }
        return stops.filter {
            $0.name.localizedCaseInsensitiveContains(searchQuery) ||
            $0.subtitle.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var filteredBuses: [ActiveBusModel] {
        guard mapCategory == .live || mapCategory == .routes else { return [] }
        return activeBuses
    }

    /// Normaliza texto eliminando tildes y mayúsculas para coincidencias tolerantes ("polleria" == "Pollería")
    nonisolated static func normalizeSearchFold(_ raw: String) -> String {
        raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_PE"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Catálogo predictivo para el buscador superior:
    /// Prioriza las ubicaciones reales devueltas por el motor híbrido (Apple MapKit + OSM) seguidas de paraderos oficiales coincidentes.
    var filteredSearchDestinations: [TacnaDestinationPlace] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return dynamicCatalogStops
        }
        let foldedQuery = Self.normalizeSearchFold(trimmed)
        let queryTokens = foldedQuery.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let catalogMatches = dynamicCatalogStops.filter { place in
            let haystack = Self.normalizeSearchFold(
                "\(place.name) \(place.shortName) \(place.subtitle) \(place.category.rawValue) \(place.routesPassing.joined(separator: " "))"
            )
            if queryTokens.isEmpty { return false }
            return queryTokens.allSatisfy { haystack.contains($0) }
        }
        return liveMapSearchResults + catalogMatches
    }

    func performLiveMapKitSearchInTacna(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            await MainActor.run {
                self.liveMapSearchResults = []
                self.isSearchingMapPlaces = false
            }
            return
        }

        liveSearchToken += 1
        let requestToken = liveSearchToken
        isSearchingMapPlaces = true

        let results = await searchMapKitPlacesInTacna(query: trimmed)
        guard !Task.isCancelled else { return }

        await MainActor.run {
            guard requestToken == self.liveSearchToken else { return }
            self.liveMapSearchResults = results
            self.isSearchingMapPlaces = false
        }
    }

    /// Motor híbrido de búsqueda en Tacna: combina Apple MapKit (MKLocalSearch + MKLocalSearchCompleter)
    /// y OpenStreetMap (Photon + Nominatim) en paralelo para encontrar comercios locales, pollerías, ferias y calles.
    func searchMapKitPlacesInTacna(query: String) async -> [TacnaDestinationPlace] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            return []
        }

        let tacnaCenter = CLLocationCoordinate2D(latitude: -18.0135, longitude: -70.2519)
        let tacnaRegion = MKCoordinateRegion(
            center: tacnaCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.24, longitudeDelta: 0.24)
        )

        async let directMapKit = Self.searchAppleMapKitDirect(query: trimmed, region: tacnaRegion)
        async let completerMapKit = Self.searchAppleMapKitCompleter(query: trimmed, region: tacnaRegion)
        async let photonOSM = Self.searchPhotonOSMPlaces(query: trimmed)
        async let nominatimOSM = Self.searchNominatimOSMPlaces(query: trimmed)

        let combined = await directMapKit + completerMapKit + photonOSM + nominatimOSM

        // Deduplicar por nombre normalizado y proximidad (~130m) y filtrar estrictamente dentro de Tacna metropolitana
        var deduplicated: [TacnaDestinationPlace] = []
        for candidate in combined {
            guard candidate.latitude >= -18.35 && candidate.latitude <= -17.70,
                  candidate.longitude >= -70.65 && candidate.longitude <= -69.95 else {
                continue
            }
            let candFolded = Self.normalizeSearchFold(candidate.name)
            let isDuplicate = deduplicated.contains { existing in
                let latDiff = abs(existing.latitude - candidate.latitude)
                let lonDiff = abs(existing.longitude - candidate.longitude)
                let sameSpot = latDiff < 0.0012 && lonDiff < 0.0012
                let existingFolded = Self.normalizeSearchFold(existing.name)
                return sameSpot && (existingFolded == candFolded || existingFolded.contains(candFolded) || candFolded.contains(existingFolded))
            }
            if !isDuplicate {
                deduplicated.append(candidate)
            }
        }

        let foldedQuery = Self.normalizeSearchFold(trimmed)
        let queryTokens = foldedQuery.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let centerLoc = CLLocation(latitude: tacnaCenter.latitude, longitude: tacnaCenter.longitude)

        return deduplicated
            .sorted { lhs, rhs in
                let lName = Self.normalizeSearchFold(lhs.name)
                let rName = Self.normalizeSearchFold(rhs.name)
                let lExact = lName.contains(foldedQuery) ? 2 : queryTokens.filter { lName.contains($0) }.count
                let rExact = rName.contains(foldedQuery) ? 2 : queryTokens.filter { rName.contains($0) }.count
                if lExact != rExact {
                    return lExact > rExact
                }
                let lDist = CLLocation(latitude: lhs.latitude, longitude: lhs.longitude).distance(from: centerLoc)
                let rDist = CLLocation(latitude: rhs.latitude, longitude: rhs.longitude).distance(from: centerLoc)
                return lDist < rDist
            }
            .prefix(15)
            .map { $0 }
    }

    private nonisolated static func searchAppleMapKitDirect(query: String, region: MKCoordinateRegion) async -> [TacnaDestinationPlace] {
        // Sin agregar ", Tacna, Perú" para no romper la búsqueda de POIs locales en Apple MapKit
        let primaryReq = MKLocalSearch.Request()
        primaryReq.naturalLanguageQuery = query
        primaryReq.resultTypes = [.pointOfInterest, .address]
        primaryReq.region = region

        var collected: [MKMapItem] = []
        if let response = try? await MKLocalSearch(request: primaryReq).start() {
            collected.append(contentsOf: response.mapItems)
        }

        if collected.count < 4, !normalizeSearchFold(query).contains("tacna") {
            let scopedReq = MKLocalSearch.Request()
            scopedReq.naturalLanguageQuery = "\(query) Tacna"
            scopedReq.resultTypes = [.pointOfInterest, .address]
            scopedReq.region = region
            if let scopedResp = try? await MKLocalSearch(request: scopedReq).start() {
                collected.append(contentsOf: scopedResp.mapItems)
            }
        }

        return collected.prefix(10).compactMap { mapItemToDestinationPlace($0, sourceLabel: "Apple Maps") }
    }

    @MainActor
    private static func searchAppleMapKitCompleter(query: String, region: MKCoordinateRegion) async -> [TacnaDestinationPlace] {
        let completions = await TacnaMapCompleterHelper.fetchCompletions(query: query, region: region)
        guard !completions.isEmpty else { return [] }

        return await withTaskGroup(of: [TacnaDestinationPlace].self) { group in
            for completion in completions.prefix(6) {
                group.addTask {
                    let req = MKLocalSearch.Request(completion: completion)
                    req.region = region
                    guard let response = try? await MKLocalSearch(request: req).start() else { return [] }
                    return response.mapItems.prefix(2).compactMap {
                        mapItemToDestinationPlace($0, sourceLabel: "Apple Maps")
                    }
                }
            }
            var resolved: [TacnaDestinationPlace] = []
            for await items in group {
                resolved.append(contentsOf: items)
            }
            return resolved
        }
    }

    private nonisolated static func mapItemToDestinationPlace(_ item: MKMapItem, sourceLabel: String) -> TacnaDestinationPlace? {
        guard let name = item.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let coord = item.placemark.coordinate
        guard CLLocationCoordinate2DIsValid(coord) else { return nil }

        let street = [item.placemark.thoroughfare, item.placemark.subThoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
        let subLocality = item.placemark.subLocality ?? ""
        let locality = item.placemark.locality ?? "Tacna"
        let addressParts = [street, subLocality, locality].filter { !$0.isEmpty }
        let addressDesc = addressParts.isEmpty ? "Tacna" : addressParts.joined(separator: ", ")

        return TacnaDestinationPlace.fromMapItem(
            name: name,
            subtitle: "📍 \(addressDesc) • \(sourceLabel)",
            coordinate: coord
        )
    }

    private nonisolated static func searchPhotonOSMPlaces(query: String) async -> [TacnaDestinationPlace] {
        var components = URLComponents(string: "https://photon.komoot.io/api/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "lat", value: "-18.0135"),
            URLQueryItem(name: "lon", value: "-70.2519"),
            URLQueryItem(name: "bbox", value: "-70.55,-18.25,-70.00,-17.75"),
            URLQueryItem(name: "limit", value: "10")
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 3.5

        struct PhotonResponse: Decodable {
            struct Feature: Decodable {
                struct Geometry: Decodable {
                    let coordinates: [Double]
                }
                struct Properties: Decodable {
                    let name: String?
                    let street: String?
                    let housenumber: String?
                    let district: String?
                    let city: String?
                }
                let geometry: Geometry
                let properties: Properties
            }
            let features: [Feature]
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(PhotonResponse.self, from: data) else {
            return []
        }

        return decoded.features.compactMap { feature in
            guard feature.geometry.coordinates.count >= 2 else { return nil }
            let lon = feature.geometry.coordinates[0]
            let lat = feature.geometry.coordinates[1]
            let props = feature.properties
            let streetPart = [props.street, props.housenumber].compactMap { $0 }.joined(separator: " ")
            let placeName = props.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = (placeName?.isEmpty == false ? placeName! : streetPart)
            guard !resolvedName.isEmpty else { return nil }

            let district = props.district ?? props.city ?? "Tacna"
            let addressDesc = [streetPart, district].filter { !$0.isEmpty }.joined(separator: ", ")
            return TacnaDestinationPlace.fromMapItem(
                name: resolvedName,
                subtitle: "📍 \(addressDesc.isEmpty ? "Tacna" : addressDesc) • Mapa OSM",
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
            )
        }
    }

    private nonisolated static func searchNominatimOSMPlaces(query: String) async -> [TacnaDestinationPlace] {
        var components = URLComponents(string: "https://nominatim.openstreetmap.org/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "viewbox", value: "-70.55,-17.75,-70.00,-18.25"),
            URLQueryItem(name: "bounded", value: "1"),
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "addressdetails", value: "1"),
            URLQueryItem(name: "limit", value: "8")
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 3.5
        request.setValue("BusConectado-iOS/1.0", forHTTPHeaderField: "User-Agent")

        struct NominatimItem: Decodable {
            let lat: String
            let lon: String
            let name: String?
            let display_name: String?
            let address: NominatimAddress?
        }
        struct NominatimAddress: Decodable {
            let road: String?
            let suburb: String?
            let city_district: String?
            let town: String?
            let city: String?
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode([NominatimItem].self, from: data) else {
            return []
        }

        return decoded.compactMap { item in
            guard let lat = Double(item.lat), let lon = Double(item.lon) else { return nil }
            let rawName = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackName = item.display_name?.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            let resolvedName = (rawName?.isEmpty == false ? rawName! : fallbackName) ?? ""
            guard !resolvedName.isEmpty else { return nil }

            let road = item.address?.road ?? ""
            let zone = item.address?.suburb ?? item.address?.city_district ?? item.address?.town ?? item.address?.city ?? "Tacna"
            let addressDesc = [road, zone].filter { !$0.isEmpty }.joined(separator: ", ")

            return TacnaDestinationPlace.fromMapItem(
                name: resolvedName,
                subtitle: "📍 \(addressDesc.isEmpty ? "Tacna" : addressDesc) • Mapa OSM",
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
            )
        }
    }

    /// Obtiene el nombre real de la calle o punto de interés en Tacna cuando el usuario fija un punto libre en el mapa
    func reverseGeocodeCoordinateInTacna(_ coordinate: CLLocationCoordinate2D, roleLabel: String = "Punto en el mapa") async -> TacnaDestinationPlace {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let pm = placemarks.first {
                let street = [pm.thoroughfare, pm.subThoroughfare].compactMap { $0 }.joined(separator: " ")
                let area = pm.subLocality ?? pm.locality ?? "Tacna"
                let title = !street.isEmpty ? street : (pm.name ?? roleLabel)
                let sub = "📍 \(area) (\(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)))"
                return TacnaDestinationPlace.fromMapItem(
                    name: title,
                    subtitle: sub,
                    coordinate: coordinate
                )
            }
        } catch {
            // Fallback a coordenada formateada
        }
        return TacnaDestinationPlace.fromMapItem(
            name: "\(roleLabel) (\(String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)))",
            subtitle: "📍 Punto personalizado en Tacna",
            coordinate: coordinate
        )
    }

    /// Evalúa automáticamente las mejores opciones de ruta (Ordinarias en servicio, Externas en vía y Caminata)
    func evaluateAutomatedRoutes(
        from origin: TacnaDestinationPlace,
        to destination: TacnaDestinationPlace
    ) -> RouteAutomationEvaluationResult {
        RouteAutomationEngine.evaluateRoutes(
            from: origin,
            to: destination,
            stops: dynamicCatalogStops,
            routes: dynamicRoutes,
            activeBuses: activeBuses
        )
    }

    /// Proyecta una Ruta (Ordinaria o Externa) desde la pestaña Líneas directamente sobre el mapa principal
    func projectRouteOnMainMap(_ route: TacnaOfficialRouteCatalogItem) {
        BCFeedbackManager.shared.impactMedium()
        self.activeRouteOverlayOnMap = route
        self.selectedTab = 0
        let coords = route.resolvedPolylineCoordinates(using: dynamicCatalogStops)
        if let first = coords.first, let last = coords.last {
            let midLat = (first.latitude + last.latitude) / 2.0
            let midLon = (first.longitude + last.longitude) / 2.0
            let span = max(abs(first.latitude - last.latitude) * 1.6, 0.032)
            focusMap(on: CLLocationCoordinate2D(latitude: midLat, longitude: midLon), spanDelta: span)
        }
    }

    // MARK: - Reglas de Dominio para Rutas Ordinarias vs Externas y Disponibilidad de Notificación en Paraderos

    /// Busca una ruta en el catálogo dinámico por su código (ej: "Ruta 14", "RUTA 10B", "Ruta 101")
    func routeItem(forCode rawCode: String) -> TacnaOfficialRouteCatalogItem? {
        let normalized = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return dynamicRoutes.first {
            $0.code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
        }
    }

    /// Devuelve todas las rutas sincronizadas (Ordinarias y Externas) que pasan por un paradero dado
    func catalogRoutes(for stop: TacnaDestinationPlace) -> [TacnaOfficialRouteCatalogItem] {
        guard stop.category != .mapCustomPlace else { return [] }
        var matched: [TacnaOfficialRouteCatalogItem] = []

        // 1. Por códigos registrados en routesPassing del paradero
        for code in stop.routesPassing {
            if let route = routeItem(forCode: code), !matched.contains(where: { $0.id == route.id }) {
                matched.append(route)
            }
        }

        // 2. Por asociación directa en keyStopIds del catálogo de rutas sincronizado
        for route in dynamicRoutes {
            let resolved = route.resolvedStops(using: dynamicCatalogStops)
            if resolved.contains(where: { $0.id == stop.id }), !matched.contains(where: { $0.id == route.id }) {
                matched.append(route)
            }
        }

        return matched
    }

    /// Rutas Ordinarias (propias de la app con tracking y pago QR) que pasan por este paradero
    func ordinaryRoutes(for stop: TacnaDestinationPlace) -> [TacnaOfficialRouteCatalogItem] {
        catalogRoutes(for: stop).filter { $0.isOrdinary }
    }

    /// Rutas Ordinarias que pasan por este paradero y se encuentran actualmente En Servicio
    func activeOrdinaryRoutes(for stop: TacnaDestinationPlace) -> [TacnaOfficialRouteCatalogItem] {
        ordinaryRoutes(for: stop).filter { $0.isInService }
    }

    /// Rutas Externas (líneas tradicionales de Tacna sin tracking) que pasan por este paradero
    func externalRoutes(for stop: TacnaDestinationPlace) -> [TacnaOfficialRouteCatalogItem] {
        catalogRoutes(for: stop).filter { $0.isExternal }
    }

    /// Evalúa la disponibilidad de la opción "Notificación" para un paradero según la regla de negocio:
    /// - Si no figura ninguna ruta ordinaria -> `.noOrdinaryRoutes` (solo opción "Ir / Punto de encuentro", sin botón de notificación).
    /// - Si tiene ruta(s) ordinaria(s) registrada(s) pero ninguna está en servicio -> `.ordinaryOutOfService` (muestra aviso + "Ir").
    /// - Si tiene al menos una ruta ordinaria en servicio -> `.available` (habilita activar notificación de llegada + "Ir").
    func stopNotificationAvailability(for stop: TacnaDestinationPlace) -> StopNotificationAvailability {
        guard stop.category != .mapCustomPlace else {
            return .noOrdinaryRoutes
        }
        let ordRoutes = ordinaryRoutes(for: stop)
        guard !ordRoutes.isEmpty else {
            return .noOrdinaryRoutes
        }
        let activeOrd = ordRoutes.filter { $0.isInService }
        if !activeOrd.isEmpty {
            return .available(activeRoutes: activeOrd)
        } else {
            return .ordinaryOutOfService(registeredRoutes: ordRoutes)
        }
    }

    // MARK: - Acciones del Buscador Predictivo, Ubicación y Módulo "Ir / Cómo Llegar"
    func selectPlaceFromSearch(_ place: TacnaDestinationPlace, startRouteImmediately: Bool) {
        BCFeedbackManager.shared.impactLight()
        isSearchDropdownVisible = false
        recordRecentSearchedPlace(place)

        if startRouteImmediately {
            // Botón circular azul [Ir]: Abre directamente el escenario Pantalla Completa "Cómo Llegar" con origen GPS y destino fijado
            routePlannerInitialOrigin = TacnaDestinationPlace.currentLocationPlace()
            routePlannerInitialDestination = place
            showRoutePlannerFullScreen = true
        } else {
            // Pulsar en la fila: Centra el mapa en el lugar y suelta un pin rojo de ubicación
            searchQuery = place.shortName
            searchedDestinationPin = place
            focusMap(on: LocationService.sanitizedTacnaCoordinate(place.coordinate), spanDelta: 0.010)
        }
    }

    func recordRecentSearchedPlace(_ place: TacnaDestinationPlace) {
        guard place.id != "current_gps" else { return }
        var updated = recentSearchedPlaces.filter {
            $0.id != place.id && $0.shortName.lowercased() != place.shortName.lowercased()
        }
        updated.insert(place, at: 0)
        if updated.count > 12 {
            updated = Array(updated.prefix(12))
        }
        recentSearchedPlaces = updated
        if let data = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(data, forKey: "bc_recent_places")
        }
    }

    func clearRecentSearchedPlaces() {
        recentSearchedPlaces = []
        UserDefaults.standard.removeObject(forKey: "bc_recent_places")
        BCFeedbackManager.shared.impactLight()
    }

    private func loadRecentSearchedPlaces() {
        if let data = UserDefaults.standard.data(forKey: "bc_recent_places"),
           let decoded = try? JSONDecoder().decode([TacnaDestinationPlace].self, from: data) {
            self.recentSearchedPlaces = decoded
        }
    }

    func clearSearchAndDismiss() {
        BCFeedbackManager.shared.impactLight()
        searchQuery = ""
        isSearchDropdownVisible = false
        searchedDestinationPin = nil
    }

    func centerMapOnUserLocation() {
        BCFeedbackManager.shared.impactMedium()
        focusMap(on: TacnaDestinationPlace.userOriginCoordinate, spanDelta: 0.014)
    }

    func focusMap(on coordinate: CLLocationCoordinate2D, spanDelta: Double = 0.015) {
        mapFocusTargetCoordinate = LocationService.sanitizedTacnaCoordinate(coordinate)
        mapFocusSpanDelta = min(max(spanDelta, 0.005), 0.16)
        mapFocusTrigger = UUID()
    }

    func openRoutePlanner(with destination: TacnaDestinationPlace? = nil, origin: TacnaDestinationPlace? = nil) {
        BCFeedbackManager.shared.impactMedium()
        isSearchDropdownVisible = false
        if let origin = origin {
            routePlannerInitialOrigin = origin
        } else if routePlannerInitialOrigin == nil || routePlannerInitialOrigin?.id == "current_gps" {
            routePlannerInitialOrigin = TacnaDestinationPlace.currentLocationPlace()
        }
        routePlannerInitialDestination = destination ?? searchedDestinationPin
        showRoutePlannerFullScreen = true
    }

    func startGuidedRoute(
        from origin: TacnaDestinationPlace = TacnaDestinationPlace.currentLocationPlace(),
        to destination: TacnaDestinationPlace,
        candidate: EvaluatedRouteCandidate? = nil,
        optionIndex: Int = 0
    ) {
        BCFeedbackManager.shared.notificationSuccess()
        showRoutePlannerFullScreen = false
        searchedDestinationPin = nil

        let resolvedCandidate: EvaluatedRouteCandidate?
        if let candidate = candidate {
            resolvedCandidate = candidate
        } else {
            let eval = evaluateAutomatedRoutes(from: origin, to: destination)
            resolvedCandidate = eval.candidates.indices.contains(optionIndex)
                ? eval.candidates[optionIndex]
                : eval.recommendedCandidate
        }

        let isOrdinaryRoute = resolvedCandidate?.kind == .ordinaryInService
        // Solo las Rutas Ordinarias en servicio cuentan con tracking real, temporizador al paradero y notificador de 5 min.
        // En Rutas Externas o Caminatas directas no se inicia temporizador ni notificador; para externas se habilita un pop-up retirable.
        let initialSeconds: Int
        if isOrdinaryRoute, let cand = resolvedCandidate {
            initialSeconds = max(cand.busWaitMinutes * 60, 298)
        } else {
            initialSeconds = 0
        }

        var guidanceState = ActiveRouteGuidanceState(
            origin: origin,
            destination: destination,
            selectedOptionIndex: optionIndex,
            candidate: resolvedCandidate,
            remainingBusArrivalSeconds: initialSeconds,
            fiveMinuteAlertFired: false
        )

        if isOrdinaryRoute, let cand = resolvedCandidate {
            showExternalGuidancePopup = false
            if initialSeconds <= 300 {
                guidanceState.fiveMinuteAlertFired = true
                showFiveMinuteBoardingBanner = true
                BCNotificationManager.shared.triggerFiveMinuteBusArrivalNotification(
                    routeCode: cand.routeCode,
                    boardingStopName: cand.boardingPointName,
                    destinationName: destination.shortName,
                    walkMinutesToStop: cand.walkInitialMinutes
                )
            } else {
                showFiveMinuteBoardingBanner = false
                BCNotificationManager.shared.requestAuthorizationIfNeeded()
            }
        } else {
            showFiveMinuteBoardingBanner = false
            showExternalGuidancePopup = (resolvedCandidate?.kind == .externalFreeBoarding)
        }

        activeRouteGuidance = guidanceState

        // Encuadrar cámara entre origen y destino dentro de los límites de Tacna
        let safeOrigin = LocationService.sanitizedTacnaCoordinate(origin.coordinate)
        let safeDest = LocationService.sanitizedTacnaCoordinate(destination.coordinate)
        let midLat = (safeOrigin.latitude + safeDest.latitude) / 2.0
        let midLon = (safeOrigin.longitude + safeDest.longitude) / 2.0
        let latDelta = min(max(abs(safeOrigin.latitude - safeDest.latitude) * 1.9, 0.012), 0.16)
        let lonDelta = min(max(abs(safeOrigin.longitude - safeDest.longitude) * 1.9, 0.012), 0.16)
        focusMap(
            on: CLLocationCoordinate2D(latitude: midLat, longitude: midLon),
            spanDelta: max(latDelta, lonDelta)
        )

        routeGuidanceTimer?.cancel()
        routeGuidanceTimer = nil

        guard isOrdinaryRoute else { return }

        routeGuidanceTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, var guidance = self.activeRouteGuidance else { return }
                if guidance.remainingBusArrivalSeconds > 0 {
                    guidance.remainingBusArrivalSeconds -= 1
                    if let cand = guidance.candidate,
                       cand.kind == .ordinaryInService,
                       !guidance.fiveMinuteAlertFired,
                       guidance.remainingBusArrivalSeconds <= 300 {
                        guidance.fiveMinuteAlertFired = true
                        self.showFiveMinuteBoardingBanner = true
                        BCFeedbackManager.shared.notificationSuccess()
                        BCNotificationManager.shared.triggerFiveMinuteBusArrivalNotification(
                            routeCode: cand.routeCode,
                            boardingStopName: cand.boardingPointName,
                            destinationName: guidance.destination.shortName,
                            walkMinutesToStop: cand.walkInitialMinutes
                        )
                    }
                    self.activeRouteGuidance = guidance
                } else {
                    guidance.remainingBusArrivalSeconds = 240
                    self.activeRouteGuidance = guidance
                }
            }
    }

    func promptCancelGuidedRoute() {
        BCFeedbackManager.shared.impactMedium()
        showCancelRouteGuidanceAlert = true
    }

    func confirmCancelGuidedRoute() {
        BCFeedbackManager.shared.impactLight()
        routeGuidanceTimer?.cancel()
        routeGuidanceTimer = nil
        activeRouteGuidance = nil
        showFiveMinuteBoardingBanner = false
        showExternalGuidancePopup = false
        showCancelRouteGuidanceAlert = false
    }

    // MARK: - Selección Rápida de Cuenta de Prueba (1 Toque en Modo Dev)
    func selectTestAccount(_ preset: TestAccountPreset) async {
        BCFeedbackManager.shared.impactMedium()
        self.phoneNumber = preset.rawPhone
        self.otpCode = preset.otpCode
        self.errorMessage = nil
        await sendOtp()
        if currentStep == .otpVerification {
            await verifyOtp()
        }
    }

    func updateBackendHost(_ host: String) {
        let cleaned = host
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.backendHost = cleaned.isEmpty ? "34.44.71.179.sslip.io" : cleaned
        UserDefaults.standard.set(self.backendHost, forKey: "bc_backend_host")
        APIClient.shared.updateBaseURL(self.backendHost)
        Task {
            await refreshStateFromBackendIfAvailable()
        }
    }

    // MARK: - Paso 1 Auth: Enviar OTP (Híbrido Backend + Local)
    func sendOtp() async {
        guard isValidPhone else {
            errorMessage = "Ingresa un número peruano de 9 dígitos que inicie con 9"
            BCFeedbackManager.shared.notificationError()
            return
        }

        isLoading = true
        errorMessage = nil

        struct SendRequest: Encodable { let phone: String }
        struct SendResponse: Decodable {
            let success: Bool
            let expiresInSeconds: Int
        }

        if APIClient.shared.canReachRemoteBackend {
            do {
                let body = try JSONEncoder().encode(SendRequest(phone: phoneNumber))
                let _: SendResponse = try await APIClient.shared.request(
                    endpoint: "auth/otp/send",
                    method: "POST",
                    body: body,
                    requiresAuth: false
                )
                isConnectedToBackend = true
                isLoading = false
                currentStep = .otpVerification
                startCountdown()
                return
            } catch let APIError.serverError(_, message) {
                isLoading = false
                errorMessage = message
                BCFeedbackManager.shared.notificationError()
                return
            } catch {
                // Fallback transparente al repositorio local en el iPhone si el servidor Mac está apagado
                isConnectedToBackend = false
            }
        }

        // Modo Local Inteligente en iPhone
        isLoading = false
        currentStep = .otpVerification
        startCountdown()
    }

    // MARK: - Paso 2 Auth: Verificar OTP y Cargar/Crear Cuenta (0 pts, 0 viajes, 0 paraderos)
    func verifyOtp() async {
        guard otpCode.count == 6 else {
            errorMessage = "El código debe tener 6 dígitos"
            return
        }

        isLoading = true
        errorMessage = nil

        struct VerifyRequest: Encodable {
            let phone: String
            let code: String
            let deviceId: String
            let deviceName: String
        }

        struct TokenResponse: Decodable {
            let accessToken: String
            let refreshToken: String
            let user: UserAuth
        }

        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "IPHONE-BC-001"
        let deviceName = UIDevice.current.name

        if APIClient.shared.canReachRemoteBackend {
            do {
                let req = VerifyRequest(phone: phoneNumber, code: otpCode, deviceId: deviceId, deviceName: deviceName)
                let encoder = JSONEncoder()
                encoder.keyEncodingStrategy = .convertToSnakeCase
                let body = try encoder.encode(req)
                let res: TokenResponse = try await APIClient.shared.request(
                    endpoint: "auth/otp/verify",
                    method: "POST",
                    body: body,
                    requiresAuth: false
                )

                KeychainService.shared.save(key: "access_token", value: res.accessToken)
                KeychainService.shared.save(key: "refresh_token", value: res.refreshToken)

                self.currentUser = res.user
                self.saveActiveUserLocally(res.user)
                self.loadLocalTransactions(for: res.user.phone)
                self.loadCarnetReviewRequest(for: res.user.phone)
                self.isConnectedToBackend = true
                self.isLoading = false
                BCFeedbackManager.shared.notificationSuccess()
                self.currentStep = .success
                await refreshStateFromBackendIfAvailable()
                return
            } catch let APIError.serverError(_, message) {
                isLoading = false
                errorMessage = message
                BCFeedbackManager.shared.notificationError()
                return
            } catch {
                isConnectedToBackend = false
            }
        }

        // Validación en Repositorio Local del iPhone (Código de desarrollo: 123456)
        guard otpCode == "123456" else {
            isLoading = false
            errorMessage = "Código incorrecto. En modo de prueba utiliza 123456."
            BCFeedbackManager.shared.notificationError()
            return
        }

        let phoneKey = normalizedPhone
        let user = loadOrCreateLocalAccount(phone: phoneKey)
        KeychainService.shared.save(key: "access_token", value: "local_jwt_\(user.id)")
        KeychainService.shared.save(key: "refresh_token", value: "local_refresh_\(user.id)")

        self.currentUser = user
        self.saveActiveUserLocally(user)
        self.loadLocalTransactions(for: phoneKey)
        self.loadCarnetReviewRequest(for: phoneKey)

        // Al ser cuenta de prueba o cuenta nueva, no existen paraderos ni buses falsos precargados
        self.routes = []
        self.stops = []
        self.activeBuses = []

        self.isLoading = false
        BCFeedbackManager.shared.notificationSuccess()
        self.currentStep = .success
    }

    func completeOnboarding() {
        BCFeedbackManager.shared.impactLight()
        self.isLoggedIn = true
        self.isGuestMode = false
        self.selectedTab = 0
    }

    func continueAsGuest() {
        BCFeedbackManager.shared.impactLight()
        self.isGuestMode = true
        self.isLoggedIn = false
        self.currentUser = nil
        self.transactions = []
        self.carnetReviewRequest = nil
        self.routes = []
        self.stops = []
        self.activeBuses = []
        self.selectedTab = 0
    }

    private func setupSmartSync() {
        appForegroundCancellable?.cancel()
        appForegroundCancellable = NotificationCenter.default
            .publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    // Sincroniza al volver de segundo plano solo si pasaron al menos 3 minutos (ahorro de batería)
                    await self.refreshStateFromBackendIfAvailable(isManual: false)
                }
            }
    }

    // MARK: - Sincronización Inteligente de Red y Paraderos (Smart Sync & Battery Saver)
    func refreshStateFromBackendIfAvailable(isManual: Bool = false) async {
        guard APIClient.shared.canReachRemoteBackend else { return }

        // Protección de batería y datos móviles: throttle de 3 minutos para sincronizaciones automáticas
        if !isManual, let last = lastSyncDate, Date().timeIntervalSince(last) < 180 {
            return
        }
        self.lastSyncDate = Date()

        // 1. Sincronizar paraderos calibrados en tiempo real desde el Administrador Web y Servidor Cloud
        do {
            let adminStops: [AdminStopDTO] = try await APIClient.shared.request(
                endpoint: "transit/stops",
                method: "GET",
                requiresAuth: false
            )
            if !adminStops.isEmpty {
                let converted = adminStops.map { $0.toDestinationPlace() }
                await MainActor.run {
                    if self.dynamicCatalogStops != converted {
                        self.dynamicCatalogStops = converted
                        if let rawData = try? JSONEncoder().encode(adminStops) {
                            UserDefaults.standard.set(rawData, forKey: "bc_cached_stops")
                        }
                    }
                    self.isConnectedToBackend = true
                    if isManual {
                        BCFeedbackManager.shared.notificationSuccess()
                    }
                }
            }
        } catch {
            print("[SYNC] Error sincronizando paraderos desde backend: \(error)")
        }

        // 2. Sincronizar catálogo de rutas (Ordinarias en Servicio/Fuera de Servicio y Externas)
        do {
            let adminRoutes: [AdminRouteDTO] = try await APIClient.shared.request(
                endpoint: "transit/routes",
                method: "GET",
                requiresAuth: false
            )
            if !adminRoutes.isEmpty {
                let convertedRoutes = adminRoutes.map { $0.toRouteCatalogItem() }
                await MainActor.run {
                    if self.dynamicRoutes != convertedRoutes {
                        self.dynamicRoutes = convertedRoutes
                        if let rawRoutes = try? JSONEncoder().encode(adminRoutes) {
                            UserDefaults.standard.set(rawRoutes, forKey: "bc_cached_routes")
                        }
                        if let currentOverlay = self.activeRouteOverlayOnMap,
                           let updatedOverlay = convertedRoutes.first(where: { $0.id == currentOverlay.id }) {
                            self.activeRouteOverlayOnMap = updatedOverlay
                        }
                    }
                    self.isConnectedToBackend = true
                }
            }
        } catch {
            print("[SYNC] Error sincronizando rutas desde backend: \(error)")
        }

        // 3. Sincronizar red de transporte activa (unidades en vivo)
        struct NetworkDTO: Decodable {
            let routes: [BusRouteModel]
            let stops: [BusStopModel]
            let activeBuses: [ActiveBusModel]
        }

        do {
            let net: NetworkDTO = try await APIClient.shared.request(
                endpoint: "transit/network",
                method: "GET",
                requiresAuth: false
            )
            await MainActor.run {
                self.routes = net.routes
                self.stops = net.stops
                self.activeBuses = net.activeBuses
                self.isConnectedToBackend = true
            }
        } catch {
            // Se mantiene el estado local si el endpoint no tiene buses asignados
        }
    }

    // MARK: - Operaciones del Monedero (CU-05 Recarga / CU-03 SUNEDU / CU-01 Pago QR)
    @discardableResult
    func rechargePoints(points: Int, gateway: String, reference: String? = nil) async -> LedgerTransactionItem? {
        guard var user = currentUser else { return nil }

        struct RechargeReq: Encodable {
            let amountPoints: Int
            let gateway: String
        }

        if APIClient.shared.canReachRemoteBackend {
            do {
                let encoder = JSONEncoder()
                encoder.keyEncodingStrategy = .convertToSnakeCase
                let body = try encoder.encode(RechargeReq(amountPoints: points, gateway: gateway))
                struct EmptyDecodable: Decodable {}
                let _: EmptyDecodable = try await APIClient.shared.request(
                    endpoint: "wallet/recharge",
                    method: "POST",
                    body: body,
                    requiresAuth: true
                )
            } catch {
                // Fallback a persistencia local
            }
        }

        let before = user.pointsBalance
        let after = before + points
        let pen = Double(points) / 10.0

        user.pointsBalance = after
        self.currentUser = user
        self.saveActiveUserLocally(user)
        self.persistAccountState(user)

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let timeStr = "Hoy, \(formatter.string(from: Date()))"
        let opCode = reference ?? "BC-\(Int.random(in: 100000...999999))"

        let newTx = LedgerTransactionItem(
            id: UUID().uuidString,
            type: "RECHARGE_CREDIT",
            title: "Recarga \(gateway)",
            subtitle: "Op. \(opCode) · Abono instantáneo",
            plateBadge: nil,
            timestampLabel: timeStr,
            amountPoints: points,
            amountPen: pen,
            balanceBefore: before,
            balanceAfter: after
        )

        self.transactions.insert(newTx, at: 0)
        self.saveLocalTransactions(for: user.phone)
        BCFeedbackManager.shared.playRechargeChime()
        return newTx
    }

    func accreditSuneduCard(dni: String, university: String, career: String) async {
        guard var user = currentUser else { return }

        let sv = StudentVerificationInfo(
            dni: dni,
            university: university,
            career: career,
            academicCycle: "2026-II",
            status: "ACTIVE",
            expiresAt: "31/12/2026"
        )

        user.role = UserRoleType.student.rawValue
        user.studentVerification = sv
        self.currentUser = user
        self.saveActiveUserLocally(user)
        self.persistAccountState(user)
        BCFeedbackManager.shared.notificationSuccess()
    }

    func submitCarnetReviewRequest(
        type: String,
        dni: String,
        institution: String,
        documentCode: String,
        expiresAt: String
    ) {
        guard let user = currentUser else { return }
        let req = CarnetReviewRequest(
            id: "CAR-\(Int.random(in: 10000...99999))",
            carnetType: type,
            dni: dni,
            institution: institution,
            documentCode: documentCode,
            submittedAt: Date(),
            status: "PENDING_REVIEW",
            expiresAt: expiresAt
        )
        self.carnetReviewRequest = req
        if let data = try? JSONEncoder().encode(req) {
            UserDefaults.standard.set(data, forKey: "bc_carnet_req_\(user.phone)")
        }
        BCFeedbackManager.shared.notificationSuccess()
    }

    private func loadCarnetReviewRequest(for phone: String) {
        if let data = UserDefaults.standard.data(forKey: "bc_carnet_req_\(phone)"),
           let decoded = try? JSONDecoder().decode(CarnetReviewRequest.self, from: data) {
            self.carnetReviewRequest = decoded
        } else {
            self.carnetReviewRequest = nil
        }
    }

    /// Ejecuta el pago de pasaje con QR en puerta + acompañantes (CU-01 / RN-07)
    func payPassageWithQr(companionsCount: Int, busUnit: String = "BUS 01", busPlate: String = "Z1A-780", lineNumber: String = "14") -> Bool {
        guard var user = currentUser else { return false }

        let holderFare = user.roleType.farePoints
        let companionsFare = companionsCount * 15 // RN-07: cada acompañante abona tarifa Adulto (15 pts)
        let totalPoints = holderFare + companionsFare
        let totalPen = Double(totalPoints) / 10.0

        if user.pointsBalance < totalPoints {
            self.requiredPointsForAttempt = totalPoints
            self.showInsufficientBalanceModal = true
            BCFeedbackManager.shared.notificationError()
            return false
        }

        let before = user.pointsBalance
        let after = before - totalPoints
        user.pointsBalance = after
        self.currentUser = user
        self.saveActiveUserLocally(user)
        self.persistAccountState(user)

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let timeStr = "Hoy, \(formatter.string(from: Date())) · Validado QR"

        let companionSuffix = companionsCount > 0 ? " (+\(companionsCount) acomp.)" : ""
        let newTx = LedgerTransactionItem(
            id: UUID().uuidString,
            type: "TRIP_DEBIT",
            title: "Ruta \(lineNumber) • \(busUnit)\(companionSuffix)",
            subtitle: "Abordaje validado en puerta",
            plateBadge: busPlate,
            timestampLabel: timeStr,
            amountPoints: -totalPoints,
            amountPen: -totalPen,
            balanceBefore: before,
            balanceAfter: after
        )

        self.transactions.insert(newTx, at: 0)
        self.saveLocalTransactions(for: user.phone)

        // Iniciar Seguimiento de Viaje en Curso (CU-06)
        self.activeTrip = ActiveTripState(
            id: UUID().uuidString,
            busUnit: busUnit,
            busPlate: busPlate,
            lineNumber: lineNumber,
            boardingStopName: "Paradero de Abordaje",
            destinationStopName: "Paradero de Destino",
            companionsCount: companionsCount,
            totalPointsDebited: totalPoints,
            isMinimized: false,
            nextStopEtaMinutes: 4
        )

        BCFeedbackManager.shared.playValidationTone()
        return true
    }

    func finishActiveTrip() {
        BCFeedbackManager.shared.impactLight()
        self.activeTrip = nil
    }

    // MARK: - Alerta de Paradero (2 Timers)
    func activateStopArrivalAlert(stop: BusStopModel, advanceMinutes: Int, imminentEnabled: Bool) {
        BCFeedbackManager.shared.notificationSuccess()
        self.activeArrivalAlert = ArrivalAlertState(
            stopId: stop.id,
            stopName: stop.name,
            advanceMinutes: advanceMinutes,
            imminentEnabled: imminentEnabled,
            remainingSeconds: advanceMinutes * 60
        )

        arrivalAlertTimer?.cancel()
        arrivalAlertTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, var alert = self.activeArrivalAlert else { return }
                if alert.remainingSeconds > 0 {
                    alert.remainingSeconds -= 1
                    self.activeArrivalAlert = alert
                } else {
                    self.arrivalAlertTimer?.cancel()
                }
            }
    }

    func cancelArrivalAlert() {
        arrivalAlertTimer?.cancel()
        activeArrivalAlert = nil
    }

    // MARK: - Cierre de Sesión y Reinicio de Cuenta de Prueba
    func resetCurrentAccountState() {
        guard var user = currentUser else { return }
        user.pointsBalance = 0
        if let preset = TestAccountPreset.officialPresets.first(where: { $0.formattedPhone == user.phone }) {
            user.role = preset.role.rawValue
            user.studentVerification = preset.studentVerification
        }
        self.currentUser = user
        self.transactions = []
        self.activeTrip = nil
        self.activeArrivalAlert = nil
        self.activeRouteGuidance = nil
        self.showFiveMinuteBoardingBanner = false
        self.showExternalGuidancePopup = false
        self.routeGuidanceTimer?.cancel()
        self.carnetReviewRequest = nil
        UserDefaults.standard.removeObject(forKey: "bc_carnet_req_\(user.phone)")
        self.saveActiveUserLocally(user)
        self.persistAccountState(user)
        self.saveLocalTransactions(for: user.phone)
        BCFeedbackManager.shared.impactMedium()
    }

    func logout() async {
        isLoading = true
        if APIClient.shared.canReachRemoteBackend {
            struct LogoutResponse: Decodable { let success: Bool }
            _ = try? await APIClient.shared.request(
                endpoint: "auth/logout",
                method: "DELETE",
                requiresAuth: true
            ) as LogoutResponse
        }

        KeychainService.shared.delete(key: "access_token")
        KeychainService.shared.delete(key: "refresh_token")
        UserDefaults.standard.removeObject(forKey: "bc_active_user")

        self.currentUser = nil
        self.transactions = []
        self.carnetReviewRequest = nil
        self.routes = []
        self.stops = []
        self.activeBuses = []
        self.activeTrip = nil
        self.activeArrivalAlert = nil
        self.activeRouteGuidance = nil
        self.showFiveMinuteBoardingBanner = false
        self.showExternalGuidancePopup = false
        self.routeGuidanceTimer?.cancel()
        self.searchedDestinationPin = nil
        self.isEmptyTransitBannerDismissed = false
        self.isLoggedIn = false
        self.isGuestMode = false
        self.phoneNumber = ""
        self.otpCode = ""
        self.currentStep = .splash
        self.isLoading = false
    }

    // MARK: - Persistencia Local por Número de Cuenta en el iPhone
    private func loadOrCreateLocalAccount(phone: String) -> UserAuth {
        let storageKey = "bc_account_\(phone)"
        if let savedData = UserDefaults.standard.data(forKey: storageKey),
           let savedUser = try? JSONDecoder().decode(UserAuth.self, from: savedData) {
            return savedUser
        }

        // Verificar si coincide con una de las 3 Cuentas de Prueba Oficiales
        if let preset = TestAccountPreset.officialPresets.first(where: { $0.formattedPhone == phone }) {
            let testUser = UserAuth(
                id: preset.id,
                phone: preset.formattedPhone,
                name: preset.name,
                role: preset.role.rawValue,
                pointsBalance: 0, // Inicia estrictamente en 0 puntos
                isNewUser: true,
                studentVerification: preset.studentVerification
            )
            persistAccountState(testUser)
            return testUser
        }

        // Usuario nuevo registrado manualmente
        let newUser = UserAuth(
            id: UUID().uuidString,
            phone: phone,
            name: "Pasajero BC",
            role: UserRoleType.adult.rawValue,
            pointsBalance: 0,
            isNewUser: true,
            studentVerification: nil
        )
        persistAccountState(newUser)
        return newUser
    }

    private func persistAccountState(_ user: UserAuth) {
        let storageKey = "bc_account_\(user.phone)"
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func saveActiveUserLocally(_ user: UserAuth) {
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: "bc_active_user")
        }
    }

    private func loadLocalTransactions(for phone: String) {
        let txKey = "bc_tx_\(phone)"
        if let data = UserDefaults.standard.data(forKey: txKey),
           let decoded = try? JSONDecoder().decode([LedgerTransactionItem].self, from: data) {
            self.transactions = decoded
        } else {
            self.transactions = []
        }
    }

    private func saveLocalTransactions(for phone: String) {
        let txKey = "bc_tx_\(phone)"
        if let data = try? JSONEncoder().encode(transactions) {
            UserDefaults.standard.set(data, forKey: txKey)
        }
    }

    private func startCountdown() {
        countdownSeconds = 59
        countdownTimer?.cancel()
        countdownTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.countdownSeconds > 0 {
                    self.countdownSeconds -= 1
                } else {
                    self.countdownTimer?.cancel()
                }
            }
    }
}

/// Envoltorio seguro para consultar autocompletado nativo de MapKit (`MKLocalSearchCompleter`) en Tacna.
@MainActor
private final class TacnaMapCompleterHelper: NSObject, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    private var continuation: CheckedContinuation<[MKLocalSearchCompletion], Never>?
    private var timeoutWorkItem: DispatchWorkItem?
    private var retainedSelf: TacnaMapCompleterHelper?

    static func fetchCompletions(query: String, region: MKCoordinateRegion) async -> [MKLocalSearchCompletion] {
        await withCheckedContinuation { continuation in
            let helper = TacnaMapCompleterHelper()
            helper.start(query: query, region: region, continuation: continuation)
        }
    }

    private func start(
        query: String,
        region: MKCoordinateRegion,
        continuation: CheckedContinuation<[MKLocalSearchCompletion], Never>
    ) {
        self.continuation = continuation
        self.retainedSelf = self
        completer.delegate = self
        completer.region = region
        completer.resultTypes = [.pointOfInterest, .address, .query]

        let timeout = DispatchWorkItem { [weak self] in
            self?.finish(with: self?.completer.results ?? [])
        }
        self.timeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25, execute: timeout)
        completer.queryFragment = query
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let items = completer.results
        Task { @MainActor in
            self.finish(with: items)
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.finish(with: [])
        }
    }

    private func finish(with results: [MKLocalSearchCompletion]) {
        guard let cont = continuation else { return }
        continuation = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        completer.delegate = nil
        cont.resume(returning: results)
        retainedSelf = nil
    }
}

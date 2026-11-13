import Foundation
import CoreLocation
import MapKit
import UserNotifications

// MARK: - Roles y Tarifas (1 PEN = 10 Puntos BC)
enum UserRoleType: String, Codable, CaseIterable {
    case adult = "ADULT"
    case student = "STUDENT"
    case conadis = "CONADIS"
    case driver = "DRIVER"
    case admin = "ADMIN"

    var farePoints: Int {
        switch self {
        case .student: return 7
        case .conadis: return 0
        default: return 15
        }
    }

    var farePen: Double {
        Double(farePoints) / 10.0
    }

    var displayName: String {
        switch self {
        case .student: return "Universitario SUNEDU"
        case .conadis: return "Pase Libre CONADIS"
        case .driver: return "Conductor BC"
        case .admin: return "Administrador"
        case .adult: return "Pasajero Adulto"
        }
    }

    var badgeLabel: String {
        switch self {
        case .student: return "Tarifa Universitaria · 7 pts (S/. 0.70)"
        case .conadis: return "Exonerado Ley 30412 · 0 pts (S/. 0.00)"
        default: return "Tarifa General · 15 pts (S/. 1.50)"
        }
    }

    var iconName: String {
        switch self {
        case .student: return "graduationcap.fill"
        case .conadis: return "figure.roll"
        default: return "person.crop.circle.fill"
        }
    }
}

// MARK: - Verificación Estudiantil SUNEDU (CU-03)
struct StudentVerificationInfo: Codable, Equatable {
    let dni: String
    let university: String
    let career: String?
    let academicCycle: String?
    let status: String
    let expiresAt: String

    static func daysRemaining(until dateStr: String) -> Int? {
        let trimmed = dateStr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formats = ["yyyy-MM-dd", "dd/MM/yyyy", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ"]
        var parsedDate: Date?
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                parsedDate = date
                break
            }
        }
        guard let target = parsedDate else { return nil }
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: Date())
        let startTarget = cal.startOfDay(for: target)
        return cal.dateComponents([.day], from: startToday, to: startTarget).day
    }

    static func formattedExpirationDate(_ dateStr: String) -> String {
        let trimmed = dateStr.trimmingCharacters(in: .whitespacesAndNewlines)
        let formats = ["yyyy-MM-dd", "dd/MM/yyyy", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ"]
        for format in formats {
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.dateFormat = format
            if let date = parser.date(from: trimmed) {
                let out = DateFormatter()
                out.locale = Locale(identifier: "es_PE")
                out.dateFormat = "dd/MM/yyyy"
                return out.string(from: date)
            }
        }
        return trimmed
    }

    var daysRemaining: Int? {
        Self.daysRemaining(until: expiresAt)
    }

    var expirationSummaryText: String {
        let dateText = Self.formattedExpirationDate(expiresAt)
        if let days = daysRemaining {
            if days < 0 {
                return "Venció el \(dateText) (hace \(abs(days)) días)"
            } else if days == 0 {
                return "Vence hoy (\(dateText))"
            } else {
                return "Vence el \(dateText) · \(days) días restantes"
            }
        }
        return "Válido hasta el \(dateText)"
    }
}

struct CarnetReviewRequest: Codable, Identifiable, Equatable {
    let id: String
    let carnetType: String // "STUDENT" o "CONADIS"
    let dni: String
    let institution: String
    let documentCode: String
    let submittedAt: Date
    let status: String // "PENDING_REVIEW", "APPROVED", "REJECTED"
    let expiresAt: String

    var carnetTypeDisplay: String {
        carnetType == "CONADIS" ? "Pase Libre CONADIS" : "Carné Universitario SUNEDU"
    }

    var statusDisplay: String {
        switch status {
        case "APPROVED": return "Aprobado"
        case "REJECTED": return "Observado"
        default: return "En revisión"
        }
    }
}

// MARK: - Perfil de Usuario Autenticado
struct UserAuth: Codable, Identifiable, Equatable {
    let id: String
    var phone: String
    var name: String?
    var firstName: String?
    var lastName: String?
    var email: String?
    var authProvider: String?
    var phoneVerified: Bool?
    var role: String
    var pointsBalance: Int
    var isNewUser: Bool
    var studentVerification: StudentVerificationInfo?

    var hasVerifiedPhone: Bool {
        let cleaned = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }
        return phoneVerified ?? true
    }

    var displayFullName: String {
        let combined = [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !combined.isEmpty { return combined }
        if let n = name?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { return n }
        return "Pasajero BC"
    }

    var roleType: UserRoleType {
        UserRoleType(rawValue: role) ?? .adult
    }

    var balancePen: Double {
        Double(pointsBalance) / 10.0
    }
}

// MARK: - Catálogo de Cuentas de Prueba (Inician en 0 pts, 0 viajes y 0 unidades falsas)
struct TestAccountPreset: Identifiable, Equatable {
    let id: String
    let rawPhone: String
    let formattedPhone: String
    let name: String
    let email: String
    let role: UserRoleType
    let subtitle: String
    let otpCode: String
    let studentVerification: StudentVerificationInfo?

    static let officialPresets: [TestAccountPreset] = [
        TestAccountPreset(
            id: "test-student-002",
            rawPhone: "952000002",
            formattedPhone: "+51952000002",
            name: "Aron Mamani Quispe",
            email: "aron.mamani@unjbg.edu.pe",
            role: .student,
            subtitle: "Universitario UNJBG (SUNEDU Vigente · 7 pts) · Inicia en 0 pts",
            otpCode: "123456",
            studentVerification: StudentVerificationInfo(
                dni: "74829103",
                university: "Universidad Nacional Jorge Basadre Grohmann (UNJBG)",
                career: "Ingeniería en Informática y Sistemas",
                academicCycle: "2026-II",
                status: "ACTIVE",
                expiresAt: "31/12/2026"
            )
        ),
        TestAccountPreset(
            id: "test-adult-001",
            rawPhone: "952000001",
            formattedPhone: "+51952000001",
            name: "Carlos Mendoza",
            email: "carlos.mendoza@tacna.pe",
            role: .adult,
            subtitle: "Pasajero Adulto (Tarifa General · 15 pts) · Inicia en 0 pts",
            otpCode: "123456",
            studentVerification: nil
        ),
        TestAccountPreset(
            id: "test-conadis-003",
            rawPhone: "952000003",
            formattedPhone: "+51952000003",
            name: "Elena Quispe",
            email: "elena.quispe@tacna.pe",
            role: .conadis,
            subtitle: "Pase Libre CONADIS (Ley 30412 · 0 pts) · Inicia en 0 pts",
            otpCode: "123456",
            studentVerification: nil
        ),
    ]
}

// MARK: - Transacción del Libro Mayor (Ledger - CU-08)
struct LedgerTransactionItem: Codable, Identifiable, Equatable {
    let id: String
    let type: String // "RECHARGE_CREDIT" o "TRIP_DEBIT"
    let title: String
    let subtitle: String
    let plateBadge: String?
    let timestampLabel: String
    let amountPoints: Int
    let amountPen: Double
    let balanceBefore: Int
    let balanceAfter: Int

    var isPositive: Bool {
        amountPoints >= 0 && type == "RECHARGE_CREDIT"
    }

    var formattedPoints: String {
        amountPoints > 0 ? "+\(amountPoints) pts" : "\(amountPoints) pts"
    }

    var formattedPen: String {
        let absPen = abs(amountPen)
        let prefix = amountPoints > 0 ? "+S/." : (amountPoints < 0 ? "-S/." : "S/.")
        return String(format: "%@ %.2f", prefix, absPen)
    }
}

// MARK: - Modelos de Red de Transporte y Telemetría (CU-07)
struct ApproachingBusETA: Codable, Identifiable, Equatable {
    let id: String
    let unitNumber: String
    let plate: String
    let etaMinutes: Int
    let occupancyPercentage: Int
}

struct BusStopModel: Codable, Identifiable, Equatable {
    let id: String
    let routeId: String
    let name: String
    let subtitle: String
    let latitude: Double
    let longitude: Double
    let sequenceOrder: Int
    let direction: String
    let isKeyStop: Bool
    var approachingBuses: [ApproachingBusETA] = []

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct ActiveBusModel: Codable, Identifiable, Equatable {
    let id: String
    let unitNumber: String
    let plate: String
    let lineNumber: String
    let driverName: String
    let driverRating: Double
    let driverLicense: String
    let occupancyCurrent: Int
    let occupancyMax: Int
    let latitude: Double
    let longitude: Double
    let nextStopName: String
    let nextStopEtaMinutes: Int

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var occupancyPercentage: Int {
        guard occupancyMax > 0 else { return 0 }
        return Int((Double(occupancyCurrent) / Double(occupancyMax)) * 100.0)
    }
}

struct BusRouteModel: Codable, Identifiable, Equatable {
    let id: String
    let lineNumber: String
    let name: String
    let originName: String
    let destinationName: String
    let frequencyMinutes: Int
    let operatingHours: String
    let colorHex: String
    var stops: [BusStopModel]
}

// MARK: - Estado de Alerta de Paradero (2 Timers) y Viaje en Curso (CU-06)
struct ArrivalAlertState: Equatable {
    let stopId: String
    let stopName: String
    let advanceMinutes: Int
    let imminentEnabled: Bool
    var remainingSeconds: Int
}

struct ActiveTripState: Identifiable, Equatable {
    let id: String
    let busUnit: String
    let busPlate: String
    let lineNumber: String
    let boardingStopName: String
    var destinationStopName: String
    let companionsCount: Int
    let totalPointsDebited: Int
    var isMinimized: Bool
    var nextStopEtaMinutes: Int
    var isConfirmedOnBoard: Bool? = nil
    var destinationLatitude: Double? = nil
    var destinationLongitude: Double? = nil
    var proximityAlertTriggered: Bool = false
}

// MARK: - Clasificación Oficial y Propuestas de Paraderos de Tacna (33 Rutas Urbanas)
enum TacnaStopCategory: String, Codable, CaseIterable {
    case marketsCommercial = "Mercados y Zonas Comerciales"
    case plazasCentral = "Plazas y Zonas Céntricas"
    case institutionsTerminals = "Instituciones y Terminales"
    case proposedHospitals = "Propuesta: Hospitales y Salud"
    case proposedUrbanGrowth = "Propuesta: Cono Sur y Cono Norte"
    case proposedEducation = "Propuesta: Zonas Educativas (Geofencing)"
    case proposedTouristBorder = "Propuesta: Zonas Turísticas y Frontera"
    case mapCustomPlace = "Ubicación en el Mapa de Tacna"

    var isProposedModernization: Bool {
        switch self {
        case .proposedHospitals, .proposedUrbanGrowth, .proposedEducation, .proposedTouristBorder:
            return true
        default:
            return false
        }
    }

    var badgeTitle: String {
        isProposedModernization ? "PROPUESTA A OFICIALIZAR" : "PARADERO OFICIAL CLAVE"
    }
}

enum DestinationRouteCase: String, Codable, Equatable {
    case walkOnlyNearby
    case busRoute14
    case busRoute10B
    case busRoute101
    case busRoute203
}

// MARK: - DTO para Sincronización en Tiempo Real con Backend Local y Web Admin
struct AdminStopDTO: Codable, Identifiable {
    let id: String
    let name: String
    let shortName: String
    let subtitle: String?
    let category: String
    let categoryLabel: String?
    let isOfficial: Bool?
    let latitude: Double
    let longitude: Double
    let routesPassing: [String]?
    let colorHex: String?
    let iconName: String?
    let statusNote: String?

    func toDestinationPlace() -> TacnaDestinationPlace {
        let cat: TacnaStopCategory
        switch category {
        case "marketsCommercial": cat = .marketsCommercial
        case "plazasCentral": cat = .plazasCentral
        case "institutionsTerminals": cat = .institutionsTerminals
        case "proposedHospitals": cat = .proposedHospitals
        case "proposedUrbanGrowth": cat = .proposedUrbanGrowth
        case "proposedEducation": cat = .proposedEducation
        case "proposedTouristBorder": cat = .proposedTouristBorder
        default: cat = (isOfficial == false) ? .proposedUrbanGrowth : .institutionsTerminals
        }

        let routes = routesPassing ?? []
        let defaultIcon = "bus.fill"
        let defaultColor = cat.isProposedModernization ? "#F59E0B" : "#2563EB"

        return TacnaDestinationPlace(
            id: id,
            name: name,
            shortName: shortName,
            subtitle: subtitle ?? "Tacna, Perú",
            category: cat,
            routesPassing: routes,
            iconName: iconName ?? defaultIcon,
            iconColorHex: colorHex ?? defaultColor,
            latitude: latitude,
            longitude: longitude,
            routeCase: .busRoute14,
            totalDurationMinutes: 8,
            secondaryDurationMinutes: 12,
            walkingDirectMinutes: 5,
            distanceLabel: "600 m",
            walkInitialMinutes: 2,
            busRideMinutes: 5,
            walkFinalMinutes: 1,
            boardingStopName: "Tacna Centro",
            alightingStopName: shortName,
            intermediateStopName: nil,
            statusNote: statusNote
        )
    }
}

// MARK: - Modelo de Paradero / Lugar Real de Tacna
struct TacnaDestinationPlace: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let shortName: String
    let subtitle: String
    let category: TacnaStopCategory
    let routesPassing: [String] // Ej: ["Ruta 14", "Ruta 10B"]
    let iconName: String
    let iconColorHex: String
    let latitude: Double
    let longitude: Double
    let routeCase: DestinationRouteCase
    let totalDurationMinutes: Int
    let secondaryDurationMinutes: Int
    let walkingDirectMinutes: Int
    let distanceLabel: String
    let walkInitialMinutes: Int
    let busRideMinutes: Int
    let walkFinalMinutes: Int
    let boardingStopName: String
    let alightingStopName: String
    let intermediateStopName: String?
    let statusNote: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var primaryRouteName: String {
        routesPassing.first ?? "Ruta 14"
    }

    /// Indica si es uno de los paraderos oficiales actuales de Tacna
    var isOfficialParadero: Bool {
        return !category.isProposedModernization && category != .mapCustomPlace
    }

    /// Icono visual: por defecto es el símbolo unificado oficial de bus ('bus.fill'); se puede personalizar individualmente desde el Panel Administrador Web
    var resolvedIconName: String {
        return Self.mapToSFSymbol(raw: iconName)
    }

    static func mapToSFSymbol(raw: String) -> String {
        switch raw {
        case "bus", "bus.fill": return "bus.fill"
        case "stop", "sign", "parkingsign", "parkingsign.circle.fill": return "parkingsign.circle.fill"
        case "store", "storefront", "storefront.fill", "cart", "cart.fill", "bag.fill": return "storefront.fill"
        case "hospital", "cross", "cross.case.fill": return "cross.case.fill"
        case "school", "education", "graduationcap", "graduationcap.fill", "academiccap": return "graduationcap.fill"
        case "terminal", "building", "building.columns.fill", "building.2.fill": return "building.columns.fill"
        case "tree", "park", "tree.fill": return "tree.fill"
        case "pin", "mappin", "mappin.and.ellipse": return "mappin.and.ellipse"
        default: return raw.contains(".") ? raw : "bus.fill"
        }
    }

    var displayIconName: String {
        resolvedIconName
    }

    /// Color común y unificado para que el usuario identifique inmediatamente un paradero
    var displayColorHex: String {
        if isOfficialParadero {
            return "#2563EB" // Color común oficial (Azul Transporte) para TODOS los paraderos
        } else if category.isProposedModernization {
            return "#F59E0B" // Ámbar distintivo para paraderos propuestos
        } else {
            return "#38BDF8" // Cian para puntos de interés del mapa de Apple
        }
    }

    /// Badge de categoría en el buscador y fichas
    var displayBadgeText: String {
        if isOfficialParadero {
            return "PARADERO"
        } else if category.isProposedModernization {
            return "PROPUESTA"
        } else {
            return "MAPA"
        }
    }

    /// Coordenada de referencia del usuario en Tacna ("Tu ubicación", Paseo Cívico / Centro o GPS real)
    static var userOriginCoordinate: CLLocationCoordinate2D {
        LocationService.shared.effectiveCoordinate
    }

    /// Punto de abordaje más cercano al origen del usuario (Tacna Centro / Mercado 2 de Mayo)
    var boardingCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: -18.0118, longitude: -70.2508)
    }

    var walkingToBoardCoordinates: [CLLocationCoordinate2D] {
        let origin = Self.userOriginCoordinate
        if routeCase == .walkOnlyNearby {
            return [origin, coordinate]
        }
        return [
            origin,
            CLLocationCoordinate2D(latitude: (origin.latitude + boardingCoordinate.latitude) / 2.0, longitude: (origin.longitude + boardingCoordinate.longitude) / 2.0),
            boardingCoordinate
        ]
    }

    var busTransitCoordinates: [CLLocationCoordinate2D] {
        if routeCase == .walkOnlyNearby {
            return []
        }
        let midLat = (boardingCoordinate.latitude + latitude) / 2.0
        let midLon = (boardingCoordinate.longitude + longitude) / 2.0 + 0.0008
        return [
            boardingCoordinate,
            CLLocationCoordinate2D(latitude: midLat, longitude: midLon),
            coordinate
        ]
    }

    var walkingFinalCoordinates: [CLLocationCoordinate2D] {
        return []
    }

    /// Crea un destino dinámico a partir de cualquier búsqueda o selección en el mapa de Tacna
    static func fromMapItem(name: String, subtitle: String, coordinate: CLLocationCoordinate2D) -> TacnaDestinationPlace {
        let origin = userOriginCoordinate
        let userLoc = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let destLoc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let meters = max(Int(userLoc.distance(from: destLoc)), 120)
        let km = Double(meters) / 1000.0
        let distStr = meters < 1000 ? "\(meters) m" : String(format: "%.1f km", km)

        let isWalkable = meters <= 450
        let walkDirectMins = max(Int(Double(meters) / 75.0), 2)
        let busMins = isWalkable ? 0 : max(Int(Double(meters) / 260.0), 5)
        let totalMins = isWalkable ? walkDirectMins : (3 + busMins + 2)

        return TacnaDestinationPlace(
            id: "map-\(name)-\(coordinate.latitude)-\(coordinate.longitude)",
            name: name,
            shortName: name,
            subtitle: subtitle.isEmpty ? "Punto de encuentro en el mapa de Tacna" : subtitle,
            category: .mapCustomPlace,
            routesPassing: [],
            iconName: "mappin.and.ellipse",
            iconColorHex: "#38BDF8",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            routeCase: isWalkable ? .walkOnlyNearby : .busRoute14,
            totalDurationMinutes: totalMins,
            secondaryDurationMinutes: totalMins + 5,
            walkingDirectMinutes: walkDirectMins,
            distanceLabel: distStr,
            walkInitialMinutes: isWalkable ? walkDirectMins : 3,
            busRideMinutes: busMins,
            walkFinalMinutes: isWalkable ? 0 : 2,
            boardingStopName: "Mercado 2 de Mayo / Tacna Centro",
            alightingStopName: name,
            intermediateStopName: "Mercado Central",
            statusNote: nil
        )
    }

    // MARK: - Catálogo Oficial de Paraderos de Tacna (27 Puntos Clave + 7 Propuestas de Modernización)
    static let catalog: [TacnaDestinationPlace] = [
        // ═══════════════════════════════════════════════════════════════════
        // 1. MERCADOS Y ZONAS COMERCIALES (9 Paraderos Oficiales)
        // ═══════════════════════════════════════════════════════════════════
        TacnaDestinationPlace(
            id: "stop-mercado-central",
            name: "Mercado Central",
            shortName: "Mercado Central",
            subtitle: "Av. Bolognesi cdra 8 / Calle Zela • Centro Histórico",
            category: .marketsCommercial,
            routesPassing: ["Ruta 14", "Ruta 10B", "Ruta 101"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.01358,
            longitude: -70.25055,
            routeCase: .busRoute14,
            totalDurationMinutes: 8,
            secondaryDurationMinutes: 13,
            walkingDirectMinutes: 14,
            distanceLabel: "1.1 km",
            walkInitialMinutes: 2,
            busRideMinutes: 6,
            walkFinalMinutes: 0,
            boardingStopName: "Mercado 2 de Mayo",
            alightingStopName: "Mercado Central",
            intermediateStopName: nil,
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-mercado-2-mayo",
            name: "Mercado 2 de Mayo",
            shortName: "Mercado 2 de Mayo",
            subtitle: "Calle 2 de Mayo / Av. Leguía • Cercado",
            category: .marketsCommercial,
            routesPassing: ["Ruta 14", "Ruta 10B", "Ruta 203"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.01085,
            longitude: -70.24865,
            routeCase: .walkOnlyNearby,
            totalDurationMinutes: 3,
            secondaryDurationMinutes: 5,
            walkingDirectMinutes: 3,
            distanceLabel: "220 m",
            walkInitialMinutes: 3,
            busRideMinutes: 0,
            walkFinalMinutes: 0,
            boardingStopName: "Mercado 2 de Mayo",
            alightingStopName: "Mercado 2 de Mayo",
            intermediateStopName: nil,
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-mercado-grau",
            name: "Mercado Miguel Grau",
            shortName: "Mercado Grau",
            subtitle: "Av. Saucini / Av. Industrial • Mayorista",
            category: .marketsCommercial,
            routesPassing: ["Ruta 14", "Ruta 101", "Ruta A"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.02420,
            longitude: -70.26210,
            routeCase: .busRoute101,
            totalDurationMinutes: 12,
            secondaryDurationMinutes: 17,
            walkingDirectMinutes: 22,
            distanceLabel: "1.7 km",
            walkInitialMinutes: 2,
            busRideMinutes: 10,
            walkFinalMinutes: 0,
            boardingStopName: "Tacna Centro",
            alightingStopName: "Mercado Miguel Grau",
            intermediateStopName: "Plaza Vigil",
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-mercado-cenepa",
            name: "Mercado Héroes del Cenepa",
            shortName: "Mdo. Héroes del Cenepa",
            subtitle: "Av. Los Próceres / Av. Cenepa • Gregorio Albarracín",
            category: .marketsCommercial,
            routesPassing: ["Ruta 14", "Ruta 203"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.04360,
            longitude: -70.24520,
            routeCase: .busRoute203,
            totalDurationMinutes: 20,
            secondaryDurationMinutes: 26,
            walkingDirectMinutes: 45,
            distanceLabel: "3.8 km",
            walkInitialMinutes: 3,
            busRideMinutes: 17,
            walkFinalMinutes: 0,
            boardingStopName: "Mercado 2 de Mayo",
            alightingStopName: "Mercado Héroes del Cenepa",
            intermediateStopName: "UNJBG",
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-polvos-rosados",
            name: "Mercado Polvos Rosados",
            shortName: "Polvos Rosados",
            subtitle: "Av. Pinto cdra 11 / Jorge Chávez • Alto de la Alianza",
            category: .marketsCommercial,
            routesPassing: ["Ruta 10B", "Ruta 101"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.00695,
            longitude: -70.24590,
            routeCase: .busRoute10B,
            totalDurationMinutes: 11,
            secondaryDurationMinutes: 16,
            walkingDirectMinutes: 19,
            distanceLabel: "1.4 km",
            walkInitialMinutes: 2,
            busRideMinutes: 9,
            walkFinalMinutes: 0,
            boardingStopName: "Plaza San Francisco",
            alightingStopName: "Mercado Polvos Rosados",
            intermediateStopName: "Paseo de las Aguas",
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-mercado-santa-rosa",
            name: "Mercado Santa Rosa",
            shortName: "Mercado Santa Rosa",
            subtitle: "Av. Santa Rosa de Lima • Cono Sur (Viñani)",
            category: .marketsCommercial,
            routesPassing: ["Ruta 14", "Ruta 203"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.04870,
            longitude: -70.24230,
            routeCase: .busRoute203,
            totalDurationMinutes: 23,
            secondaryDurationMinutes: 29,
            walkingDirectMinutes: 52,
            distanceLabel: "4.3 km",
            walkInitialMinutes: 3,
            busRideMinutes: 20,
            walkFinalMinutes: 0,
            boardingStopName: "Mercado 2 de Mayo",
            alightingStopName: "Mercado Santa Rosa",
            intermediateStopName: "Plaza Pérez Gamboa",
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-mercado-pesquero",
            name: "Mercado Pesquero",
            shortName: "Mercado Pesquero",
            subtitle: "Av. Internacional • Ciudad Nueva",
            category: .marketsCommercial,
            routesPassing: ["Ruta 101"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.00240,
            longitude: -70.24210,
            routeCase: .busRoute101,
            totalDurationMinutes: 15,
            secondaryDurationMinutes: 21,
            walkingDirectMinutes: 28,
            distanceLabel: "2.3 km",
            walkInitialMinutes: 2,
            busRideMinutes: 13,
            walkFinalMinutes: 0,
            boardingStopName: "Pasaje Vigil",
            alightingStopName: "Mercado Pesquero",
            intermediateStopName: "C.C. Túpac Amaru",
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-plaza-vea",
            name: "Paradero Av. Cusco (Eje Comercial Sur)",
            shortName: "Paradero Av. Cusco",
            subtitle: "Av. Cusco / Panamericana Sur • Paradero Oficial",
            category: .marketsCommercial,
            routesPassing: ["Ruta 14", "Ruta 10B", "Ruta A"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.02120,
            longitude: -70.25320,
            routeCase: .busRoute14,
            totalDurationMinutes: 7,
            secondaryDurationMinutes: 11,
            walkingDirectMinutes: 10,
            distanceLabel: "750 m",
            walkInitialMinutes: 2,
            busRideMinutes: 5,
            walkFinalMinutes: 0,
            boardingStopName: "Tacna Centro",
            alightingStopName: "Paradero Av. Cusco",
            intermediateStopName: nil,
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-cc-tupac-amaru",
            name: "Centro Comercial Túpac Amaru",
            shortName: "C.C. Túpac Amaru",
            subtitle: "Av. Coronel Mendoza cdra 12",
            category: .marketsCommercial,
            routesPassing: ["Ruta 14", "Ruta 10B", "Ruta 101"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.00790,
            longitude: -70.24670,
            routeCase: .busRoute14,
            totalDurationMinutes: 9,
            secondaryDurationMinutes: 14,
            walkingDirectMinutes: 15,
            distanceLabel: "1.1 km",
            walkInitialMinutes: 2,
            busRideMinutes: 7,
            walkFinalMinutes: 0,
            boardingStopName: "Pasaje Vigil",
            alightingStopName: "C.C. Túpac Amaru",
            intermediateStopName: "Plaza Vigil",
            statusNote: nil
        ),

        // ═══════════════════════════════════════════════════════════════════
        // 2. PLAZAS Y ZONAS CÉNTRICAS (10 Paraderos Oficiales)
        // ═══════════════════════════════════════════════════════════════════
        TacnaDestinationPlace(
            id: "stop-parque-locomotora",
            name: "Parque de la Locomotora",
            shortName: "Parque Locomotora",
            subtitle: "Av. Miguel Grau / 8 de Octubre • Centro Histórico",
            category: .plazasCentral,
            routesPassing: ["Ruta 14", "Ruta 10B", "Ruta A"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.01640,
            longitude: -70.25475,
            routeCase: .busRoute14,
            totalDurationMinutes: 6,
            secondaryDurationMinutes: 10,
            walkingDirectMinutes: 8,
            distanceLabel: "620 m",
            walkInitialMinutes: 2,
            busRideMinutes: 4,
            walkFinalMinutes: 0,
            boardingStopName: "Tacna Centro",
            alightingStopName: "Parque de la Locomotora",
            intermediateStopName: nil,
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-plaza-san-francisco",
            name: "Plaza San Francisco",
            shortName: "Plaza San Francisco",
            subtitle: "Calle Zela / Calle San Francisco • Cercado",
            category: .plazasCentral,
            routesPassing: ["Ruta 14", "Ruta 10B"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.01190,
            longitude: -70.25460,
            routeCase: .walkOnlyNearby,
            totalDurationMinutes: 4,
            secondaryDurationMinutes: 6,
            walkingDirectMinutes: 4,
            distanceLabel: "290 m",
            walkInitialMinutes: 4,
            busRideMinutes: 0,
            walkFinalMinutes: 0,
            boardingStopName: "Plaza San Francisco",
            alightingStopName: "Plaza San Francisco",
            intermediateStopName: nil,
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-plaza-perez-gamboa",
            name: "Plaza Pérez Gamboa",
            shortName: "Plaza Pérez Gamboa",
            subtitle: "Av. Los Molles / Av. Humboldt • Gregorio Albarracín",
            category: .plazasCentral,
            routesPassing: ["Ruta 14", "Ruta 101"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.03470,
            longitude: -70.24920,
            routeCase: .busRoute203,
            totalDurationMinutes: 17,
            secondaryDurationMinutes: 22,
            walkingDirectMinutes: 36,
            distanceLabel: "2.9 km",
            walkInitialMinutes: 2,
            busRideMinutes: 15,
            walkFinalMinutes: 0,
            boardingStopName: "Mercado 2 de Mayo",
            alightingStopName: "Plaza Pérez Gamboa",
            intermediateStopName: "UNJBG",
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-plaza-del-maestro",
            name: "Plaza del Maestro",
            shortName: "Plaza del Maestro",
            subtitle: "Av. Pinto / Calle Tarata • Alto de la Alianza",
            category: .plazasCentral,
            routesPassing: ["Ruta 14", "Ruta 10B"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.00860,
            longitude: -70.24410,
            routeCase: .busRoute14,
            totalDurationMinutes: 11,
            secondaryDurationMinutes: 15,
            walkingDirectMinutes: 18,
            distanceLabel: "1.4 km",
            walkInitialMinutes: 2,
            busRideMinutes: 9,
            walkFinalMinutes: 0,
            boardingStopName: "Mercado 2 de Mayo",
            alightingStopName: "Plaza del Maestro",
            intermediateStopName: "Mercado Central",
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-plaza-vigil",
            name: "Plaza Vigil",
            shortName: "Plaza Vigil",
            subtitle: "Av. Pinto / Calle Vigil / Calle San Martín",
            category: .plazasCentral,
            routesPassing: ["Ruta 14", "Ruta 10B", "Ruta 203"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.00910,
            longitude: -70.24730,
            routeCase: .busRoute14,
            totalDurationMinutes: 7,
            secondaryDurationMinutes: 11,
            walkingDirectMinutes: 9,
            distanceLabel: "680 m",
            walkInitialMinutes: 2,
            busRideMinutes: 5,
            walkFinalMinutes: 0,
            boardingStopName: "Pasaje Vigil",
            alightingStopName: "Plaza Vigil",
            intermediateStopName: nil,
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-plaza-quinones",
            name: "Plaza Quiñones",
            shortName: "Plaza Quiñones",
            subtitle: "Av. Jorge Basadre Norte / Av. Aviación • Alto de la Alianza",
            category: .plazasCentral,
            routesPassing: ["Ruta 10B"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.00430,
            longitude: -70.24060,
            routeCase: .busRoute10B,
            totalDurationMinutes: 11,
            secondaryDurationMinutes: 16,
            walkingDirectMinutes: 17,
            distanceLabel: "1.3 km",
            walkInitialMinutes: 2,
            busRideMinutes: 9,
            walkFinalMinutes: 0,
            boardingStopName: "Gran Hotel Tacna",
            alightingStopName: "Plaza Quiñones",
            intermediateStopName: nil,
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-plaza-jorge-chavez",
            name: "Plaza Jorge Chávez",
            shortName: "Plaza Jorge Chávez",
            subtitle: "Calle Jorge Chávez / Juan Velasco • Cono Norte",
            category: .plazasCentral,
            routesPassing: ["Ruta 14", "Ruta 203"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.00290,
            longitude: -70.24970,
            routeCase: .busRoute14,
            totalDurationMinutes: 16,
            secondaryDurationMinutes: 21,
            walkingDirectMinutes: 32,
            distanceLabel: "2.6 km",
            walkInitialMinutes: 2,
            busRideMinutes: 14,
            walkFinalMinutes: 0,
            boardingStopName: "Mercado 2 de Mayo",
            alightingStopName: "Plaza Jorge Chávez",
            intermediateStopName: "C.C. Túpac Amaru",
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-paseo-aguas",
            name: "Paseo de las Aguas",
            shortName: "Paseo de las Aguas",
            subtitle: "Av. Augusto B. Leguía / Calle San Martín",
            category: .plazasCentral,
            routesPassing: ["Ruta 14", "Ruta 10B"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.00960,
            longitude: -70.25560,
            routeCase: .busRoute14,
            totalDurationMinutes: 6,
            secondaryDurationMinutes: 10,
            walkingDirectMinutes: 8,
            distanceLabel: "580 m",
            walkInitialMinutes: 2,
            busRideMinutes: 4,
            walkFinalMinutes: 0,
            boardingStopName: "Plaza San Francisco",
            alightingStopName: "Paseo de las Aguas",
            intermediateStopName: nil,
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-tacna-centro",
            name: "Tacna Centro",
            shortName: "Tacna Centro",
            subtitle: "Paseo Cívico / Arco Parabólico / Catedral de Tacna",
            category: .plazasCentral,
            routesPassing: ["Ruta 14", "Ruta 10B", "Ruta A"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.01380,
            longitude: -70.25190,
            routeCase: .walkOnlyNearby,
            totalDurationMinutes: 2,
            secondaryDurationMinutes: 4,
            walkingDirectMinutes: 2,
            distanceLabel: "180 m",
            walkInitialMinutes: 2,
            busRideMinutes: 0,
            walkFinalMinutes: 0,
            boardingStopName: "Tacna Centro",
            alightingStopName: "Tacna Centro",
            intermediateStopName: nil,
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-pasaje-vigil",
            name: "Pasaje Vigil",
            shortName: "Pasaje Vigil",
            subtitle: "Pasaje Peatonal Vigil entre Bolognesi y San Martín",
            category: .plazasCentral,
            routesPassing: ["Ruta 14", "Ruta 10B"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.01260,
            longitude: -70.25090,
            routeCase: .walkOnlyNearby,
            totalDurationMinutes: 3,
            secondaryDurationMinutes: 5,
            walkingDirectMinutes: 3,
            distanceLabel: "250 m",
            walkInitialMinutes: 3,
            busRideMinutes: 0,
            walkFinalMinutes: 0,
            boardingStopName: "Pasaje Vigil",
            alightingStopName: "Pasaje Vigil",
            intermediateStopName: nil,
            statusNote: nil
        ),

        // ═══════════════════════════════════════════════════════════════════
        // 3. INSTITUCIONES Y TERMINALES (8 Paraderos Oficiales)
        // ═══════════════════════════════════════════════════════════════════
        TacnaDestinationPlace(
            id: "stop-unjbg",
            name: "Universidad Nacional Jorge Basadre Grohmann (UNJBG)",
            shortName: "UNJBG Campus Central",
            subtitle: "Av. Miraflores s/n / Calle Los Pinos • Ciudad Universitaria",
            category: .institutionsTerminals,
            routesPassing: ["Ruta 14", "Ruta 10B", "Ruta 101"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.02610,
            longitude: -70.24960,
            routeCase: .busRoute14,
            totalDurationMinutes: 14,
            secondaryDurationMinutes: 19,
            walkingDirectMinutes: 28,
            distanceLabel: "2.4 km",
            walkInitialMinutes: 2,
            busRideMinutes: 12,
            walkFinalMinutes: 0,
            boardingStopName: "Mercado 2 de Mayo",
            alightingStopName: "UNJBG Campus Central",
            intermediateStopName: "Plaza del Maestro",
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-terminal-terrestre",
            name: "Terminal Terrestre Manuel A. Odría",
            shortName: "Terminal Nacional",
            subtitle: "Av. Hipólito Unanue / Panamericana Sur",
            category: .institutionsTerminals,
            routesPassing: ["Ruta 14", "Ruta 10B", "Ruta 101", "Ruta 203"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.00660,
            longitude: -70.25760,
            routeCase: .busRoute101,
            totalDurationMinutes: 13,
            secondaryDurationMinutes: 18,
            walkingDirectMinutes: 24,
            distanceLabel: "1.9 km",
            walkInitialMinutes: 2,
            busRideMinutes: 11,
            walkFinalMinutes: 0,
            boardingStopName: "Pasaje Vigil",
            alightingStopName: "Terminal Nacional",
            intermediateStopName: "Mercado Miguel Grau",
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-terminal-bolognesi",
            name: "Terminal Bolognesi",
            shortName: "Terminal Bolognesi",
            subtitle: "Av. Centenario / Salida a Tarata",
            category: .institutionsTerminals,
            routesPassing: ["Ruta 14", "Ruta 10B"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.01410,
            longitude: -70.24610,
            routeCase: .busRoute101,
            totalDurationMinutes: 13,
            secondaryDurationMinutes: 18,
            walkingDirectMinutes: 23,
            distanceLabel: "1.8 km",
            walkInitialMinutes: 2,
            busRideMinutes: 11,
            walkFinalMinutes: 0,
            boardingStopName: "Pasaje Vigil",
            alightingStopName: "Terminal Bolognesi",
            intermediateStopName: "C.C. Túpac Amaru",
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-gobierno-regional",
            name: "Gobierno Regional Tacna",
            shortName: "Gobierno Regional",
            subtitle: "Calle Gregoria Albarracín 526",
            category: .institutionsTerminals,
            routesPassing: ["Ruta 14", "Ruta 10B"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.01960,
            longitude: -70.25910,
            routeCase: .busRoute14,
            totalDurationMinutes: 9,
            secondaryDurationMinutes: 14,
            walkingDirectMinutes: 13,
            distanceLabel: "1.0 km",
            walkInitialMinutes: 2,
            busRideMinutes: 7,
            walkFinalMinutes: 0,
            boardingStopName: "Tacna Centro",
            alightingStopName: "Gobierno Regional Tacna",
            intermediateStopName: "Plaza Vea",
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-poder-judicial",
            name: "Poder Judicial",
            shortName: "Poder Judicial",
            subtitle: "Calle Inclán / Presbítero Andía • Corte Superior",
            category: .institutionsTerminals,
            routesPassing: ["Ruta 14", "Ruta 10B", "Ruta A"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.01560,
            longitude: -70.25360,
            routeCase: .walkOnlyNearby,
            totalDurationMinutes: 3,
            secondaryDurationMinutes: 5,
            walkingDirectMinutes: 3,
            distanceLabel: "240 m",
            walkInitialMinutes: 3,
            busRideMinutes: 0,
            walkFinalMinutes: 0,
            boardingStopName: "Poder Judicial",
            alightingStopName: "Poder Judicial",
            intermediateStopName: nil,
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-estadio-jorge-basadre",
            name: "Estadio Jorge Basadre",
            shortName: "Estadio Jorge Basadre",
            subtitle: "Av. Arias y Aragüez / Olga Grohmann",
            category: .institutionsTerminals,
            routesPassing: ["Ruta 14", "Ruta 10B"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.00560,
            longitude: -70.25090,
            routeCase: .busRoute14,
            totalDurationMinutes: 9,
            secondaryDurationMinutes: 13,
            walkingDirectMinutes: 14,
            distanceLabel: "1.1 km",
            walkInitialMinutes: 2,
            busRideMinutes: 7,
            walkFinalMinutes: 0,
            boardingStopName: "Pasaje Vigil",
            alightingStopName: "Estadio Jorge Basadre",
            intermediateStopName: "Plaza Vigil",
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-radio-nacional",
            name: "Radio Nacional",
            shortName: "Radio Nacional",
            subtitle: "Calle Apurímac / Calle Patricio Meléndez",
            category: .institutionsTerminals,
            routesPassing: ["Ruta 14", "Ruta 10B"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.01510,
            longitude: -70.25160,
            routeCase: .busRoute14,
            totalDurationMinutes: 7,
            secondaryDurationMinutes: 11,
            walkingDirectMinutes: 10,
            distanceLabel: "780 m",
            walkInitialMinutes: 2,
            busRideMinutes: 5,
            walkFinalMinutes: 0,
            boardingStopName: "Pasaje Vigil",
            alightingStopName: "Radio Nacional",
            intermediateStopName: nil,
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-gran-hotel-tacna",
            name: "Gran Hotel Tacna",
            shortName: "Gran Hotel Tacna",
            subtitle: "Av. Bolognesi 300 / Calle Miller",
            category: .institutionsTerminals,
            routesPassing: ["Ruta 14", "Ruta 10B", "Ruta A"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.01760,
            longitude: -70.25610,
            routeCase: .walkOnlyNearby,
            totalDurationMinutes: 3,
            secondaryDurationMinutes: 5,
            walkingDirectMinutes: 3,
            distanceLabel: "210 m",
            walkInitialMinutes: 3,
            busRideMinutes: 0,
            walkFinalMinutes: 0,
            boardingStopName: "Gran Hotel Tacna",
            alightingStopName: "Gran Hotel Tacna",
            intermediateStopName: nil,
            statusNote: nil
        ),

        // ═══════════════════════════════════════════════════════════════════
        // 4. PROPUESTAS DE PARADEROS PARA OFICIALIZAR (Modernización Tacna)
        // ═══════════════════════════════════════════════════════════════════
        // A. Hospitales y Centros de Salud (Prioridad Adulto Mayor)
        TacnaDestinationPlace(
            id: "prop-hospital-unanue",
            name: "Hospital Regional Hipólito Unanue",
            shortName: "Hosp. Hipólito Unanue",
            subtitle: "Calle Blondell / Calle 2 de Mayo • Accesibilidad Prioritaria",
            category: .proposedHospitals,
            routesPassing: ["Ruta 10B", "Ruta 14"],
            iconName: "bus.fill",
            iconColorHex: "#F59E0B",
            latitude: -18.01010,
            longitude: -70.24360,
            routeCase: .busRoute10B,
            totalDurationMinutes: 8,
            secondaryDurationMinutes: 12,
            walkingDirectMinutes: 12,
            distanceLabel: "890 m",
            walkInitialMinutes: 2,
            busRideMinutes: 6,
            walkFinalMinutes: 0,
            boardingStopName: "Plaza San Francisco",
            alightingStopName: "Hospital Hipólito Unanue",
            intermediateStopName: nil,
            statusNote: "Propuesta Oficialización: Accesibilidad Adulto Mayor / CONADIS"
        ),
        TacnaDestinationPlace(
            id: "prop-hospital-essalud-calana",
            name: "Hospital EsSalud Daniel Alcides Carrión (Calana)",
            shortName: "Hosp. EsSalud Calana",
            subtitle: "Carretera a Calana Km 7 • Valle Viejo",
            category: .proposedHospitals,
            routesPassing: ["Ruta 10B"],
            iconName: "bus.fill",
            iconColorHex: "#F59E0B",
            latitude: -17.97160,
            longitude: -70.20110,
            routeCase: .busRoute10B,
            totalDurationMinutes: 26,
            secondaryDurationMinutes: 34,
            walkingDirectMinutes: 85,
            distanceLabel: "7.4 km",
            walkInitialMinutes: 2,
            busRideMinutes: 24,
            walkFinalMinutes: 0,
            boardingStopName: "Plaza San Francisco",
            alightingStopName: "Hospital EsSalud Calana",
            intermediateStopName: "UPT Campus Capanique",
            statusNote: "Propuesta Oficialización: Prioridad Adulto Mayor"
        ),
        TacnaDestinationPlace(
            id: "prop-postas-medicas",
            name: "Posta Médica Cono Sur (Viñani)",
            shortName: "Posta Médica Viñani",
            subtitle: "Av. Municipal con Calle 10 • Gregorio Albarracín",
            category: .proposedHospitals,
            routesPassing: ["Ruta 14", "Ruta 101"],
            iconName: "bus.fill",
            iconColorHex: "#F59E0B",
            latitude: -18.05510,
            longitude: -70.24010,
            routeCase: .busRoute203,
            totalDurationMinutes: 18,
            secondaryDurationMinutes: 24,
            walkingDirectMinutes: 40,
            distanceLabel: "3.3 km",
            walkInitialMinutes: 2,
            busRideMinutes: 16,
            walkFinalMinutes: 0,
            boardingStopName: "Mercado 2 de Mayo",
            alightingStopName: "Posta Médica Viñani",
            intermediateStopName: "UNJBG",
            statusNote: "Propuesta Oficialización: Red de Postas Médicas"
        ),

        // B. Zonas de Crecimiento Urbano (Cono Sur y Cono Norte)
        TacnaDestinationPlace(
            id: "prop-vinani-albarracin",
            name: "Viñani - Av. Municipal",
            shortName: "Viñani (Av. Municipal)",
            subtitle: "Av. Municipal cdra 20 • Asoc. Nuevas Cono Sur",
            category: .proposedUrbanGrowth,
            routesPassing: ["Ruta 14"],
            iconName: "bus.fill",
            iconColorHex: "#F59E0B",
            latitude: -18.06110,
            longitude: -70.23810,
            routeCase: .busRoute203,
            totalDurationMinutes: 25,
            secondaryDurationMinutes: 31,
            walkingDirectMinutes: 60,
            distanceLabel: "5.1 km",
            walkInitialMinutes: 3,
            busRideMinutes: 22,
            walkFinalMinutes: 0,
            boardingStopName: "Mercado 2 de Mayo",
            alightingStopName: "Paradero Formal Viñani",
            intermediateStopName: "Mercado Santa Rosa",
            statusNote: "Propuesta Cono Sur: Ordenamiento Urbano en Viñani"
        ),
        TacnaDestinationPlace(
            id: "prop-ciudad-nueva",
            name: "Ciudad Nueva - Av. Internacional",
            shortName: "Ciudad Nueva (Plaza Olaya)",
            subtitle: "Plaza José Olaya / Av. Internacional • Cono Norte",
            category: .proposedUrbanGrowth,
            routesPassing: ["Ruta 10B"],
            iconName: "bus.fill",
            iconColorHex: "#F59E0B",
            latitude: -17.99810,
            longitude: -70.23910,
            routeCase: .busRoute14,
            totalDurationMinutes: 19,
            secondaryDurationMinutes: 24,
            walkingDirectMinutes: 42,
            distanceLabel: "3.4 km",
            walkInitialMinutes: 2,
            busRideMinutes: 17,
            walkFinalMinutes: 0,
            boardingStopName: "Pasaje Vigil",
            alightingStopName: "Paradero Formal Ciudad Nueva",
            intermediateStopName: "Plaza Jorge Chávez",
            statusNote: "Propuesta Cono Norte: Reducción de Paradas Informales"
        ),

        // C. Zonas Educativas Estratégicas (Geofencing Carnet Universitario)
        TacnaDestinationPlace(
            id: "prop-upt-colegios",
            name: "Universidad Privada de Tacna (UPT)",
            shortName: "UPT (Campus Capanique)",
            subtitle: "Av. Jorge Basadre Grohmann Poniente / Capanique",
            category: .proposedEducation,
            routesPassing: ["Ruta 10B", "Ruta 203"],
            iconName: "bus.fill",
            iconColorHex: "#F59E0B",
            latitude: -18.04110,
            longitude: -70.26410,
            routeCase: .busRoute10B,
            totalDurationMinutes: 16,
            secondaryDurationMinutes: 21,
            walkingDirectMinutes: 35,
            distanceLabel: "2.9 km",
            walkInitialMinutes: 2,
            busRideMinutes: 14,
            walkFinalMinutes: 0,
            boardingStopName: "Plaza San Francisco",
            alightingStopName: "UPT Campus Capanique",
            intermediateStopName: "Hospital Hipólito Unanue",
            statusNote: "Propuesta Geofencing: Validación Tarifaria Universitaria"
        ),

        // D. Zonas Turísticas y Fronterizas (Tótems Informativos)
        TacnaDestinationPlace(
            id: "prop-complejo-santa-rosa",
            name: "Complejo Fronterizo Santa Rosa (Tótem Inteligente)",
            shortName: "Frontera Santa Rosa",
            subtitle: "Panamericana Sur Km 1336 • Frontera Perú - Chile",
            category: .proposedTouristBorder,
            routesPassing: ["Corredor Turístico-Fronterizo"],
            iconName: "bus.fill",
            iconColorHex: "#F59E0B",
            latitude: -18.31510,
            longitude: -70.32010,
            routeCase: .busRoute101,
            totalDurationMinutes: 35,
            secondaryDurationMinutes: 45,
            walkingDirectMinutes: 180,
            distanceLabel: "34.0 km",
            walkInitialMinutes: 3,
            busRideMinutes: 32,
            walkFinalMinutes: 0,
            boardingStopName: "Terminal Terrestre",
            alightingStopName: "Complejo Fronterizo Santa Rosa",
            intermediateStopName: "Aeropuerto / Panamericana Sur",
            statusNote: "Propuesta Turística: Equipado con Tótem Digital de ETAs"
        )
    ]
}

// MARK: - Clasificación Operativa de Rutas (Ordinarias con Tracking/QR vs Externas Referenciales)
enum RouteServiceType: String, Codable, Equatable {
    case ordinary = "ordinary" // Rutas propias de Bus Conectado (Con Tracking GPS, Pago QR y Notificación)
    case external = "external" // Líneas tradicionales de Tacna (Solo referenciales, sin tracking ni QR)
}

/// Estado de disponibilidad de notificación de llegada para un paradero según las rutas ordinarias que pasan por él
enum StopNotificationAvailability: Equatable {
    /// Pasa al menos una Ruta Ordinaria y se encuentra En Servicio activo
    case available(activeRoutes: [TacnaOfficialRouteCatalogItem])
    /// El paradero tiene registrada al menos una Ruta Ordinaria, pero ninguna está en servicio actualmente
    case ordinaryOutOfService(registeredRoutes: [TacnaOfficialRouteCatalogItem])
    /// No pasa ninguna Ruta Ordinaria por este punto (solo rutas externas o punto de encuentro del mapa)
    case noOrdinaryRoutes
}

// MARK: - DTO de Rutas para Sincronización con el Panel Administrador Web (/api/v1/transit/routes)
struct AdminRouteDTO: Codable, Identifiable {
    let id: String
    let code: String
    let title: String
    let routeType: String?
    let isInService: Bool?
    let supportsQrPayment: Bool?
    let supportsArrivalNotification: Bool?
    let statusLabel: String?
    let corridor: String?
    let frequencyMinutes: Int?
    let averageSpeedKmh: Double?
    let totalDistanceKm: Double?
    let estimatedTotalMinutes: Int?
    let scheduleLabel: String?
    let colorHex: String?
    let iconName: String?
    let keyStopIds: [String]?
    let pathCoordinates: [[Double]]?
    let isClosedLoop: Bool?

    func toRouteCatalogItem() -> TacnaOfficialRouteCatalogItem {
        let resolvedType: RouteServiceType = (routeType?.lowercased() == "external") ? .external : .ordinary
        let inService = (resolvedType == .ordinary) ? (isInService ?? true) : false
        let freqMins = frequencyMinutes ?? (resolvedType == .ordinary ? 6 : 0)
        let freqLabel: String
        if resolvedType == .ordinary {
            freqLabel = inService ? "Cada \(max(1, freqMins)) min" : "Fuera de servicio"
        } else {
            freqLabel = "Referencial (Sin GPS)"
        }

        let defaultStatus: String
        if resolvedType == .ordinary {
            defaultStatus = inService
                ? "En Servicio • GPS & Pago QR Activo"
                : "Fuera de Servicio Temporal • Sin unidades activas"
        } else {
            defaultStatus = "Línea Externa de Tacna • Sin Tracking GPS"
        }

        return TacnaOfficialRouteCatalogItem(
            id: id,
            code: code.uppercased(),
            title: title,
            routeType: resolvedType,
            isInService: inService,
            supportsQrPayment: supportsQrPayment ?? (resolvedType == .ordinary),
            supportsArrivalNotification: supportsArrivalNotification ?? (resolvedType == .ordinary),
            statusLabel: statusLabel ?? defaultStatus,
            corridorSummary: corridor ?? title,
            frequencyMinutes: freqMins,
            averageSpeedKmh: averageSpeedKmh ?? 22.0,
            totalDistanceKm: totalDistanceKm ?? 12.5,
            estimatedTotalMinutes: estimatedTotalMinutes ?? 38,
            frequencyLabel: freqLabel,
            scheduleLabel: scheduleLabel ?? "05:30 - 22:30",
            colorHex: colorHex ?? (resolvedType == .ordinary ? "#2563EB" : "#64748B"),
            keyStopIds: keyStopIds ?? [],
            pathCoordinates: pathCoordinates ?? [],
            isClosedLoop: isClosedLoop ?? false
        )
    }
}

// MARK: - Catálogo Oficial de Rutas (Ordinarias con Tracking/QR y Externas Referenciales de Tacna)
struct TacnaOfficialRouteCatalogItem: Identifiable, Equatable {
    let id: String
    let code: String
    let title: String
    let routeType: RouteServiceType
    var isInService: Bool
    let supportsQrPayment: Bool
    let supportsArrivalNotification: Bool
    let statusLabel: String
    let corridorSummary: String
    let frequencyMinutes: Int
    let averageSpeedKmh: Double
    let totalDistanceKm: Double
    let estimatedTotalMinutes: Int
    let frequencyLabel: String
    let scheduleLabel: String
    let colorHex: String
    let keyStopIds: [String]
    let pathCoordinates: [[Double]]
    var isClosedLoop: Bool = false

    var isOrdinary: Bool {
        routeType == .ordinary
    }

    var isOrdinaryInService: Bool {
        routeType == .ordinary && isInService
    }

    var isExternal: Bool {
        routeType == .external
    }

    /// Resuelve los paraderos de la ruta usando el catálogo sincronizado en memoria (compatible con IDs con o sin prefijo "stop-")
    func resolvedStops(using catalog: [TacnaDestinationPlace] = TacnaDestinationPlace.catalog) -> [TacnaDestinationPlace] {
        keyStopIds.compactMap { rawId in
            let normalized = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
            let withoutStopPrefix = normalized.replacingOccurrences(of: "stop-", with: "")
            let withStopPrefix = normalized.hasPrefix("stop-") ? normalized : "stop-\(normalized)"

            return catalog.first { place in
                place.id == normalized ||
                place.id == withoutStopPrefix ||
                place.id == withStopPrefix ||
                (normalized == "mercado-2-de-mayo" && place.id == "stop-mercado-2-mayo") ||
                (normalized == "stop-mercado-2-mayo" && place.id == "mercado-2-de-mayo") ||
                (normalized == "prop-vinani-crecimiento" && place.id == "prop-vinani-albarracin") ||
                (normalized == "prop-ciudad-nueva-crecimiento" && place.id == "prop-ciudad-nueva") ||
                (normalized == "prop-upt-capanique" && place.id == "prop-upt-colegios") ||
                (normalized == "prop-frontera-santa-rosa" && place.id == "prop-complejo-santa-rosa")
            }
        }
    }

    /// Compatibilidad directa cuando no se pasa catálogo explícito
    var resolvedStops: [TacnaDestinationPlace] {
        resolvedStops(using: TacnaDestinationPlace.catalog)
    }

    /// Coordenadas para trazar la polilínea en el mapa (usa pathCoordinates trazadas por el administrador o los paraderos resueltos)
    func resolvedPolylineCoordinates(using catalog: [TacnaDestinationPlace] = TacnaDestinationPlace.catalog) -> [CLLocationCoordinate2D] {
        if pathCoordinates.count >= 2 {
            return pathCoordinates.compactMap { pair in
                guard pair.count >= 2 else { return nil }
                return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
            }
        }
        return resolvedStops(using: catalog).map(\.coordinate)
    }

    /// Calcula el tiempo aproximado acumulado (en minutos) desde el inicio de la ruta hasta el paradero indicado (Referencia App + Chofer)
    func estimatedArrivalMinutesFromOrigin(forStopAt index: Int, using catalog: [TacnaDestinationPlace]) -> Int {
        let stops = resolvedStops(using: catalog)
        guard index > 0, index < stops.count else { return 0 }
        var cumulativeMeters: Double = 0
        for i in 1...index {
            let prev = CLLocation(latitude: stops[i - 1].latitude, longitude: stops[i - 1].longitude)
            let curr = CLLocation(latitude: stops[i].latitude, longitude: stops[i].longitude)
            cumulativeMeters += prev.distance(from: curr) * 1.25
        }
        let km = cumulativeMeters / 1000.0
        let speed = max(10.0, averageSpeedKmh)
        let driveMins = (km / speed) * 60.0
        let dwellMins = Double(index) * 0.42
        return max(1, Int(round(driveMins + dwellMins)))
    }

    static let officialRoutes: [TacnaOfficialRouteCatalogItem] = [
        TacnaOfficialRouteCatalogItem(
            id: "tacna-ruta-14",
            code: "RUTA 14",
            title: "Eje Troncal Cono Norte – Centro – UNJBG – Cono Sur",
            routeType: .ordinary,
            isInService: true,
            supportsQrPayment: true,
            supportsArrivalNotification: true,
            statusLabel: "En Servicio • GPS & Pago QR Activo",
            corridorSummary: "Ciudad Nueva ⇄ C.C. Túpac Amaru ⇄ Mercado 2 de Mayo ⇄ Mercado Central ⇄ UNJBG ⇄ Gregorio Albarracín (Viñani)",
            frequencyMinutes: 5,
            averageSpeedKmh: 22.0,
            totalDistanceKm: 20.31,
            estimatedTotalMinutes: 68,
            frequencyLabel: "Cada 5 min",
            scheduleLabel: "05:30 - 22:30",
            colorHex: "#2563EB",
            keyStopIds: [
                "prop-ciudad-nueva-crecimiento",
                "plaza-jorge-chavez",
                "estadio-jorge-basadre",
                "cc-tupac-amaru",
                "plaza-vigil",
                "pasaje-vigil",
                "mercado-2-de-mayo",
                "mercado-central",
                "tacna-centro",
                "plaza-vea",
                "gobierno-regional",
                "plaza-del-maestro",
                "unjbg",
                "plaza-perez-gamboa",
                "mercado-cenepa",
                "mercado-santa-rosa",
                "prop-vinani-crecimiento"
            ],
            pathCoordinates: []
        ),
        TacnaOfficialRouteCatalogItem(
            id: "tacna-ruta-10b",
            code: "RUTA 10B",
            title: "Corredor Universitario, Hospitalario y Céntrico",
            routeType: .ordinary,
            isInService: false,
            supportsQrPayment: true,
            supportsArrivalNotification: true,
            statusLabel: "Fuera de Servicio Temporal • Sin unidades activas",
            corridorSummary: "Polvos Rosados ⇄ Paseo de las Aguas ⇄ Plaza San Francisco ⇄ Hosp. Unanue ⇄ UNJBG ⇄ UPT ⇄ EsSalud Calana",
            frequencyMinutes: 6,
            averageSpeedKmh: 21.0,
            totalDistanceKm: 24.59,
            estimatedTotalMinutes: 82,
            frequencyLabel: "Fuera de servicio",
            scheduleLabel: "06:00 - 22:00",
            colorHex: "#10B981",
            keyStopIds: [
                "polvos-rosados",
                "paseo-aguas",
                "plaza-san-francisco",
                "gran-hotel-tacna",
                "poder-judicial",
                "parque-locomotora",
                "prop-hospital-unanue",
                "plaza-quinones",
                "unjbg",
                "prop-upt-capanique",
                "prop-hospital-essalud-calana"
            ],
            pathCoordinates: []
        ),
        TacnaOfficialRouteCatalogItem(
            id: "tacna-ruta-101",
            code: "RUTA 101",
            title: "Corredor Comercial, Terminales y Parque Industrial",
            routeType: .external,
            isInService: false,
            supportsQrPayment: false,
            supportsArrivalNotification: false,
            statusLabel: "Línea Externa de Tacna • Sin Tracking GPS",
            corridorSummary: "Mercado Pesquero ⇄ Terminal Terrestre ⇄ Terminal Bolognesi ⇄ Mercado Grau ⇄ Radio Nacional ⇄ Mercado Central",
            frequencyMinutes: 8,
            averageSpeedKmh: 20.0,
            totalDistanceKm: 9.5,
            estimatedTotalMinutes: 32,
            frequencyLabel: "Referencial (Sin GPS)",
            scheduleLabel: "05:30 - 22:00",
            colorHex: "#F59E0B",
            keyStopIds: [
                "mercado-pesquero",
                "terminal-terrestre",
                "terminal-bolognesi",
                "mercado-grau",
                "radio-nacional",
                "cc-tupac-amaru",
                "plaza-vigil",
                "mercado-central"
            ],
            pathCoordinates: []
        ),
        TacnaOfficialRouteCatalogItem(
            id: "tacna-ruta-203",
            code: "RUTA 203",
            title: "Expreso Cono Sur – Mercados – Campus UNJBG",
            routeType: .external,
            isInService: false,
            supportsQrPayment: false,
            supportsArrivalNotification: false,
            statusLabel: "Línea Externa de Tacna • Sin Tracking GPS",
            corridorSummary: "Mercado 2 de Mayo ⇄ Plaza del Maestro ⇄ UNJBG ⇄ Plaza Pérez Gamboa ⇄ Postas Médicas ⇄ Mdo. Cenepa ⇄ Viñani",
            frequencyMinutes: 7,
            averageSpeedKmh: 22.0,
            totalDistanceKm: 7.84,
            estimatedTotalMinutes: 25,
            frequencyLabel: "Referencial (Sin GPS)",
            scheduleLabel: "05:45 - 22:15",
            colorHex: "#A855F7",
            keyStopIds: [
                "mercado-2-de-mayo",
                "plaza-del-maestro",
                "unjbg",
                "plaza-perez-gamboa",
                "prop-postas-medicas",
                "mercado-cenepa",
                "mercado-santa-rosa",
                "prop-vinani-crecimiento"
            ],
            pathCoordinates: []
        ),
        TacnaOfficialRouteCatalogItem(
            id: "tacna-ruta-a",
            code: "RUTA A",
            title: "Anillo Histórico y Turístico – Complejo Santa Rosa",
            routeType: .external,
            isInService: false,
            supportsQrPayment: false,
            supportsArrivalNotification: false,
            statusLabel: "Línea Externa de Tacna • Sin Tracking GPS",
            corridorSummary: "Parque de la Locomotora ⇄ Tacna Centro ⇄ Gran Hotel Tacna ⇄ Paseo de las Aguas ⇄ Terminal Terrestre ⇄ Santa Rosa",
            frequencyMinutes: 12,
            averageSpeedKmh: 25.0,
            totalDistanceKm: 41.94,
            estimatedTotalMinutes: 103,
            frequencyLabel: "Referencial (Sin GPS)",
            scheduleLabel: "06:00 - 21:30",
            colorHex: "#06B6D4",
            keyStopIds: [
                "parque-locomotora",
                "tacna-centro",
                "gran-hotel-tacna",
                "plaza-san-francisco",
                "paseo-aguas",
                "plaza-vea",
                "terminal-terrestre",
                "prop-frontera-santa-rosa"
            ],
            pathCoordinates: []
        )
    ]
}

// MARK: - Estado de Guía de Ruta Activa en el Mapa Principal (Cuando se presiona [Iniciar])
struct ActiveRouteGuidanceState: Equatable {
    let origin: TacnaDestinationPlace
    let destination: TacnaDestinationPlace
    let selectedOptionIndex: Int
    var candidate: EvaluatedRouteCandidate?
    var remainingBusArrivalSeconds: Int
    var fiveMinuteAlertFired: Bool = false

    init(
        origin: TacnaDestinationPlace = TacnaDestinationPlace.currentLocationPlace(),
        destination: TacnaDestinationPlace,
        selectedOptionIndex: Int = 0,
        candidate: EvaluatedRouteCandidate? = nil,
        remainingBusArrivalSeconds: Int = 305,
        fiveMinuteAlertFired: Bool = false
    ) {
        self.origin = origin
        self.destination = destination
        self.selectedOptionIndex = selectedOptionIndex
        self.candidate = candidate
        self.remainingBusArrivalSeconds = remainingBusArrivalSeconds
        self.fiveMinuteAlertFired = fiveMinuteAlertFired
    }
}

extension TacnaDestinationPlace {
    /// Representa la ubicación actual del usuario como punto de partida o llegada
    static func currentLocationPlace() -> TacnaDestinationPlace {
        let coord = userOriginCoordinate
        return TacnaDestinationPlace(
            id: "user-current-gps-origin",
            name: "Tu ubicación actual",
            shortName: "Tu ubicación",
            subtitle: "Ubicación GPS en Tacna",
            category: .mapCustomPlace,
            routesPassing: [],
            iconName: "location.fill",
            iconColorHex: "#0A84FF",
            latitude: coord.latitude,
            longitude: coord.longitude,
            routeCase: .walkOnlyNearby,
            totalDurationMinutes: 0,
            secondaryDurationMinutes: 0,
            walkingDirectMinutes: 0,
            distanceLabel: "0 m",
            walkInitialMinutes: 0,
            busRideMinutes: 0,
            walkFinalMinutes: 0,
            boardingStopName: "Tu ubicación",
            alightingStopName: "Tu ubicación",
            intermediateStopName: nil,
            statusNote: nil
        )
    }
}

// MARK: - Gestor de Notificaciones Nativas iOS (UNUserNotificationCenter) para Aviso de 5 Minutos
final class BCNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = BCNotificationManager()

    private override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
    }

    func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func triggerFiveMinuteBusArrivalNotification(
        routeCode: String,
        boardingStopName: String,
        destinationName: String,
        walkMinutesToStop: Int
    ) {
        requestAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = "🚌 ¡\(routeCode) a 5 min de tu paradero!"
        content.subtitle = "Paradero de subida: \(boardingStopName)"
        content.body = "Tu bus ordinario llegará en ~5 minutos a \(boardingStopName) rumbo a \(destinationName). Camina hacia el paradero (~\(max(walkMinutesToStop, 1)) min a pie) para abordar con QR."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(
            identifier: "bc-5min-alert-\(routeCode)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // Mostrar banner y sonido incluso con la app abierta en primer plano
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

// MARK: - Modelos y Motor de Automatización de Rutas (Rutas Ordinarias vs. Externas + Caminata)

enum RouteCandidateKind: String, Equatable {
    case ordinaryInService     // Ruta Ordinaria activa: subida/bajada en paraderos oficiales, tracking GPS, QR y aviso a 5 min
    case externalFreeBoarding  // Ruta Externa: subida/bajada libre en cualquier punto de la vía por donde pasa, sin tracking
    case walkingDirect         // Caminata directa de inicio a fin
}

struct EvaluatedRouteCandidate: Identifiable, Equatable {
    let id: String
    let kind: RouteCandidateKind
    let route: TacnaOfficialRouteCatalogItem?
    let routeCode: String
    let routeTitle: String
    let colorHex: String

    let totalDurationMinutes: Int
    let totalDistanceMeters: Int

    let walkInitialMinutes: Int
    let walkInitialMeters: Int
    let busWaitMinutes: Int
    let busRideMinutes: Int
    let busRideMeters: Int
    let walkFinalMinutes: Int
    let walkFinalMeters: Int

    let boardingStop: TacnaDestinationPlace?
    let alightingStop: TacnaDestinationPlace?
    let intermediateStopsCount: Int
    let intermediateStopNames: [String]

    let boardingPointName: String
    let alightingPointName: String
    let boardingLatitude: Double
    let boardingLongitude: Double
    let alightingLatitude: Double
    let alightingLongitude: Double

    /// Polilíneas calculadas para los 3 tramos: Caminata inicial -> Bus (sobre ruta real) -> Caminata final
    let walkToBoardCoords: [[Double]]
    let busTransitCoords: [[Double]]
    let walkFinalCoords: [[Double]]

    var isRecommendedPrimary: Bool
    var externalRecommendationReason: String?

    // Campos para rutas con transbordo (2 rutas)
    var isTransfer: Bool = false
    var secondRouteCode: String? = nil
    var secondRouteColorHex: String? = nil
    var transferPointName: String? = nil
    var transferLatitude: Double? = nil
    var transferLongitude: Double? = nil
    var transferWalkMeters: Int = 0
    var firstBusRideMinutes: Int = 0
    var secondBusRideMinutes: Int = 0
    var secondBusTransitCoords: [[Double]] = []
    var transferWalkCoords: [[Double]] = []

    var transferCoordinate: CLLocationCoordinate2D? {
        guard let lat = transferLatitude, let lon = transferLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var secondBusTransitCLCoordinates: [CLLocationCoordinate2D] {
        secondBusTransitCoords.compactMap { $0.count >= 2 ? CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) : nil }
    }

    var transferWalkCLCoordinates: [CLLocationCoordinate2D] {
        transferWalkCoords.compactMap { $0.count >= 2 ? CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) : nil }
    }

    var boardingCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: boardingLatitude, longitude: boardingLongitude)
    }

    var alightingCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: alightingLatitude, longitude: alightingLongitude)
    }

    var walkToBoardCLCoordinates: [CLLocationCoordinate2D] {
        walkToBoardCoords.compactMap { $0.count >= 2 ? CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) : nil }
    }

    var busTransitCLCoordinates: [CLLocationCoordinate2D] {
        busTransitCoords.compactMap { $0.count >= 2 ? CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) : nil }
    }

    var walkFinalCLCoordinates: [CLLocationCoordinate2D] {
        walkFinalCoords.compactMap { $0.count >= 2 ? CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) : nil }
    }

    var totalDistanceLabel: String {
        if totalDistanceMeters < 1000 {
            return "\(totalDistanceMeters) m"
        }
        return String(format: "%.1f km", Double(totalDistanceMeters) / 1000.0)
    }

    var walkTotalMeters: Int {
        walkInitialMeters + transferWalkMeters + walkFinalMeters
    }

    var supportsFiveMinuteAlert: Bool {
        kind == .ordinaryInService
    }
}

struct RouteAutomationEvaluationResult: Equatable {
    let origin: TacnaDestinationPlace
    let destination: TacnaDestinationPlace
    let candidates: [EvaluatedRouteCandidate]
    let primaryBannerWarning: String?
    let hasOrdinaryInService: Bool

    var recommendedCandidate: EvaluatedRouteCandidate? {
        candidates.first
    }

    var ordinaryCandidates: [EvaluatedRouteCandidate] {
        candidates.filter { $0.kind == .ordinaryInService }
    }

    var externalCandidates: [EvaluatedRouteCandidate] {
        candidates.filter { $0.kind == .externalFreeBoarding }
    }

    var walkingCandidate: EvaluatedRouteCandidate? {
        candidates.first(where: { $0.kind == .walkingDirect })
    }
}

enum RouteAutomationEngine {
    /// Distancia en metros entre dos coordenadas
    static func distanceMeters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let locA = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let locB = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return locA.distance(from: locB)
    }

    /// Extrae el sub-segmento de una polilínea vial entre el vértice más cercano a `start` y el más cercano a `end`
    static func extractRouteSubPolyline(
        from fullPolyline: [CLLocationCoordinate2D],
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) -> (subCoords: [CLLocationCoordinate2D], boardVertex: CLLocationCoordinate2D, alightVertex: CLLocationCoordinate2D, lengthMeters: Double, isForwardValid: Bool) {
        guard fullPolyline.count >= 2 else {
            let d = distanceMeters(start, end) * 1.25
            return ([start, end], start, end, d, true)
        }

        var startIdx = 0
        var minStartDist = Double.greatestFiniteMagnitude
        var endIdx = 0
        var minEndDist = Double.greatestFiniteMagnitude

        for (i, pt) in fullPolyline.enumerated() {
            let ds = distanceMeters(start, pt)
            if ds < minStartDist {
                minStartDist = ds
                startIdx = i
            }
            let de = distanceMeters(end, pt)
            if de < minEndDist {
                minEndDist = de
                endIdx = i
            }
        }

        if startIdx > endIdx {
            return ([], fullPolyline[startIdx], fullPolyline[endIdx], 0, false)
        }

        if startIdx == endIdx {
            if endIdx < fullPolyline.count - 1 {
                endIdx += 1
            } else {
                return ([], fullPolyline[startIdx], fullPolyline[endIdx], 0, false)
            }
        }

        let slice = Array(fullPolyline[startIdx...endIdx])

        var totalMeters: Double = 0
        if slice.count >= 2 {
            for k in 0..<(slice.count - 1) {
                totalMeters += distanceMeters(slice[k], slice[k + 1])
            }
        } else {
            totalMeters = distanceMeters(start, end) * 1.25
        }

        let boardPt = slice.first ?? start
        let alightPt = slice.last ?? end
        return (slice, boardPt, alightPt, max(totalMeters, 120), true)
    }

    /// Evalúa de forma automática las opciones para ir desde `origin` hasta `destination`:
    /// 1) Rutas Ordinarias en servicio (subiendo y bajando obligatoriamente en Paraderos Oficiales de la ruta).
    /// 2) Rutas Externas (subiendo y bajando en cualquier punto de la calle por donde pasa la ruta).
    /// 3) Caminata directa.
    /// Aplica la regla de prioridad: prioriza la Ruta Ordinaria más corta salvo que no haya ninguna en servicio
    /// o que la Ruta Ordinaria demore +10 min más o exija caminar > 700 m adicionales respecto a una Ruta Externa.
    static func evaluateRoutes(
        from origin: TacnaDestinationPlace,
        to destination: TacnaDestinationPlace,
        stops: [TacnaDestinationPlace],
        routes: [TacnaOfficialRouteCatalogItem],
        activeBuses: [ActiveBusModel]
    ) -> RouteAutomationEvaluationResult {
        let originCoord = origin.coordinate
        let destCoord = destination.coordinate
        let directRawMeters = distanceMeters(originCoord, destCoord)
        let directWalkMeters = max(Int(directRawMeters * 1.18), 40)
        let directWalkMinutes = max(Int(round(Double(directWalkMeters) / 76.0)), 1)

        // 1. Candidato de Caminata Directa (siempre disponible como referencia)
        let walkCandidate = EvaluatedRouteCandidate(
            id: "cand-walk-\(origin.id)-\(destination.id)",
            kind: .walkingDirect,
            route: nil,
            routeCode: "A pie",
            routeTitle: "Caminata directa por las calles de Tacna",
            colorHex: "#38BDF8",
            totalDurationMinutes: directWalkMinutes,
            totalDistanceMeters: directWalkMeters,
            walkInitialMinutes: directWalkMinutes,
            walkInitialMeters: directWalkMeters,
            busWaitMinutes: 0,
            busRideMinutes: 0,
            busRideMeters: 0,
            walkFinalMinutes: 0,
            walkFinalMeters: 0,
            boardingStop: nil,
            alightingStop: nil,
            intermediateStopsCount: 0,
            intermediateStopNames: [],
            boardingPointName: origin.shortName,
            alightingPointName: destination.shortName,
            boardingLatitude: originCoord.latitude,
            boardingLongitude: originCoord.longitude,
            alightingLatitude: destCoord.latitude,
            alightingLongitude: destCoord.longitude,
            walkToBoardCoords: [
                [originCoord.latitude, originCoord.longitude],
                [destCoord.latitude, destCoord.longitude]
            ],
            busTransitCoords: [],
            walkFinalCoords: [],
            isRecommendedPrimary: false,
            externalRecommendationReason: nil
        )

        var ordinaryCandidates: [EvaluatedRouteCandidate] = []
        var externalCandidates: [EvaluatedRouteCandidate] = []

        // 2. Evaluar cada Ruta Ordinaria En Servicio (Abordaje y bajada en Paraderos Oficiales)
        let activeOrdRoutes = routes.filter { $0.isOrdinary && $0.isInService }
        for route in activeOrdRoutes {
            let baseStops = route.resolvedStops(using: stops)
            guard baseStops.count >= 2 else { continue }
            let fullPoly = route.resolvedPolylineCoordinates(using: stops)
            let isLoop = route.isClosedLoop ||
                (baseStops.count >= 3 && baseStops.first?.id == baseStops.last?.id) ||
                (fullPoly.count >= 4 && distanceMeters(fullPoly.first!, fullPoly.last!) <= 80.0)
            let routeStops = (isLoop && baseStops.first?.id != baseStops.last?.id)
                ? (baseStops + [baseStops.first!])
                : baseStops

            var bestPairForRoute: (
                boardStop: TacnaDestinationPlace,
                alightStop: TacnaDestinationPlace,
                boardIdx: Int,
                alightIdx: Int,
                walk1Meters: Int,
                walk2Meters: Int,
                scoreMinutes: Double
            )? = nil

            for (i, sBoard) in routeStops.enumerated() where i + 1 < routeStops.count {
                let dWalk1 = distanceMeters(originCoord, sBoard.coordinate) * 1.18
                for j in (i + 1)..<routeStops.count {
                    let sAlight = routeStops[j]
                    if sAlight.id == sBoard.id { continue }
                    let dWalk2 = distanceMeters(sAlight.coordinate, destCoord) * 1.18
                    // Descartar si caminar a los paraderos es más largo que caminar directo al destino + margen
                    if dWalk1 + dWalk2 > max(directRawMeters * 1.35, 650) {
                        continue
                    }
                    let approxBusDist = distanceMeters(sBoard.coordinate, sAlight.coordinate) * 1.25
                    let speedMetersPerMin = max(route.averageSpeedKmh, 15.0) * 1000.0 / 60.0
                    let estMinutes = (dWalk1 + dWalk2) / 76.0 + (approxBusDist / speedMetersPerMin) + Double(abs(j - i)) * 0.32
                    if bestPairForRoute == nil || estMinutes < bestPairForRoute!.scoreMinutes {
                        bestPairForRoute = (
                            sBoard,
                            sAlight,
                            i,
                            j,
                            max(Int(round(dWalk1)), 20),
                            max(Int(round(dWalk2)), 0),
                            estMinutes
                        )
                    }
                }
            }

            guard let chosen = bestPairForRoute else { continue }

            let subSegment: (subCoords: [CLLocationCoordinate2D], boardVertex: CLLocationCoordinate2D, alightVertex: CLLocationCoordinate2D, lengthMeters: Double, isForwardValid: Bool)
            if isLoop && chosen.alightIdx == routeStops.count - 1 && fullPoly.count >= 2 {
                var boardPolyIdx = fullPoly.indices.min(by: {
                    distanceMeters(fullPoly[$0], chosen.boardStop.coordinate) < distanceMeters(fullPoly[$1], chosen.boardStop.coordinate)
                }) ?? 0
                if boardPolyIdx >= fullPoly.count - 1 && fullPoly.count > 2 {
                    boardPolyIdx = fullPoly.count - 2
                }
                let slice = Array(fullPoly[boardPolyIdx...(fullPoly.count - 1)])
                var segLen = 0.0
                if slice.count >= 2 {
                    for k in 0..<(slice.count - 1) { segLen += distanceMeters(slice[k], slice[k + 1]) }
                }
                subSegment = (slice, slice.first ?? chosen.boardStop.coordinate, slice.last ?? chosen.alightStop.coordinate, max(segLen, 120), true)
            } else {
                subSegment = extractRouteSubPolyline(
                    from: fullPoly,
                    start: chosen.boardStop.coordinate,
                    end: chosen.alightStop.coordinate
                )
            }

            let speedKmh = max(route.averageSpeedKmh, 16.0)
            let intermediateIndices: [Int]
            if chosen.boardIdx < chosen.alightIdx {
                intermediateIndices = Array((chosen.boardIdx + 1)..<chosen.alightIdx)
            } else {
                intermediateIndices = Array((chosen.alightIdx + 1)..<chosen.boardIdx).reversed()
            }
            let intermediateNames = intermediateIndices.map { routeStops[$0].shortName }

            let walk1Min = max(1, Int(round(Double(chosen.walk1Meters) / 76.0)))
            let walk2Min = chosen.walk2Meters < 45 ? 0 : max(1, Int(round(Double(chosen.walk2Meters) / 76.0)))
            let busMeters = Int(round(subSegment.lengthMeters))
            let busRideMin = max(2, Int(round((Double(busMeters) / 1000.0) / speedKmh * 60.0 + Double(intermediateNames.count) * 0.35)))

            // ETA del bus al paradero de subida (en vivo si hay unidad activa, o basado en frecuencia)
            let liveBusEta = activeBuses.first(where: {
                $0.lineNumber.localizedCaseInsensitiveContains(route.code) ||
                route.code.localizedCaseInsensitiveContains($0.lineNumber)
            })?.nextStopEtaMinutes
            let busWaitMin = liveBusEta ?? min(5, max(3, route.frequencyMinutes))

            let totalMin = walk1Min + busRideMin + walk2Min
            let totalMeters = chosen.walk1Meters + busMeters + chosen.walk2Meters

            let walk1Coords: [[Double]] = [
                [originCoord.latitude, originCoord.longitude],
                [chosen.boardStop.latitude, chosen.boardStop.longitude]
            ]
            let busCoords: [[Double]] = subSegment.subCoords.map { [$0.latitude, $0.longitude] }
            let walk2Coords: [[Double]] = chosen.walk2Meters < 35
                ? []
                : [
                    [chosen.alightStop.latitude, chosen.alightStop.longitude],
                    [destCoord.latitude, destCoord.longitude]
                ]

            ordinaryCandidates.append(
                EvaluatedRouteCandidate(
                    id: "cand-ord-\(route.id)",
                    kind: .ordinaryInService,
                    route: route,
                    routeCode: route.code,
                    routeTitle: route.title,
                    colorHex: route.colorHex,
                    totalDurationMinutes: totalMin,
                    totalDistanceMeters: totalMeters,
                    walkInitialMinutes: walk1Min,
                    walkInitialMeters: chosen.walk1Meters,
                    busWaitMinutes: busWaitMin,
                    busRideMinutes: busRideMin,
                    busRideMeters: busMeters,
                    walkFinalMinutes: walk2Min,
                    walkFinalMeters: chosen.walk2Meters,
                    boardingStop: chosen.boardStop,
                    alightingStop: chosen.alightStop,
                    intermediateStopsCount: intermediateNames.count,
                    intermediateStopNames: intermediateNames,
                    boardingPointName: chosen.boardStop.shortName,
                    alightingPointName: chosen.alightStop.shortName,
                    boardingLatitude: chosen.boardStop.latitude,
                    boardingLongitude: chosen.boardStop.longitude,
                    alightingLatitude: chosen.alightStop.latitude,
                    alightingLongitude: chosen.alightStop.longitude,
                    walkToBoardCoords: walk1Coords,
                    busTransitCoords: busCoords,
                    walkFinalCoords: walk2Coords,
                    isRecommendedPrimary: false,
                    externalRecommendationReason: nil
                )
            )
        }

        // 3. Evaluar cada Ruta Externa (El usuario puede subir y bajar en CUALQUIER punto de la vía por donde pasa la ruta)
        let extRoutes = routes.filter { $0.isExternal }
        for route in extRoutes {
            let fullPoly = route.resolvedPolylineCoordinates(using: stops)
            guard fullPoly.count >= 2 else { continue }

            let subSegment = extractRouteSubPolyline(
                from: fullPoly,
                start: originCoord,
                end: destCoord
            )
            guard subSegment.isForwardValid else { continue }

            let dWalk1 = Int(round(distanceMeters(originCoord, subSegment.boardVertex) * 1.18))
            let dWalk2 = Int(round(distanceMeters(subSegment.alightVertex, destCoord) * 1.18))

            // Solo incluir si tomar la línea externa ahorra caminata respecto a ir directo a pie
            if Double(dWalk1 + dWalk2) > max(directRawMeters * 1.30, 600) {
                continue
            }

            let walk1Min = dWalk1 < 40 ? 1 : max(1, Int(round(Double(dWalk1) / 76.0)))
            let walk2Min = dWalk2 < 45 ? 0 : max(1, Int(round(Double(dWalk2) / 76.0)))
            let busMeters = Int(round(subSegment.lengthMeters))
            let speedKmh = max(route.averageSpeedKmh, 18.0)
            let busRideMin = max(2, Int(round((Double(busMeters) / 1000.0) / speedKmh * 60.0)))
            let totalMin = walk1Min + busRideMin + walk2Min
            let totalMeters = dWalk1 + busMeters + dWalk2

            // Referencia cercana para nombrar el punto de abordaje libre en la calle
            let nearestBoardRef = stops.min(by: {
                distanceMeters($0.coordinate, subSegment.boardVertex) < distanceMeters($1.coordinate, subSegment.boardVertex)
            })
            let nearestAlightRef = stops.min(by: {
                distanceMeters($0.coordinate, subSegment.alightVertex) < distanceMeters($1.coordinate, subSegment.alightVertex)
            })

            let boardLabel = nearestBoardRef != nil
                ? "En vía de \(route.code) (alt. \(nearestBoardRef!.shortName))"
                : "Punto en ruta de \(route.code) (Abordaje libre)"
            let alightLabel = nearestAlightRef != nil && distanceMeters(nearestAlightRef!.coordinate, subSegment.alightVertex) < 350
                ? "En vía de \(route.code) (alt. \(nearestAlightRef!.shortName))"
                : "Tramo de \(route.code) más cercano a \(destination.shortName)"

            let walk1Coords: [[Double]] = [
                [originCoord.latitude, originCoord.longitude],
                [subSegment.boardVertex.latitude, subSegment.boardVertex.longitude]
            ]
            let busCoords: [[Double]] = subSegment.subCoords.map { [$0.latitude, $0.longitude] }
            let walk2Coords: [[Double]] = dWalk2 < 35
                ? []
                : [
                    [subSegment.alightVertex.latitude, subSegment.alightVertex.longitude],
                    [destCoord.latitude, destCoord.longitude]
                ]

            externalCandidates.append(
                EvaluatedRouteCandidate(
                    id: "cand-ext-\(route.id)",
                    kind: .externalFreeBoarding,
                    route: route,
                    routeCode: route.code,
                    routeTitle: route.title,
                    colorHex: route.colorHex,
                    totalDurationMinutes: totalMin,
                    totalDistanceMeters: totalMeters,
                    walkInitialMinutes: walk1Min,
                    walkInitialMeters: dWalk1,
                    busWaitMinutes: max(4, route.frequencyMinutes),
                    busRideMinutes: busRideMin,
                    busRideMeters: busMeters,
                    walkFinalMinutes: walk2Min,
                    walkFinalMeters: dWalk2,
                    boardingStop: nil,
                    alightingStop: nil,
                    intermediateStopsCount: 0,
                    intermediateStopNames: [],
                    boardingPointName: boardLabel,
                    alightingPointName: alightLabel,
                    boardingLatitude: subSegment.boardVertex.latitude,
                    boardingLongitude: subSegment.boardVertex.longitude,
                    alightingLatitude: subSegment.alightVertex.latitude,
                    alightingLongitude: subSegment.alightVertex.longitude,
                    walkToBoardCoords: walk1Coords,
                    busTransitCoords: busCoords,
                    walkFinalCoords: walk2Coords,
                    isRecommendedPrimary: false,
                    externalRecommendationReason: nil
                )
            )
        }

        let loopReboardCandidates = evaluateClosedLoopReboardCandidates(
            originCoord: originCoord,
            destCoord: destCoord,
            directRawMeters: directRawMeters,
            stops: stops,
            activeOrdRoutes: activeOrdRoutes,
            extRoutes: extRoutes,
            activeBuses: activeBuses
        )
        ordinaryCandidates.append(contentsOf: loopReboardCandidates.filter { $0.kind == .ordinaryInService })
        externalCandidates.append(contentsOf: loopReboardCandidates.filter { $0.kind == .externalFreeBoarding })

        let transferCandidates = evaluateTransferPairs(
            originCoord: originCoord,
            destCoord: destCoord,
            directRawMeters: directRawMeters,
            stops: stops,
            activeOrdRoutes: activeOrdRoutes,
            extRoutes: extRoutes,
            activeBuses: activeBuses
        )
        ordinaryCandidates.append(contentsOf: transferCandidates.filter { $0.kind == .ordinaryInService }.prefix(2))
        externalCandidates.append(contentsOf: transferCandidates.filter { $0.kind == .externalFreeBoarding }.prefix(2))

        // Ordenar cada grupo por menor duración total y menor caminata
        ordinaryCandidates.sort {
            if $0.totalDurationMinutes != $1.totalDurationMinutes {
                return $0.totalDurationMinutes < $1.totalDurationMinutes
            }
            return $0.walkTotalMeters < $1.walkTotalMeters
        }

        externalCandidates.sort {
            if $0.totalDurationMinutes != $1.totalDurationMinutes {
                return $0.totalDurationMinutes < $1.totalDurationMinutes
            }
            return $0.walkTotalMeters < $1.walkTotalMeters
        }

        // 4. Regla de Decisión Principal (Prioridad a Rutas Ordinarias salvo ausencia o exceso de umbral +10 min / > 700 m caminata)
        var finalCandidates: [EvaluatedRouteCandidate] = []
        var bannerWarning: String? = nil

        if directRawMeters <= 280 {
            // Destino a menos de ~3 cuadras: caminar directo es lo óptimo
            var primaryWalk = walkCandidate
            primaryWalk.isRecommendedPrimary = true
            finalCandidates.append(primaryWalk)
            finalCandidates.append(contentsOf: ordinaryCandidates)
            finalCandidates.append(contentsOf: externalCandidates)
        } else if let bestOrd = ordinaryCandidates.first {
            if let bestExt = externalCandidates.first {
                let timeExcess = bestOrd.totalDurationMinutes - bestExt.totalDurationMinutes
                let walkExcess = bestOrd.walkTotalMeters - bestExt.walkTotalMeters

                if timeExcess >= 10 || walkExcess > 700 {
                    // La ruta ordinaria se pasa del promedio aceptable (+10 min o >700m de caminata extra): sugerir Ruta Externa con advertencia
                    var recExt = bestExt
                    recExt.isRecommendedPrimary = true
                    let reason = timeExcess >= 10
                        ? "La ruta ordinaria más cercana demora +\(timeExcess) min adicionales."
                        : "La ruta ordinaria más cercana exige caminar \(walkExcess) m adicionales hasta su paradero."
                    recExt.externalRecommendationReason = reason
                    bannerWarning = "Se sugiere \(recExt.routeCode) (Externa): \(reason) Abordaje libre en vía, sin GPS, pago QR ni avisos de paradero."

                    finalCandidates.append(recExt)
                    finalCandidates.append(contentsOf: ordinaryCandidates)
                    finalCandidates.append(contentsOf: externalCandidates.dropFirst())
                    finalCandidates.append(walkCandidate)
                } else {
                    // Priorizar la Ruta Ordinaria más corta (con Tracking GPS, Pago QR y Notificación a 5 min)
                    var recOrd = bestOrd
                    recOrd.isRecommendedPrimary = true
                    finalCandidates.append(recOrd)
                    finalCandidates.append(contentsOf: ordinaryCandidates.dropFirst())
                    finalCandidates.append(contentsOf: externalCandidates)
                    finalCandidates.append(walkCandidate)
                }
            } else {
                var recOrd = bestOrd
                recOrd.isRecommendedPrimary = true
                finalCandidates.append(recOrd)
                finalCandidates.append(contentsOf: ordinaryCandidates.dropFirst())
                finalCandidates.append(walkCandidate)
            }
        } else if let bestExt = externalCandidates.first {
            // No hay ninguna Ruta Ordinaria en servicio (o ninguna cubre el trayecto): sugerir Ruta Externa con aviso
            var recExt = bestExt
            recExt.isRecommendedPrimary = true
            let noOrdReason = activeOrdRoutes.isEmpty
                ? "No hay Rutas Ordinarias en servicio en este momento."
                : "Ninguna Ruta Ordinaria en servicio pasa cerca de este trayecto."
            recExt.externalRecommendationReason = noOrdReason
            bannerWarning = "\(noOrdReason) Se sugiere \(recExt.routeCode) (Externa): abordaje libre en vía, sin tracking GPS ni avisos al paradero."

            finalCandidates.append(recExt)
            finalCandidates.append(contentsOf: externalCandidates.dropFirst())
            finalCandidates.append(walkCandidate)
        } else {
            var primaryWalk = walkCandidate
            primaryWalk.isRecommendedPrimary = true
            bannerWarning = "Ninguna ruta de bus conecta estos dos puntos. Se muestra el recorrido peatonal."
            finalCandidates.append(primaryWalk)
        }

        return RouteAutomationEvaluationResult(
            origin: origin,
            destination: destination,
            candidates: finalCandidates,
            primaryBannerWarning: bannerWarning,
            hasOrdinaryInService: !activeOrdRoutes.isEmpty
        )
    }

    private struct TransferAnchor {
        let coord: CLLocationCoordinate2D
        let label: String
        let stop: TacnaDestinationPlace?
    }

    private static func buildAnchorsForRoute(
        _ route: TacnaOfficialRouteCatalogItem,
        stops: [TacnaDestinationPlace]
    ) -> ([TransferAnchor], [CLLocationCoordinate2D]) {
        let fullPoly = route.resolvedPolylineCoordinates(using: stops)
        if route.isOrdinary {
            let routeStops = route.resolvedStops(using: stops)
            return (routeStops.map { TransferAnchor(coord: $0.coordinate, label: $0.shortName, stop: $0) }, fullPoly)
        }
        guard fullPoly.count >= 2 else { return ([], fullPoly) }
        var sampled: [TransferAnchor] = []
        var lastAdded: CLLocationCoordinate2D? = nil
        for (idx, pt) in fullPoly.enumerated() {
            let isEdge = idx == 0 || idx == fullPoly.count - 1
            if isEdge || lastAdded == nil || distanceMeters(lastAdded!, pt) >= 140.0 {
                let nearest = stops.min { distanceMeters($0.coordinate, pt) < distanceMeters($1.coordinate, pt) }
                let label: String
                if let nearest, distanceMeters(nearest.coordinate, pt) < 280.0 {
                    label = "alt. \(nearest.shortName)"
                } else {
                    label = "vía \(route.code)"
                }
                sampled.append(TransferAnchor(coord: pt, label: label, stop: nil))
                lastAdded = pt
            }
        }
        return (sampled, fullPoly)
    }

    private static func evaluateTransferPairs(
        originCoord: CLLocationCoordinate2D,
        destCoord: CLLocationCoordinate2D,
        directRawMeters: Double,
        stops: [TacnaDestinationPlace],
        activeOrdRoutes: [TacnaOfficialRouteCatalogItem],
        extRoutes: [TacnaOfficialRouteCatalogItem],
        activeBuses: [ActiveBusModel]
    ) -> [EvaluatedRouteCandidate] {
        guard directRawMeters > 450.0 else { return [] }
        let pool = activeOrdRoutes + extRoutes
        guard pool.count >= 2 else { return [] }

        let routeData: [(route: TacnaOfficialRouteCatalogItem, anchors: [TransferAnchor], poly: [CLLocationCoordinate2D])] = pool.compactMap { r in
            let (anchors, poly) = buildAnchorsForRoute(r, stops: stops)
            return anchors.count >= 2 ? (r, anchors, poly) : nil
        }
        guard routeData.count >= 2 else { return [] }

        let maxWalkLimit = max(directRawMeters * 0.95, 700.0)
        let maxSingleWalk = max(directRawMeters * 0.72, 550.0)
        var transferCandidates: [EvaluatedRouteCandidate] = []

        for (r1, anchors1, poly1) in routeData {
            let boardOptions = anchors1.enumerated().compactMap { (idx, a) -> (idx: Int, walk1: Double)? in
                let w = distanceMeters(originCoord, a.coord) * 1.18
                return w <= maxSingleWalk ? (idx, w) : nil
            }
            guard !boardOptions.isEmpty else { continue }

            for (r2, anchors2, poly2) in routeData where r1.id != r2.id {
                let alightOptions = anchors2.enumerated().compactMap { (idx, a) -> (idx: Int, walk2: Double)? in
                    let w = distanceMeters(a.coord, destCoord) * 1.18
                    return w <= maxSingleWalk ? (idx, w) : nil
                }
                guard !alightOptions.isEmpty else { continue }

                var bestScore = Double.greatestFiniteMagnitude
                var bestBoardIdx = -1
                var bestT1Idx = -1
                var bestT2Idx = -1
                var bestAlightIdx = -1
                var bestWalk1 = 0.0
                var bestWalkT = 0.0
                var bestWalk2 = 0.0

                let speed1Mpm = max(r1.averageSpeedKmh, 16.0) * 1000.0 / 60.0
                let speed2Mpm = max(r2.averageSpeedKmh, 16.0) * 1000.0 / 60.0

                for t1Idx in anchors1.indices {
                    let t1 = anchors1[t1Idx]
                    for t2Idx in anchors2.indices {
                        let t2 = anchors2[t2Idx]
                        let dTransferRaw = distanceMeters(t1.coord, t2.coord)
                        if dTransferRaw > 280.0 { continue }
                        let dTransferWalk = dTransferRaw < 25.0 ? 0.0 : dTransferRaw * 1.18

                        guard let bBest = boardOptions
                            .filter({ $0.idx < t1Idx && distanceMeters(anchors1[$0.idx].coord, t1.coord) >= 150.0 })
                            .min(by: { lhs, rhs in
                                let lScore = (lhs.walk1 / 76.0) + (distanceMeters(anchors1[lhs.idx].coord, t1.coord) * 1.25 / speed1Mpm)
                                let rScore = (rhs.walk1 / 76.0) + (distanceMeters(anchors1[rhs.idx].coord, t1.coord) * 1.25 / speed1Mpm)
                                return lScore < rScore
                            }) else { continue }

                        guard let aBest = alightOptions
                            .filter({ $0.idx > t2Idx && distanceMeters(t2.coord, anchors2[$0.idx].coord) >= 150.0 })
                            .min(by: { lhs, rhs in
                                let lScore = (lhs.walk2 / 76.0) + (distanceMeters(t2.coord, anchors2[lhs.idx].coord) * 1.25 / speed2Mpm)
                                let rScore = (rhs.walk2 / 76.0) + (distanceMeters(t2.coord, anchors2[rhs.idx].coord) * 1.25 / speed2Mpm)
                                return lScore < rScore
                            }) else { continue }

                        let totalWalk = bBest.walk1 + dTransferWalk + aBest.walk2
                        if totalWalk > maxWalkLimit { continue }

                        let dBus1 = distanceMeters(anchors1[bBest.idx].coord, t1.coord) * 1.25
                        let dBus2 = distanceMeters(t2.coord, anchors2[aBest.idx].coord) * 1.25
                        let score = (totalWalk / 76.0) + (dBus1 / speed1Mpm) + (dBus2 / speed2Mpm) + 4.0

                        if score < bestScore {
                            bestScore = score
                            bestBoardIdx = bBest.idx
                            bestT1Idx = t1Idx
                            bestT2Idx = t2Idx
                            bestAlightIdx = aBest.idx
                            bestWalk1 = bBest.walk1
                            bestWalkT = dTransferWalk
                            bestWalk2 = aBest.walk2
                        }
                    }
                }

                guard bestBoardIdx >= 0, bestT1Idx >= 0, bestT2Idx >= 0, bestAlightIdx >= 0 else { continue }

                let boardAnchor = anchors1[bestBoardIdx]
                let t1Anchor = anchors1[bestT1Idx]
                let t2Anchor = anchors2[bestT2Idx]
                let alightAnchor = anchors2[bestAlightIdx]

                let seg1 = extractRouteSubPolyline(from: poly1, start: boardAnchor.coord, end: t1Anchor.coord)
                let seg2 = extractRouteSubPolyline(from: poly2, start: t2Anchor.coord, end: alightAnchor.coord)

                let walk1M = max(Int(round(bestWalk1)), 20)
                let walkTM = bestWalkT < 25.0 ? 0 : Int(round(bestWalkT))
                let walk2M = max(Int(round(bestWalk2)), 0)

                let walk1Min = max(1, Int(round(Double(walk1M) / 76.0)))
                let walkTMin = walkTM < 35 ? 0 : max(1, Int(round(Double(walkTM) / 76.0)))
                let walk2Min = walk2M < 45 ? 0 : max(1, Int(round(Double(walk2M) / 76.0)))

                let bus1Meters = Int(round(seg1.lengthMeters))
                let bus2Meters = Int(round(seg2.lengthMeters))
                let bus1Min = max(2, Int(round((Double(bus1Meters) / 1000.0) / max(r1.averageSpeedKmh, 16.0) * 60.0)))
                let bus2Min = max(2, Int(round((Double(bus2Meters) / 1000.0) / max(r2.averageSpeedKmh, 16.0) * 60.0)))
                let transferWaitMin = 4
                let totalMin = walk1Min + bus1Min + walkTMin + transferWaitMin + bus2Min + walk2Min
                let totalMeters = walk1M + bus1Meters + walkTM + bus2Meters + walk2M

                let bothOrdinary = r1.isOrdinary && r2.isOrdinary
                let liveEta = activeBuses.first {
                    $0.lineNumber.localizedCaseInsensitiveContains(r1.code) ||
                    r1.code.localizedCaseInsensitiveContains($0.lineNumber)
                }?.nextStopEtaMinutes
                let busWaitMin = liveEta ?? min(5, max(3, r1.frequencyMinutes))

                let transferLabel = t1Anchor.label == t2Anchor.label
                    ? t1Anchor.label
                    : "\(t1Anchor.label) / \(t2Anchor.label)"

                transferCandidates.append(
                    EvaluatedRouteCandidate(
                        id: "cand-transfer-\(r1.id)-\(r2.id)",
                        kind: bothOrdinary ? .ordinaryInService : .externalFreeBoarding,
                        route: r1,
                        routeCode: "\(r1.code) → \(r2.code)",
                        routeTitle: "Transbordo en \(transferLabel) (2 rutas)",
                        colorHex: r1.colorHex,
                        totalDurationMinutes: totalMin,
                        totalDistanceMeters: totalMeters,
                        walkInitialMinutes: walk1Min,
                        walkInitialMeters: walk1M,
                        busWaitMinutes: busWaitMin,
                        busRideMinutes: bus1Min + bus2Min + walkTMin + transferWaitMin,
                        busRideMeters: bus1Meters + bus2Meters,
                        walkFinalMinutes: walk2Min,
                        walkFinalMeters: walk2M,
                        boardingStop: boardAnchor.stop,
                        alightingStop: alightAnchor.stop,
                        intermediateStopsCount: 0,
                        intermediateStopNames: [],
                        boardingPointName: boardAnchor.label,
                        alightingPointName: alightAnchor.label,
                        boardingLatitude: boardAnchor.coord.latitude,
                        boardingLongitude: boardAnchor.coord.longitude,
                        alightingLatitude: alightAnchor.coord.latitude,
                        alightingLongitude: alightAnchor.coord.longitude,
                        walkToBoardCoords: [
                            [originCoord.latitude, originCoord.longitude],
                            [boardAnchor.coord.latitude, boardAnchor.coord.longitude]
                        ],
                        busTransitCoords: seg1.subCoords.map { [$0.latitude, $0.longitude] },
                        walkFinalCoords: walk2M < 35 ? [] : [
                            [alightAnchor.coord.latitude, alightAnchor.coord.longitude],
                            [destCoord.latitude, destCoord.longitude]
                        ],
                        isRecommendedPrimary: false,
                        externalRecommendationReason: nil,
                        isTransfer: true,
                        secondRouteCode: r2.code,
                        secondRouteColorHex: r2.colorHex,
                        transferPointName: transferLabel,
                        transferLatitude: t1Anchor.coord.latitude,
                        transferLongitude: t1Anchor.coord.longitude,
                        transferWalkMeters: walkTM,
                        firstBusRideMinutes: bus1Min,
                        secondBusRideMinutes: bus2Min,
                        secondBusTransitCoords: seg2.subCoords.map { [$0.latitude, $0.longitude] },
                        transferWalkCoords: walkTM < 25 ? [] : [
                            [t1Anchor.coord.latitude, t1Anchor.coord.longitude],
                            [t2Anchor.coord.latitude, t2Anchor.coord.longitude]
                        ]
                    )
                )
            }
        }

        return transferCandidates.sorted {
            if $0.totalDurationMinutes != $1.totalDurationMinutes {
                return $0.totalDurationMinutes < $1.totalDurationMinutes
            }
            return $0.walkTotalMeters < $1.walkTotalMeters
        }
    }

    private static func evaluateClosedLoopReboardCandidates(
        originCoord: CLLocationCoordinate2D,
        destCoord: CLLocationCoordinate2D,
        directRawMeters: Double,
        stops: [TacnaDestinationPlace],
        activeOrdRoutes: [TacnaOfficialRouteCatalogItem],
        extRoutes: [TacnaOfficialRouteCatalogItem],
        activeBuses: [ActiveBusModel]
    ) -> [EvaluatedRouteCandidate] {
        var result: [EvaluatedRouteCandidate] = []
        for route in (activeOrdRoutes + extRoutes) {
            let routeStops = route.resolvedStops(using: stops)
            guard routeStops.count >= 2 else { continue }
            let fullPoly = route.resolvedPolylineCoordinates(using: stops)
            let isLoop = route.isClosedLoop ||
                (routeStops.count >= 3 && routeStops.first?.id == routeStops.last?.id) ||
                (fullPoly.count >= 4 && distanceMeters(fullPoly.first!, fullPoly.last!) <= 80.0)
            guard isLoop, let terminalStop = routeStops.first else { continue }

            let endCoord = fullPoly.last ?? terminalStop.coordinate
            let startCoord = fullPoly.first ?? terminalStop.coordinate
            let speedKmh = max(route.averageSpeedKmh, 16.0)
            let speedMpm = speedKmh * 1000.0 / 60.0

            var bestI = -1
            var bestJ = -1
            var bestWalk1 = 0
            var bestWalk2 = 0
            var bestScore = Double.greatestFiniteMagnitude

            for i in 1..<routeStops.count {
                let sBoard = routeStops[i]
                if sBoard.id == terminalStop.id { continue }
                let dWalk1 = distanceMeters(originCoord, sBoard.coordinate) * 1.18
                for j in 1..<i {
                    let sAlight = routeStops[j]
                    if sAlight.id == terminalStop.id { continue }
                    let dWalk2 = distanceMeters(sAlight.coordinate, destCoord) * 1.18
                    if dWalk1 + dWalk2 > max(directRawMeters * 1.35, 650.0) { continue }

                    let dBus1 = distanceMeters(sBoard.coordinate, endCoord) * 1.25
                    let dBus2 = distanceMeters(startCoord, sAlight.coordinate) * 1.25
                    let estMin = (dWalk1 + dWalk2) / 76.0 + (dBus1 + dBus2) / speedMpm + 4.0
                    if estMin < bestScore {
                        bestScore = estMin
                        bestI = i
                        bestJ = j
                        bestWalk1 = max(Int(round(dWalk1)), 20)
                        bestWalk2 = max(Int(round(dWalk2)), 0)
                    }
                }
            }

            guard bestI >= 0, bestJ >= 0 else { continue }

            let boardStop = routeStops[bestI]
            let alightStop = routeStops[bestJ]

            let seg1Coords: [CLLocationCoordinate2D]
            let seg2Coords: [CLLocationCoordinate2D]
            let seg1Len: Double
            let seg2Len: Double

            if fullPoly.count >= 2 {
                var boardPolyIdx = fullPoly.indices.min(by: {
                    distanceMeters(fullPoly[$0], boardStop.coordinate) < distanceMeters(fullPoly[$1], boardStop.coordinate)
                }) ?? 0
                if boardPolyIdx == fullPoly.count - 1 && fullPoly.count > 2 {
                    boardPolyIdx = fullPoly.count - 2
                }
                var alightPolyIdx = fullPoly.indices.min(by: {
                    distanceMeters(fullPoly[$0], alightStop.coordinate) < distanceMeters(fullPoly[$1], alightStop.coordinate)
                }) ?? 0
                if alightPolyIdx == 0 && fullPoly.count > 2 {
                    alightPolyIdx = 1
                }
                seg1Coords = Array(fullPoly[boardPolyIdx...(fullPoly.count - 1)])
                seg2Coords = Array(fullPoly[0...alightPolyIdx])
                var d1 = 0.0
                if seg1Coords.count >= 2 {
                    for k in 0..<(seg1Coords.count - 1) { d1 += distanceMeters(seg1Coords[k], seg1Coords[k + 1]) }
                }
                var d2 = 0.0
                if seg2Coords.count >= 2 {
                    for k in 0..<(seg2Coords.count - 1) { d2 += distanceMeters(seg2Coords[k], seg2Coords[k + 1]) }
                }
                seg1Len = max(d1, max(distanceMeters(boardStop.coordinate, endCoord) * 1.25, 120.0))
                seg2Len = max(d2, max(distanceMeters(startCoord, alightStop.coordinate) * 1.25, 120.0))
            } else {
                seg1Coords = [boardStop.coordinate, endCoord]
                seg2Coords = [startCoord, alightStop.coordinate]
                seg1Len = max(distanceMeters(boardStop.coordinate, endCoord) * 1.25, 120.0)
                seg2Len = max(distanceMeters(startCoord, alightStop.coordinate) * 1.25, 120.0)
            }

            let walk1Min = max(1, Int(round(Double(bestWalk1) / 76.0)))
            let walk2Min = bestWalk2 < 45 ? 0 : max(1, Int(round(Double(bestWalk2) / 76.0)))
            let bus1Meters = Int(round(seg1Len))
            let bus2Meters = Int(round(seg2Len))
            let bus1Min = max(2, Int(round((Double(bus1Meters) / 1000.0) / speedKmh * 60.0)))
            let bus2Min = max(2, Int(round((Double(bus2Meters) / 1000.0) / speedKmh * 60.0)))
            let reboardWaitMin = 4
            let totalMin = walk1Min + bus1Min + reboardWaitMin + bus2Min + walk2Min
            let totalMeters = bestWalk1 + bus1Meters + bus2Meters + bestWalk2

            let liveEta = activeBuses.first {
                $0.lineNumber.localizedCaseInsensitiveContains(route.code) ||
                route.code.localizedCaseInsensitiveContains($0.lineNumber)
            }?.nextStopEtaMinutes
            let busWaitMin = liveEta ?? min(5, max(3, route.frequencyMinutes))

            result.append(
                EvaluatedRouteCandidate(
                    id: "cand-loop-\(route.id)",
                    kind: route.isOrdinary ? .ordinaryInService : .externalFreeBoarding,
                    route: route,
                    routeCode: "\(route.code) ↻ \(route.code)",
                    routeTitle: "Fin de vuelta en \(terminalStop.shortName) (bajas y reabordas)",
                    colorHex: route.colorHex,
                    totalDurationMinutes: totalMin,
                    totalDistanceMeters: totalMeters,
                    walkInitialMinutes: walk1Min,
                    walkInitialMeters: bestWalk1,
                    busWaitMinutes: busWaitMin,
                    busRideMinutes: bus1Min + bus2Min + reboardWaitMin,
                    busRideMeters: bus1Meters + bus2Meters,
                    walkFinalMinutes: walk2Min,
                    walkFinalMeters: bestWalk2,
                    boardingStop: boardStop,
                    alightingStop: alightStop,
                    intermediateStopsCount: 0,
                    intermediateStopNames: [],
                    boardingPointName: boardStop.shortName,
                    alightingPointName: alightStop.shortName,
                    boardingLatitude: boardStop.latitude,
                    boardingLongitude: boardStop.longitude,
                    alightingLatitude: alightStop.latitude,
                    alightingLongitude: alightStop.longitude,
                    walkToBoardCoords: [
                        [originCoord.latitude, originCoord.longitude],
                        [boardStop.latitude, boardStop.longitude]
                    ],
                    busTransitCoords: seg1Coords.map { [$0.latitude, $0.longitude] },
                    walkFinalCoords: bestWalk2 < 35 ? [] : [
                        [alightStop.latitude, alightStop.longitude],
                        [destCoord.latitude, destCoord.longitude]
                    ],
                    isRecommendedPrimary: false,
                    externalRecommendationReason: nil,
                    isTransfer: true,
                    secondRouteCode: route.code,
                    secondRouteColorHex: route.colorHex,
                    transferPointName: "\(terminalStop.shortName) (Fin de vuelta · Nuevo pasaje)",
                    transferLatitude: terminalStop.latitude,
                    transferLongitude: terminalStop.longitude,
                    transferWalkMeters: 0,
                    firstBusRideMinutes: bus1Min,
                    secondBusRideMinutes: bus2Min,
                    secondBusTransitCoords: seg2Coords.map { [$0.latitude, $0.longitude] },
                    transferWalkCoords: []
                )
            )
        }
        return result
    }
}

// MARK: - Motor Nativo de Alineación a Calles en Apple Maps (MKDirections)
enum NativeStreetRouter {
    /// Calcula la polilínea exacta alineada a las calles de Tacna entre una secuencia de puntos usando MKDirections nativo.
    static func alignPolylineToStreets(
        waypoints: [CLLocationCoordinate2D],
        transportType: MKDirectionsTransportType = .automobile
    ) async -> [CLLocationCoordinate2D] {
        guard waypoints.count >= 2 else { return waypoints }
        var alignedResult: [CLLocationCoordinate2D] = []

        for idx in 0..<(waypoints.count - 1) {
            let start = waypoints[idx]
            let end = waypoints[idx + 1]

            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
            request.transportType = transportType

            do {
                let response = try await MKDirections(request: request).calculate()
                if let route = response.routes.first {
                    let count = route.polyline.pointCount
                    if count >= 2 {
                        var segmentCoords = Array(repeating: kCLLocationCoordinate2DInvalid, count: count)
                        route.polyline.getCoordinates(&segmentCoords, range: NSRange(location: 0, length: count))
                        for coord in segmentCoords where CLLocationCoordinate2DIsValid(coord) {
                            if let last = alignedResult.last,
                               abs(last.latitude - coord.latitude) < 0.000005,
                               abs(last.longitude - coord.longitude) < 0.000005 {
                                continue
                            }
                            alignedResult.append(coord)
                        }
                        continue
                    }
                }
            } catch {
                // Fallback al tramo directo si MKDirections no responde
            }

            if alignedResult.isEmpty {
                alignedResult.append(start)
            }
            alignedResult.append(end)
        }

        return alignedResult.count >= 2 ? alignedResult : waypoints
    }
}

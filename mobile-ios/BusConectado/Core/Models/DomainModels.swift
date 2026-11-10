import Foundation
import CoreLocation

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
}

// MARK: - Perfil de Usuario Autenticado
struct UserAuth: Codable, Identifiable, Equatable {
    let id: String
    let phone: String
    var name: String?
    var role: String
    var pointsBalance: Int
    var isNewUser: Bool
    var studentVerification: StudentVerificationInfo?

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

// MARK: - Modelo de Paradero / Lugar Real de Tacna
struct TacnaDestinationPlace: Identifiable, Equatable {
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

    /// Icono visual estandarizado: autobús para paraderos oficiales, destello para propuestas, marcador para puntos del mapa
    var displayIconName: String {
        if isOfficialParadero {
            return "bus.fill"
        } else if category.isProposedModernization {
            return "sparkles"
        } else {
            return "mappin.and.ellipse"
        }
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
            subtitle: subtitle.isEmpty ? "Punto seleccionado en el mapa de Tacna" : subtitle,
            category: .mapCustomPlace,
            routesPassing: ["Ruta 14", "Ruta 10B"],
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
            subtitle: "Av. Bolognesi / Calle Mendoza • Zona Comercial",
            category: .marketsCommercial,
            routesPassing: ["Ruta 14", "Ruta 10B", "Ruta 101"],
            iconName: "storefront.fill",
            iconColorHex: "#2563EB",
            latitude: -18.0132,
            longitude: -70.2505,
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
            subtitle: "Av. 2 de Mayo • Cercado de Tacna",
            category: .marketsCommercial,
            routesPassing: ["Ruta 14", "Ruta 10B", "Ruta 203"],
            iconName: "storefront.fill",
            iconColorHex: "#2563EB",
            latitude: -18.0118,
            longitude: -70.2508,
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
            subtitle: "Av. Saucini / Hipólito Unanue • Plataforma Mayorista",
            category: .marketsCommercial,
            routesPassing: ["Ruta 14", "Ruta 101", "Ruta A"],
            iconName: "cart.fill",
            iconColorHex: "#2563EB",
            latitude: -18.0055,
            longitude: -70.2602,
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
            subtitle: "Av. Municipal / La Cultura • Gregorio Albarracín",
            category: .marketsCommercial,
            routesPassing: ["Ruta 14", "Ruta 203"],
            iconName: "storefront.fill",
            iconColorHex: "#2563EB",
            latitude: -18.0465,
            longitude: -70.2520,
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
            subtitle: "Av. Pinto / Tarata / Industrial • Feria Comercial",
            category: .marketsCommercial,
            routesPassing: ["Ruta 10B", "Ruta 101"],
            iconName: "bag.fill",
            iconColorHex: "#2563EB",
            latitude: -18.0038,
            longitude: -70.2492,
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
            subtitle: "Asoc. Santa Rosa • Distrito Gregorio Albarracín",
            category: .marketsCommercial,
            routesPassing: ["Ruta 14", "Ruta 203"],
            iconName: "storefront.fill",
            iconColorHex: "#2563EB",
            latitude: -18.0530,
            longitude: -70.2485,
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
            subtitle: "Av. Industrial / Prol. Unanue • Parque Industrial",
            category: .marketsCommercial,
            routesPassing: ["Ruta 101"],
            iconName: "fish.fill",
            iconColorHex: "#2563EB",
            latitude: -17.9960,
            longitude: -70.2592,
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
            name: "Plaza Vea",
            shortName: "Plaza Vea",
            subtitle: "Av. Cusco / Av. Miguel Grau • Cercado",
            category: .marketsCommercial,
            routesPassing: ["Ruta 14", "Ruta 10B", "Ruta A"],
            iconName: "cart.fill",
            iconColorHex: "#2563EB",
            latitude: -18.0175,
            longitude: -70.2525,
            routeCase: .busRoute14,
            totalDurationMinutes: 7,
            secondaryDurationMinutes: 11,
            walkingDirectMinutes: 10,
            distanceLabel: "750 m",
            walkInitialMinutes: 2,
            busRideMinutes: 5,
            walkFinalMinutes: 0,
            boardingStopName: "Tacna Centro",
            alightingStopName: "Plaza Vea",
            intermediateStopName: nil,
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-cc-tupac-amaru",
            name: "Centro Comercial Túpac Amaru",
            shortName: "C.C. Túpac Amaru",
            subtitle: "Av. Coronel Mendoza / Calle Pinto • Zona Comercial",
            category: .marketsCommercial,
            routesPassing: ["Ruta 14", "Ruta 10B", "Ruta 101"],
            iconName: "bag.circle.fill",
            iconColorHex: "#2563EB",
            latitude: -18.0080,
            longitude: -70.2522,
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
            subtitle: "Av. Miguel Grau / Av. Bolognesi • Centro Histórico",
            category: .plazasCentral,
            routesPassing: ["Ruta 14", "Ruta 10B", "Ruta A"],
            iconName: "tram.fill",
            iconColorHex: "#2563EB",
            latitude: -18.0163,
            longitude: -70.2548,
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
            subtitle: "Calle San Martín / Calle Zela • Centro Histórico",
            category: .plazasCentral,
            routesPassing: ["Ruta 10B", "Ruta A"],
            iconName: "leaf.fill",
            iconColorHex: "#2563EB",
            latitude: -18.0115,
            longitude: -70.2485,
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
            subtitle: "Av. Municipal • Distrito Gregorio Albarracín",
            category: .plazasCentral,
            routesPassing: ["Ruta 14", "Ruta 203"],
            iconName: "mappin.circle.fill",
            iconColorHex: "#2563EB",
            latitude: -18.0410,
            longitude: -70.2505,
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
            subtitle: "Av. Miraflores / Calle Arica • Cercado de Tacna",
            category: .plazasCentral,
            routesPassing: ["Ruta 14", "Ruta 10B", "Ruta 203"],
            iconName: "mappin.circle.fill",
            iconColorHex: "#2563EB",
            latitude: -18.0210,
            longitude: -70.2510,
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
            subtitle: "Av. Coronel Mendoza / Calle Vigil • Cercado",
            category: .plazasCentral,
            routesPassing: ["Ruta 14", "Ruta 10B", "Ruta 101"],
            iconName: "leaf.fill",
            iconColorHex: "#2563EB",
            latitude: -18.0088,
            longitude: -70.2515,
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
            subtitle: "Alto Bolognesi / Basadre y Forero • Cercado",
            category: .plazasCentral,
            routesPassing: ["Ruta 10B"],
            iconName: "airplane.circle.fill",
            iconColorHex: "#2563EB",
            latitude: -18.0145,
            longitude: -70.2420,
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
            subtitle: "Av. Internacional / Daniel Alcides Carrión • Ciudad Nueva",
            category: .plazasCentral,
            routesPassing: ["Ruta 14", "Ruta 101"],
            iconName: "mappin.circle.fill",
            iconColorHex: "#2563EB",
            latitude: -17.9890,
            longitude: -70.2425,
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
            subtitle: "Av. Augusto B. Leguía / Calle Arias Aragüez",
            category: .plazasCentral,
            routesPassing: ["Ruta 14", "Ruta 10B", "Ruta 101", "Ruta A"],
            iconName: "drop.fill",
            iconColorHex: "#2563EB",
            latitude: -18.0095,
            longitude: -70.2555,
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
            subtitle: "Av. San Martín / Paseo Cívico • Corazón de Tacna",
            category: .plazasCentral,
            routesPassing: ["Ruta 14", "Ruta 10B", "Ruta A"],
            iconName: "building.2.fill",
            iconColorHex: "#2563EB",
            latitude: -18.0138,
            longitude: -70.2512,
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
            subtitle: "Calle Vigil / San Martín y Bolognesi • Cercado",
            category: .plazasCentral,
            routesPassing: ["Ruta 14", "Ruta 10B", "Ruta 101"],
            iconName: "mappin.and.ellipse",
            iconColorHex: "#2563EB",
            latitude: -18.0128,
            longitude: -70.2508,
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
            shortName: "UNJBG (Ciudad Universitaria)",
            subtitle: "Av. Miraflores S/N • Paradero Universitario Principal",
            category: .institutionsTerminals,
            routesPassing: ["Ruta 14", "Ruta 10B", "Ruta 203"],
            iconName: "graduationcap.fill",
            iconColorHex: "#2563EB",
            latitude: -18.0255,
            longitude: -70.2505,
            routeCase: .busRoute14,
            totalDurationMinutes: 14,
            secondaryDurationMinutes: 19,
            walkingDirectMinutes: 28,
            distanceLabel: "2.4 km",
            walkInitialMinutes: 2,
            busRideMinutes: 12,
            walkFinalMinutes: 0,
            boardingStopName: "Mercado 2 de Mayo",
            alightingStopName: "UNJBG (Ciudad Universitaria)",
            intermediateStopName: "Plaza del Maestro",
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-terminal-terrestre",
            name: "Terminal Terrestre",
            shortName: "Terminal Terrestre",
            subtitle: "Prol. Hipólito Unanue • Terminal Manuel A. Odría",
            category: .institutionsTerminals,
            routesPassing: ["Ruta 14", "Ruta 101"],
            iconName: "bus.doubledecker.fill",
            iconColorHex: "#2563EB",
            latitude: -18.0035,
            longitude: -70.2625,
            routeCase: .busRoute101,
            totalDurationMinutes: 13,
            secondaryDurationMinutes: 18,
            walkingDirectMinutes: 24,
            distanceLabel: "1.9 km",
            walkInitialMinutes: 2,
            busRideMinutes: 11,
            walkFinalMinutes: 0,
            boardingStopName: "Pasaje Vigil",
            alightingStopName: "Terminal Terrestre",
            intermediateStopName: "Mercado Miguel Grau",
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "stop-terminal-bolognesi",
            name: "Terminal Bolognesi",
            shortName: "Terminal Bolognesi",
            subtitle: "Prol. Bolognesi / Coronel Mendoza • Terminal Nacional",
            category: .institutionsTerminals,
            routesPassing: ["Ruta 14", "Ruta 101"],
            iconName: "bus.fill",
            iconColorHex: "#2563EB",
            latitude: -18.0040,
            longitude: -70.2605,
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
            subtitle: "Av. Gregorio Albarracín 526 / Hipólito Unanue",
            category: .institutionsTerminals,
            routesPassing: ["Ruta 14", "Ruta 10B"],
            iconName: "building.columns.fill",
            iconColorHex: "#2563EB",
            latitude: -18.0165,
            longitude: -70.2525,
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
            iconName: "scalemass.fill",
            iconColorHex: "#2563EB",
            latitude: -18.0110,
            longitude: -70.2525,
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
            subtitle: "Av. Arias Aragüez / Olga Grohmann • Estadio",
            category: .institutionsTerminals,
            routesPassing: ["Ruta 14", "Ruta 10B", "Ruta 101"],
            iconName: "sportscourt.fill",
            iconColorHex: "#2563EB",
            latitude: -18.0065,
            longitude: -70.2530,
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
            subtitle: "Av. Pinto / Av. Coronel Mendoza • Punto Clave",
            category: .institutionsTerminals,
            routesPassing: ["Ruta 14", "Ruta 101"],
            iconName: "antenna.radiowaves.left.and.right",
            iconColorHex: "#2563EB",
            latitude: -18.0075,
            longitude: -70.2525,
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
            subtitle: "Av. Bolognesi 300 / Billinghurst • Centro Histórico",
            category: .institutionsTerminals,
            routesPassing: ["Ruta 14", "Ruta 10B", "Ruta A"],
            iconName: "building.fill",
            iconColorHex: "#2563EB",
            latitude: -18.0115,
            longitude: -70.2475,
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
            subtitle: "Calle Blondell • Accesibilidad Prioritaria Adulto Mayor",
            category: .proposedHospitals,
            routesPassing: ["Ruta 10B", "Ruta 14"],
            iconName: "cross.case.fill",
            iconColorHex: "#F59E0B",
            latitude: -18.0100,
            longitude: -70.2435,
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
            iconName: "cross.case.fill",
            iconColorHex: "#F59E0B",
            latitude: -17.9575,
            longitude: -70.1985,
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
            name: "Principales Postas Médicas (C.S. San Francisco)",
            shortName: "Postas Médicas / C.S.",
            subtitle: "Red de Atención Primaria • Gregorio Albarracín",
            category: .proposedHospitals,
            routesPassing: ["Ruta 14", "Ruta 203"],
            iconName: "heart.text.square.fill",
            iconColorHex: "#F59E0B",
            latitude: -18.0420,
            longitude: -70.2515,
            routeCase: .busRoute203,
            totalDurationMinutes: 18,
            secondaryDurationMinutes: 24,
            walkingDirectMinutes: 40,
            distanceLabel: "3.3 km",
            walkInitialMinutes: 2,
            busRideMinutes: 16,
            walkFinalMinutes: 0,
            boardingStopName: "Mercado 2 de Mayo",
            alightingStopName: "Posta Médica San Francisco",
            intermediateStopName: "UNJBG",
            statusNote: "Propuesta Oficialización: Red de Postas Médicas"
        ),

        // B. Zonas de Crecimiento Urbano (Cono Sur y Cono Norte)
        TacnaDestinationPlace(
            id: "prop-vinani-albarracin",
            name: "Asociaciones de Vivienda Viñani (Gregorio Albarracín)",
            shortName: "Paradero Formal Viñani",
            subtitle: "Cono Sur • Punto de Parada Fijo (Cero Paradas Informales)",
            category: .proposedUrbanGrowth,
            routesPassing: ["Ruta 14", "Ruta 203"],
            iconName: "house.and.flag.fill",
            iconColorHex: "#F59E0B",
            latitude: -18.0620,
            longitude: -70.2470,
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
            name: "Asociaciones de Vivienda Ciudad Nueva (Cono Norte)",
            shortName: "Paradero Ciudad Nueva",
            subtitle: "Av. Juan Moore / Internacional • Punto Fijo Formalizado",
            category: .proposedUrbanGrowth,
            routesPassing: ["Ruta 14", "Ruta 101"],
            iconName: "building.2.crop.circle.fill",
            iconColorHex: "#F59E0B",
            latitude: -17.9820,
            longitude: -70.2350,
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
            name: "Universidad Privada de Tacna (UPT) y Colegios",
            shortName: "UPT (Campus Capanique)",
            subtitle: "Av. Jorge Basadre Grohmann s/n • Geofencing Universitario",
            category: .proposedEducation,
            routesPassing: ["Ruta 10B"],
            iconName: "graduationcap.circle.fill",
            iconColorHex: "#F59E0B",
            latitude: -18.0045,
            longitude: -70.2260,
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
            subtitle: "Panamericana Sur Km 1335 • Tótem de Rutas y ETA en Vivo",
            category: .proposedTouristBorder,
            routesPassing: ["Corredor Turístico-Fronterizo"],
            iconName: "globe.americas.fill",
            iconColorHex: "#F59E0B",
            latitude: -18.3050,
            longitude: -70.3150,
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

// MARK: - Catálogo Oficial de las Rutas Principales de Tacna (Sistema de 33 Rutas Urbanas)
struct TacnaOfficialRouteCatalogItem: Identifiable, Equatable {
    let id: String
    let code: String
    let title: String
    let corridorSummary: String
    let frequencyLabel: String
    let scheduleLabel: String
    let colorHex: String
    let keyStopIds: [String]

    var resolvedStops: [TacnaDestinationPlace] {
        keyStopIds.compactMap { stopId in
            TacnaDestinationPlace.catalog.first(where: { $0.id == stopId })
        }
    }

    static let officialRoutes: [TacnaOfficialRouteCatalogItem] = [
        TacnaOfficialRouteCatalogItem(
            id: "tacna-ruta-14",
            code: "RUTA 14",
            title: "Eje Troncal Cono Norte – Centro – UNJBG – Cono Sur",
            corridorSummary: "Ciudad Nueva ⇄ C.C. Túpac Amaru ⇄ Mercado 2 de Mayo ⇄ Mercado Central ⇄ UNJBG ⇄ Gregorio Albarracín (Viñani)",
            frequencyLabel: "Cada 5 min",
            scheduleLabel: "05:30 - 22:30",
            colorHex: "#2563EB",
            keyStopIds: [
                "prop-ciudad-nueva",
                "stop-plaza-jorge-chavez",
                "stop-estadio-jorge-basadre",
                "stop-cc-tupac-amaru",
                "stop-plaza-vigil",
                "stop-pasaje-vigil",
                "stop-mercado-2-mayo",
                "stop-mercado-central",
                "stop-tacna-centro",
                "stop-plaza-vea",
                "stop-gobierno-regional",
                "stop-plaza-del-maestro",
                "stop-unjbg",
                "stop-plaza-perez-gamboa",
                "stop-mercado-cenepa",
                "stop-mercado-santa-rosa",
                "prop-vinani-albarracin"
            ]
        ),
        TacnaOfficialRouteCatalogItem(
            id: "tacna-ruta-10b",
            code: "RUTA 10B",
            title: "Corredor Universitario, Hospitalario y Céntrico",
            corridorSummary: "Polvos Rosados ⇄ Paseo de las Aguas ⇄ Plaza San Francisco ⇄ Hosp. Unanue ⇄ UNJBG ⇄ UPT ⇄ EsSalud Calana",
            frequencyLabel: "Cada 6 min",
            scheduleLabel: "06:00 - 22:00",
            colorHex: "#10B981",
            keyStopIds: [
                "stop-polvos-rosados",
                "stop-paseo-aguas",
                "stop-plaza-san-francisco",
                "stop-gran-hotel-tacna",
                "stop-poder-judicial",
                "stop-parque-locomotora",
                "prop-hospital-unanue",
                "stop-plaza-quinones",
                "stop-unjbg",
                "prop-upt-colegios",
                "prop-hospital-essalud-calana"
            ]
        ),
        TacnaOfficialRouteCatalogItem(
            id: "tacna-ruta-101",
            code: "RUTA 101",
            title: "Corredor Comercial, Terminales y Parque Industrial",
            corridorSummary: "Mercado Pesquero ⇄ Terminal Terrestre ⇄ Terminal Bolognesi ⇄ Mercado Grau ⇄ Radio Nacional ⇄ Mercado Central",
            frequencyLabel: "Cada 7 min",
            scheduleLabel: "05:30 - 22:00",
            colorHex: "#F59E0B",
            keyStopIds: [
                "stop-mercado-pesquero",
                "stop-terminal-terrestre",
                "stop-terminal-bolognesi",
                "stop-mercado-grau",
                "stop-radio-nacional",
                "stop-cc-tupac-amaru",
                "stop-plaza-vigil",
                "stop-mercado-central"
            ]
        ),
        TacnaOfficialRouteCatalogItem(
            id: "tacna-ruta-203",
            code: "RUTA 203",
            title: "Expreso Cono Sur – Mercados – Campus UNJBG",
            corridorSummary: "Mercado 2 de Mayo ⇄ Plaza del Maestro ⇄ UNJBG ⇄ Plaza Pérez Gamboa ⇄ Postas Médicas ⇄ Mdo. Cenepa ⇄ Viñani",
            frequencyLabel: "Cada 6 min",
            scheduleLabel: "05:45 - 22:15",
            colorHex: "#A855F7",
            keyStopIds: [
                "stop-mercado-2-mayo",
                "stop-plaza-del-maestro",
                "stop-unjbg",
                "stop-plaza-perez-gamboa",
                "prop-postas-medicas",
                "stop-mercado-cenepa",
                "stop-mercado-santa-rosa",
                "prop-vinani-albarracin"
            ]
        ),
        TacnaOfficialRouteCatalogItem(
            id: "tacna-ruta-a",
            code: "RUTA A",
            title: "Anillo Histórico y Turístico – Complejo Santa Rosa",
            corridorSummary: "Parque de la Locomotora ⇄ Tacna Centro ⇄ Gran Hotel Tacna ⇄ Paseo de las Aguas ⇄ Terminal Terrestre ⇄ Santa Rosa",
            frequencyLabel: "Cada 10 min",
            scheduleLabel: "06:00 - 21:30",
            colorHex: "#06B6D4",
            keyStopIds: [
                "stop-parque-locomotora",
                "stop-tacna-centro",
                "stop-gran-hotel-tacna",
                "stop-plaza-san-francisco",
                "stop-paseo-aguas",
                "stop-plaza-vea",
                "stop-terminal-terrestre",
                "prop-complejo-santa-rosa"
            ]
        )
    ]
}

// MARK: - Estado de Guía de Ruta Activa en el Mapa Principal (Cuando se presiona [Iniciar])
struct ActiveRouteGuidanceState: Equatable {
    let destination: TacnaDestinationPlace
    let selectedOptionIndex: Int
    var remainingBusArrivalSeconds: Int
}

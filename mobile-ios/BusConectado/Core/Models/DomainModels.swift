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

// MARK: - Catálogo de Cuentas de Prueba (Inician en 0 pts, 0 viajes y 0 paraderos/buses)
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
// Por defecto las cuentas de prueba inician con listas vacías ([]),
// pero toda la arquitectura está lista para renderizarlos dinámicamente cuando existan.
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
    let direction: String // "UP" (Ida) o "DOWN" (Vuelta)
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

// MARK: - Destinos y Lugares de Tacna para Buscador Predictivo y Módulo "Ir / Cómo Llegar" (CU-07 / Sección 4.B y 4.E)
enum DestinationRouteCase: String, Codable, Equatable {
    case walkOnlyPlazaZela   // Caso 1: Destino Plaza Zela (2 min a pie · 180 m · Gratis)
    case busToUnjbg          // Caso 2: Destino P. UNJBG (16 min · 3.2 km · S/. 0.70)
    case busToMercado        // Caso 3A: Destino P. Mercado (10 min · 1.2 km · S/. 0.70)
    case busToMercadillo     // Caso 3B: Destino Mercadillo / Comercial (12 min · 1.4 km · S/. 0.70)
}

struct TacnaDestinationPlace: Identifiable, Equatable {
    let id: String
    let name: String
    let shortName: String
    let subtitle: String
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

    /// Coordenada simulada del usuario en Tacna ("Tu ubicación", cerca al Centro Histórico / Calle Zela)
    static let userOriginCoordinate = CLLocationCoordinate2D(latitude: -18.0108, longitude: -70.2512)
    static let plazaZelaCoordinate = CLLocationCoordinate2D(latitude: -18.0116, longitude: -70.2496)
    static let pMercadoCoordinate = CLLocationCoordinate2D(latitude: -18.0148, longitude: -70.2525)
    static let pUnjbgCoordinate = CLLocationCoordinate2D(latitude: -18.0242, longitude: -70.2504)

    var walkingToBoardCoordinates: [CLLocationCoordinate2D] {
        [
            Self.userOriginCoordinate,
            CLLocationCoordinate2D(latitude: -18.0112, longitude: -70.2504),
            Self.plazaZelaCoordinate
        ]
    }

    var busTransitCoordinates: [CLLocationCoordinate2D] {
        switch routeCase {
        case .walkOnlyPlazaZela:
            return []
        case .busToMercado, .busToMercadillo:
            return [
                Self.plazaZelaCoordinate,
                CLLocationCoordinate2D(latitude: -18.0132, longitude: -70.2510),
                Self.pMercadoCoordinate
            ]
        case .busToUnjbg:
            return [
                Self.plazaZelaCoordinate,
                CLLocationCoordinate2D(latitude: -18.0132, longitude: -70.2510),
                Self.pMercadoCoordinate,
                CLLocationCoordinate2D(latitude: -18.0195, longitude: -70.2515),
                Self.pUnjbgCoordinate
            ]
        }
    }

    var walkingFinalCoordinates: [CLLocationCoordinate2D] {
        switch routeCase {
        case .walkOnlyPlazaZela, .busToMercado, .busToUnjbg:
            if coordinate.latitude == Self.pUnjbgCoordinate.latitude && coordinate.longitude == Self.pUnjbgCoordinate.longitude {
                return []
            }
            if coordinate.latitude == Self.pMercadoCoordinate.latitude && coordinate.longitude == Self.pMercadoCoordinate.longitude {
                return []
            }
            if coordinate.latitude == Self.plazaZelaCoordinate.latitude && coordinate.longitude == Self.plazaZelaCoordinate.longitude {
                return []
            }
            let lastBusCoord = busTransitCoordinates.last ?? Self.pMercadoCoordinate
            return [lastBusCoord, coordinate]
        case .busToMercadillo:
            return [
                Self.pMercadoCoordinate,
                CLLocationCoordinate2D(latitude: -18.0155, longitude: -70.2533),
                coordinate
            ]
        }
    }

    /// Catálogo oficial del Mockup (Sección 4.B y 4.E)
    static let catalog: [TacnaDestinationPlace] = [
        TacnaDestinationPlace(
            id: "dest-mercado",
            name: "P. Mercado (Mercado Central)",
            shortName: "P. Mercado",
            subtitle: "Av. Bolognesi #450 • Paradero L10",
            iconName: "storefront.fill",
            iconColorHex: "#3B82F6",
            latitude: -18.0148,
            longitude: -70.2525,
            routeCase: .busToMercado,
            totalDurationMinutes: 10,
            secondaryDurationMinutes: 16,
            walkingDirectMinutes: 18,
            distanceLabel: "1.2 km",
            walkInitialMinutes: 2,
            busRideMinutes: 8,
            walkFinalMinutes: 0,
            boardingStopName: "Plaza Zela",
            alightingStopName: "P. Mercado",
            intermediateStopName: nil,
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "dest-zela",
            name: "Plaza Zela",
            shortName: "Plaza Zela",
            subtitle: "Calle Zela • Paradero Histórico L10",
            iconName: "mappin.and.ellipse",
            iconColorHex: "#10B981",
            latitude: -18.0116,
            longitude: -70.2496,
            routeCase: .walkOnlyPlazaZela,
            totalDurationMinutes: 2,
            secondaryDurationMinutes: 2,
            walkingDirectMinutes: 2,
            distanceLabel: "180 m",
            walkInitialMinutes: 2,
            busRideMinutes: 0,
            walkFinalMinutes: 0,
            boardingStopName: "Plaza Zela",
            alightingStopName: "Plaza Zela",
            intermediateStopName: nil,
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "dest-unjbg",
            name: "P. UNJBG (Campus Universitario)",
            shortName: "P. UNJBG",
            subtitle: "Av. Miraflores • Paradero Universitario L10",
            iconName: "graduationcap.fill",
            iconColorHex: "#F59E0B",
            latitude: -18.0242,
            longitude: -70.2504,
            routeCase: .busToUnjbg,
            totalDurationMinutes: 16,
            secondaryDurationMinutes: 22,
            walkingDirectMinutes: 34,
            distanceLabel: "3.2 km",
            walkInitialMinutes: 2,
            busRideMinutes: 14,
            walkFinalMinutes: 0,
            boardingStopName: "Plaza Zela",
            alightingStopName: "P. UNJBG",
            intermediateStopName: "P. Mercado",
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "dest-mercadillo",
            name: "Mercadillo Bolognesi",
            shortName: "Mercadillo Bolognesi",
            subtitle: "Av. Bolognesi • Zona Comercial Tacna",
            iconName: "bag.fill",
            iconColorHex: "#38BDF8",
            latitude: -18.0161,
            longitude: -70.2541,
            routeCase: .busToMercadillo,
            totalDurationMinutes: 12,
            secondaryDurationMinutes: 18,
            walkingDirectMinutes: 22,
            distanceLabel: "1.4 km",
            walkInitialMinutes: 2,
            busRideMinutes: 8,
            walkFinalMinutes: 1,
            boardingStopName: "Plaza Zela",
            alightingStopName: "P. Mercado",
            intermediateStopName: nil,
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "dest-terminal",
            name: "Terminal Terrestre Tacna",
            shortName: "Terminal Terrestre",
            subtitle: "Prol. Hipólito Unanue • Destino Comercial",
            iconName: "bus.doubledecker.fill",
            iconColorHex: "#F43F5E",
            latitude: -18.0045,
            longitude: -70.2612,
            routeCase: .busToMercadillo,
            totalDurationMinutes: 14,
            secondaryDurationMinutes: 20,
            walkingDirectMinutes: 26,
            distanceLabel: "1.9 km",
            walkInitialMinutes: 2,
            busRideMinutes: 10,
            walkFinalMinutes: 2,
            boardingStopName: "Plaza Zela",
            alightingStopName: "P. Mercado",
            intermediateStopName: nil,
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "dest-estadio",
            name: "Estadio Jorge Basadre",
            shortName: "Estadio Jorge Basadre",
            subtitle: "Av. Coronel Justo Arias Araguez, Tacna",
            iconName: "sportscourt.fill",
            iconColorHex: "#A855F7",
            latitude: -18.0185,
            longitude: -70.2509,
            routeCase: .busToUnjbg,
            totalDurationMinutes: 14,
            secondaryDurationMinutes: 19,
            walkingDirectMinutes: 25,
            distanceLabel: "2.1 km",
            walkInitialMinutes: 2,
            busRideMinutes: 10,
            walkFinalMinutes: 2,
            boardingStopName: "Plaza Zela",
            alightingStopName: "P. UNJBG",
            intermediateStopName: "P. Mercado",
            statusNote: nil
        ),
        TacnaDestinationPlace(
            id: "dest-pronabec",
            name: "Pronabec Tacna",
            shortName: "Pronabec Tacna",
            subtitle: "Av. Bolognesi • Oficina Regional Tacna",
            iconName: "building.columns.fill",
            iconColorHex: "#FB923C",
            latitude: -18.0138,
            longitude: -70.2518,
            routeCase: .busToMercado,
            totalDurationMinutes: 11,
            secondaryDurationMinutes: 17,
            walkingDirectMinutes: 19,
            distanceLabel: "1.3 km",
            walkInitialMinutes: 2,
            busRideMinutes: 8,
            walkFinalMinutes: 1,
            boardingStopName: "Plaza Zela",
            alightingStopName: "P. Mercado",
            intermediateStopName: nil,
            statusNote: "Cerrado · Abre a las 8:30 a.m. del lun"
        )
    ]
}

// MARK: - Estado de Guía de Ruta Activa en el Mapa Principal (Cuando se presiona [Iniciar])
struct ActiveRouteGuidanceState: Equatable {
    let destination: TacnaDestinationPlace
    let selectedOptionIndex: Int
    var remainingBusArrivalSeconds: Int // Inicia en 168 seg (02:48 como en el mockup)
}


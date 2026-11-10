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

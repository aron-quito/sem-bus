package pe.edu.unjbg.busconectado.core.model

import android.content.Context
import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import com.google.gson.reflect.TypeToken
import pe.edu.unjbg.busconectado.core.location.GeoPointData
import pe.edu.unjbg.busconectado.core.location.LocationService
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

enum class UserRoleType(
    val raw: String,
    val farePoints: Int,
    val displayName: String,
    val badgeLabel: String
) {
    ADULT(
        raw = "ADULT",
        farePoints = 15,
        displayName = "Pasajero Adulto",
        badgeLabel = "Tarifa General · 15 pts (S/. 1.50)"
    ),
    STUDENT(
        raw = "STUDENT",
        farePoints = 7,
        displayName = "Universitario SUNEDU",
        badgeLabel = "Tarifa Universitaria · 7 pts (S/. 0.70)"
    ),
    CONADIS(
        raw = "CONADIS",
        farePoints = 0,
        displayName = "Pase Libre CONADIS",
        badgeLabel = "Exonerado Ley 30412 · 0 pts (S/. 0.00)"
    ),
    DRIVER(
        raw = "DRIVER",
        farePoints = 15,
        displayName = "Conductor BC",
        badgeLabel = "Tarifa General · 15 pts (S/. 1.50)"
    ),
    ADMIN(
        raw = "ADMIN",
        farePoints = 15,
        displayName = "Administrador",
        badgeLabel = "Tarifa General · 15 pts (S/. 1.50)"
    );

    val farePen: Double
        get() = farePoints / 10.0

    companion object {
        fun fromRaw(raw: String?): UserRoleType {
            return entries.firstOrNull { it.raw.equals(raw, ignoreCase = true) } ?: ADULT
        }
    }
}

data class StudentVerificationInfo(
    val dni: String = "",
    val university: String = "",
    val career: String? = null,
    @SerializedName("academic_cycle")
    val academicCycle: String? = null,
    val status: String = "VERIFIED",
    @SerializedName("expires_at")
    val expiresAt: String = "2026-12-31"
) {
    val daysRemaining: Int?
        get() {
            val cleaned = expiresAt.trim()
            if (cleaned.isEmpty()) return null
            val formats = listOf("yyyy-MM-dd", "dd/MM/yyyy")
            for (fmt in formats) {
                try {
                    val target = LocalDate.parse(cleaned.take(10), DateTimeFormatter.ofPattern(fmt))
                    return ChronoUnit.DAYS.between(LocalDate.now(), target).toInt()
                } catch (_: Exception) {
                }
            }
            return null
        }

    val formattedExpirationDate: String
        get() {
            val cleaned = expiresAt.trim()
            val formats = listOf("yyyy-MM-dd", "dd/MM/yyyy")
            for (fmt in formats) {
                try {
                    val target = LocalDate.parse(cleaned.take(10), DateTimeFormatter.ofPattern(fmt))
                    return target.format(DateTimeFormatter.ofPattern("dd/MM/yyyy", Locale("es", "PE")))
                } catch (_: Exception) {
                }
            }
            return cleaned
        }

    val expirationSummaryText: String
        get() {
            val days = daysRemaining
            return when {
                days == null -> "Vigencia hasta $formattedExpirationDate"
                days < 0 -> "Vencido el $formattedExpirationDate"
                days == 0 -> "Vence hoy ($formattedExpirationDate)"
                else -> "Vence $formattedExpirationDate · Quedan $days días"
            }
        }
}

data class CarnetReviewRequest(
    val id: String,
    val requestedType: String, // "STUDENT" or "CONADIS"
    val dni: String,
    val institutionOrRegistry: String,
    val documentCode: String,
    val expiresAt: String,
    val status: String,
    val submittedAtLabel: String
)

data class UserAuth(
    val id: String,
    val phone: String,
    @SerializedName("display_name")
    val displayName: String,
    val role: String = "ADULT",
    @SerializedName("is_student")
    val isStudent: Boolean = false,
    @SerializedName("points_balance")
    val pointsBalance: Int = 0,
    @SerializedName("student_verification")
    val studentVerification: StudentVerificationInfo? = null,
    @SerializedName("qr_code_payload")
    val qrCodePayload: String? = null
) {
    val roleType: UserRoleType
        get() {
            val upper = role.uppercase(Locale.ROOT)
            return when {
                upper == "CONADIS" -> UserRoleType.CONADIS
                upper == "STUDENT" || isStudent -> UserRoleType.STUDENT
                upper == "DRIVER" -> UserRoleType.DRIVER
                upper == "ADMIN" -> UserRoleType.ADMIN
                else -> UserRoleType.ADULT
            }
        }

    val initials: String
        get() {
            val parts = displayName.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
            if (parts.isEmpty()) return "BC"
            val first = parts.first().take(1)
            val second = if (parts.size > 1) parts[1].take(1) else ""
            return (first + second).uppercase(Locale.ROOT)
        }
}

data class TestAccountPreset(
    val id: String,
    val phoneNumber: String,
    val otpCode: String,
    val title: String,
    val subtitle: String,
    val badge: String,
    val accentHex: String,
    val roleType: UserRoleType,
    val defaultUser: UserAuth
) {
    companion object {
        val officialPresets: List<TestAccountPreset> = listOf(
            TestAccountPreset(
                id = "student_unjbg",
                phoneNumber = "952000002",
                otpCode = "123456",
                title = "Aron Mamani Quispe",
                subtitle = "Estudiante UNJBG • Carné SUNEDU Verificado",
                badge = "Tarifa 7 pts (S/. 0.70)",
                accentHex = "#F59E0B",
                roleType = UserRoleType.STUDENT,
                defaultUser = UserAuth(
                    id = "demo_student_952000002",
                    phone = "+51952000002",
                    displayName = "Aron Mamani Quispe",
                    role = "STUDENT",
                    isStudent = true,
                    pointsBalance = 0,
                    studentVerification = StudentVerificationInfo(
                        dni = "74829103",
                        university = "Universidad Nacional Jorge Basadre Grohmann (UNJBG)",
                        career = "Ing. Sistemas",
                        academicCycle = "2026-II",
                        status = "VERIFIED",
                        expiresAt = "2026-12-31"
                    ),
                    qrCodePayload = "BC-PASS|STUDENT|952000002"
                )
            ),
            TestAccountPreset(
                id = "adult_general",
                phoneNumber = "952000001",
                otpCode = "123456",
                title = "Carlos Mendoza",
                subtitle = "Pasajero General • Tarifa Estándar",
                badge = "Tarifa 15 pts (S/. 1.50)",
                accentHex = "#2563EB",
                roleType = UserRoleType.ADULT,
                defaultUser = UserAuth(
                    id = "demo_adult_952000001",
                    phone = "+51952000001",
                    displayName = "Carlos Mendoza",
                    role = "ADULT",
                    isStudent = false,
                    pointsBalance = 0,
                    studentVerification = null,
                    qrCodePayload = "BC-PASS|ADULT|952000001"
                )
            ),
            TestAccountPreset(
                id = "conadis_free",
                phoneNumber = "952000003",
                otpCode = "123456",
                title = "Elena Quispe",
                subtitle = "Beneficiaria CONADIS • Ley N° 30412",
                badge = "Pase Libre 0 pts (S/. 0.00)",
                accentHex = "#06B6D4",
                roleType = UserRoleType.CONADIS,
                defaultUser = UserAuth(
                    id = "demo_conadis_952000003",
                    phone = "+51952000003",
                    displayName = "Elena Quispe",
                    role = "CONADIS",
                    isStudent = false,
                    pointsBalance = 0,
                    studentVerification = null,
                    qrCodePayload = "BC-PASS|CONADIS|952000003"
                )
            )
        )
    }
}

enum class LedgerTransactionKind {
    RECHARGE,
    QR_PAYMENT
}

data class LedgerTransactionItem(
    val id: String,
    val title: String,
    val subtitle: String,
    val amountPoints: Int,
    val balanceBefore: Int,
    val balanceAfter: Int,
    val timestampLabel: String,
    val kind: LedgerTransactionKind,
    val plateBadge: String? = null
) {
    val isPositive: Boolean
        get() = amountPoints >= 0

    val formattedPoints: String
        get() = if (amountPoints >= 0) "+$amountPoints pts" else "$amountPoints pts"

    val amountPen: Double
        get() = abs(amountPoints) / 10.0
}

data class ActiveBusModel(
    val id: String,
    @SerializedName("unit_number")
    val unitNumber: String,
    val plate: String,
    @SerializedName("line_number")
    val lineNumber: String,
    @SerializedName("route_id")
    val routeId: String,
    val latitude: Double,
    val longitude: Double,
    @SerializedName("speed_kmh")
    val speedKmh: Double,
    val heading: Double,
    val passengers: Int,
    val capacity: Int,
    @SerializedName("next_stop_name")
    val nextStopName: String,
    @SerializedName("next_stop_eta_minutes")
    val nextStopEtaMinutes: Int,
    @SerializedName("driver_name")
    val driverName: String,
    @SerializedName("driver_rating")
    val driverRating: Double
) {
    val coordinate: GeoPointData
        get() = GeoPointData(latitude, longitude)

    val isFull: Boolean
        get() = passengers >= capacity
}

data class BusStopModel(
    val id: String,
    @SerializedName("route_id")
    val routeId: String,
    val name: String,
    val subtitle: String,
    val latitude: Double,
    val longitude: Double,
    @SerializedName("sequence_order")
    val sequenceOrder: Int,
    val direction: String,
    @SerializedName("is_key_stop")
    val isKeyStop: Boolean
) {
    val coordinate: GeoPointData
        get() = GeoPointData(latitude, longitude)
}

data class BusRouteModel(
    val id: String,
    @SerializedName("line_number")
    val lineNumber: String,
    val name: String,
    @SerializedName("origin_name")
    val originName: String,
    @SerializedName("destination_name")
    val destinationName: String,
    @SerializedName("frequency_minutes")
    val frequencyMinutes: Int,
    @SerializedName("operating_hours")
    val operatingHours: String,
    @SerializedName("color_hex")
    val colorHex: String,
    val stops: List<BusStopModel> = emptyList()
)

data class ArrivalAlertState(
    val stopId: String,
    val stopName: String,
    val routeLine: String,
    val advanceMinutes: Int,
    val remainingSeconds: Int,
    val imminentVibrationsEnabled: Boolean
)

data class ActiveTripState(
    val unitNumber: String,
    val plate: String,
    val lineNumber: String,
    val pointsPaid: Int,
    val companionsCount: Int,
    val remainingSeconds: Int,
    val isConfirmedOnBoard: Boolean? = null,
    val destinationStopName: String? = null,
    val destinationLatitude: Double? = null,
    val destinationLongitude: Double? = null,
    val proximityAlertTriggered: Boolean = false
)

enum class MapFilterCategory(val label: String) {
    LIVE("En vivo"),
    ROUTES("Rutas"),
    STOPS("Paraderos")
}

enum class MainAppTab(val title: String) {
    EXPLORE("Explorar"),
    LINES("Líneas"),
    PAY_QR("Pagar QR"),
    WALLET("Monedero")
}

enum class TacnaStopCategory(val raw: String, val displayLabel: String) {
    ALL("all", "Todos"),
    UNIVERSITIES("universities", "Universidades"),
    MARKETS("marketsCommercial", "Mercados"),
    TRANSPORT("transportTerminals", "Terminales"),
    CIVIC("civicHealth", "Salud y Cívico"),
    MAP_CUSTOM("mapCustomPlace", "Mapa");

    companion object {
        fun fromRaw(raw: String?): TacnaStopCategory {
            return when (raw) {
                "universities" -> UNIVERSITIES
                "marketsCommercial" -> MARKETS
                "transportTerminals" -> TRANSPORT
                "civicHealth" -> CIVIC
                "mapCustomPlace" -> MAP_CUSTOM
                else -> CIVIC
            }
        }
    }
}

enum class RouteCaseKind {
    DIRECT_ORDINARY,
    EXTERNAL_SUGGESTION,
    WALK_ONLY_NEARBY
}

data class TacnaDestinationPlace(
    val id: String,
    val name: String,
    val shortName: String,
    val subtitle: String,
    val category: String = "civicHealth",
    val categoryLabel: String = "Punto de referencia",
    val isOfficial: Boolean = true,
    val latitude: Double,
    val longitude: Double,
    val routesPassing: List<String> = emptyList(),
    val colorHex: String = "#06B6D4",
    val iconName: String = "bus.fill",
    val statusNote: String? = null
) {
    val coordinate: GeoPointData
        get() = GeoPointData(latitude, longitude)

    val stopCategory: TacnaStopCategory
        get() = TacnaStopCategory.fromRaw(category)

    val primaryRouteName: String
        get() = routesPassing.firstOrNull() ?: "Ruta 14"

    val totalDurationMinutes: Int
        get() = if (id.startsWith("map_") || id.startsWith("api_")) 18 else 22

    val routeCase: RouteCaseKind
        get() = when {
            routesPassing.any { it.contains("14", ignoreCase = true) } -> RouteCaseKind.DIRECT_ORDINARY
            routesPassing.isNotEmpty() -> RouteCaseKind.EXTERNAL_SUGGESTION
            else -> RouteCaseKind.WALK_ONLY_NEARBY
        }

    companion object {
        fun currentLocationPlace(coord: GeoPointData = LocationService.TACNA_DEFAULT): TacnaDestinationPlace {
            return TacnaDestinationPlace(
                id = "current_gps",
                name = "Tu ubicación actual",
                shortName = "Tu ubicación",
                subtitle = "GPS de Tacna",
                category = "mapCustomPlace",
                categoryLabel = "GPS",
                isOfficial = false,
                latitude = coord.latitude,
                longitude = coord.longitude,
                routesPassing = emptyList(),
                colorHex = "#2563EB"
            )
        }

        fun fromMapItem(
            name: String,
            subtitle: String,
            coordinate: GeoPointData,
            idPrefix: String = "map"
        ): TacnaDestinationPlace {
            val safe = LocationService.sanitizedTacnaCoordinate(coordinate)
            val cleanShort = name.take(28)
            return TacnaDestinationPlace(
                id = "${idPrefix}_${(safe.latitude * 100000).roundToInt()}_${(safe.longitude * 100000).roundToInt()}",
                name = name,
                shortName = cleanShort,
                subtitle = subtitle,
                category = "mapCustomPlace",
                categoryLabel = "Punto en mapa",
                isOfficial = false,
                latitude = safe.latitude,
                longitude = safe.longitude,
                routesPassing = emptyList(),
                colorHex = "#06B6D4"
            )
        }
    }
}

sealed class StopNotificationAvailability {
    data class Available(val activeOrdinaryRoutes: List<TacnaOfficialRouteCatalogItem>) : StopNotificationAvailability()
    data class OrdinaryOutOfService(val registeredRoutes: List<TacnaOfficialRouteCatalogItem>) : StopNotificationAvailability()
    object NoOrdinaryRoutes : StopNotificationAvailability()
}

data class TacnaOfficialRouteCatalogItem(
    val id: String,
    val code: String,
    val title: String,
    val routeType: String = "ordinary", // "ordinary" | "external"
    val isInService: Boolean = false,
    val corridorSummary: String = "",
    val frequencyMinutes: Int = 6,
    val frequencyLabel: String = "Cada 5 min",
    val scheduleLabel: String = "05:30 - 22:30",
    val averageSpeedKmh: Double = 22.0,
    val totalDistanceKm: Double = 18.0,
    val estimatedTotalMinutes: Int = 55,
    val colorHex: String = "#2563EB",
    val keyStopIds: List<String> = emptyList(),
    val pathCoordinates: List<List<Double>> = emptyList()
) {
    val isOrdinary: Boolean
        get() = routeType.equals("ordinary", ignoreCase = true)

    val isExternal: Boolean
        get() = !isOrdinary

    val isOrdinaryInService: Boolean
        get() = isOrdinary && isInService

    val supportsQrPayment: Boolean
        get() = isOrdinaryInService

    val supportsArrivalNotification: Boolean
        get() = isOrdinaryInService

    fun resolvedStops(usingStops: List<TacnaDestinationPlace>): List<TacnaDestinationPlace> {
        if (usingStops.isEmpty()) return emptyList()
        val byId = usingStops.associateBy { it.id }
        val ordered = keyStopIds.mapNotNull { byId[it] }
        if (ordered.isNotEmpty()) return ordered
        return usingStops.filter { stop ->
            stop.routesPassing.any { r ->
                r.equals(code, ignoreCase = true) ||
                    code.contains(r, ignoreCase = true) ||
                    r.contains(code, ignoreCase = true)
            }
        }
    }

    fun resolvedPolylineCoordinates(usingStops: List<TacnaDestinationPlace>): List<GeoPointData> {
        if (pathCoordinates.size >= 2) {
            val parsed = pathCoordinates.mapNotNull { pair ->
                if (pair.size >= 2) GeoPointData(pair[0], pair[1]) else null
            }
            if (parsed.size >= 2) return parsed
        }
        return resolvedStops(usingStops).map { it.coordinate }
    }
}

enum class EvaluatedCandidateKind {
    ORDINARY_IN_SERVICE,
    EXTERNAL_FREE_BOARDING,
    WALKING_DIRECT
}

data class EvaluatedRouteCandidate(
    val id: String,
    val kind: EvaluatedCandidateKind,
    val route: TacnaOfficialRouteCatalogItem?,
    val routeCode: String,
    val routeTitle: String,
    val colorHex: String,
    val totalDurationMinutes: Int,
    val totalDistanceMeters: Int,
    val walkInitialMinutes: Int,
    val walkInitialMeters: Int,
    val busWaitMinutes: Int,
    val busRideMinutes: Int,
    val busRideMeters: Int,
    val walkFinalMinutes: Int,
    val walkFinalMeters: Int,
    val boardingStop: TacnaDestinationPlace?,
    val alightingStop: TacnaDestinationPlace?,
    val intermediateStopsCount: Int,
    val intermediateStopNames: List<String>,
    val boardingPointName: String,
    val alightingPointName: String,
    val boardingLatitude: Double,
    val boardingLongitude: Double,
    val alightingLatitude: Double,
    val alightingLongitude: Double,
    val walkToBoardCoords: List<GeoPointData>,
    val busTransitCoords: List<GeoPointData>,
    val walkFinalCoords: List<GeoPointData>,
    val isRecommendedPrimary: Boolean = false,
    val externalRecommendationReason: String? = null
) {
    val boardingCoordinate: GeoPointData
        get() = GeoPointData(boardingLatitude, boardingLongitude)

    val alightingCoordinate: GeoPointData
        get() = GeoPointData(alightingLatitude, alightingLongitude)

    val walkTotalMeters: Int
        get() = walkInitialMeters + walkFinalMeters

    val totalDistanceLabel: String
        get() = if (totalDistanceMeters >= 1000) {
            String.format(Locale.US, "%.1f km", totalDistanceMeters / 1000.0)
        } else {
            "$totalDistanceMeters m"
        }
}

data class RouteAutomationEvaluationResult(
    val origin: TacnaDestinationPlace,
    val destination: TacnaDestinationPlace,
    val candidates: List<EvaluatedRouteCandidate>,
    val primaryBannerWarning: String?,
    val hasOrdinaryInService: Boolean
) {
    val recommendedCandidate: EvaluatedRouteCandidate?
        get() = candidates.firstOrNull { it.isRecommendedPrimary } ?: candidates.firstOrNull()
}

data class ActiveRouteGuidanceState(
    val origin: TacnaDestinationPlace,
    val destination: TacnaDestinationPlace,
    val selectedOptionIndex: Int,
    val candidate: EvaluatedRouteCandidate?,
    val remainingBusArrivalSeconds: Int,
    val showArrivalTimer: Boolean
)

object TacnaSeedLoader {
    private val gson = Gson()

    fun loadBundledStops(context: Context): List<TacnaDestinationPlace> {
        return try {
            context.assets.open("tacna_seed_stops.json").bufferedReader().use { reader ->
                val type = object : TypeToken<List<TacnaDestinationPlace>>() {}.type
                gson.fromJson(reader.readText(), type) ?: emptyList()
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun loadBundledRoutes(context: Context): List<TacnaOfficialRouteCatalogItem> {
        return try {
            context.assets.open("tacna_seed_routes.json").bufferedReader().use { reader ->
                val type = object : TypeToken<List<TacnaOfficialRouteCatalogItem>>() {}.type
                gson.fromJson(reader.readText(), type) ?: emptyList()
            }
        } catch (_: Exception) {
            emptyList()
        }
    }
}

object RouteAutomationEngine {

    private data class SubPolylineResult(
        val subCoords: List<GeoPointData>,
        val boardVertex: GeoPointData,
        val alightVertex: GeoPointData,
        val lengthMeters: Double
    )

    private fun extractRouteSubPolyline(
        polyline: List<GeoPointData>,
        start: GeoPointData,
        end: GeoPointData
    ): SubPolylineResult {
        if (polyline.size < 2) {
            return SubPolylineResult(
                subCoords = listOf(start, end),
                boardVertex = start,
                alightVertex = end,
                lengthMeters = max(start.distanceMetersTo(end), 120.0)
            )
        }

        var idxStart = 0
        var minDistStart = Double.MAX_VALUE
        polyline.forEachIndexed { idx, pt ->
            val d = pt.distanceMetersTo(start)
            if (d < minDistStart) {
                minDistStart = d
                idxStart = idx
            }
        }

        var idxEnd = 0
        var minDistEnd = Double.MAX_VALUE
        polyline.forEachIndexed { idx, pt ->
            val d = pt.distanceMetersTo(end)
            if (d < minDistEnd) {
                minDistEnd = d
                idxEnd = idx
            }
        }

        val slice = if (idxStart <= idxEnd) {
            polyline.subList(idxStart, idxEnd + 1).toList()
        } else {
            polyline.subList(idxEnd, idxStart + 1).reversed()
        }

        var totalMeters = 0.0
        for (i in 0 until slice.size - 1) {
            totalMeters += slice[i].distanceMetersTo(slice[i + 1])
        }
        val boardPt = slice.firstOrNull() ?: start
        val alightPt = slice.lastOrNull() ?: end
        return SubPolylineResult(
            subCoords = slice,
            boardVertex = boardPt,
            alightVertex = alightPt,
            lengthMeters = max(totalMeters, 120.0)
        )
    }

    fun evaluateRoutes(
        origin: TacnaDestinationPlace,
        destination: TacnaDestinationPlace,
        stops: List<TacnaDestinationPlace>,
        routes: List<TacnaOfficialRouteCatalogItem>,
        activeBuses: List<ActiveBusModel>
    ): RouteAutomationEvaluationResult {
        val originCoord = LocationService.sanitizedTacnaCoordinate(origin.coordinate)
        val destCoord = LocationService.sanitizedTacnaCoordinate(destination.coordinate)
        val directRawMeters = originCoord.distanceMetersTo(destCoord)
        val directWalkMeters = max((directRawMeters * 1.18).roundToInt(), 40)
        val directWalkMinutes = max((directWalkMeters / 76.0).roundToInt(), 1)

        val walkCandidate = EvaluatedRouteCandidate(
            id = "cand-walk-${origin.id}-${destination.id}",
            kind = EvaluatedCandidateKind.WALKING_DIRECT,
            route = null,
            routeCode = "A pie",
            routeTitle = "Caminata directa por las calles de Tacna",
            colorHex = "#38BDF8",
            totalDurationMinutes = directWalkMinutes,
            totalDistanceMeters = directWalkMeters,
            walkInitialMinutes = directWalkMinutes,
            walkInitialMeters = directWalkMeters,
            busWaitMinutes = 0,
            busRideMinutes = 0,
            busRideMeters = 0,
            walkFinalMinutes = 0,
            walkFinalMeters = 0,
            boardingStop = null,
            alightingStop = null,
            intermediateStopsCount = 0,
            intermediateStopNames = emptyList(),
            boardingPointName = origin.shortName,
            alightingPointName = destination.shortName,
            boardingLatitude = originCoord.latitude,
            boardingLongitude = originCoord.longitude,
            alightingLatitude = destCoord.latitude,
            alightingLongitude = destCoord.longitude,
            walkToBoardCoords = listOf(originCoord, destCoord),
            busTransitCoords = emptyList(),
            walkFinalCoords = emptyList()
        )

        val ordinaryCandidates = mutableListOf<EvaluatedRouteCandidate>()
        val externalCandidates = mutableListOf<EvaluatedRouteCandidate>()

        val activeOrdRoutes = routes.filter { it.isOrdinary && it.isInService }
        for (route in activeOrdRoutes) {
            val routeStops = route.resolvedStops(stops)
            if (routeStops.size < 2) continue
            val fullPoly = route.resolvedPolylineCoordinates(stops)

            var bestBoardIdx = -1
            var bestAlightIdx = -1
            var bestWalk1M = 0
            var bestWalk2M = 0
            var bestScore = Double.MAX_VALUE

            for (i in routeStops.indices) {
                val sBoard = routeStops[i]
                val dWalk1 = originCoord.distanceMetersTo(sBoard.coordinate) * 1.18
                for (j in routeStops.indices) {
                    if (i == j) continue
                    val sAlight = routeStops[j]
                    val dWalk2 = sAlight.coordinate.distanceMetersTo(destCoord) * 1.18
                    if (dWalk1 + dWalk2 > max(directRawMeters * 1.35, 650.0)) continue
                    val approxBusDist = sBoard.coordinate.distanceMetersTo(sAlight.coordinate) * 1.25
                    val speedMetersPerMin = max(route.averageSpeedKmh, 15.0) * 1000.0 / 60.0
                    val estMinutes = (dWalk1 + dWalk2) / 76.0 + (approxBusDist / speedMetersPerMin) + abs(j - i) * 0.32
                    if (estMinutes < bestScore) {
                        bestScore = estMinutes
                        bestBoardIdx = i
                        bestAlightIdx = j
                        bestWalk1M = max(dWalk1.roundToInt(), 20)
                        bestWalk2M = max(dWalk2.roundToInt(), 0)
                    }
                }
            }

            if (bestBoardIdx < 0 || bestAlightIdx < 0) continue

            val boardStop = routeStops[bestBoardIdx]
            val alightStop = routeStops[bestAlightIdx]
            val subSegment = extractRouteSubPolyline(fullPoly, boardStop.coordinate, alightStop.coordinate)

            val speedKmh = max(route.averageSpeedKmh, 16.0)
            val intermediateIndices = if (bestBoardIdx < bestAlightIdx) {
                ((bestBoardIdx + 1) until bestAlightIdx).toList()
            } else {
                ((bestAlightIdx + 1) until bestBoardIdx).reversed()
            }
            val intermediateNames = intermediateIndices.map { routeStops[it].shortName }

            val walk1Min = max(1, (bestWalk1M / 76.0).roundToInt())
            val walk2Min = if (bestWalk2M < 45) 0 else max(1, (bestWalk2M / 76.0).roundToInt())
            val busMeters = subSegment.lengthMeters.roundToInt()
            val busRideMin = max(
                2,
                ((busMeters / 1000.0) / speedKmh * 60.0 + intermediateNames.size * 0.35).roundToInt()
            )
            val liveEta = activeBuses.firstOrNull {
                it.lineNumber.contains(route.code, ignoreCase = true) ||
                    route.code.contains(it.lineNumber, ignoreCase = true)
            }?.nextStopEtaMinutes
            val busWaitMin = liveEta ?: min(5, max(3, route.frequencyMinutes))

            val totalMin = walk1Min + busRideMin + walk2Min
            val totalMeters = bestWalk1M + busMeters + bestWalk2M

            ordinaryCandidates += EvaluatedRouteCandidate(
                id = "cand-ord-${route.id}",
                kind = EvaluatedCandidateKind.ORDINARY_IN_SERVICE,
                route = route,
                routeCode = route.code,
                routeTitle = route.title,
                colorHex = route.colorHex,
                totalDurationMinutes = totalMin,
                totalDistanceMeters = totalMeters,
                walkInitialMinutes = walk1Min,
                walkInitialMeters = bestWalk1M,
                busWaitMinutes = busWaitMin,
                busRideMinutes = busRideMin,
                busRideMeters = busMeters,
                walkFinalMinutes = walk2Min,
                walkFinalMeters = bestWalk2M,
                boardingStop = boardStop,
                alightingStop = alightStop,
                intermediateStopsCount = intermediateNames.size,
                intermediateStopNames = intermediateNames,
                boardingPointName = boardStop.shortName,
                alightingPointName = alightStop.shortName,
                boardingLatitude = boardStop.latitude,
                boardingLongitude = boardStop.longitude,
                alightingLatitude = alightStop.latitude,
                alightingLongitude = alightStop.longitude,
                walkToBoardCoords = listOf(originCoord, boardStop.coordinate),
                busTransitCoords = subSegment.subCoords,
                walkFinalCoords = if (bestWalk2M < 35) emptyList() else listOf(alightStop.coordinate, destCoord)
            )
        }

        val extRoutes = routes.filter { it.isExternal }
        for (route in extRoutes) {
            val fullPoly = route.resolvedPolylineCoordinates(stops)
            if (fullPoly.size < 2) continue

            val subSegment = extractRouteSubPolyline(fullPoly, originCoord, destCoord)
            val dWalk1 = (originCoord.distanceMetersTo(subSegment.boardVertex) * 1.18).roundToInt()
            val dWalk2 = (subSegment.alightVertex.distanceMetersTo(destCoord) * 1.18).roundToInt()

            if ((dWalk1 + dWalk2) > max(directRawMeters * 1.30, 600.0)) continue

            val walk1Min = if (dWalk1 < 40) 1 else max(1, (dWalk1 / 76.0).roundToInt())
            val walk2Min = if (dWalk2 < 45) 0 else max(1, (dWalk2 / 76.0).roundToInt())
            val busMeters = subSegment.lengthMeters.roundToInt()
            val speedKmh = max(route.averageSpeedKmh, 18.0)
            val busRideMin = max(2, ((busMeters / 1000.0) / speedKmh * 60.0).roundToInt())
            val totalMin = walk1Min + busRideMin + walk2Min
            val totalMeters = dWalk1 + busMeters + dWalk2

            val nearestBoardRef = stops.minByOrNull { it.coordinate.distanceMetersTo(subSegment.boardVertex) }
            val nearestAlightRef = stops.minByOrNull { it.coordinate.distanceMetersTo(subSegment.alightVertex) }

            val boardLabel = if (nearestBoardRef != null) {
                "En vía de ${route.code} (alt. ${nearestBoardRef.shortName})"
            } else {
                "Punto en ruta de ${route.code} (Abordaje libre)"
            }
            val alightLabel = if (nearestAlightRef != null && nearestAlightRef.coordinate.distanceMetersTo(subSegment.alightVertex) < 350.0) {
                "En vía de ${route.code} (alt. ${nearestAlightRef.shortName})"
            } else {
                "Tramo de ${route.code} más cercano a ${destination.shortName}"
            }

            externalCandidates += EvaluatedRouteCandidate(
                id = "cand-ext-${route.id}",
                kind = EvaluatedCandidateKind.EXTERNAL_FREE_BOARDING,
                route = route,
                routeCode = route.code,
                routeTitle = route.title,
                colorHex = route.colorHex,
                totalDurationMinutes = totalMin,
                totalDistanceMeters = totalMeters,
                walkInitialMinutes = walk1Min,
                walkInitialMeters = dWalk1,
                busWaitMinutes = max(4, route.frequencyMinutes),
                busRideMinutes = busRideMin,
                busRideMeters = busMeters,
                walkFinalMinutes = walk2Min,
                walkFinalMeters = dWalk2,
                boardingStop = null,
                alightingStop = null,
                intermediateStopsCount = 0,
                intermediateStopNames = emptyList(),
                boardingPointName = boardLabel,
                alightingPointName = alightLabel,
                boardingLatitude = subSegment.boardVertex.latitude,
                boardingLongitude = subSegment.boardVertex.longitude,
                alightingLatitude = subSegment.alightVertex.latitude,
                alightingLongitude = subSegment.alightVertex.longitude,
                walkToBoardCoords = listOf(originCoord, subSegment.boardVertex),
                busTransitCoords = subSegment.subCoords,
                walkFinalCoords = if (dWalk2 < 35) emptyList() else listOf(subSegment.alightVertex, destCoord)
            )
        }

        ordinaryCandidates.sortWith(compareBy<EvaluatedRouteCandidate> { it.totalDurationMinutes }.thenBy { it.walkTotalMeters })
        externalCandidates.sortWith(compareBy<EvaluatedRouteCandidate> { it.totalDurationMinutes }.thenBy { it.walkTotalMeters })

        val finalCandidates = mutableListOf<EvaluatedRouteCandidate>()
        var bannerWarning: String? = null

        val bestOrd = ordinaryCandidates.firstOrNull()
        val bestExt = externalCandidates.firstOrNull()

        when {
            directRawMeters <= 280.0 -> {
                finalCandidates += walkCandidate.copy(isRecommendedPrimary = true)
                finalCandidates += ordinaryCandidates
                finalCandidates += externalCandidates
            }
            bestOrd != null -> {
                if (bestExt != null) {
                    val timeDiff = bestOrd.totalDurationMinutes - bestExt.totalDurationMinutes
                    val walkDiff = bestOrd.walkTotalMeters - bestExt.walkTotalMeters
                    if (timeDiff > 10 || walkDiff > 700) {
                        val reason = if (walkDiff > 700) {
                            "Caminarás ${bestExt.walkTotalMeters} m frente a ${bestOrd.walkTotalMeters} m con ${bestOrd.routeCode} (supera umbral 700 m)"
                        } else {
                            "${bestExt.routeCode} tarda ${bestExt.totalDurationMinutes} min vs ${bestOrd.totalDurationMinutes} min (+10 min de diferencia)"
                        }
                        bannerWarning = "${bestExt.routeCode} (Externa) sugerida por umbral: $reason. Abordaje libre en vía, sin QR ni tracking GPS."
                        finalCandidates += bestExt.copy(isRecommendedPrimary = true, externalRecommendationReason = reason)
                        finalCandidates += ordinaryCandidates
                        finalCandidates += externalCandidates.drop(1)
                        finalCandidates += walkCandidate
                    } else {
                        finalCandidates += bestOrd.copy(isRecommendedPrimary = true)
                        finalCandidates += ordinaryCandidates.drop(1)
                        finalCandidates += externalCandidates
                        finalCandidates += walkCandidate
                    }
                } else {
                    finalCandidates += bestOrd.copy(isRecommendedPrimary = true)
                    finalCandidates += ordinaryCandidates.drop(1)
                    finalCandidates += walkCandidate
                }
            }
            bestExt != null -> {
                val noOrdReason = if (activeOrdRoutes.isEmpty()) {
                    "No hay Rutas Ordinarias en servicio en este momento."
                } else {
                    "Ninguna Ruta Ordinaria en servicio pasa cerca de este trayecto."
                }
                bannerWarning = "$noOrdReason Se sugiere ${bestExt.routeCode} (Externa): abordaje libre en vía, sin tracking GPS ni avisos al paradero."
                finalCandidates += bestExt.copy(isRecommendedPrimary = true, externalRecommendationReason = noOrdReason)
                finalCandidates += externalCandidates.drop(1)
                finalCandidates += walkCandidate
            }
            else -> {
                bannerWarning = "Ninguna ruta de bus conecta estos dos puntos. Se muestra el recorrido peatonal."
                finalCandidates += walkCandidate.copy(isRecommendedPrimary = true)
            }
        }

        return RouteAutomationEvaluationResult(
            origin = origin,
            destination = destination,
            candidates = finalCandidates,
            primaryBannerWarning = bannerWarning,
            hasOrdinaryInService = activeOrdRoutes.isNotEmpty()
        )
    }
}


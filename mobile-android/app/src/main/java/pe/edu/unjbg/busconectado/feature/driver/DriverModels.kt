package pe.edu.unjbg.busconectado.feature.driver

enum class FareType(
    val displayName: String,
    val defaultAmountPen: Double,
    val isFree: Boolean = false
) {
    ADULT("PASAJE ADULTO", 1.50),
    STUDENT("UNIVERSITARIO", 0.70),
    CONADIS("CONADIS", 0.00, isFree = true),
    INSUFFICIENT("INSUFICIENTE", 0.00)
}

enum class PaymentMethod(val label: String) {
    APP("Aplicativo Móvil"),
    YAPE_PLIN("Yape / Plin (QR)"),
    POS("Validador POS"),
    CARNET("Pase Libre (Carnet)")
}

data class FareRecord(
    val id: String,
    val timeFormatted: String,
    val fareType: FareType,
    val paymentMethod: PaymentMethod,
    val amountFormatted: String,
    val isSuccess: Boolean
)

data class VehicleSensorsState(
    val hasFault: Boolean = false,
    val pressurePsi: Int = 32,
    val doorsClosed: Boolean = true,
    val faultDescription: String = "Puertas cerradas • Presión OK"
)

data class DriverShiftState(
    val isAuthenticated: Boolean = false,
    val isLoggingIn: Boolean = false,
    val loginError: String? = null,
    val driverDni: String = "",
    val busId: String = "",
    val routeLine: String = "",
    val plate: String = "",
    val driverName: String = "",
    val occupancy: Int = 0,
    val maxCapacity: Int = 35,
    val appTrips: Int = 0,
    val conadisCount: Int = 0,
    val totalRevenuePen: Double = 0.0,
    val isPublicMapPaused: Boolean = false,
    val isPosPaymentEnabled: Boolean = false,
    val currentStopIndex: Int = 0,
    val stopsList: List<String> = emptyList(),
    val lastFare: FareRecord? = null,
    val recentFares: List<FareRecord> = emptyList(),
    val sensors: VehicleSensorsState = VehicleSensorsState()
) {
    val occupancyPercentage: Float
        get() = (occupancy.toFloat() / maxCapacity.toFloat()).coerceIn(0f, 1f)

    val currentStopName: String
        get() = stopsList.getOrElse(currentStopIndex) { "Sin paraderos" }

    val nextStopName: String
        get() = if (stopsList.isEmpty()) "Sin paraderos" else stopsList.getOrElse((currentStopIndex + 1) % stopsList.size) { "Sin paraderos" }
}


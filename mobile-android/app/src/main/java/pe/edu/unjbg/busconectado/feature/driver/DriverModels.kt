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
    val busId: String = "BUS 01",
    val routeLine: String = "10",
    val plate: String = "Z1A-780",
    val driverName: String = "Juan Mamani Quispe",
    val occupancy: Int = 22,
    val maxCapacity: Int = 32,
    val appTrips: Int = 48,
    val conadisCount: Int = 3,
    val totalRevenuePen: Double = 58.40,
    val isPublicMapPaused: Boolean = false,
    val currentStopIndex: Int = 0,
    val stopsList: List<String> = listOf(
        "P. Cono Norte",
        "P. Plaza Zela",
        "P. Mercado Central",
        "P. Av. Bolognesi",
        "P. UNJBG",
        "P. Terminal Terrestre",
        "P. Alto de la Alianza"
    ),
    val lastFare: FareRecord? = FareRecord(
        id = "init-1",
        timeFormatted = "19:24:12",
        fareType = FareType.STUDENT,
        paymentMethod = PaymentMethod.APP,
        amountFormatted = "S/. 0.70",
        isSuccess = true
    ),
    val recentFares: List<FareRecord> = listOf(
        FareRecord("f-1", "19:24:12", FareType.STUDENT, PaymentMethod.APP, "S/. 0.70", true),
        FareRecord("f-2", "19:22:45", FareType.ADULT, PaymentMethod.YAPE_PLIN, "S/. 1.50", true),
        FareRecord("f-3", "19:21:10", FareType.CONADIS, PaymentMethod.CARNET, "S/. 0.00", true),
        FareRecord("f-4", "19:20:18", FareType.INSUFFICIENT, PaymentMethod.APP, "NO PASA", false),
        FareRecord("f-5", "19:18:02", FareType.ADULT, PaymentMethod.POS, "S/. 1.50", true)
    ),
    val sensors: VehicleSensorsState = VehicleSensorsState()
) {
    val occupancyPercentage: Float
        get() = (occupancy.toFloat() / maxCapacity.toFloat()).coerceIn(0f, 1f)

    val currentStopName: String
        get() = stopsList.getOrElse(currentStopIndex) { "P. Cono Norte" }

    val nextStopName: String
        get() = stopsList.getOrElse((currentStopIndex + 1) % stopsList.size) { "P. Plaza Zela" }
}


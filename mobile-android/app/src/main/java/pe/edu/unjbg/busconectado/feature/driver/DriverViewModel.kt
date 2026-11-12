package pe.edu.unjbg.busconectado.feature.driver

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

class DriverViewModel(
    private val audioBuzzer: DriverAudioBuzzer = DriverAudioBuzzer()
) : ViewModel() {

    private val _uiState = MutableStateFlow(DriverShiftState())
    val uiState: StateFlow<DriverShiftState> = _uiState.asStateFlow()

    private val timeFormat = SimpleDateFormat("HH:mm:ss", Locale.getDefault())

    /**
     * Valida y registra un pasaje en la tablet, actualizando el banner y el feed.
     */
    fun simulateFare(
        type: FareType,
        method: PaymentMethod,
        customAmount: String? = null
    ) {
        val nowStr = timeFormat.format(Date())
        val isSuccess = type != FareType.INSUFFICIENT
        val amountStr = customAmount ?: when (type) {
            FareType.ADULT -> "S/. 1.50"
            FareType.STUDENT -> "S/. 0.70"
            FareType.CONADIS -> "S/. 0.00"
            FareType.INSUFFICIENT -> "NO PASA"
        }

        val record = FareRecord(
            id = UUID.randomUUID().toString(),
            timeFormatted = nowStr,
            fareType = type,
            paymentMethod = method,
            amountFormatted = amountStr,
            isSuccess = isSuccess
        )

        // Reproducir el sonido correspondiente
        if (isSuccess) {
            audioBuzzer.playSuccessBeep()
        } else {
            audioBuzzer.playErrorBuzzer()
        }

        _uiState.update { current ->
            val newRevenue = if (isSuccess) {
                current.totalRevenuePen + type.defaultAmountPen
            } else current.totalRevenuePen

            val newAppTrips = if (isSuccess && method == PaymentMethod.APP) {
                current.appTrips + 1
            } else current.appTrips

            val newOccupancy = if (isSuccess) {
                (current.occupancy + 1).coerceAtMost(current.maxCapacity)
            } else current.occupancy

            current.copy(
                lastFare = record,
                recentFares = listOf(record) + current.recentFares.take(25),
                occupancy = newOccupancy,
                appTrips = newAppTrips,
                totalRevenuePen = newRevenue
            )
        }
    }

    /**
     * Registra un pasaje libre CONADIS desde el botón físico de cabina (+1 aforo, S/. 0.00).
     */
    fun recordConadis() {
        simulateFare(FareType.CONADIS, PaymentMethod.CARNET, "S/. 0.00")
        _uiState.update { it.copy(conadisCount = it.conadisCount + 1) }
    }

    /**
     * Ajuste manual rápido de aforo (+1 o -1 pasajero en paradero).
     */
    fun adjustOccupancy(delta: Int) {
        _uiState.update { current ->
            val updated = (current.occupancy + delta).coerceIn(0, current.maxCapacity)
            current.copy(occupancy = updated)
        }
    }

    /**
     * Avanza al siguiente paradero de la ruta de Línea 10.
     */
    fun advanceStop() {
        _uiState.update { current ->
            val nextIdx = (current.currentStopIndex + 1) % current.stopsList.size
            current.copy(currentStopIndex = nextIdx)
        }
    }

    /**
     * Simula advertencia de sensores vehiculares (CAN-Bus / OBD-II).
     */
    fun toggleVehicleFault() {
        _uiState.update { current ->
            val currentFault = current.sensors.hasFault
            val newFault = !currentFault
            val newSensors = if (newFault) {
                VehicleSensorsState(
                    hasFault = true,
                    pressurePsi = 18,
                    doorsClosed = true,
                    faultDescription = "¡ADVERTENCIA ACTIVA! (Baja presión neumático: 18 PSI)"
                )
            } else {
                VehicleSensorsState(
                    hasFault = false,
                    pressurePsi = 32,
                    doorsClosed = true,
                    faultDescription = "Puertas cerradas • Presión OK"
                )
            }
            current.copy(sensors = newSensors)
        }
    }

    /**
     * Activa o desactiva la pausa en el mapa público (CU-04 / CU-04.A).
     */
    fun togglePausePublicMap() {
        _uiState.update { it.copy(isPublicMapPaused = !it.isPublicMapPaused) }
    }

    /**
     * Actualiza el catálogo de paraderos en vivo (conectado a backend o API).
     */
    fun updateStopsList(newStops: List<String>) {
        if (newStops.isNotEmpty()) {
            _uiState.update { it.copy(stopsList = newStops) }
        }
    }
}


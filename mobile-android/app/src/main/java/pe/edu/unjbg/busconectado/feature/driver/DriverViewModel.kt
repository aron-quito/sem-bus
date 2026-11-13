package pe.edu.unjbg.busconectado.feature.driver

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import java.util.concurrent.TimeUnit

class DriverViewModel @JvmOverloads constructor(
    private val audioBuzzer: DriverAudioBuzzer = DriverAudioBuzzer()
) : ViewModel() {

    private val _uiState = MutableStateFlow(DriverShiftState())
    val uiState: StateFlow<DriverShiftState> = _uiState.asStateFlow()

    private val timeFormat = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
    private val baseUrl = "https://34.30.86.129.sslip.io"
    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(12, TimeUnit.SECONDS)
        .dns(object : okhttp3.Dns {
            override fun lookup(hostname: String): List<java.net.InetAddress> {
                return try {
                    okhttp3.Dns.SYSTEM.lookup(hostname)
                } catch (e: Exception) {
                    if (hostname == "34.30.86.129.sslip.io") {
                        listOf(java.net.InetAddress.getByAddress(hostname, byteArrayOf(34, 30, 86.toByte(), 129.toByte())))
                    } else {
                        throw e
                    }
                }
            }
        })
        .build()
    private val seenTxIds = mutableSetOf<String>()
    private var hasSeededTransactions = false
    private var driverToken: String = ""
    private var appContext: android.content.Context? = null

    fun attachContext(context: android.content.Context) {
        if (appContext != null) return
        appContext = context.applicationContext
        val prefs = appContext?.getSharedPreferences("driver_session_prefs", android.content.Context.MODE_PRIVATE) ?: return
        val savedDni = prefs.getString("dni", null)
        val savedToken = prefs.getString("token", null)
        if (!savedDni.isNullOrBlank() && !savedToken.isNullOrBlank() && !_uiState.value.isAuthenticated) {
            driverToken = savedToken
            _uiState.update {
                it.copy(
                    isAuthenticated = true,
                    driverDni = savedDni,
                    driverName = prefs.getString("name", "Chofer") ?: "Chofer",
                    busId = prefs.getString("busId", "UNI-1408") ?: "UNI-1408",
                    plate = prefs.getString("plate", "Z4B-812") ?: "Z4B-812",
                    routeLine = prefs.getString("routeLine", "Ruta 14") ?: "Ruta 14",
                    isPosPaymentEnabled = prefs.getBoolean("posEnabled", false)
                )
            }
            startLivePosSync()
        }
    }

    fun loginDriver(dni: String, pin: String) {
        if (_uiState.value.isLoggingIn) return
        val cleanDni = dni.trim()
        val cleanPin = pin.trim()
        if (cleanDni.length != 8) {
            _uiState.update { it.copy(loginError = "Ingresa un DNI válido de 8 dígitos") }
            return
        }
        if (cleanPin.isEmpty()) {
            _uiState.update { it.copy(loginError = "Ingresa el PIN de enlace") }
            return
        }
        _uiState.update { it.copy(isLoggingIn = true, loginError = null) }

        viewModelScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching {
                    val bodyJson = JSONObject().apply {
                        put("dni", dni.trim())
                        put("pin", pin.trim())
                    }.toString()
                    val req = Request.Builder()
                        .url("$baseUrl/api/v1/driver/login")
                        .post(bodyJson.toRequestBody("application/json; charset=utf-8".toMediaType()))
                        .build()
                    httpClient.newCall(req).execute().use { resp ->
                        val raw = resp.body?.string().orEmpty()
                        val json = JSONObject(raw)
                        if (!resp.isSuccessful || (json.optString("status") != "SUCCESS" && !json.optBoolean("success", false))) {
                            throw IllegalStateException(json.optString("error").ifBlank { "DNI o PIN inválido" })
                        }
                        driverToken = json.optString("token", "")
                        json.getJSONObject("driver")
                    }
                }
            }

            result.onSuccess { drv ->
                val dDni = drv.optString("dni", dni.trim())
                val dName = drv.optString("name", "Chofer")
                val dUnit = drv.optString("unit_code", "UNI-1408")
                val dPlate = drv.optString("plate", "Z4B-812")
                val dRoute = drv.optString("route_code", "Ruta 14")
                appContext?.getSharedPreferences("driver_session_prefs", android.content.Context.MODE_PRIVATE)
                    ?.edit()
                    ?.putString("dni", dDni)
                    ?.putString("name", dName)
                    ?.putString("busId", dUnit)
                    ?.putString("plate", dPlate)
                    ?.putString("routeLine", dRoute)
                    ?.putString("token", driverToken)
                    ?.putBoolean("posEnabled", false)
                    ?.apply()
                _uiState.update {
                    it.copy(
                        isAuthenticated = true,
                        isLoggingIn = false,
                        loginError = null,
                        isPosPaymentEnabled = false,
                        driverDni = dDni,
                        driverName = dName,
                        busId = dUnit,
                        plate = dPlate,
                        routeLine = dRoute
                    )
                }
                startLivePosSync()
            }.onFailure { err ->
                _uiState.update {
                    it.copy(isLoggingIn = false, loginError = err.localizedMessage ?: "Error de conexión")
                }
            }
        }
    }

    fun logoutDriver(reason: String? = null) {
        val currentDni = _uiState.value.driverDni
        val currentToken = driverToken
        driverToken = ""
        seenTxIds.clear()
        hasSeededTransactions = false
        appContext?.getSharedPreferences("driver_session_prefs", android.content.Context.MODE_PRIVATE)?.edit()?.clear()?.apply()
        _uiState.update {
            DriverShiftState(
                isAuthenticated = false,
                loginError = reason
            )
        }
        if (currentDni.isNotBlank()) {
            viewModelScope.launch(Dispatchers.IO) {
                runCatching {
                    val body = JSONObject().apply {
                        put("dni", currentDni)
                        put("token", currentToken)
                    }.toString()
                    val req = Request.Builder()
                        .url("$baseUrl/api/v1/driver/logout")
                        .post(body.toRequestBody("application/json; charset=utf-8".toMediaType()))
                        .build()
                    httpClient.newCall(req).execute().close()
                }
            }
        }
    }

    private fun startLivePosSync() {
        viewModelScope.launch {
            while (_uiState.value.isAuthenticated) {
                val sessionValid = withContext(Dispatchers.IO) {
                    runCatching {
                        val dniParam = _uiState.value.driverDni
                        val req = Request.Builder()
                            .url("$baseUrl/api/v1/driver/session/status?dni=$dniParam&token=$driverToken")
                            .get()
                            .build()
                        httpClient.newCall(req).execute().use { resp ->
                            if (!resp.isSuccessful) true
                            else {
                                val json = JSONObject(resp.body?.string() ?: "{}")
                                val active = json.optBoolean("active", true)
                                val disabled = json.optBoolean("disabled", false)
                                active && !disabled
                            }
                        }
                    }.getOrDefault(true)
                }
                if (!sessionValid) {
                    logoutDriver("Sesión cerrada o usuario deshabilitado desde el Panel Administrador.")
                    break
                }

                val unit = _uiState.value.busId
                val txs = withContext(Dispatchers.IO) {
                    runCatching {
                        val req = Request.Builder().url("$baseUrl/api/v1/admin/transactions?unit=$unit").get().build()
                        httpClient.newCall(req).execute().use { resp ->
                            if (!resp.isSuccessful) emptyList()
                            else {
                                val arr = JSONArray(resp.body?.string() ?: "[]")
                                (0 until arr.length()).map { arr.getJSONObject(it) }
                            }
                        }
                    }.getOrDefault(emptyList())
                }
                val backendOccupancy = withContext(Dispatchers.IO) {
                    runCatching {
                        val req = Request.Builder().url("$baseUrl/api/v1/admin/drivers/sessions").get().build()
                        httpClient.newCall(req).execute().use { resp ->
                            if (!resp.isSuccessful) null
                            else {
                                val json = JSONObject(resp.body?.string() ?: "{}")
                                val occObj = json.optJSONObject("occupancy")
                                if (occObj != null && occObj.has(unit)) occObj.optInt(unit, -1).takeIf { it >= 0 } else null
                            }
                        }
                    }.getOrNull()
                }
                val matching = txs.filter { it.optString("unit_code").equals(unit, ignoreCase = true) || unit.isBlank() }
                    .take(20)
                    .reversed()
                if (!hasSeededTransactions) {
                    val seededRecords = mutableListOf<FareRecord>()
                    for (tx in matching) {
                        val txId = tx.optString("id").ifBlank { tx.optString("order_id") + tx.optString("timestamp") }
                        val idemKey = tx.optString("idempotency_key")
                        if (idemKey.isNotBlank()) seenTxIds.add(idemKey)
                        seenTxIds.add(txId)
                        val fareLabel = tx.optString("fare_label")
                        val methodRaw = tx.optString("payment_method")
                        val amt = tx.optDouble("amount_pen", 1.50)
                        val fareType = when {
                            fareLabel.contains("CONADIS", true) || methodRaw == "CONADIS" -> FareType.CONADIS
                            fareLabel.contains("Univ", true) || amt in 0.69..0.71 -> FareType.STUDENT
                            else -> FareType.ADULT
                        }
                        val payMethod = when {
                            methodRaw.contains("YAPE", true) -> PaymentMethod.YAPE_PLIN
                            methodRaw.contains("CONADIS", true) -> PaymentMethod.CARNET
                            else -> PaymentMethod.APP
                        }
                        seededRecords.add(
                            0,
                            FareRecord(
                                id = txId,
                                timeFormatted = tx.optString("timestamp").takeLast(8).ifBlank { timeFormat.format(Date()) },
                                fareType = fareType,
                                paymentMethod = payMethod,
                                amountFormatted = String.format(Locale.US, "S/. %.2f", amt),
                                isSuccess = true
                            )
                        )
                    }
                    hasSeededTransactions = true
                    _uiState.update { cur ->
                        cur.copy(
                            recentFares = if (seededRecords.isNotEmpty()) seededRecords else cur.recentFares,
                            lastFare = seededRecords.firstOrNull() ?: cur.lastFare,
                            occupancy = backendOccupancy ?: cur.occupancy
                        )
                    }
                } else {
                    for (tx in matching) {
                        val txId = tx.optString("id").ifBlank { tx.optString("order_id") + tx.optString("timestamp") }
                        val idemKey = tx.optString("idempotency_key")
                        val isNewId = seenTxIds.add(txId)
                        val isNewIdem = idemKey.isBlank() || seenTxIds.add(idemKey)
                        if (isNewId && isNewIdem) {
                            val fareLabel = tx.optString("fare_label")
                            val methodRaw = tx.optString("payment_method")
                            val amt = tx.optDouble("amount_pen", 1.50)
                            val fareType = when {
                                fareLabel.contains("CONADIS", true) || methodRaw == "CONADIS" -> FareType.CONADIS
                                fareLabel.contains("Univ", true) || amt in 0.69..0.71 -> FareType.STUDENT
                                else -> FareType.ADULT
                            }
                            val payMethod = when {
                                methodRaw.contains("YAPE", true) -> PaymentMethod.YAPE_PLIN
                                methodRaw.contains("CONADIS", true) -> PaymentMethod.CARNET
                                else -> PaymentMethod.APP
                            }
                            simulateFare(fareType, payMethod, String.format(Locale.US, "S/. %.2f", amt))
                        }
                    }
                    if (backendOccupancy != null) {
                        _uiState.update { cur -> cur.copy(occupancy = backendOccupancy.coerceIn(0, cur.maxCapacity)) }
                    }
                }
                delay(2500L)
            }
        }
    }

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

    private var lastConadisTapMs: Long = 0L

    /**
     * Registra un pasaje libre CONADIS desde el botón físico de cabina (+1 aforo, S/. 0.00).
     */
    fun recordConadis() {
        val nowMs = System.currentTimeMillis()
        if (nowMs - lastConadisTapMs < 1500L) return
        lastConadisTapMs = nowMs

        val idemKey = "cnd-${UUID.randomUUID()}"
        seenTxIds.add(idemKey)

        simulateFare(FareType.CONADIS, PaymentMethod.CARNET, "S/. 0.00")
        _uiState.update { it.copy(conadisCount = it.conadisCount + 1) }
        val s = _uiState.value
        viewModelScope.launch(Dispatchers.IO) {
            runCatching {
                val body = JSONObject().apply {
                    put("driver_dni", s.driverDni.ifBlank { "43892110" })
                    put("unit_code", s.busId)
                    put("route_code", s.routeLine)
                    put("stop_name", s.currentStopName)
                    put("idempotency_key", idemKey)
                }.toString()
                val req = Request.Builder()
                    .url("$baseUrl/api/v1/driver/boardings/conadis")
                    .post(body.toRequestBody("application/json; charset=utf-8".toMediaType()))
                    .build()
                httpClient.newCall(req).execute().use { resp ->
                    val raw = resp.body?.string().orEmpty()
                    val txId = runCatching { JSONObject(raw).optString("id") }.getOrDefault("")
                    if (txId.isNotBlank()) seenTxIds.add(txId)
                }
            }
        }
    }

    /**
     * Ajuste manual rápido de aforo (+1 o -1 pasajero en paradero).
     */
    fun adjustOccupancy(delta: Int) {
        var updatedValue = 0
        _uiState.update { current ->
            val updated = (current.occupancy + delta).coerceIn(0, current.maxCapacity)
            updatedValue = updated
            current.copy(occupancy = updated)
        }
        val unitCode = _uiState.value.busId
        if (unitCode.isNotBlank()) {
            viewModelScope.launch(Dispatchers.IO) {
                runCatching {
                    val body = JSONObject().apply {
                        put("unit_code", unitCode)
                        put("passengers", updatedValue)
                    }.toString()
                    val req = Request.Builder()
                        .url("$baseUrl/api/v1/driver/occupancy")
                        .post(body.toRequestBody("application/json; charset=utf-8".toMediaType()))
                        .build()
                    httpClient.newCall(req).execute().close()
                }
            }
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

    fun togglePosPayment() {
        val nextEnabled = !_uiState.value.isPosPaymentEnabled
        val dni = _uiState.value.driverDni
        val unit = _uiState.value.busId
        val name = _uiState.value.driverName
        _uiState.update { it.copy(isPosPaymentEnabled = nextEnabled) }
        appContext?.getSharedPreferences("driver_session_prefs", android.content.Context.MODE_PRIVATE)
            ?.edit()?.putBoolean("posEnabled", nextEnabled)?.apply()
        if (dni.isNotBlank()) {
            viewModelScope.launch(Dispatchers.IO) {
                runCatching {
                    val body = JSONObject().apply {
                        put("dni", dni)
                        put("enabled", nextEnabled)
                        put("unit_code", unit)
                        put("name", name)
                    }.toString()
                    val req = Request.Builder()
                        .url("$baseUrl/api/v1/driver/pos/toggle")
                        .post(body.toRequestBody("application/json; charset=utf-8".toMediaType()))
                        .build()
                    httpClient.newCall(req).execute().close()
                }
            }
        }
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


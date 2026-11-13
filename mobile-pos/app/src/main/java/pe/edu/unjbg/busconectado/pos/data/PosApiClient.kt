package pe.edu.unjbg.busconectado.pos.data

import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import okhttp3.Dns
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.POST
import retrofit2.http.Path
import java.net.InetAddress
import java.util.concurrent.TimeUnit
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

data class PosOrderCreateRequest(
    @SerializedName("unit_code") val unitCode: String = "UNI-1408",
    @SerializedName("plate") val plate: String = "Z4B-812",
    @SerializedName("route_code") val routeCode: String = "RUTA 14",
    @SerializedName("fixed_amount_points") val fixedAmountPoints: Int = 15
)

data class PosOrderResponse(
    @SerializedName("order_id") val orderId: String,
    @SerializedName("unit_code") val unitCode: String,
    @SerializedName("plate") val plate: String,
    @SerializedName("route_code") val routeCode: String,
    @SerializedName("status") val status: String,
    @SerializedName("amount_points") val amountPoints: Int,
    @SerializedName("amount_pen") val amountPen: Double,
    @SerializedName("ttl_seconds") val ttlSeconds: Int,
    @SerializedName("expires_at") val expiresAt: String,
    @SerializedName("app_qr_payload") val appQrPayload: String,
    @SerializedName("yape_qr_payload") val yapeQrPayload: String,
    @SerializedName("ws_path") val wsPath: String,
    @SerializedName("yape_commission_rate") val yapeCommissionRate: Double,
    @SerializedName("yape_commission_pen") val yapeCommissionPen: Double,
    @SerializedName("yape_net_pen") val yapeNetPen: Double,
    @SerializedName("app_commission_pen") val appCommissionPen: Double,
    @SerializedName("app_net_pen") val appNetPen: Double
)

data class PosOrderStatusResponse(
    @SerializedName("order_id") val orderId: String,
    @SerializedName("unit_code") val unitCode: String,
    @SerializedName("route_code") val routeCode: String,
    @SerializedName("status") val status: String,
    @SerializedName("payment_method") val paymentMethod: String? = null,
    @SerializedName("fare_label") val fareLabel: String? = null,
    @SerializedName("companions_count") val companionsCount: Int = 0,
    @SerializedName("amount_points") val amountPoints: Int,
    @SerializedName("amount_pen") val amountPen: Double,
    @SerializedName("commission_pen") val commissionPen: Double = 0.0,
    @SerializedName("net_pen") val netPen: Double = 0.0,
    @SerializedName("paid_at") val paidAt: String? = null,
    @SerializedName("expires_at") val expiresAt: String
)

data class PosWsEvent(
    @SerializedName("event") val event: String = "",
    @SerializedName("order_id") val orderId: String = "",
    @SerializedName("status") val status: String = "",
    @SerializedName("payment_method") val paymentMethod: String? = null,
    @SerializedName("fare_label") val fareLabel: String? = null,
    @SerializedName("companions_count") val companionsCount: Int = 0,
    @SerializedName("amount_points") val amountPoints: Int = 0,
    @SerializedName("amount_pen") val amountPen: Double = 0.0,
    @SerializedName("commission_pen") val commissionPen: Double = 0.0,
    @SerializedName("net_pen") val netPen: Double = 0.0
)

data class PosNfcTapRequest(
    @SerializedName("order_id") val orderId: String,
    @SerializedName("card_uid") val cardUid: String,
    @SerializedName("companions_count") val companionsCount: Int = 0
)

data class PosTelemetryRequest(
    @SerializedName("unit_code") val unitCode: String = "UNI-1408",
    @SerializedName("plate") val plate: String = "Z4B-812",
    @SerializedName("route_code") val routeCode: String = "Ruta 14",
    @SerializedName("latitude") val latitude: Double,
    @SerializedName("longitude") val longitude: Double,
    @SerializedName("speed_kmh") val speedKmh: Double = 26.0,
    @SerializedName("heading") val heading: Double = 0.0
)

data class DriverLoginRequest(
    @SerializedName("dni") val dni: String,
    @SerializedName("pin") val pin: String
)

data class DriverLoginInfo(
    @SerializedName("id") val id: String? = null,
    @SerializedName("name") val name: String,
    @SerializedName("dni") val dni: String,
    @SerializedName("brevete") val brevete: String? = null,
    @SerializedName("unit_code") val unitCode: String,
    @SerializedName("plate") val plate: String,
    @SerializedName("route_code") val routeCode: String
)

data class DriverPosInfo(
    @SerializedName("pos_id") val posId: String? = null,
    @SerializedName("pairing_code") val pairingCode: String? = null
)

data class DriverLoginResponse(
    @SerializedName("status") val status: String? = null,
    @SerializedName("token") val token: String? = null,
    @SerializedName("driver") val driver: DriverLoginInfo? = null,
    @SerializedName("pos") val pos: DriverPosInfo? = null,
    @SerializedName("error") val error: String? = null
)

interface PosApiService {
    @POST("api/v1/pos/orders")
    suspend fun createOrder(
        @Header("X-POS-Device-Id") deviceId: String,
        @Header("X-POS-Secret") deviceSecret: String,
        @Body body: PosOrderCreateRequest
    ): PosOrderResponse

    @GET("api/v1/pos/orders/{order_id}")
    suspend fun getOrderStatus(
        @Header("X-POS-Device-Id") deviceId: String,
        @Header("X-POS-Secret") deviceSecret: String,
        @Path("order_id") orderId: String
    ): PosOrderStatusResponse

    @POST("api/v1/pos/orders/{order_id}/cancel")
    suspend fun cancelOrder(
        @Header("X-POS-Device-Id") deviceId: String,
        @Header("X-POS-Secret") deviceSecret: String,
        @Path("order_id") orderId: String
    ): PosOrderStatusResponse

    @POST("api/v1/pos/nfc-tap")
    suspend fun submitNfcTap(
        @Header("X-POS-Device-Id") deviceId: String,
        @Header("X-POS-Secret") deviceSecret: String,
        @Body body: PosNfcTapRequest
    ): PosOrderStatusResponse

    @POST("api/v1/pos/telemetry")
    suspend fun sendTelemetry(
        @Header("X-POS-Device-Id") deviceId: String,
        @Header("X-POS-Secret") deviceSecret: String,
        @Body body: PosTelemetryRequest
    ): retrofit2.Response<Map<String, Any>>

    @POST("api/v1/driver/login")
    suspend fun driverLogin(
        @Body body: DriverLoginRequest
    ): DriverLoginResponse
}

object PosCommissionCalculator {
    const val FLAT_FARE_POINTS = 15
    const val FLAT_FARE_PEN = 1.50
    const val YAPE_EMPRESA_RATE = 0.0295

    fun yapeCommissionPen(grossPen: Double): Double {
        return kotlin.math.round(grossPen * YAPE_EMPRESA_RATE * 100.0) / 100.0
    }

    fun yapeNetPen(grossPen: Double): Double {
        return kotlin.math.round((grossPen - yapeCommissionPen(grossPen)) * 100.0) / 100.0
    }

    fun appDoorNetPen(grossPen: Double): Double = kotlin.math.round(grossPen * 100.0) / 100.0
}

class PosNetworkRepository(
    private val baseUrl: String = DEFAULT_BASE_URL,
    private var deviceId: String = DEFAULT_DEVICE_ID,
    private val deviceSecret: String = DEFAULT_DEVICE_SECRET
) {
    var activeUnitCode: String = "UNI-1408"
        private set
    var activePlate: String = "Z4B-812"
        private set
    var activeRouteCode: String = "Ruta 14"
        private set
    var activeDriver: DriverLoginInfo? = null
        private set

    companion object {
        const val DEFAULT_BASE_URL = "https://34.30.86.129.sslip.io/"
        const val DEFAULT_DEVICE_ID = "POS-UNI-1408"
        const val DEFAULT_DEVICE_SECRET = "dev_pos_terminal_secret_bus_conectado_tacna_2026"
        const val DEV_YAPE_WEBHOOK_SECRET = "test_yape_webhook_secret_bcp"
    }

    private val gson = Gson()
    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .dns(object : Dns {
            override fun lookup(hostname: String): List<InetAddress> {
                return try {
                    Dns.SYSTEM.lookup(hostname)
                } catch (e: Exception) {
                    if (hostname == "34.30.86.129.sslip.io") {
                        listOf(InetAddress.getByAddress(hostname, byteArrayOf(34, 30, 86.toByte(), 129.toByte())))
                    } else {
                        throw e
                    }
                }
            }
        })
        .build()

    private val api: PosApiService = Retrofit.Builder()
        .baseUrl(baseUrl)
        .client(httpClient)
        .addConverterFactory(GsonConverterFactory.create(gson))
        .build()
        .create(PosApiService::class.java)

    var activeDriverToken: String? = null
        private set

    fun restoreSession(
        id: String,
        dni: String,
        name: String,
        unitCode: String,
        plate: String,
        routeCode: String,
        token: String,
        posId: String
    ) {
        activeDriver = DriverLoginInfo(
            id = id,
            name = name,
            dni = dni,
            unitCode = unitCode,
            plate = plate,
            routeCode = routeCode
        )
        activeDriverToken = token
        activeUnitCode = unitCode
        activePlate = plate
        activeRouteCode = routeCode
        if (posId.isNotBlank()) deviceId = posId
    }

    suspend fun loginDriver(dni: String, pin: String): Result<DriverLoginResponse> = runCatching {
        val resp = try {
            api.driverLogin(DriverLoginRequest(dni = dni.trim(), pin = pin.trim()))
        } catch (httpEx: retrofit2.HttpException) {
            val rawErr = httpEx.response()?.errorBody()?.string().orEmpty()
            val parsedMsg = runCatching { org.json.JSONObject(rawErr).optString("error") }.getOrNull()
            throw IllegalStateException(parsedMsg?.takeIf { it.isNotBlank() } ?: "DNI o PIN no registrado")
        }
        val drv = resp.driver ?: throw IllegalStateException(resp.error ?: "Credenciales inválidas")
        activeDriver = drv
        activeDriverToken = resp.token
        activeUnitCode = drv.unitCode
        activePlate = drv.plate
        activeRouteCode = drv.routeCode
        resp.pos?.posId?.takeIf { it.isNotBlank() }?.let { deviceId = it }
        resp
    }

    fun logoutDriver() {
        val dni = activeDriver?.dni
        activeDriver = null
        activeDriverToken = null
        if (!dni.isNullOrBlank()) {
            runCatching {
                val body = """{"dni":"$dni"}""".toRequestBody("application/json; charset=utf-8".toMediaType())
                val req = Request.Builder().url("${baseUrl}api/v1/driver/logout").post(body).build()
                httpClient.newCall(req).execute().close()
            }
        }
    }

    fun fetchSessionStatus(): Pair<Boolean, Boolean> {
        val dni = activeDriver?.dni ?: return (false to false)
        val tok = activeDriverToken ?: return (false to false)
        return runCatching {
            val req = Request.Builder().url("${baseUrl}api/v1/driver/session/status?dni=$dni&token=$tok").get().build()
            httpClient.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) return@use (true to false)
                val raw = resp.body?.string().orEmpty()
                val json = org.json.JSONObject(raw)
                val active = json.optBoolean("active", true) && json.optBoolean("enabled", true)
                val posEnabled = json.optBoolean("pos_enabled", false)
                (active to posEnabled)
            }
        }.getOrDefault(true to false)
    }

    suspend fun createFlatFareOrder(
        unitCode: String = activeUnitCode,
        plate: String = activePlate,
        routeCode: String = activeRouteCode,
        points: Int = PosCommissionCalculator.FLAT_FARE_POINTS
    ): Result<PosOrderResponse> = runCatching {
        api.createOrder(
            deviceId = deviceId,
            deviceSecret = deviceSecret,
            body = PosOrderCreateRequest(
                unitCode = unitCode,
                plate = plate,
                routeCode = routeCode,
                fixedAmountPoints = points
            )
        )
    }

    suspend fun getOrderStatus(orderId: String): Result<PosOrderStatusResponse> = runCatching {
        api.getOrderStatus(deviceId = deviceId, deviceSecret = deviceSecret, orderId = orderId)
    }

    suspend fun cancelOrder(orderId: String): Result<PosOrderStatusResponse> = runCatching {
        api.cancelOrder(deviceId = deviceId, deviceSecret = deviceSecret, orderId = orderId)
    }

    suspend fun submitNfcTap(orderId: String, cardUid: String): Result<PosOrderStatusResponse> = runCatching {
        api.submitNfcTap(
            deviceId = deviceId,
            deviceSecret = deviceSecret,
            body = PosNfcTapRequest(orderId = orderId, cardUid = cardUid)
        )
    }

    suspend fun sendTelemetry(lat: Double, lng: Double, speed: Double = 26.0, heading: Double = 0.0): Result<Boolean> = runCatching {
        val resp = api.sendTelemetry(
            deviceId = deviceId,
            deviceSecret = deviceSecret,
            body = PosTelemetryRequest(
                unitCode = activeUnitCode,
                plate = activePlate,
                routeCode = activeRouteCode,
                latitude = lat,
                longitude = lng,
                speedKmh = speed,
                heading = heading
            )
        )
        resp.isSuccessful
    }

    /**
     * Dispara un webhook firmado HMAC-SHA256 de prueba (simula llegada de confirmación Yape Empresas).
     */
    fun triggerSignedTestYapeWebhook(orderId: String, unitCode: String, amountPen: Double): Result<Boolean> = runCatching {
        val opCode = "YAPE-${System.currentTimeMillis()}"
        val bodyJson = """{"order_id":"$orderId","unit_code":"$unitCode","amount_pen":$amountPen,"operation_code":"$opCode"}"""
        val sig = hmacSha256Hex(bodyJson, DEV_YAPE_WEBHOOK_SECRET)
        val req = Request.Builder()
            .url("${baseUrl}api/v1/pos/webhooks/yape-empresa")
            .header("X-Yape-Signature", sig)
            .post(bodyJson.toRequestBody("application/json; charset=utf-8".toMediaType()))
            .build()
        httpClient.newCall(req).execute().use { resp ->
            resp.isSuccessful
        }
    }

    fun openOrderWebSocket(
        orderId: String,
        onEvent: (PosWsEvent) -> Unit,
        onFailure: () -> Unit
    ): WebSocket {
        val wsUrl = baseUrl
            .replace("https://", "wss://")
            .replace("http://", "ws://") +
            "api/v1/pos/ws/$orderId?token=$deviceSecret"

        val request = Request.Builder().url(wsUrl).build()
        return httpClient.newWebSocket(request, object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                try {
                    val evt = gson.fromJson(text, PosWsEvent::class.java)
                    onEvent(evt)
                } catch (_: Exception) {
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                onFailure()
            }
        })
    }

    private fun hmacSha256Hex(payload: String, secret: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret.toByteArray(Charsets.UTF_8), "HmacSHA256"))
        return mac.doFinal(payload.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    }
}


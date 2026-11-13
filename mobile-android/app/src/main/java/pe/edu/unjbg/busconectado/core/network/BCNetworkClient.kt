package pe.edu.unjbg.busconectado.core.network

import com.google.gson.Gson
import com.google.gson.JsonArray
import com.google.gson.JsonObject
import com.google.gson.annotations.SerializedName
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.logging.HttpLoggingInterceptor
import pe.edu.unjbg.busconectado.core.location.GeoPointData
import pe.edu.unjbg.busconectado.core.location.LocationService
import pe.edu.unjbg.busconectado.core.model.ActiveBusModel
import pe.edu.unjbg.busconectado.core.model.BusRouteModel
import pe.edu.unjbg.busconectado.core.model.BusStopModel
import pe.edu.unjbg.busconectado.core.model.TacnaDestinationPlace
import pe.edu.unjbg.busconectado.core.model.TacnaOfficialRouteCatalogItem
import pe.edu.unjbg.busconectado.core.model.UserAuth
import pe.edu.unjbg.busconectado.core.security.EncryptedStorage
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.POST
import java.net.URLEncoder
import java.util.Locale
import java.util.concurrent.TimeUnit

data class OtpSendRequest(val phone: String)

data class OtpSendResponse(
    val status: String? = null,
    val phone: String? = null,
    val message: String? = null
)

data class OtpVerifyRequest(
    val phone: String,
    val code: String
)

data class AuthVerifyResponse(
    @SerializedName("access_token")
    val accessToken: String,
    @SerializedName("refresh_token")
    val refreshToken: String,
    val user: UserAuth
)

data class RechargeRequest(
    val amountPoints: Int,
    val gateway: String = "YAPE",
    val reference: String? = null
)

data class RechargeResponse(
    val status: String? = null,
    val message: String? = null,
    @SerializedName("new_balance")
    val newBalance: Int = 0
)

data class TransitNetworkResponse(
    val routes: List<BusRouteModel> = emptyList(),
    @SerializedName("catalog_routes")
    val catalogRoutes: List<TacnaOfficialRouteCatalogItem> = emptyList(),
    val stops: List<BusStopModel> = emptyList(),
    @SerializedName("active_buses")
    val activeBuses: List<ActiveBusModel> = emptyList()
)

interface BCApiService {
    @GET("health")
    suspend fun healthCheck(): Response<Map<String, Any>>

    @POST("auth/otp/send")
    suspend fun sendOtp(@Body request: OtpSendRequest): Response<OtpSendResponse>

    @POST("auth/otp/verify")
    suspend fun verifyOtp(@Body request: OtpVerifyRequest): Response<AuthVerifyResponse>

    @GET("transit/stops")
    suspend fun fetchStopsCatalog(): Response<List<TacnaDestinationPlace>>

    @GET("transit/routes")
    suspend fun fetchRoutesCatalog(): Response<List<TacnaOfficialRouteCatalogItem>>

    @GET("transit/network")
    suspend fun fetchTransitNetwork(): Response<TransitNetworkResponse>

    @POST("wallet/recharge")
    suspend fun rechargePoints(
        @Header("Authorization") authHeader: String?,
        @Body request: RechargeRequest
    ): Response<RechargeResponse>

    @POST("wallet/pay-qr")
    suspend fun payQrPassage(
        @Header("Authorization") authHeader: String?,
        @Body request: Map<String, @JvmSuppressWildcards Any>
    ): Response<Map<String, Any>>
}

class BCNetworkClient(private val storage: EncryptedStorage) {

    var onUnauthorizedSession: (() -> Unit)? = null

    private val okHttpClient: OkHttpClient by lazy {
        val logging = HttpLoggingInterceptor().apply {
            level = HttpLoggingInterceptor.Level.BASIC
        }
        OkHttpClient.Builder()
            .connectTimeout(4, TimeUnit.SECONDS)
            .readTimeout(8, TimeUnit.SECONDS)
            .writeTimeout(8, TimeUnit.SECONDS)
            .addInterceptor { chain ->
                val reqBuilder = chain.request().newBuilder()
                    .header("Accept", "application/json")
                storage.getAccessToken()?.takeIf { it.isNotBlank() }?.let { token ->
                    reqBuilder.header("Authorization", "Bearer $token")
                }
                val response = chain.proceed(reqBuilder.build())
                if (response.code == 401) {
                    onUnauthorizedSession?.invoke()
                }
                response
            }
            .addInterceptor(logging)
            .build()
    }

    private val externalHttpClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(4, TimeUnit.SECONDS)
            .readTimeout(8, TimeUnit.SECONDS)
            .build()
    }

    private val gson = Gson()

    @Volatile
    private var cachedHost: String? = null
    @Volatile
    private var cachedService: BCApiService? = null

    fun currentBaseUrl(): String = resolveBaseUrl(storage.getBackendHost())

    fun service(): BCApiService {
        val host = storage.getBackendHost()
        val existing = cachedService
        if (existing != null && cachedHost == host) {
            return existing
        }
        val retrofit = Retrofit.Builder()
            .baseUrl(resolveBaseUrl(host))
            .client(okHttpClient)
            .addConverterFactory(GsonConverterFactory.create())
            .build()
        val created = retrofit.create(BCApiService::class.java)
        cachedHost = host
        cachedService = created
        return created
    }

    fun invalidateRetrofitCache() {
        cachedService = null
        cachedHost = null
    }

    suspend fun searchLivePlacesInTacna(query: String): List<TacnaDestinationPlace> = withContext(Dispatchers.IO) {
        val clean = query.trim()
        if (clean.length < 2) return@withContext emptyList()
        val encoded = URLEncoder.encode("$clean Tacna Peru", "UTF-8")

        // 1) Photon Komoot (rápido, sin API key, acotado al área de Tacna)
        val photonResults = try {
            val url = "https://photon.komoot.io/api/?q=$encoded&lat=-18.0135&lon=-70.2519&bbox=-70.55,-18.25,-70.00,-17.75&limit=8"
            val req = Request.Builder()
                .url(url)
                .header("User-Agent", "BusConectado-Tacna-Android/1.0")
                .build()
            externalHttpClient.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) emptyList() else parsePhotonResults(resp.body?.string().orEmpty())
            }
        } catch (_: Exception) {
            emptyList()
        }

        if (photonResults.isNotEmpty()) return@withContext photonResults

        // 2) Fallback Nominatim OpenStreetMap acotado a Tacna
        return@withContext try {
            val nomEncoded = URLEncoder.encode(clean, "UTF-8")
            val url = "https://nominatim.openstreetmap.org/search?q=$nomEncoded&format=json&addressdetails=1&bounded=1&viewbox=-70.55,-17.75,-70.00,-18.25&limit=8"
            val req = Request.Builder()
                .url(url)
                .header("User-Agent", "BusConectado-Tacna-Android/1.0")
                .build()
            externalHttpClient.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) emptyList() else parseNominatimResults(resp.body?.string().orEmpty())
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    suspend fun reverseGeocodeInTacna(coord: GeoPointData): TacnaDestinationPlace = withContext(Dispatchers.IO) {
        val safe = LocationService.sanitizedTacnaCoordinate(coord)
        try {
            val url = String.format(
                Locale.US,
                "https://nominatim.openstreetmap.org/reverse?lat=%.6f&lon=%.6f&format=json&addressdetails=1",
                safe.latitude,
                safe.longitude
            )
            val req = Request.Builder()
                .url(url)
                .header("User-Agent", "BusConectado-Tacna-Android/1.0")
                .build()
            externalHttpClient.newCall(req).execute().use { resp ->
                val raw = resp.body?.string().orEmpty()
                if (resp.isSuccessful && raw.isNotBlank()) {
                    val obj = gson.fromJson(raw, JsonObject::class.java)
                    val addr = obj.getAsJsonObject("address")
                    val road = addr?.get("road")?.asString
                        ?: addr?.get("amenity")?.asString
                        ?: addr?.get("neighbourhood")?.asString
                        ?: obj.get("name")?.asString
                    val suburb = addr?.get("suburb")?.asString
                        ?: addr?.get("city_district")?.asString
                        ?: "Tacna"
                    val label = road?.takeIf { it.isNotBlank() } ?: "Punto en Tacna"
                    return@withContext TacnaDestinationPlace.fromMapItem(
                        name = label,
                        subtitle = "$suburb · Tacna, Perú",
                        coordinate = safe
                    )
                }
            }
        } catch (_: Exception) {
        }
        TacnaDestinationPlace.fromMapItem(
            name = "Punto en mapa",
            subtitle = String.format(Locale.US, "%.4f, %.4f · Tacna", safe.latitude, safe.longitude),
            coordinate = safe
        )
    }

    suspend fun alignPolylineToStreets(
        waypoints: List<GeoPointData>,
        isWalking: Boolean
    ): List<GeoPointData> = withContext(Dispatchers.IO) {
        if (waypoints.size < 2) return@withContext waypoints
        val profile = if (isWalking) "foot" else "driving"
        val sampled = if (waypoints.size > 16) {
            val step = maxOf(1, waypoints.size / 14)
            waypoints.filterIndexed { index, _ -> index == 0 || index == waypoints.lastIndex || index % step == 0 }
        } else {
            waypoints
        }
        val coordsParam = sampled.joinToString(";") { pt ->
            String.format(Locale.US, "%.6f,%.6f", pt.longitude, pt.latitude)
        }
        try {
            val url = "https://router.project-osrm.org/route/v1/$profile/$coordsParam?overview=full&geometries=geojson"
            val req = Request.Builder()
                .url(url)
                .header("User-Agent", "BusConectado-Tacna-Android/1.0")
                .build()
            externalHttpClient.newCall(req).execute().use { resp ->
                val raw = resp.body?.string().orEmpty()
                if (!resp.isSuccessful || raw.isBlank()) return@withContext waypoints
                val root = gson.fromJson(raw, JsonObject::class.java)
                val routes = root.getAsJsonArray("routes") ?: return@withContext waypoints
                if (routes.size() == 0) return@withContext waypoints
                val geom = routes[0].asJsonObject.getAsJsonObject("geometry") ?: return@withContext waypoints
                val coordArray = geom.getAsJsonArray("coordinates") ?: return@withContext waypoints
                val parsed = coordArray.mapNotNull { elem ->
                    val pair = elem.asJsonArray
                    if (pair.size() >= 2) GeoPointData(pair[1].asDouble, pair[0].asDouble) else null
                }
                if (parsed.size >= 2) return@withContext parsed
            }
        } catch (_: Exception) {
        }
        waypoints
    }

    private fun parsePhotonResults(raw: String): List<TacnaDestinationPlace> {
        return try {
            val root = gson.fromJson(raw, JsonObject::class.java)
            val features = root.getAsJsonArray("features") ?: return emptyList()
            features.mapNotNull { el ->
                val feat = el.asJsonObject
                val geom = feat.getAsJsonObject("geometry") ?: return@mapNotNull null
                val coords = geom.getAsJsonArray("coordinates") ?: return@mapNotNull null
                if (coords.size() < 2) return@mapNotNull null
                val lon = coords[0].asDouble
                val lat = coords[1].asDouble
                val pt = GeoPointData(lat, lon)
                if (!LocationService.isWithinTacna(pt)) return@mapNotNull null
                val props = feat.getAsJsonObject("properties") ?: return@mapNotNull null
                val name = props.get("name")?.asString
                    ?: props.get("street")?.asString
                    ?: return@mapNotNull null
                val street = props.get("street")?.asString
                val district = props.get("district")?.asString ?: props.get("city")?.asString ?: "Tacna"
                val subtitle = listOfNotNull(street?.takeIf { it != name }, district, "Tacna")
                    .joinToString(" · ")
                    .ifBlank { "Tacna, Perú" }
                TacnaDestinationPlace.fromMapItem(name = name, subtitle = subtitle, coordinate = pt, idPrefix = "api")
            }.distinctBy { "${it.name}_${(it.latitude * 1000).toInt()}" }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun parseNominatimResults(raw: String): List<TacnaDestinationPlace> {
        return try {
            val arr = gson.fromJson(raw, JsonArray::class.java) ?: return emptyList()
            arr.mapNotNull { el ->
                val obj = el.asJsonObject
                val lat = obj.get("lat")?.asString?.toDoubleOrNull() ?: return@mapNotNull null
                val lon = obj.get("lon")?.asString?.toDoubleOrNull() ?: return@mapNotNull null
                val pt = GeoPointData(lat, lon)
                if (!LocationService.isWithinTacna(pt)) return@mapNotNull null
                val display = obj.get("display_name")?.asString ?: return@mapNotNull null
                val firstPart = display.substringBefore(",").trim()
                val rest = display.substringAfter(",", "Tacna, Perú").trim().take(55)
                TacnaDestinationPlace.fromMapItem(
                    name = obj.get("name")?.asString?.takeIf { it.isNotBlank() } ?: firstPart,
                    subtitle = rest,
                    coordinate = pt,
                    idPrefix = "api"
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    companion object {
        fun resolveBaseUrl(rawHost: String): String {
            val cleaned = rawHost.trim().ifBlank { EncryptedStorage.DEFAULT_BACKEND_HOST }
            val withScheme = when {
                cleaned.startsWith("http://", ignoreCase = true) ||
                    cleaned.startsWith("https://", ignoreCase = true) -> cleaned.trimEnd('/')
                cleaned.contains("sslip.io") || cleaned.contains(".") &&
                    !cleaned.first().isDigit() && !cleaned.startsWith("localhost") -> "https://$cleaned"
                else -> "http://$cleaned:8000"
            }
            return "$withScheme/api/v1/"
        }
    }
}

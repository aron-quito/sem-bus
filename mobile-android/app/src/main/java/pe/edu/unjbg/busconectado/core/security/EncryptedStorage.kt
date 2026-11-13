package pe.edu.unjbg.busconectado.core.security

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import pe.edu.unjbg.busconectado.core.model.CarnetReviewRequest
import pe.edu.unjbg.busconectado.core.model.TacnaDestinationPlace
import pe.edu.unjbg.busconectado.core.model.TacnaOfficialRouteCatalogItem

/**
 * Almacenamiento seguro nativo respaldado por el Android Keystore del sistema operativo
 * y preferencias locales de caché para operación offline-first.
 */
class EncryptedStorage(context: Context) {

    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val prefs: SharedPreferences = try {
        EncryptedSharedPreferences.create(
            context,
            "bc_secure_prefs",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    } catch (_: Exception) {
        context.getSharedPreferences("bc_secure_prefs_fallback", Context.MODE_PRIVATE)
    }

    private val appPrefs: SharedPreferences =
        context.getSharedPreferences("bc_app_prefs", Context.MODE_PRIVATE)

    private val gson = Gson()

    fun saveAccessToken(token: String) {
        prefs.edit().putString(KEY_ACCESS_TOKEN, token).apply()
    }

    fun getAccessToken(): String? = prefs.getString(KEY_ACCESS_TOKEN, null)

    fun saveRefreshToken(token: String) {
        prefs.edit().putString(KEY_REFRESH_TOKEN, token).apply()
    }

    fun getRefreshToken(): String? = prefs.getString(KEY_REFRESH_TOKEN, null)

    fun saveLastPhone(phone: String) {
        prefs.edit().putString(KEY_LAST_PHONE, phone).apply()
    }

    fun getLastPhone(): String? = prefs.getString(KEY_LAST_PHONE, null)

    fun clearSession() {
        prefs.edit()
            .remove(KEY_ACCESS_TOKEN)
            .remove(KEY_REFRESH_TOKEN)
            .remove(KEY_LAST_PHONE)
            .apply()
    }

    fun getBackendHost(): String {
        return appPrefs.getString(KEY_BACKEND_HOST, DEFAULT_BACKEND_HOST) ?: DEFAULT_BACKEND_HOST
    }

    fun saveBackendHost(host: String) {
        val cleaned = host.trim().ifEmpty { DEFAULT_BACKEND_HOST }
        appPrefs.edit().putString(KEY_BACKEND_HOST, cleaned).apply()
    }

    fun saveCachedStops(stops: List<TacnaDestinationPlace>) {
        appPrefs.edit().putString(KEY_CACHED_STOPS, gson.toJson(stops)).apply()
    }

    fun loadCachedStops(): List<TacnaDestinationPlace> {
        val raw = appPrefs.getString(KEY_CACHED_STOPS, null) ?: return emptyList()
        return try {
            val type = object : TypeToken<List<TacnaDestinationPlace>>() {}.type
            gson.fromJson(raw, type) ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun saveCachedRoutes(routes: List<TacnaOfficialRouteCatalogItem>) {
        appPrefs.edit().putString(KEY_CACHED_ROUTES, gson.toJson(routes)).apply()
    }

    fun loadCachedRoutes(): List<TacnaOfficialRouteCatalogItem> {
        val raw = appPrefs.getString(KEY_CACHED_ROUTES, null) ?: return emptyList()
        return try {
            val type = object : TypeToken<List<TacnaOfficialRouteCatalogItem>>() {}.type
            gson.fromJson(raw, type) ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun saveRecentPlaces(places: List<TacnaDestinationPlace>) {
        appPrefs.edit().putString(KEY_RECENT_PLACES, gson.toJson(places)).apply()
    }

    fun loadRecentPlaces(): List<TacnaDestinationPlace> {
        val raw = appPrefs.getString(KEY_RECENT_PLACES, null) ?: return emptyList()
        return try {
            val type = object : TypeToken<List<TacnaDestinationPlace>>() {}.type
            gson.fromJson(raw, type) ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun saveWalletPointsOverride(userId: String, points: Int) {
        appPrefs.edit().putInt("wallet_pts_$userId", points).apply()
    }

    fun getWalletPointsOverride(userId: String): Int? {
        val key = "wallet_pts_$userId"
        return if (appPrefs.contains(key)) appPrefs.getInt(key, 0) else null
    }

    fun clearWalletPointsOverride(userId: String) {
        appPrefs.edit().remove("wallet_pts_$userId").apply()
    }

    fun saveCarnetReviewRequest(userId: String, req: CarnetReviewRequest?) {
        val key = "carnet_req_$userId"
        if (req == null) {
            appPrefs.edit().remove(key).apply()
        } else {
            appPrefs.edit().putString(key, gson.toJson(req)).apply()
        }
    }

    fun loadCarnetReviewRequest(userId: String): CarnetReviewRequest? {
        val raw = appPrefs.getString("carnet_req_$userId", null) ?: return null
        return try {
            gson.fromJson(raw, CarnetReviewRequest::class.java)
        } catch (_: Exception) {
            null
        }
    }

    companion object {
        const val DEFAULT_BACKEND_HOST = "34.30.86.129.sslip.io"
        private const val KEY_ACCESS_TOKEN = "access_token"
        private const val KEY_REFRESH_TOKEN = "refresh_token"
        private const val KEY_LAST_PHONE = "last_phone"
        private const val KEY_BACKEND_HOST = "bc_backend_host"
        private const val KEY_CACHED_STOPS = "bc_cached_stops"
        private const val KEY_CACHED_ROUTES = "bc_cached_routes"
        private const val KEY_RECENT_PLACES = "bc_recent_places"
    }
}

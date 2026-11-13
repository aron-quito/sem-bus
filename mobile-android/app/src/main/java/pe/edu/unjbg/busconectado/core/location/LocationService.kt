package pe.edu.unjbg.busconectado.core.location

import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import androidx.core.content.ContextCompat
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

data class GeoPointData(
    val latitude: Double,
    val longitude: Double
) {
    fun distanceMetersTo(other: GeoPointData): Double {
        val r = 6371000.0
        val dLat = Math.toRadians(other.latitude - latitude)
        val dLon = Math.toRadians(other.longitude - longitude)
        val a = sin(dLat / 2) * sin(dLat / 2) +
            cos(Math.toRadians(latitude)) * cos(Math.toRadians(other.latitude)) *
            sin(dLon / 2) * sin(dLon / 2)
        val c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return r * c
    }
}

class LocationService(private val context: Context) {

    private val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager

    private val _currentLocation = MutableStateFlow(TACNA_DEFAULT)
    val currentLocation: StateFlow<GeoPointData> = _currentLocation.asStateFlow()

    private val _hasGpsLock = MutableStateFlow(false)
    val hasGpsLock: StateFlow<Boolean> = _hasGpsLock.asStateFlow()

    private val listener = LocationListener { location ->
        applyLocation(location)
    }

    fun hasLocationPermission(): Boolean {
        val fine = ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    @SuppressLint("MissingPermission")
    fun startUpdates() {
        if (!hasLocationPermission() || locationManager == null) return
        try {
            val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            var bestLast: Location? = null
            for (provider in providers) {
                if (locationManager.isProviderEnabled(provider)) {
                    val last = locationManager.getLastKnownLocation(provider)
                    if (last != null && (bestLast == null || last.time > bestLast.time)) {
                        bestLast = last
                    }
                    locationManager.requestLocationUpdates(provider, 3000L, 5f, listener)
                }
            }
            bestLast?.let { applyLocation(it) }
        } catch (_: Exception) {
        }
    }

    fun stopUpdates() {
        try {
            locationManager?.removeUpdates(listener)
        } catch (_: Exception) {
        }
    }

    private fun applyLocation(location: Location) {
        val candidate = GeoPointData(location.latitude, location.longitude)
        _currentLocation.value = sanitizedTacnaCoordinate(candidate)
        _hasGpsLock.value = true
    }

    companion object {
        val TACNA_DEFAULT = GeoPointData(-18.0135, -70.2519)
        val TACNA_HISTORIC_CENTER = GeoPointData(-18.0128, -70.2512)

        fun isWithinTacna(point: GeoPointData): Boolean {
            return point.latitude > -18.6 && point.latitude < -17.3 &&
                point.longitude > -70.9 && point.longitude < -69.7
        }

        fun sanitizedTacnaCoordinate(point: GeoPointData?): GeoPointData {
            if (point == null) return TACNA_DEFAULT
            return if (isWithinTacna(point)) point else TACNA_DEFAULT
        }
    }
}


package pe.edu.unjbg.busconectado.pos.ui

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.compose.ui.platform.LocalContext
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Contactless
import androidx.compose.material.icons.filled.DirectionsBus
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.QrCode2
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Security
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.WebSocket
import pe.edu.unjbg.busconectado.pos.data.PosNetworkRepository
import pe.edu.unjbg.busconectado.pos.data.PosOrderResponse
import java.util.Locale

private data class PaidConfirmationBanner(
    val methodLabel: String,
    val fareLabel: String,
    val amountPen: Double,
    val commissionPen: Double,
    val netPen: Double,
    val companionsCount: Int,
    val isStudent: Boolean = false,
    val isConadis: Boolean = false
)

@Composable
fun PosTerminalScreen(
    repository: PosNetworkRepository,
    nfcSupported: Boolean,
    lastNfcUid: String?,
    onClearNfcUid: () -> Unit
) {
    val scope = rememberCoroutineScope()

    var currentOrder by remember { mutableStateOf<PosOrderResponse?>(null) }
    var appQrBitmap by remember { mutableStateOf<Bitmap?>(null) }
    var yapeQrBitmap by remember { mutableStateOf<Bitmap?>(null) }
    var remainingSeconds by remember { mutableIntStateOf(60) }
    var isLoadingOrder by remember { mutableStateOf(true) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var paidConfirmation by remember { mutableStateOf<PaidConfirmationBanner?>(null) }
    var activeWs by remember { mutableStateOf<WebSocket?>(null) }

    // Estado de sesión / enlace de Chofer (DNI + PIN)
    var showDriverLoginDialog by remember { mutableStateOf(false) }
    var driverDniInput by remember { mutableStateOf("") }
    var driverPinInput by remember { mutableStateOf("") }
    var driverLoginError by remember { mutableStateOf<String?>(null) }
    var isLoggingInDriver by remember { mutableStateOf(false) }
    var linkedDriverName by remember { mutableStateOf<String?>(null) }
    var isPosPaymentEnabled by remember { mutableStateOf(false) }
    var linkedUnitCode by remember { mutableStateOf("") }
    var linkedPlate by remember { mutableStateOf("") }
    var linkedRouteCode by remember { mutableStateOf("") }

    // Contadores del turno en vivo
    var totalTripsCount by remember { mutableIntStateOf(0) }
    var adultTripsCount by remember { mutableIntStateOf(0) }
    var studentTripsCount by remember { mutableIntStateOf(0) }
    var yapeTripsCount by remember { mutableIntStateOf(0) }
    var conadisTripsCount by remember { mutableIntStateOf(0) }
    var totalGrossPen by remember { mutableDoubleStateOf(0.0) }
    var totalCommissionPen by remember { mutableDoubleStateOf(0.0) }
    var totalNetPen by remember { mutableDoubleStateOf(0.0) }

    fun handlePaidEvent(
        method: String?,
        fareLabel: String?,
        amountPen: Double,
        commissionPen: Double,
        netPen: Double,
        companions: Int
    ) {
        if (paidConfirmation != null) return
        PosValidatorSound.playSuccessBeep()
        val isStudentFare = fareLabel?.contains("Universitaria", ignoreCase = true) == true ||
            fareLabel?.contains("SUNEDU", ignoreCase = true) == true ||
            (amountPen in 0.69..0.71) || (amountPen in 2.19..2.21 && companions == 1)
        val isConadisFare = fareLabel?.contains("CONADIS", ignoreCase = true) == true ||
            fareLabel?.contains("Libre", ignoreCase = true) == true ||
            amountPen == 0.0

        totalTripsCount += 1 + companions
        totalGrossPen += amountPen
        totalCommissionPen += commissionPen
        totalNetPen += netPen

        when {
            method == "YAPE_EMPRESA" -> {
                yapeTripsCount += 1
            }
            isConadisFare -> {
                conadisTripsCount += 1
            }
            isStudentFare -> {
                studentTripsCount += 1
                if (companions > 0) adultTripsCount += companions
            }
            else -> {
                adultTripsCount += 1 + companions
            }
        }

        val resolvedMethodLabel = when (method) {
            "YAPE_EMPRESA" -> "YAPE EMPRESA BCP"
            "NFC" -> "TARJETA CONTACTLESS NFC"
            else -> "APP BUS CONECTADO"
        }

        val resolvedFareLabel = when {
            isConadisFare -> "PASE LIBRE CONADIS (LEY 30412)"
            isStudentFare -> "TARIFA UNIVERSITARIA SUNEDU (S/. 0.70)" + (if (companions > 0) " + $companions ADULTO" else "")
            method == "YAPE_EMPRESA" -> "TARIFA PLANA DIGITAL"
            else -> fareLabel ?: "TARIFA ADULTO GENERAL"
        }

        paidConfirmation = PaidConfirmationBanner(
            methodLabel = resolvedMethodLabel,
            fareLabel = resolvedFareLabel,
            amountPen = amountPen,
            commissionPen = commissionPen,
            netPen = netPen,
            companionsCount = companions,
            isStudent = isStudentFare,
            isConadis = isConadisFare
        )
    }

    suspend fun requestNewOrder() {
        activeWs?.close(1000, "new_order")
        activeWs = null
        isLoadingOrder = true
        errorMessage = null

        val result = withContext(Dispatchers.IO) {
            repository.createFlatFareOrder()
        }
        result.onSuccess { order ->
            currentOrder = order
            remainingSeconds = order.ttlSeconds
            withContext(Dispatchers.Default) {
                appQrBitmap = QrBitmapGenerator.generate(order.appQrPayload, 500)
                yapeQrBitmap = QrBitmapGenerator.generate(order.yapeQrPayload, 500)
            }
            isLoadingOrder = false
        }.onFailure { err ->
            isLoadingOrder = false
            errorMessage = "Sin enlace con servidor POS (${err.localizedMessage ?: "verifica conexión"})."
        }
    }

    LaunchedEffect(Unit) {
        requestNewOrder()
    }

    // Escucha WebSocket + polling respaldo + cuenta regresiva de expiración única
    LaunchedEffect(currentOrder?.orderId) {
        val order = currentOrder ?: return@LaunchedEffect
        val targetOrderId = order.orderId

        val ws = repository.openOrderWebSocket(
            orderId = targetOrderId,
            onEvent = { evt ->
                if (evt.status == "PAID") {
                    scope.launch(Dispatchers.Main) {
                        handlePaidEvent(
                            method = evt.paymentMethod,
                            fareLabel = evt.fareLabel,
                            amountPen = evt.amountPen,
                            commissionPen = evt.commissionPen,
                            netPen = evt.netPen,
                            companions = evt.companionsCount
                        )
                    }
                }
            },
            onFailure = {}
        )
        activeWs = ws

        while (currentOrder?.orderId == targetOrderId) {
            delay(1000L)
            if (paidConfirmation != null) continue

            remainingSeconds -= 1
            // Polling continuo cada segundo para captura instantánea de cobros
            val statusRes = withContext(Dispatchers.IO) {
                repository.getOrderStatus(targetOrderId)
            }
            statusRes.getOrNull()?.let { st ->
                if (st.status == "PAID") {
                    handlePaidEvent(
                        method = st.paymentMethod,
                        fareLabel = st.fareLabel,
                        amountPen = st.amountPen,
                        commissionPen = st.commissionPen,
                        netPen = st.netPen,
                        companions = st.companionsCount
                    )
                } else if (st.status == "EXPIRED" || st.status == "CANCELLED") {
                    remainingSeconds = 0
                }
            }

            if (remainingSeconds <= 0 && paidConfirmation == null) {
                requestNewOrder()
                break
            }
        }
    }

    // Tras mostrar pantalla de cobro exitoso, rota automáticamente a un nuevo QR único
    LaunchedEffect(paidConfirmation != null) {
        if (paidConfirmation != null) {
            delay(2500L)
            requestNewOrder()
            paidConfirmation = null
        }
    }

    val context = LocalContext.current
    val posPrefs = remember { context.getSharedPreferences("pos_session_prefs", Context.MODE_PRIVATE) }
    var latestRealLocation by remember { mutableStateOf<Location?>(null) }
    var hasLocationPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
                ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        )
    }
    val locationPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions()
    ) { perms ->
        hasLocationPermission = perms[Manifest.permission.ACCESS_FINE_LOCATION] == true ||
            perms[Manifest.permission.ACCESS_COARSE_LOCATION] == true
    }

    LaunchedEffect(Unit) {
        val savedDni = posPrefs.getString("dni", null)
        val savedToken = posPrefs.getString("token", null)
        val savedName = posPrefs.getString("name", null)
        if (!savedDni.isNullOrBlank() && !savedToken.isNullOrBlank() && !savedName.isNullOrBlank()) {
            val sId = posPrefs.getString("id", "USR-DRV") ?: "USR-DRV"
            val sUnit = posPrefs.getString("unit_code", "UNI-1408") ?: "UNI-1408"
            val sPlate = posPrefs.getString("plate", "Z4B-812") ?: "Z4B-812"
            val sRoute = posPrefs.getString("route_code", "Ruta 14") ?: "Ruta 14"
            val sPosId = posPrefs.getString("pos_id", "") ?: ""
            repository.restoreSession(sId, savedDni, savedName, sUnit, sPlate, sRoute, savedToken, sPosId)
            linkedDriverName = savedName
            linkedUnitCode = sUnit
            linkedPlate = sPlate
            linkedRouteCode = sRoute
            val (active, posEnabled) = withContext(Dispatchers.IO) { repository.fetchSessionStatus() }
            if (!active) {
                posPrefs.edit().clear().apply()
                repository.logoutDriver()
                linkedDriverName = null
                isPosPaymentEnabled = false
            } else {
                isPosPaymentEnabled = posEnabled
                requestNewOrder()
            }
        }
        if (!hasLocationPermission) {
            locationPermissionLauncher.launch(
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
            )
        }
    }

    DisposableEffect(hasLocationPermission) {
        val locManager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        val listener = LocationListener { loc ->
            val current = latestRealLocation
            val isBetter = current == null ||
                (loc.time - current.time) > 10_000L ||
                (loc.hasAccuracy() && (!current.hasAccuracy() || loc.accuracy <= current.accuracy))
            if (isBetter) {
                latestRealLocation = loc
            }
        }
        if (hasLocationPermission && locManager != null) {
            runCatching {
                val gpsLast = locManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                val netLast = locManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                val bestLast = listOfNotNull(gpsLast, netLast).maxByOrNull { it.time }
                if (bestLast != null && (System.currentTimeMillis() - bestLast.time) < 120_000L) {
                    latestRealLocation = bestLast
                }
                if (locManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                    locManager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1500L, 1f, listener)
                }
                if (locManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                    locManager.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 2500L, 2f, listener)
                }
            }
        }
        onDispose {
            runCatching { locManager?.removeUpdates(listener) }
        }
    }

    // Emisión continua de telemetría GPS REAL del dispositivo + verificación de sesión y habilitación desde App Chofer
    LaunchedEffect(Unit) {
        while (true) {
            delay(2500L)
            if (linkedDriverName != null) {
                val loc = latestRealLocation
                withContext(Dispatchers.IO) {
                    if (loc != null) {
                        val speedKmh = if (loc.hasSpeed()) (loc.speed * 3.6).coerceAtLeast(0.0) else 0.0
                        val heading = if (loc.hasBearing()) loc.bearing.toDouble() else 0.0
                        repository.sendTelemetry(lat = loc.latitude, lng = loc.longitude, speed = speedKmh, heading = heading)
                    }
                    val (sessionActive, posEnabled) = repository.fetchSessionStatus()
                    withContext(Dispatchers.Main) {
                        if (!sessionActive) {
                            posPrefs.edit().clear().apply()
                            repository.logoutDriver()
                            linkedDriverName = null
                            isPosPaymentEnabled = false
                            errorMessage = "Sesión finalizada o usuario deshabilitado desde el Panel Administrador."
                        } else {
                            isPosPaymentEnabled = posEnabled
                        }
                    }
                }
            }
        }
    }

    // Lectura NFC en la misma pantalla POS
    LaunchedEffect(lastNfcUid) {
        val uid = lastNfcUid ?: return@LaunchedEffect
        val order = currentOrder ?: return@LaunchedEffect
        val res = withContext(Dispatchers.IO) {
            repository.submitNfcTap(order.orderId, uid)
        }
        onClearNfcUid()
        if (res.isFailure) {
            PosValidatorSound.playRejectedBeep()
            errorMessage = "Tarjeta NFC detectada ($uid). Pendiente vincular padrón en central."
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            activeWs?.close(1000, "dispose")
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF0A0F18))
            .statusBarsPadding()
            .navigationBarsPadding()
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            errorMessage?.let { msg ->
                Surface(
                    shape = RoundedCornerShape(12.dp),
                    color = Color(0xFF450A0A),
                    border = BorderStroke(1.dp, Color(0xFFEF4444))
                ) {
                    Text(
                        msg,
                        color = Color.White,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(12.dp)
                    )
                }
            }

            if (linkedDriverName == null) {
                // Pantalla única de Inicio de Sesión (Google Material 3, limpia y sin paneles extra)
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                    contentAlignment = Alignment.Center
                ) {
                    Surface(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(24.dp),
                        color = Color(0xFF121A28),
                        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.12f))
                    ) {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(24.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(52.dp)
                                    .clip(RoundedCornerShape(14.dp))
                                    .background(Color(0xFF2563EB)),
                                contentAlignment = Alignment.Center
                            ) {
                                Icon(Icons.Default.DirectionsBus, contentDescription = null, tint = Color.White, modifier = Modifier.size(28.dp))
                            }
                            Text(
                                "Bus Conectado POS",
                                color = Color.White,
                                fontWeight = FontWeight.Black,
                                fontSize = 20.sp,
                                textAlign = TextAlign.Center
                            )
                            Text(
                                "Inicia sesión con el DNI y PIN del chofer registrado en el Panel Administrador.",
                                color = Color(0xFF94A3B8),
                                fontSize = 12.sp,
                                textAlign = TextAlign.Center
                            )
                            val fieldColors = OutlinedTextFieldDefaults.colors(
                                focusedTextColor = Color.White,
                                unfocusedTextColor = Color.White,
                                focusedLabelColor = Color(0xFF38BDF8),
                                unfocusedLabelColor = Color(0xFF94A3B8),
                                focusedBorderColor = Color(0xFF38BDF8),
                                unfocusedBorderColor = Color(0xFF334155),
                                cursorColor = Color.White
                            )
                            OutlinedTextField(
                                value = driverDniInput,
                                onValueChange = { driverDniInput = it.filter { c -> c.isDigit() }.take(8) },
                                label = { Text("DNI del Chofer") },
                                singleLine = true,
                                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Number),
                                colors = fieldColors,
                                modifier = Modifier.fillMaxWidth()
                            )
                            OutlinedTextField(
                                value = driverPinInput,
                                onValueChange = { driverPinInput = it.filter { c -> c.isDigit() }.take(6) },
                                label = { Text("PIN de Enlace") },
                                singleLine = true,
                                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Number),
                                colors = fieldColors,
                                modifier = Modifier.fillMaxWidth()
                            )
                            driverLoginError?.let { err ->
                                Text(err, color = Color(0xFFF87171), fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                            }
                            Button(
                                enabled = !isLoggingInDriver,
                                onClick = {
                                    if (driverDniInput.length != 8) {
                                        driverLoginError = "Ingresa un DNI válido de 8 dígitos"
                                        return@Button
                                    }
                                    if (driverPinInput.isBlank()) {
                                        driverLoginError = "Ingresa el PIN de enlace del POS"
                                        return@Button
                                    }
                                    scope.launch {
                                        isLoggingInDriver = true
                                        driverLoginError = null
                                        errorMessage = null
                                        val res = withContext(Dispatchers.IO) {
                                            repository.loginDriver(driverDniInput, driverPinInput)
                                        }
                                        isLoggingInDriver = false
                                        res.onSuccess { loginResp ->
                                            loginResp.driver?.let { d ->
                                                linkedDriverName = d.name
                                                linkedUnitCode = d.unitCode
                                                linkedPlate = d.plate
                                                linkedRouteCode = d.routeCode
                                                posPrefs.edit()
                                                    .putString("id", d.id)
                                                    .putString("dni", d.dni)
                                                    .putString("name", d.name)
                                                    .putString("unit_code", d.unitCode)
                                                    .putString("plate", d.plate)
                                                    .putString("route_code", d.routeCode)
                                                    .putString("token", loginResp.token.orEmpty())
                                                    .putString("pos_id", loginResp.pos?.posId.orEmpty())
                                                    .apply()
                                            }
                                            isPosPaymentEnabled = withContext(Dispatchers.IO) { repository.fetchSessionStatus().second }
                                            requestNewOrder()
                                        }.onFailure { e ->
                                            driverLoginError = e.localizedMessage ?: "DNI o PIN inválido"
                                        }
                                    }
                                },
                                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF2563EB)),
                                shape = RoundedCornerShape(14.dp),
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(48.dp)
                            ) {
                                Text(if (isLoggingInDriver) "Iniciando sesión..." else "Iniciar Turno en POS", color = Color.White, fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                }
            } else if (!isPosPaymentEnabled) {
                Surface(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                    shape = RoundedCornerShape(24.dp),
                    color = Color(0xFF121A28),
                    border = BorderStroke(1.dp, Color(0xFFF59E0B).copy(alpha = 0.55f))
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center
                    ) {
                        Icon(Icons.Default.QrCode2, contentDescription = null, tint = Color(0xFFFBBF24), modifier = Modifier.size(48.dp))
                        Spacer(Modifier.height(14.dp))
                        Text(
                            "$linkedRouteCode · $linkedUnitCode ($linkedPlate)",
                            color = Color(0xFF38BDF8),
                            fontWeight = FontWeight.Bold,
                            fontSize = 13.sp,
                            textAlign = TextAlign.Center
                        )
                        Spacer(Modifier.height(6.dp))
                        Text(
                            "Cobros POS Pausados por el Chofer",
                            color = Color.White,
                            fontWeight = FontWeight.Black,
                            fontSize = 18.sp,
                            textAlign = TextAlign.Center
                        )
                        Spacer(Modifier.height(8.dp))
                        Text(
                            "Sesión activa: $linkedDriverName.\n" +
                                (if (latestRealLocation != null) "GPS en tiempo real activo.\n" else "Buscando señal GPS...\n") +
                                "El chofer debe presionar \"Habilitar POS\" en la App del Chofer para mostrar los QR.",
                            color = Color(0xFFCBD5E1),
                            fontSize = 12.sp,
                            textAlign = TextAlign.Center
                        )
                    }
                }
            } else if (isLoadingOrder && currentOrder == null) {
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                    contentAlignment = Alignment.Center
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        CircularProgressIndicator(color = Color(0xFF34D399))
                        Text("Generando QRs dinámicos únicos...", color = Color(0xFF94A3B8), fontSize = 13.sp)
                    }
                }
            } else {
                // Tarjeta Dual de 2 QRs: en tablet lado a lado; en celular un QR sobre otro (Column)
                BoxWithConstraints(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                ) {
                    val isWide = maxWidth >= 600.dp
                    val order = currentOrder
                    val progress = (remainingSeconds / (order?.ttlSeconds?.toFloat() ?: 60f)).coerceIn(0f, 1f)

                    if (isWide) {
                        Row(
                            modifier = Modifier.fillMaxSize(),
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            AppDynamicQrCard(
                                modifier = Modifier.weight(1f),
                                bitmap = appQrBitmap,
                                remainingSeconds = remainingSeconds,
                                progress = progress,
                                amountPen = order?.amountPen ?: 1.50,
                                qrSize = 190.dp,
                                compact = false
                            )
                            YapeEmpresaQrCard(
                                modifier = Modifier.weight(1f),
                                bitmap = yapeQrBitmap,
                                orderId = order?.orderId.orEmpty(),
                                amountPen = order?.amountPen ?: 1.50,
                                commissionPen = order?.yapeCommissionPen ?: 0.04,
                                netPen = order?.yapeNetPen ?: 1.46,
                                qrSize = 190.dp,
                                compact = false
                            )
                        }
                    } else {
                        val phoneQrSize = ((maxHeight - 24.dp) / 2f - 28.dp).coerceIn(96.dp, 148.dp)
                        Column(
                            modifier = Modifier.fillMaxSize(),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            AppDynamicQrCard(
                                modifier = Modifier
                                    .weight(1f)
                                    .fillMaxWidth(),
                                bitmap = appQrBitmap,
                                remainingSeconds = remainingSeconds,
                                progress = progress,
                                amountPen = order?.amountPen ?: 1.50,
                                qrSize = phoneQrSize,
                                compact = true
                            )
                            YapeEmpresaQrCard(
                                modifier = Modifier
                                    .weight(1f)
                                    .fillMaxWidth(),
                                bitmap = yapeQrBitmap,
                                orderId = order?.orderId.orEmpty(),
                                amountPen = order?.amountPen ?: 1.50,
                                commissionPen = order?.yapeCommissionPen ?: 0.04,
                                netPen = order?.yapeNetPen ?: 1.46,
                                qrSize = phoneQrSize,
                                compact = true
                            )
                        }
                    }
                }
            }

            if (linkedDriverName != null && isPosPaymentEnabled) {
                // Controles operativos / prueba de webhook firmado
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(
                        onClick = { scope.launch { requestNewOrder() } },
                        modifier = Modifier
                            .weight(1f)
                            .height(44.dp),
                        shape = RoundedCornerShape(12.dp),
                        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.2f))
                    ) {
                        Icon(Icons.Default.Refresh, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(5.dp))
                        Text("Nuevo QR", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 12.sp, maxLines = 1)
                    }

                    Button(
                        onClick = {
                            val order = currentOrder ?: return@Button
                            scope.launch {
                                withContext(Dispatchers.IO) {
                                    repository.triggerSignedTestYapeWebhook(
                                        orderId = order.orderId,
                                        unitCode = order.unitCode,
                                        amountPen = order.amountPen
                                    )
                                }
                            }
                        },
                        modifier = Modifier
                            .weight(1.25f)
                            .height(44.dp),
                        shape = RoundedCornerShape(12.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF7C3AED))
                    ) {
                        Icon(Icons.Default.QrCode2, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(5.dp))
                        Text("Simular Yape S/. 1.50", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 12.sp, maxLines = 1)
                    }
                }
            }
        }

        // Pantalla de Confirmación Instantánea (Estilo Validador según Tipo de Tarifa sin PII)
        AnimatedVisibility(
            visible = paidConfirmation != null,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.fillMaxSize()
        ) {
            paidConfirmation?.let { paid ->
                val bgTint = when {
                    paid.isConadis -> Color(0xF5042F2E)
                    paid.isStudent -> Color(0xF51E1B4B)
                    paid.methodLabel.contains("YAPE") -> Color(0xF52E1065)
                    else -> Color(0xF5052E16)
                }
                val iconTint = when {
                    paid.isConadis -> Color(0xFF14B8A6)
                    paid.isStudent -> Color(0xFF818CF8)
                    paid.methodLabel.contains("YAPE") -> Color(0xFFA855F7)
                    else -> Color(0xFF10B981)
                }

                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(bgTint),
                    contentAlignment = Alignment.Center
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(14.dp),
                        modifier = Modifier.padding(28.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(96.dp)
                                .clip(CircleShape)
                                .background(iconTint),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                Icons.Default.CheckCircle,
                                contentDescription = null,
                                tint = Color.Black,
                                modifier = Modifier.size(58.dp)
                            )
                        }
                        Text(
                            when {
                                paid.isConadis -> "PASE LIBRE CONADIS"
                                paid.isStudent -> "TARIFA UNIVERSITARIA"
                                else -> "PASAJE VALIDADO"
                            },
                            color = when {
                                paid.isConadis -> Color(0xFF5EEAD4)
                                paid.isStudent -> Color(0xFFA5B4FC)
                                else -> Color(0xFF6EE7B7)
                            },
                            fontWeight = FontWeight.Black,
                            fontSize = 26.sp
                        )
                        Text(
                            String.format(Locale.US, "S/. %.2f", paid.amountPen),
                            color = Color.White,
                            fontWeight = FontWeight.Black,
                            fontSize = 46.sp
                        )
                        Surface(
                            shape = RoundedCornerShape(50),
                            color = Color.White.copy(alpha = 0.16f)
                        ) {
                            Text(
                                "${paid.methodLabel} · ${paid.fareLabel}",
                                color = Color.White,
                                fontWeight = FontWeight.Bold,
                                fontSize = 14.sp,
                                modifier = Modifier.padding(horizontal = 18.dp, vertical = 8.dp)
                            )
                        }
                        if (paid.isStudent) {
                            Surface(
                                shape = RoundedCornerShape(8.dp),
                                color = Color(0xFF312E81)
                            ) {
                                Text(
                                    "Carnet SUNEDU validado · Ventana anti-fraude 2 min activada",
                                    color = Color(0xFFC7D2FE),
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp)
                                )
                            }
                        }
                        Text(
                            String.format(
                                Locale.US,
                                "Comisión: S/. %.2f · Neto unidad: S/. %.2f",
                                paid.commissionPen,
                                paid.netPen
                            ),
                            color = Color.White.copy(alpha = 0.85f),
                            fontSize = 13.sp,
                            fontFamily = FontFamily.Monospace
                        )
                    }
                }
            }
        }

        if (showDriverLoginDialog) {
            AlertDialog(
                onDismissRequest = { if (!isLoggingInDriver) showDriverLoginDialog = false },
                containerColor = Color(0xFF121A28),
                title = {
                    Text("Enlazar Chofer al POS", color = Color.White, fontWeight = FontWeight.Bold)
                },
                text = {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(
                            "Inicia sesión con las credenciales del chofer registradas en el Panel Administrador para vincular esta tablet a su unidad y ruta.",
                            color = Color(0xFF94A3B8),
                            fontSize = 12.sp
                        )
                        val fieldColors = OutlinedTextFieldDefaults.colors(
                            focusedTextColor = Color.White,
                            unfocusedTextColor = Color.White,
                            focusedLabelColor = Color(0xFF38BDF8),
                            unfocusedLabelColor = Color(0xFF94A3B8),
                            focusedBorderColor = Color(0xFF38BDF8),
                            unfocusedBorderColor = Color(0xFF475569),
                            cursorColor = Color.White
                        )
                        OutlinedTextField(
                            value = driverDniInput,
                            onValueChange = { driverDniInput = it },
                            label = { Text("DNI del Chofer") },
                            singleLine = true,
                            colors = fieldColors,
                            modifier = Modifier.fillMaxWidth()
                        )
                        OutlinedTextField(
                            value = driverPinInput,
                            onValueChange = { driverPinInput = it },
                            label = { Text("PIN de Enlace (4 dígitos)") },
                            singleLine = true,
                            colors = fieldColors,
                            modifier = Modifier.fillMaxWidth()
                        )
                        driverLoginError?.let { err ->
                            Text(err, color = Color(0xFFF87171), fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                        }
                    }
                },
                confirmButton = {
                    Button(
                        enabled = !isLoggingInDriver,
                        onClick = {
                            scope.launch {
                                isLoggingInDriver = true
                                driverLoginError = null
                                val res = withContext(Dispatchers.IO) {
                                    repository.loginDriver(driverDniInput, driverPinInput)
                                }
                                isLoggingInDriver = false
                                res.onSuccess { loginResp ->
                                    loginResp.driver?.let { d ->
                                        linkedDriverName = d.name
                                        linkedUnitCode = d.unitCode
                                        linkedPlate = d.plate
                                        linkedRouteCode = d.routeCode
                                        posPrefs.edit()
                                            .putString("id", d.id)
                                            .putString("dni", d.dni)
                                            .putString("name", d.name)
                                            .putString("unit_code", d.unitCode)
                                            .putString("plate", d.plate)
                                            .putString("route_code", d.routeCode)
                                            .putString("token", loginResp.token.orEmpty())
                                            .putString("pos_id", loginResp.pos?.posId.orEmpty())
                                            .apply()
                                    }
                                    showDriverLoginDialog = false
                                    isPosPaymentEnabled = withContext(Dispatchers.IO) { repository.fetchSessionStatus().second }
                                    requestNewOrder()
                                }.onFailure { e ->
                                    driverLoginError = e.localizedMessage ?: "DNI o PIN inválido"
                                }
                            }
                        }
                    ) {
                        Text(if (isLoggingInDriver) "Enlazando..." else "Enlazar y Renovar QR")
                    }
                },
                dismissButton = {
                    TextButton(
                        enabled = !isLoggingInDriver,
                        onClick = { showDriverLoginDialog = false }
                    ) {
                        Text("Cancelar", color = Color(0xFF94A3B8))
                    }
                }
            )
        }
    }
}

@Composable
private fun AppDynamicQrCard(
    modifier: Modifier,
    bitmap: Bitmap?,
    remainingSeconds: Int,
    progress: Float,
    amountPen: Double,
    qrSize: androidx.compose.ui.unit.Dp = 210.dp,
    compact: Boolean = false
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(if (compact) 16.dp else 22.dp),
        color = Color(0xFF121A28),
        border = BorderStroke(1.5.dp, Color(0xFF10B981).copy(alpha = 0.55f))
    ) {
        if (compact) {
            Row(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(qrSize)
                        .clip(RoundedCornerShape(12.dp))
                        .background(Color.White)
                        .padding(6.dp),
                    contentAlignment = Alignment.Center
                ) {
                    if (bitmap != null) {
                        Image(
                            bitmap = bitmap.asImageBitmap(),
                            contentDescription = "QR Dinámico Bus Conectado",
                            modifier = Modifier.fillMaxSize()
                        )
                    }
                }
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            Icon(Icons.Default.Security, contentDescription = null, tint = Color(0xFF34D399), modifier = Modifier.size(15.dp))
                            Text("APP BUS CONECTADO", color = Color.White, fontWeight = FontWeight.Black, fontSize = 12.sp)
                        }
                        Surface(shape = RoundedCornerShape(50), color = Color(0xFF052E16)) {
                            Text("0% com.", color = Color(0xFF34D399), fontSize = 9.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp))
                        }
                    }
                    Text(
                        String.format(Locale.US, "Tarifa S/. %.2f (Univ. S/. 0.70)", amountPen),
                        color = Color(0xFFCBD5E1),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                    LinearProgressIndicator(
                        progress = { progress },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(6.dp)
                            .clip(RoundedCornerShape(50)),
                        color = Color(0xFF10B981),
                        trackColor = Color(0xFF1E293B)
                    )
                    Text(
                        "Renueva en ${remainingSeconds}s · QR único HMAC",
                        color = Color(0xFF94A3B8),
                        fontSize = 10.sp,
                        fontFamily = FontFamily.Monospace
                    )
                }
            }
        } else {
            Column(
                modifier = Modifier.padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Icon(Icons.Default.Security, contentDescription = null, tint = Color(0xFF34D399), modifier = Modifier.size(18.dp))
                        Text("APP BUS CONECTADO", color = Color.White, fontWeight = FontWeight.Black, fontSize = 13.sp)
                    }
                    Surface(shape = RoundedCornerShape(50), color = Color(0xFF052E16)) {
                        Text(
                            "0% puerta",
                            color = Color(0xFF34D399),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                        )
                    }
                }

                Box(
                    modifier = Modifier
                        .size(qrSize)
                        .clip(RoundedCornerShape(16.dp))
                        .background(Color.White)
                        .padding(10.dp),
                    contentAlignment = Alignment.Center
                ) {
                    if (bitmap != null) {
                        Image(
                            bitmap = bitmap.asImageBitmap(),
                            contentDescription = "QR Dinámico Bus Conectado",
                            modifier = Modifier.fillMaxSize()
                        )
                    }
                }

                Text(
                    String.format(Locale.US, "Tarifa plana: S/. %.2f · QR único anti-reuso", amountPen),
                    color = Color(0xFFCBD5E1),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    textAlign = TextAlign.Center
                )

                Column(modifier = Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    LinearProgressIndicator(
                        progress = { progress },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(6.dp)
                            .clip(RoundedCornerShape(50)),
                        color = Color(0xFF10B981),
                        trackColor = Color(0xFF1E293B)
                    )
                    Text(
                        "Renueva en ${remainingSeconds}s · Firmado HMAC-SHA256",
                        color = Color(0xFF94A3B8),
                        fontSize = 10.sp,
                        fontFamily = FontFamily.Monospace
                    )
                }
            }
        }
    }
}

@Composable
private fun YapeEmpresaQrCard(
    modifier: Modifier,
    bitmap: Bitmap?,
    orderId: String,
    amountPen: Double,
    commissionPen: Double,
    netPen: Double,
    qrSize: androidx.compose.ui.unit.Dp = 210.dp,
    compact: Boolean = false
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(if (compact) 16.dp else 22.dp),
        color = Color(0xFF1A1026),
        border = BorderStroke(1.5.dp, Color(0xFFA855F7).copy(alpha = 0.55f))
    ) {
        if (compact) {
            Row(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(qrSize)
                        .clip(RoundedCornerShape(12.dp))
                        .background(Color.White)
                        .padding(6.dp),
                    contentAlignment = Alignment.Center
                ) {
                    if (bitmap != null) {
                        Image(
                            bitmap = bitmap.asImageBitmap(),
                            contentDescription = "QR Yape Empresa",
                            modifier = Modifier.fillMaxSize()
                        )
                    }
                }
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            Icon(Icons.Default.Lock, contentDescription = null, tint = Color(0xFFC084FC), modifier = Modifier.size(15.dp))
                            Text("YAPE EMPRESA", color = Color.White, fontWeight = FontWeight.Black, fontSize = 12.sp)
                        }
                        Surface(shape = RoundedCornerShape(50), color = Color(0xFF3B0764)) {
                            Text(
                                String.format(Locale.US, "S/. %.2f", amountPen),
                                color = Color(0xFFE9D5FF),
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                            )
                        }
                    }
                    Text(
                        "Esperando confirmación automática...",
                        color = Color(0xFFE9D5FF),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        String.format(
                            Locale.US,
                            "Orden %s · Com. 2.95%% (S/. %.2f)\nNeto unidad: S/. %.2f",
                            orderId.take(8).uppercase(Locale.US),
                            commissionPen,
                            netPen
                        ),
                        color = Color(0xFFC4B5FD),
                        fontSize = 10.sp,
                        fontFamily = FontFamily.Monospace
                    )
                }
            }
        } else {
            Column(
                modifier = Modifier.padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Icon(Icons.Default.Lock, contentDescription = null, tint = Color(0xFFC084FC), modifier = Modifier.size(18.dp))
                        Text("YAPE EMPRESA", color = Color.White, fontWeight = FontWeight.Black, fontSize = 13.sp)
                    }
                    Surface(shape = RoundedCornerShape(50), color = Color(0xFF3B0764)) {
                        Text(
                            String.format(Locale.US, "S/. %.2f", amountPen),
                            color = Color(0xFFE9D5FF),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                        )
                    }
                }

                Box(
                    modifier = Modifier
                        .size(qrSize)
                        .clip(RoundedCornerShape(16.dp))
                        .background(Color.White)
                        .padding(10.dp),
                    contentAlignment = Alignment.Center
                ) {
                    if (bitmap != null) {
                        Image(
                            bitmap = bitmap.asImageBitmap(),
                            contentDescription = "QR Yape Empresa",
                            modifier = Modifier.fillMaxSize()
                        )
                    }
                }

                Text(
                    "Esperando confirmación automática...",
                    color = Color(0xFFE9D5FF),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center
                )

                Text(
                    String.format(
                        Locale.US,
                        "Orden %s · Com. 2.95%% (S/. %.2f) · Neto S/. %.2f",
                        orderId.take(8).uppercase(Locale.US),
                        commissionPen,
                        netPen
                    ),
                    color = Color(0xFFC4B5FD),
                    fontSize = 10.sp,
                    fontFamily = FontFamily.Monospace,
                    textAlign = TextAlign.Center
                )
            }
        }
    }
}

@Composable
private fun ShiftStat(label: String, value: String, color: Color) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(label, color = Color(0xFF94A3B8), fontSize = 10.sp, fontWeight = FontWeight.SemiBold)
        Text(value, color = color, fontSize = 14.sp, fontWeight = FontWeight.Black, fontFamily = FontFamily.Monospace)
    }
}


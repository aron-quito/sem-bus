package pe.edu.unjbg.busconectado.feature.qrscan

import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import android.view.ViewGroup
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.OptIn
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FlashlightOff
import androidx.compose.material.icons.filled.FlashlightOn
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import pe.edu.unjbg.busconectado.core.designsystem.BCColors
import pe.edu.unjbg.busconectado.core.model.MainAppTab
import pe.edu.unjbg.busconectado.core.model.UserRoleType
import pe.edu.unjbg.busconectado.feature.auth.AuthViewModel
import pe.edu.unjbg.busconectado.feature.auth.BCUiState
import java.util.Locale
import java.util.concurrent.Executors

@Composable
fun PayQrScreen(
    state: BCUiState,
    viewModel: AuthViewModel,
    isScreenActive: Boolean = true,
    bottomContentPadding: PaddingValues = PaddingValues(bottom = 96.dp)
) {
    if (state.isGuestMode || !state.isLoggedIn || state.currentUser == null) {
        QrGuestGate(onGoToLogin = viewModel::leaveGuestForOnboarding)
        return
    }
    if (!state.currentUser.hasVerifiedPhone) {
        QrPhoneRequiredGate(
            userName = state.currentUser.displayFullName,
            onLinkPhone = viewModel::openPhoneLinkingFromApp
        )
        return
    }

    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    var isLifecycleResumed by remember(lifecycleOwner) {
        mutableStateOf(lifecycleOwner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED))
    }
    var companionsCount by remember { mutableIntStateOf(0) }
    var torchEnabled by remember { mutableStateOf(false) }
    var lastScannedAtMs by remember { mutableLongStateOf(0L) }
    var lastScannedRaw by remember { mutableStateOf<String?>(null) }

    var cameraPermissionGranted by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
        )
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> isLifecycleResumed = true
                Lifecycle.Event.ON_PAUSE, Lifecycle.Event.ON_STOP -> {
                    isLifecycleResumed = false
                    torchEnabled = false
                }
                else -> {}
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            torchEnabled = false
        }
    }

    val cameraShouldRun = isScreenActive && cameraPermissionGranted && isLifecycleResumed

    LaunchedEffect(cameraShouldRun) {
        if (!cameraShouldRun) {
            torchEnabled = false
        }
    }

    val cameraPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        cameraPermissionGranted = granted
    }

    val galleryLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        if (uri != null) {
            try {
                val img = InputImage.fromFilePath(context, uri)
                BarcodeScanning.getClient().process(img)
                    .addOnSuccessListener { barcodes ->
                        val raw = barcodes.firstOrNull()?.rawValue
                        if (!raw.isNullOrBlank()) {
                            viewModel.payPassageWithQr(raw, companionsCount)
                        } else {
                            viewModel.payPassageWithQr("INVALID", companionsCount)
                        }
                    }
            } catch (_: Exception) {
            }
        }
    }

    LaunchedEffect(Unit) {
        if (!cameraPermissionGranted) {
            cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    val user = state.currentUser
    var cooldownRemainingSec by remember { mutableIntStateOf(viewModel.getStudentCooldownRemainingSeconds()) }
    LaunchedEffect(user.roleType, state.ledgerTransactions.size) {
        while (true) {
            val rem = viewModel.getStudentCooldownRemainingSeconds()
            cooldownRemainingSec = rem
            if (rem <= 0) break
            kotlinx.coroutines.delay(1000)
        }
    }
    val isStudentCooldownActive = user.roleType == UserRoleType.STUDENT && cooldownRemainingSec > 0
    val holderFare = if (isStudentCooldownActive) 15 else user.roleType.farePoints
    val totalPoints = holderFare + companionsCount * 15
    val totalPen = totalPoints / 10.0

    val infiniteTransition = rememberInfiniteTransition(label = "qrLaser")
    val laserProgress by infiniteTransition.animateFloat(
        initialValue = 0.08f,
        targetValue = 0.92f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1900, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "laserSweep"
    )

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF070B12))
    ) {
        val density = LocalDensity.current
        val scanBoxDp = 248.dp
        val scanBoxPx = with(density) { scanBoxDp.toPx() }
        val cornerRadiusPx = with(density) { 24.dp.toPx() }
        val cutoutCenterYFraction = 0.34f
        val cutoutTopDp = maxHeight * cutoutCenterYFraction - scanBoxDp / 2f

        // 1. Cámara Edge-to-Edge SOLO activa mientras está visible y en primer plano
        if (cameraShouldRun) {
            CameraXQrPreview(
                shouldRun = cameraShouldRun,
                torchEnabled = torchEnabled,
                onQrDetected = { raw ->
                    val now = System.currentTimeMillis()
                    if (raw != lastScannedRaw || now - lastScannedAtMs > 2200L) {
                        lastScannedRaw = raw
                        lastScannedAtMs = now
                        viewModel.payPassageWithQr(raw, companionsCount)
                    }
                }
            )
        } else {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        Brush.verticalGradient(
                            listOf(Color(0xFF0B111C), Color(0xFF06090F))
                        )
                    )
            )
        }

        // 2. Máscara oscura translúcida estilo Yape con ventana transparente recortada
        Canvas(
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
        ) {
            drawRect(color = Color.Black.copy(alpha = 0.60f))
            val left = (size.width - scanBoxPx) / 2f
            val top = size.height * cutoutCenterYFraction - scanBoxPx / 2f
            drawRoundRect(
                color = Color.Transparent,
                topLeft = Offset(left, top),
                size = Size(scanBoxPx, scanBoxPx),
                cornerRadius = CornerRadius(cornerRadiusPx, cornerRadiusPx),
                blendMode = BlendMode.Clear
            )
        }

        // 3. Esquinas blancas + línea láser esmeralda animada dentro de la ventana
        Canvas(modifier = Modifier.fillMaxSize()) {
            val left = (size.width - scanBoxPx) / 2f
            val top = size.height * cutoutCenterYFraction - scanBoxPx / 2f
            val right = left + scanBoxPx
            val bottom = top + scanBoxPx
            val bracketLen = 30.dp.toPx()
            val stroke = 3.5.dp.toPx()
            val pad = 2.dp.toPx()

            val white = Color.White.copy(alpha = 0.96f)
            // Top-Left
            drawLine(white, Offset(left + pad, top + bracketLen), Offset(left + pad, top + pad), stroke, StrokeCap.Round)
            drawLine(white, Offset(left + pad, top + pad), Offset(left + bracketLen, top + pad), stroke, StrokeCap.Round)
            // Top-Right
            drawLine(white, Offset(right - bracketLen, top + pad), Offset(right - pad, top + pad), stroke, StrokeCap.Round)
            drawLine(white, Offset(right - pad, top + pad), Offset(right - pad, top + bracketLen), stroke, StrokeCap.Round)
            // Bottom-Left
            drawLine(white, Offset(left + pad, bottom - bracketLen), Offset(left + pad, bottom - pad), stroke, StrokeCap.Round)
            drawLine(white, Offset(left + pad, bottom - pad), Offset(left + bracketLen, bottom - pad), stroke, StrokeCap.Round)
            // Bottom-Right
            drawLine(white, Offset(right - bracketLen, bottom - pad), Offset(right - pad, bottom - pad), stroke, StrokeCap.Round)
            drawLine(white, Offset(right - pad, bottom - pad), Offset(right - pad, bottom - bracketLen), stroke, StrokeCap.Round)

            if (cameraShouldRun) {
                val laserY = top + scanBoxPx * laserProgress
                drawLine(
                    brush = Brush.horizontalGradient(
                        listOf(Color.Transparent, BCColors.Emerald, Color(0xFF6EE7B7), BCColors.Emerald, Color.Transparent),
                        startX = left + 16.dp.toPx(),
                        endX = right - 16.dp.toPx()
                    ),
                    start = Offset(left + 16.dp.toPx(), laserY),
                    end = Offset(right - 16.dp.toPx(), laserY),
                    strokeWidth = 2.5.dp.toPx(),
                    cap = StrokeCap.Round
                )
            }
        }

        // Permiso pendiente dentro de la ventana central
        if (!cameraPermissionGranted) {
            Column(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .offset(y = cutoutTopDp + 48.dp)
                    .width(220.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Icon(Icons.Default.QrCodeScanner, contentDescription = null, tint = BCColors.Emerald, modifier = Modifier.size(44.dp))
                Text(
                    "Autoriza la cámara para escanear el QR en la puerta del bus.",
                    color = Color.White,
                    fontSize = 12.sp,
                    textAlign = TextAlign.Center
                )
                Button(
                    onClick = { cameraPermissionLauncher.launch(Manifest.permission.CAMERA) },
                    colors = ButtonDefaults.buttonColors(containerColor = BCColors.Emerald, contentColor = Color.Black),
                    shape = RoundedCornerShape(50)
                ) {
                    Text("Activar cámara", fontWeight = FontWeight.Bold, fontSize = 12.sp)
                }
            }
        }

        // Cápsula guía debajo de la ventana de escaneo
        Surface(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .offset(y = cutoutTopDp + scanBoxDp + 16.dp)
                .padding(horizontal = 24.dp),
            shape = RoundedCornerShape(50),
            color = Color.Black.copy(alpha = 0.52f),
            border = BorderStroke(1.dp, Color.White.copy(alpha = 0.14f))
        ) {
            Text(
                "Enfoca el código QR del validador en la puerta del bus",
                color = Color.White.copy(alpha = 0.92f),
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp)
            )
        }

        // 4. Cabecera superior flotante estilo Yape
        Row(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    "Pagar con QR",
                    color = Color.White,
                    fontSize = 21.sp,
                    fontWeight = FontWeight.Black
                )
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(8.dp)
                            .clip(CircleShape)
                            .background(if (cameraShouldRun) BCColors.Emerald else BCColors.Amber)
                    )
                    Text(
                        if (cameraShouldRun) "Cámara activa solo en esta pantalla" else "Cámara en pausa por privacidad",
                        color = Color.White.copy(alpha = 0.85f),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Medium
                    )
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Surface(
                    modifier = Modifier.size(42.dp),
                    shape = CircleShape,
                    color = if (torchEnabled) BCColors.Amber.copy(alpha = 0.28f) else Color.Black.copy(alpha = 0.48f),
                    border = BorderStroke(1.dp, Color.White.copy(alpha = 0.20f))
                ) {
                    IconButton(
                        enabled = cameraShouldRun,
                        onClick = { torchEnabled = !torchEnabled }
                    ) {
                        Icon(
                            if (torchEnabled) Icons.Default.FlashlightOn else Icons.Default.FlashlightOff,
                            contentDescription = "Linterna",
                            tint = if (torchEnabled) BCColors.Amber else Color.White,
                            modifier = Modifier.size(20.dp)
                        )
                    }
                }

                Surface(
                    modifier = Modifier.size(42.dp),
                    shape = CircleShape,
                    color = Color.Black.copy(alpha = 0.48f),
                    border = BorderStroke(1.dp, Color.White.copy(alpha = 0.20f))
                ) {
                    IconButton(onClick = {
                        torchEnabled = false
                        viewModel.selectTab(MainAppTab.EXPLORE)
                    }) {
                        Icon(
                            Icons.Default.Close,
                            contentDescription = "Cerrar escáner QR",
                            tint = Color.White,
                            modifier = Modifier.size(20.dp)
                        )
                    }
                }
            }
        }

        // 5. Panel inferior translúcido estilo Yape (encima del dock flotante)
        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .padding(horizontal = 14.dp)
                .padding(bottom = bottomContentPadding.calculateBottomPadding() + 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            if (!state.qrErrorMessage.isNullOrBlank()) {
                Surface(
                    shape = RoundedCornerShape(14.dp),
                    color = Color(0xD9450A0A),
                    border = BorderStroke(1.dp, BCColors.DestructiveRed.copy(alpha = 0.65f))
                ) {
                    Text(
                        state.qrErrorMessage,
                        color = Color.White,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 12.dp, vertical = 8.dp)
                    )
                }
            }

            Surface(
                shape = RoundedCornerShape(24.dp),
                color = Color(0xCF0F1521),
                border = BorderStroke(1.dp, Color.White.copy(alpha = 0.16f)),
                shadowElevation = 14.dp
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    // Tarifa titular + Saldo actual
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Surface(
                            shape = RoundedCornerShape(50),
                            color = (if (isStudentCooldownActive) BCColors.Amber else BCColors.Emerald).copy(alpha = 0.16f),
                            border = BorderStroke(1.dp, (if (isStudentCooldownActive) BCColors.Amber else BCColors.Emerald).copy(alpha = 0.4f))
                        ) {
                            Text(
                                when {
                                    isStudentCooldownActive -> "Espera Univ. (${cooldownRemainingSec}s) · 15 pts"
                                    user.roleType == UserRoleType.STUDENT -> "Tarifa Universitaria · 7 pts"
                                    user.roleType == UserRoleType.CONADIS -> "CONADIS · 0 pts"
                                    else -> "Tarifa Adulto · 15 pts"
                                },
                                color = if (isStudentCooldownActive) BCColors.Amber else BCColors.Emerald,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp)
                            )
                        }
                        Text(
                            "Saldo: ${user.pointsBalance} pts",
                            color = Color.White.copy(alpha = 0.9f),
                            fontSize = 12.sp,
                            fontWeight = FontWeight.ExtraBold
                        )
                    }

                    if (isStudentCooldownActive) {
                        val mins = cooldownRemainingSec / 60
                        val secs = cooldownRemainingSec % 60
                        val timerFormatted = String.format(Locale.US, "%02d:%02d", mins, secs)
                        Surface(
                            shape = RoundedCornerShape(12.dp),
                            color = BCColors.Amber.copy(alpha = 0.16f),
                            border = BorderStroke(1.dp, BCColors.Amber.copy(alpha = 0.55f)),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(
                                text = "⏳ Tiempo de espera universitario ($timerFormatted): se cobrará S/. 1.50 (15 pts) hasta que el contador llegue a 00:00.",
                                color = BCColors.Amber,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp)
                            )
                        }
                    }

                    HorizontalDivider(color = Color.White.copy(alpha = 0.10f))

                    // Regla RN-07: Titular + hasta 4 acompañantes
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier.weight(1f)
                        ) {
                            Icon(Icons.Default.Group, contentDescription = null, tint = BCColors.CyanAccent, modifier = Modifier.size(18.dp))
                            Column {
                                Text("Acompañantes (RN-07)", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                                Text(
                                    "$totalPoints pts · S/. ${String.format(Locale.US, "%.2f", totalPen)}",
                                    color = BCColors.Emerald,
                                    fontWeight = FontWeight.ExtraBold,
                                    fontSize = 12.sp
                                )
                            }
                        }

                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            IconButton(
                                onClick = { if (companionsCount > 0) companionsCount-- },
                                modifier = Modifier
                                    .size(32.dp)
                                    .clip(CircleShape)
                                    .background(Color.White.copy(alpha = 0.12f))
                            ) {
                                Icon(Icons.Default.Remove, contentDescription = "Menos", tint = Color.White, modifier = Modifier.size(16.dp))
                            }
                            Text(
                                "$companionsCount",
                                color = Color.White,
                                fontWeight = FontWeight.Black,
                                fontSize = 16.sp,
                                textAlign = TextAlign.Center,
                                modifier = Modifier.widthIn(min = 22.dp)
                            )
                            IconButton(
                                onClick = { if (companionsCount < 4) companionsCount++ },
                                modifier = Modifier
                                    .size(32.dp)
                                    .clip(CircleShape)
                                    .background(BCColors.RoyalBlue)
                            ) {
                                Icon(Icons.Default.Add, contentDescription = "Más", tint = Color.White, modifier = Modifier.size(16.dp))
                            }
                        }
                    }

                    // Subir código QR desde galería (escaneo fotográfico)
                    Row(
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Surface(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(42.dp)
                                .clickable { galleryLauncher.launch("image/*") },
                            shape = RoundedCornerShape(12.dp),
                            color = Color.White.copy(alpha = 0.08f),
                            border = BorderStroke(1.dp, Color.White.copy(alpha = 0.16f))
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.Center
                            ) {
                                Icon(Icons.Default.PhotoLibrary, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
                                Spacer(Modifier.width(8.dp))
                                Text(
                                    "Subir imagen QR desde galería",
                                    color = Color.White,
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalGetImage::class)
@Composable
private fun CameraXQrPreview(
    shouldRun: Boolean,
    torchEnabled: Boolean,
    onQrDetected: (String) -> Unit
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var camera by remember { mutableStateOf<Camera?>(null) }
    var boundProvider by remember { mutableStateOf<ProcessCameraProvider?>(null) }
    val executor = remember { Executors.newSingleThreadExecutor() }

    val previewView = remember {
        PreviewView(context).apply {
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            scaleType = PreviewView.ScaleType.FILL_CENTER
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
    }

    LaunchedEffect(torchEnabled, camera, shouldRun) {
        try {
            camera?.cameraControl?.enableTorch(shouldRun && torchEnabled)
        } catch (_: Exception) {
        }
    }

    DisposableEffect(shouldRun, lifecycleOwner) {
        var cancelled = false
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            if (cancelled) return@addListener
            val provider = try {
                future.get()
            } catch (_: Exception) {
                null
            } ?: return@addListener
            boundProvider = provider

            if (!shouldRun || !lifecycleOwner.lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) {
                try {
                    provider.unbindAll()
                } catch (_: Exception) {
                }
                camera = null
                return@addListener
            }

            val preview = Preview.Builder().build().apply {
                setSurfaceProvider(previewView.surfaceProvider)
            }
            val scanner = BarcodeScanning.getClient()
            val analysis = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
                .apply {
                    setAnalyzer(executor) { imageProxy ->
                        val mediaImage = imageProxy.image
                        if (mediaImage != null && shouldRun) {
                            val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
                            scanner.process(image)
                                .addOnSuccessListener { barcodes ->
                                    val qr = barcodes.firstOrNull()?.rawValue
                                    if (!qr.isNullOrBlank()) {
                                        onQrDetected(qr)
                                    }
                                }
                                .addOnCompleteListener {
                                    imageProxy.close()
                                }
                        } else {
                            imageProxy.close()
                        }
                    }
                }

            try {
                provider.unbindAll()
                camera = provider.bindToLifecycle(
                    lifecycleOwner,
                    CameraSelector.DEFAULT_BACK_CAMERA,
                    preview,
                    analysis
                )
                camera?.cameraControl?.enableTorch(torchEnabled)
            } catch (_: Exception) {
            }
        }, ContextCompat.getMainExecutor(context))

        onDispose {
            cancelled = true
            try {
                camera?.cameraControl?.enableTorch(false)
            } catch (_: Exception) {
            }
            camera = null
            try {
                boundProvider?.unbindAll()
            } catch (_: Exception) {
            }
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            try {
                boundProvider?.unbindAll()
            } catch (_: Exception) {
            }
            executor.shutdown()
        }
    }

    AndroidView(
        modifier = Modifier.fillMaxSize(),
        factory = { previewView }
    )
}

@Composable
private fun QrGuestGate(onGoToLogin: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(BCColors.DarkBackground)
            .padding(28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Box(
            modifier = Modifier
                .size(76.dp)
                .clip(CircleShape)
                .background(BCColors.RoyalBlue.copy(alpha = 0.16f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(Icons.Default.QrCodeScanner, contentDescription = null, tint = BCColors.RoyalBlue, modifier = Modifier.size(38.dp))
        }
        Spacer(Modifier.height(16.dp))
        Text("Pago QR requiere cuenta", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(8.dp))
        Text(
            "Inicia sesión o regístrate con tu celular para pagar tu pasaje con Monedero BC.",
            color = BCColors.TextSecondary,
            textAlign = TextAlign.Center,
            fontSize = 14.sp
        )
        Spacer(Modifier.height(22.dp))
        Button(
            onClick = onGoToLogin,
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp),
            shape = RoundedCornerShape(14.dp),
            colors = ButtonDefaults.buttonColors(containerColor = BCColors.Emerald)
        ) {
            Text("Iniciar Sesión o Crear Cuenta", color = Color.Black, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun QrPhoneRequiredGate(userName: String, onLinkPhone: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(BCColors.DarkBackground)
            .padding(28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Box(
            modifier = Modifier
                .size(76.dp)
                .clip(CircleShape)
                .background(BCColors.Emerald.copy(alpha = 0.16f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(Icons.Default.QrCodeScanner, contentDescription = null, tint = BCColors.Emerald, modifier = Modifier.size(38.dp))
        }
        Spacer(Modifier.height(14.dp))
        Text("Hola, $userName", color = BCColors.CyanAccent, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(6.dp))
        Text(
            "Accede con tu número celular para poder hacer pagos QR",
            color = Color.White,
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.height(8.dp))
        Text(
            "Si desea hacer pagos dentro de la app o acceder a los beneficios como descuentos o promociones, registre su celular.",
            color = BCColors.TextSecondary,
            textAlign = TextAlign.Center,
            fontSize = 14.sp
        )
        Spacer(Modifier.height(22.dp))
        Button(
            onClick = onLinkPhone,
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp),
            shape = RoundedCornerShape(14.dp),
            colors = ButtonDefaults.buttonColors(containerColor = BCColors.Emerald)
        ) {
            Text("Vincular número celular", color = Color.Black, fontWeight = FontWeight.Bold)
        }
    }
}

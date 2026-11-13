package pe.edu.unjbg.busconectado.feature.explore

import android.graphics.Color as AndroidColor
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Directions
import androidx.compose.material.icons.filled.DirectionsBus
import androidx.compose.material.icons.filled.DirectionsWalk
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Sensors
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import pe.edu.unjbg.busconectado.core.designsystem.BCColors
import pe.edu.unjbg.busconectado.core.location.GeoPointData
import pe.edu.unjbg.busconectado.core.model.ActiveBusModel
import pe.edu.unjbg.busconectado.core.model.ActiveRouteGuidanceState
import pe.edu.unjbg.busconectado.core.model.BusStopModel
import pe.edu.unjbg.busconectado.core.model.EvaluatedCandidateKind
import pe.edu.unjbg.busconectado.core.model.MapFilterCategory
import pe.edu.unjbg.busconectado.core.model.StopNotificationAvailability
import pe.edu.unjbg.busconectado.core.model.TacnaDestinationPlace
import pe.edu.unjbg.busconectado.core.ui.BCOsmMapView
import pe.edu.unjbg.busconectado.core.ui.MapMarkerKind
import pe.edu.unjbg.busconectado.core.ui.MapMarkerSpec
import pe.edu.unjbg.busconectado.core.ui.MapPolylineSpec
import pe.edu.unjbg.busconectado.feature.auth.AuthViewModel
import pe.edu.unjbg.busconectado.feature.auth.BCUiState
import java.util.Locale
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExploreMapScreen(
    state: BCUiState,
    viewModel: AuthViewModel,
    onDismissSearchFocus: () -> Unit,
    bottomInsetPadding: PaddingValues = PaddingValues(bottom = 86.dp)
) {
    val scope = rememberCoroutineScope()

    var selectedCatalogStop by remember { mutableStateOf<TacnaDestinationPlace?>(null) }
    var selectedBus by remember { mutableStateOf<ActiveBusModel?>(null) }
    var advanceMinutes by remember { mutableIntStateOf(5) }
    var imminentAlert by remember { mutableStateOf(true) }
    var isPinDropMode by remember { mutableStateOf(false) }

    var guidedWalkStreetCoords by remember { mutableStateOf<List<GeoPointData>>(emptyList()) }
    var guidedBusStreetCoords by remember { mutableStateOf<List<GeoPointData>>(emptyList()) }
    var guidedFinalStreetCoords by remember { mutableStateOf<List<GeoPointData>>(emptyList()) }
    var projectedRouteCoords by remember { mutableStateOf<List<GeoPointData>>(emptyList()) }

    val guidance = state.activeRouteGuidance
    LaunchedEffect(guidance?.candidate?.id) {
        val cand = guidance?.candidate
        if (cand == null) {
            guidedWalkStreetCoords = emptyList()
            guidedBusStreetCoords = emptyList()
            guidedFinalStreetCoords = emptyList()
        } else {
            val wDeferred = async { viewModel.networkClient.alignPolylineToStreets(cand.walkToBoardCoords, isWalking = true) }
            val bDeferred = async {
                if (cand.busTransitCoords.size > 6) cand.busTransitCoords
                else viewModel.networkClient.alignPolylineToStreets(cand.busTransitCoords, isWalking = false)
            }
            val fDeferred = async { viewModel.networkClient.alignPolylineToStreets(cand.walkFinalCoords, isWalking = true) }
            guidedWalkStreetCoords = wDeferred.await()
            guidedBusStreetCoords = bDeferred.await()
            guidedFinalStreetCoords = fDeferred.await()
        }
    }

    LaunchedEffect(state.activeRouteOverlayOnMap?.id) {
        val overlay = state.activeRouteOverlayOnMap
        if (overlay == null) {
            projectedRouteCoords = emptyList()
        } else {
            val raw = overlay.resolvedPolylineCoordinates(state.dynamicCatalogStops)
            projectedRouteCoords = if (raw.size > 6) raw else viewModel.networkClient.alignPolylineToStreets(raw, isWalking = false)
        }
    }

    val polylines = remember(
        state.mapCategory,
        state.activeRouteOverlayOnMap,
        projectedRouteCoords,
        state.dynamicRoutes,
        guidance,
        guidedWalkStreetCoords,
        guidedBusStreetCoords,
        guidedFinalStreetCoords
    ) {
        buildList {
            val projected = state.activeRouteOverlayOnMap
            if (projected != null) {
                val pts = if (projectedRouteCoords.size >= 2) projectedRouteCoords
                else projected.resolvedPolylineCoordinates(state.dynamicCatalogStops)
                add(
                    MapPolylineSpec(
                        id = "projected_${projected.id}",
                        points = pts,
                        colorArgb = BCColors.fromHex(projected.colorHex).toArgb(),
                        strokeWidthPx = 12f,
                        dashed = projected.isExternal
                    )
                )
            } else if (state.mapCategory == MapFilterCategory.ROUTES) {
                state.dynamicRoutes.filter { it.isOrdinaryInService }.forEach { route ->
                    val pts = route.resolvedPolylineCoordinates(state.dynamicCatalogStops)
                    add(
                        MapPolylineSpec(
                            id = "route_${route.id}",
                            points = pts,
                            colorArgb = BCColors.fromHex(route.colorHex).toArgb(),
                            strokeWidthPx = 10f
                        )
                    )
                }
            }

            if (guidance != null && guidance.candidate != null) {
                val cand = guidance.candidate
                val walkPts = if (guidedWalkStreetCoords.size >= 2) guidedWalkStreetCoords else cand.walkToBoardCoords
                if (walkPts.size >= 2) {
                    add(
                        MapPolylineSpec(
                            id = "guide_walk_1",
                            points = walkPts,
                            colorArgb = BCColors.CyanAccent.toArgb(),
                            strokeWidthPx = 9f,
                            dashed = true
                        )
                    )
                }
                if (cand.kind != EvaluatedCandidateKind.WALKING_DIRECT) {
                    val isOrd = cand.kind == EvaluatedCandidateKind.ORDINARY_IN_SERVICE
                    val busPts = if (guidedBusStreetCoords.size >= 2) guidedBusStreetCoords else cand.busTransitCoords
                    if (busPts.size >= 2) {
                        add(
                            MapPolylineSpec(
                                id = "guide_bus",
                                points = busPts,
                                colorArgb = if (isOrd) 0xFF00E5FF.toInt() else BCColors.fromHex(cand.colorHex).toArgb(),
                                strokeWidthPx = 13f,
                                dashed = !isOrd
                            )
                        )
                    }
                    if (cand.isTransfer && cand.transferWalkCoords.size >= 2) {
                        add(
                            MapPolylineSpec(
                                id = "guide_transfer_walk",
                                points = cand.transferWalkCoords,
                                colorArgb = BCColors.CyanAccent.toArgb(),
                                strokeWidthPx = 9f,
                                dashed = true
                            )
                        )
                    }
                    if (cand.isTransfer && cand.secondBusTransitCoords.size >= 2) {
                        add(
                            MapPolylineSpec(
                                id = "guide_bus2",
                                points = cand.secondBusTransitCoords,
                                colorArgb = BCColors.fromHex(cand.secondRouteColorHex ?: cand.colorHex).toArgb(),
                                strokeWidthPx = 13f,
                                dashed = !isOrd
                            )
                        )
                    }
                }
                val finalPts = if (guidedFinalStreetCoords.size >= 2) guidedFinalStreetCoords else cand.walkFinalCoords
                if (finalPts.size >= 2) {
                    add(
                        MapPolylineSpec(
                            id = "guide_walk_2",
                            points = finalPts,
                            colorArgb = BCColors.CyanAccent.toArgb(),
                            strokeWidthPx = 9f,
                            dashed = true
                        )
                    )
                }
            }
        }
    }

    val visibleStops = remember(state.mapCategory, state.activeRouteOverlayOnMap, state.dynamicCatalogStops) {
        val overlay = state.activeRouteOverlayOnMap
        when {
            overlay != null -> overlay.resolvedStops(state.dynamicCatalogStops)
            state.mapCategory == MapFilterCategory.STOPS -> state.dynamicCatalogStops
            else -> emptyList()
        }
    }

    val markers = remember(
        state.userLocation,
        visibleStops,
        state.activeBuses,
        state.searchedDestinationPin,
        guidance
    ) {
        buildList {
            add(
                MapMarkerSpec(
                    id = "user_location",
                    point = guidance?.origin?.coordinate ?: state.userLocation,
                    kind = MapMarkerKind.USER_ORIGIN_DOT,
                    colorArgb = BCColors.RoyalBlue.toArgb()
                )
            )
            visibleStops.forEach { stop ->
                add(
                    MapMarkerSpec(
                        id = "stop:${stop.id}",
                        point = stop.coordinate,
                        kind = MapMarkerKind.TRANSIT_STOP_DOT,
                        colorArgb = BCColors.fromHex(stop.colorHex).toArgb(),
                        label = stop.shortName
                    )
                )
            }
            if (guidance?.candidate != null && guidance.candidate.kind != EvaluatedCandidateKind.WALKING_DIRECT) {
                val cand = guidance.candidate
                val isOrd = cand.kind == EvaluatedCandidateKind.ORDINARY_IN_SERVICE
                add(
                    MapMarkerSpec(
                        id = "guide_board",
                        point = cand.boardingCoordinate,
                        kind = MapMarkerKind.TRANSIT_STOP_DOT,
                        colorArgb = (if (isOrd) BCColors.Emerald else BCColors.Amber).toArgb()
                    )
                )
                add(
                    MapMarkerSpec(
                        id = "guide_alight",
                        point = cand.alightingCoordinate,
                        kind = MapMarkerKind.TRANSIT_STOP_DOT,
                        colorArgb = BCColors.CyanAccent.toArgb()
                    )
                )
            }
            val subscribedTrip = state.activeTrip?.takeIf { it.isConfirmedOnBoard == true }
            val busesToRender = if (subscribedTrip != null) {
                state.activeBuses.filter {
                    it.unitNumber.equals(subscribedTrip.unitNumber, ignoreCase = true) ||
                    it.plate.equals(subscribedTrip.plate, ignoreCase = true)
                }
            } else {
                state.activeBuses
            }
            busesToRender.forEach { bus ->
                add(
                    MapMarkerSpec(
                        id = "bus:${bus.id}",
                        point = bus.coordinate,
                        kind = MapMarkerKind.LIVE_BUS,
                        colorArgb = BCColors.RoyalBlue.toArgb(),
                        label = "${bus.unitNumber} · ${bus.nextStopEtaMinutes}m"
                    )
                )
            }
            val destPin = guidance?.destination ?: state.searchedDestinationPin
            if (destPin != null) {
                add(
                    MapMarkerSpec(
                        id = "dest:${destPin.id}",
                        point = destPin.coordinate,
                        kind = MapMarkerKind.DESTINATION_PIN,
                        colorArgb = BCColors.DestructiveRed.toArgb(),
                        label = destPin.shortName
                    )
                )
            }
        }
    }

    val ordinaryInServiceCount = state.dynamicRoutes.count { it.isOrdinaryInService }

    Box(modifier = Modifier.fillMaxSize()) {
        // 1. Mapa Dark OSMDroid de Tacna a pantalla completa
        BCOsmMapView(
            modifier = Modifier.fillMaxSize(),
            cameraCommand = state.cameraFocus,
            polylines = polylines,
            markers = markers,
            onMarkerClick = { markerId ->
                onDismissSearchFocus()
                when {
                    markerId.startsWith("stop:") -> {
                        val id = markerId.removePrefix("stop:")
                        selectedCatalogStop = state.dynamicCatalogStops.firstOrNull { it.id == id }
                    }
                    markerId.startsWith("bus:") -> {
                        val id = markerId.removePrefix("bus:")
                        selectedBus = state.activeBuses.firstOrNull { it.id == id }
                    }
                    markerId.startsWith("dest:") -> {
                        val dest = guidance?.destination ?: state.searchedDestinationPin
                        if (dest != null) {
                            selectedCatalogStop = dest
                        }
                    }
                }
            },
            onMapTap = if (isPinDropMode) {
                { point ->
                    isPinDropMode = false
                    scope.launch {
                        val place = viewModel.networkClient.reverseGeocodeInTacna(point)
                        viewModel.focusMapOnPlace(place)
                        selectedCatalogStop = place
                    }
                }
            } else {
                { onDismissSearchFocus() }
            }
        )

        // 2. Degradado translúcido superior
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(108.dp)
                .background(
                    Brush.verticalGradient(
                        listOf(Color.Black.copy(alpha = 0.72f), Color.Transparent)
                    )
                )
        )

        // 3. Controles superiores bajo el buscador flotante
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(top = 62.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            // Chips de filtro + Pin Manual
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = 14.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                MapFilterCategory.entries.forEach { cat ->
                    val selected = state.mapCategory == cat && state.activeRouteOverlayOnMap == null
                    val label = when (cat) {
                        MapFilterCategory.LIVE -> if (state.activeBuses.isEmpty()) "En vivo" else "En vivo (${state.activeBuses.count()})"
                        MapFilterCategory.ROUTES -> "Rutas ($ordinaryInServiceCount)"
                        MapFilterCategory.STOPS -> "Paraderos (${state.dynamicCatalogStops.size})"
                    }
                    val icon = when (cat) {
                        MapFilterCategory.LIVE -> Icons.Default.Sensors
                        MapFilterCategory.ROUTES -> Icons.Default.DirectionsBus
                        MapFilterCategory.STOPS -> Icons.Default.Place
                    }
                    Surface(
                        modifier = Modifier.clickable {
                            onDismissSearchFocus()
                            viewModel.selectMapCategory(cat)
                        },
                        shape = RoundedCornerShape(50),
                        color = if (selected) BCColors.RoyalBlue else BCColors.ControlSurface.copy(alpha = 0.94f),
                        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.14f)),
                        shadowElevation = 4.dp
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 13.dp, vertical = 7.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(5.dp)
                        ) {
                            Icon(
                                icon,
                                contentDescription = null,
                                tint = if (selected) Color.White else BCColors.CyanAccent,
                                modifier = Modifier.size(14.dp)
                            )
                            Text(
                                label,
                                color = Color.White,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                    }
                }

                // Chip de Pin Manual en mapa
                Surface(
                    modifier = Modifier.clickable {
                        onDismissSearchFocus()
                        isPinDropMode = !isPinDropMode
                    },
                    shape = RoundedCornerShape(50),
                    color = if (isPinDropMode) BCColors.CyanAccent else BCColors.ControlSurface.copy(alpha = 0.94f),
                    border = BorderStroke(1.dp, if (isPinDropMode) Color.White else BCColors.CyanAccent.copy(alpha = 0.4f)),
                    shadowElevation = 4.dp
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 13.dp, vertical = 7.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(5.dp)
                    ) {
                        Icon(
                            Icons.Default.TouchApp,
                            contentDescription = null,
                            tint = if (isPinDropMode) Color.Black else BCColors.CyanAccent,
                            modifier = Modifier.size(14.dp)
                        )
                        Text(
                            if (isPinDropMode) "Toca el mapa..." else "Pin en mapa",
                            color = if (isPinDropMode) Color.Black else Color.White,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
            }

            // Píldora de Ruta proyectada
            state.activeRouteOverlayOnMap?.let { projected ->
                val stopsInRoute = projected.resolvedStops(state.dynamicCatalogStops)
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp),
                    shape = RoundedCornerShape(50),
                    color = BCColors.ControlSurface.copy(alpha = 0.95f),
                    border = BorderStroke(1.dp, BCColors.HairlineBorder)
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 7.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Surface(shape = RoundedCornerShape(6.dp), color = BCColors.fromHex(projected.colorHex)) {
                            Text(
                                projected.code,
                                color = Color.White,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Black,
                                modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp)
                            )
                        }
                        Text(
                            "${if (projected.isOrdinaryInService) "En servicio" else "Referencial"} · ${stopsInRoute.size} paraderos · ~${projected.estimatedTotalMinutes}m",
                            color = Color.White,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.weight(1f),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        IconButton(
                            onClick = { viewModel.clearRouteOverlayOnMap() },
                            modifier = Modifier.size(22.dp)
                        ) {
                            Icon(Icons.Default.Close, contentDescription = "Cerrar ruta", tint = Color.White, modifier = Modifier.size(16.dp))
                        }
                    }
                }
            }

            // Estándar minimalista unificado para cualquier guía activa "Ir" + Pop-up retirable
            if (guidance != null) {
                MinimalistGuidanceBar(
                    guidance = guidance,
                    onTapOpenPlanner = {
                        viewModel.openRoutePlanner(destination = guidance.destination, origin = guidance.origin)
                    },
                    onCancelClick = { viewModel.promptCancelGuidedRoute() }
                )

                val cand = guidance.candidate
                if (state.showFiveMinuteBoardingBanner && cand?.kind == EvaluatedCandidateKind.ORDINARY_IN_SERVICE) {
                    DismissibleBannerPopup(
                        accentColor = BCColors.Emerald,
                        bgColor = Color(0xFF052E16),
                        title = "${cand.routeCode} a ≤ 5 min del paradero",
                        message = "Camina a ${cand.boardingPointName} (~${cand.walkInitialMinutes}m) rumbo a ${guidance.destination.shortName}.",
                        onDismiss = { viewModel.dismissFiveMinuteBanner() }
                    )
                } else if (state.showExternalGuidancePopup && cand?.kind == EvaluatedCandidateKind.EXTERNAL_FREE_BOARDING) {
                    DismissibleBannerPopup(
                        accentColor = BCColors.Amber,
                        bgColor = BCColors.ElevatedSurface,
                        title = "${cand.routeCode} · Ruta externa (sin GPS)",
                        message = "Abordaje en ${cand.boardingPointName}. Sin temporizador ni avisos de llegada; desliza para retirar.",
                        onDismiss = { viewModel.dismissExternalGuidancePopup() }
                    )
                }
            }

            // Aviso de tarifa / pago QR (incluyendo aviso de espera universitaria de 2 min)
            state.qrSuccessMessage?.let { msg ->
                DismissibleBannerPopup(
                    accentColor = if (msg.contains("espera", ignoreCase = true)) BCColors.Amber else BCColors.Emerald,
                    bgColor = BCColors.ElevatedSurface,
                    title = if (msg.contains("espera", ignoreCase = true)) "Espera Universitaria Activa" else "Validación de Abordaje",
                    message = msg,
                    onDismiss = { viewModel.clearQrMessages() }
                )
            }

            // Pregunta en vivo: ¿Te encuentras a bordo del bus? -> Suscripción a alertas
            state.activeTrip?.let { trip ->
                if (trip.isConfirmedOnBoard == null) {
                    Surface(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 14.dp),
                        shape = RoundedCornerShape(16.dp),
                        color = BCColors.ElevatedSurface.copy(alpha = 0.96f),
                        border = BorderStroke(1.2.dp, BCColors.SkyBlue.copy(alpha = 0.55f)),
                        shadowElevation = 6.dp
                    ) {
                        Column(
                            modifier = Modifier.padding(14.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            Text(
                                "¿Te encuentras a bordo de la unidad ${trip.unitNumber}?",
                                color = Color.White,
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Bold
                            )
                            Text(
                                "Si confirmas, monitorearemos la velocidad del bus en tiempo real y te avisaremos 200m antes de tu paradero.",
                                color = BCColors.TextSecondary,
                                fontSize = 12.sp
                            )
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Button(
                                    onClick = { viewModel.confirmOnBoardStatus(true) },
                                    colors = ButtonDefaults.buttonColors(containerColor = BCColors.Emerald),
                                    modifier = Modifier.weight(1f),
                                    shape = RoundedCornerShape(10.dp)
                                ) {
                                    Text("✓ Sí, estoy a bordo", color = Color.Black, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                                }
                                OutlinedButton(
                                    onClick = { viewModel.confirmOnBoardStatus(false) },
                                    border = BorderStroke(1.dp, Color.White.copy(alpha = 0.3f)),
                                    modifier = Modifier.weight(1f),
                                    shape = RoundedCornerShape(10.dp)
                                ) {
                                    Text("En paradero", color = Color.White, fontSize = 12.sp)
                                }
                            }
                        }
                    }
                } else if (trip.proximityAlertTriggered) {
                    DismissibleBannerPopup(
                        accentColor = BCColors.Amber,
                        bgColor = Color(0xFF451A03),
                        title = "¡Paradero próximo (≤ 200m)!",
                        message = "Tu unidad ${trip.unitNumber} está llegando a ${trip.destinationStopName ?: "tu paradero"}. Prepárate para descender.",
                        onDismiss = { viewModel.endActiveTrip() }
                    )
                } else if (trip.isConfirmedOnBoard == true) {
                    val liveBus = state.activeBuses.firstOrNull {
                        it.unitNumber.equals(trip.unitNumber, ignoreCase = true) ||
                        it.plate.equals(trip.plate, ignoreCase = true)
                    }
                    val nextStop = liveBus?.nextStopName ?: trip.destinationStopName ?: "En ruta"
                    val etaMin = liveBus?.nextStopEtaMinutes ?: 3
                    val speed = liveBus?.speedKmh?.toInt() ?: 26
                    Surface(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 14.dp),
                        shape = RoundedCornerShape(14.dp),
                        color = BCColors.ElevatedSurface.copy(alpha = 0.96f),
                        border = BorderStroke(1.dp, BCColors.Emerald.copy(alpha = 0.5f)),
                        shadowElevation = 5.dp
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(
                                    "🚌 A bordo de ${trip.unitNumber} · ${trip.lineNumber}",
                                    color = BCColors.Emerald,
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.ExtraBold
                                )
                                Text(
                                    "Próx. paradero: $nextStop (~$etaMin min · $speed km/h)",
                                    color = Color.White,
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Medium
                                )
                            }
                            IconButton(
                                onClick = { viewModel.endActiveTrip() },
                                modifier = Modifier.size(24.dp)
                            ) {
                                Icon(Icons.Default.Close, contentDescription = "Finalizar viaje", tint = Color.White.copy(alpha = 0.7f), modifier = Modifier.size(16.dp))
                            }
                        }
                    }
                }
            }

            // Widget circular de Alerta de Llegada
            state.activeArrivalAlert?.let { alert ->
                Surface(
                    modifier = Modifier.padding(horizontal = 14.dp),
                    shape = RoundedCornerShape(50),
                    color = BCColors.ElevatedSurface.copy(alpha = 0.95f),
                    border = BorderStroke(1.dp, BCColors.Emerald.copy(alpha = 0.55f))
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 7.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(8.dp)
                                .clip(CircleShape)
                                .background(BCColors.Emerald)
                        )
                        Text(
                            "${alert.stopName} · ${formatSeconds(alert.remainingSeconds)}",
                            color = Color.White,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold
                        )
                        IconButton(
                            onClick = { viewModel.cancelArrivalAlert() },
                            modifier = Modifier.size(20.dp)
                        ) {
                            Icon(Icons.Default.Close, contentDescription = "Cancelar alerta", tint = Color.White, modifier = Modifier.size(14.dp))
                        }
                    }
                }
            }
        }

        // 4. Botones flotantes inferior derecha (Mi Ubicación + Cian "Ir")
        val hasActiveTrip = state.activeTrip != null
        Column(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(
                    end = 16.dp,
                    bottom = bottomInsetPadding.calculateBottomPadding() + (if (hasActiveTrip) 94.dp else 14.dp)
                ),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            horizontalAlignment = Alignment.End
        ) {
            if (!hasActiveTrip) {
                Surface(
                    modifier = Modifier.clickable {
                        onDismissSearchFocus()
                        viewModel.verifyAndSubscribeNearestBus()
                    },
                    shape = RoundedCornerShape(50),
                    color = BCColors.ElevatedSurface.copy(alpha = 0.96f),
                    border = BorderStroke(1.dp, BCColors.Emerald.copy(alpha = 0.65f)),
                    shadowElevation = 6.dp
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 9.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Icon(Icons.Default.DirectionsBus, contentDescription = null, tint = BCColors.Emerald, modifier = Modifier.size(16.dp))
                        Text("¿Estoy en el bus?", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }

            Surface(
                modifier = Modifier
                    .size(46.dp)
                    .clickable {
                        onDismissSearchFocus()
                        viewModel.centerMapOnUserLocation()
                    },
                shape = RoundedCornerShape(14.dp),
                color = BCColors.ControlSurface.copy(alpha = 0.96f),
                border = BorderStroke(1.dp, Color.White.copy(alpha = 0.14f)),
                shadowElevation = 6.dp
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(Icons.Default.MyLocation, contentDescription = "Mi ubicación", tint = Color.White, modifier = Modifier.size(22.dp))
                }
            }

            if (!hasActiveTrip) {
                Surface(
                    modifier = Modifier
                        .size(56.dp)
                        .clickable {
                            onDismissSearchFocus()
                            viewModel.openRoutePlanner(destination = state.searchedDestinationPin)
                        },
                    shape = RoundedCornerShape(16.dp),
                    color = BCColors.SkyBlue,
                    border = BorderStroke(1.dp, Color.White.copy(alpha = 0.45f)),
                    shadowElevation = 8.dp
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(Icons.Default.Directions, contentDescription = "Ir / Cómo llegar", tint = Color.Black, modifier = Modifier.size(28.dp))
                    }
                }
            }
        }
    }

    // Confirmación para cancelar guía activa
    if (state.showCancelGuidanceConfirm) {
        AlertDialog(
            onDismissRequest = { viewModel.dismissCancelGuidancePrompt() },
            containerColor = BCColors.ElevatedSurface,
            title = { Text("¿Cancelar ruta guiada?", color = Color.White) },
            text = { Text("Se detendrá el seguimiento y la alerta activa hacia tu destino.", color = BCColors.TextSecondary) },
            confirmButton = {
                TextButton(onClick = { viewModel.cancelGuidedRoute() }) {
                    Text("Cancelar Ruta", color = BCColors.DestructiveRed, fontWeight = FontWeight.Bold)
                }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.dismissCancelGuidancePrompt() }) {
                    Text("Continuar", color = Color.White)
                }
            }
        )
    }

    // Sheet de Paradero / Destino seleccionado
    selectedCatalogStop?.let { place ->
        val availability = viewModel.notificationAvailability(place)
        val estMin = viewModel.estimateTravelMinutes(place)
        ModalBottomSheet(
            onDismissRequest = { selectedCatalogStop = null },
            containerColor = BCColors.ElevatedSurface
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .padding(bottom = 28.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text(place.name, color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Black)
                Text(place.subtitle, color = BCColors.TextSecondary, fontSize = 12.sp)

                if (place.routesPassing.isNotEmpty()) {
                    Row(
                        modifier = Modifier.horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        place.routesPassing.forEach { code ->
                            val matched = viewModel.routeItemForCode(code)
                            val isOrdActive = matched?.isOrdinaryInService == true
                            Surface(
                                shape = RoundedCornerShape(50),
                                color = if (isOrdActive) BCColors.RoyalBlue else BCColors.ControlSurface
                            ) {
                                Text(
                                    code,
                                    color = Color.White,
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Bold,
                                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                                )
                            }
                        }
                    }
                }

                HorizontalDivider(color = BCColors.HairlineBorder)

                Button(
                    onClick = {
                        selectedCatalogStop = null
                        viewModel.openRoutePlanner(destination = place)
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(48.dp),
                    shape = RoundedCornerShape(12.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = BCColors.CyanAccent, contentColor = Color.Black)
                ) {
                    Icon(Icons.Default.Directions, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("Ir / Cómo llegar (aprox. ~$estMin min)", fontWeight = FontWeight.Bold)
                }

                if (state.searchedDestinationPin?.id == place.id) {
                    OutlinedButton(
                        onClick = {
                            selectedCatalogStop = null
                            viewModel.clearSearchedDestinationPin()
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(44.dp),
                        shape = RoundedCornerShape(12.dp),
                        border = BorderStroke(1.dp, BCColors.DestructiveRed.copy(alpha = 0.55f))
                    ) {
                        Icon(Icons.Default.Close, contentDescription = null, tint = BCColors.DestructiveRed, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Quitar pin del mapa", color = BCColors.DestructiveRed, fontWeight = FontWeight.Bold)
                    }
                }

                when (availability) {
                    is StopNotificationAvailability.Available -> {
                        Text("ALERTA DE LLEGADA DE BUS", color = BCColors.TextMuted, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            listOf(5, 10, 15).forEach { mins ->
                                Surface(
                                    modifier = Modifier
                                        .weight(1f)
                                        .clickable { advanceMinutes = mins },
                                    shape = RoundedCornerShape(10.dp),
                                    color = if (advanceMinutes == mins) BCColors.Emerald else BCColors.ControlSurface
                                ) {
                                    Text(
                                        "$mins min antes",
                                        color = if (advanceMinutes == mins) Color.Black else Color.White,
                                        fontWeight = FontWeight.Bold,
                                        fontSize = 12.sp,
                                        modifier = Modifier.padding(vertical = 9.dp, horizontal = 8.dp)
                                    )
                                }
                            }
                        }
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text("Vibración inminente al llegar", color = Color.White, fontSize = 12.sp)
                            Switch(checked = imminentAlert, onCheckedChange = { imminentAlert = it })
                        }
                        OutlinedButton(
                            onClick = {
                                val ordCode = availability.activeOrdinaryRoutes.firstOrNull()?.code ?: place.primaryRouteName
                                viewModel.activateStopArrivalAlert(
                                    stop = BusStopModel(
                                        id = place.id,
                                        routeId = ordCode,
                                        name = place.shortName,
                                        subtitle = place.subtitle,
                                        latitude = place.latitude,
                                        longitude = place.longitude,
                                        sequenceOrder = 1,
                                        direction = "CORREDOR",
                                        isKeyStop = true
                                    ),
                                    advanceMinutes = advanceMinutes,
                                    imminentEnabled = imminentAlert
                                )
                                selectedCatalogStop = null
                            },
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(12.dp),
                            border = BorderStroke(1.dp, BCColors.Emerald.copy(alpha = 0.6f))
                        ) {
                            Icon(Icons.Default.NotificationsActive, contentDescription = null, tint = BCColors.Emerald, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(6.dp))
                            Text("Activar Notificación (${availability.activeOrdinaryRoutes.joinToString { it.code }})", color = BCColors.Emerald, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                        }
                    }
                    is StopNotificationAvailability.OrdinaryOutOfService -> {
                        Surface(
                            shape = RoundedCornerShape(10.dp),
                            color = BCColors.Amber.copy(alpha = 0.14f),
                            border = BorderStroke(1.dp, BCColors.Amber.copy(alpha = 0.4f))
                        ) {
                            Row(modifier = Modifier.padding(10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Icon(Icons.Default.Warning, contentDescription = null, tint = BCColors.Amber, modifier = Modifier.size(16.dp))
                                Text(
                                    "Sin unidades ordinarias en servicio actualmente. Notificación deshabilitada.",
                                    color = BCColors.Amber,
                                    fontSize = 11.sp
                                )
                            }
                        }
                    }
                    is StopNotificationAvailability.NoOrdinaryRoutes -> {
                        Text(
                            if (place.routesPassing.isEmpty()) "Punto de encuentro en mapa (sin rutas ordinarias trackeadas)."
                            else "Solo rutas externas referenciales (sin tracking GPS ni notificación).",
                            color = BCColors.TextMuted,
                            fontSize = 11.sp
                        )
                    }
                }
            }
        }
    }

    // Sheet técnico de bus en vivo
    selectedBus?.let { bus ->
        ModalBottomSheet(
            onDismissRequest = { selectedBus = null },
            containerColor = BCColors.ElevatedSurface
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .padding(bottom = 28.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text("Ruta ${bus.lineNumber} · ${bus.unitNumber}", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Black)
                Text(
                    String.format(Locale.US, "Placa: %s · Conductor: %s (%.1f★)", bus.plate, bus.driverName, bus.driverRating),
                    color = BCColors.TextSecondary,
                    fontSize = 12.sp
                )
                Text(
                    "Próximo paradero: ${bus.nextStopName} (~${bus.nextStopEtaMinutes} min) · ${bus.passengers}/${bus.capacity} pasajeros",
                    color = BCColors.Emerald,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    }
}

@Composable
private fun MinimalistGuidanceBar(
    guidance: ActiveRouteGuidanceState,
    onTapOpenPlanner: () -> Unit,
    onCancelClick: () -> Unit
) {
    val cand = guidance.candidate
    val isOrd = cand?.kind == EvaluatedCandidateKind.ORDINARY_IN_SERVICE
    val isExt = cand?.kind == EvaluatedCandidateKind.EXTERNAL_FREE_BOARDING
    val accent = when {
        isOrd -> BCColors.Emerald
        isExt -> BCColors.Amber
        else -> BCColors.CyanAccent
    }
    val icon = if (cand?.kind == EvaluatedCandidateKind.WALKING_DIRECT) Icons.Default.DirectionsWalk else Icons.Default.DirectionsBus

    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp)
            .clickable(onClick = onTapOpenPlanner),
        shape = RoundedCornerShape(50),
        color = BCColors.ElevatedSurface.copy(alpha = 0.96f),
        border = BorderStroke(1.dp, accent.copy(alpha = 0.55f)),
        shadowElevation = 6.dp
    ) {
        Row(
            modifier = Modifier.padding(start = 10.dp, end = 8.dp, top = 7.dp, bottom = 7.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(28.dp)
                    .clip(CircleShape)
                    .background(accent.copy(alpha = 0.2f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(icon, contentDescription = null, tint = accent, modifier = Modifier.size(16.dp))
            }

            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(cand?.routeCode ?: "Ruta", color = Color.White, fontWeight = FontWeight.ExtraBold, fontSize = 12.sp)
                    when {
                        isOrd -> Text(
                            formatSeconds(guidance.remainingBusArrivalSeconds),
                            color = BCColors.Emerald,
                            fontWeight = FontWeight.Bold,
                            fontFamily = FontFamily.Monospace,
                            fontSize = 12.sp
                        )
                        isExt -> Text("· Sin GPS", color = BCColors.Amber, fontWeight = FontWeight.SemiBold, fontSize = 11.sp)
                        cand != null -> Text("· ~${cand.totalDurationMinutes} min", color = BCColors.CyanAccent, fontWeight = FontWeight.SemiBold, fontSize = 11.sp)
                    }
                }
                Text(
                    "Hacia ${guidance.destination.shortName}",
                    color = BCColors.TextSecondary,
                    fontSize = 11.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }

            IconButton(
                onClick = onCancelClick,
                modifier = Modifier
                    .size(28.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.12f))
            ) {
                Icon(Icons.Default.Close, contentDescription = "Cancelar guía", tint = Color.White, modifier = Modifier.size(15.dp))
            }
        }
    }
}

@Composable
private fun DismissibleBannerPopup(
    accentColor: Color,
    bgColor: Color,
    title: String,
    message: String,
    onDismiss: () -> Unit
) {
    var offsetX by remember { mutableFloatStateOf(0f) }

    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp)
            .offset { IntOffset(offsetX.roundToInt(), 0) }
            .pointerInput(Unit) {
                detectHorizontalDragGestures(
                    onDragEnd = {
                        if (kotlin.math.abs(offsetX) > 160f) onDismiss() else offsetX = 0f
                    },
                    onHorizontalDrag = { _, dragAmount -> offsetX += dragAmount }
                )
            },
        shape = RoundedCornerShape(16.dp),
        color = bgColor.copy(alpha = 0.96f),
        border = BorderStroke(1.dp, accentColor.copy(alpha = 0.55f)),
        shadowElevation = 6.dp
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Icon(Icons.Default.Warning, contentDescription = null, tint = accentColor, modifier = Modifier.size(18.dp))
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(title, color = accentColor, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                Text(message, color = Color.White.copy(alpha = 0.88f), fontSize = 11.sp)
            }
            IconButton(onClick = onDismiss, modifier = Modifier.size(22.dp)) {
                Icon(Icons.Default.Close, contentDescription = "Cerrar aviso", tint = Color.White, modifier = Modifier.size(14.dp))
            }
        }
    }
}

private fun formatSeconds(total: Int): String {
    val safe = total.coerceAtLeast(0)
    return String.format(Locale.US, "%02d:%02d", safe / 60, safe % 60)
}


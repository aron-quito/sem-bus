package pe.edu.unjbg.busconectado.feature.lines

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Directions
import androidx.compose.material.icons.filled.DirectionsBus
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.QrCode2
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import pe.edu.unjbg.busconectado.core.designsystem.BCColors
import pe.edu.unjbg.busconectado.core.model.StopNotificationAvailability
import pe.edu.unjbg.busconectado.core.model.TacnaDestinationPlace
import pe.edu.unjbg.busconectado.core.model.TacnaOfficialRouteCatalogItem
import pe.edu.unjbg.busconectado.core.model.TacnaStopCategory
import pe.edu.unjbg.busconectado.feature.auth.AuthViewModel
import pe.edu.unjbg.busconectado.feature.auth.BCUiState

private enum class DirectoryTab(val title: String) {
    LINES("Líneas"),
    STOPS("Paraderos")
}

private enum class RouteTypeFilter(val title: String) {
    ALL("Todas"),
    IN_SERVICE("En servicio"),
    ORDINARY("Ordinarias"),
    EXTERNAL("Externas")
}

@Composable
fun LinesScreen(
    state: BCUiState,
    viewModel: AuthViewModel,
    bottomContentPadding: PaddingValues = PaddingValues(bottom = 96.dp)
) {
    var selectedDirectory by remember { mutableStateOf(DirectoryTab.LINES) }
    var routeFilter by remember { mutableStateOf(RouteTypeFilter.ALL) }
    var stopCategory by remember { mutableStateOf(TacnaStopCategory.ALL) }
    var expandedRouteIds by remember { mutableStateOf(setOf("tacna-ruta-14")) }

    val filteredRoutes = remember(state.dynamicRoutes, routeFilter) {
        when (routeFilter) {
            RouteTypeFilter.ALL -> state.dynamicRoutes
            RouteTypeFilter.IN_SERVICE -> state.dynamicRoutes.filter { it.isOrdinaryInService }
            RouteTypeFilter.ORDINARY -> state.dynamicRoutes.filter { it.isOrdinary }
            RouteTypeFilter.EXTERNAL -> state.dynamicRoutes.filter { it.isExternal }
        }
    }

    val filteredStops = remember(state.dynamicCatalogStops, stopCategory) {
        if (stopCategory == TacnaStopCategory.ALL) {
            state.dynamicCatalogStops
        } else {
            state.dynamicCatalogStops.filter { it.stopCategory == stopCategory }
        }
    }

    val activeOrdCount = state.dynamicRoutes.count { it.isOrdinaryInService }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(BCColors.DarkBackground)
            .statusBarsPadding()
    ) {
        Spacer(Modifier.height(66.dp)) // Reserva para barra flotante superior

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                "Red de Tacna",
                fontSize = 20.sp,
                fontWeight = FontWeight.Black,
                color = Color.White,
                modifier = Modifier.weight(1f)
            )
            Surface(
                shape = RoundedCornerShape(50),
                color = BCColors.Emerald.copy(alpha = 0.16f),
                border = BorderStroke(1.dp, BCColors.Emerald.copy(alpha = 0.4f))
            ) {
                Text(
                    "$activeOrdCount ord. activas · ${state.dynamicCatalogStops.size} paraderos",
                    color = BCColors.Emerald,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp)
                )
            }
        }

        Spacer(Modifier.height(10.dp))

        // Segmented Toggle Líneas / Paraderos
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(BCColors.ControlSurface)
                .padding(4.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            DirectoryTab.entries.forEach { tab ->
                val selected = selectedDirectory == tab
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(10.dp))
                        .background(if (selected) BCColors.RoyalBlue else Color.Transparent)
                        .clickable { selectedDirectory = tab }
                        .padding(vertical = 9.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        tab.title,
                        color = if (selected) Color.White else BCColors.TextSecondary,
                        fontWeight = FontWeight.Bold,
                        fontSize = 13.sp
                    )
                }
            }
        }

        Spacer(Modifier.height(8.dp))

        if (selectedDirectory == DirectoryTab.LINES) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                RouteTypeFilter.entries.forEach { f ->
                    FilterChip(
                        selected = routeFilter == f,
                        onClick = { routeFilter = f },
                        label = { Text(f.title, fontSize = 12.sp) },
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = BCColors.RoyalBlue,
                            selectedLabelColor = Color.White,
                            containerColor = BCColors.ControlSurface,
                            labelColor = BCColors.TextSecondary
                        )
                    )
                }
            }

            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(
                    start = 16.dp,
                    end = 16.dp,
                    top = 8.dp,
                    bottom = bottomContentPadding.calculateBottomPadding()
                ),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                items(filteredRoutes, key = { it.id }) { route ->
                    val expanded = route.id in expandedRouteIds
                    RouteCatalogCard(
                        route = route,
                        stops = route.resolvedStops(state.dynamicCatalogStops),
                        expanded = expanded,
                        onToggleExpand = {
                            expandedRouteIds = if (expanded) expandedRouteIds - route.id else expandedRouteIds + route.id
                        },
                        onShowOnMap = { viewModel.projectRouteOnExploreMap(route) },
                        onFocusStop = { stop -> viewModel.focusMapOnPlace(stop) }
                    )
                }
            }
        } else {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                listOf(
                    TacnaStopCategory.ALL,
                    TacnaStopCategory.UNIVERSITIES,
                    TacnaStopCategory.MARKETS,
                    TacnaStopCategory.TRANSPORT,
                    TacnaStopCategory.CIVIC
                ).forEach { cat ->
                    FilterChip(
                        selected = stopCategory == cat,
                        onClick = { stopCategory = cat },
                        label = { Text(cat.displayLabel, fontSize = 12.sp) },
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = BCColors.CyanAccent,
                            selectedLabelColor = Color.Black,
                            containerColor = BCColors.ControlSurface,
                            labelColor = BCColors.TextSecondary
                        )
                    )
                }
            }

            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(
                    start = 16.dp,
                    end = 16.dp,
                    top = 8.dp,
                    bottom = bottomContentPadding.calculateBottomPadding()
                ),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                items(filteredStops, key = { it.id }) { stop ->
                    StopDirectoryCard(
                        stop = stop,
                        availability = viewModel.notificationAvailability(stop),
                        onViewOnMap = { viewModel.focusMapOnPlace(stop) },
                        onRouteHere = { viewModel.openRoutePlanner(destination = stop) }
                    )
                }
            }
        }
    }
}

@Composable
private fun RouteCatalogCard(
    route: TacnaOfficialRouteCatalogItem,
    stops: List<TacnaDestinationPlace>,
    expanded: Boolean,
    onToggleExpand: () -> Unit,
    onShowOnMap: () -> Unit,
    onFocusStop: (TacnaDestinationPlace) -> Unit
) {
    val accent = BCColors.fromHex(route.colorHex)
    val badgeBg = when {
        route.isOrdinaryInService -> BCColors.Emerald
        route.isOrdinary -> BCColors.Amber
        else -> Color(0xFF94A3B8)
    }
    val statusText = when {
        route.isOrdinaryInService -> "ORDINARIA · EN SERVICIO"
        route.isOrdinary -> "ORDINARIA · SIN UNIDADES"
        else -> "EXTERNA · REFERENCIAL"
    }

    Surface(
        shape = RoundedCornerShape(18.dp),
        color = BCColors.CardSurface,
        border = BorderStroke(1.dp, accent.copy(alpha = 0.45f))
    ) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(onClick = onToggleExpand),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Surface(shape = RoundedCornerShape(8.dp), color = accent) {
                    Text(
                        route.code,
                        color = Color.White,
                        fontWeight = FontWeight.Black,
                        fontFamily = FontFamily.Monospace,
                        fontSize = 12.sp,
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp)
                    )
                }
                Column(modifier = Modifier.weight(1f)) {
                    Text(statusText, color = badgeBg, fontSize = 10.sp, fontWeight = FontWeight.ExtraBold)
                    Text(
                        route.title,
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                        fontSize = 14.sp,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                Icon(
                    imageVector = if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                    contentDescription = null,
                    tint = Color.White
                )
            }

            Text(
                route.corridorSummary,
                color = BCColors.TextSecondary,
                fontSize = 12.sp
            )

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Schedule, contentDescription = null, tint = BCColors.CyanAccent, modifier = Modifier.size(14.dp))
                    Text("${route.frequencyLabel} · ${route.scheduleLabel}", color = Color.White, fontSize = 11.sp)
                }
                if (route.supportsQrPayment) {
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.QrCode2, contentDescription = null, tint = BCColors.Emerald, modifier = Modifier.size(14.dp))
                        Text("Pago QR", color = BCColors.Emerald, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }

            AnimatedVisibility(visible = expanded) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    HorizontalDivider(color = BCColors.HairlineBorder)
                    Text(
                        "RECORRIDO (${stops.size} PARADEROS · ~${route.estimatedTotalMinutes} MIN)",
                        color = BCColors.TextMuted,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold
                    )
                    stops.forEachIndexed { idx, stop ->
                        val estMin = if (stops.size <= 1) 0 else (route.estimatedTotalMinutes * idx) / (stops.size - 1)
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onFocusStop(stop) }
                                .padding(vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(22.dp)
                                    .clip(CircleShape)
                                    .background(accent.copy(alpha = 0.22f)),
                                contentAlignment = Alignment.Center
                            ) {
                                Text("${idx + 1}", color = accent, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                            }
                            Column(modifier = Modifier.weight(1f)) {
                                Text(stop.name, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(stop.subtitle, color = BCColors.TextMuted, fontSize = 10.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                            Text("~${estMin}m", color = accent, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                        }
                    }

                    Button(
                        onClick = onShowOnMap,
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(12.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = accent)
                    ) {
                        Icon(Icons.Default.Map, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Ver trazado en el mapa", fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}

@Composable
private fun StopDirectoryCard(
    stop: TacnaDestinationPlace,
    availability: StopNotificationAvailability,
    onViewOnMap: () -> Unit,
    onRouteHere: () -> Unit
) {
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = BCColors.CardSurface,
        border = BorderStroke(1.dp, BCColors.HairlineBorder)
    ) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .clip(CircleShape)
                        .background(BCColors.fromHex(stop.colorHex).copy(alpha = 0.2f)),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Default.Place, contentDescription = null, tint = BCColors.fromHex(stop.colorHex))
                }
                Column(modifier = Modifier.weight(1f)) {
                    Text(stop.name, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Text(stop.subtitle, color = BCColors.TextSecondary, fontSize = 11.sp, maxLines = 2)
                }
            }

            if (stop.routesPassing.isNotEmpty()) {
                Row(
                    modifier = Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    stop.routesPassing.forEach { code ->
                        Surface(
                            shape = RoundedCornerShape(50),
                            color = BCColors.ControlSurface,
                            border = BorderStroke(1.dp, BCColors.HairlineBorder)
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(4.dp)
                            ) {
                                Icon(Icons.Default.DirectionsBus, contentDescription = null, tint = BCColors.CyanAccent, modifier = Modifier.size(11.dp))
                                Text(code, color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                }
            }

            when (availability) {
                is StopNotificationAvailability.Available -> {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Icons.Default.NotificationsActive, contentDescription = null, tint = BCColors.Emerald, modifier = Modifier.size(14.dp))
                        Text(
                            "Notificación 5m disponible (${availability.activeOrdinaryRoutes.joinToString { it.code }})",
                            color = BCColors.Emerald,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
                is StopNotificationAvailability.OrdinaryOutOfService -> {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Icons.Default.Warning, contentDescription = null, tint = BCColors.Amber, modifier = Modifier.size(14.dp))
                        Text(
                            "Ruta ordinaria registrada sin unidades en servicio.",
                            color = BCColors.Amber,
                            fontSize = 11.sp
                        )
                    }
                }
                is StopNotificationAvailability.NoOrdinaryRoutes -> {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Icons.Default.NotificationsOff, contentDescription = null, tint = BCColors.TextMuted, modifier = Modifier.size(14.dp))
                        Text(
                            "Sin rutas ordinarias trackeadas en este punto.",
                            color = BCColors.TextMuted,
                            fontSize = 11.sp
                        )
                    }
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = onViewOnMap,
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(10.dp),
                    border = BorderStroke(1.dp, BCColors.HairlineBorder)
                ) {
                    Icon(Icons.Default.Info, contentDescription = null, tint = Color.White, modifier = Modifier.size(15.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("Ver en Mapa", color = Color.White, fontSize = 12.sp)
                }
                Button(
                    onClick = onRouteHere,
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(10.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = BCColors.CyanAccent)
                ) {
                    Icon(Icons.Default.Directions, contentDescription = null, tint = Color.Black, modifier = Modifier.size(15.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("Ir", color = Color.Black, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                }
            }
        }
    }
}


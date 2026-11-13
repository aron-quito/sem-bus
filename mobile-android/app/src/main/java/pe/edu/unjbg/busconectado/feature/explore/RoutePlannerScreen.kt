package pe.edu.unjbg.busconectado.feature.explore

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.Crossfade
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Directions
import androidx.compose.material.icons.filled.DirectionsBus
import androidx.compose.material.icons.filled.DirectionsWalk
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Navigation
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.QrCode2
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import pe.edu.unjbg.busconectado.core.designsystem.BCColors
import pe.edu.unjbg.busconectado.core.designsystem.SpeechSearchEngine
import pe.edu.unjbg.busconectado.core.location.GeoPointData
import pe.edu.unjbg.busconectado.core.location.LocationService
import pe.edu.unjbg.busconectado.core.model.EvaluatedCandidateKind
import pe.edu.unjbg.busconectado.core.model.EvaluatedRouteCandidate
import pe.edu.unjbg.busconectado.core.model.RouteAutomationEvaluationResult
import pe.edu.unjbg.busconectado.core.model.TacnaDestinationPlace
import pe.edu.unjbg.busconectado.core.ui.BCOsmMapView
import pe.edu.unjbg.busconectado.core.ui.MapMarkerKind
import pe.edu.unjbg.busconectado.core.ui.MapMarkerSpec
import pe.edu.unjbg.busconectado.core.ui.MapPolylineSpec
import pe.edu.unjbg.busconectado.feature.auth.AuthViewModel
import pe.edu.unjbg.busconectado.feature.auth.BCUiState
import pe.edu.unjbg.busconectado.feature.auth.CameraFocusCommand
import java.util.Locale

private enum class EndpointTarget { ORIGIN, DESTINATION }

private sealed class PlannerState {
    object Selector : PlannerState()
    data class LiveSearch(val target: EndpointTarget) : PlannerState()
    data class MapPicker(val target: EndpointTarget) : PlannerState()
    object RouteMap : PlannerState()
}

private enum class SheetSnapLevel(val heightDp: Int) {
    COMPACT(178),
    MEDIUM(355),
    FULL(540);

    fun next(): SheetSnapLevel = when (this) {
        COMPACT -> MEDIUM
        MEDIUM -> FULL
        FULL -> COMPACT
    }
}

private enum class RouteFilterTab(val label: String) {
    RECOMMENDED("Recomendado"),
    ORDINARY("Ordinarias"),
    WALK("A pie")
}

@Composable
fun RoutePlannerScreen(
    state: BCUiState,
    viewModel: AuthViewModel,
    onClose: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val speechEngine = remember { SpeechSearchEngine(context) }
    val isListening by speechEngine.isListening.collectAsState()

    val audioLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) {
            speechEngine.startListening { }
        }
    }

    DisposableEffect(Unit) {
        onDispose { speechEngine.release() }
    }

    val initialOrigin = state.routePlannerInitialOrigin ?: TacnaDestinationPlace.currentLocationPlace(state.userLocation)
    val initialDest = state.routePlannerInitialDestination

    var selectedOrigin by remember { mutableStateOf(initialOrigin) }
    var selectedDestination by remember { mutableStateOf(initialDest ?: initialOrigin) }
    var hasChosenDestination by remember { mutableStateOf(initialDest != null) }

    var screenState by remember {
        mutableStateOf<PlannerState>(if (initialDest != null) PlannerState.RouteMap else PlannerState.Selector)
    }

    var searchQuery by remember { mutableStateOf("") }
    var apiResults by remember { mutableStateOf<List<TacnaDestinationPlace>>(emptyList()) }
    var isSearchingApi by remember { mutableStateOf(false) }

    var evaluationResult by remember { mutableStateOf<RouteAutomationEvaluationResult?>(null) }
    var selectedFilter by remember { mutableStateOf(RouteFilterTab.RECOMMENDED) }
    var selectedCandidateIdx by remember { mutableIntStateOf(0) }
    var sheetSnap by remember { mutableStateOf(SheetSnapLevel.COMPACT) }

    var walkCoords by remember { mutableStateOf<List<GeoPointData>>(emptyList()) }
    var busCoords by remember { mutableStateOf<List<GeoPointData>>(emptyList()) }
    var finalCoords by remember { mutableStateOf<List<GeoPointData>>(emptyList()) }

    var routeCam by remember {
        mutableStateOf(
            CameraFocusCommand(
                LocationService.sanitizedTacnaCoordinate(selectedOrigin.coordinate),
                14.0,
                1
            )
        )
    }

    val displayedCandidates = remember(evaluationResult, selectedFilter) {
        val all = evaluationResult?.candidates ?: emptyList()
        when (selectedFilter) {
            RouteFilterTab.RECOMMENDED -> all
            RouteFilterTab.ORDINARY -> all.filter { it.kind == EvaluatedCandidateKind.ORDINARY_IN_SERVICE }
            RouteFilterTab.WALK -> all.filter { it.kind == EvaluatedCandidateKind.WALKING_DIRECT }
        }
    }

    val activeCandidate = displayedCandidates.getOrNull(selectedCandidateIdx) ?: displayedCandidates.firstOrNull()

    fun recomputeRoutes() {
        if (!hasChosenDestination) return
        val res = viewModel.evaluateAutomatedRoutes(selectedOrigin, selectedDestination)
        evaluationResult = res
        selectedCandidateIdx = 0
        selectedFilter = RouteFilterTab.RECOMMENDED
        sheetSnap = SheetSnapLevel.COMPACT
        val midLat = (selectedOrigin.latitude + selectedDestination.latitude) / 2.0
        val midLon = (selectedOrigin.longitude + selectedDestination.longitude) / 2.0
        routeCam = CameraFocusCommand(
            center = LocationService.sanitizedTacnaCoordinate(GeoPointData(midLat, midLon)),
            zoom = 13.9,
            nonce = routeCam.nonce + 1
        )
    }

    LaunchedEffect(hasChosenDestination, selectedOrigin.id, selectedDestination.id) {
        if (hasChosenDestination && screenState is PlannerState.RouteMap) {
            recomputeRoutes()
        }
    }

    LaunchedEffect(activeCandidate?.id) {
        val cand = activeCandidate
        if (cand == null) {
            walkCoords = emptyList()
            busCoords = emptyList()
            finalCoords = emptyList()
        } else {
            val wJob = async { viewModel.networkClient.alignPolylineToStreets(cand.walkToBoardCoords, isWalking = true) }
            val bJob = async {
                if (cand.busTransitCoords.size > 6) cand.busTransitCoords
                else viewModel.networkClient.alignPolylineToStreets(cand.busTransitCoords, isWalking = false)
            }
            val fJob = async { viewModel.networkClient.alignPolylineToStreets(cand.walkFinalCoords, isWalking = true) }
            walkCoords = wJob.await()
            busCoords = bJob.await()
            finalCoords = fJob.await()
        }
    }

    LaunchedEffect(searchQuery, screenState) {
        if (screenState !is PlannerState.LiveSearch) return@LaunchedEffect
        val q = searchQuery.trim()
        if (q.length < 2) {
            apiResults = emptyList()
            isSearchingApi = false
            return@LaunchedEffect
        }
        isSearchingApi = true
        delay(240L)
        val res = viewModel.networkClient.searchLivePlacesInTacna(q)
        apiResults = res
        isSearchingApi = false
    }

    fun selectEndpoint(place: TacnaDestinationPlace, target: EndpointTarget) {
        viewModel.recordRecentSearchedPlace(place)
        if (target == EndpointTarget.ORIGIN) {
            selectedOrigin = place
            screenState = if (hasChosenDestination) PlannerState.RouteMap else PlannerState.Selector
        } else {
            selectedDestination = place
            hasChosenDestination = true
            screenState = PlannerState.RouteMap
        }
    }

    fun swapEndpoints() {
        if (hasChosenDestination) {
            val tmp = selectedOrigin
            selectedOrigin = selectedDestination
            selectedDestination = tmp
        } else if (selectedOrigin.id != "current_gps") {
            selectedDestination = selectedOrigin
            selectedOrigin = TacnaDestinationPlace.currentLocationPlace(state.userLocation)
            hasChosenDestination = true
            screenState = PlannerState.RouteMap
        }
    }

    val userFareLabel = state.currentUser?.roleType?.let {
        String.format(Locale.US, "S/. %.2f", it.farePen)
    } ?: "S/. 0.70"

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(BCColors.DarkBackground)
    ) {
        when (val st = screenState) {
            is PlannerState.Selector -> {
                SelectorView(
                    origin = selectedOrigin,
                    destination = if (hasChosenDestination) selectedDestination else null,
                    recentPlaces = state.recentSearchedPlaces,
                    onClose = onClose,
                    onEditOrigin = {
                        searchQuery = ""
                        screenState = PlannerState.LiveSearch(EndpointTarget.ORIGIN)
                    },
                    onEditDestination = {
                        searchQuery = ""
                        screenState = PlannerState.LiveSearch(EndpointTarget.DESTINATION)
                    },
                    onUseCurrentOrigin = {
                        selectedOrigin = TacnaDestinationPlace.currentLocationPlace(state.userLocation)
                    },
                    onPickDestOnMap = {
                        screenState = PlannerState.MapPicker(EndpointTarget.DESTINATION)
                    },
                    onSwap = ::swapEndpoints,
                    onSelectRecent = { selectEndpoint(it, EndpointTarget.DESTINATION) },
                    onClearRecents = { viewModel.clearRecentSearchedPlaces() }
                )
            }

            is PlannerState.LiveSearch -> {
                LiveSearchView(
                    target = st.target,
                    query = searchQuery,
                    onQueryChange = { searchQuery = it },
                    isListeningVoice = isListening,
                    onVoiceClick = {
                        val micOk = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
                        if (!micOk) {
                            audioLauncher.launch(Manifest.permission.RECORD_AUDIO)
                        } else {
                            speechEngine.startListening { spoken -> searchQuery = spoken }
                        }
                    },
                    onBack = {
                        speechEngine.stopListening()
                        screenState = if (hasChosenDestination) PlannerState.RouteMap else PlannerState.Selector
                    },
                    onPickOnMap = {
                        speechEngine.stopListening()
                        screenState = PlannerState.MapPicker(st.target)
                    },
                    onSelectCurrentLocation = {
                        selectEndpoint(TacnaDestinationPlace.currentLocationPlace(state.userLocation), EndpointTarget.ORIGIN)
                    },
                    catalogMatches = viewModel.filteredPredictivePlaces(searchQuery).ifEmpty {
                        if (searchQuery.isBlank()) state.dynamicCatalogStops else emptyList()
                    },
                    apiResults = apiResults,
                    isSearchingApi = isSearchingApi,
                    onSelectPlace = { selectEndpoint(it, st.target) }
                )
            }

            is PlannerState.MapPicker -> {
                MapCrosshairPickerView(
                    target = st.target,
                    initialPoint = LocationService.sanitizedTacnaCoordinate(
                        if (st.target == EndpointTarget.ORIGIN) selectedOrigin.coordinate
                        else if (hasChosenDestination) selectedDestination.coordinate
                        else state.userLocation
                    ),
                    viewModel = viewModel,
                    onCancel = {
                        screenState = if (hasChosenDestination) PlannerState.RouteMap else PlannerState.Selector
                    },
                    onConfirm = { place -> selectEndpoint(place, st.target) }
                )
            }

            is PlannerState.RouteMap -> {
                RouteMapResultView(
                    origin = selectedOrigin,
                    destination = selectedDestination,
                    camera = routeCam,
                    walkCoords = walkCoords,
                    busCoords = busCoords,
                    finalCoords = finalCoords,
                    evaluationResult = evaluationResult,
                    candidates = displayedCandidates,
                    activeCandidate = activeCandidate,
                    selectedCandidateIdx = selectedCandidateIdx,
                    selectedFilter = selectedFilter,
                    sheetSnap = sheetSnap,
                    userFareLabel = userFareLabel,
                    onBack = { screenState = PlannerState.Selector },
                    onEditOrigin = {
                        searchQuery = ""
                        screenState = PlannerState.LiveSearch(EndpointTarget.ORIGIN)
                    },
                    onEditDestination = {
                        searchQuery = ""
                        screenState = PlannerState.LiveSearch(EndpointTarget.DESTINATION)
                    },
                    onSwap = ::swapEndpoints,
                    onFilterSelected = {
                        selectedFilter = it
                        selectedCandidateIdx = 0
                    },
                    onCandidateSelected = { idx ->
                        selectedCandidateIdx = idx
                    },
                    onCycleSnap = { sheetSnap = sheetSnap.next() },
                    onSetSnap = { sheetSnap = it },
                    onStartGuidance = { cand ->
                        viewModel.startGuidedRoute(
                            origin = selectedOrigin,
                            destination = selectedDestination,
                            optionIndex = selectedCandidateIdx,
                            candidate = cand
                        )
                    }
                )
            }
        }
    }
}

@Composable
private fun SelectorView(
    origin: TacnaDestinationPlace,
    destination: TacnaDestinationPlace?,
    recentPlaces: List<TacnaDestinationPlace>,
    onClose: () -> Unit,
    onEditOrigin: () -> Unit,
    onEditDestination: () -> Unit,
    onUseCurrentOrigin: () -> Unit,
    onPickDestOnMap: () -> Unit,
    onSwap: () -> Unit,
    onSelectRecent: (TacnaDestinationPlace) -> Unit,
    onClearRecents: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .navigationBarsPadding()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            IconButton(
                onClick = onClose,
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(BCColors.ControlSurface)
            ) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Cerrar", tint = Color.White)
            }

            Surface(
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(18.dp),
                color = BCColors.ControlSurface,
                border = BorderStroke(1.dp, BCColors.HairlineBorder)
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable(onClick = onEditOrigin),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(10.dp)
                                    .clip(CircleShape)
                                    .background(BCColors.RoyalBlue)
                            )
                            Text(
                                origin.name,
                                color = Color.White,
                                fontWeight = FontWeight.SemiBold,
                                fontSize = 14.sp,
                                modifier = Modifier.weight(1f),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                            IconButton(onClick = onUseCurrentOrigin, modifier = Modifier.size(26.dp)) {
                                Icon(Icons.Default.MyLocation, contentDescription = "Mi GPS", tint = BCColors.CyanAccent, modifier = Modifier.size(16.dp))
                            }
                        }

                        HorizontalDivider(color = BCColors.HairlineBorder)

                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable(onClick = onEditDestination),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Icon(Icons.Default.Place, contentDescription = null, tint = BCColors.DestructiveRed, modifier = Modifier.size(14.dp))
                            Text(
                                destination?.name ?: "¿A dónde vamos en Tacna?",
                                color = if (destination != null) Color.White else BCColors.TextMuted,
                                fontWeight = FontWeight.SemiBold,
                                fontSize = 14.sp,
                                modifier = Modifier.weight(1f),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                            IconButton(onClick = onPickDestOnMap, modifier = Modifier.size(26.dp)) {
                                Icon(Icons.Default.MyLocation, contentDescription = "Elegir en mapa", tint = BCColors.DestructiveRed, modifier = Modifier.size(16.dp))
                            }
                        }
                    }

                    IconButton(onClick = onSwap, modifier = Modifier.size(34.dp)) {
                        Icon(Icons.Default.SwapVert, contentDescription = "Intercambiar", tint = Color.White)
                    }
                }
            }
        }

        HorizontalDivider(color = BCColors.HairlineBorder)

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Default.History, contentDescription = null, tint = BCColors.CyanAccent, modifier = Modifier.size(16.dp))
                Text("Últimos sitios buscados", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
            }
            if (recentPlaces.isNotEmpty()) {
                Text(
                    "Limpiar",
                    color = BCColors.TextSecondary,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.clickable(onClick = onClearRecents)
                )
            }
        }

        if (recentPlaces.isEmpty()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(Icons.Default.Search, contentDescription = null, tint = BCColors.TextMuted, modifier = Modifier.size(40.dp))
                Text("Sin búsquedas recientes", color = Color.White, fontWeight = FontWeight.Bold)
                Text(
                    "Toca el campo de destino arriba o el icono de mira para elegir cualquier punto del mapa de Tacna.",
                    color = BCColors.TextMuted,
                    fontSize = 12.sp
                )
            }
        } else {
            LazyColumn(modifier = Modifier.fillMaxSize()) {
                items(recentPlaces, key = { it.id }) { place ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onSelectRecent(place) }
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(38.dp)
                                .clip(CircleShape)
                                .background(BCColors.ControlSurface),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(Icons.Default.Place, contentDescription = null, tint = BCColors.CyanAccent, modifier = Modifier.size(18.dp))
                        }
                        Column(modifier = Modifier.weight(1f)) {
                            Text(place.name, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(place.subtitle, color = BCColors.TextMuted, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        Icon(Icons.Default.Directions, contentDescription = null, tint = BCColors.CyanAccent, modifier = Modifier.size(18.dp))
                    }
                    HorizontalDivider(color = BCColors.HairlineBorder, modifier = Modifier.padding(start = 66.dp))
                }
            }
        }
    }
}

@Composable
private fun LiveSearchView(
    target: EndpointTarget,
    query: String,
    onQueryChange: (String) -> Unit,
    isListeningVoice: Boolean,
    onVoiceClick: () -> Unit,
    onBack: () -> Unit,
    onPickOnMap: () -> Unit,
    onSelectCurrentLocation: () -> Unit,
    catalogMatches: List<TacnaDestinationPlace>,
    apiResults: List<TacnaDestinationPlace>,
    isSearchingApi: Boolean,
    onSelectPlace: (TacnaDestinationPlace) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .navigationBarsPadding()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Volver", tint = Color.White)
            }
            OutlinedTextField(
                value = query,
                onValueChange = onQueryChange,
                placeholder = {
                    Text(
                        if (target == EndpointTarget.ORIGIN) "Buscar punto de inicio..." else "Buscar calle o lugar en Tacna...",
                        color = BCColors.TextMuted,
                        fontSize = 14.sp
                    )
                },
                singleLine = true,
                trailingIcon = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        if (query.isNotEmpty()) {
                            IconButton(onClick = { onQueryChange("") }) {
                                Icon(Icons.Default.Close, contentDescription = "Borrar", tint = BCColors.TextSecondary)
                            }
                        }
                        IconButton(onClick = onVoiceClick) {
                            Icon(
                                Icons.Default.Mic,
                                contentDescription = "Voz",
                                tint = if (isListeningVoice) BCColors.DestructiveRed else BCColors.CyanAccent
                            )
                        }
                    }
                },
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = BCColors.CyanAccent,
                    unfocusedBorderColor = BCColors.HairlineBorder,
                    focusedTextColor = Color.White,
                    unfocusedTextColor = Color.White,
                    focusedContainerColor = BCColors.ControlSurface,
                    unfocusedContainerColor = BCColors.ControlSurface
                ),
                shape = RoundedCornerShape(14.dp),
                modifier = Modifier.weight(1f)
            )
        }

        if (isSearchingApi) {
            Row(modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp, color = BCColors.CyanAccent)
                Text("Buscando lugares en Tacna...", color = BCColors.CyanAccent, fontSize = 12.sp)
            }
        }

        LazyColumn(modifier = Modifier.fillMaxSize()) {
            if (target == EndpointTarget.ORIGIN) {
                item {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable(onClick = onSelectCurrentLocation)
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Icon(Icons.Default.MyLocation, contentDescription = null, tint = BCColors.RoyalBlue)
                        Text("Tu ubicación actual (GPS)", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    }
                }
            }

            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(onClick = onPickOnMap)
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Icon(Icons.Default.Place, contentDescription = null, tint = BCColors.CyanAccent)
                    Text("Elegir en el mapa de Tacna", color = BCColors.CyanAccent, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                }
                HorizontalDivider(color = BCColors.HairlineBorder)
            }

            if (apiResults.isNotEmpty()) {
                item {
                    Text(
                        "LUGARES Y CALLES DE TACNA",
                        color = BCColors.CyanAccent,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                }
                items(apiResults, key = { "api_${it.id}" }) { place ->
                    PlaceSearchRow(place = place, onClick = { onSelectPlace(place) })
                }
            }

            if (catalogMatches.isNotEmpty()) {
                item {
                    Text(
                        "PARADEROS Y PUNTOS DE REFERENCIA",
                        color = BCColors.TextMuted,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                }
                items(catalogMatches, key = { "cat_${it.id}" }) { place ->
                    PlaceSearchRow(place = place, onClick = { onSelectPlace(place) })
                }
            }
        }
    }
}

@Composable
private fun PlaceSearchRow(place: TacnaDestinationPlace, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Box(
            modifier = Modifier
                .size(34.dp)
                .clip(CircleShape)
                .background(BCColors.fromHex(place.colorHex).copy(alpha = 0.2f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(Icons.Default.Place, contentDescription = null, tint = BCColors.fromHex(place.colorHex), modifier = Modifier.size(18.dp))
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(place.name, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(place.subtitle, color = BCColors.TextMuted, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun MapCrosshairPickerView(
    target: EndpointTarget,
    initialPoint: GeoPointData,
    viewModel: AuthViewModel,
    onCancel: () -> Unit,
    onConfirm: (TacnaDestinationPlace) -> Unit
) {
    val isOrigin = target == EndpointTarget.ORIGIN
    var centerCoord by remember { mutableStateOf(initialPoint) }
    var resolvedPlace by remember { mutableStateOf<TacnaDestinationPlace?>(null) }

    LaunchedEffect(centerCoord) {
        delay(420L)
        resolvedPlace = viewModel.networkClient.reverseGeocodeInTacna(centerCoord)
    }

    Box(modifier = Modifier.fillMaxSize()) {
        BCOsmMapView(
            modifier = Modifier.fillMaxSize(),
            cameraCommand = CameraFocusCommand(initialPoint, 16.2, 1),
            onCameraCenterMoved = { pt -> centerCoord = pt }
        )

        // Mira fija central
        Icon(
            Icons.Default.Place,
            contentDescription = null,
            tint = if (isOrigin) BCColors.RoyalBlue else BCColors.DestructiveRed,
            modifier = Modifier
                .align(Alignment.Center)
                .size(44.dp)
                .padding(bottom = 18.dp)
        )

        Surface(
            modifier = Modifier
                .align(Alignment.TopStart)
                .statusBarsPadding()
                .padding(14.dp),
            shape = RoundedCornerShape(50),
            color = BCColors.ElevatedSurface.copy(alpha = 0.94f),
            border = BorderStroke(1.dp, BCColors.HairlineBorder)
        ) {
            Row(
                modifier = Modifier
                    .clickable(onClick = onCancel)
                    .padding(horizontal = 14.dp, vertical = 9.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
                Text("Mueve el mapa bajo la mira", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            }
        }

        Surface(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .navigationBarsPadding()
                .padding(14.dp)
                .fillMaxWidth(),
            shape = RoundedCornerShape(22.dp),
            color = BCColors.ElevatedSurface.copy(alpha = 0.98f),
            border = BorderStroke(1.dp, BCColors.HairlineBorder),
            shadowElevation = 10.dp
        ) {
            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    resolvedPlace?.name ?: "Ubicación seleccionada en Tacna",
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 15.sp
                )
                Text(
                    resolvedPlace?.subtitle ?: String.format(Locale.US, "%.5f, %.5f", centerCoord.latitude, centerCoord.longitude),
                    color = BCColors.TextSecondary,
                    fontSize = 12.sp
                )
                Button(
                    onClick = {
                        val finalPlace = resolvedPlace ?: TacnaDestinationPlace.fromMapItem(
                            name = if (isOrigin) "Inicio en mapa" else "Destino en mapa",
                            subtitle = "Punto personalizado en Tacna",
                            coordinate = centerCoord
                        )
                        onConfirm(finalPlace)
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(48.dp),
                    shape = RoundedCornerShape(14.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = BCColors.CyanAccent, contentColor = Color.Black)
                ) {
                    Icon(Icons.Default.CheckCircle, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text(
                        if (isOrigin) "Establecer Punto de Inicio" else "Establecer Destino y Calcular Ruta",
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }
    }
}

@Composable
private fun RouteMapResultView(
    origin: TacnaDestinationPlace,
    destination: TacnaDestinationPlace,
    camera: CameraFocusCommand,
    walkCoords: List<GeoPointData>,
    busCoords: List<GeoPointData>,
    finalCoords: List<GeoPointData>,
    evaluationResult: RouteAutomationEvaluationResult?,
    candidates: List<EvaluatedRouteCandidate>,
    activeCandidate: EvaluatedRouteCandidate?,
    selectedCandidateIdx: Int,
    selectedFilter: RouteFilterTab,
    sheetSnap: SheetSnapLevel,
    userFareLabel: String,
    onBack: () -> Unit,
    onEditOrigin: () -> Unit,
    onEditDestination: () -> Unit,
    onSwap: () -> Unit,
    onFilterSelected: (RouteFilterTab) -> Unit,
    onCandidateSelected: (Int) -> Unit,
    onCycleSnap: () -> Unit,
    onSetSnap: (SheetSnapLevel) -> Unit,
    onStartGuidance: (EvaluatedRouteCandidate) -> Unit
) {
    val polylines = remember(activeCandidate, walkCoords, busCoords, finalCoords) {
        buildList {
            val w1 = if (walkCoords.size >= 2) walkCoords else activeCandidate?.walkToBoardCoords.orEmpty()
            if (w1.size >= 2) {
                add(MapPolylineSpec("p_walk1", w1, BCColors.CyanAccent.toArgb(), 10f, dashed = true))
            }
            if (activeCandidate != null && activeCandidate.kind != EvaluatedCandidateKind.WALKING_DIRECT) {
                val isOrd = activeCandidate.kind == EvaluatedCandidateKind.ORDINARY_IN_SERVICE
                val b = if (busCoords.size >= 2) busCoords else activeCandidate.busTransitCoords
                if (b.size >= 2) {
                    add(
                        MapPolylineSpec(
                            "p_bus",
                            b,
                            BCColors.fromHex(activeCandidate.colorHex).toArgb(),
                            if (isOrd) 14f else 11f,
                            dashed = !isOrd
                        )
                    )
                }
            }
            val w2 = if (finalCoords.size >= 2) finalCoords else activeCandidate?.walkFinalCoords.orEmpty()
            if (w2.size >= 2) {
                add(MapPolylineSpec("p_walk2", w2, BCColors.CyanAccent.toArgb(), 10f, dashed = true))
            }
        }
    }

    val markers = remember(origin, destination, activeCandidate) {
        buildList {
            add(MapMarkerSpec("r_orig", origin.coordinate, MapMarkerKind.USER_ORIGIN_DOT, BCColors.RoyalBlue.toArgb()))
            if (activeCandidate != null && activeCandidate.kind != EvaluatedCandidateKind.WALKING_DIRECT) {
                val isOrd = activeCandidate.kind == EvaluatedCandidateKind.ORDINARY_IN_SERVICE
                add(
                    MapMarkerSpec(
                        "r_board",
                        activeCandidate.boardingCoordinate,
                        MapMarkerKind.TRANSIT_STOP_DOT,
                        (if (isOrd) BCColors.Emerald else BCColors.Amber).toArgb()
                    )
                )
                add(
                    MapMarkerSpec(
                        "r_alight",
                        activeCandidate.alightingCoordinate,
                        MapMarkerKind.TRANSIT_STOP_DOT,
                        BCColors.CyanAccent.toArgb()
                    )
                )
            }
            add(MapMarkerSpec("r_dest", destination.coordinate, MapMarkerKind.DESTINATION_PIN, BCColors.DestructiveRed.toArgb(), destination.shortName))
        }
    }

    val density = LocalDensity.current
    var activeDragDeltaPx by remember { mutableFloatStateOf(0f) }
    var isDraggingSheet by remember { mutableStateOf(false) }

    val targetSheetDp = remember(sheetSnap, activeDragDeltaPx, density) {
        val baseDp = sheetSnap.heightDp.toFloat()
        val deltaDp = with(density) { -activeDragDeltaPx.toDp().value }
        (baseDp + deltaDp)
            .coerceIn(SheetSnapLevel.COMPACT.heightDp.toFloat(), SheetSnapLevel.FULL.heightDp.toFloat())
            .dp
    }

    val animatedSheetHeight by animateDpAsState(
        targetValue = targetSheetDp,
        animationSpec = if (isDraggingSheet) {
            spring(stiffness = Spring.StiffnessHigh)
        } else {
            spring(dampingRatio = 0.84f, stiffness = Spring.StiffnessMediumLow)
        },
        label = "sheetHeight"
    )

    Box(modifier = Modifier.fillMaxSize()) {
        BCOsmMapView(
            modifier = Modifier.fillMaxSize(),
            cameraCommand = camera,
            polylines = polylines,
            markers = markers
        )

        // Top translucent fade
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(100.dp)
                .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.72f), Color.Transparent)))
        )

        // Cabecera Flotante de Origen y Destino
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(horizontal = 12.dp, vertical = 6.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                IconButton(
                    onClick = onBack,
                    modifier = Modifier
                        .size(38.dp)
                        .clip(CircleShape)
                        .background(BCColors.ControlSurface.copy(alpha = 0.94f))
                ) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Atrás", tint = Color.White)
                }

                Surface(
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(16.dp),
                    color = BCColors.ControlSurface.copy(alpha = 0.94f),
                    border = BorderStroke(1.dp, BCColors.HairlineBorder)
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(
                                "Desde: ${origin.shortName}",
                                color = BCColors.SkyBlue,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.clickable(onClick = onEditOrigin)
                            )
                            HorizontalDivider(color = BCColors.HairlineBorder)
                            Text(
                                "Hasta: ${destination.shortName}",
                                color = Color.White,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.clickable(onClick = onEditDestination)
                            )
                        }
                        IconButton(onClick = onSwap, modifier = Modifier.size(32.dp)) {
                            Icon(Icons.Default.SwapVert, contentDescription = "Invertir", tint = Color.White)
                        }
                    }
                }
            }

            // Píldora Multimodal resumida
            activeCandidate?.let { cand ->
                val isOrd = cand.kind == EvaluatedCandidateKind.ORDINARY_IN_SERVICE
                Surface(
                    shape = RoundedCornerShape(14.dp),
                    color = BCColors.ControlSurface.copy(alpha = 0.92f),
                    border = BorderStroke(1.dp, BCColors.HairlineBorder)
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 12.dp, vertical = 7.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text("🚶 ${cand.walkInitialMinutes}m", color = BCColors.CyanAccent, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                            if (cand.kind != EvaluatedCandidateKind.WALKING_DIRECT) {
                                Text("→", color = BCColors.TextMuted, fontSize = 10.sp)
                                Surface(shape = RoundedCornerShape(5.dp), color = BCColors.fromHex(cand.colorHex)) {
                                    Text(
                                        "${cand.routeCode} (${cand.busRideMinutes}m)",
                                        color = Color.White,
                                        fontSize = 10.sp,
                                        fontWeight = FontWeight.Bold,
                                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                                    )
                                }
                            }
                            if (cand.walkFinalMinutes > 0) {
                                Text("→ 🚶 ${cand.walkFinalMinutes}m", color = BCColors.CyanAccent, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                            }
                        }
                        Text(
                            if (isOrd) "~${cand.totalDurationMinutes} min · $userFareLabel" else "~${cand.totalDurationMinutes} min · Sin QR",
                            color = if (isOrd) BCColors.Emerald else BCColors.Amber,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.ExtraBold
                        )
                    }
                }
            }
        }

        // Hoja Inferior Interactiva de 3 Niveles (Compact / Medium / Full) con arrastre continuo estilo Apple
        Surface(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .height(animatedSheetHeight),
            shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
            color = BCColors.SheetSurface.copy(alpha = 0.96f),
            border = BorderStroke(1.dp, Color.White.copy(alpha = 0.14f)),
            shadowElevation = 20.dp
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .navigationBarsPadding()
            ) {
                // Zona superior arrastrable (Handle + Chips)
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .pointerInput(sheetSnap) {
                            detectVerticalDragGestures(
                                onDragStart = {
                                    isDraggingSheet = true
                                    activeDragDeltaPx = 0f
                                },
                                onVerticalDrag = { change, dragAmount ->
                                    change.consume()
                                    activeDragDeltaPx += dragAmount
                                },
                                onDragEnd = {
                                    val deltaDp = with(density) { -activeDragDeltaPx.toDp().value }
                                    val projectedDp = (sheetSnap.heightDp + deltaDp)
                                        .coerceIn(
                                            SheetSnapLevel.COMPACT.heightDp.toFloat(),
                                            SheetSnapLevel.FULL.heightDp.toFloat()
                                        )
                                    val nearest = SheetSnapLevel.entries.minByOrNull { level ->
                                        kotlin.math.abs(level.heightDp - projectedDp)
                                    } ?: sheetSnap
                                    activeDragDeltaPx = 0f
                                    isDraggingSheet = false
                                    onSetSnap(nearest)
                                },
                                onDragCancel = {
                                    activeDragDeltaPx = 0f
                                    isDraggingSheet = false
                                }
                            )
                        }
                ) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable(onClick = onCycleSnap)
                            .padding(top = 10.dp, bottom = 8.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Box(
                            modifier = Modifier
                                .width(44.dp)
                                .height(5.dp)
                                .clip(RoundedCornerShape(50))
                                .background(Color.White.copy(alpha = 0.34f))
                        )
                    }

                    // Selector rápido de modo/filtro en Nivel Medium & Full
                    if (sheetSnap != SheetSnapLevel.COMPACT) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .horizontalScroll(rememberScrollState())
                                .padding(horizontal = 16.dp, vertical = 2.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            RouteFilterTab.entries.forEach { tab ->
                                FilterChip(
                                    selected = selectedFilter == tab,
                                    onClick = { onFilterSelected(tab) },
                                    label = { Text(tab.label, fontSize = 11.sp) },
                                    colors = FilterChipDefaults.filterChipColors(
                                        selectedContainerColor = BCColors.AppleBlue,
                                        selectedLabelColor = Color.White,
                                        containerColor = BCColors.ControlSurface,
                                        labelColor = BCColors.TextSecondary
                                    )
                                )
                            }
                        }
                    }
                }

                // Contenido principal con transición suave entre niveles
                Crossfade(
                    targetState = sheetSnap,
                    animationSpec = tween(durationMillis = 190),
                    label = "sheetSnapCrossfade",
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .animateContentSize(spring(dampingRatio = 0.85f, stiffness = Spring.StiffnessMediumLow))
                ) { currentSnap ->
                    when (currentSnap) {
                        SheetSnapLevel.COMPACT -> {
                            activeCandidate?.let { cand ->
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(horizontal = 16.dp, vertical = 6.dp),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                            Surface(shape = RoundedCornerShape(6.dp), color = BCColors.fromHex(cand.colorHex)) {
                                                Text(
                                                    cand.routeCode,
                                                    color = Color.White,
                                                    fontWeight = FontWeight.Black,
                                                    fontSize = 11.sp,
                                                    modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp)
                                                )
                                            }
                                            Text(
                                                "~${cand.totalDurationMinutes} min · ${cand.totalDistanceLabel}",
                                                color = Color.White,
                                                fontWeight = FontWeight.Black,
                                                fontSize = 15.sp
                                            )
                                        }
                                        Text(
                                            if (cand.kind == EvaluatedCandidateKind.WALKING_DIRECT)
                                                "Caminata directa · Sin costo"
                                            else "Sube: ${cand.boardingPointName} → Baja: ${cand.alightingPointName}",
                                            color = BCColors.TextSecondary,
                                            fontSize = 11.sp,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis
                                        )
                                    }
                                    TextButton(onClick = { onSetSnap(SheetSnapLevel.MEDIUM) }) {
                                        Text("Ver tramos", color = BCColors.CyanAccent, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                                    }
                                }
                            }
                        }

                        SheetSnapLevel.MEDIUM -> {
                            activeCandidate?.let { cand ->
                                Column(
                                    modifier = Modifier
                                        .fillMaxSize()
                                        .verticalScroll(rememberScrollState())
                                        .padding(horizontal = 16.dp),
                                    verticalArrangement = Arrangement.spacedBy(10.dp)
                                ) {
                                    Row(
                                        modifier = Modifier.horizontalScroll(rememberScrollState()),
                                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                                    ) {
                                        candidates.forEachIndexed { index, item ->
                                            val isSel = index == selectedCandidateIdx
                                            Surface(
                                                modifier = Modifier.clickable { onCandidateSelected(index) },
                                                shape = RoundedCornerShape(10.dp),
                                                color = if (isSel) BCColors.AppleBlue.copy(alpha = 0.25f) else BCColors.ControlSurface,
                                                border = BorderStroke(1.dp, if (isSel) BCColors.AppleBlue else BCColors.HairlineBorder)
                                            ) {
                                                Text(
                                                    "${item.routeCode} · ${item.totalDurationMinutes}m",
                                                    color = Color.White,
                                                    fontSize = 12.sp,
                                                    fontWeight = FontWeight.Bold,
                                                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp)
                                                )
                                            }
                                        }
                                    }

                                    Surface(shape = RoundedCornerShape(14.dp), color = BCColors.CardSurface) {
                                        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                            if (cand.kind == EvaluatedCandidateKind.WALKING_DIRECT) {
                                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                                    Icon(Icons.Default.DirectionsWalk, contentDescription = null, tint = BCColors.CyanAccent, modifier = Modifier.size(18.dp))
                                                    Text(
                                                        "Caminar a ${destination.shortName} · ${cand.walkInitialMeters} m (${cand.walkInitialMinutes}m)",
                                                        color = Color.White,
                                                        fontSize = 13.sp,
                                                        fontWeight = FontWeight.SemiBold
                                                    )
                                                }
                                            } else {
                                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                                    Icon(Icons.Default.DirectionsWalk, contentDescription = null, tint = BCColors.CyanAccent, modifier = Modifier.size(16.dp))
                                                    Text("Camina ${cand.walkInitialMeters} m hasta ${cand.boardingPointName}", color = Color.White, fontSize = 12.sp)
                                                }
                                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                                    Icon(Icons.Default.DirectionsBus, contentDescription = null, tint = BCColors.Emerald, modifier = Modifier.size(16.dp))
                                                    Text(
                                                        "Toma ${cand.routeCode} (~${cand.busRideMinutes} min · ${if (cand.kind == EvaluatedCandidateKind.ORDINARY_IN_SERVICE) "Pago QR $userFareLabel" else "Abordaje libre"})",
                                                        color = BCColors.CyanAccent,
                                                        fontSize = 12.sp,
                                                        fontWeight = FontWeight.Bold
                                                    )
                                                }
                                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                                    Icon(Icons.Default.Place, contentDescription = null, tint = BCColors.DestructiveRed, modifier = Modifier.size(16.dp))
                                                    Text("Baja en ${cand.alightingPointName} (${cand.walkFinalMinutes}m al destino)", color = Color.White, fontSize = 12.sp)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        SheetSnapLevel.FULL -> {
                            LazyColumn(
                                modifier = Modifier
                                    .fillMaxSize()
                                    .padding(horizontal = 16.dp),
                                verticalArrangement = Arrangement.spacedBy(10.dp)
                            ) {
                                evaluationResult?.primaryBannerWarning?.let { warn ->
                                    item {
                                        Surface(
                                            shape = RoundedCornerShape(12.dp),
                                            color = BCColors.Amber.copy(alpha = 0.14f),
                                            border = BorderStroke(1.dp, BCColors.Amber.copy(alpha = 0.45f))
                                        ) {
                                            Row(modifier = Modifier.padding(10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                                Icon(Icons.Default.Warning, contentDescription = null, tint = BCColors.Amber, modifier = Modifier.size(16.dp))
                                                Text(warn, color = Color.White, fontSize = 11.sp)
                                            }
                                        }
                                    }
                                }

                                items(candidates.indices.toList()) { idx ->
                                    val cand = candidates[idx]
                                    val isSel = idx == selectedCandidateIdx
                                    val isOrd = cand.kind == EvaluatedCandidateKind.ORDINARY_IN_SERVICE
                                    Surface(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clickable { onCandidateSelected(idx) },
                                        shape = RoundedCornerShape(16.dp),
                                        color = BCColors.CardSurface,
                                        border = BorderStroke(if (isSel) 2.dp else 1.dp, if (isSel) BCColors.AppleBlue else BCColors.HairlineBorder)
                                    ) {
                                        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                                    Surface(shape = RoundedCornerShape(6.dp), color = BCColors.fromHex(cand.colorHex)) {
                                                        Text(cand.routeCode, color = Color.White, fontWeight = FontWeight.Black, fontSize = 11.sp, modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp))
                                                    }
                                                    Text(
                                                        if (isOrd) "Ordinaria · GPS & QR" else if (cand.kind == EvaluatedCandidateKind.EXTERNAL_FREE_BOARDING) "Externa · Sin GPS" else "Peatonal",
                                                        color = if (isOrd) BCColors.Emerald else BCColors.Amber,
                                                        fontSize = 11.sp,
                                                        fontWeight = FontWeight.Bold
                                                    )
                                                }
                                                Text("~${cand.totalDurationMinutes} min", color = Color.White, fontWeight = FontWeight.Black, fontSize = 14.sp)
                                            }
                                            Text(
                                                "${cand.boardingPointName} → ${cand.alightingPointName} (${cand.totalDistanceLabel})",
                                                color = BCColors.TextSecondary,
                                                fontSize = 11.sp,
                                                maxLines = 2
                                            )
                                            if (isOrd) {
                                                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                                        Icon(Icons.Default.QrCode2, contentDescription = null, tint = BCColors.Emerald, modifier = Modifier.size(13.dp))
                                                        Text("QR $userFareLabel", color = BCColors.Emerald, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                                                    }
                                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                                        Icon(Icons.Default.NotificationsActive, contentDescription = null, tint = BCColors.Emerald, modifier = Modifier.size(13.dp))
                                                        Text("Aviso 5m", color = BCColors.Emerald, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // CTA Inferior Fijo: "Ir con <RUTA>"
                activeCandidate?.let { cand ->
                    Box(modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) {
                        Button(
                            onClick = { onStartGuidance(cand) },
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(50.dp),
                            shape = RoundedCornerShape(14.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = BCColors.Emerald, contentColor = Color.Black)
                        ) {
                            Icon(Icons.Default.Navigation, contentDescription = null)
                            Spacer(Modifier.width(8.dp))
                            Text("Ir con ${cand.routeCode}", fontWeight = FontWeight.Black, fontSize = 16.sp)
                        }
                    }
                }
            }
        }
    }
}


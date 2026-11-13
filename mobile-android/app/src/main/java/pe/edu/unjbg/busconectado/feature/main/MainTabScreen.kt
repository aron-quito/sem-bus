package pe.edu.unjbg.busconectado.feature.main

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Directions
import androidx.compose.material.icons.filled.DirectionsBus
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import kotlinx.coroutines.delay
import pe.edu.unjbg.busconectado.core.designsystem.BCColors
import pe.edu.unjbg.busconectado.core.designsystem.SpeechSearchEngine
import pe.edu.unjbg.busconectado.core.model.ActiveTripState
import pe.edu.unjbg.busconectado.core.model.MainAppTab
import pe.edu.unjbg.busconectado.core.model.TacnaDestinationPlace
import pe.edu.unjbg.busconectado.feature.auth.AuthViewModel
import pe.edu.unjbg.busconectado.feature.auth.BCUiState
import pe.edu.unjbg.busconectado.feature.explore.ExploreMapScreen
import pe.edu.unjbg.busconectado.feature.explore.RoutePlannerScreen
import pe.edu.unjbg.busconectado.feature.lines.LinesScreen
import pe.edu.unjbg.busconectado.feature.profile.HelpFaqDialog
import pe.edu.unjbg.busconectado.feature.profile.ProfileSheet
import pe.edu.unjbg.busconectado.feature.qrscan.PayQrScreen
import pe.edu.unjbg.busconectado.feature.wallet.WalletScreen
import java.util.Locale

@Composable
fun MainTabScreen(
    state: BCUiState,
    viewModel: AuthViewModel
) {
    val context = LocalContext.current
    val focusManager = LocalFocusManager.current
    val speechEngine = remember { SpeechSearchEngine(context) }
    val isListening by speechEngine.isListening.collectAsState()

    var isSearchFocused by remember { mutableStateOf(false) }
    var showProfileSheet by remember { mutableStateOf(false) }
    var showFaqDialog by remember { mutableStateOf(false) }
    var apiDropdownPlaces by remember { mutableStateOf<List<TacnaDestinationPlace>>(emptyList()) }
    var isSearchingApi by remember { mutableStateOf(false) }

    val micLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) {
            speechEngine.startListening { spoken ->
                viewModel.onSearchTextChanged(spoken)
                isSearchFocused = true
            }
        }
    }

    DisposableEffect(Unit) {
        onDispose { speechEngine.release() }
    }

    LaunchedEffect(state.searchText) {
        val q = state.searchText.trim()
        if (q.length < 2) {
            apiDropdownPlaces = emptyList()
            isSearchingApi = false
            return@LaunchedEffect
        }
        isSearchingApi = true
        delay(250L)
        apiDropdownPlaces = viewModel.networkClient.searchLivePlacesInTacna(q)
        isSearchingApi = false
    }

    val catalogSuggestions = remember(state.searchText, state.dynamicCatalogStops) {
        viewModel.filteredPredictivePlaces(state.searchText)
    }

    val navBottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    val dockReservedBottom = navBottom + 88.dp
    val contentBottom = PaddingValues(bottom = dockReservedBottom)
    val isModalCoveringScreen =
        showProfileSheet || showFaqDialog || state.isRoutePlannerPresented || state.showInsufficientBalanceDialog

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(BCColors.DarkBackground)
    ) {
        // Contenido principal con transición fluida entre pestañas
        Crossfade(
            targetState = state.selectedTab,
            animationSpec = tween(durationMillis = 210),
            label = "mainTabCrossfade"
        ) { tab ->
            when (tab) {
                MainAppTab.EXPLORE -> ExploreMapScreen(
                    state = state,
                    viewModel = viewModel,
                    onDismissSearchFocus = {
                        isSearchFocused = false
                        focusManager.clearFocus()
                    },
                    bottomInsetPadding = contentBottom
                )
                MainAppTab.LINES -> LinesScreen(
                    state = state,
                    viewModel = viewModel,
                    bottomContentPadding = contentBottom
                )
                MainAppTab.PAY_QR -> PayQrScreen(
                    state = state,
                    viewModel = viewModel,
                    isScreenActive = !isModalCoveringScreen && state.selectedTab == MainAppTab.PAY_QR,
                    bottomContentPadding = contentBottom
                )
                MainAppTab.WALLET -> WalletScreen(
                    state = state,
                    viewModel = viewModel,
                    onOpenHelpFaq = { showFaqDialog = true },
                    bottomContentPadding = contentBottom
                )
            }
        }

        // Píldora flotante de búsqueda global + Voz + Avatar Perfil (oculta en Pagar QR como en iOS)
        AnimatedVisibility(
            visible = state.selectedTab != MainAppTab.PAY_QR,
            enter = fadeIn(tween(180)) + slideInVertically { -it / 2 },
            exit = fadeOut(tween(140)) + slideOutVertically { -it / 2 },
            modifier = Modifier.align(Alignment.TopCenter)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .statusBarsPadding()
                    .padding(horizontal = 14.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Surface(
                    shape = RoundedCornerShape(50),
                    color = BCColors.ControlSurface.copy(alpha = 0.94f),
                    border = BorderStroke(1.dp, Color.White.copy(alpha = 0.14f)),
                    shadowElevation = 10.dp
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(50.dp)
                            .padding(start = 14.dp, end = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(
                            Icons.Default.Search,
                            contentDescription = null,
                            tint = if (isListening) BCColors.DestructiveRed else BCColors.CyanAccent,
                            modifier = Modifier.size(20.dp)
                        )

                        Box(modifier = Modifier.weight(1f)) {
                            if (state.searchText.isEmpty()) {
                                Text(
                                    if (isListening) "Escuchando en Tacna..." else "Buscar lugar o paradero en Tacna...",
                                    color = if (isListening) BCColors.DestructiveRed else BCColors.TextMuted,
                                    fontSize = 13.sp,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                            BasicTextField(
                                value = state.searchText,
                                onValueChange = { viewModel.onSearchTextChanged(it) },
                                singleLine = true,
                                textStyle = TextStyle(color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Medium),
                                cursorBrush = SolidColor(BCColors.CyanAccent),
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .onFocusChanged { isSearchFocused = it.isFocused }
                            )
                        }

                        if (state.searchText.isNotEmpty() || state.searchedDestinationPin != null) {
                            IconButton(
                                onClick = {
                                    viewModel.onSearchTextChanged("")
                                    viewModel.clearSearchedDestinationPin()
                                    isSearchFocused = false
                                    focusManager.clearFocus()
                                },
                                modifier = Modifier.size(30.dp)
                            ) {
                                Icon(Icons.Default.Close, contentDescription = "Limpiar", tint = BCColors.TextSecondary, modifier = Modifier.size(18.dp))
                            }
                        }

                        IconButton(
                            onClick = {
                                val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
                                if (!granted) {
                                    micLauncher.launch(Manifest.permission.RECORD_AUDIO)
                                } else {
                                    speechEngine.startListening { spoken ->
                                        viewModel.onSearchTextChanged(spoken)
                                        isSearchFocused = true
                                    }
                                }
                            },
                            modifier = Modifier.size(34.dp)
                        ) {
                            Icon(
                                Icons.Default.Mic,
                                contentDescription = "Buscar por voz",
                                tint = if (isListening) BCColors.DestructiveRed else Color.White,
                                modifier = Modifier.size(20.dp)
                            )
                        }

                        Box(
                            modifier = Modifier
                                .size(36.dp)
                                .clip(CircleShape)
                                .background(BCColors.RoyalBlue)
                                .clickable { showProfileSheet = true },
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                state.currentUser?.initials ?: "BC",
                                color = Color.White,
                                fontWeight = FontWeight.Black,
                                fontSize = 13.sp
                            )
                        }
                    }
                }

                // Dropdown predictivo de búsqueda
                if ((isSearchFocused || state.searchText.isNotBlank()) &&
                    (catalogSuggestions.isNotEmpty() || apiDropdownPlaces.isNotEmpty() || isSearchingApi)
                ) {
                    Surface(
                        shape = RoundedCornerShape(18.dp),
                        color = BCColors.ElevatedSurface.copy(alpha = 0.98f),
                        border = BorderStroke(1.dp, BCColors.HairlineBorder),
                        shadowElevation = 12.dp,
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(max = 310.dp)
                    ) {
                        Column {
                            if (isSearchingApi) {
                                Row(
                                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                                ) {
                                    CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp, color = BCColors.CyanAccent)
                                    Text("Consultando mapa de Tacna...", color = BCColors.CyanAccent, fontSize = 11.sp)
                                }
                            }

                            LazyColumn {
                                if (catalogSuggestions.isNotEmpty()) {
                                    item {
                                        Text(
                                            "PARADEROS DE TACNA Y PUNTOS OFICIALES",
                                            color = BCColors.TextMuted,
                                            fontSize = 10.sp,
                                            fontWeight = FontWeight.Bold,
                                            modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp)
                                        )
                                    }
                                    items(catalogSuggestions.take(6), key = { "drop_cat_${it.id}" }) { place ->
                                        PredictiveSearchRow(
                                            place = place,
                                            onSelectPlace = {
                                                isSearchFocused = false
                                                focusManager.clearFocus()
                                                viewModel.focusMapOnPlace(place)
                                            },
                                            onRouteNow = {
                                                isSearchFocused = false
                                                focusManager.clearFocus()
                                                viewModel.openRoutePlanner(destination = place)
                                            }
                                        )
                                    }
                                }

                                if (apiDropdownPlaces.isNotEmpty()) {
                                    item {
                                        Text(
                                            "LUGARES DEL MAPA (OSM TACNA)",
                                            color = BCColors.CyanAccent,
                                            fontSize = 10.sp,
                                            fontWeight = FontWeight.Bold,
                                            modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp)
                                        )
                                    }
                                    items(apiDropdownPlaces.take(5), key = { "drop_api_${it.id}" }) { place ->
                                        PredictiveSearchRow(
                                            place = place,
                                            onSelectPlace = {
                                                isSearchFocused = false
                                                focusManager.clearFocus()
                                                viewModel.focusMapOnPlace(place)
                                            },
                                            onRouteNow = {
                                                isSearchFocused = false
                                                focusManager.clearFocus()
                                                viewModel.openRoutePlanner(destination = place)
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Banner de Viaje Activo validado por QR (CU-06) + Dock flotante translúcido estilo Apple
        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 14.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            AnimatedVisibility(
                visible = state.activeTrip != null && state.selectedTab != MainAppTab.PAY_QR,
                enter = fadeIn() + slideInVertically { it / 2 },
                exit = fadeOut() + slideOutVertically { it / 2 }
            ) {
                state.activeTrip?.let { trip ->
                    ActiveTripOverlayBanner(
                        trip = trip,
                        onEndTrip = { viewModel.endActiveTrip() }
                    )
                }
            }

            FloatingGlassTabDock(
                selectedTab = state.selectedTab,
                onSelectTab = { tab ->
                    isSearchFocused = false
                    focusManager.clearFocus()
                    viewModel.selectTab(tab)
                }
            )
        }
    }

    // Planificador Multimodal Fullscreen ("Ir")
    if (state.isRoutePlannerPresented) {
        Dialog(
            onDismissRequest = { viewModel.closeRoutePlanner() },
            properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)
        ) {
            RoutePlannerScreen(
                state = state,
                viewModel = viewModel,
                onClose = { viewModel.closeRoutePlanner() }
            )
        }
    }

    // Hoja de Perfil
    if (showProfileSheet) {
        ProfileSheet(
            state = state,
            viewModel = viewModel,
            onDismiss = { showProfileSheet = false }
        )
    }

    if (showFaqDialog) {
        HelpFaqDialog(onDismiss = { showFaqDialog = false })
    }

    if (state.showPhoneLinkDialog) {
        pe.edu.unjbg.busconectado.feature.auth.ui.PhoneLinkModalDialog(
            state = state,
            viewModel = viewModel
        )
    }

    // Alerta de Saldo Insuficiente en pago QR
    if (state.showInsufficientBalanceDialog) {
        AlertDialog(
            onDismissRequest = { viewModel.dismissInsufficientBalanceDialog() },
            containerColor = BCColors.ElevatedSurface,
            title = { Text("Saldo Insuficiente", color = Color.White, fontWeight = FontWeight.Bold) },
            text = { Text(state.insufficientBalanceDetail, color = BCColors.TextSecondary) },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.dismissInsufficientBalanceDialog()
                    viewModel.selectTab(MainAppTab.WALLET)
                }) {
                    Text("Recargar Ahora", color = BCColors.Emerald, fontWeight = FontWeight.Bold)
                }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.dismissInsufficientBalanceDialog() }) {
                    Text("Cancelar", color = Color.White)
                }
            }
        )
    }
}

@Composable
private fun FloatingGlassTabDock(
    selectedTab: MainAppTab,
    onSelectTab: (MainAppTab) -> Unit
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .height(64.dp),
        shape = RoundedCornerShape(32.dp),
        color = Color(0xEA121823),
        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.14f)),
        shadowElevation = 18.dp
    ) {
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 6.dp, vertical = 5.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            MainAppTab.entries.forEach { tab ->
                val selected = selectedTab == tab
                val icon = when (tab) {
                    MainAppTab.EXPLORE -> Icons.Default.Explore
                    MainAppTab.LINES -> Icons.Default.DirectionsBus
                    MainAppTab.PAY_QR -> Icons.Default.QrCodeScanner
                    MainAppTab.WALLET -> Icons.Default.AccountBalanceWallet
                }
                val pillColor by animateColorAsState(
                    targetValue = if (selected) BCColors.AppleBlue.copy(alpha = 0.24f) else Color.Transparent,
                    animationSpec = spring(stiffness = Spring.StiffnessMediumLow),
                    label = "dockPill_${tab.name}"
                )
                val tintColor by animateColorAsState(
                    targetValue = if (selected) BCColors.SkyBlue else BCColors.TextSecondary,
                    animationSpec = spring(stiffness = Spring.StiffnessMediumLow),
                    label = "dockTint_${tab.name}"
                )
                val iconScale by animateFloatAsState(
                    targetValue = if (selected) 1.08f else 0.96f,
                    animationSpec = spring(dampingRatio = 0.65f, stiffness = Spring.StiffnessMedium),
                    label = "dockScale_${tab.name}"
                )
                val interactionSource = remember { MutableInteractionSource() }

                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .clip(RoundedCornerShape(26.dp))
                        .background(pillColor)
                        .clickable(
                            interactionSource = interactionSource,
                            indication = null,
                            onClick = { onSelectTab(tab) }
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(2.dp)
                    ) {
                        Icon(
                            icon,
                            contentDescription = tab.title,
                            tint = tintColor,
                            modifier = Modifier
                                .size(22.dp)
                                .scale(iconScale)
                        )
                        Text(
                            tab.title,
                            color = tintColor,
                            fontSize = 10.sp,
                            fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
                            maxLines = 1,
                            overflow = TextOverflow.Clip
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun PredictiveSearchRow(
    place: TacnaDestinationPlace,
    onSelectPlace: () -> Unit,
    onRouteNow: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onSelectPlace)
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Icon(Icons.Default.Place, contentDescription = null, tint = BCColors.fromHex(place.colorHex), modifier = Modifier.size(18.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(place.name, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(place.subtitle, color = BCColors.TextMuted, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Surface(
            modifier = Modifier.clickable(onClick = onRouteNow),
            shape = RoundedCornerShape(50),
            color = BCColors.CyanAccent.copy(alpha = 0.2f),
            border = BorderStroke(1.dp, BCColors.CyanAccent.copy(alpha = 0.5f))
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Icon(Icons.Default.Directions, contentDescription = "Ir", tint = BCColors.CyanAccent, modifier = Modifier.size(14.dp))
                Text("Ir", color = BCColors.CyanAccent, fontWeight = FontWeight.Bold, fontSize = 11.sp)
            }
        }
    }
    HorizontalDivider(color = BCColors.HairlineBorder, modifier = Modifier.padding(start = 42.dp))
}

@Composable
private fun ActiveTripOverlayBanner(
    trip: ActiveTripState,
    modifier: Modifier = Modifier,
    onEndTrip: () -> Unit
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        color = Color(0xFF052E16).copy(alpha = 0.96f),
        border = BorderStroke(1.dp, BCColors.Emerald.copy(alpha = 0.6f)),
        shadowElevation = 10.dp
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 11.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Icon(Icons.Default.Verified, contentDescription = null, tint = BCColors.Emerald, modifier = Modifier.size(26.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    "Viaje Activo · ${trip.lineNumber} (${trip.plate})",
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 13.sp
                )
                Text(
                    "Pagado: ${trip.pointsPaid} pts · Vigencia QR: ${String.format(Locale.US, "%02d:%02d", trip.remainingSeconds / 60, trip.remainingSeconds % 60)}",
                    color = BCColors.Emerald,
                    fontFamily = FontFamily.Monospace,
                    fontSize = 11.sp
                )
            }
            TextButton(onClick = onEndTrip) {
                Text("Finalizar", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 11.sp)
            }
        }
    }
}

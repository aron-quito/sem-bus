package pe.edu.unjbg.busconectado.feature.driver

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.util.Locale

// PALETA DE COLORES DE CABINA (Material 3 Dark Slate)
val Slate950 = Color(0xFF020617)
val Slate900 = Color(0xFF0F172A)
val Slate800 = Color(0xFF1E293B)
val Slate400 = Color(0xFF94A3B8)
val Slate200 = Color(0xFFE2E8F0)

val EmeraldPrimary = Color(0xFF10B981)
val EmeraldDark = Color(0xFF064E3B)
val EmeraldLight = Color(0xFFA7F3D0)

val AmberPrimary = Color(0xFFF59E0B)
val AmberDark = Color(0xFF78350F)
val AmberLight = Color(0xFFFDE68A)

val RosePrimary = Color(0xFFF43F5E)
val RoseDark = Color(0xFF881337)
val RoseLight = Color(0xFFFECDD3)

val BluePrimary = Color(0xFF2563EB)

@Composable
fun DriverTabletScreen(
    viewModel: DriverViewModel,
    modifier: Modifier = Modifier
) {
    val state by viewModel.uiState.collectAsState()
    var showBreakdownSubmodule by remember { mutableStateOf(false) }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(Slate950)
    ) {
        // 1. BARRA SUPERIOR (HEADER DE CABINA)
        DriverHeader(
            state = state,
            onAdvanceStop = { viewModel.advanceStop() }
        )

        // 2. CUERPO PRINCIPAL (2 COLUMNAS: Izquierda 7 cols / Derecha 5 cols)
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // COLUMNA IZQUIERDA (58% del ancho)
            Column(
                modifier = Modifier
                    .weight(0.58f)
                    .fillMaxHeight(),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                // Último Pasaje Validado (Banner adaptativo)
                state.lastFare?.let { fare ->
                    LastFareBanner(fare = fare)
                }

                // Tabla de Cobros Recientes (Estilo Gestor de Archivos)
                FareDetailsFeed(
                    fares = state.recentFares,
                    onSimulateFare = { type, method ->
                        viewModel.simulateFare(type, method)
                    },
                    modifier = Modifier.weight(1f)
                )

                // Sensores del Vehículo y Botones de Acción
                VehicleSensorsAndActions(
                    sensors = state.sensors,
                    isMapPaused = state.isPublicMapPaused,
                    showSubmodule = showBreakdownSubmodule,
                    onToggleFault = { viewModel.toggleVehicleFault() },
                    onRecordConadis = { viewModel.recordConadis() },
                    onClickBreakdown = {
                        if (state.sensors.hasFault) {
                            showBreakdownSubmodule = !showBreakdownSubmodule
                        }
                    },
                    onTogglePauseMap = { viewModel.togglePausePublicMap() }
                )
            }

            // COLUMNA DERECHA (42% del ancho: Aforo y Liquidación)
            Column(
                modifier = Modifier
                    .weight(0.42f)
                    .fillMaxHeight(),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                // Aforo en Vivo
                BusOccupancyCard(
                    occupancy = state.occupancy,
                    maxCapacity = state.maxCapacity,
                    percentage = state.occupancyPercentage,
                    onAdjustOccupancy = { delta -> viewModel.adjustOccupancy(delta) }
                )

                // Liquidación de Turno
                ShiftLiquidationCard(
                    state = state,
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
}

// -----------------------------------------------------------------------------
// COMPONENTES MODULARES DE LA TABLET
// -----------------------------------------------------------------------------

@Composable
fun DriverHeader(
    state: DriverShiftState,
    onAdvanceStop: () -> Unit
) {
    Surface(
        color = Slate900,
        modifier = Modifier
            .fillMaxWidth()
            .height(56.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 20.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            // Unidad y Chofer
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .background(BluePrimary),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = state.routeLine,
                        color = Color.White,
                        fontWeight = FontWeight.Black,
                        fontSize = 16.sp
                    )
                }
                Column {
                    Text(
                        text = "LÍNEA ${state.routeLine} • UNIDAD ${state.busId}",
                        color = Color.White,
                        fontWeight = FontWeight.ExtraBold,
                        fontSize = 13.sp
                    )
                    Text(
                        text = "Placa: ${state.plate} • Chofer: ${state.driverName}",
                        color = Slate400,
                        fontSize = 11.sp
                    )
                }
            }

            // Paradero Actual ➔ Siguiente
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Surface(
                    color = Slate950,
                    shape = RoundedCornerShape(12.dp),
                    border = borderStroke(),
                    modifier = Modifier.padding(vertical = 4.dp)
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text("ACTUAL:", color = Slate400, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                        Text(state.currentStopName, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Black)
                        Text("➔", color = BluePrimary, fontWeight = FontWeight.Black)
                        Text("SIGUIENTE:", color = Slate400, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                        Text(state.nextStopName, color = Color(0xFF93C5FD), fontSize = 12.sp, fontWeight = FontWeight.Black)
                    }
                }

                Button(
                    onClick = onAdvanceStop,
                    colors = ButtonDefaults.buttonColors(containerColor = Slate800),
                    shape = RoundedCornerShape(10.dp),
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp)
                ) {
                    Text("Siguiente", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

@Composable
fun LastFareBanner(fare: FareRecord) {
    val borderColor = when (fare.fareType) {
        FareType.STUDENT, FareType.CONADIS -> AmberPrimary
        FareType.ADULT -> EmeraldPrimary
        FareType.INSUFFICIENT -> RosePrimary
    }

    val amountColor = when (fare.fareType) {
        FareType.STUDENT, FareType.CONADIS -> AmberPrimary
        FareType.ADULT -> EmeraldPrimary
        FareType.INSUFFICIENT -> RosePrimary
    }

    Surface(
        color = Slate900,
        shape = RoundedCornerShape(16.dp),
        border = BorderStroke(2.dp, borderColor.copy(alpha = 0.8f)),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Surface(
                        color = when (fare.fareType) {
                            FareType.STUDENT, FareType.CONADIS -> AmberDark
                            FareType.ADULT -> EmeraldDark
                            FareType.INSUFFICIENT -> RoseDark
                        },
                        shape = CircleShape
                    ) {
                        Text(
                            text = fare.fareType.displayName,
                            color = when (fare.fareType) {
                                FareType.STUDENT, FareType.CONADIS -> AmberLight
                                FareType.ADULT -> EmeraldLight
                                FareType.INSUFFICIENT -> RoseLight
                            },
                            fontWeight = FontWeight.Black,
                            fontSize = 10.sp,
                            modifier = Modifier.padding(horizontal = 10.dp, vertical = 2.dp)
                        )
                    }
                    Text(fare.timeFormatted, color = Slate400, fontSize = 11.sp)
                }
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = fare.paymentMethod.label,
                    color = Slate200,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold
                )
            }

            Column(horizontalAlignment = Alignment.End) {
                Text(
                    text = fare.amountFormatted,
                    color = amountColor,
                    fontSize = 28.sp,
                    fontWeight = FontWeight.Black,
                    fontFamily = FontFamily.Monospace
                )
                Text(
                    text = if (fare.isSuccess) "Validado en puerta" else "Cobro rechazado",
                    color = Slate400,
                    fontSize = 11.sp
                )
            }
        }
    }
}

@Composable
fun FareDetailsFeed(
    fares: List<FareRecord>,
    onSimulateFare: (FareType, PaymentMethod) -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        color = Slate900,
        shape = RoundedCornerShape(16.dp),
        border = borderStroke(),
        modifier = modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            // Header del Feed con botones de prueba rápida
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Slate950)
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text("DETALLES DE PASAJES", color = Slate400, fontSize = 10.sp, fontWeight = FontWeight.Bold)

                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    MiniTestButton("+ Adulto App", EmeraldDark, EmeraldLight) {
                        onSimulateFare(FareType.ADULT, PaymentMethod.APP)
                    }
                    MiniTestButton("+ Univ Yape", AmberDark, AmberLight) {
                        onSimulateFare(FareType.STUDENT, PaymentMethod.YAPE_PLIN)
                    }
                    MiniTestButton("+ POS", BluePrimary.copy(alpha = 0.3f), Color(0xFF93C5FD)) {
                        onSimulateFare(FareType.ADULT, PaymentMethod.POS)
                    }
                    MiniTestButton("+ Rechazo", RoseDark, RoseLight) {
                        onSimulateFare(FareType.INSUFFICIENT, PaymentMethod.APP)
                    }
                }
            }

            // Cabecera de columnas
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 6.dp)
            ) {
                Text("HORA", color = Slate400, fontSize = 10.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(0.2f))
                Text("TARIFA", color = Slate400, fontSize = 10.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(0.3f))
                Text("MEDIO DE PAGO", color = Slate400, fontSize = 10.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(0.35f))
                Text("IMPORTE", color = Slate400, fontSize = 10.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.End, modifier = Modifier.weight(0.15f))
            }

            HorizontalDivider(color = Slate800)

            // Filas scrolleables
            LazyColumn(modifier = Modifier.fillMaxSize()) {
                items(fares) { fare ->
                    FareRow(fare = fare)
                    HorizontalDivider(color = Slate800.copy(alpha = 0.5f))
                }
            }
        }
    }
}

@Composable
fun FareRow(fare: FareRecord) {
    val amountColor = when (fare.fareType) {
        FareType.STUDENT, FareType.CONADIS -> AmberPrimary
        FareType.ADULT -> EmeraldPrimary
        FareType.INSUFFICIENT -> RosePrimary
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(fare.timeFormatted, color = Slate400, fontSize = 11.sp, fontFamily = FontFamily.Monospace, modifier = Modifier.weight(0.2f))
        Text(fare.fareType.displayName, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(0.3f))
        Text(fare.paymentMethod.label, color = Slate200, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(0.35f))
        Text(
            text = fare.amountFormatted,
            color = amountColor,
            fontSize = 12.sp,
            fontWeight = FontWeight.Black,
            fontFamily = FontFamily.Monospace,
            textAlign = TextAlign.End,
            modifier = Modifier.weight(0.15f)
        )
    }
}

@Composable
fun VehicleSensorsAndActions(
    sensors: VehicleSensorsState,
    isMapPaused: Boolean,
    showSubmodule: Boolean,
    onToggleFault: () -> Unit,
    onRecordConadis: () -> Unit,
    onClickBreakdown: () -> Unit,
    onTogglePauseMap: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        // Barra de Sensores OBD-II
        Surface(
            color = Slate900,
            shape = RoundedCornerShape(12.dp),
            border = borderStroke(),
            modifier = Modifier.fillMaxWidth()
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(10.dp)
                            .clip(CircleShape)
                            .background(if (sensors.hasFault) RosePrimary else EmeraldPrimary)
                    )
                    Text(
                        text = "Sensores: ${sensors.faultDescription}",
                        color = if (sensors.hasFault) RoseLight else Slate200,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Medium
                    )
                }

                Button(
                    onClick = onToggleFault,
                    colors = ButtonDefaults.buttonColors(containerColor = Slate800),
                    shape = RoundedCornerShape(8.dp),
                    contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp)
                ) {
                    Text("Simular Alerta", color = AmberPrimary, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                }
            }
        }

        // Botones de Acción (CONADIS y Avería)
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Button(
                onClick = onRecordConadis,
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFD97706)),
                shape = RoundedCornerShape(14.dp),
                modifier = Modifier
                    .weight(1f)
                    .height(56.dp)
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("+1 CONADIS", fontWeight = FontWeight.Black, fontSize = 14.sp)
                    Text("Pase Libre S/. 0.00", fontSize = 10.sp, color = Color.White.copy(alpha = 0.9f))
                }
            }

            Button(
                onClick = onClickBreakdown,
                enabled = sensors.hasFault,
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (sensors.hasFault) RoseDark else Slate900,
                    disabledContainerColor = Slate900.copy(alpha = 0.5f)
                ),
                shape = RoundedCornerShape(14.dp),
                border = BorderStroke(1.dp, if (sensors.hasFault) RosePrimary else Slate800),
                modifier = Modifier
                    .weight(1f)
                    .height(56.dp)
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        text = "Avería de Unidad",
                        fontWeight = FontWeight.Black,
                        fontSize = 14.sp,
                        color = if (sensors.hasFault) Color.White else Slate400
                    )
                    Text(
                        text = if (sensors.hasFault) "¡Falla detectada!" else "Requiere alerta del auto",
                        fontSize = 10.sp,
                        color = if (sensors.hasFault) RoseLight else Slate400
                    )
                }
            }
        }

        // Submódulo de Avería desplegable
        if (showSubmodule) {
            Surface(
                color = RoseDark,
                shape = RoundedCornerShape(14.dp),
                border = BorderStroke(2.dp, RosePrimary),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        "INCIDENCIA VEHICULAR CONFIRMADA",
                        color = RoseLight,
                        fontWeight = FontWeight.Black,
                        fontSize = 11.sp
                    )
                    Text(
                        "Baja presión detectada en neumático delantero (18 PSI).",
                        color = Color.White,
                        fontSize = 11.sp
                    )
                    Button(
                        onClick = onTogglePauseMap,
                        colors = ButtonDefaults.buttonColors(containerColor = RosePrimary),
                        shape = RoundedCornerShape(10.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            text = if (isMapPaused) "Reanudar en Mapa Público" else "Pausar en Mapa Público",
                            fontWeight = FontWeight.Bold,
                            fontSize = 12.sp
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun BusOccupancyCard(
    occupancy: Int,
    maxCapacity: Int,
    percentage: Float,
    onAdjustOccupancy: (Int) -> Unit
) {
    Surface(
        color = Slate900,
        shape = RoundedCornerShape(20.dp),
        border = borderStroke(),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("AFORO DEL BUS", color = Slate400, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                Surface(
                    color = if (occupancy >= maxCapacity) RoseDark else EmeraldDark,
                    shape = CircleShape
                ) {
                    Text(
                        text = if (occupancy >= maxCapacity) "BUS COMPLETO" else "ASIENTOS DISPONIBLES",
                        color = if (occupancy >= maxCapacity) RoseLight else EmeraldLight,
                        fontWeight = FontWeight.Bold,
                        fontSize = 10.sp,
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 3.dp)
                    )
                }
            }

            Row(
                verticalAlignment = Alignment.Bottom,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    text = "$occupancy",
                    color = Color.White,
                    fontSize = 44.sp,
                    fontWeight = FontWeight.Black,
                    fontFamily = FontFamily.Monospace
                )
                Text(
                    text = "/ $maxCapacity",
                    color = Slate400,
                    fontSize = 20.sp,
                    modifier = Modifier.padding(bottom = 6.dp)
                )
            }

            // Barra de progreso de aforo
            LinearProgressIndicator(
                progress = { percentage },
                color = if (percentage > 0.85f) RosePrimary else EmeraldPrimary,
                trackColor = Slate800,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(10.dp)
                    .clip(RoundedCornerShape(5.dp))
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Button(
                    onClick = { onAdjustOccupancy(-1) },
                    colors = ButtonDefaults.buttonColors(containerColor = Slate800),
                    shape = RoundedCornerShape(10.dp),
                    modifier = Modifier.weight(1f)
                ) {
                    Text("-1 Pasajero", color = Slate200, fontWeight = FontWeight.Bold)
                }
                Button(
                    onClick = { onAdjustOccupancy(1) },
                    colors = ButtonDefaults.buttonColors(containerColor = Slate800),
                    shape = RoundedCornerShape(10.dp),
                    modifier = Modifier.weight(1f)
                ) {
                    Text("+1 Pasajero", color = Slate200, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

@Composable
fun ShiftLiquidationCard(
    state: DriverShiftState,
    modifier: Modifier = Modifier
) {
    Surface(
        color = Slate900,
        shape = RoundedCornerShape(20.dp),
        border = borderStroke(),
        modifier = modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(18.dp),
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("LIQUIDACIÓN DE TURNO", color = Slate400, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                HorizontalDivider(color = Slate800)

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text("Cobros App BC:", color = Slate400, fontSize = 13.sp)
                    Text("${state.appTrips} viajes", color = Color.White, fontWeight = FontWeight.Bold)
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text("Total CONADIS:", color = Slate400, fontSize = 13.sp)
                    Text("${state.conadisCount} personas", color = AmberPrimary, fontWeight = FontWeight.Bold)
                }

                HorizontalDivider(color = Slate800)

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("Total Recaudado:", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Text(
                        text = "S/. ${String.format(Locale.US, "%.2f", state.totalRevenuePen)}",
                        color = EmeraldPrimary,
                        fontSize = 22.sp,
                        fontWeight = FontWeight.Black,
                        fontFamily = FontFamily.Monospace
                    )
                }
            }

            Button(
                onClick = { /* Cierre de turno y liquidación */ },
                colors = ButtonDefaults.buttonColors(containerColor = BluePrimary),
                shape = RoundedCornerShape(12.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(48.dp)
            ) {
                Text("Cerrar Turno (Liquidación)", fontWeight = FontWeight.Bold, fontSize = 13.sp)
            }
        }
    }
}

@Composable
fun MiniTestButton(
    label: String,
    bgColor: Color,
    textColor: Color,
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        colors = ButtonDefaults.buttonColors(containerColor = bgColor),
        shape = RoundedCornerShape(6.dp),
        contentPadding = PaddingValues(horizontal = 6.dp, vertical = 2.dp)
    ) {
        Text(label, color = textColor, fontSize = 9.sp, fontWeight = FontWeight.Bold)
    }
}

fun borderStroke() = BorderStroke(1.dp, Slate800)

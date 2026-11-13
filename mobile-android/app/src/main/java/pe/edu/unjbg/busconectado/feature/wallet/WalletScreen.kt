package pe.edu.unjbg.busconectado.feature.wallet

import android.graphics.BitmapFactory
import android.util.Base64
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.platform.LocalContext
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import java.io.ByteArrayOutputStream
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
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material.icons.filled.AccessibleForward
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.HelpOutline
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.QrCode2
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import pe.edu.unjbg.busconectado.core.designsystem.BCColors
import pe.edu.unjbg.busconectado.core.model.LedgerTransactionItem
import pe.edu.unjbg.busconectado.core.model.LedgerTransactionKind
import pe.edu.unjbg.busconectado.core.model.UserRoleType
import pe.edu.unjbg.busconectado.feature.auth.AuthViewModel
import pe.edu.unjbg.busconectado.feature.auth.BCUiState
import java.util.Locale
import kotlin.math.max
import kotlin.math.roundToInt

private enum class LedgerFilter(val label: String) {
    ALL("Todos"),
    TRIPS("Viajes"),
    RECHARGES("Recargas")
}

private enum class PaymentMethodOption(
    val title: String,
    val shortTitle: String,
    val subtitle: String,
    val accent: Color
) {
    YAPE("Yape", "Yape", "Billetera BCP · Instantáneo sin comisión", BCColors.YapePurple),
    PLIN("Plin", "Plin", "Interbank, BBVA, Scotiabank · Instantáneo", BCColors.PlinTeal),
    CARD("Tarjeta Crédito/Débito", "Tarjeta", "Visa / Mastercard · Pasarela cifrada TLS", BCColors.RoyalBlue)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WalletScreen(
    state: BCUiState,
    viewModel: AuthViewModel,
    onOpenHelpFaq: () -> Unit,
    bottomContentPadding: PaddingValues = PaddingValues(bottom = 96.dp)
) {
    if (state.isGuestMode || state.currentUser == null) {
        WalletGuestGate(onGoToLogin = viewModel::leaveGuestForOnboarding)
        return
    }
    if (!state.currentUser.hasVerifiedPhone) {
        WalletPhoneRequiredGate(
            userName = state.currentUser.displayFullName,
            onLinkPhone = viewModel::openPhoneLinkingFromApp
        )
        return
    }

    val user = state.currentUser
    val coroutineScope = rememberCoroutineScope()

    var filter by remember { mutableStateOf(LedgerFilter.ALL) }
    var showRechargeSheet by remember { mutableStateOf(false) }
    var showCarnetSheet by remember { mutableStateOf(false) }
    var selectedDetailTx by remember { mutableStateOf<LedgerTransactionItem?>(null) }

    val totalRechargedPts = state.ledgerTransactions
        .filter { it.kind == LedgerTransactionKind.RECHARGE }
        .sumOf { it.amountPoints }
    val qrTripsCount = state.ledgerTransactions.count { it.kind == LedgerTransactionKind.QR_PAYMENT }

    val filteredTransactions = remember(state.ledgerTransactions, filter) {
        when (filter) {
            LedgerFilter.ALL -> state.ledgerTransactions
            LedgerFilter.TRIPS -> state.ledgerTransactions.filter { it.kind == LedgerTransactionKind.QR_PAYMENT }
            LedgerFilter.RECHARGES -> state.ledgerTransactions.filter { it.kind == LedgerTransactionKind.RECHARGE }
        }
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(BCColors.DarkBackground)
            .statusBarsPadding(),
        contentPadding = PaddingValues(
            start = 16.dp,
            end = 16.dp,
            top = 68.dp,
            bottom = bottomContentPadding.calculateBottomPadding()
        ),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Cabecera única y limpia (corrigiendo duplicación reportada previamente)
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        "Mi Monedero BC",
                        color = Color.White,
                        fontSize = 22.sp,
                        fontWeight = FontWeight.Black
                    )
                    Text(
                        "Saldo prepago y historial · Tacna",
                        color = BCColors.TextSecondary,
                        fontSize = 12.sp
                    )
                }
                Surface(
                    shape = RoundedCornerShape(50),
                    color = BCColors.Emerald.copy(alpha = 0.16f),
                    border = BorderStroke(1.dp, BCColors.Emerald.copy(alpha = 0.45f))
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(5.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(7.dp)
                                .clip(CircleShape)
                                .background(BCColors.Emerald)
                        )
                        Text(
                            when (user.roleType) {
                                UserRoleType.STUDENT -> "SUNEDU Verificado"
                                UserRoleType.CONADIS -> "CONADIS Activo"
                                else -> "Cuenta Activa"
                            },
                            color = BCColors.Emerald,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        }

        // Tarjeta Principal de Saldo
        item {
            Surface(
                shape = RoundedCornerShape(22.dp),
                color = Color.Transparent,
                modifier = Modifier
                    .fillMaxWidth()
                    .background(
                        Brush.linearGradient(listOf(Color(0xFF1D4ED8), Color(0xFF0F3285))),
                        RoundedCornerShape(22.dp)
                    )
            ) {
                Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            "Saldo Prepago Bus Conectado",
                            color = Color.White.copy(alpha = 0.85f),
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Medium
                        )
                        Surface(shape = RoundedCornerShape(50), color = Color.White.copy(alpha = 0.16f)) {
                            Text(
                                "1 PEN = 10 Pts",
                                color = Color.White,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier.padding(horizontal = 9.dp, vertical = 4.dp)
                            )
                        }
                    }

                    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(
                            "${user.pointsBalance}",
                            color = Color.White,
                            fontSize = 40.sp,
                            fontWeight = FontWeight.Black
                        )
                        Text(
                            "PUNTOS BC",
                            color = Color.White.copy(alpha = 0.8f),
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.padding(bottom = 8.dp)
                        )
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            String.format(Locale.US, "Equivalente: S/. %.2f", user.pointsBalance / 10.0),
                            color = Color.White.copy(alpha = 0.82f),
                            fontSize = 13.sp
                        )
                        Button(
                            onClick = { showRechargeSheet = true },
                            shape = RoundedCornerShape(50),
                            colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = Color(0xFF1D4ED8))
                        ) {
                            Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(4.dp))
                            Text("Recargar", fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }
        }

        // Beneficio / Caducidad de Carné o Solicitud de Revisión
        item {
            BenefitAndCarnetCard(
                state = state,
                onOpenCarnetRequest = { showCarnetSheet = true }
            )
        }

        // Accesos rápidos: Pasarela de pagos + Ayuda
        item {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedButton(
                    onClick = { showRechargeSheet = true },
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(14.dp),
                    border = BorderStroke(1.dp, BCColors.HairlineBorder)
                ) {
                    Icon(Icons.Default.CreditCard, contentDescription = null, tint = BCColors.CyanAccent, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Pasarela de Pagos", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                }
                OutlinedButton(
                    onClick = onOpenHelpFaq,
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(14.dp),
                    border = BorderStroke(1.dp, BCColors.HairlineBorder)
                ) {
                    Icon(Icons.Default.HelpOutline, contentDescription = null, tint = BCColors.Amber, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Ayuda y Tarifas", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }

        // Historial de Movimientos
        item {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Icons.Default.History, contentDescription = null, tint = BCColors.TextSecondary, modifier = Modifier.size(16.dp))
                        Text("HISTORIAL DE MOVIMIENTOS", color = BCColors.TextSecondary, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                    }
                    Text("${filteredTransactions.size}", color = BCColors.TextMuted, fontSize = 11.sp)
                }

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    LedgerFilter.entries.forEach { f ->
                        FilterChip(
                            selected = filter == f,
                            onClick = { filter = f },
                            label = { Text(f.label, fontSize = 12.sp) },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = BCColors.RoyalBlue,
                                selectedLabelColor = Color.White,
                                containerColor = BCColors.ControlSurface,
                                labelColor = BCColors.TextSecondary
                            )
                        )
                    }
                }
            }
        }

        if (filteredTransactions.isEmpty()) {
            item {
                Surface(
                    shape = RoundedCornerShape(18.dp),
                    color = BCColors.CardSurface,
                    border = BorderStroke(1.dp, BCColors.HairlineBorder),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(
                        modifier = Modifier.padding(28.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(Icons.Default.Inbox, contentDescription = null, tint = BCColors.TextMuted, modifier = Modifier.size(34.dp))
                        Text("Sin movimientos registrados", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                        Text(
                            "Tus recargas con Yape, Plin o Tarjeta y tus viajes validados con QR aparecerán aquí.",
                            color = BCColors.TextMuted,
                            fontSize = 12.sp,
                            textAlign = TextAlign.Center
                        )
                    }
                }
            }
        } else {
            items(filteredTransactions, key = { it.id }) { tx ->
                TransactionRowItem(tx = tx, onClick = { selectedDetailTx = tx })
            }
        }
    }

    // Sheet de Pasarela de Pagos en 3 Pasos
    if (showRechargeSheet) {
        PaymentGatewayBottomSheet(
            currentBalance = user.pointsBalance,
            onDismiss = { showRechargeSheet = false },
            onConfirmPayment = { points, method, ref ->
                viewModel.rechargePoints(points = points, gateway = method.title, reference = ref)
            }
        )
    }

    // Sheet de Solicitud de Revisión de Carné
    if (showCarnetSheet) {
        CarnetReviewBottomSheet(
            onDismiss = { showCarnetSheet = false },
            onSubmit = { type, dni, inst, doc, exp ->
                viewModel.submitCarnetReviewRequest(type, dni, inst, doc, exp)
                showCarnetSheet = false
            },
            onSubmitSunedu = { dni, inst, doc, exp, qr, photo ->
                viewModel.submitCarnetReviewRequest("STUDENT", dni, inst, doc, exp, qr, photo)
                showCarnetSheet = false
            }
        )
    }

    // Sheet de Detalle de Movimiento
    selectedDetailTx?.let { tx ->
        ModalBottomSheet(
            onDismissRequest = { selectedDetailTx = null },
            containerColor = BCColors.ElevatedSurface
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .padding(bottom = 28.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text("Detalle de Movimiento", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Black)
                Text(tx.title, color = BCColors.CyanAccent, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                Text(
                    tx.formattedPoints,
                    color = if (tx.isPositive) BCColors.Emerald else BCColors.DestructiveRed,
                    fontSize = 26.sp,
                    fontWeight = FontWeight.Black
                )
                Surface(
                    shape = RoundedCornerShape(16.dp),
                    color = BCColors.CardSurface,
                    border = BorderStroke(1.dp, BCColors.HairlineBorder)
                ) {
                    Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        ReceiptLine("Fecha / Hora", tx.timestampLabel)
                        ReceiptLine("Descripción", tx.subtitle)
                        ReceiptLine("Equivalente", String.format(Locale.US, "S/. %.2f", tx.amountPen))
                        tx.plateBadge?.let { ReceiptLine("Unidad / Placa", it) }
                        ReceiptLine("Saldo anterior", "${tx.balanceBefore} pts")
                        ReceiptLine("Saldo resultante", "${tx.balanceAfter} pts")
                    }
                }
            }
        }
    }
}

@Composable
private fun WalletMetricCard(
    modifier: Modifier,
    title: String,
    value: String,
    accent: Color
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(16.dp),
        color = BCColors.CardSurface,
        border = BorderStroke(1.dp, BCColors.HairlineBorder)
    ) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, color = BCColors.TextMuted, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
            Text(value, color = accent, fontSize = 16.sp, fontWeight = FontWeight.Black)
        }
    }
}

@Composable
private fun BenefitAndCarnetCard(
    state: BCUiState,
    onOpenCarnetRequest: () -> Unit
) {
    val user = state.currentUser ?: return
    val pendingRequest = state.carnetReviewRequests.firstOrNull()

    when {
        user.roleType == UserRoleType.STUDENT -> {
            val sv = user.studentVerification
            Surface(
                shape = RoundedCornerShape(18.dp),
                color = Color(0xFF2C1E0A),
                border = BorderStroke(1.dp, BCColors.Amber.copy(alpha = 0.45f))
            ) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Box(
                            modifier = Modifier
                                .size(40.dp)
                                .clip(CircleShape)
                                .background(BCColors.Amber.copy(alpha = 0.2f)),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(Icons.Default.School, contentDescription = null, tint = BCColors.Amber)
                        }
                        Column(modifier = Modifier.weight(1f)) {
                            Text("Carné Universitario Vigente", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                            Text(sv?.university ?: "Universitario SUNEDU", color = BCColors.TextSecondary, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        Surface(shape = RoundedCornerShape(50), color = BCColors.Amber.copy(alpha = 0.2f)) {
                            Text(
                                "Tarifa 7 pts",
                                color = BCColors.Amber,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp)
                            )
                        }
                    }
                    HorizontalDivider(color = Color.White.copy(alpha = 0.1f))
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Default.Schedule, contentDescription = null, tint = BCColors.Amber, modifier = Modifier.size(16.dp))
                        Text(
                            sv?.expirationSummaryText ?: "Válido hasta 31/12/2026",
                            color = Color.White.copy(alpha = 0.9f),
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
            }
        }
        user.roleType == UserRoleType.CONADIS -> {
            Surface(
                shape = RoundedCornerShape(18.dp),
                color = Color(0xFF0C2630),
                border = BorderStroke(1.dp, BCColors.CyanAccent.copy(alpha = 0.45f))
            ) {
                Row(
                    modifier = Modifier.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(40.dp)
                            .clip(CircleShape)
                            .background(BCColors.CyanAccent.copy(alpha = 0.18f)),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(Icons.Default.AccessibleForward, contentDescription = null, tint = BCColors.CyanAccent)
                    }
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Pase Libre CONADIS Activo", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                        Text("Beneficio exonerado · Ley N° 30412", color = BCColors.TextSecondary, fontSize = 11.sp)
                    }
                    Surface(shape = RoundedCornerShape(50), color = BCColors.CyanAccent.copy(alpha = 0.2f)) {
                        Text(
                            "0 pts",
                            color = BCColors.CyanAccent,
                            fontWeight = FontWeight.Black,
                            fontSize = 12.sp,
                            modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp)
                        )
                    }
                }
            }
        }
        else -> {
            Surface(
                shape = RoundedCornerShape(18.dp),
                color = BCColors.CardSurface,
                border = BorderStroke(1.dp, BCColors.HairlineBorder)
            ) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Icon(Icons.Default.Person, contentDescription = null, tint = BCColors.RoyalBlue)
                        Column(modifier = Modifier.weight(1f)) {
                            Text("Tarifa Estándar Adulto", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                            Text("15 puntos (S/. 1.50) por validación QR", color = BCColors.TextSecondary, fontSize = 11.sp)
                        }
                    }

                    if (pendingRequest != null) {
                        Surface(
                            shape = RoundedCornerShape(12.dp),
                            color = BCColors.Amber.copy(alpha = 0.14f),
                            border = BorderStroke(1.dp, BCColors.Amber.copy(alpha = 0.45f))
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Column {
                                    Text("Solicitud ${pendingRequest.requestedType} · ${pendingRequest.status}", color = BCColors.Amber, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                    Text("Doc: ${pendingRequest.documentCode} · Caduca ${pendingRequest.expiresAt}", color = BCColors.TextSecondary, fontSize = 11.sp)
                                }
                            }
                        }
                    } else {
                        Button(
                            onClick = onOpenCarnetRequest,
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(12.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = BCColors.Amber, contentColor = Color.Black)
                        ) {
                            Icon(Icons.Default.VerifiedUser, contentDescription = null, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(6.dp))
                            Text("Solicitar Revisión de Carné (7 pts / 0 pts)", fontWeight = FontWeight.Bold, fontSize = 12.sp)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TransactionRowItem(
    tx: LedgerTransactionItem,
    onClick: () -> Unit
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(16.dp),
        color = BCColors.CardSurface,
        border = BorderStroke(1.dp, BCColors.HairlineBorder)
    ) {
        Row(
            modifier = Modifier.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(42.dp)
                    .clip(CircleShape)
                    .background(if (tx.isPositive) BCColors.Emerald.copy(alpha = 0.16f) else BCColors.RoyalBlue.copy(alpha = 0.18f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = if (tx.isPositive) Icons.Default.ArrowDownward else Icons.Default.QrCode2,
                    contentDescription = null,
                    tint = if (tx.isPositive) BCColors.Emerald else BCColors.RoyalBlue
                )
            }

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(tx.title, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    tx.plateBadge?.let { plate ->
                        Surface(shape = RoundedCornerShape(50), color = Color.White.copy(alpha = 0.12f)) {
                            Text(plate, color = Color.White, fontSize = 9.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp))
                        }
                    }
                }
                Text(tx.subtitle, color = BCColors.TextSecondary, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text("${tx.timestampLabel} · Saldo: ${tx.balanceAfter} pts", color = BCColors.TextMuted, fontSize = 10.sp)
            }

            Column(horizontalAlignment = Alignment.End) {
                Text(
                    tx.formattedPoints,
                    color = if (tx.isPositive) BCColors.Emerald else Color(0xFFF87171),
                    fontWeight = FontWeight.Bold,
                    fontSize = 14.sp
                )
                Text(
                    String.format(Locale.US, "S/. %.2f", tx.amountPen),
                    color = BCColors.TextMuted,
                    fontSize = 11.sp
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PaymentGatewayBottomSheet(
    currentBalance: Int,
    onDismiss: () -> Unit,
    onConfirmPayment: suspend (points: Int, method: PaymentMethodOption, reference: String?) -> LedgerTransactionItem?
) {
    val scope = rememberCoroutineScope()
    var step by remember { mutableIntStateOf(0) }
    var selectedPkgPoints by remember { mutableIntStateOf(50) }
    var customPenText by remember { mutableStateOf("") }
    var method by remember { mutableStateOf(PaymentMethodOption.YAPE) }
    var operationRef by remember { mutableStateOf("") }
    var cardNumber by remember { mutableStateOf("") }
    var cardExpiry by remember { mutableStateOf("") }
    var cardCvv by remember { mutableStateOf("") }
    var processing by remember { mutableStateOf(false) }
    var completedTx by remember { mutableStateOf<LedgerTransactionItem?>(null) }

    val parsedCustomPen = customPenText.replace(",", ".").toDoubleOrNull()
    val effectivePoints = if (parsedCustomPen != null && parsedCustomPen >= 1.0) {
        max(10, (parsedCustomPen * 10.0).roundToInt())
    } else {
        selectedPkgPoints
    }
    val effectivePen = effectivePoints / 10.0

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = BCColors.ElevatedSurface
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text(
                    when (step) {
                        0 -> "Recargar Monedero BC"
                        1 -> "Confirmar Pago · ${method.shortTitle}"
                        else -> "Comprobante de Recarga"
                    },
                    color = Color.White,
                    fontWeight = FontWeight.Black,
                    fontSize = 18.sp
                )
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Default.Close, contentDescription = "Cerrar", tint = Color.White)
                }
            }

            if (step == 0) {
                Text("SELECCIONA MONTO (1 PEN = 10 PTS)", color = BCColors.TextMuted, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(20 to "S/. 2.00", 50 to "S/. 5.00", 100 to "S/. 10.00").forEach { (pts, label) ->
                        val active = customPenText.isBlank() && selectedPkgPoints == pts
                        Surface(
                            modifier = Modifier
                                .weight(1f)
                                .clickable {
                                    customPenText = ""
                                    selectedPkgPoints = pts
                                },
                            shape = RoundedCornerShape(14.dp),
                            color = if (active) BCColors.RoyalBlue.copy(alpha = 0.2f) else BCColors.CardSurface,
                            border = BorderStroke(if (active) 2.dp else 1.dp, if (active) BCColors.RoyalBlue else BCColors.HairlineBorder)
                        ) {
                            Column(modifier = Modifier.padding(12.dp)) {
                                Text("+$pts pts", color = Color.White, fontWeight = FontWeight.Black, fontSize = 15.sp)
                                Text(label, color = if (active) BCColors.Emerald else BCColors.TextSecondary, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                }

                OutlinedTextField(
                    value = customPenText,
                    onValueChange = { customPenText = it },
                    label = { Text("Otro monto en Soles (mín. S/. 1.00)") },
                    suffix = { Text("= $effectivePoints pts", color = BCColors.Emerald, fontWeight = FontWeight.Bold) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    singleLine = true,
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = BCColors.RoyalBlue,
                        unfocusedBorderColor = BCColors.HairlineBorder,
                        focusedTextColor = Color.White,
                        unfocusedTextColor = Color.White
                    ),
                    modifier = Modifier.fillMaxWidth()
                )

                Text("MÉTODO DE PAGO", color = BCColors.TextMuted, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                PaymentMethodOption.entries.forEach { option ->
                    val selected = method == option
                    Surface(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { method = option },
                        shape = RoundedCornerShape(14.dp),
                        color = if (selected) BCColors.RoyalBlue.copy(alpha = 0.14f) else BCColors.CardSurface,
                        border = BorderStroke(1.2.dp, if (selected) BCColors.RoyalBlue else BCColors.HairlineBorder)
                    ) {
                        Row(
                            modifier = Modifier.padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(38.dp)
                                    .clip(RoundedCornerShape(10.dp))
                                    .background(option.accent.copy(alpha = 0.2f)),
                                contentAlignment = Alignment.Center
                            ) {
                                Icon(
                                    imageVector = if (option == PaymentMethodOption.CARD) Icons.Default.CreditCard else Icons.Default.PhoneAndroid,
                                    contentDescription = null,
                                    tint = option.accent
                                )
                            }
                            Column(modifier = Modifier.weight(1f)) {
                                Text(option.title, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                                Text(option.subtitle, color = BCColors.TextSecondary, fontSize = 11.sp)
                            }
                            if (selected) {
                                Icon(Icons.Default.CheckCircle, contentDescription = null, tint = BCColors.RoyalBlue)
                            }
                        }
                    }
                }

                Button(
                    onClick = { step = 1 },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(52.dp),
                    shape = RoundedCornerShape(14.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = BCColors.RoyalBlue)
                ) {
                    Text(String.format(Locale.US, "Continuar · S/. %.2f (%d pts)", effectivePen, effectivePoints), fontWeight = FontWeight.Bold)
                    Spacer(Modifier.width(8.dp))
                    Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null)
                }
            } else if (step == 1) {
                Surface(shape = RoundedCornerShape(16.dp), color = BCColors.CardSurface, border = BorderStroke(1.dp, BCColors.HairlineBorder)) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column {
                            Text("TOTAL A PAGAR", color = BCColors.TextMuted, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                            Text(String.format(Locale.US, "S/. %.2f", effectivePen), color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Black)
                        }
                        Column(horizontalAlignment = Alignment.End) {
                            Text(method.title, color = method.accent, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                            Text("+$effectivePoints Puntos BC", color = BCColors.Emerald, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                        }
                    }
                }

                if (method == PaymentMethodOption.CARD) {
                    OutlinedTextField(
                        value = cardNumber,
                        onValueChange = { cardNumber = it.take(19) },
                        label = { Text("Número de tarjeta (4557 •••• •••• ••••)") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        modifier = Modifier.fillMaxWidth()
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        OutlinedTextField(
                            value = cardExpiry,
                            onValueChange = { cardExpiry = it.take(5) },
                            label = { Text("MM/AA") },
                            modifier = Modifier.weight(1f)
                        )
                        OutlinedTextField(
                            value = cardCvv,
                            onValueChange = { cardCvv = it.take(4) },
                            label = { Text("CVV") },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                            modifier = Modifier.weight(1f)
                        )
                    }
                } else {
                    Surface(shape = RoundedCornerShape(14.dp), color = BCColors.CardSurface) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            Icon(Icons.Default.QrCode2, contentDescription = null, tint = Color.White, modifier = Modifier.size(44.dp))
                            Column {
                                Text("Yapea / Plinea al 987 654 321", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                                Text("Bus Conectado Tacna SAC", color = method.accent, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                            }
                        }
                    }
                    OutlinedTextField(
                        value = operationRef,
                        onValueChange = { operationRef = it },
                        label = { Text("Código de aprobación (opcional en demo)") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        modifier = Modifier.fillMaxWidth()
                    )
                }

                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(Icons.Default.Lock, contentDescription = null, tint = BCColors.Emerald, modifier = Modifier.size(14.dp))
                    Text("Transacción cifrada TLS · Recarga instantánea", color = BCColors.TextSecondary, fontSize = 11.sp)
                }

                Button(
                    onClick = {
                        processing = true
                        scope.launch {
                            delay(550L)
                            completedTx = onConfirmPayment(effectivePoints, method, operationRef.takeIf { it.isNotBlank() })
                            processing = false
                            step = 2
                        }
                    },
                    enabled = !processing,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(52.dp),
                    shape = RoundedCornerShape(14.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = BCColors.Emerald, contentColor = Color.Black)
                ) {
                    if (processing) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp), color = Color.Black)
                        Spacer(Modifier.width(8.dp))
                        Text("Procesando pago...", fontWeight = FontWeight.Bold)
                    } else {
                        Text(String.format(Locale.US, "Confirmar y Pagar S/. %.2f", effectivePen), fontWeight = FontWeight.Bold)
                    }
                }
            } else {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Icon(Icons.Default.CheckCircle, contentDescription = null, tint = BCColors.Emerald, modifier = Modifier.size(60.dp))
                    Text("¡Recarga Exitosa!", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Black)
                    Text(
                        "Se acreditaron +${completedTx?.amountPoints ?: effectivePoints} Puntos BC.",
                        color = BCColors.TextSecondary,
                        fontSize = 13.sp
                    )
                    Surface(shape = RoundedCornerShape(16.dp), color = BCColors.CardSurface) {
                        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            ReceiptLine("Método", method.title)
                            ReceiptLine("Importe", String.format(Locale.US, "S/. %.2f", completedTx?.amountPen ?: effectivePen))
                            ReceiptLine("Nuevo saldo", "${completedTx?.balanceAfter ?: (currentBalance + effectivePoints)} pts")
                        }
                    }
                    Button(
                        onClick = onDismiss,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(50.dp),
                        shape = RoundedCornerShape(14.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = BCColors.RoyalBlue)
                    ) {
                        Text("Listo", fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CarnetReviewBottomSheet(
    onDismiss: () -> Unit,
    onSubmit: (type: String, dni: String, institution: String, code: String, expiresAt: String) -> Unit,
    onSubmitSunedu: ((dni: String, institution: String, code: String, expiresAt: String, qrPayload: String, photoBase64: String) -> Unit)? = null
) {
    val context = LocalContext.current
    var dni by remember { mutableStateOf("") }
    var institution by remember { mutableStateOf("UNJBG Tacna") }
    var code by remember { mutableStateOf("") }
    var expiresAt by remember { mutableStateOf("2026-12-31") }
    var detectedQrPayload by remember { mutableStateOf<String?>(null) }
    var photoBase64 by remember { mutableStateOf("") }
    var qrStatusText by remember { mutableStateOf("Sube la foto frontal de tu carnet universitario (con el código QR visible).") }
    var isScanningPhoto by remember { mutableStateOf(false) }

    val photoPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        isScanningPhoto = true
        qrStatusText = "Identificando QR SUNEDU en la foto..."
        runCatching {
            val stream = context.contentResolver.openInputStream(uri)
            val bmp = BitmapFactory.decodeStream(stream)
            stream?.close()
            if (bmp != null) {
                val out = ByteArrayOutputStream()
                val scaled = android.graphics.Bitmap.createScaledBitmap(bmp, 480, (480 * bmp.height / bmp.width.coerceAtLeast(1)).coerceAtLeast(1), true)
                scaled.compress(android.graphics.Bitmap.CompressFormat.JPEG, 75, out)
                photoBase64 = Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)

                val image = InputImage.fromBitmap(bmp, 0)
                BarcodeScanning.getClient().process(image)
                    .addOnSuccessListener { barcodes ->
                        isScanningPhoto = false
                        val rawQr = barcodes.firstOrNull { !it.rawValue.isNullOrBlank() }?.rawValue
                        if (!rawQr.isNullOrBlank()) {
                            detectedQrPayload = rawQr
                            Regex("\\b(\\d{8})\\b").find(rawQr)?.groupValues?.getOrNull(1)?.let { foundDni ->
                                if (dni.isBlank()) dni = foundDni
                            }
                            Regex("(20\\d{2}[-/]\\d{2}[-/]\\d{2})").find(rawQr)?.groupValues?.getOrNull(1)?.let { foundExp ->
                                expiresAt = foundExp.replace("/", "-")
                            }
                            qrStatusText = "✓ QR SUNEDU identificado correctamente. Información lista para enviar al Panel Admin."
                        } else {
                            detectedQrPayload = null
                            qrStatusText = "✕ No se pudo identificar el QR en la foto. Toma una foto frontal más nítida del carnet."
                        }
                    }
                    .addOnFailureListener {
                        isScanningPhoto = false
                        detectedQrPayload = null
                        qrStatusText = "✕ Error analizando la imagen del carnet."
                    }
            } else {
                isScanningPhoto = false
                qrStatusText = "✕ No se pudo leer la imagen seleccionada."
            }
        }.onFailure {
            isScanningPhoto = false
            qrStatusText = "✕ Error cargando la foto."
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = BCColors.ElevatedSurface) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text("Verificación Carnet Universitario SUNEDU", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Black)
            Text("Sube la foto frontal de tu carnet universitario. Validaremos el QR y tu DNI para que el administrador confirme tu tarifa de S/. 0.70.", color = BCColors.TextSecondary, fontSize = 12.sp)

            Button(
                onClick = { photoPickerLauncher.launch("image/*") },
                modifier = Modifier.fillMaxWidth().height(46.dp),
                shape = RoundedCornerShape(12.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF2563EB))
            ) {
                Icon(Icons.Default.QrCode2, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text(if (isScanningPhoto) "Escaneando QR..." else "Subir Foto Frontal del Carnet (QR)", fontWeight = FontWeight.Bold)
            }

            Text(
                qrStatusText,
                color = if (detectedQrPayload != null) BCColors.Emerald else BCColors.Amber,
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold
            )

            OutlinedTextField(
                value = dni,
                onValueChange = { dni = it.filter { c -> c.isDigit() }.take(8) },
                label = { Text("DNI (8 dígitos)") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.fillMaxWidth()
            )
            OutlinedTextField(
                value = institution,
                onValueChange = { institution = it },
                label = { Text("Universidad (Perú)") },
                modifier = Modifier.fillMaxWidth()
            )
            OutlinedTextField(
                value = expiresAt,
                onValueChange = { expiresAt = it },
                label = { Text("Fecha de caducidad del carnet (AAAA-MM-DD)") },
                modifier = Modifier.fillMaxWidth()
            )

            Button(
                enabled = detectedQrPayload != null && dni.length == 8 && !isScanningPhoto,
                onClick = {
                    val qr = detectedQrPayload ?: return@Button
                    val finalCode = code.ifBlank { "SUNEDU-$dni" }
                    if (onSubmitSunedu != null) {
                        onSubmitSunedu(dni, institution, finalCode, expiresAt, qr, photoBase64)
                    } else {
                        onSubmit("STUDENT", dni, institution, finalCode, expiresAt)
                    }
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(50.dp),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(containerColor = BCColors.Amber, contentColor = Color.Black)
            ) {
                Icon(Icons.Default.Send, contentDescription = null, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(8.dp))
                Text("Validar y Enviar a Confirmación Admin", fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
private fun ReceiptLine(label: String, value: String) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, color = BCColors.TextSecondary, fontSize = 12.sp)
        Text(value, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 12.sp)
    }
}

@Composable
private fun WalletGuestGate(onGoToLogin: () -> Unit) {
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
            Icon(Icons.Default.AccountBalanceWallet, contentDescription = null, tint = BCColors.RoyalBlue, modifier = Modifier.size(38.dp))
        }
        Spacer(Modifier.height(16.dp))
        Text("Monedero BC requiere cuenta", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(8.dp))
        Text(
            "Regístrate o inicia sesión para recargar puntos con Yape/Plin, validar tu carné y revisar tu historial.",
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
            colors = ButtonDefaults.buttonColors(containerColor = BCColors.Emerald, contentColor = Color.Black)
        ) {
            Text("Crear Cuenta o Iniciar Sesión", fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun WalletPhoneRequiredGate(userName: String, onLinkPhone: () -> Unit) {
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
            Icon(Icons.Default.AccountBalanceWallet, contentDescription = null, tint = BCColors.Emerald, modifier = Modifier.size(38.dp))
        }
        Spacer(Modifier.height(14.dp))
        Text(userName, color = BCColors.CyanAccent, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(6.dp))
        Text(
            "Accede con tu número celular para usar tu Monedero",
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
            colors = ButtonDefaults.buttonColors(containerColor = BCColors.Emerald, contentColor = Color.Black)
        ) {
            Text("Vincular número celular", fontWeight = FontWeight.Bold)
        }
    }
}


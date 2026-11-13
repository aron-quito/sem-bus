package pe.edu.unjbg.busconectado.feature.profile

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ExitToApp
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.HelpOutline
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import pe.edu.unjbg.busconectado.core.designsystem.BCColors
import pe.edu.unjbg.busconectado.core.model.MainAppTab
import pe.edu.unjbg.busconectado.core.model.UserRoleType
import pe.edu.unjbg.busconectado.feature.auth.AuthViewModel
import pe.edu.unjbg.busconectado.feature.auth.BCUiState
import pe.edu.unjbg.busconectado.feature.wallet.CarnetReviewBottomSheet
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileSheet(
    state: BCUiState,
    viewModel: AuthViewModel,
    onDismiss: () -> Unit
) {
    val user = state.currentUser
    var showDevSettings by remember { mutableStateOf(false) }
    var hostInput by remember(state.backendHost) { mutableStateOf(state.backendHost) }
    var showCarnetModal by remember { mutableStateOf(false) }
    var showFaqModal by remember { mutableStateOf(false) }
    var showDeleteConfirm by remember { mutableStateOf(false) }

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
                Text("Mi Perfil BC", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Black)
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Default.Close, contentDescription = "Cerrar", tint = Color.White)
                }
            }

            if (user == null || state.isGuestMode) {
                Surface(shape = RoundedCornerShape(16.dp), color = BCColors.CardSurface) {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("Modo Invitado", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                        Text("Inicia sesión para gestionar tu carné, recargar Puntos BC y pagar con QR.", color = BCColors.TextSecondary, fontSize = 12.sp)
                        Button(
                            onClick = {
                                onDismiss()
                                viewModel.leaveGuestForOnboarding()
                            },
                            modifier = Modifier.fillMaxWidth(),
                            colors = ButtonDefaults.buttonColors(containerColor = BCColors.RoyalBlue)
                        ) {
                            Text("Iniciar Sesión o Crear Cuenta")
                        }
                    }
                }
                return@Column
            }

            // Tarjeta de usuario
            Surface(
                shape = RoundedCornerShape(18.dp),
                color = BCColors.CardSurface,
                border = BorderStroke(1.dp, BCColors.HairlineBorder)
            ) {
                Row(
                    modifier = Modifier.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(54.dp)
                            .clip(CircleShape)
                            .background(BCColors.RoyalBlue),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(user.initials, color = Color.White, fontWeight = FontWeight.Black, fontSize = 18.sp)
                    }
                    Column(modifier = Modifier.weight(1f)) {
                        Text(user.displayName, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                        Text(user.phone, color = BCColors.TextSecondary, fontSize = 12.sp)
                        Spacer(Modifier.height(4.dp))
                        Text(user.roleType.badgeLabel, color = BCColors.CyanAccent, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
            }

            // Estado de Carné y Solicitud de Revisión
            Surface(
                shape = RoundedCornerShape(16.dp),
                color = BCColors.CardSurface,
                border = BorderStroke(1.dp, BCColors.HairlineBorder)
            ) {
                Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("CARNÉ Y BENEFICIOS", color = BCColors.TextMuted, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                    if (user.roleType == UserRoleType.STUDENT) {
                        Text("Carné Universitario SUNEDU Verificado", color = BCColors.Amber, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                        Text(
                            user.studentVerification?.expirationSummaryText ?: "Vigencia 31/12/2026",
                            color = Color.White,
                            fontSize = 12.sp
                        )
                    } else if (user.roleType == UserRoleType.CONADIS) {
                        Text("Pase Libre CONADIS Activo (0 pts)", color = BCColors.CyanAccent, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                    } else {
                        Text("Sin carné preferencial registrado.", color = BCColors.TextSecondary, fontSize = 12.sp)
                        Button(
                            onClick = { showCarnetModal = true },
                            modifier = Modifier.fillMaxWidth(),
                            colors = ButtonDefaults.buttonColors(containerColor = BCColors.Amber, contentColor = Color.Black),
                            shape = RoundedCornerShape(12.dp)
                        ) {
                            Icon(Icons.Default.VerifiedUser, contentDescription = null, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(6.dp))
                            Text("Solicitar Revisión de Carné", fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }

            // Acceso directo a Monedero
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        onDismiss()
                        viewModel.selectTab(MainAppTab.WALLET)
                    },
                shape = RoundedCornerShape(16.dp),
                color = BCColors.CardSurface,
                border = BorderStroke(1.dp, BCColors.HairlineBorder)
            ) {
                Row(
                    modifier = Modifier.padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Icon(Icons.Default.AccountBalanceWallet, contentDescription = null, tint = BCColors.Emerald)
                        Column {
                            Text("Mi Monedero BC", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                            Text(
                                String.format(Locale.US, "%d pts (S/. %.2f)", user.pointsBalance, user.pointsBalance / 10.0),
                                color = BCColors.Emerald,
                                fontSize = 12.sp
                            )
                        }
                    }
                    Text("Abrir →", color = BCColors.CyanAccent, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                }
            }

            // Centro de Ayuda / FAQ
            OutlinedButton(
                onClick = { showFaqModal = true },
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp),
                border = BorderStroke(1.dp, BCColors.HairlineBorder)
            ) {
                Icon(Icons.Default.HelpOutline, contentDescription = null, tint = BCColors.CyanAccent)
                Spacer(Modifier.width(8.dp))
                Text("Centro de Ayuda y Preguntas Frecuentes", color = Color.White)
            }

            // Ajustes Avanzados de Servidor (para desarrollo/entorno cloud)
            Surface(
                shape = RoundedCornerShape(14.dp),
                color = BCColors.CardSurface,
                border = BorderStroke(1.dp, BCColors.HairlineBorder)
            ) {
                Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { showDevSettings = !showDevSettings },
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Icon(Icons.Default.Settings, contentDescription = null, tint = BCColors.TextSecondary, modifier = Modifier.size(16.dp))
                            Text("Ajustes Avanzados de Backend", color = BCColors.TextSecondary, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                        }
                        Icon(if (showDevSettings) Icons.Default.ExpandLess else Icons.Default.ExpandMore, contentDescription = null, tint = BCColors.TextSecondary)
                    }

                    if (showDevSettings) {
                        OutlinedTextField(
                            value = hostInput,
                            onValueChange = { hostInput = it },
                            label = { Text("Host Backend (IP o dominio)") },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth()
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(
                                onClick = { viewModel.updateBackendHost(hostInput) },
                                modifier = Modifier.weight(1f),
                                colors = ButtonDefaults.buttonColors(containerColor = BCColors.RoyalBlue)
                            ) {
                                Text("Guardar y Sincronizar", fontSize = 11.sp)
                            }
                            OutlinedButton(
                                onClick = { viewModel.resetCurrentAccountState() },
                                modifier = Modifier.weight(1f),
                                border = BorderStroke(1.dp, BCColors.Amber)
                            ) {
                                Icon(Icons.Default.Refresh, contentDescription = null, tint = BCColors.Amber, modifier = Modifier.size(14.dp))
                                Spacer(Modifier.width(4.dp))
                                Text("Reset 0 pts", color = BCColors.Amber, fontSize = 11.sp)
                            }
                        }
                    }
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedButton(
                    onClick = {
                        onDismiss()
                        viewModel.logout()
                    },
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(14.dp),
                    border = BorderStroke(1.dp, BCColors.HairlineBorder)
                ) {
                    Icon(Icons.AutoMirrored.Filled.ExitToApp, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Cerrar Sesión", color = Color.White, fontSize = 13.sp)
                }
                OutlinedButton(
                    onClick = { showDeleteConfirm = true },
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(14.dp),
                    border = BorderStroke(1.dp, BCColors.DestructiveRed.copy(alpha = 0.6f))
                ) {
                    Icon(Icons.Default.DeleteForever, contentDescription = null, tint = BCColors.DestructiveRed, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Eliminar Cuenta", color = BCColors.DestructiveRed, fontSize = 12.sp)
                }
            }
        }
    }

    if (showCarnetModal) {
        CarnetReviewBottomSheet(
            onDismiss = { showCarnetModal = false },
            onSubmit = { type, dni, inst, doc, exp ->
                viewModel.submitCarnetReviewRequest(type, dni, inst, doc, exp)
                showCarnetModal = false
            },
            onSubmitSunedu = { dni, inst, doc, exp, qr, photo ->
                viewModel.submitCarnetReviewRequest("STUDENT", dni, inst, doc, exp, qr, photo)
                showCarnetModal = false
            }
        )
    }

    if (showFaqModal) {
        HelpFaqDialog(onDismiss = { showFaqModal = false })
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            containerColor = BCColors.ElevatedSurface,
            title = { Text("¿Eliminar cuenta local?", color = Color.White) },
            text = { Text("Se borrarán tu sesión y saldo local en este dispositivo.", color = BCColors.TextSecondary) },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    onDismiss()
                    viewModel.resetCurrentAccountState()
                    viewModel.logout()
                }) {
                    Text("Eliminar", color = BCColors.DestructiveRed, fontWeight = FontWeight.Bold)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) {
                    Text("Cancelar", color = Color.White)
                }
            }
        )
    }
}

@Composable
fun HelpFaqDialog(onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = BCColors.ElevatedSurface,
        title = { Text("Ayuda · Bus Conectado Tacna", color = Color.White, fontWeight = FontWeight.Bold) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    "• Equivalencia: 1 PEN = 10 Puntos BC.\n" +
                        "• Tarifas: Adulto 15 pts (S/. 1.50), Universitario SUNEDU 7 pts (S/. 0.70), CONADIS 0 pts.\n" +
                        "• Rutas Ordinarias vs Externas: Las rutas ordinarias en servicio cuentan con GPS en vivo, pago QR y alerta 5 minutos antes.\n" +
                        "• Acompañantes (RN-07): Puedes pagar hasta 4 acompañantes adicionales con tarifa adulto en el mismo QR.",
                    color = BCColors.TextSecondary,
                    fontSize = 13.sp,
                    lineHeight = 19.sp
                )
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text("Entendido", color = BCColors.CyanAccent, fontWeight = FontWeight.Bold)
            }
        }
    )
}


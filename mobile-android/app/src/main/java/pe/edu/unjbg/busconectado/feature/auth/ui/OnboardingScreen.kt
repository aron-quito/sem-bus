package pe.edu.unjbg.busconectado.feature.auth.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DirectionsBus
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.Sms
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import pe.edu.unjbg.busconectado.core.designsystem.BCColors
import pe.edu.unjbg.busconectado.core.model.TestAccountPreset
import pe.edu.unjbg.busconectado.core.model.UserRoleType
import pe.edu.unjbg.busconectado.feature.auth.AuthViewModel
import pe.edu.unjbg.busconectado.feature.auth.BCUiState
import pe.edu.unjbg.busconectado.feature.auth.OnboardingStep

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OnboardingScreen(
    state: BCUiState,
    viewModel: AuthViewModel
) {
    var showPresetsSheet by remember { mutableStateOf(false) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    colors = listOf(BCColors.DarkBackground, BCColors.ElevatedSurface)
                )
            )
            .statusBarsPadding()
            .navigationBarsPadding()
    ) {
        when (state.currentStep) {
            is OnboardingStep.Splash -> SplashContent(
                onStartPhone = viewModel::startPhoneOnboarding,
                onOpenTestAccounts = { showPresetsSheet = true },
                onContinueGuest = viewModel::continueAsGuest
            )
            is OnboardingStep.PhoneInput -> PhoneInputContent(
                state = state,
                onBack = viewModel::backToSplash,
                onPhoneChanged = viewModel::onPhoneChanged,
                onSendOtp = viewModel::sendOtp,
                onOpenTestAccounts = { showPresetsSheet = true }
            )
            is OnboardingStep.OtpVerification -> OtpVerificationContent(
                state = state,
                onBack = viewModel::backToPhoneInput,
                onOtpChanged = viewModel::onOtpChanged,
                onFillDemo = viewModel::fillDemoOtp,
                onVerify = viewModel::verifyOtp,
                onResend = viewModel::sendOtp
            )
            is OnboardingStep.Success -> OnboardingSuccessContent(
                state = state,
                onContinue = viewModel::finishOnboardingToMain
            )
        }
    }

    if (showPresetsSheet) {
        ModalBottomSheet(
            onDismissRequest = { showPresetsSheet = false },
            containerColor = BCColors.ElevatedSurface
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .padding(bottom = 28.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Default.Bolt, contentDescription = null, tint = BCColors.Amber)
                    Text(
                        "Cuentas Oficiales de Prueba (Tacna)",
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                        fontSize = 18.sp
                    )
                }
                Text(
                    "Inicia sesión instantáneamente para probar tarifas SUNEDU (7 pts), tarifa adulto (15 pts) o Pase Libre CONADIS (0 pts).",
                    color = BCColors.TextSecondary,
                    fontSize = 12.sp
                )

                TestAccountPreset.officialPresets.forEach { preset ->
                    val accent = BCColors.fromHex(preset.accentHex)
                    Surface(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                showPresetsSheet = false
                                viewModel.loginWithPreset(preset)
                            },
                        shape = RoundedCornerShape(16.dp),
                        color = BCColors.CardSurface,
                        border = BorderStroke(1.dp, accent.copy(alpha = 0.4f))
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
                                    .background(accent.copy(alpha = 0.2f)),
                                contentAlignment = Alignment.Center
                            ) {
                                Icon(
                                    imageVector = when (preset.roleType) {
                                        UserRoleType.STUDENT -> Icons.Default.School
                                        UserRoleType.CONADIS -> Icons.Default.AccountCircle
                                        else -> Icons.Default.Person
                                    },
                                    contentDescription = null,
                                    tint = accent
                                )
                            }
                            Column(modifier = Modifier.weight(1f)) {
                                Text(preset.title, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                                Text(preset.subtitle, color = BCColors.TextSecondary, fontSize = 12.sp)
                                Spacer(Modifier.height(4.dp))
                                Text(
                                    "+51 ${preset.phoneNumber} · OTP ${preset.otpCode} · ${preset.badge}",
                                    color = accent,
                                    fontWeight = FontWeight.SemiBold,
                                    fontSize = 11.sp
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SplashContent(
    onStartPhone: () -> Unit,
    onOpenTestAccounts: () -> Unit,
    onContinueGuest: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        Spacer(Modifier.height(24.dp))

        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Box(
                modifier = Modifier
                    .size(104.dp)
                    .clip(CircleShape)
                    .background(BCColors.RoyalBlue.copy(alpha = 0.16f))
                    .border(2.dp, BCColors.Emerald.copy(alpha = 0.55f), CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Default.DirectionsBus,
                    contentDescription = "Bus Conectado",
                    tint = BCColors.Emerald,
                    modifier = Modifier.size(54.dp)
                )
            }

            Text(
                "Bus Conectado",
                fontSize = 30.sp,
                fontWeight = FontWeight.Black,
                color = Color.White
            )

            Text(
                "Transporte urbano inteligente de Tacna\nTracking GPS en vivo · Monedero y Pago QR · Rutas",
                textAlign = TextAlign.Center,
                color = BCColors.TextSecondary,
                fontSize = 14.sp,
                lineHeight = 20.sp
            )
        }

        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Button(
                onClick = onStartPhone,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(54.dp),
                shape = RoundedCornerShape(16.dp),
                colors = ButtonDefaults.buttonColors(containerColor = BCColors.RoyalBlue)
            ) {
                Icon(Icons.Default.Sms, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Ingresar con Celular (+51)", fontWeight = FontWeight.Bold, fontSize = 16.sp)
            }

            OutlinedButton(
                onClick = onOpenTestAccounts,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(50.dp),
                shape = RoundedCornerShape(16.dp),
                border = BorderStroke(1.dp, BCColors.Amber.copy(alpha = 0.6f))
            ) {
                Icon(Icons.Default.Bolt, contentDescription = null, tint = BCColors.Amber)
                Spacer(Modifier.width(8.dp))
                Text("Acceso Rápido · Cuentas de Prueba", color = BCColors.Amber, fontWeight = FontWeight.Bold)
            }

            TextButton(
                onClick = onContinueGuest,
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Default.Explore, contentDescription = null, tint = BCColors.CyanAccent)
                Spacer(Modifier.width(6.dp))
                Text("Explorar Mapa como Invitado", color = BCColors.CyanAccent, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
private fun PhoneInputContent(
    state: BCUiState,
    onBack: () -> Unit,
    onPhoneChanged: (String) -> Unit,
    onSendOtp: () -> Unit,
    onOpenTestAccounts: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        IconButton(onClick = onBack) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Volver", tint = Color.White)
        }

        Text(
            "Ingresa tu número celular",
            fontSize = 26.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White
        )
        Text(
            "Te enviaremos un código SMS de 6 dígitos para verificar tu cuenta en Bus Conectado Tacna.",
            color = BCColors.TextSecondary,
            fontSize = 14.sp
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Surface(
                shape = RoundedCornerShape(14.dp),
                color = BCColors.CardSurface,
                border = BorderStroke(1.dp, BCColors.HairlineBorder)
            ) {
                Text(
                    "🇵🇪 +51",
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 18.dp)
                )
            }

            OutlinedTextField(
                value = state.phoneNumber,
                onValueChange = onPhoneChanged,
                placeholder = { Text("952 000 002", color = BCColors.TextMuted) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = BCColors.RoyalBlue,
                    unfocusedBorderColor = BCColors.HairlineBorder,
                    focusedTextColor = Color.White,
                    unfocusedTextColor = Color.White,
                    focusedContainerColor = BCColors.CardSurface,
                    unfocusedContainerColor = BCColors.CardSurface
                ),
                shape = RoundedCornerShape(14.dp),
                modifier = Modifier.weight(1f)
            )
        }

        if (!state.errorMessage.isNullOrBlank()) {
            Text(state.errorMessage, color = BCColors.DestructiveRed, fontSize = 13.sp, fontWeight = FontWeight.Medium)
        }

        Button(
            onClick = onSendOtp,
            enabled = !state.isLoading && state.phoneNumber.length == 9,
            modifier = Modifier
                .fillMaxWidth()
                .height(54.dp),
            shape = RoundedCornerShape(16.dp),
            colors = ButtonDefaults.buttonColors(containerColor = BCColors.RoyalBlue)
        ) {
            if (state.isLoading) {
                CircularProgressIndicator(modifier = Modifier.size(22.dp), color = Color.White, strokeWidth = 2.5.dp)
            } else {
                Text("Enviar Código SMS", fontWeight = FontWeight.Bold, fontSize = 16.sp)
            }
        }

        OutlinedButton(
            onClick = onOpenTestAccounts,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(14.dp),
            border = BorderStroke(1.dp, BCColors.Amber.copy(alpha = 0.45f))
        ) {
            Icon(Icons.Default.Bolt, contentDescription = null, tint = BCColors.Amber)
            Spacer(Modifier.width(6.dp))
            Text("Usar Cuenta de Prueba Tacna", color = BCColors.Amber)
        }
    }
}

@Composable
private fun OtpVerificationContent(
    state: BCUiState,
    onBack: () -> Unit,
    onOtpChanged: (String) -> Unit,
    onFillDemo: () -> Unit,
    onVerify: () -> Unit,
    onResend: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        IconButton(onClick = onBack) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Volver", tint = Color.White)
        }

        Text("Código de verificación", fontSize = 26.sp, fontWeight = FontWeight.Bold, color = Color.White)
        Text(
            "Enviado al +51 ${state.phoneNumber}. Código de entorno demo: 123456",
            color = BCColors.TextSecondary,
            fontSize = 14.sp
        )

        BasicTextField(
            value = state.otpCode,
            onValueChange = onOtpChanged,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            textStyle = TextStyle(color = Color.Transparent),
            decorationBox = {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    repeat(6) { idx ->
                        val ch = state.otpCode.getOrNull(idx)?.toString() ?: ""
                        val focused = idx == state.otpCode.length
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(56.dp)
                                .clip(RoundedCornerShape(14.dp))
                                .background(BCColors.CardSurface)
                                .border(
                                    width = if (focused) 2.dp else 1.dp,
                                    color = if (focused) BCColors.RoyalBlue else BCColors.HairlineBorder,
                                    shape = RoundedCornerShape(14.dp)
                                ),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                ch,
                                color = Color.White,
                                fontSize = 22.sp,
                                fontWeight = FontWeight.Bold,
                                fontFamily = FontFamily.Monospace
                            )
                        }
                    }
                }
            }
        )

        TextButton(onClick = onFillDemo) {
            Icon(Icons.Default.Key, contentDescription = null, tint = BCColors.CyanAccent)
            Spacer(Modifier.width(6.dp))
            Text("Autocompletar código demo (123456)", color = BCColors.CyanAccent)
        }

        if (!state.errorMessage.isNullOrBlank()) {
            Text(state.errorMessage, color = BCColors.DestructiveRed, fontSize = 13.sp)
        }

        Button(
            onClick = onVerify,
            enabled = !state.isLoading && state.otpCode.length == 6,
            modifier = Modifier
                .fillMaxWidth()
                .height(54.dp),
            shape = RoundedCornerShape(16.dp),
            colors = ButtonDefaults.buttonColors(containerColor = BCColors.Emerald)
        ) {
            if (state.isLoading) {
                CircularProgressIndicator(modifier = Modifier.size(22.dp), color = Color.Black)
            } else {
                Text("Verificar e Ingresar", color = Color.Black, fontWeight = FontWeight.Bold, fontSize = 16.sp)
            }
        }

        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
            if (state.countdownSeconds > 0) {
                Text("Reenviar código en ${state.countdownSeconds}s", color = BCColors.TextMuted, fontSize = 13.sp)
            } else {
                TextButton(onClick = onResend) {
                    Text("Reenviar SMS", color = BCColors.RoyalBlue, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

@Composable
private fun OnboardingSuccessContent(
    state: BCUiState,
    onContinue: () -> Unit
) {
    val user = state.currentUser
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Box(
            modifier = Modifier
                .size(88.dp)
                .clip(CircleShape)
                .background(BCColors.Emerald.copy(alpha = 0.18f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                Icons.Default.CheckCircle,
                contentDescription = null,
                tint = BCColors.Emerald,
                modifier = Modifier.size(56.dp)
            )
        }

        Spacer(Modifier.height(20.dp))
        Text("¡Bienvenido a Bus Conectado!", fontSize = 24.sp, fontWeight = FontWeight.Black, color = Color.White)
        Spacer(Modifier.height(8.dp))
        Text(
            user?.displayName ?: "Pasajero de Tacna",
            fontSize = 18.sp,
            fontWeight = FontWeight.SemiBold,
            color = BCColors.CyanAccent
        )
        Spacer(Modifier.height(6.dp))
        Text(
            user?.roleType?.badgeLabel ?: "Tarifa General · 15 pts",
            fontSize = 13.sp,
            color = BCColors.TextSecondary
        )

        Spacer(Modifier.height(32.dp))
        Button(
            onClick = onContinue,
            modifier = Modifier
                .fillMaxWidth()
                .height(54.dp),
            shape = RoundedCornerShape(16.dp),
            colors = ButtonDefaults.buttonColors(containerColor = BCColors.RoyalBlue)
        ) {
            Text("Ir al Mapa de Tacna", fontWeight = FontWeight.Bold, fontSize = 16.sp)
        }
    }
}


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
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DirectionsBus
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.Sms
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import pe.edu.unjbg.busconectado.core.designsystem.BCColors
import pe.edu.unjbg.busconectado.feature.auth.AuthViewModel
import pe.edu.unjbg.busconectado.feature.auth.BCUiState
import pe.edu.unjbg.busconectado.feature.auth.OnboardingStep

@Composable
fun OnboardingScreen(
    state: BCUiState,
    viewModel: AuthViewModel
) {
    var socialDialogProvider by remember { mutableStateOf<String?>(null) }
    var socialIsRegistration by remember { mutableStateOf(true) }

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
                state = state,
                onGoogle = {
                    socialIsRegistration = false
                    socialDialogProvider = "google"
                },
                onApple = {
                    socialIsRegistration = false
                    socialDialogProvider = "apple"
                },
                onContinueGuest = viewModel::continueAsGuest
            )
            is OnboardingStep.RegisterSocial -> RegisterSocialContent(
                state = state,
                onBack = viewModel::backToSplash,
                onGoogle = {
                    socialIsRegistration = true
                    socialDialogProvider = "google"
                },
                onApple = {
                    socialIsRegistration = true
                    socialDialogProvider = "apple"
                }
            )
            is OnboardingStep.ProfileSetup -> ProfileSetupContent(
                state = state,
                onBack = viewModel::backToRegisterSocial,
                onFirstNameChanged = viewModel::onDraftFirstNameChanged,
                onLastNameChanged = viewModel::onDraftLastNameChanged,
                onEmailChanged = viewModel::onDraftEmailChanged,
                onContinue = viewModel::saveProfileSetupAndContinue
            )
            is OnboardingStep.PhoneInput -> PhoneInputContent(
                state = state,
                onBack = {
                    if (state.isLinkingPhoneFlow) viewModel.backToProfileSetup() else viewModel.backToSplash()
                },
                onPhoneChanged = viewModel::onPhoneChanged,
                onChannelChanged = viewModel::selectOtpChannel,
                onSendOtp = viewModel::sendOtp,
                onSkip = viewModel::skipPhoneLinking,
                onSocialLogin = { provider ->
                    socialIsRegistration = false
                    socialDialogProvider = provider
                }
            )
            is OnboardingStep.OtpVerification -> OtpVerificationContent(
                state = state,
                onBack = viewModel::backToPhoneInput,
                onOtpChanged = viewModel::onOtpChanged,
                onVerify = viewModel::verifyOtp,
                onResend = viewModel::sendOtp,
                onSkip = viewModel::skipPhoneLinking
            )
            is OnboardingStep.Success -> OnboardingSuccessContent(
                state = state,
                onContinue = viewModel::finishOnboardingToMain
            )
        }
    }

    socialDialogProvider?.let { provider ->
        SocialAccountInputDialog(
            provider = provider,
            onDismiss = { socialDialogProvider = null },
            onConfirm = { first, last, email ->
                socialDialogProvider = null
                viewModel.signInWithSocial(
                    provider = provider,
                    providerUserId = email.ifBlank { "${provider}_uid" },
                    email = email,
                    firstName = first,
                    lastName = last,
                    isRegistration = socialIsRegistration
                )
            }
        )
    }
}

@Composable
private fun SplashContent(
    state: BCUiState,
    onGoogle: () -> Unit,
    onApple: () -> Unit,
    onContinueGuest: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp, vertical = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Spacer(modifier = Modifier.weight(1f))

        Box(
            modifier = Modifier
                .size(104.dp)
                .clip(RoundedCornerShape(28.dp))
                .background(Color(0xFF0C1426))
                .border(
                    width = 1.8.dp,
                    brush = Brush.linearGradient(listOf(BCColors.CyanAccent, BCColors.RoyalBlue)),
                    shape = RoundedCornerShape(28.dp)
                ),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Default.DirectionsBus,
                contentDescription = "Bus Conectado",
                tint = BCColors.CyanAccent,
                modifier = Modifier.size(50.dp)
            )
        }

        Spacer(modifier = Modifier.height(22.dp))

        Text(
            text = "Bus Conectado",
            fontSize = 30.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White
        )
        Spacer(modifier = Modifier.height(6.dp))
        Text(
            text = "Tacna · Transporte Urbano Digital",
            fontSize = 14.sp,
            color = Color.White.copy(alpha = 0.6f)
        )

        Spacer(modifier = Modifier.height(14.dp))

        Surface(
            shape = CircleShape,
            color = Color.White.copy(alpha = 0.06f),
            border = BorderStroke(1.dp, BCColors.HairlineBorder)
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp),
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
                    text = "Rutas urbanas de Tacna en tiempo real",
                    color = Color.White.copy(alpha = 0.8f),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium
                )
            }
        }

        Spacer(modifier = Modifier.height(34.dp))

        Button(
            onClick = onGoogle,
            enabled = !state.isLoading,
            modifier = Modifier
                .fillMaxWidth()
                .height(54.dp),
            shape = RoundedCornerShape(16.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Color.White)
        ) {
            Text("Continuar con Google", color = Color.Black, fontWeight = FontWeight.Bold, fontSize = 16.sp)
        }

        Spacer(modifier = Modifier.height(12.dp))

        OutlinedButton(
            onClick = onApple,
            enabled = !state.isLoading,
            modifier = Modifier
                .fillMaxWidth()
                .height(54.dp),
            shape = RoundedCornerShape(16.dp),
            border = BorderStroke(1.2.dp, Color.White.copy(alpha = 0.5f)),
            colors = ButtonDefaults.outlinedButtonColors(containerColor = Color.Black)
        ) {
            Text("Continuar con Apple ID", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 16.sp)
        }

        if (state.isLoading) {
            Spacer(modifier = Modifier.height(12.dp))
            CircularProgressIndicator(color = BCColors.Emerald, modifier = Modifier.size(26.dp))
        }
        if (state.errorMessage != null) {
            Spacer(modifier = Modifier.height(8.dp))
            Text(state.errorMessage, color = Color(0xFFEF4444), fontSize = 13.sp, textAlign = TextAlign.Center)
        }

        Spacer(modifier = Modifier.height(12.dp))

        OutlinedButton(
            onClick = onContinueGuest,
            modifier = Modifier
                .fillMaxWidth()
                .height(46.dp),
            shape = RoundedCornerShape(14.dp),
            border = BorderStroke(1.dp, BCColors.HairlineBorder),
            colors = ButtonDefaults.outlinedButtonColors(containerColor = Color.White.copy(alpha = 0.04f))
        ) {
            Text("Iniciar como Invitado", color = Color.White.copy(alpha = 0.8f), fontWeight = FontWeight.Medium, fontSize = 14.sp)
        }

        Spacer(modifier = Modifier.height(14.dp))

        Text(
            text = "Al continuar aceptas los Términos y Privacidad de Bus Conectado",
            color = Color.White.copy(alpha = 0.4f),
            fontSize = 11.sp,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.weight(1f))
    }
}

@Composable
private fun RegisterSocialContent(
    state: BCUiState,
    onBack: () -> Unit,
    onGoogle: () -> Unit,
    onApple: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        IconButton(onClick = onBack) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Atrás", tint = Color.White)
        }

        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Icon(
                imageVector = Icons.Default.VerifiedUser,
                contentDescription = null,
                tint = BCColors.CyanAccent,
                modifier = Modifier.size(44.dp)
            )
            Text(
                text = "Crear cuenta",
                color = Color.White,
                fontSize = 26.sp,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = "Regístrate de forma rápida y segura con tu cuenta de Google o Apple ID.",
                color = Color.White.copy(alpha = 0.65f),
                fontSize = 14.sp,
                textAlign = TextAlign.Center
            )

            Spacer(modifier = Modifier.height(8.dp))

            Button(
                onClick = onGoogle,
                enabled = !state.isLoading,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(54.dp),
                shape = RoundedCornerShape(16.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Color.White)
            ) {
                Text("Continuar con Google", color = Color.Black, fontWeight = FontWeight.Bold, fontSize = 16.sp)
            }

            OutlinedButton(
                onClick = onApple,
                enabled = !state.isLoading,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(54.dp),
                shape = RoundedCornerShape(16.dp),
                border = BorderStroke(1.2.dp, Color.White.copy(alpha = 0.5f)),
                colors = ButtonDefaults.outlinedButtonColors(containerColor = Color.Black)
            ) {
                Text("Continuar con Apple ID", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 16.sp)
            }

            if (state.isLoading) {
                CircularProgressIndicator(color = BCColors.Emerald, modifier = Modifier.size(28.dp))
            }
            if (state.errorMessage != null) {
                Text(state.errorMessage, color = Color(0xFFEF4444), fontSize = 13.sp, textAlign = TextAlign.Center)
            }
        }

        Spacer(modifier = Modifier.height(24.dp))
    }
}

@Composable
private fun ProfileSetupContent(
    state: BCUiState,
    onBack: () -> Unit,
    onFirstNameChanged: (String) -> Unit,
    onLastNameChanged: (String) -> Unit,
    onEmailChanged: (String) -> Unit,
    onContinue: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        IconButton(onClick = onBack) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Atrás", tint = Color.White)
        }

        Text("Confirma tus datos", color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.Bold)
        Text(
            "Verifica o edita tu nombre y apellido tal como aparecerán en tu cuenta.",
            color = Color.White.copy(alpha = 0.65f),
            fontSize = 14.sp
        )

        OutlinedTextField(
            value = state.draftFirstName,
            onValueChange = onFirstNameChanged,
            label = { Text("Nombre") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = Color.White,
                unfocusedTextColor = Color.White,
                focusedBorderColor = BCColors.Emerald,
                unfocusedBorderColor = BCColors.HairlineBorder,
                focusedLabelColor = BCColors.Emerald,
                unfocusedLabelColor = Color.White.copy(alpha = 0.6f)
            )
        )

        OutlinedTextField(
            value = state.draftLastName,
            onValueChange = onLastNameChanged,
            label = { Text("Apellido") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = Color.White,
                unfocusedTextColor = Color.White,
                focusedBorderColor = BCColors.Emerald,
                unfocusedBorderColor = BCColors.HairlineBorder,
                focusedLabelColor = BCColors.Emerald,
                unfocusedLabelColor = Color.White.copy(alpha = 0.6f)
            )
        )

        OutlinedTextField(
            value = state.draftEmail,
            onValueChange = onEmailChanged,
            label = { Text("Correo") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
            modifier = Modifier.fillMaxWidth(),
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = Color.White,
                unfocusedTextColor = Color.White,
                focusedBorderColor = BCColors.Emerald,
                unfocusedBorderColor = BCColors.HairlineBorder,
                focusedLabelColor = BCColors.Emerald,
                unfocusedLabelColor = Color.White.copy(alpha = 0.6f)
            )
        )

        if (state.errorMessage != null) {
            Text(state.errorMessage, color = Color(0xFFEF4444), fontSize = 13.sp)
        }

        Button(
            onClick = onContinue,
            enabled = !state.isLoading,
            modifier = Modifier
                .fillMaxWidth()
                .height(54.dp),
            shape = RoundedCornerShape(16.dp),
            colors = ButtonDefaults.buttonColors(containerColor = BCColors.Emerald)
        ) {
            Text("Continuar", color = Color(0xFF04120C), fontWeight = FontWeight.Bold, fontSize = 16.sp)
        }
    }
}

@Composable
private fun PhoneInputContent(
    state: BCUiState,
    onBack: () -> Unit,
    onPhoneChanged: (String) -> Unit,
    onChannelChanged: (String) -> Unit,
    onSendOtp: () -> Unit,
    onSkip: () -> Unit,
    onSocialLogin: (String) -> Unit
) {
    val isValid = state.phoneNumber.length == 9 && state.phoneNumber.startsWith("9")

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        IconButton(onClick = onBack) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Atrás", tint = Color.White)
        }

        Text(
            text = if (state.isLinkingPhoneFlow) "Vincula tu celular" else "Iniciar Sesión",
            color = Color.White,
            fontSize = 26.sp,
            fontWeight = FontWeight.Bold
        )
        Text(
            text = if (state.isLinkingPhoneFlow) {
                "Si desea hacer pagos dentro de la app o acceder a los beneficios como descuentos o promociones, registre su celular."
            } else {
                "Ingresa tu número celular para recibir un código de verificación por WhatsApp o SMS."
            },
            color = Color.White.copy(alpha = 0.65f),
            fontSize = 14.sp
        )

        ChannelSelectorRow(
            selected = state.otpChannel,
            onSelect = onChannelChanged
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Surface(
                shape = RoundedCornerShape(14.dp),
                color = Color.White.copy(alpha = 0.06f),
                border = BorderStroke(1.dp, BCColors.HairlineBorder),
                modifier = Modifier.height(56.dp)
            ) {
                Box(modifier = Modifier.padding(horizontal = 14.dp), contentAlignment = Alignment.Center) {
                    Text("🇵🇪 +51", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                }
            }

            OutlinedTextField(
                value = state.phoneNumber,
                onValueChange = onPhoneChanged,
                placeholder = { Text("9XX XXX XXX", color = Color.White.copy(alpha = 0.35f)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(14.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = Color.White,
                    unfocusedTextColor = Color.White,
                    focusedBorderColor = if (isValid) BCColors.Emerald else BCColors.RoyalBlue,
                    unfocusedBorderColor = BCColors.HairlineBorder,
                    focusedContainerColor = Color.White.copy(alpha = 0.06f),
                    unfocusedContainerColor = Color.White.copy(alpha = 0.06f)
                )
            )
        }

        if (state.errorMessage != null) {
            Text(state.errorMessage, color = Color(0xFFEF4444), fontSize = 13.sp)
        }

        Button(
            onClick = onSendOtp,
            enabled = isValid && !state.isLoading,
            modifier = Modifier
                .fillMaxWidth()
                .height(54.dp),
            shape = RoundedCornerShape(16.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = if (isValid) BCColors.Emerald else Color.White.copy(alpha = 0.12f)
            )
        ) {
            if (state.isLoading) {
                CircularProgressIndicator(color = Color.Black, modifier = Modifier.size(22.dp))
            } else {
                Text(
                    text = if (state.otpChannel == "whatsapp") "Enviar código por WhatsApp" else "Enviar código por SMS",
                    color = if (isValid) Color(0xFF04120C) else Color.White.copy(alpha = 0.4f),
                    fontWeight = FontWeight.Bold
                )
            }
        }

        if (state.isLinkingPhoneFlow) {
            TextButton(
                onClick = onSkip,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Omitir por ahora", color = Color.White.copy(alpha = 0.75f), fontWeight = FontWeight.Medium)
            }
        } else {
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text("o continúa con tu cuenta", color = Color.White.copy(alpha = 0.45f), fontSize = 12.sp)
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Button(
                        onClick = { onSocialLogin("google") },
                        modifier = Modifier.weight(1f).height(46.dp),
                        shape = RoundedCornerShape(12.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = Color.White)
                    ) {
                        Text("Google", color = Color.Black, fontWeight = FontWeight.SemiBold)
                    }
                    OutlinedButton(
                        onClick = { onSocialLogin("apple") },
                        modifier = Modifier.weight(1f).height(46.dp),
                        shape = RoundedCornerShape(12.dp),
                        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.45f)),
                        colors = ButtonDefaults.outlinedButtonColors(containerColor = Color.Black)
                    ) {
                        Text("Apple ID", color = Color.White, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }
    }
}

@Composable
private fun OtpVerificationContent(
    state: BCUiState,
    onBack: () -> Unit,
    onOtpChanged: (String) -> Unit,
    onVerify: () -> Unit,
    onResend: () -> Unit,
    onSkip: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        IconButton(onClick = onBack) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Atrás", tint = Color.White)
        }

        Text("Código de verificación", color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.Bold)
        Text(
            text = state.otpInfoMessage
                ?: "Enviado por ${if (state.otpChannel == "whatsapp") "WhatsApp" else "SMS"} a +51 ${state.phoneNumber}",
            color = Color.White.copy(alpha = 0.65f),
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
                    horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally)
                ) {
                    repeat(6) { index ->
                        val digit = state.otpCode.getOrNull(index)?.toString() ?: ""
                        val focused = state.otpCode.length == index
                        Box(
                            modifier = Modifier
                                .size(width = 46.dp, height = 56.dp)
                                .clip(RoundedCornerShape(12.dp))
                                .background(Color.White.copy(alpha = 0.06f))
                                .border(
                                    width = 1.5.dp,
                                    color = if (focused) BCColors.Emerald else BCColors.HairlineBorder,
                                    shape = RoundedCornerShape(12.dp)
                                ),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(digit, color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }
        )

        if (state.errorMessage != null) {
            Text(state.errorMessage, color = Color(0xFFEF4444), fontSize = 13.sp, textAlign = TextAlign.Center)
        }

        if (state.countdownSeconds > 0) {
            Text(
                "Reenviar código en ${state.countdownSeconds}s",
                color = Color.White.copy(alpha = 0.5f),
                fontSize = 12.sp,
                modifier = Modifier.fillMaxWidth(),
                textAlign = TextAlign.Center
            )
        } else {
            TextButton(onClick = onResend, modifier = Modifier.fillMaxWidth()) {
                Text("Reenviar código", color = BCColors.Emerald, fontWeight = FontWeight.SemiBold)
            }
        }

        Button(
            onClick = onVerify,
            enabled = state.otpCode.length == 6 && !state.isLoading,
            modifier = Modifier
                .fillMaxWidth()
                .height(54.dp),
            shape = RoundedCornerShape(16.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = if (state.otpCode.length == 6) BCColors.Emerald else Color.White.copy(alpha = 0.12f)
            )
        ) {
            Text(
                "Continuar",
                color = if (state.otpCode.length == 6) Color(0xFF04120C) else Color.White.copy(alpha = 0.4f),
                fontWeight = FontWeight.Bold
            )
        }

        if (state.isLinkingPhoneFlow) {
            TextButton(onClick = onSkip, modifier = Modifier.fillMaxWidth()) {
                Text("Omitir por ahora", color = Color.White.copy(alpha = 0.75f))
            }
        }
    }
}

@Composable
private fun OnboardingSuccessContent(
    state: BCUiState,
    onContinue: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = Icons.Default.CheckCircle,
            contentDescription = null,
            tint = BCColors.Emerald,
            modifier = Modifier.size(72.dp)
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text("¡Sesión verificada!", color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.Bold)
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = state.currentUser?.displayFullName ?: "Pasajero BC",
            color = BCColors.Emerald,
            fontSize = 18.sp,
            fontWeight = FontWeight.SemiBold
        )
        Spacer(modifier = Modifier.height(28.dp))
        Button(
            onClick = onContinue,
            modifier = Modifier
                .fillMaxWidth()
                .height(54.dp),
            shape = RoundedCornerShape(16.dp),
            colors = ButtonDefaults.buttonColors(containerColor = BCColors.Emerald)
        ) {
            Text("Entrar a Bus Conectado", color = Color(0xFF04120C), fontWeight = FontWeight.Bold, fontSize = 16.sp)
        }
    }
}

@Composable
private fun ChannelSelectorRow(
    selected: String,
    onSelect: (String) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        listOf("whatsapp" to "WhatsApp", "sms" to "SMS normal").forEach { (id, label) ->
            val isSelected = selected == id
            Surface(
                modifier = Modifier
                    .weight(1f)
                    .height(42.dp)
                    .clickable { onSelect(id) },
                shape = RoundedCornerShape(12.dp),
                color = if (isSelected) BCColors.Emerald else Color.White.copy(alpha = 0.06f),
                border = BorderStroke(1.dp, if (isSelected) BCColors.Emerald else BCColors.HairlineBorder)
            ) {
                Row(
                    modifier = Modifier.fillMaxSize(),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = if (id == "whatsapp") Icons.Default.PhoneAndroid else Icons.Default.Sms,
                        contentDescription = null,
                        tint = if (isSelected) Color.Black else Color.White,
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = label,
                        color = if (isSelected) Color.Black else Color.White,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 13.sp
                    )
                }
            }
        }
    }
}

@Composable
private fun SocialAccountInputDialog(
    provider: String,
    onDismiss: () -> Unit,
    onConfirm: (first: String, last: String, email: String) -> Unit
) {
    var firstName by remember { mutableStateOf("") }
    var lastName by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    val title = if (provider == "apple") "Continuar con Apple ID" else "Continuar con Google"

    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = BCColors.ElevatedSurface,
        titleContentColor = Color.White,
        textContentColor = Color.White,
        title = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Default.AccountCircle, contentDescription = null, tint = BCColors.CyanAccent)
                Text(title, fontSize = 18.sp, fontWeight = FontWeight.Bold)
            }
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    value = firstName,
                    onValueChange = { firstName = it },
                    label = { Text("Nombre") },
                    singleLine = true,
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = Color.White,
                        unfocusedTextColor = Color.White,
                        focusedBorderColor = BCColors.Emerald,
                        unfocusedBorderColor = BCColors.HairlineBorder
                    )
                )
                OutlinedTextField(
                    value = lastName,
                    onValueChange = { lastName = it },
                    label = { Text("Apellido") },
                    singleLine = true,
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = Color.White,
                        unfocusedTextColor = Color.White,
                        focusedBorderColor = BCColors.Emerald,
                        unfocusedBorderColor = BCColors.HairlineBorder
                    )
                )
                OutlinedTextField(
                    value = email,
                    onValueChange = { email = it },
                    label = { Text("Correo") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = Color.White,
                        unfocusedTextColor = Color.White,
                        focusedBorderColor = BCColors.Emerald,
                        unfocusedBorderColor = BCColors.HairlineBorder
                    )
                )
            }
        },
        confirmButton = {
            Button(
                onClick = { onConfirm(firstName, lastName, email) },
                enabled = email.trim().isNotEmpty(),
                colors = ButtonDefaults.buttonColors(containerColor = BCColors.Emerald)
            ) {
                Text("Continuar", color = Color.Black, fontWeight = FontWeight.Bold)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancelar", color = Color.White.copy(alpha = 0.7f))
            }
        }
    )
}

@Composable
fun PhoneLinkModalDialog(
    state: BCUiState,
    viewModel: AuthViewModel
) {
    val isValidPhone = state.phoneNumber.length == 9 && state.phoneNumber.startsWith("9")
    AlertDialog(
        onDismissRequest = viewModel::closePhoneLinkingFromApp,
        containerColor = BCColors.ElevatedSurface,
        titleContentColor = Color.White,
        textContentColor = Color.White,
        title = {
            Text(
                text = if (state.currentStep is OnboardingStep.OtpVerification) "Código de verificación" else "Vincular celular",
                fontWeight = FontWeight.Bold
            )
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (state.currentStep is OnboardingStep.OtpVerification) {
                    Text(
                        text = state.otpInfoMessage
                            ?: "Enviado por ${if (state.otpChannel == "whatsapp") "WhatsApp" else "SMS"} a +51 ${state.phoneNumber}",
                        color = Color.White.copy(alpha = 0.75f),
                        fontSize = 13.sp
                    )
                    OutlinedTextField(
                        value = state.otpCode,
                        onValueChange = viewModel::onOtpChanged,
                        label = { Text("Código de 6 dígitos") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedTextColor = Color.White,
                            unfocusedTextColor = Color.White,
                            focusedBorderColor = BCColors.Emerald,
                            unfocusedBorderColor = BCColors.HairlineBorder
                        )
                    )
                } else {
                    Text(
                        text = "Si desea hacer pagos dentro de la app o acceder a los beneficios como descuentos o promociones, registre su celular.",
                        color = Color.White.copy(alpha = 0.75f),
                        fontSize = 13.sp
                    )
                    ChannelSelectorRow(
                        selected = state.otpChannel,
                        onSelect = viewModel::selectOtpChannel
                    )
                    OutlinedTextField(
                        value = state.phoneNumber,
                        onValueChange = viewModel::onPhoneChanged,
                        label = { Text("Celular (+51)") },
                        placeholder = { Text("9XX XXX XXX") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedTextColor = Color.White,
                            unfocusedTextColor = Color.White,
                            focusedBorderColor = BCColors.Emerald,
                            unfocusedBorderColor = BCColors.HairlineBorder
                        )
                    )
                }
                if (state.errorMessage != null) {
                    Text(state.errorMessage, color = Color(0xFFEF4444), fontSize = 12.sp)
                }
            }
        },
        confirmButton = {
            if (state.currentStep is OnboardingStep.OtpVerification) {
                Button(
                    onClick = viewModel::verifyOtp,
                    enabled = state.otpCode.length == 6 && !state.isLoading,
                    colors = ButtonDefaults.buttonColors(containerColor = BCColors.Emerald)
                ) {
                    Text("Verificar", color = Color.Black, fontWeight = FontWeight.Bold)
                }
            } else {
                Button(
                    onClick = viewModel::sendOtp,
                    enabled = isValidPhone && !state.isLoading,
                    colors = ButtonDefaults.buttonColors(containerColor = BCColors.Emerald)
                ) {
                    Text("Enviar código", color = Color.Black, fontWeight = FontWeight.Bold)
                }
            }
        },
        dismissButton = {
            TextButton(onClick = viewModel::closePhoneLinkingFromApp) {
                Text("Cerrar", color = Color.White.copy(alpha = 0.7f))
            }
        }
    )
}

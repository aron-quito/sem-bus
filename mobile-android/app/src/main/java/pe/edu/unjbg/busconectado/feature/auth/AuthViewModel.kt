package pe.edu.unjbg.busconectado.feature.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import pe.edu.unjbg.busconectado.core.security.EncryptedStorage

sealed class OnboardingStep {
    object Splash : OnboardingStep()
    object PhoneInput : OnboardingStep()
    object OtpVerification : OnboardingStep()
    object Success : OnboardingStep()
}

data class AuthUiState(
    val currentStep: OnboardingStep = OnboardingStep.Splash,
    val phoneNumber: String = "",
    val otpCode: String = "",
    val isGuestMode: Boolean = false,
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val countdownSeconds: Int = 59
)

class AuthViewModel(
    private val encryptedStorage: EncryptedStorage
) : ViewModel() {

    private val _uiState = MutableStateFlow(AuthUiState())
    val uiState: StateFlow<AuthUiState> = _uiState.asStateFlow()

    fun onPhoneChanged(phone: String) {
        val filtered = phone.filter { it.isDigit() }.take(9)
        _uiState.value = _uiState.value.copy(
            phoneNumber = filtered,
            errorMessage = null
        )
    }

    fun onOtpChanged(code: String) {
        val filtered = code.filter { it.isDigit() }.take(6)
        _uiState.value = _uiState.value.copy(
            otpCode = filtered,
            errorMessage = null
        )
    }

    fun sendOtp() {
        val phone = _uiState.value.phoneNumber
        if (phone.length != 9 || !phone.startsWith("9")) {
            _uiState.value = _uiState.value.copy(
                errorMessage = "Ingresa un celular peruano de 9 dígitos que empiece con 9"
            )
            return
        }

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, errorMessage = null)
            // Simulación o llamada API REST
            _uiState.value = _uiState.value.copy(
                isLoading = false,
                currentStep = OnboardingStep.OtpVerification,
                countdownSeconds = 59
            )
        }
    }

    fun verifyOtp() {
        val code = _uiState.value.otpCode
        if (code.length != 6) {
            _uiState.value = _uiState.value.copy(errorMessage = "El código debe tener 6 dígitos")
            return
        }

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, errorMessage = null)
            // Si es demo o validado exitosamente:
            encryptedStorage.saveAccessToken("demo_access_token_jwt")
            encryptedStorage.saveRefreshToken("demo_refresh_token_jwt")
            _uiState.value = _uiState.value.copy(
                isLoading = false,
                currentStep = OnboardingStep.Success
            )
        }
    }

    fun continueAsGuest() {
        _uiState.value = _uiState.value.copy(isGuestMode = true)
    }
}

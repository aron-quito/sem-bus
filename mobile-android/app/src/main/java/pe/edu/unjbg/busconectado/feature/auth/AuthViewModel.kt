package pe.edu.unjbg.busconectado.feature.auth

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import pe.edu.unjbg.busconectado.core.designsystem.BCFeedback
import pe.edu.unjbg.busconectado.core.location.GeoPointData
import pe.edu.unjbg.busconectado.core.location.LocationService
import pe.edu.unjbg.busconectado.core.model.ActiveBusModel
import pe.edu.unjbg.busconectado.core.model.ActiveRouteGuidanceState
import pe.edu.unjbg.busconectado.core.model.ActiveTripState
import pe.edu.unjbg.busconectado.core.model.ArrivalAlertState
import pe.edu.unjbg.busconectado.core.model.BusRouteModel
import pe.edu.unjbg.busconectado.core.model.BusStopModel
import pe.edu.unjbg.busconectado.core.model.CarnetReviewRequest
import pe.edu.unjbg.busconectado.core.model.EvaluatedCandidateKind
import pe.edu.unjbg.busconectado.core.model.EvaluatedRouteCandidate
import pe.edu.unjbg.busconectado.core.model.LedgerTransactionItem
import pe.edu.unjbg.busconectado.core.model.LedgerTransactionKind
import pe.edu.unjbg.busconectado.core.model.MainAppTab
import pe.edu.unjbg.busconectado.core.model.MapFilterCategory
import pe.edu.unjbg.busconectado.core.model.RouteAutomationEngine
import pe.edu.unjbg.busconectado.core.model.RouteAutomationEvaluationResult
import pe.edu.unjbg.busconectado.core.model.StopNotificationAvailability
import pe.edu.unjbg.busconectado.core.model.TacnaDestinationPlace
import pe.edu.unjbg.busconectado.core.model.TacnaOfficialRouteCatalogItem
import pe.edu.unjbg.busconectado.core.model.TacnaSeedLoader
import pe.edu.unjbg.busconectado.core.model.TestAccountPreset
import pe.edu.unjbg.busconectado.core.model.UserAuth
import pe.edu.unjbg.busconectado.core.model.UserRoleType
import pe.edu.unjbg.busconectado.core.network.BCNetworkClient
import pe.edu.unjbg.busconectado.core.network.OtpSendRequest
import pe.edu.unjbg.busconectado.core.network.OtpVerifyRequest
import pe.edu.unjbg.busconectado.core.network.ProfileUpdateRequest
import pe.edu.unjbg.busconectado.core.network.RechargeRequest
import pe.edu.unjbg.busconectado.core.network.SocialAuthRequest
import pe.edu.unjbg.busconectado.core.notifications.BCNotificationManager
import pe.edu.unjbg.busconectado.core.security.EncryptedStorage
import java.text.Normalizer
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import kotlin.math.max
import kotlin.math.roundToInt

sealed class OnboardingStep {
    object Splash : OnboardingStep()
    object RegisterSocial : OnboardingStep()
    object ProfileSetup : OnboardingStep()
    object PhoneInput : OnboardingStep()
    object OtpVerification : OnboardingStep()
    object Success : OnboardingStep()
}

data class CameraFocusCommand(
    val center: GeoPointData,
    val zoom: Double,
    val nonce: Int
)

data class BCUiState(
    val currentStep: OnboardingStep = OnboardingStep.Splash,
    val phoneNumber: String = "",
    val otpCode: String = "",
    val otpChannel: String = "whatsapp",
    val otpInfoMessage: String? = null,
    val isLinkingPhoneFlow: Boolean = false,
    val showPhoneLinkDialog: Boolean = false,
    val draftFirstName: String = "",
    val draftLastName: String = "",
    val draftEmail: String = "",
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val isLoggedIn: Boolean = false,
    val isGuestMode: Boolean = false,
    val currentUser: UserAuth? = null,
    val countdownSeconds: Int = 59,

    val selectedTab: MainAppTab = MainAppTab.EXPLORE,
    val mapCategory: MapFilterCategory = MapFilterCategory.LIVE,
    val searchText: String = "",
    val searchedDestinationPin: TacnaDestinationPlace? = null,
    val activeRouteOverlayOnMap: TacnaOfficialRouteCatalogItem? = null,
    val cameraFocus: CameraFocusCommand = CameraFocusCommand(LocationService.TACNA_HISTORIC_CENTER, 14.5, 0),

    val isRoutePlannerPresented: Boolean = false,
    val routePlannerInitialDestination: TacnaDestinationPlace? = null,
    val routePlannerInitialOrigin: TacnaDestinationPlace? = null,
    val recentSearchedPlaces: List<TacnaDestinationPlace> = emptyList(),

    val activeRouteGuidance: ActiveRouteGuidanceState? = null,
    val showFiveMinuteBoardingBanner: Boolean = false,
    val showExternalGuidancePopup: Boolean = false,
    val showCancelGuidanceConfirm: Boolean = false,
    val activeArrivalAlert: ArrivalAlertState? = null,
    val activeTrip: ActiveTripState? = null,

    val showInsufficientBalanceDialog: Boolean = false,
    val insufficientBalanceDetail: String = "",
    val qrErrorMessage: String? = null,
    val qrSuccessMessage: String? = null,

    val ledgerTransactions: List<LedgerTransactionItem> = emptyList(),
    val carnetReviewRequests: List<CarnetReviewRequest> = emptyList(),

    val stops: List<BusStopModel> = emptyList(),
    val routes: List<BusRouteModel> = emptyList(),
    val activeBuses: List<ActiveBusModel> = emptyList(),
    val dynamicCatalogStops: List<TacnaDestinationPlace> = emptyList(),
    val dynamicRoutes: List<TacnaOfficialRouteCatalogItem> = emptyList(),

    val isSyncingCatalog: Boolean = false,
    val syncStatusMessage: String? = null,
    val lastSyncTimeLabel: String? = null,
    val backendHost: String = EncryptedStorage.DEFAULT_BACKEND_HOST,
    val userLocation: GeoPointData = LocationService.TACNA_DEFAULT,
    val hasGpsLock: Boolean = false
)

class AuthViewModel(application: Application) : AndroidViewModel(application) {

    private val appContext: Context = application.applicationContext
    val storage = EncryptedStorage(appContext)
    val networkClient = BCNetworkClient(storage)
    val locationService = LocationService(appContext)
    private val notificationManager = BCNotificationManager(appContext)

    private val _uiState = MutableStateFlow(
        BCUiState(
            backendHost = storage.getBackendHost(),
            recentSearchedPlaces = storage.loadRecentPlaces()
        )
    )
    val uiState: StateFlow<BCUiState> = _uiState.asStateFlow()

    private var lastSyncEpochMs: Long = 0L
    private var otpCountdownJob: Job? = null
    private var liveLoopJob: Job? = null
    private var lastStudentFareTimestampMs: Long = 0L

    fun getStudentCooldownRemainingSeconds(): Int {
        if (lastStudentFareTimestampMs <= 0L) return 0
        val elapsedSec = (System.currentTimeMillis() - lastStudentFareTimestampMs) / 1000L
        return if (elapsedSec < 120L) (120L - elapsedSec).toInt() else 0
    }

    init {
        networkClient.onUnauthorizedSession = {
            viewModelScope.launch { logout() }
        }
        bootstrapOfflineCatalog()
        restoreSessionIfAvailable()
        observeLocation()
        startLiveLoop()
        startLiveTransitPolling()
        viewModelScope.launch {
            refreshStateFromBackend(force = true)
        }
    }

    private fun bootstrapOfflineCatalog() {
        val cachedStops = storage.loadCachedStops()
        val cachedRoutes = storage.loadCachedRoutes()
        val stops = if (cachedStops.isNotEmpty()) cachedStops else TacnaSeedLoader.loadBundledStops(appContext)
        val routes = if (cachedRoutes.isNotEmpty()) cachedRoutes else TacnaSeedLoader.loadBundledRoutes(appContext)
        _uiState.update {
            it.copy(
                dynamicCatalogStops = stops,
                dynamicRoutes = routes
            )
        }
    }

    private fun restoreSessionIfAvailable() {
        val token = storage.getAccessToken()
        val savedPhone = storage.getLastPhone()
        if (!token.isNullOrBlank() && !savedPhone.isNullOrBlank()) {
            val clean = savedPhone.replace("+51", "").takeLast(9)
            val preset = TestAccountPreset.officialPresets.firstOrNull { it.phoneNumber == clean }
            val user = preset?.defaultUser ?: UserAuth(
                id = "user_tacna_$clean",
                phone = "+51$clean",
                displayName = "Pasajero Tacna",
                role = "ADULT",
                isStudent = false,
                pointsBalance = 0
            )
            applyAuthenticatedUser(user, toSuccessStep = false)
        }
    }

    private fun applyAuthenticatedUser(user: UserAuth, toSuccessStep: Boolean) {
        val overridePts = storage.getWalletPointsOverride(user.id)
        val effectiveUser = if (overridePts != null) user.copy(pointsBalance = overridePts) else user
        val savedCarnet = storage.loadCarnetReviewRequest(effectiveUser.id)
        _uiState.update { state ->
            state.copy(
                isLoggedIn = !toSuccessStep,
                isGuestMode = false,
                currentUser = effectiveUser,
                currentStep = if (toSuccessStep) OnboardingStep.Success else state.currentStep,
                carnetReviewRequests = listOfNotNull(savedCarnet),
                errorMessage = null
            )
        }
    }

    private fun observeLocation() {
        locationService.startUpdates()
        viewModelScope.launch {
            locationService.currentLocation.collect { pt ->
                _uiState.update { it.copy(userLocation = pt) }
            }
        }
        viewModelScope.launch {
            locationService.hasGpsLock.collect { locked ->
                _uiState.update { it.copy(hasGpsLock = locked) }
            }
        }
    }

    private fun startLiveLoop() {
        liveLoopJob?.cancel()
        liveLoopJob = viewModelScope.launch {
            while (true) {
                delay(1000L)
                _uiState.update { state ->
                    var nextGuidance = state.activeRouteGuidance
                    var show5Min = state.showFiveMinuteBoardingBanner
                    if (nextGuidance != null && nextGuidance.showArrivalTimer && nextGuidance.remainingBusArrivalSeconds > 0) {
                        val updatedSecs = nextGuidance.remainingBusArrivalSeconds - 1
                        nextGuidance = nextGuidance.copy(remainingBusArrivalSeconds = updatedSecs)
                        if (updatedSecs == 300) {
                            show5Min = true
                            notificationManager.showBusApproachingNotification(
                                routeCode = nextGuidance.candidate?.routeCode ?: "Ruta",
                                stopName = nextGuidance.candidate?.boardingPointName ?: "Paradero",
                                minutesAway = 5
                            )
                            BCFeedback.warning(appContext)
                        }
                    }

                    var nextAlert = state.activeArrivalAlert
                    if (nextAlert != null && nextAlert.remainingSeconds > 0) {
                        val rem = nextAlert.remainingSeconds - 1
                        if (rem == 300) {
                            notificationManager.showBusApproachingNotification(
                                routeCode = nextAlert.routeLine,
                                stopName = nextAlert.stopName,
                                minutesAway = 5
                            )
                            BCFeedback.warning(appContext)
                        }
                        nextAlert = if (rem <= 0) null else nextAlert.copy(remainingSeconds = rem)
                    }

                    var nextTrip = state.activeTrip
                    if (nextTrip != null && nextTrip.remainingSeconds > 0) {
                        val rem = nextTrip.remainingSeconds - 1
                        nextTrip = if (rem <= 0) null else nextTrip.copy(remainingSeconds = rem)
                    }

                    state.copy(
                        activeRouteGuidance = nextGuidance,
                        showFiveMinuteBoardingBanner = show5Min,
                        activeArrivalAlert = nextAlert,
                        activeTrip = nextTrip
                    )
                }
            }
        }
    }

    fun startPhoneOnboarding() {
        _uiState.update {
            it.copy(
                currentStep = OnboardingStep.PhoneInput,
                isLinkingPhoneFlow = false,
                errorMessage = null,
                otpInfoMessage = null
            )
        }
    }

    fun startRegisterSocial() {
        _uiState.update {
            it.copy(
                currentStep = OnboardingStep.RegisterSocial,
                isLinkingPhoneFlow = true,
                errorMessage = null
            )
        }
    }

    fun backToSplash() {
        otpCountdownJob?.cancel()
        _uiState.update {
            it.copy(
                currentStep = OnboardingStep.Splash,
                isLinkingPhoneFlow = false,
                errorMessage = null,
                otpInfoMessage = null
            )
        }
    }

    fun backToRegisterSocial() {
        _uiState.update { it.copy(currentStep = OnboardingStep.RegisterSocial, errorMessage = null) }
    }

    fun backToProfileSetup() {
        _uiState.update { it.copy(currentStep = OnboardingStep.ProfileSetup, errorMessage = null) }
    }

    fun backToPhoneInput() {
        otpCountdownJob?.cancel()
        _uiState.update {
            it.copy(
                currentStep = OnboardingStep.PhoneInput,
                otpCode = "",
                errorMessage = null
            )
        }
    }

    fun selectOtpChannel(channel: String) {
        _uiState.update { it.copy(otpChannel = channel, errorMessage = null) }
    }

    fun onDraftFirstNameChanged(value: String) {
        _uiState.update { it.copy(draftFirstName = value, errorMessage = null) }
    }

    fun onDraftLastNameChanged(value: String) {
        _uiState.update { it.copy(draftLastName = value, errorMessage = null) }
    }

    fun onDraftEmailChanged(value: String) {
        _uiState.update { it.copy(draftEmail = value, errorMessage = null) }
    }

    fun signInWithSocial(
        provider: String,
        providerUserId: String,
        email: String,
        firstName: String,
        lastName: String,
        isRegistration: Boolean
    ) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, errorMessage = null) }
            val cleanFirst = firstName.trim()
            val cleanLast = lastName.trim()
            val fullName = listOf(cleanFirst, cleanLast).filter { it.isNotEmpty() }.joinToString(" ")
                .ifEmpty { if (provider == "apple") "Usuario Apple" else "Usuario Google" }

            var resolvedUser: UserAuth? = null
            var isNewUser = isRegistration
            try {
                val resp = networkClient.service().socialAuth(
                    SocialAuthRequest(
                        provider = provider,
                        providerUserId = providerUserId,
                        email = email.trim(),
                        firstName = cleanFirst,
                        lastName = cleanLast,
                        displayName = fullName
                    )
                )
                if (resp.isSuccessful && resp.body() != null) {
                    val body = resp.body()!!
                    storage.saveAccessToken(body.accessToken)
                    storage.saveRefreshToken(body.refreshToken)
                    resolvedUser = body.user
                    isNewUser = body.isNewUser
                }
            } catch (_: Exception) {
            }

            if (resolvedUser == null) {
                val uid = "usr_${provider}_${UUID.randomUUID().toString().take(8)}"
                storage.saveAccessToken("local_jwt_$uid")
                storage.saveRefreshToken("local_refresh_$uid")
                isNewUser = true
                resolvedUser = UserAuth(
                    id = uid,
                    phone = "",
                    firstName = cleanFirst,
                    lastName = cleanLast,
                    displayName = fullName,
                    email = email.trim(),
                    authProvider = provider,
                    phoneVerified = false,
                    role = "ADULT",
                    isStudent = false,
                    pointsBalance = 0
                )
            }

            val user = resolvedUser
            if (user.phone.isNotBlank()) storage.saveLastPhone(user.phone)
            val nextStep = when {
                isNewUser -> OnboardingStep.ProfileSetup
                !user.hasVerifiedPhone -> OnboardingStep.PhoneInput
                else -> OnboardingStep.Splash
            }

            _uiState.update {
                it.copy(
                    isLoading = false,
                    currentUser = user,
                    draftFirstName = user.firstName ?: cleanFirst,
                    draftLastName = user.lastName ?: cleanLast,
                    draftEmail = user.email ?: email.trim(),
                    isLinkingPhoneFlow = isNewUser || !user.hasVerifiedPhone,
                    currentStep = nextStep,
                    isLoggedIn = !isNewUser && user.hasVerifiedPhone,
                    isGuestMode = false
                )
            }
            BCFeedback.success(appContext)
        }
    }

    fun saveProfileSetupAndContinue() {
        val first = _uiState.value.draftFirstName.trim()
        val last = _uiState.value.draftLastName.trim()
        val email = _uiState.value.draftEmail.trim()
        if (first.isEmpty()) {
            _uiState.update { it.copy(errorMessage = "Ingresa tu nombre para continuar") }
            BCFeedback.error(appContext)
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, errorMessage = null) }
            val current = _uiState.value.currentUser
            val fullName = listOf(first, last).filter { it.isNotEmpty() }.joinToString(" ")
            if (current != null) {
                val updated = current.copy(
                    firstName = first,
                    lastName = last,
                    displayName = fullName,
                    email = email.ifEmpty { current.email }
                )
                try {
                    networkClient.service().updateProfile(
                        ProfileUpdateRequest(
                            userId = updated.id,
                            firstName = first,
                            lastName = last,
                            displayName = fullName,
                            email = updated.email ?: ""
                        )
                    )
                } catch (_: Exception) {
                }
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        currentUser = updated,
                        isLinkingPhoneFlow = true,
                        currentStep = OnboardingStep.PhoneInput
                    )
                }
            } else {
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        isLinkingPhoneFlow = true,
                        currentStep = OnboardingStep.PhoneInput
                    )
                }
            }
        }
    }

    fun skipPhoneLinking() {
        otpCountdownJob?.cancel()
        _uiState.update {
            it.copy(
                isLinkingPhoneFlow = false,
                showPhoneLinkDialog = false,
                isLoggedIn = true,
                isGuestMode = false,
                errorMessage = null,
                otpInfoMessage = null
            )
        }
        BCFeedback.impactLight(appContext)
    }

    fun openPhoneLinkingFromApp() {
        otpCountdownJob?.cancel()
        _uiState.update {
            it.copy(
                isLinkingPhoneFlow = true,
                showPhoneLinkDialog = true,
                currentStep = OnboardingStep.PhoneInput,
                otpCode = "",
                errorMessage = null,
                otpInfoMessage = null
            )
        }
    }

    fun closePhoneLinkingFromApp() {
        otpCountdownJob?.cancel()
        _uiState.update {
            it.copy(
                showPhoneLinkDialog = false,
                isLinkingPhoneFlow = false,
                errorMessage = null,
                otpInfoMessage = null
            )
        }
    }

    fun onPhoneChanged(phone: String) {
        val filtered = phone.filter { it.isDigit() }.take(9)
        _uiState.update { it.copy(phoneNumber = filtered, errorMessage = null) }
    }

    fun onOtpChanged(code: String) {
        val filtered = code.filter { it.isDigit() }.take(6)
        _uiState.update { it.copy(otpCode = filtered, errorMessage = null) }
        if (filtered.length == 6 && !_uiState.value.isLoading) {
            verifyOtp()
        }
    }

    fun fillDemoOtp() {
        onOtpChanged("123456")
    }

    fun sendOtp() {
        val phone = _uiState.value.phoneNumber
        val channel = _uiState.value.otpChannel
        if (phone.length != 9 || !phone.startsWith("9")) {
            _uiState.update {
                it.copy(errorMessage = "Ingresa un celular peruano válido de 9 dígitos (empieza con 9)")
            }
            BCFeedback.error(appContext)
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, errorMessage = null, otpInfoMessage = null) }
            val fullPhone = "+51$phone"
            var infoMsg = "Código de prueba (${if (channel == "whatsapp") "WhatsApp" else "SMS"}): 123456"
            try {
                val resp = networkClient.service().sendOtp(OtpSendRequest(fullPhone, channel))
                if (resp.isSuccessful && !resp.body()?.message.isNullOrBlank()) {
                    infoMsg = resp.body()!!.message!!
                }
            } catch (_: Exception) {
            }
            _uiState.update {
                it.copy(
                    isLoading = false,
                    currentStep = OnboardingStep.OtpVerification,
                    countdownSeconds = 59,
                    otpCode = "",
                    otpInfoMessage = infoMsg
                )
            }
            BCFeedback.success(appContext)
            startOtpCountdown()
        }
    }

    private fun startOtpCountdown() {
        otpCountdownJob?.cancel()
        otpCountdownJob = viewModelScope.launch {
            while (_uiState.value.countdownSeconds > 0 &&
                _uiState.value.currentStep is OnboardingStep.OtpVerification
            ) {
                delay(1000L)
                _uiState.update {
                    it.copy(countdownSeconds = max(0, it.countdownSeconds - 1))
                }
            }
        }
    }

    fun verifyOtp() {
        val code = _uiState.value.otpCode
        val phone = _uiState.value.phoneNumber
        val isLinking = _uiState.value.isLinkingPhoneFlow
        val currentUser = _uiState.value.currentUser
        if (code.length != 6) {
            _uiState.update { it.copy(errorMessage = "El código de verificación debe tener 6 dígitos") }
            BCFeedback.error(appContext)
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, errorMessage = null) }
            val linkingUserId = if (isLinking) currentUser?.id else null

            try {
                val resp = networkClient.service().verifyOtp(
                    OtpVerifyRequest(phone = "+51$phone", code = code, userId = linkingUserId)
                )
                if (resp.isSuccessful && resp.body() != null) {
                    val body = resp.body()!!
                    storage.saveAccessToken(body.accessToken)
                    storage.saveRefreshToken(body.refreshToken)
                    storage.saveLastPhone(phone)
                    if (_uiState.value.showPhoneLinkDialog) {
                        applyAuthenticatedUser(body.user, toSuccessStep = false)
                        _uiState.update {
                            it.copy(
                                isLoading = false,
                                showPhoneLinkDialog = false,
                                isLinkingPhoneFlow = false,
                                isLoggedIn = true,
                                isGuestMode = false
                            )
                        }
                    } else {
                        applyAuthenticatedUser(body.user, toSuccessStep = true)
                        _uiState.update { it.copy(isLoading = false, isLinkingPhoneFlow = false) }
                    }
                    BCFeedback.success(appContext)
                    return@launch
                } else {
                    val errText = resp.errorBody()?.string()
                    if (!errText.isNullOrBlank() && errText.contains("vinculado")) {
                        _uiState.update {
                            it.copy(isLoading = false, errorMessage = "Este número celular ya está vinculado a otra cuenta.")
                        }
                        BCFeedback.error(appContext)
                        return@launch
                    }
                }
            } catch (_: Exception) {
            }

            if (code == "123456") {
                val updatedUser = if (isLinking && currentUser != null) {
                    currentUser.copy(phone = "+51$phone", phoneVerified = true)
                } else {
                    UserAuth(
                        id = "user_tacna_$phone",
                        phone = "+51$phone",
                        displayName = "Pasajero Tacna",
                        phoneVerified = true,
                        role = "ADULT",
                        isStudent = false,
                        pointsBalance = 0
                    )
                }
                storage.saveAccessToken("local_access_${updatedUser.id}")
                storage.saveRefreshToken("local_refresh_${updatedUser.id}")
                storage.saveLastPhone(phone)
                if (_uiState.value.showPhoneLinkDialog) {
                    applyAuthenticatedUser(updatedUser, toSuccessStep = false)
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            showPhoneLinkDialog = false,
                            isLinkingPhoneFlow = false,
                            isLoggedIn = true,
                            isGuestMode = false
                        )
                    }
                } else {
                    applyAuthenticatedUser(updatedUser, toSuccessStep = true)
                    _uiState.update { it.copy(isLoading = false, isLinkingPhoneFlow = false) }
                }
                BCFeedback.success(appContext)
            } else {
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        errorMessage = "Código OTP incorrecto. Verifica el código enviado."
                    )
                }
                BCFeedback.error(appContext)
            }
        }
    }

    fun finishOnboardingToMain() {
        _uiState.update { it.copy(isLoggedIn = true, isGuestMode = false) }
    }

    fun loginWithPreset(preset: TestAccountPreset) {
        storage.saveAccessToken("demo_access_${preset.id}")
        storage.saveRefreshToken("demo_refresh_${preset.id}")
        storage.saveLastPhone(preset.phoneNumber)
        applyAuthenticatedUser(preset.defaultUser, toSuccessStep = false)
        _uiState.update {
            it.copy(
                phoneNumber = preset.phoneNumber,
                isLoggedIn = true,
                isGuestMode = false
            )
        }
        BCFeedback.success(appContext)
    }

    fun continueAsGuest() {
        _uiState.update {
            it.copy(
                isGuestMode = true,
                isLoggedIn = false,
                currentUser = null,
                errorMessage = null
            )
        }
        BCFeedback.impactMedium(appContext)
    }

    fun leaveGuestForOnboarding() {
        _uiState.update {
            it.copy(
                isGuestMode = false,
                isLoggedIn = false,
                currentStep = OnboardingStep.Splash
            )
        }
    }

    fun selectTab(tab: MainAppTab) {
        _uiState.update { it.copy(selectedTab = tab, qrErrorMessage = null, qrSuccessMessage = null) }
        BCFeedback.impactLight(appContext)
    }

    fun selectMapCategory(category: MapFilterCategory) {
        _uiState.update {
            it.copy(
                mapCategory = category,
                activeRouteOverlayOnMap = null
            )
        }
        BCFeedback.impactLight(appContext)
    }

    fun onSearchTextChanged(text: String) {
        _uiState.update { it.copy(searchText = text) }
    }

    fun focusMapOnCoordinate(point: GeoPointData, zoom: Double = 15.8) {
        val safe = LocationService.sanitizedTacnaCoordinate(point)
        _uiState.update { state ->
            state.copy(
                cameraFocus = CameraFocusCommand(
                    center = safe,
                    zoom = zoom,
                    nonce = state.cameraFocus.nonce + 1
                )
            )
        }
    }

    fun centerMapOnUserLocation() {
        val pt = _uiState.value.userLocation
        focusMapOnCoordinate(pt, zoom = 16.0)
        BCFeedback.impactLight(appContext)
    }

    fun focusMapOnPlace(place: TacnaDestinationPlace) {
        recordRecentSearchedPlace(place)
        _uiState.update { state ->
            state.copy(
                selectedTab = MainAppTab.EXPLORE,
                searchedDestinationPin = place,
                searchText = "",
                activeRouteOverlayOnMap = null,
                cameraFocus = CameraFocusCommand(
                    center = LocationService.sanitizedTacnaCoordinate(place.coordinate),
                    zoom = 16.0,
                    nonce = state.cameraFocus.nonce + 1
                )
            )
        }
    }

    fun clearSearchedDestinationPin() {
        _uiState.update { it.copy(searchedDestinationPin = null) }
    }

    fun projectRouteOnExploreMap(route: TacnaOfficialRouteCatalogItem) {
        val stops = route.resolvedStops(_uiState.value.dynamicCatalogStops)
        val center = stops.firstOrNull()?.coordinate ?: LocationService.TACNA_HISTORIC_CENTER
        _uiState.update { state ->
            state.copy(
                selectedTab = MainAppTab.EXPLORE,
                mapCategory = MapFilterCategory.ROUTES,
                activeRouteOverlayOnMap = route,
                cameraFocus = CameraFocusCommand(
                    center = LocationService.sanitizedTacnaCoordinate(center),
                    zoom = 13.6,
                    nonce = state.cameraFocus.nonce + 1
                )
            )
        }
        BCFeedback.impactMedium(appContext)
    }

    fun clearRouteOverlayOnMap() {
        _uiState.update { it.copy(activeRouteOverlayOnMap = null) }
    }

    fun openRoutePlanner(
        destination: TacnaDestinationPlace? = null,
        origin: TacnaDestinationPlace? = null
    ) {
        _uiState.update { state ->
            state.copy(
                isRoutePlannerPresented = true,
                routePlannerInitialDestination = destination,
                routePlannerInitialOrigin = origin ?: TacnaDestinationPlace.currentLocationPlace(state.userLocation)
            )
        }
        BCFeedback.impactMedium(appContext)
    }

    fun closeRoutePlanner() {
        _uiState.update {
            it.copy(
                isRoutePlannerPresented = false,
                routePlannerInitialDestination = null
            )
        }
    }

    fun recordRecentSearchedPlace(place: TacnaDestinationPlace) {
        if (place.id == "current_gps") return
        val current = _uiState.value.recentSearchedPlaces.toMutableList()
        current.removeAll { it.id == place.id || it.name.equals(place.name, ignoreCase = true) }
        current.add(0, place)
        val trimmed = current.take(12)
        storage.saveRecentPlaces(trimmed)
        _uiState.update { it.copy(recentSearchedPlaces = trimmed) }
    }

    fun clearRecentSearchedPlaces() {
        storage.saveRecentPlaces(emptyList())
        _uiState.update { it.copy(recentSearchedPlaces = emptyList()) }
    }

    fun evaluateAutomatedRoutes(
        origin: TacnaDestinationPlace,
        destination: TacnaDestinationPlace
    ): RouteAutomationEvaluationResult {
        val state = _uiState.value
        return RouteAutomationEngine.evaluateRoutes(
            origin = origin,
            destination = destination,
            stops = state.dynamicCatalogStops,
            routes = state.dynamicRoutes,
            activeBuses = state.activeBuses
        )
    }

    fun startGuidedRoute(
        origin: TacnaDestinationPlace,
        destination: TacnaDestinationPlace,
        optionIndex: Int,
        candidate: EvaluatedRouteCandidate
    ) {
        val isOrdinary = candidate.kind == EvaluatedCandidateKind.ORDINARY_IN_SERVICE
        val initialSeconds = if (isOrdinary) max(candidate.busWaitMinutes * 60, 120) else 0
        val showBannerImmediate = isOrdinary && candidate.busWaitMinutes <= 5
        val guidance = ActiveRouteGuidanceState(
            origin = origin,
            destination = destination,
            selectedOptionIndex = optionIndex,
            candidate = candidate,
            remainingBusArrivalSeconds = initialSeconds,
            showArrivalTimer = isOrdinary
        )
        val midLat = (origin.latitude + destination.latitude) / 2.0
        val midLon = (origin.longitude + destination.longitude) / 2.0
        _uiState.update { state ->
            state.copy(
                selectedTab = MainAppTab.EXPLORE,
                isRoutePlannerPresented = false,
                activeRouteGuidance = guidance,
                searchedDestinationPin = null,
                showFiveMinuteBoardingBanner = showBannerImmediate,
                showExternalGuidancePopup = candidate.kind == EvaluatedCandidateKind.EXTERNAL_FREE_BOARDING,
                cameraFocus = CameraFocusCommand(
                    center = LocationService.sanitizedTacnaCoordinate(GeoPointData(midLat, midLon)),
                    zoom = 14.3,
                    nonce = state.cameraFocus.nonce + 1
                )
            )
        }
        if (showBannerImmediate) {
            notificationManager.showBusApproachingNotification(
                routeCode = candidate.routeCode,
                stopName = candidate.boardingPointName,
                minutesAway = max(1, candidate.busWaitMinutes)
            )
        }
        BCFeedback.success(appContext)
    }

    fun dismissFiveMinuteBanner() {
        _uiState.update { it.copy(showFiveMinuteBoardingBanner = false) }
    }

    fun dismissExternalGuidancePopup() {
        _uiState.update { it.copy(showExternalGuidancePopup = false) }
    }

    fun promptCancelGuidedRoute() {
        _uiState.update { it.copy(showCancelGuidanceConfirm = true) }
    }

    fun dismissCancelGuidancePrompt() {
        _uiState.update { it.copy(showCancelGuidanceConfirm = false) }
    }

    fun cancelGuidedRoute() {
        _uiState.update {
            it.copy(
                activeRouteGuidance = null,
                searchedDestinationPin = null,
                routePlannerInitialDestination = null,
                searchText = "",
                showFiveMinuteBoardingBanner = false,
                showExternalGuidancePopup = false,
                showCancelGuidanceConfirm = false
            )
        }
        notificationManager.cancelAll()
        BCFeedback.impactLight(appContext)
    }

    fun activateStopArrivalAlert(
        stop: BusStopModel,
        advanceMinutes: Int,
        imminentEnabled: Boolean
    ) {
        val alert = ArrivalAlertState(
            stopId = stop.id,
            stopName = stop.name,
            routeLine = stop.routeId,
            advanceMinutes = advanceMinutes,
            remainingSeconds = advanceMinutes * 60,
            imminentVibrationsEnabled = imminentEnabled
        )
        _uiState.update { it.copy(activeArrivalAlert = alert) }
        if (advanceMinutes <= 5) {
            notificationManager.showBusApproachingNotification(
                routeCode = stop.routeId,
                stopName = stop.name,
                minutesAway = advanceMinutes
            )
        }
        BCFeedback.success(appContext)
    }

    fun cancelArrivalAlert() {
        _uiState.update { it.copy(activeArrivalAlert = null) }
        notificationManager.cancelAll()
    }

    fun ordinaryRoutesPassing(place: TacnaDestinationPlace): List<TacnaOfficialRouteCatalogItem> {
        return place.routesPassing.mapNotNull { code -> routeItemForCode(code) }.filter { it.isOrdinary }
    }

    fun routeItemForCode(code: String): TacnaOfficialRouteCatalogItem? {
        val norm = code.replace("ruta ", "", ignoreCase = true).trim()
        return _uiState.value.dynamicRoutes.firstOrNull { route ->
            route.code.equals(code, ignoreCase = true) ||
                route.code.replace("ruta ", "", ignoreCase = true).trim().equals(norm, ignoreCase = true)
        }
    }

    fun notificationAvailability(place: TacnaDestinationPlace): StopNotificationAvailability {
        val ordRoutes = ordinaryRoutesPassing(place)
        if (ordRoutes.isEmpty()) return StopNotificationAvailability.NoOrdinaryRoutes
        val activeOrd = ordRoutes.filter { it.isInService }
        return if (activeOrd.isNotEmpty()) {
            StopNotificationAvailability.Available(activeOrd)
        } else {
            StopNotificationAvailability.OrdinaryOutOfService(ordRoutes)
        }
    }

    fun estimateTravelMinutes(place: TacnaDestinationPlace): Int {
        val origin = _uiState.value.userLocation
        val meters = origin.distanceMetersTo(place.coordinate)
        return max(4, (meters / 320.0).roundToInt())
    }

    suspend fun refreshStateFromBackend(force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force && (now - lastSyncEpochMs) < 180_000L && _uiState.value.dynamicCatalogStops.isNotEmpty()) {
            return
        }
        _uiState.update { it.copy(isSyncingCatalog = true) }
        try {
            val api = networkClient.service()
            val stopsResp = api.fetchStopsCatalog()
            val routesResp = api.fetchRoutesCatalog()
            val netResp = api.fetchTransitNetwork()

            val loadedStops = if (stopsResp.isSuccessful && !stopsResp.body().isNullOrEmpty()) {
                stopsResp.body()!!.also { storage.saveCachedStops(it) }
            } else {
                _uiState.value.dynamicCatalogStops
            }

            val loadedRoutes = if (routesResp.isSuccessful && !routesResp.body().isNullOrEmpty()) {
                routesResp.body()!!.also { storage.saveCachedRoutes(it) }
            } else {
                _uiState.value.dynamicRoutes
            }

            val netBody = if (netResp.isSuccessful) netResp.body() else null
            val clock = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
            lastSyncEpochMs = now
            _uiState.update {
                it.copy(
                    isSyncingCatalog = false,
                    dynamicCatalogStops = loadedStops,
                    dynamicRoutes = loadedRoutes,
                    stops = netBody?.stops ?: it.stops,
                    routes = netBody?.routes ?: it.routes,
                    activeBuses = netBody?.activeBuses ?: it.activeBuses,
                    lastSyncTimeLabel = clock,
                    syncStatusMessage = "Red de Tacna sincronizada ($clock)"
                )
            }
            evaluateInBusProximityAlert()
        } catch (_: Exception) {
            _uiState.update {
                it.copy(
                    isSyncingCatalog = false,
                    syncStatusMessage = "Modo offline activo (catálogo local de Tacna)"
                )
            }
        }
    }

    private fun startLiveTransitPolling() {
        viewModelScope.launch {
            while (true) {
                delay(4000L)
                if (_uiState.value.isLoggedIn || _uiState.value.isGuestMode) {
                    runCatching {
                        val netResp = networkClient.service().fetchTransitNetwork()
                        if (netResp.isSuccessful) {
                            val netBody = netResp.body()
                            if (netBody != null) {
                                _uiState.update {
                                    it.copy(
                                        activeBuses = netBody.activeBuses,
                                        stops = if (netBody.stops.isNotEmpty()) netBody.stops else it.stops,
                                        routes = if (netBody.routes.isNotEmpty()) netBody.routes else it.routes
                                    )
                                }
                                evaluateInBusProximityAlert()
                            }
                        }
                    }
                }
            }
        }
    }

    suspend fun rechargePoints(
        points: Int,
        gateway: String,
        reference: String?
    ): LedgerTransactionItem? {
        val user = _uiState.value.currentUser ?: return null
        if (points <= 0) return null
        val before = user.pointsBalance
        val after = before + points
        try {
            networkClient.service().rechargePoints(
                authHeader = storage.getAccessToken()?.let { "Bearer $it" },
                request = RechargeRequest(amountPoints = points, gateway = gateway, reference = reference)
            )
        } catch (_: Exception) {
        }
        storage.saveWalletPointsOverride(user.id, after)
        val timeLabel = SimpleDateFormat("dd MMM · HH:mm", Locale("es", "PE")).format(Date())
        val tx = LedgerTransactionItem(
            id = "tx_rec_${UUID.randomUUID().toString().take(8)}",
            title = "Recarga con $gateway",
            subtitle = if (reference.isNullOrBlank()) "Abono instantáneo a Monedero BC" else "Ref. operación: $reference",
            amountPoints = points,
            balanceBefore = before,
            balanceAfter = after,
            timestampLabel = timeLabel,
            kind = LedgerTransactionKind.RECHARGE
        )
        _uiState.update {
            it.copy(
                currentUser = user.copy(pointsBalance = after),
                ledgerTransactions = listOf(tx) + it.ledgerTransactions
            )
        }
        BCFeedback.success(appContext)
        return tx
    }

    fun submitCarnetReviewRequest(
        type: String,
        dni: String,
        institution: String,
        documentCode: String,
        expiresAt: String,
        qrPayload: String = "",
        frontPhotoBase64: String = ""
    ) {
        val user = _uiState.value.currentUser ?: return
        val req = CarnetReviewRequest(
            id = "carnet_${UUID.randomUUID().toString().take(6)}",
            requestedType = "STUDENT",
            dni = dni,
            institutionOrRegistry = institution.ifBlank { "Universidad Licenciada SUNEDU" },
            documentCode = documentCode.ifBlank { "SUNEDU-$dni" },
            expiresAt = expiresAt.ifBlank { "2026-12-31" },
            status = "ESPERANDO CONFIRMACIÓN ADMIN",
            submittedAtLabel = SimpleDateFormat("dd/MM/yyyy HH:mm", Locale("es", "PE")).format(Date())
        )
        storage.saveCarnetReviewRequest(user.id, req)
        _uiState.update {
            it.copy(carnetReviewRequests = listOf(req) + it.carnetReviewRequests.filterNot { r -> r.id == req.id })
        }
        BCFeedback.success(appContext)

        viewModelScope.launch(kotlinx.coroutines.Dispatchers.IO) {
            runCatching {
                val client = okhttp3.OkHttpClient()
                val jsonBody = org.json.JSONObject().apply {
                    put("user_id", user.id)
                    put("phone", user.phone)
                    put("passenger_name", user.displayName)
                    put("dni", dni)
                    put("university", institution)
                    put("expiry_date", expiresAt)
                    put("qr_payload", qrPayload.ifBlank { "SUNEDU|$dni|$institution|$expiresAt" })
                    put("front_photo_base64", frontPhotoBase64)
                }.toString()
                val mediaType = okhttp3.MediaType.Companion.run { "application/json; charset=utf-8".toMediaType() }
                val reqBody = okhttp3.RequestBody.Companion.run { jsonBody.toRequestBody(mediaType) }
                val httpReq = okhttp3.Request.Builder()
                    .url("https://34.30.86.129.sslip.io/api/v1/carnet/verify-sunedu")
                    .post(reqBody)
                    .build()
                client.newCall(httpReq).execute().use { resp ->
                    if (resp.isSuccessful) {
                        val raw = resp.body?.string().orEmpty()
                        val obj = org.json.JSONObject(raw).optJSONObject("request")
                        if (obj != null) {
                            val updated = req.copy(
                                dni = obj.optString("dni", dni),
                                institutionOrRegistry = obj.optString("university", req.institutionOrRegistry),
                                documentCode = obj.optString("carnet_code", req.documentCode),
                                expiresAt = obj.optString("expiry_date", req.expiresAt),
                                status = "ESPERANDO CONFIRMACIÓN ADMIN"
                            )
                            storage.saveCarnetReviewRequest(user.id, updated)
                            _uiState.update { st ->
                                st.copy(carnetReviewRequests = listOf(updated) + st.carnetReviewRequests.filterNot { r -> r.id == req.id })
                            }
                        }
                    }
                }
            }
        }
    }

    fun payPassageWithQr(qrPayload: String, companionsCount: Int) {
        val user = _uiState.value.currentUser
        if (user == null) {
            _uiState.update { it.copy(qrErrorMessage = "Inicia sesión para validar pasajes con QR.") }
            return
        }
        val cleanPayload = qrPayload.trim()
        val parts = cleanPayload.split("|")
        val isPosDynamic = parts.size == 8 && parts[0] == "BC-POS" && parts[1] == "v1"
        val isLegacyBus = parts.size >= 4 && parts[0] == "BC-BUS"
        if (!isPosDynamic && !isLegacyBus) {
            _uiState.update {
                it.copy(qrErrorMessage = "Código QR inválido. Escanea el QR oficial ubicado en la puerta del bus.")
            }
            BCFeedback.error(appContext)
            return
        }
        val unitNumber = if (isPosDynamic) parts[3] else parts[1]
        val plate = if (isPosDynamic) "POS" else parts[2]
        val lineNumber = if (isPosDynamic) unitNumber else parts[3]
        val fixedPosPoints = if (isPosDynamic) parts[6].toIntOrNull()?.takeIf { it > 0 } else null

        val isStudent = user.roleType == UserRoleType.STUDENT
        val nowMs = System.currentTimeMillis()

        // Control de reuso universitario:
        // Si pagó universitario hace menos de 2 minutos (120s), no se niega el pasaje:
        // se cobra tarifa general de 15 pts (S/. 1.50) y se coloca un aviso explicativo de espera de 2 min.
        val isStudentCooldownActive = if (isStudent) {
            val elapsedSec = (nowMs - lastStudentFareTimestampMs) / 1000L
            elapsedSec < 120L && lastStudentFareTimestampMs > 0L
        } else false

        val remainingCooldownSec = if (isStudentCooldownActive) {
            (120L - ((nowMs - lastStudentFareTimestampMs) / 1000L)).coerceAtLeast(1L)
        } else 0L

        val clampedCompanions = companionsCount.coerceIn(0, 4)
        val holderFare = when {
            isStudent && !isStudentCooldownActive -> 7 // Tarifa Universitaria SUNEDU (S/. 0.70)
            isStudent && isStudentCooldownActive -> 15 // Tarifa General Adulto aplicada por intervalo de 2 min
            else -> fixedPosPoints ?: user.roleType.farePoints
        }
        val companionsFare = clampedCompanions * 15 // Acompañantes siempre abonan tarifa general adulto
        val totalCost = holderFare + companionsFare

        if (user.pointsBalance < totalCost) {
            val missing = totalCost - user.pointsBalance
            _uiState.update {
                it.copy(
                    showInsufficientBalanceDialog = true,
                    insufficientBalanceDetail = "Necesitas $totalCost pts (S/. ${String.format(Locale.US, "%.2f", totalCost / 10.0)}). Te faltan $missing pts en tu Monedero BC."
                )
            }
            BCFeedback.error(appContext)
            return
        }

        if (isStudent && !isStudentCooldownActive) {
            lastStudentFareTimestampMs = nowMs
        }

        val before = user.pointsBalance
        val after = before - totalCost
        storage.saveWalletPointsOverride(user.id, after)

        val timeLabel = SimpleDateFormat("dd MMM · HH:mm", Locale("es", "PE")).format(Date())
        val tx = LedgerTransactionItem(
            id = "tx_qr_${UUID.randomUUID().toString().take(8)}",
            title = "Pasaje $lineNumber",
            subtitle = if (clampedCompanions > 0) "Titular + $clampedCompanions acomp. · $unitNumber" else "Validación QR · $unitNumber",
            amountPoints = -totalCost,
            balanceBefore = before,
            balanceAfter = after,
            timestampLabel = timeLabel,
            kind = LedgerTransactionKind.QR_PAYMENT,
            plateBadge = plate
        )
        val cleanLineNumber = if (lineNumber.contains("14") || unitNumber.contains("14")) "Ruta 14" else lineNumber
        val matchedRoute = _uiState.value.dynamicRoutes.firstOrNull { route ->
            route.title.contains(cleanLineNumber, ignoreCase = true) ||
            route.code.contains(cleanLineNumber, ignoreCase = true) ||
            cleanLineNumber.contains(route.code, ignoreCase = true)
        } ?: _uiState.value.dynamicRoutes.firstOrNull { it.code.contains("14") }

        val routeStops = matchedRoute?.resolvedStops(_uiState.value.dynamicCatalogStops)
        val center = routeStops?.firstOrNull()?.coordinate ?: LocationService.TACNA_HISTORIC_CENTER

        val destStop = _uiState.value.activeRouteGuidance?.destination
            ?: _uiState.value.searchedDestinationPin
            ?: routeStops?.lastOrNull()

        val trip = ActiveTripState(
            unitNumber = unitNumber,
            plate = plate,
            lineNumber = cleanLineNumber,
            pointsPaid = totalCost,
            companionsCount = clampedCompanions,
            remainingSeconds = 45 * 60,
            isConfirmedOnBoard = true,
            destinationStopName = destStop?.shortName,
            destinationLatitude = destStop?.coordinate?.latitude,
            destinationLongitude = destStop?.coordinate?.longitude
        )
        _uiState.update {
            it.copy(
                currentUser = user.copy(pointsBalance = after),
                ledgerTransactions = listOf(tx) + it.ledgerTransactions,
                activeTrip = trip,
                activeRouteOverlayOnMap = matchedRoute,
                mapCategory = MapFilterCategory.ROUTES,
                cameraFocus = CameraFocusCommand(
                    center = LocationService.sanitizedTacnaCoordinate(center),
                    zoom = 14.2,
                    nonce = it.cameraFocus.nonce + 1
                ),
                qrErrorMessage = null,
                qrSuccessMessage = if (isStudentCooldownActive) {
                    "Pagaste tarifa universitaria hace menos de 2 min. Se cobraron 15 pts (espera de ${remainingCooldownSec}s activa)."
                } else if (isStudent) {
                    "Pasaje universitario validado (7 pts / S/. 0.70) · $cleanLineNumber"
                } else {
                    "Pasaje validado ($totalCost pts) · $cleanLineNumber ($plate)"
                },
                selectedTab = MainAppTab.EXPLORE
            )
        }

        if (isPosDynamic) {
            viewModelScope.launch(kotlinx.coroutines.Dispatchers.IO) {
                try {
                    val authHeader = storage.getAccessToken()?.takeIf { it.isNotBlank() }?.let { "Bearer $it" }
                    val body = mapOf<String, Any>(
                        "qr_payload" to cleanPayload,
                        "companions_count" to clampedCompanions,
                        "user_id" to user.id,
                        "phone" to user.phone,
                        "user_role" to user.roleType.raw,
                        "is_student" to isStudent
                    )
                    networkClient.service().payQrPassage(authHeader, body)
                } catch (_: Exception) {
                }
            }
        }

        BCFeedback.success(appContext)
    }

    fun dismissInsufficientBalanceDialog() {
        _uiState.update { it.copy(showInsufficientBalanceDialog = false) }
    }

    fun clearQrMessages() {
        _uiState.update { it.copy(qrErrorMessage = null, qrSuccessMessage = null) }
    }

    fun endActiveTrip() {
        _uiState.update { it.copy(activeTrip = null) }
    }

    fun confirmOnBoardStatus(onBoard: Boolean) {
        val current = _uiState.value.activeTrip ?: return
        _uiState.update {
            it.copy(
                activeTrip = current.copy(isConfirmedOnBoard = onBoard),
                qrSuccessMessage = if (onBoard) {
                    "Suscrito a alertas de bajada en ${current.unitNumber}. Te avisaremos 200m antes de llegar."
                } else {
                    "Esperando unidad ${current.unitNumber} en paradero."
                }
            )
        }
        if (onBoard) {
            evaluateInBusProximityAlert()
        }
    }

    fun verifyAndSubscribeNearestBus() {
        val state = _uiState.value
        val userLoc = state.userLocation
        val candidates = state.activeBuses.map { bus ->
            bus to userLoc.distanceMetersTo(GeoPointData(bus.latitude, bus.longitude))
        }.sortedBy { it.second }

        val nearest = candidates.firstOrNull { it.second <= 120.0 }
        if (nearest == null) {
            _uiState.update {
                it.copy(
                    qrSuccessMessage = "No se detectó ningún bus a ≤ 120m de tu ubicación actual."
                )
            }
            return
        }

        val (bus, distMeters) = nearest
        val matchedRoute = state.dynamicRoutes.firstOrNull { route ->
            route.code.equals(bus.lineNumber, ignoreCase = true) ||
            bus.lineNumber.contains(route.code, ignoreCase = true) ||
            route.code.contains(bus.lineNumber, ignoreCase = true)
        } ?: state.dynamicRoutes.firstOrNull { it.code.contains("14") }

        val routeStops = matchedRoute?.resolvedStops(state.dynamicCatalogStops)
        val destStop = state.activeRouteGuidance?.destination
            ?: state.searchedDestinationPin
            ?: routeStops?.lastOrNull()

        val trip = ActiveTripState(
            unitNumber = bus.unitNumber,
            plate = bus.plate,
            lineNumber = bus.lineNumber,
            pointsPaid = 0,
            companionsCount = 0,
            remainingSeconds = 45 * 60,
            isConfirmedOnBoard = true,
            destinationStopName = destStop?.shortName ?: bus.nextStopName,
            destinationLatitude = destStop?.coordinate?.latitude,
            destinationLongitude = destStop?.coordinate?.longitude
        )

        _uiState.update {
            it.copy(
                activeTrip = trip,
                activeRouteOverlayOnMap = matchedRoute,
                mapCategory = MapFilterCategory.ROUTES,
                cameraFocus = CameraFocusCommand(
                    center = GeoPointData(bus.latitude, bus.longitude),
                    zoom = 15.6,
                    nonce = it.cameraFocus.nonce + 1
                ),
                qrSuccessMessage = "✓ Detectado a bordo de ${bus.unitNumber} (${distMeters.toInt()}m). Suscrito en tiempo real."
            )
        }
        BCFeedback.success(appContext)
    }

    private fun evaluateInBusProximityAlert() {
        val state = _uiState.value
        val trip = state.activeTrip ?: return
        if (trip.isConfirmedOnBoard != true || trip.proximityAlertTriggered) return
        val destLat = trip.destinationLatitude ?: return
        val destLon = trip.destinationLongitude ?: return

        val liveBus = state.activeBuses.firstOrNull { bus ->
            bus.unitNumber.equals(trip.unitNumber, ignoreCase = true) ||
            bus.plate.equals(trip.plate, ignoreCase = true)
        }
        val currentLat = liveBus?.latitude ?: state.userLocation.latitude
        val currentLon = liveBus?.longitude ?: state.userLocation.longitude

        val distanceMeters = GeoPointData(currentLat, currentLon).distanceMetersTo(
            GeoPointData(destLat, destLon)
        )
        if (distanceMeters <= 220.0) {
            _uiState.update {
                it.copy(
                    activeTrip = trip.copy(proximityAlertTriggered = true),
                    activeArrivalAlert = ArrivalAlertState(
                        stopId = "dest-alert",
                        stopName = trip.destinationStopName ?: "Tu paradero",
                        routeLine = trip.lineNumber,
                        advanceMinutes = 1,
                        remainingSeconds = 35,
                        imminentVibrationsEnabled = true
                    )
                )
            }
            BCFeedback.success(appContext)
        }
    }

    fun updateBackendHost(newHost: String) {
        storage.saveBackendHost(newHost)
        networkClient.invalidateRetrofitCache()
        _uiState.update { it.copy(backendHost = storage.getBackendHost()) }
        viewModelScope.launch { refreshStateFromBackend(force = true) }
    }

    fun resetCurrentAccountState() {
        val user = _uiState.value.currentUser ?: return
        storage.saveWalletPointsOverride(user.id, 0)
        storage.saveCarnetReviewRequest(user.id, null)
        _uiState.update {
            it.copy(
                currentUser = user.copy(pointsBalance = 0),
                ledgerTransactions = emptyList(),
                carnetReviewRequests = emptyList(),
                activeTrip = null
            )
        }
        BCFeedback.impactMedium(appContext)
    }

    fun logout() {
        otpCountdownJob?.cancel()
        storage.clearSession()
        _uiState.update {
            it.copy(
                isLoggedIn = false,
                isGuestMode = false,
                currentUser = null,
                currentStep = OnboardingStep.Splash,
                phoneNumber = "",
                otpCode = "",
                ledgerTransactions = emptyList(),
                activeTrip = null,
                activeRouteGuidance = null,
                activeArrivalAlert = null
            )
        }
    }

    fun filteredPredictivePlaces(query: String): List<TacnaDestinationPlace> {
        val clean = normalizeSearchFold(query.trim())
        val base = _uiState.value.dynamicCatalogStops
        if (clean.isEmpty()) return emptyList()
        val tokens = clean.split(Regex("\\s+")).filter { it.isNotEmpty() }
        return base.filter { place ->
            val hay = normalizeSearchFold("${place.name} ${place.shortName} ${place.subtitle} ${place.routesPassing.joinToString(" ")}")
            tokens.all { hay.contains(it) }
        }
    }

    companion object {
        fun normalizeSearchFold(raw: String): String {
            val normalized = Normalizer.normalize(raw.lowercase(Locale.ROOT), Normalizer.Form.NFD)
            return Regex("\\p{InCombiningDiacriticalMarks}+").replace(normalized, "")
        }
    }

    override fun onCleared() {
        super.onCleared()
        locationService.stopUpdates()
        otpCountdownJob?.cancel()
        liveLoopJob?.cancel()
    }
}

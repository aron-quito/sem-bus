package pe.edu.unjbg.busconectado.core.designsystem

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

object BCColors {
    val DarkBackground = Color(0xFF090D16)
    val ElevatedSurface = Color(0xFF0F172A)
    val CardSurface = Color(0xFF141E33)
    val SheetSurface = Color(0xFF171A21)
    val ControlSurface = Color(0xFF1F262E)
    val Emerald = Color(0xFF10B981)
    val RoyalBlue = Color(0xFF2563EB)
    val CyanAccent = Color(0xFF06B6D4)
    val SkyBlue = Color(0xFF38BDF8)
    val AppleBlue = Color(0xFF0A84FF)
    val Amber = Color(0xFFF59E0B)
    val YapePurple = Color(0xFF742384)
    val PlinTeal = Color(0xFF06B6D4)
    val DestructiveRed = Color(0xFFEF4444)
    val HairlineBorder = Color.White.copy(alpha = 0.12f)
    val TextSecondary = Color.White.copy(alpha = 0.68f)
    val TextMuted = Color.White.copy(alpha = 0.48f)

    fun fromHex(hex: String, fallback: Color = RoyalBlue): Color {
        return try {
            val cleaned = hex.trim().removePrefix("#")
            val argb = when (cleaned.length) {
                6 -> ("FF$cleaned").toLong(16).toInt()
                8 -> cleaned.toLong(16).toInt()
                else -> return fallback
            }
            Color(argb)
        } catch (_: Exception) {
            fallback
        }
    }
}

private val BCDarkColorScheme = darkColorScheme(
    primary = BCColors.RoyalBlue,
    onPrimary = Color.White,
    secondary = BCColors.Emerald,
    onSecondary = Color.Black,
    tertiary = BCColors.CyanAccent,
    background = BCColors.DarkBackground,
    onBackground = Color.White,
    surface = BCColors.ElevatedSurface,
    onSurface = Color.White,
    surfaceVariant = BCColors.CardSurface,
    onSurfaceVariant = Color.White.copy(alpha = 0.78f),
    error = BCColors.DestructiveRed,
    onError = Color.White
)

@Composable
fun BCMaterialTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = BCDarkColorScheme,
        content = content
    )
}

object BCFeedback {
    fun impactLight(context: Context) {
        vibrate(context, 14L, 70)
    }

    fun impactMedium(context: Context) {
        vibrate(context, 28L, 140)
    }

    fun success(context: Context) {
        vibrate(context, 42L, 200)
        playTone(ToneGenerator.TONE_PROP_ACK, 120)
    }

    fun warning(context: Context) {
        vibrate(context, 60L, 180)
        playTone(ToneGenerator.TONE_PROP_BEEP, 130)
    }

    fun error(context: Context) {
        vibrate(context, 90L, 240)
        playTone(ToneGenerator.TONE_PROP_NACK, 160)
    }

    private fun vibrate(context: Context, durationMs: Long, amplitude: Int) {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vm?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
            vibrator?.vibrate(VibrationEffect.createOneShot(durationMs, amplitude))
        } catch (_: Exception) {
        }
    }

    private fun playTone(tone: Int, durationMs: Int) {
        try {
            val tg = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 75)
            tg.startTone(tone, durationMs)
            Handler(Looper.getMainLooper()).postDelayed({ tg.release() }, durationMs + 60L)
        } catch (_: Exception) {
        }
    }
}

class SpeechSearchEngine(private val context: Context) {
    private val _isListening = MutableStateFlow(false)
    val isListening: StateFlow<Boolean> = _isListening.asStateFlow()

    private val _transcript = MutableStateFlow("")
    val transcript: StateFlow<String> = _transcript.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private var speechRecognizer: SpeechRecognizer? = null

    fun clearError() {
        _errorMessage.value = null
    }

    fun startListening(onResult: (String) -> Unit) {
        if (_isListening.value) {
            stopListening()
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(context)) {
            _errorMessage.value = "El reconocimiento de voz no está disponible en este dispositivo."
            return
        }
        try {
            speechRecognizer?.destroy()
            val recognizer = SpeechRecognizer.createSpeechRecognizer(context)
            speechRecognizer = recognizer
            recognizer.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {
                    _isListening.value = true
                    _errorMessage.value = null
                }

                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {
                    _isListening.value = false
                }

                override fun onError(error: Int) {
                    _isListening.value = false
                    _errorMessage.value = when (error) {
                        SpeechRecognizer.ERROR_NO_MATCH -> "No se escuchó un destino claro. Intenta de nuevo."
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Permite el micrófono para buscar por voz."
                        else -> "No se pudo iniciar la búsqueda por voz."
                    }
                }

                override fun onResults(results: Bundle?) {
                    _isListening.value = false
                    val spoken = results
                        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull()
                        ?.trim()
                        .orEmpty()
                    if (spoken.isNotEmpty()) {
                        _transcript.value = spoken
                        onResult(spoken)
                    }
                }

                override fun onPartialResults(partialResults: Bundle?) {
                    val partial = partialResults
                        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull()
                        ?.trim()
                        .orEmpty()
                    if (partial.isNotEmpty()) {
                        _transcript.value = partial
                        onResult(partial)
                    }
                }

                override fun onEvent(eventType: Int, params: Bundle?) {}
            })

            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "es-PE")
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            }
            _isListening.value = true
            recognizer.startListening(intent)
        } catch (_: Exception) {
            _isListening.value = false
            _errorMessage.value = "No se pudo activar el micrófono."
        }
    }

    fun stopListening() {
        try {
            speechRecognizer?.stopListening()
        } catch (_: Exception) {
        }
        _isListening.value = false
    }

    fun release() {
        try {
            speechRecognizer?.destroy()
        } catch (_: Exception) {
        }
        speechRecognizer = null
    }
}


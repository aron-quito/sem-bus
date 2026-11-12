package pe.edu.unjbg.busconectado.feature.driver

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.sin

/**
 * Generador nativo de pitidos y buzzers para validación en cabina de chofer.
 * Emula la respuesta acústica de los torniquetes y validadores POS de transporte urbano.
 */
class DriverAudioBuzzer {

    private val scope = CoroutineScope(Dispatchers.Default)

    /**
     * Tono Verde (880 Hz): Confirmación de pasaje validado exitosamente.
     */
    fun playSuccessBeep() {
        scope.launch {
            playTone(frequencyHz = 880.0, durationMs = 380, volume = 0.85f)
        }
    }

    /**
     * Tono Rojo (Doble Buzzer 300 Hz -> 210 Hz): Alerta grave de saldo insuficiente o rechazo.
     */
    fun playErrorBuzzer() {
        scope.launch {
            playTone(frequencyHz = 300.0, durationMs = 140, volume = 0.95f)
            delay(40)
            playTone(frequencyHz = 210.0, durationMs = 150, volume = 0.95f)
        }
    }

    private fun playTone(frequencyHz: Double, durationMs: Int, volume: Float) {
        val sampleRate = 44100
        val numSamples = (sampleRate * (durationMs / 1000.0)).toInt()
        val buffer = ShortArray(numSamples)

        for (i in 0 until numSamples) {
            // Forma de onda con caída suave al final para evitar chasquidos ("clicks")
            val envelope = if (i > numSamples * 0.8) {
                ((numSamples - i).toFloat() / (numSamples * 0.2f)).coerceIn(0f, 1f)
            } else {
                1.0f
            }
            val angle = 2.0 * Math.PI * i / (sampleRate / frequencyHz)
            buffer[i] = (sin(angle) * Short.MAX_VALUE * volume * envelope).toInt().toShort()
        }

        try {
            val audioTrack = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setBufferSizeInBytes(buffer.size * 2)
                .setTransferMode(AudioTrack.MODE_STATIC)
                .build()

            audioTrack.write(buffer, 0, buffer.size)
            audioTrack.play()

            // Liberar memoria al terminar la reproducción
            scope.launch {
                delay(durationMs.toLong() + 50)
                audioTrack.stop()
                audioTrack.release()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}


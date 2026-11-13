package pe.edu.unjbg.busconectado.pos.ui

import android.media.AudioManager
import android.media.ToneGenerator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

object PosValidatorSound {
    fun playSuccessBeep() {
        CoroutineScope(Dispatchers.Default).launch {
            try {
                val tone = ToneGenerator(AudioManager.STREAM_MUSIC, 90)
                tone.startTone(ToneGenerator.TONE_PROP_ACK, 240)
                delay(300)
                tone.release()
            } catch (_: Exception) {
            }
        }
    }

    fun playRejectedBeep() {
        CoroutineScope(Dispatchers.Default).launch {
            try {
                val tone = ToneGenerator(AudioManager.STREAM_MUSIC, 90)
                tone.startTone(ToneGenerator.TONE_PROP_NACK, 200)
                delay(240)
                tone.startTone(ToneGenerator.TONE_PROP_NACK, 240)
                delay(300)
                tone.release()
            } catch (_: Exception) {
            }
        }
    }
}


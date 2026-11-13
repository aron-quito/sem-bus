package pe.edu.unjbg.busconectado.pos

import android.app.PendingIntent
import android.content.Intent
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.mutableStateOf
import pe.edu.unjbg.busconectado.pos.data.PosNetworkRepository
import pe.edu.unjbg.busconectado.pos.ui.PosTerminalScreen

class MainActivity : ComponentActivity() {
    private var nfcAdapter: NfcAdapter? = null
    private val lastNfcUid = mutableStateOf<String?>(null)
    private val repository by lazy { PosNetworkRepository() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        nfcAdapter = NfcAdapter.getDefaultAdapter(this)

        setContent {
            PosTerminalScreen(
                repository = repository,
                nfcSupported = nfcAdapter != null,
                lastNfcUid = lastNfcUid.value,
                onClearNfcUid = { lastNfcUid.value = null }
            )
        }
    }

    override fun onResume() {
        super.onResume()
        val intent = Intent(this, javaClass).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
        val pendingIntent = PendingIntent.getActivity(this, 0, intent, flags)
        nfcAdapter?.enableForegroundDispatch(this, pendingIntent, null, null)
    }

    override fun onPause() {
        super.onPause()
        nfcAdapter?.disableForegroundDispatch(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == NfcAdapter.ACTION_TAG_DISCOVERED ||
            intent.action == NfcAdapter.ACTION_TECH_DISCOVERED ||
            intent.action == NfcAdapter.ACTION_NDEF_DISCOVERED
        ) {
            @Suppress("DEPRECATION")
            val tag: Tag? = intent.getParcelableExtra(NfcAdapter.EXTRA_TAG)
            val uidHex = tag?.id?.joinToString("") { "%02X".format(it) }
            if (!uidHex.isNullOrBlank()) {
                lastNfcUid.value = uidHex
            }
        }
    }
}


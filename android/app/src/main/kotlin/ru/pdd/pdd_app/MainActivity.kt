package ru.pdd.pdd_app

import android.media.AudioManager
import android.telephony.TelephonyManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.android.FlutterActivity
import java.util.Locale

class MainActivity : FlutterActivity() {
    private var appUpdates: AppUpdatesBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        appUpdates?.close()
        appUpdates = AppUpdatesBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        // Страна устройства для выбора способа оплаты (Dart: device_region.dart).
        // Сначала сеть оператора — там телефон реально подключён; VPN её не
        // меняет. Запасные варианты — SIM и системная локаль.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pdd/device_region").setMethodCallHandler { call, result ->
            if (call.method != "countryCode") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val telephony = getSystemService(TELEPHONY_SERVICE) as? TelephonyManager
            val network = telephony?.networkCountryIso?.takeIf { it.isNotEmpty() }
            val sim = telephony?.simCountryIso?.takeIf { it.isNotEmpty() }
            val locale = Locale.getDefault().country.takeIf { it.isNotEmpty() }
            result.success(network ?: sim ?: locale)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pdd/acquisition").setMethodCallHandler { call, result ->
            if (call.method != "installReferrer") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val handler = Handler(Looper.getMainLooper())
            val client = InstallReferrerClient.newBuilder(this).build()
            var completed = false
            fun finish(value: String?) {
                if (completed) return
                completed = true
                try { client.endConnection() } catch (_: Exception) {}
                result.success(value)
            }
            val timeout = Runnable { finish(null) }
            handler.postDelayed(timeout, 3000)
            try {
                client.startConnection(object : InstallReferrerStateListener {
                    override fun onInstallReferrerSetupFinished(code: Int) {
                        handler.post {
                            if (completed) return@post
                            handler.removeCallbacks(timeout)
                            try {
                                finish(if (code == InstallReferrerClient.InstallReferrerResponse.OK) client.installReferrer.installReferrer else null)
                            } catch (_: Exception) { finish(null) }
                        }
                    }
                    override fun onInstallReferrerServiceDisconnected() { handler.post { finish(null) } }
                })
            } catch (_: Exception) {
                handler.removeCallbacks(timeout)
                finish(null)
            }
        }
    }

    override fun onDestroy() {
        appUpdates?.close()
        appUpdates = null
        super.onDestroy()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        volumeControlStream = AudioManager.STREAM_MUSIC
    }
}

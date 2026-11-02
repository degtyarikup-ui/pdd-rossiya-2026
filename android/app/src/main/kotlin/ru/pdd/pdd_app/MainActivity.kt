package ru.pdd.pdd_app

import android.media.AudioManager
import android.telephony.TelephonyManager
import android.os.Bundle
import com.google.android.gms.common.GoogleApiAvailability
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterActivity
import java.util.Locale

class MainActivity : FlutterActivity() {
    private var appUpdates: AppUpdatesBridge? = null
    private var godotGame: GodotGameBridge? = null

    @Deprecated("Activity results of the game screen")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        if (godotGame?.onResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        appUpdates?.close()
        appUpdates = AppUpdatesBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        godotGame = GodotGameBridge(this, flutterEngine.dartExecutor.binaryMessenger)
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
        // Вход через Google работает только с сервисами Google Play (Dart:
        // auth_service.dart). Без них окно входа возвращается пустым, и
        // человек видел безликую ошибку sign_in_failed.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pdd/google_services").setMethodCallHandler { call, result ->
            if (call.method != "status") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            result.success(GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(this))
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pdd/build_info").setMethodCallHandler { call, result ->
            if (call.method == "gitCommit") {
                val resId = resources.getIdentifier("git_commit", "string", packageName)
                val commit = if (resId != 0) getString(resId) else ""
                result.success(commit)
            } else {
                result.notImplemented()
            }
        }
        AcquisitionBridge(this, flutterEngine.dartExecutor.binaryMessenger)
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

package ru.pdd.pdd_app

import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import ru.rustore.sdk.install.referrer.InstallReferrerClient as RuStoreReferrerClient

/** Reads only the selected store's referrer; an absent value stays unknown. */
class AcquisitionBridge(context: Context, messenger: BinaryMessenger) {
    private val context = context.applicationContext
    private val handler = Handler(Looper.getMainLooper())

    init {
        MethodChannel(messenger, "pdd/acquisition").setMethodCallHandler { call, result ->
            when (call.method) {
                "installReferrer" -> {
                    if (installer() == "com.android.vending") readPlay(result)
                    else result.success(null)
                }
                "rustoreInstallReferrer" -> {
                    if (installer() == "ru.vk.store") readRuStore(result)
                    else result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun installer(): String? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            context.packageManager.getInstallSourceInfo(context.packageName).installingPackageName
        } else {
            context.packageManager.getInstallerPackageName(context.packageName)
        }
    } catch (_: Exception) { null }

    private fun readPlay(result: MethodChannel.Result) {
        val client = InstallReferrerClient.newBuilder(context).build()
        var completed = false
        lateinit var timeout: Runnable
        fun finish(value: String?) {
            if (completed) return
            completed = true
            handler.removeCallbacks(timeout)
            try { client.endConnection() } catch (_: Exception) {}
            result.success(boundedReferrer(value))
        }
        timeout = Runnable { finish(null) }
        handler.postDelayed(timeout, 3000)
        try {
            client.startConnection(object : InstallReferrerStateListener {
                override fun onInstallReferrerSetupFinished(code: Int) {
                    handler.post {
                        if (completed) return@post
                        try {
                            finish(if (code == InstallReferrerClient.InstallReferrerResponse.OK)
                                client.installReferrer.installReferrer else null)
                        } catch (_: Exception) { finish(null) }
                    }
                }
                override fun onInstallReferrerServiceDisconnected() {
                    handler.post { finish(null) }
                }
            })
        } catch (_: Exception) { finish(null) }
    }

    private fun readRuStore(result: MethodChannel.Result) {
        val prefs = context.getSharedPreferences("pdd_acquisition", Context.MODE_PRIVATE)
        val saved = boundedReferrer(prefs.getString("rustore_referrer_v1", null))
        if (saved != null) {
            result.success(saved)
            return
        }
        var completed = false
        lateinit var timeout: Runnable
        fun finish(value: String?) {
            if (completed) return
            completed = true
            handler.removeCallbacks(timeout)
            result.success(value)
        }
        timeout = Runnable { finish(null) }
        handler.postDelayed(timeout, 3000)
        try {
            RuStoreReferrerClient(context).getInstallReferrerV2()
                .addOnSuccessListener { details ->
                    handler.post {
                        val raw = boundedReferrer(
                            details?.takeIf { it.isFromRuStore }?.installReferrer
                        )
                        // Some store versions consume the referral on first read.
                        // Save before replying, including a response after timeout.
                        if (raw != null) prefs.edit().putString("rustore_referrer_v1", raw).commit()
                        finish(raw)
                    }
                }
                .addOnFailureListener { handler.post { finish(null) } }
        } catch (_: Exception) { finish(null) }
    }

    /** Only campaign fields may cross into Flutter or the persistent cache. */
    private fun boundedReferrer(raw: String?): String? {
        if (raw.isNullOrEmpty() || raw.length > 8192) return null
        return try {
            val input = Uri.parse("?$raw")
            val output = Uri.Builder()
            val token = Regex("^[A-Za-z0-9._-]{1,64}$")
            var hasSource = false
            for (key in listOf("utm_source", "utm_medium", "utm_campaign", "utm_content")) {
                val value = input.getQueryParameter(key) ?: continue
                if (token.matches(value) && value !in listOf("__proto__", "constructor", "prototype")) {
                    output.appendQueryParameter(key, value)
                    if (key == "utm_source") hasSource = true
                }
            }
            input.getQueryParameter("ref")?.let { value ->
                if (Regex("^[A-Za-z0-9._:-]{1,128}$").matches(value)) {
                    output.appendQueryParameter("ref", value)
                    hasSource = true
                }
            }
            input.getQueryParameter("landing_page")?.substringBefore('?')?.substringBefore('#')?.let { path ->
                if (path.startsWith("/") && !path.startsWith("//") && path.length <= 240 &&
                    path.none { it <= ' ' || it == '\\' || it == '<' || it == '>' }) {
                    output.appendQueryParameter("landing_page", path)
                }
            }
            input.getQueryParameter("referrer_host")?.lowercase(Locale.ROOT)?.let { host ->
                if (host.length <= 160 && !host.contains("..") &&
                    Regex("^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$").matches(host)) {
                    output.appendQueryParameter("referrer_host", host)
                }
            }
            if (hasSource) output.build().encodedQuery else null
        } catch (_: Exception) { null }
    }
}

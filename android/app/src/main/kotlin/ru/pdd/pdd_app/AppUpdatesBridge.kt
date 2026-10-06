package ru.pdd.pdd_app

import android.app.Activity
import android.os.Build
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Optional Play update flow. Never restarts the app without a Flutter button tap. */
class AppUpdatesBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val manager = AppUpdateManagerFactory.create(activity)
    private val channel = MethodChannel(messenger, "pdd/app_updates")
    private var closed = false
    private var starting = false
    private val listener = InstallStateUpdatedListener { state ->
        if (!closed && state.installStatus() == InstallStatus.DOWNLOADED) {
            channel.invokeMethod("downloaded", null)
        }
    }

    init {
        manager.registerListener(listener)
        channel.setMethodCallHandler { call, result ->
            if (closed || !installedFromPlay()) {
                result.success(null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "check" -> manager.appUpdateInfo.addOnSuccessListener { info ->
                    if (!closed) result.success(mapOf(
                        "available" to (info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE),
                        "build" to info.availableVersionCode(),
                        "flexible" to info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE),
                        "downloaded" to (info.installStatus() == InstallStatus.DOWNLOADED),
                        "downloading" to (info.installStatus() == InstallStatus.DOWNLOADING || info.installStatus() == InstallStatus.PENDING)
                    ))
                }.addOnFailureListener { if (!closed) result.success(null) }
                "start" -> {
                    if (starting) { result.success("cancelled"); return@setMethodCallHandler }
                    starting = true
                    // Fresh AppUpdateInfo for each attempt; Play validates user eligibility.
                    manager.appUpdateInfo.addOnSuccessListener { info ->
                        if (closed) return@addOnSuccessListener
                        if (info.updateAvailability() != UpdateAvailability.UPDATE_AVAILABLE || !info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE)) {
                            starting = false
                            result.success("unavailable")
                        } else {
                            manager.startUpdateFlow(info, activity, AppUpdateOptions.newBuilder(AppUpdateType.FLEXIBLE).build())
                                .addOnSuccessListener { code ->
                                    starting = false
                                    if (!closed) result.success(if (code == Activity.RESULT_OK) "accepted" else "cancelled")
                                }.addOnFailureListener {
                                    starting = false
                                    if (!closed) result.success("failed")
                                }
                        }
                    }.addOnFailureListener {
                        starting = false
                        if (!closed) result.success("failed")
                    }
                }
                "complete" -> manager.appUpdateInfo.addOnSuccessListener { info ->
                    if (closed) return@addOnSuccessListener
                    if (info.installStatus() != InstallStatus.DOWNLOADED) result.success(false)
                    else manager.completeUpdate().addOnSuccessListener { if (!closed) result.success(true) }
                        .addOnFailureListener { if (!closed) result.success(false) }
                }.addOnFailureListener { if (!closed) result.success(false) }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun installedFromPlay(): Boolean = try {
        val installer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.packageManager.getInstallSourceInfo(activity.packageName).installingPackageName
        } else activity.packageManager.getInstallerPackageName(activity.packageName)
        installer == "com.android.vending"
    } catch (_: Exception) { false }

    fun close() {
        closed = true
        manager.unregisterListener(listener)
        channel.setMethodCallHandler(null)
    }
}

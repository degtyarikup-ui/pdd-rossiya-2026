package ru.pdd.pdd_app

import android.app.Service
import android.content.Intent
import android.os.Binder
import android.os.IBinder

/** The visible :game Activity binds to its Flutter host process while in use.
 * Without a binding Android caches/freezes the stopped Flutter Activity, so
 * asynchronous ResultReceiver requests (voice, reports) stop being delivered.
 * No foreground service, background work, wake lock or notification is needed.
 * https://source.android.com/docs/core/architecture/ipc/binder-freezer
 */
class GameHostService : Service() {
    private val binder = Binder()
    override fun onBind(intent: Intent): IBinder = binder
}

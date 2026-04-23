package com.invisible.invisible

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Foreground Service che mantiene l'app viva in background su Android.
 *
 * Senza questo servizio Android può killare il processo dopo pochi minuti
 * in background, interrompendo il WebSocket con il relay e impedendo la
 * ricezione dei messaggi offline.
 *
 * NON usa FCM/Google — la ricezione avviene direttamente tramite il
 * WebSocket persistente già aperto da InvisibleClient.
 *
 * Lifecycle:
 *   - START: chiamato da Flutter via MethodChannel quando l'utente fa login
 *   - STOP:  chiamato da Flutter via MethodChannel al logout o alla chiusura
 */
class RelayForegroundService : Service() {

    companion object {
        const val CHANNEL_ID    = "invisible_relay"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START  = "com.invisible.invisible.START_RELAY"
        const val ACTION_STOP   = "com.invisible.invisible.STOP_RELAY"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            else -> startForegroundNotification()
        }
        // START_STICKY: se Android killa il processo, lo riavvia automaticamente
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startForegroundNotification() {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Invisible")
            .setContentText("Connessione sicura attiva")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pendingIntent)
            .setOngoing(true)          // non rimuovibile dall'utente
            .setSilent(true)           // nessun suono/vibrazione
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        startForeground(NOTIFICATION_ID, notification)
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Connessione relay",
            NotificationManager.IMPORTANCE_LOW,  // nessun suono
        ).apply {
            description = "Mantiene attiva la ricezione messaggi in background"
            setShowBadge(false)
        }
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(channel)
    }
}

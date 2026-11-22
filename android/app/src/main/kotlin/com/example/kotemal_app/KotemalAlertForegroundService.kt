package com.example.kotemal_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

class KotemalAlertForegroundService : Service() {
    companion object {
        private const val CHANNEL_ID = "kotemal_alerts_channel"
        private const val NOTIFICATION_ID = 2026
        private const val WAKE_LOCK_TAG = "kotemal:alert_wakelock"
        private const val PING_WAKE_LOCK_TAG = "kotemal:alert_ping_wakelock"
        const val ACTION_ALERT_PING = "com.example.kotemal_app.ALERT_PING"

        fun ping(context: Context) {
            val intent = Intent(context, KotemalAlertForegroundService::class.java).apply {
                action = ACTION_ALERT_PING
            }
            ContextCompat.startForegroundService(context, intent)
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var pingWakeLock: PowerManager.WakeLock? = null
    private var alertRingtone: Ringtone? = null
    private var audioManager: AudioManager? = null

    private val audioFocusListener = AudioManager.OnAudioFocusChangeListener { }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundWithNotification()
        acquireWakeLock()

        if (intent?.action == ACTION_ALERT_PING) {
            playAlertPing()
        }

        return START_STICKY
    }

    private fun startForegroundWithNotification() {
        createNotificationChannel()

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("K'OTEMAL Activo")
            .setContentText("Escuchando nuevos pedidos en tiempo real")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setSilent(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Alertas K'OTEMAL",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Escucha de nuevos pedidos en tiempo real"
                setSound(null, null)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG)
            .apply {
                setReferenceCounted(false)
                acquire()
            }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {}
        wakeLock = null
    }

    @Suppress("DEPRECATION")
    private fun playAlertPing() {
        // Despierta brevemente la pantalla y mantiene la CPU activa.
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            pingWakeLock = powerManager
                .newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    PING_WAKE_LOCK_TAG
                )
                .apply {
                    setReferenceCounted(false)
                    acquire(6000L)
                }
        } catch (_: Exception) {}

        // Solicita foco de audio para que el tono suene aunque la Activity esté pausada.
        try {
            val manager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioManager = manager
            manager.requestAudioFocus(
                audioFocusListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
            )
        } catch (_: Exception) {}

        try {
            alertRingtone?.stop()
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val ringtone = RingtoneManager.getRingtone(this, uri)
            ringtone?.audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            ringtone?.play()
            alertRingtone = ringtone
        } catch (_: Exception) {}

        Handler(Looper.getMainLooper()).postDelayed({
            try {
                alertRingtone?.stop()
            } catch (_: Exception) {}
            alertRingtone = null

            try {
                audioManager?.abandonAudioFocus(audioFocusListener)
            } catch (_: Exception) {}
            audioManager = null

            try {
                if (pingWakeLock?.isHeld == true) {
                    pingWakeLock?.release()
                }
            } catch (_: Exception) {}
            pingWakeLock = null
        }, 6000L)
    }

    override fun onDestroy() {
        try {
            alertRingtone?.stop()
        } catch (_: Exception) {}
        alertRingtone = null

        try {
            if (pingWakeLock?.isHeld == true) {
                pingWakeLock?.release()
            }
        } catch (_: Exception) {}
        pingWakeLock = null

        releaseWakeLock()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}

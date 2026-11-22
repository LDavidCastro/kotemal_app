package com.example.kotemal_app

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "kotemal/ringtones"
    private val backgroundChannelName = "kotemal/background_alerts"
    private var currentRingtone: Ringtone? = null
    private val audioManager by lazy {
        getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }
    private val audioFocusListener = AudioManager.OnAudioFocusChangeListener { }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getNotificationRingtones" -> {
                        try {
                            result.success(getNotificationRingtones())
                        } catch (e: Exception) {
                            result.error("RINGTONES_ERROR", e.message, null)
                        }
                    }
                    "playRingtone" -> {
                        try {
                            val uri = call.argument<String>("uri")
                            playRingtone(uri)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("PLAY_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, backgroundChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startBackgroundService" -> {
                        try {
                            ContextCompat.startForegroundService(
                                this,
                                Intent(this, KotemalAlertForegroundService::class.java)
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("FOREGROUND_SERVICE_ERROR", e.message, null)
                        }
                    }
                    "stopBackgroundService" -> {
                        try {
                            stopService(
                                Intent(this, KotemalAlertForegroundService::class.java)
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("FOREGROUND_SERVICE_ERROR", e.message, null)
                        }
                    }
                    "pingAlert" -> {
                        try {
                            KotemalAlertForegroundService.ping(this)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("FOREGROUND_SERVICE_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun getNotificationRingtones(): List<Map<String, String>> {
        val manager = RingtoneManager(this)
        manager.setType(RingtoneManager.TYPE_NOTIFICATION)
        val cursor = manager.cursor ?: return emptyList()
        val ringtones = mutableListOf<Map<String, String>>()
        while (cursor.moveToNext()) {
            val title = cursor.getString(RingtoneManager.TITLE_COLUMN_INDEX) ?: continue
            val uri = manager.getRingtoneUri(cursor.position)?.toString() ?: continue
            ringtones.add(mapOf("title" to title, "uri" to uri))
        }

        val classicRingtones = listOf(
            "Alpha", "Been One", "Bells", "Cassiopeia", "Concertina",
            "Conclusion", "Contact", "Cosmic Radio", "Crescent", "Crystal",
            "Glitter", "Guitar", "Lucid", "Meteor", "Red Dwarf",
            "Signal", "Transmitter", "Arcade", "Breezy Dream",
            "Crystal Echo", "Fall Stroll", "Finding Galaxy"
        )

        return ringtones.sortedWith(
            compareBy<Map<String, String>> { item ->
                val title = item["title"] ?: ""
                val index = classicRingtones.indexOfFirst { classic ->
                    classic.equals(title, ignoreCase = true)
                }
                if (index >= 0) index else Int.MAX_VALUE
            }.thenBy { it["title"] ?: "" }
        )
    }

    @Suppress("DEPRECATION")
    private fun playRingtone(uriString: String?) {
        try {
            currentRingtone?.stop()
        } catch (_: Exception) {}
        currentRingtone = null

        try {
            audioManager.requestAudioFocus(
                audioFocusListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
            )
        } catch (_: Exception) {}

        val uri: Uri? = if (!uriString.isNullOrBlank()) {
            Uri.parse(uriString)
        } else {
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        }

        val ringtone = (uri?.let { RingtoneManager.getRingtone(this, it) })
            ?: RingtoneManager.getRingtone(
                this,
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            ) ?: return

        ringtone.audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        ringtone.play()
        currentRingtone = ringtone

        Handler(Looper.getMainLooper()).postDelayed({
            try {
                currentRingtone?.stop()
            } catch (_: Exception) {}
            currentRingtone = null
            try {
                audioManager.abandonAudioFocus(audioFocusListener)
            } catch (_: Exception) {}
        }, 6000L)
    }

    override fun onDestroy() {
        try {
            currentRingtone?.stop()
        } catch (_: Exception) {}
        currentRingtone = null
        super.onDestroy()
    }
}

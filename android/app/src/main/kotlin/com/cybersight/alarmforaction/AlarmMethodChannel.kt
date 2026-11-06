package com.cybersight.alarmforaction

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class AlarmMethodChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val appContext = activity.applicationContext
    private val scheduler = AlarmScheduler(appContext)
    private val permissionManager = PermissionManager(appContext)
    private val videoReader = VideoMetadataReader(appContext)
    private val audioPreview = AudioPreviewPlayer(appContext)

    // MediaMetadataRetriever spins up a real decoder — tens to hundreds of
    // ms per video. MethodChannel handlers run on the Android main thread,
    // so doing that inline froze input/rendering (visible jank + ANR
    // warnings) whenever the alarm list validated its videos. All metadata
    // work goes through this single background worker instead; results are
    // posted back to the main thread as MethodChannel requires.
    private val metadataExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private fun respondOffMainThread(result: MethodChannel.Result, block: () -> Any?) {
        metadataExecutor.execute {
            val outcome = runCatching(block)
            mainHandler.post {
                outcome.fold(
                    { result.success(it) },
                    { result.error("MOTIVALARM_NATIVE_ERROR", it.message, null) }
                )
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "scheduleAlarm", "updateAlarm" -> {
                    val args = call.arguments as Map<*, *>
                    val alarm = AlarmData.fromMap(args)
                    // Optional explicit trigger (epoch millis) — used by the
                    // Timetable's today-only shift/skip. Absent = the normal
                    // next-occurrence computation, identical to before.
                    val triggerAtMillis = (args["triggerAtMillis"] as? Number)?.toLong()
                    if (triggerAtMillis != null) {
                        scheduler.schedule(alarm, triggerAtMillis)
                    } else {
                        scheduler.schedule(alarm)
                    }
                    result.success(null)
                }
                "cancelAlarm" -> {
                    scheduler.cancel(call.argument<String>("alarmId") ?: "")
                    result.success(null)
                }
                "snoozeAlarm" -> {
                    scheduler.snooze(
                        call.argument<String>("alarmId") ?: "",
                        call.argument<Int>("minutes") ?: 5
                    )
                    result.success(null)
                }
                "stopAlarm" -> {
                    scheduler.stop(call.argument<String>("alarmId") ?: "")
                    result.success(null)
                }
                "getNextAlarmTime" -> result.success(scheduler.getNextAlarmTime())
                "previewAlarm" -> {
                    val alarm = AlarmData.fromMap(call.arguments as Map<*, *>)
                    AlarmStore(appContext).upsert(alarm)
                    val serviceIntent = Intent(appContext, AlarmForegroundService::class.java)
                        .setAction(AlarmForegroundService.ACTION_START)
                        .putExtra(AlarmScheduler.EXTRA_ALARM_ID, alarm.id)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        appContext.startForegroundService(serviceIntent)
                    } else {
                        appContext.startService(serviceIntent)
                    }
                    val activityIntent = Intent(appContext, AlarmRingActivity::class.java)
                        .putExtra(AlarmScheduler.EXTRA_ALARM_ID, alarm.id)
                        .putExtra(AlarmRingActivity.EXTRA_IS_PREVIEW, true)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    appContext.startActivity(activityIntent)
                    result.success(null)
                }
                "getPermissionStatuses" -> result.success(permissionManager.getStatuses())
                "canScheduleExactAlarms" -> result.success(permissionManager.canScheduleExactAlarms())
                "hasNotificationPermission" -> result.success(permissionManager.hasNotificationPermission())
                "isIgnoringBatteryOptimizations" -> result.success(permissionManager.isIgnoringBatteryOptimizations())
                "openFullScreenIntentSettings" -> {
                    permissionManager.openFullScreenIntentSettings()
                    result.success(null)
                }
                "openBackgroundRestrictionSettings" -> {
                    permissionManager.openBackgroundRestrictionSettings()
                    result.success(null)
                }
                "openUrl" -> {
                    permissionManager.openUrl(call.argument<String>("url") ?: "")
                    result.success(null)
                }
                "getVideoDuration" -> {
                    val uri = call.argument<String>("uri") ?: ""
                    respondOffMainThread(result) { videoReader.getDurationSeconds(uri) }
                }
                "validateVideo" -> {
                    val uri = call.argument<String>("uri") ?: ""
                    respondOffMainThread(result) { videoReader.validate(uri) }
                }
                "persistVideoUriPermission" -> {
                    videoReader.persistUriPermission(call.argument<String>("uri") ?: "")
                    result.success(null)
                }
                "persistMediaUriPermission" -> {
                    videoReader.persistUriPermission(call.argument<String>("uri") ?: "")
                    result.success(null)
                }
                "previewAudio" -> {
                    audioPreview.play(call.argument<String>("uri") ?: "")
                    result.success(null)
                }
                "previewDefaultAlarmTone" -> {
                    audioPreview.playDefaultAlarmTone()
                    result.success(null)
                }
                "stopAudioPreview" -> {
                    audioPreview.stop()
                    result.success(null)
                }
                "startTimerAlert" -> {
                    audioPreview.startTimerAlert()
                    result.success(null)
                }
                "stopTimerAlert" -> {
                    audioPreview.stopTimerAlert()
                    result.success(null)
                }
                "isBootReceiverEnabled" -> result.success(permissionManager.isBootReceiverEnabled())
                "getRingTimeoutMinutes" -> result.success(RingSettings.timeoutMinutes(appContext))
                "setRingTimeoutMinutes" -> {
                    RingSettings.setTimeoutMinutes(appContext, call.argument<Int>("minutes") ?: RingSettings.DEFAULT_TIMEOUT_MINUTES)
                    result.success(null)
                }
                "canDrawOverlays" -> result.success(permissionManager.canDrawOverlays())
                "openOverlaySettings" -> {
                    permissionManager.openOverlaySettings()
                    result.success(null)
                }
                "getInactiveAlarmIds" -> result.success(
                    AlarmStore(appContext).getAlarms().filterNot { it.enabled }.map { it.id }
                )
                "startIntervalSession" -> {
                    val intent = Intent(appContext, IntervalSessionService::class.java)
                        .setAction(IntervalSessionService.ACTION_START)
                        .putExtra(
                            IntervalSessionService.EXTRA_PHASES_JSON,
                            call.argument<String>("phasesJson") ?: "[]"
                        )
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        appContext.startForegroundService(intent)
                    } else {
                        appContext.startService(intent)
                    }
                    result.success(null)
                }
                "pauseIntervalSession", "resumeIntervalSession", "endIntervalSession" -> {
                    val action = when (call.method) {
                        "pauseIntervalSession" -> IntervalSessionService.ACTION_PAUSE
                        "resumeIntervalSession" -> IntervalSessionService.ACTION_RESUME
                        else -> IntervalSessionService.ACTION_END
                    }
                    appContext.startService(
                        Intent(appContext, IntervalSessionService::class.java).setAction(action)
                    )
                    result.success(null)
                }
                "getIntervalSessionState" -> result.success(IntervalSessionService.stateSnapshot())
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("MOTIVALARM_NATIVE_ERROR", error.message, null)
        }
    }
}

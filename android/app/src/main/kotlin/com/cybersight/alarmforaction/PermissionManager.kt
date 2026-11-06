package com.cybersight.alarmforaction

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings

class PermissionManager(private val context: Context) {
    private val oemResolver = OemPermissionResolver(context)

    fun getStatuses(): List<Map<String, Any>> {
        return listOf(
            mapOf(
                "key" to "exactAlarm",
                "title" to "Exact Alarm permission",
                "granted" to canScheduleExactAlarms(),
                "reason" to "Needed for reliable alarm timing at the exact selected minute."
            ),
            mapOf(
                "key" to "notification",
                "title" to "Notification permission",
                "granted" to hasNotificationPermission(),
                "reason" to "Needed for alarm alerts and a fallback notification when full-screen launch is limited."
            ),
            mapOf(
                "key" to "battery",
                "title" to "Battery optimization exemption",
                "granted" to isIgnoringBatteryOptimizations(),
                "reason" to "Improves reliability on devices that aggressively stop background work."
            ),
            mapOf(
                "key" to "fullScreen",
                "title" to "Full-screen notification permission",
                "granted" to canUseFullScreenIntent(),
                "reason" to "Allows the alarm screen to appear prominently when the phone is locked."
            ),
            mapOf(
                "key" to "backgroundRestrictions",
                "title" to "Background Activity",
                // Not detectable via any public API — most OEM battery managers
                // (MIUI/HyperOS Autostart, Samsung Sleeping apps, etc.) don't
                // expose their state to apps. Always resurfaced so the user
                // re-checks it periodically rather than assuming it's done once.
                "granted" to false,
                "reason" to oemResolver.instructionText(),
                "referenceUrl" to oemResolver.referenceUrl()
            )
        )
    }

    fun openBackgroundRestrictionSettings() = oemResolver.openSettings()

    fun openUrl(url: String) {
        try {
            context.startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (_: Exception) {
            // No browser available — nothing sensible to fall back to here.
        }
    }

    fun canScheduleExactAlarms(): Boolean {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()
    }

    fun hasNotificationPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    }

    fun isIgnoringBatteryOptimizations(): Boolean {
        val manager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return manager.isIgnoringBatteryOptimizations(context.packageName)
    }

    /** "Display over other apps" — optional, user-grantable in Settings.
     *  On MIUI it acts as one more gate on lock-screen/pop-up launches. */
    fun canDrawOverlays(): Boolean = Settings.canDrawOverlays(context)

    fun openOverlaySettings() {
        startActivity(
            Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)
                .setData(Uri.parse("package:${context.packageName}"))
        )
    }

    fun canUseFullScreenIntent(): Boolean {
        if (Build.VERSION.SDK_INT < 34) return true
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return manager.canUseFullScreenIntent()
    }

    fun openFullScreenIntentSettings() {
        val intent = if (Build.VERSION.SDK_INT >= 34) {
            Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
                .setData(Uri.parse("package:${context.packageName}"))
        } else {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        }
        startActivity(intent)
    }

    fun isBootReceiverEnabled(): Boolean {
        val component = ComponentName(context, BootReceiver::class.java)
        val setting = context.packageManager.getComponentEnabledSetting(component)
        return setting == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
            setting == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT
    }

    private fun appDetailsIntent(): Intent {
        return Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.parse("package:${context.packageName}"))
    }

    private fun startActivity(intent: Intent, fallback: Intent = appDetailsIntent()) {
        val prepared = intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(prepared)
        } catch (_: Exception) {
            context.startActivity(fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
}

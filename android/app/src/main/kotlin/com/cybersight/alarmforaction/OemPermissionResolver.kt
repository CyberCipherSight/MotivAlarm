package com.cybersight.alarmforaction

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings

/**
 * No public Android API exists to detect or request OEM-specific background-kill
 * exemptions (MIUI Autostart, Samsung Sleeping apps, etc.) — every reliable alarm
 * app on these skins works around it by manufacturer-detection + a deep link to
 * that OEM's own settings screen. Component names are undocumented and change
 * across OS versions, so every candidate is resolvability-checked before launch
 * and the whole chain degrades gracefully to a generic settings screen rather
 * than ever throwing [android.content.ActivityNotFoundException].
 *
 * Reference for menu paths/components: https://dontkillmyapp.com
 */
class OemPermissionResolver(private val context: Context) {
    private val brand = Build.MANUFACTURER.lowercase()

    /** User-facing, brand-specific explanation for why this step exists. */
    fun instructionText(): String {
        return when {
            isXiaomi() ->
                "On Xiaomi/Redmi/POCO the alarm can only take over the screen if you enable " +
                    "\"Show on Lock screen\", \"Open new windows while running in the background\" " +
                    "and \"Display pop-up windows\". Tap to open that page, then turn all three on. " +
                    "Also enable Autostart so alarms survive in the background."
            isSamsung() ->
                "Samsung's Device Care can put MotivAlarm to sleep and block alarms. Tap to remove it from sleeping/restricted apps."
            isOppo() ->
                "ColorOS battery management can block alarms in the background. Tap to allow MotivAlarm to start automatically."
            isVivo() ->
                "Vivo's battery manager can block background alarms. Tap to enable high background power usage for MotivAlarm."
            isHuawei() ->
                "EMUI/Magic UI can stop alarms unless launch is managed manually for MotivAlarm. Tap to review it."
            isOnePlus() ->
                "OnePlus battery optimization can block background alarms. Tap to allow unrestricted background usage."
            else ->
                "Some phone makers add their own battery management on top of Android's. Tap to double check yours allows MotivAlarm to run in the background."
        }
    }

    /** Canonical reference link shown alongside the in-app instruction. */
    fun referenceUrl(): String = "https://dontkillmyapp.com"

    /**
     * Launches the most specific screen this OEM exposes, falling through a
     * defensive chain: brand autostart manager -> brand battery manager ->
     * stock battery-optimization request -> generic app-details settings.
     * Every candidate is checked with [Intent.resolveActivity] first so a
     * missing/renamed OEM activity never crashes the launch.
     */
    fun openSettings() {
        for (candidate in ownerCandidates()) {
            if (launchIfResolvable(candidate)) return
        }
        if (launchIfResolvable(batteryOptimizationRequestIntent())) return
        // Guaranteed to resolve on any real Android device — the true last resort.
        context.startActivity(appDetailsIntent().addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun launchIfResolvable(intent: Intent): Boolean {
        return try {
            if (intent.resolveActivity(context.packageManager) == null) return false
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: Exception) {
            false
        }
    }

    /** Ordered, brand-specific candidates — most specific (autostart) first. */
    private fun ownerCandidates(): List<Intent> = when {
        isXiaomi() -> listOf(
            // The exact "Other permissions" editor for THIS app — where
            // "Show on Lock screen", "Open new windows while running in the
            // background" and "Display pop-up windows" live. These three are
            // what actually gate the full-screen alarm on MIUI/HyperOS
            // (verified on-device: without them the alarm degrades to a
            // plain notification). Undocumented but stable across MIUI 12-14.
            Intent("miui.intent.action.APP_PERM_EDITOR")
                .putExtra("extra_pkgname", context.packageName),
            Intent().setClassName(
                "com.miui.securitycenter",
                "com.miui.permcenter.permissions.PermissionsEditorActivity"
            ).putExtra("extra_pkgname", context.packageName),
            Intent().setClassName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity"
            ),
            Intent("miui.intent.action.OP_AUTO_START").addCategory(Intent.CATEGORY_DEFAULT)
        )
        isSamsung() -> listOf(
            Intent().setClassName(
                "com.samsung.android.lool",
                "com.samsung.android.sm.ui.battery.BatteryActivity"
            )
        )
        isOppo() -> listOf(
            Intent().setClassName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.permission.startup.StartupAppListActivity"
            ),
            Intent().setClassName(
                "com.oppo.safe",
                "com.oppo.safe.permission.startup.StartupAppListActivity"
            )
        )
        isVivo() -> listOf(
            Intent().setClassName(
                "com.vivo.permissionmanager",
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
            )
        )
        isHuawei() -> listOf(
            Intent().setClassName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
            )
        )
        isOnePlus() -> listOf(
            Intent().setClassName(
                "com.oneplus.security",
                "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"
            )
        )
        else -> emptyList()
    }

    private fun batteryOptimizationRequestIntent(): Intent {
        return Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            .setData(Uri.parse("package:${context.packageName}"))
    }

    private fun appDetailsIntent(): Intent {
        return Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.parse("package:${context.packageName}"))
    }

    private fun isXiaomi() = brand.contains("xiaomi") || brand.contains("redmi") || brand.contains("poco")
    private fun isSamsung() = brand.contains("samsung")
    private fun isOppo() = brand.contains("oppo") || brand.contains("realme")
    private fun isVivo() = brand.contains("vivo")
    private fun isHuawei() = brand.contains("huawei") || brand.contains("honor")
    private fun isOnePlus() = brand.contains("oneplus")
}

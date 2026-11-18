package com.example.routine_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat

class DayAuraPackageInstallReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return
        if (intent.action != Intent.ACTION_PACKAGE_ADDED) return

        val packageName = intent.data?.schemeSpecificPart ?: return
        if (packageName == context.packageName) return // ignore DayAura self updates

        val isReplacing = intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)
        if (isReplacing) return // ignore app updates

        val isTimeLock = DayAuraDeviceAdminReceiver.isTimeLockActive(context)
        Log.i("DayAuraInstall", "New app installed: $packageName, TimeLock active: $isTimeLock")

        if (isTimeLock) {
            // 1. Instant Hardware Freeze via Device Owner (0ms - Gray Icon)
            DayAuraDeviceAdminReceiver.suspendSingleApp(context, packageName, true)

            // 2. Fetch app label
            val pm = context.packageManager
            val appLabel = try {
                val appInfo = pm.getApplicationInfo(packageName, 0)
                pm.getApplicationLabel(appInfo).toString()
            } catch (_: Exception) {
                packageName
            }

            // 3. Save to pending verification queue in SharedPreferences
            savePendingApp(context, packageName, appLabel)

            // 4. Notify Flutter UI if app is open
            MainActivity.sendAppInstallEventToFlutter(packageName, appLabel)

            // 5. Post High-Priority Notification informing user that Smart Guard is inspecting
            showSmartInstallScanningNotification(context, packageName, appLabel)
        }
    }

    private fun showSmartInstallScanningNotification(context: Context, packageName: String, appLabel: String) {
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
            val channelId = "dayaura_smart_install_guard"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val chan = NotificationChannel(
                    channelId,
                    "DayAura Smart Install Guard",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Notifications for newly installed app inspection under Time Lock"
                }
                nm.createNotificationChannel(chan)
            }

            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pi = if (launchIntent != null) {
                PendingIntent.getActivity(context, 7788, launchIntent, flags)
            } else null

            val notif = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("🛡️ Smart Guard: $appLabel Suspended")
                .setContentText("App frozen by Device Owner. AI inspection is active.")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .apply {
                    if (pi != null) setContentIntent(pi)
                }
                .build()

            nm.notify(packageName.hashCode(), notif)
        } catch (e: Exception) {
            Log.e("DayAuraInstall", "Notification error: ", e)
        }
    }

    companion object {
        fun savePendingApp(context: Context, pkg: String, label: String) {
            val prefs = context.getSharedPreferences("smart_install_guard_prefs", Context.MODE_PRIVATE)
            val current = prefs.getStringSet("pending_packages", mutableSetOf()) ?: mutableSetOf()
            val updated = HashSet(current)
            updated.add("$pkg|||$label")
            prefs.edit().putStringSet("pending_packages", updated).apply()
        }

        fun removePendingApp(context: Context, pkg: String) {
            val prefs = context.getSharedPreferences("smart_install_guard_prefs", Context.MODE_PRIVATE)
            val current = prefs.getStringSet("pending_packages", mutableSetOf()) ?: mutableSetOf()
            val updated = HashSet<String>()
            for (item in current) {
                if (!item.startsWith("$pkg|||") && item != pkg) {
                    updated.add(item)
                }
            }
            prefs.edit().putStringSet("pending_packages", updated).apply()
        }

        fun getPendingApps(context: Context): List<Map<String, String>> {
            val prefs = context.getSharedPreferences("smart_install_guard_prefs", Context.MODE_PRIVATE)
            val current = prefs.getStringSet("pending_packages", mutableSetOf()) ?: mutableSetOf()
            val list = mutableListOf<Map<String, String>>()
            for (item in current) {
                val parts = item.split("|||")
                val pkg = parts.getOrNull(0) ?: ""
                val label = parts.getOrNull(1) ?: pkg
                if (pkg.isNotEmpty()) {
                    list.add(mapOf("packageName" to pkg, "appName" to label))
                }
            }
            return list
        }
    }
}

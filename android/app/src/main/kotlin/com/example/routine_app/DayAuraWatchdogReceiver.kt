package com.example.routine_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class DayAuraWatchdogReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_RESTART_GUARD = "com.example.routine_app.RESTART_GUARD"
        const val ACTION_RELOAD_SETTINGS = "com.example.routine_app.RELOAD_SETTINGS"

        fun scheduleWatchdog(context: Context, delayMs: Long = 30_000L) {
            try {
                val intent = Intent(context, DayAuraWatchdogReceiver::class.java).apply {
                    action = ACTION_RESTART_GUARD
                }
                val pi = PendingIntent.getBroadcast(
                    context,
                    999,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                val triggerAt = System.currentTimeMillis() + delayMs

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    val info = AlarmManager.AlarmClockInfo(triggerAt, pi)
                    am?.setAlarmClock(info, pi)
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    am?.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
                } else {
                    am?.set(AlarmManager.RTC_WAKEUP, triggerAt, pi)
                }
            } catch (_: Exception) {}
        }
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null) return
        val action = intent?.action ?: ""

        when (action) {
            ACTION_RELOAD_SETTINGS -> {
                DayAuraAccessibilityService.reloadAllSettings()
                FloatingTrackerService.reloadDistractingApps()
            }
            ACTION_RESTART_GUARD,
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_USER_PRESENT -> {
                DayAuraAccessibilityService.reloadAllSettings()
                FloatingTrackerService.reloadDistractingApps()

                // If Time Lock is active, ensure all protection layers are running
                val prefs = context.getSharedPreferences("locked_in_prefs", Context.MODE_PRIVATE)
                val mode = prefs.getString("locked_in_mode", "") ?: ""
                val until = prefs.getLong("time_lock_until_epoch", prefs.getLong("locked_in_until_epoch", 0L))
                val isTimeLock = mode == "time_lock" && System.currentTimeMillis() < until
                val distractionPrefs = context.getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
                val vpnShieldEnabled = distractionPrefs.getBoolean("vpn_shield_enabled", false)

                if (isTimeLock) {
                    DayAuraDeviceAdminReceiver.suspendAllDistractingApps(context, true)
                    DayAuraDeviceAdminReceiver.enableKernelPrivateDns(context, true)
                    DayAuraDeviceAdminReceiver.enforceChromeEnterprisePolicies(context, true)
                }

                if (isTimeLock || vpnShieldEnabled) {
                    try {
                        val guardianIntent = Intent(context, DayAuraGuardianService::class.java)
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                context.startForegroundService(guardianIntent)
                            } else {
                                context.startService(guardianIntent)
                            }
                        } catch (_: Exception) {
                            context.startService(guardianIntent)
                        }
                    } catch (_: Exception) {}
                }

                if (!isTimeLock && vpnShieldEnabled) {
                    try {
                        if (android.net.VpnService.prepare(context) == null) {
                            val vpnIntent = Intent(context, DayAuraDnsVpnService::class.java)
                            try {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                    context.startForegroundService(vpnIntent)
                                } else {
                                    context.startService(vpnIntent)
                                }
                            } catch (_: Exception) {
                                context.startService(vpnIntent)
                            }
                        }
                    } catch (_: Exception) {}
                }

                // If Time Lock or Web Shield is active, keep watchdog loop running to prevent cleaner vulnerability
                if (isTimeLock || vpnShieldEnabled) {
                    scheduleWatchdog(context, 10_000L) // check every 10s
                } else if (mode == "time_lock") {
                    // Time Lock has elapsed, un-suspend distracting apps and restore settings
                    DayAuraDeviceAdminReceiver.suspendAllDistractingApps(context, false)
                    DayAuraDeviceAdminReceiver.bindAlwaysOnVpn(context, false)
                    DayAuraDeviceAdminReceiver.enableKernelPrivateDns(context, false)
                    DayAuraDeviceAdminReceiver.enforceChromeEnterprisePolicies(context, false)
                }
            }
        }
    }
}

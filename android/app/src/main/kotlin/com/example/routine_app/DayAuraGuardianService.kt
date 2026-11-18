package com.example.routine_app

import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Binder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

class DayAuraGuardianService : Service() {

    companion object {
        const val GUARDIAN_CHANNEL_ID = "dayaura_guardian_daemon"
        const val GUARDIAN_NOTIFICATION_ID = 2003
        var isRunning = false
    }

    private val binder = GuardianBinder()
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var isMonitoring = false
    private var monitorThread: Thread? = null
    private var packageInstallReceiver: DayAuraPackageInstallReceiver? = null

    inner class GuardianBinder : Binder() {
        fun getService(): DayAuraGuardianService = this@DayAuraGuardianService
    }

    override fun onBind(intent: Intent?): IBinder {
        return binder
    }

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        startGuardianForegroundNotification()
        startProcessWatchdogLoop()
        registerPackageInstallReceiver()
    }

    private fun registerPackageInstallReceiver() {
        try {
            if (packageInstallReceiver == null) {
                packageInstallReceiver = DayAuraPackageInstallReceiver()
                val filter = android.content.IntentFilter(Intent.ACTION_PACKAGE_ADDED).apply {
                    addDataScheme("package")
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    registerReceiver(packageInstallReceiver, filter, Context.RECEIVER_EXPORTED)
                } else {
                    registerReceiver(packageInstallReceiver, filter)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun unregisterPackageInstallReceiver() {
        try {
            if (packageInstallReceiver != null) {
                unregisterReceiver(packageInstallReceiver)
                packageInstallReceiver = null
            }
        } catch (_: Exception) {}
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startGuardianForegroundNotification()
        startProcessWatchdogLoop()
        return START_STICKY
    }

    private fun startGuardianForegroundNotification() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                GUARDIAN_CHANNEL_ID,
                "DayAura Watchdog",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Keeps Locked In tamper-proof"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_SECRET
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, GUARDIAN_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setContentTitle("DayAura Protection Active")
            .setContentText("Locked In Guardian")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }

        val notification = builder.build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(GUARDIAN_NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(GUARDIAN_NOTIFICATION_ID, notification)
        }
    }

    private fun isMainProcessAlive(): Boolean {
        try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager ?: return false
            val processes = am.runningAppProcesses ?: return false
            val mainPkg = packageName
            for (proc in processes) {
                if (proc.processName == mainPkg) {
                    return true
                }
            }
        } catch (_: Exception) {}
        return false
    }

    private fun isVpnProcessAlive(): Boolean {
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? android.net.ConnectivityManager
            if (cm != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                for (network in cm.allNetworks) {
                    val caps = cm.getNetworkCapabilities(network)
                    if (caps != null && caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_VPN)) {
                        return true
                    }
                }
            }
            val am = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager ?: return false
            val processes = am.runningAppProcesses ?: return false
            val vpnPkg = "$packageName:vpn"
            for (proc in processes) {
                if (proc.processName == vpnPkg && proc.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND_SERVICE) {
                    return true
                }
            }
        } catch (_: Exception) {}
        return false
    }

    private fun isTimeLockActive(): Boolean {
        return DayAuraDeviceAdminReceiver.isTimeLockActive(applicationContext)
    }

    private fun startProcessWatchdogLoop() {
        if (isMonitoring) return
        isMonitoring = true

        var policyTick = 0
        monitorThread = Thread({
            while (isMonitoring) {
                try {
                    Thread.sleep(400L) // Fast 400ms process heartbeat

                    val isTimeLock = isTimeLockActive()
                    val prefs = applicationContext.getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
                    val vpnShieldEnabled = prefs.getBoolean("vpn_shield_enabled", false)

                    if (isTimeLock) {
                        // Periodic policy verification every ~30 seconds (75 * 400ms)
                        if (policyTick % 75 == 0) {
                            DayAuraDeviceAdminReceiver.suspendAllDistractingApps(applicationContext, true)
                            DayAuraDeviceAdminReceiver.enableKernelPrivateDns(applicationContext, true)
                            DayAuraDeviceAdminReceiver.enforceChromeEnterprisePolicies(applicationContext, true)
                        }
                        policyTick++

                        // Revive main process if killed
                        val mainAlive = isMainProcessAlive()
                        if (!mainAlive) {
                            reviveMainProcess()
                        }
                    } else {
                        policyTick = 0
                    }

                    if (!isTimeLock && vpnShieldEnabled) {
                        // Revive VPN service only for non-time-lock mode
                        val vpnAlive = isVpnProcessAlive()
                        if (!vpnAlive) {
                            reviveVpnService()
                        }
                    }
                } catch (_: InterruptedException) {
                    break
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }, "DayAura-GuardianHeartbeat").apply {
            priority = Thread.MAX_PRIORITY
            start()
        }
    }

    private fun reviveVpnService() {
        mainHandler.post {
            try {
                if (android.net.VpnService.prepare(applicationContext) == null) {
                    val vpnIntent = Intent(applicationContext, DayAuraDnsVpnService::class.java)
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(vpnIntent)
                        } else {
                            startService(vpnIntent)
                        }
                    } catch (_: Exception) {
                        startService(vpnIntent)
                    }
                }
            } catch (_: Exception) {}
        }
    }

    private fun reviveMainProcess() {
        mainHandler.post {
            try {
                // 1. Trigger DayAuraWatchdogReceiver
                val watchdogIntent = Intent(applicationContext, DayAuraWatchdogReceiver::class.java).apply {
                    action = DayAuraWatchdogReceiver.ACTION_RESTART_GUARD
                }
                sendBroadcast(watchdogIntent)

                // 2. Schedule instant 100ms AlarmClock backup
                DayAuraWatchdogReceiver.scheduleWatchdog(applicationContext, 100L)
            } catch (_: Exception) {}
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        startGuardianForegroundNotification()
        DayAuraWatchdogReceiver.scheduleWatchdog(applicationContext, 100L)
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterPackageInstallReceiver()
        isMonitoring = false
        isRunning = false
        try { monitorThread?.interrupt() } catch (_: Exception) {}
        monitorThread = null
        val distractionPrefs = applicationContext.getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
        val vpnShieldEnabled = distractionPrefs.getBoolean("vpn_shield_enabled", false)
        if (isTimeLockActive() || vpnShieldEnabled) {
            DayAuraWatchdogReceiver.scheduleWatchdog(applicationContext, 100L)
        }
        stopForeground(true)
    }
}

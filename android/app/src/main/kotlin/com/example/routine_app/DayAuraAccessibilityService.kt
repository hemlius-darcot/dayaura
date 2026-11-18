package com.example.routine_app

import android.accessibilityservice.AccessibilityService
import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.admin.DevicePolicyManager
import android.app.usage.UsageStatsManager
import android.app.usage.UsageEvents
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.Locale

class DayAuraAccessibilityService : AccessibilityService() {

    companion object {
        var isRunning = false
        var instance: DayAuraAccessibilityService? = null

        private val BROWSER_PACKAGES = setOf(
            "com.android.chrome",
            "com.chrome.beta",
            "com.chrome.dev",
            "com.chrome.canary",
            "com.google.android.apps.chrome",
            "org.mozilla.firefox",
            "org.mozilla.firefox_beta",
            "org.mozilla.focus",
            "com.sec.android.app.sbrowser",
            "com.sec.android.app.sbrowser.beta",
            "com.microsoft.emmx",
            "com.brave.browser",
            "com.opera.browser",
            "com.opera.mini.native",
            "com.opera.touch",
            "com.opera.gx",
            "com.duckduckgo.mobile.android",
            "com.coloros.browser",
            "com.vivo.browser",
            "com.mi.globalbrowser",
            "com.android.browser",
            "com.miui.browser",
            "com.kiwibrowser.browser",
            "com.yandex.browser",
            "com.vivaldi.browser",
            "com.ucmobile.intl",
            "com.ucmobile.lite",
            "com.transsion.phoenix",
            "mark.via.gp",
            "acr.browser.barebones",
            "com.pure.mini.browser",
            "com.ghostery.android.ghostery",
            "org.bromite.bromite",
            "net.waterfox.android.release",
            "io.github.forkmaintainers.iceraven",
            "com.lemur.browser",
            "com.aloha.browser",
            "com.alohamobile.browser",
            "com.monumentbrowser",
            "com.ksmobile.cb",
            "com.huawei.browser",
            "com.heytap.browser"
        )

        private val dynamicBrowserPackages = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()

        fun reloadAllSettings() {
            instance?.loadAllSettings()
        }

        fun reloadDistractingApps() {
            instance?.loadDistractingPackages()
        }

        fun reloadBlockedWebsites() {
            instance?.loadBlockedWebsites()
        }

        fun isAllowedGoogleChrome(pkg: String): Boolean {
            val lower = pkg.lowercase(Locale.ROOT)
            return lower == "com.android.chrome" ||
                   lower == "com.google.android.apps.chrome" ||
                   lower == "com.chrome.beta" ||
                   lower == "com.chrome.dev" ||
                   lower == "com.chrome.canary"
        }
    }

    private fun isBrowserPackage(pkg: String): Boolean {
        if (pkg.isEmpty()) return false
        val lower = pkg.lowercase(Locale.ROOT)
        if (BROWSER_PACKAGES.contains(lower) || dynamicBrowserPackages.contains(lower)) {
            return true
        }
        if (lower.contains("browser") ||
            lower.contains("chrome") ||
            lower.contains("firefox") ||
            lower.contains("opera") ||
            lower.contains("ucmobile") ||
            lower.contains("webbrowser") ||
            lower.contains("navigator") ||
            lower == "mark.via.gp"
        ) {
            dynamicBrowserPackages.add(lower)
            return true
        }

        try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://google.com")).apply {
                setPackage(pkg)
            }
            val resolves = packageManager.queryIntentActivities(intent, 0)
            if (resolves.isNotEmpty()) {
                dynamicBrowserPackages.add(lower)
                return true
            }
        } catch (_: Throwable) {}

        return false
    }

    private var windowManager: WindowManager? = null
    private var redOverlayView: View? = null
    private var currentOverlayTarget: String? = null
    private var currentOverlayPackage: String? = null

    private val distractingPackages = mutableSetOf<String>()
    private val blockedWebsites = mutableSetOf<String>()
    private val appDailyLimits = java.util.concurrent.ConcurrentHashMap<String, Int>()
    private val appDailyUsageSeconds = java.util.concurrent.ConcurrentHashMap<String, Long>()
    private val appSessionStartUsage = java.util.concurrent.ConcurrentHashMap<String, Long>()
    private var lastRecordedDate = ""
    private var activeAppForegroundStart = 0L
    private var activeAppPackage: String? = null
    private var lastShortsBlockedTime = 0L
    private var shortsWarningView: View? = null
    private var blockAdultPreset = true
    private var blockGamblingPreset = true

    private var currentForegroundPackage: String? = null
    private var lastBlockedTime = 0L
    private var lastBlockedTarget = ""
    private var lastSettingsRefreshTime = 0L
    private val appLabelCache = java.util.concurrent.ConcurrentHashMap<String, String>()
    private val warned2MinPackages = java.util.concurrent.ConcurrentHashMap<String, Boolean>()

    private fun createQuotaWarningNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = "dayaura_quota_warning"
            val channelName = "Daily Quota Warnings"
            val channel = NotificationChannel(
                channelId,
                channelName,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "2-minute warning notifications before daily app quota lock"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 350, 150, 350)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            nm?.createNotificationChannel(channel)
        }
    }

    private fun send2MinuteWarningNotification(pkg: String, limitMinutes: Int, remainingSec: Long) {
        try {
            createQuotaWarningNotificationChannel()
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
            val appLabel = getAppLabelFast(pkg)
            val channelId = "dayaura_quota_warning"

            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                this,
                pkg.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
            )

            val remText = if (remainingSec <= 60L) "1min" else "2min"
            val title = "⚠️ $appLabel: remain $remText"
            val text = "Daily limit almost reached ($limitMinutes min limit). $appLabel will be strongly locked in $remText."

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, channelId)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }

            builder
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(Notification.BigTextStyle().bigText(text))
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setPriority(Notification.PRIORITY_HIGH)
                .setDefaults(Notification.DEFAULT_ALL)

            val notifId = 20000 + (pkg.hashCode() and 0x7FFF)
            nm.notify(notifId, builder.build())
        } catch (t: Throwable) {
            t.printStackTrace()
        }
    }

    private val settingsReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            loadAllSettings()
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    private val ADULT_KEYWORDS = listOf(
        "porn", "xvideos", "xnxx", "pornhub", "redtube", "youporn",
        "chaturbate", "stripchat", "onlyfans", "cam4", "brazzers",
        "xhamster", "eporner", "beeg.com", "spankbang", "hentai"
    )

    private val ADULT_DOMAINS = listOf(
        "xhamster.com", "pornhub.com", "xvideos.com", "xnxx.com", "stripchat.com",
        "chaturbate.com", "redtube.com", "youporn.com", "onlyfans.com", "spankbang.com",
        "eporner.com", "beeg.com", "brazzers.com", "cam4.com", "hentaihaven.xxx",
        "livejasmin.com", "daftsex.com", "rule34.xxx", "tnaflix.com", "tube8.com",
        "pornhat.com", "hqporner.com", "txxx.com", "upornia.com", "porn.com",
        "bongacams.com", "camsoda.com", "manyvids.com", "fapello.com", "erome.com"
    )

    private val GAMBLING_KEYWORDS = listOf(
        "1xbet", "bet365", "melbet", "parimatch", "babu88", "jeetwin",
        "mostbet", "betway", "stake.com", "casino", "gambling"
    )

    private val GAMBLING_DOMAINS = listOf(
        "1xbet.com", "bet365.com", "melbet.com", "parimatch.com", "babu88.com",
        "jeetwin.com", "mostbet.com", "betway.com", "stake.com", "1win.com",
        "betfair.com", "888casino.com", "baji999.com", "linebet.com", "megari.com",
        "betonline.ag", "bovada.lv", "draftkings.com", "fanduel.com", "betmgm.com"
    )

    override fun onServiceConnected() {
        super.onServiceConnected()
        isRunning = true
        instance = this
        windowManager = getSystemService(Context.WINDOW_SERVICE) as? WindowManager
        loadAllSettings()
        try {
            val filter = android.content.IntentFilter(DayAuraWatchdogReceiver.ACTION_RELOAD_SETTINGS)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(settingsReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(settingsReceiver, filter)
            }
        } catch (_: Exception) {}

        mainHandler.removeCallbacks(serviceWatchdogRunnable)
        mainHandler.post(serviceWatchdogRunnable)
    }

    private var lastVpnReviveCheckTime = 0L

    private val serviceWatchdogRunnable = object : Runnable {
        override fun run() {
            try {
                checkAndReviveServicesIfNeeded()

                // Midnight date rollover check: reset daily tracking and clear yesterday's cache
                val today = getTodayDateString()
                if (lastRecordedDate.isNotEmpty() && today != lastRecordedDate) {
                    lastRecordedDate = today
                    appDailyUsageSeconds.clear()
                    appSessionStartUsage.clear()
                    warned2MinPackages.clear()
                    try {
                        val prefs = getSharedPreferences("app_usage_daily_prefs", Context.MODE_PRIVATE)
                        prefs.edit().putString("usage_date", today).putString("usage_seconds", "{}").apply()
                    } catch (_: Exception) {}
                } else if (lastRecordedDate.isEmpty()) {
                    lastRecordedDate = today
                }

                val rootNode = try { rootInActiveWindow } catch (_: Throwable) { null }
                val activePkg = rootNode?.packageName?.toString() ?: currentForegroundPackage ?: ""
                val mode = getLockedInMode()

                if (mode == "time_lock") {
                    // Actively monitor daily quotas for all tracked apps
                    // 1) Freeze apps whose daily quota expired (Device Owner setPackagesSuspended -> Gray Icon)
                    // 2) Unfreeze apps whose daily quota has remaining time (Device Owner un-suspend -> Normal Icon)
                    // 3) Trigger 2-minute heads-up notification when remaining <= 120s
                    val distCopy = synchronized(distractingPackages) { distractingPackages.toList() }
                    for (pkg in distCopy) {
                        val limitMinutes = appDailyLimits[pkg] ?: 0
                        if (limitMinutes > 0) {
                            val usedSec = getAppUsageSeconds(pkg)
                            val remainingSec = (limitMinutes * 60L) - usedSec
                            if (remainingSec <= 0L) {
                                DayAuraDeviceAdminReceiver.suspendSingleApp(applicationContext, pkg, true)
                            } else {
                                // Quota remaining -> Ensure app is UN-SUSPENDED (Normal color)
                                DayAuraDeviceAdminReceiver.suspendSingleApp(applicationContext, pkg, false)
                                if (limitMinutes > 2 && remainingSec in 1L..120L) {
                                    if (!warned2MinPackages.containsKey(pkg)) {
                                        warned2MinPackages[pkg] = true
                                        send2MinuteWarningNotification(pkg, limitMinutes, remainingSec)
                                    }
                                } else if (limitMinutes <= 2 && remainingSec in 1L..30L) {
                                    if (!warned2MinPackages.containsKey(pkg)) {
                                        warned2MinPackages[pkg] = true
                                        send2MinuteWarningNotification(pkg, limitMinutes, remainingSec)
                                    }
                                }
                            }
                        }
                    }

                    if (activePkg.isNotEmpty() && activePkg != packageName && !isIgnoredSystemPackage(activePkg)) {
                        val isDistracting = synchronized(distractingPackages) {
                            distractingPackages.contains(activePkg)
                        }
                        if (isDistracting) {
                            val limitMinutes = appDailyLimits[activePkg] ?: 0
                            if (limitMinutes <= 0) {
                                handleDistractingApp(activePkg, mode, limitMinutes = 0)
                            } else {
                                val usedSec = getAppUsageSeconds(activePkg)
                                if (usedSec >= limitMinutes * 60L) {
                                    handleDistractingApp(activePkg, mode, limitMinutes = limitMinutes)
                                }
                            }
                        }

                        // YouTube App Shorts Active Shield (Even while YouTube has remaining quota for classes)
                        if (activePkg == "com.google.android.youtube" && rootNode != null) {
                            if (isYouTubeShortsNode(rootNode)) {
                                val now = System.currentTimeMillis()
                                if (now - lastShortsBlockedTime > 1800L) {
                                    lastShortsBlockedTime = now
                                    performGlobalAction(GLOBAL_ACTION_BACK)
                                    showShortsWarningOverlay()
                                }
                            }
                        }

                        // Single Browser Policy: In Time Lock, ONLY Google Chrome is permitted!
                        // All other browsers in the world are immediately blocked and suspended.
                        if (isBrowserPackage(activePkg)) {
                            if (!isAllowedGoogleChrome(activePkg)) {
                                handleForbiddenBrowser(activePkg, mode)
                            } else if (rootNode != null) {
                                inspectAndBlockBrowser(activePkg, rootNode, mode)
                            }
                        }
                    }
                } else {
                    if (activePkg.isNotEmpty() && activePkg != packageName && !isIgnoredSystemPackage(activePkg)) {
                        if (rootNode != null && isBrowserPackage(activePkg)) {
                            inspectAndBlockBrowser(activePkg, rootNode, "none")
                        }
                    }
                }
            } catch (_: Throwable) {}
            // Battery Saver: 1500ms watchdog interval stops CPU hammering and allows processor deep sleep
            mainHandler.postDelayed(this, 1500L)
        }
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
            val vpnProc = "$packageName:vpn"
            for (proc in processes) {
                if (proc.processName == vpnProc && proc.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND_SERVICE) {
                    return true
                }
            }
        } catch (_: Exception) {}
        return false
    }

    private fun isGuardianProcessAlive(): Boolean {
        try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager ?: return false
            val processes = am.runningAppProcesses ?: return false
            val guardianProc = "$packageName:guardian"
            for (proc in processes) {
                if (proc.processName == guardianProc && proc.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND_SERVICE) {
                    return true
                }
            }
        } catch (_: Exception) {}
        return false
    }

    fun checkAndReviveServicesIfNeeded() {
        val now = System.currentTimeMillis()
        if (now - lastVpnReviveCheckTime < 1000L) return
        lastVpnReviveCheckTime = now

        val prefs = getSharedPreferences("locked_in_prefs", Context.MODE_PRIVATE)
        val mode = prefs.getString("locked_in_mode", "") ?: ""
        val until = prefs.getLong("time_lock_until_epoch", prefs.getLong("locked_in_until_epoch", 0L))
        val isTimeLock = mode == "time_lock" && now < until
        val distractionPrefs = getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
        val vpnShieldEnabled = distractionPrefs.getBoolean("vpn_shield_enabled", false)

        val shouldVpnRun = !isTimeLock && vpnShieldEnabled

        if (isTimeLock && isVpnProcessAlive()) {
            try {
                val stopVpn = Intent(this, DayAuraDnsVpnService::class.java).apply {
                    action = DayAuraDnsVpnService.ACTION_STOP_VPN
                }
                startService(stopVpn)
            } catch (_: Throwable) {}
        } else if (shouldVpnRun && !isVpnProcessAlive()) {
            try {
                if (VpnService.prepare(this) == null) {
                    val vpnIntent = Intent(this, DayAuraDnsVpnService::class.java)
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
            } catch (_: Throwable) {}
        }

        val shouldGuardianRun = isTimeLock || vpnShieldEnabled
        if (shouldGuardianRun && !isGuardianProcessAlive()) {
            try {
                val guardianIntent = Intent(this, DayAuraGuardianService::class.java)
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(guardianIntent)
                    } else {
                        startService(guardianIntent)
                    }
                } catch (_: Exception) {
                    startService(guardianIntent)
                }
            } catch (_: Throwable) {}
        }
    }

    fun loadAllSettings() {
        loadDistractingPackages()
        loadBlockedWebsites()
        loadAppDailyLimits()
    }

    fun loadDistractingPackages() {
        try {
            val prefs = getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
            val json = prefs.getString("distracting_packages", "[]") ?: "[]"
            val arr = JSONArray(json)
            synchronized(distractingPackages) {
                distractingPackages.clear()
                for (i in 0 until arr.length()) {
                    val p = arr.getString(i).trim()
                    if (p.isNotEmpty()) distractingPackages.add(p)
                }
            }
        } catch (_: Exception) {}
    }

    fun loadBlockedWebsites() {
        try {
            val prefs = getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
            val json = prefs.getString("blocked_websites", "[]") ?: "[]"
            val arr = JSONArray(json)
            synchronized(blockedWebsites) {
                blockedWebsites.clear()
                for (i in 0 until arr.length()) {
                    val site = arr.getString(i).trim().lowercase(Locale.ROOT)
                    if (site.isNotEmpty()) blockedWebsites.add(site)
                }
            }
            blockAdultPreset = prefs.getBoolean("block_adult_preset", true)
            blockGamblingPreset = prefs.getBoolean("block_gambling_preset", true)
        } catch (_: Exception) {}
    }

    private fun getTodayDateString(): String {
        val cal = Calendar.getInstance()
        return "${cal.get(Calendar.YEAR)}_${cal.get(Calendar.DAY_OF_YEAR)}"
    }

    fun getAppDailyLimitsMap(): Map<String, Int> = HashMap(appDailyLimits)

    fun getSystemUsageSeconds(pkg: String): Long {
        if (pkg.isEmpty()) return 0L
        try {
            val usm = getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager ?: return 0L
            val cal = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val startOfDay = cal.timeInMillis
            val now = System.currentTimeMillis()

            var totalMs = 0L
            val usageEvents = usm.queryEvents(startOfDay, now)
            if (usageEvents != null) {
                var startResumeMs = 0L
                val event = UsageEvents.Event()
                while (usageEvents.hasNextEvent()) {
                    usageEvents.getNextEvent(event)
                    if (event.packageName == pkg) {
                        when (event.eventType) {
                            UsageEvents.Event.ACTIVITY_RESUMED, 1 /* MOVE_TO_FOREGROUND */ -> {
                                startResumeMs = event.timeStamp
                            }
                            UsageEvents.Event.ACTIVITY_PAUSED, 2 /* MOVE_TO_BACKGROUND */ -> {
                                if (startResumeMs > 0L && event.timeStamp > startResumeMs) {
                                    totalMs += (event.timeStamp - startResumeMs)
                                    startResumeMs = 0L
                                }
                            }
                        }
                    }
                }
                if (startResumeMs > 0L && now > startResumeMs) {
                    totalMs += (now - startResumeMs)
                }
            }
            return totalMs / 1000L
        } catch (_: Throwable) {
            return 0L
        }
    }

    fun getAppUsageSeconds(pkg: String, forceSystemQuery: Boolean = false): Long {
        if (pkg.isEmpty()) return 0L
        val now = System.currentTimeMillis()
        val isForeground = (activeAppPackage == pkg)
        // Battery Saver: Only run heavy system database queries if the app is currently in foreground,
        // or explicitly requested (forceSystemQuery). Background apps use the accumulated daily usage in RAM.
        var total = if (isForeground || forceSystemQuery) {
            getSystemUsageSeconds(pkg)
        } else {
            appDailyUsageSeconds[pkg] ?: 0L
        }

        if (isForeground && activeAppForegroundStart > 0L) {
            val sessionElapsed = maxOf(0L, (now - activeAppForegroundStart) / 1000L)
            val sessionBase = appSessionStartUsage[pkg] ?: total
            total = maxOf(total, sessionBase + sessionElapsed)
        }
        appDailyUsageSeconds[pkg] = total
        return total
    }

    private fun loadDailyUsage() {
        try {
            val prefs = getSharedPreferences("app_usage_daily_prefs", Context.MODE_PRIVATE)
            val savedDate = prefs.getString("usage_date", "")
            val today = getTodayDateString()
            if (savedDate == today) {
                val json = prefs.getString("usage_seconds", "{}") ?: "{}"
                val obj = JSONObject(json)
                val keys = obj.keys()
                while (keys.hasNext()) {
                    val k = keys.next()
                    val savedSec = obj.optLong(k, 0L)
                    appDailyUsageSeconds[k] = maxOf(appDailyUsageSeconds[k] ?: 0L, savedSec)
                }
            } else {
                appDailyUsageSeconds.clear()
                appSessionStartUsage.clear()
                warned2MinPackages.clear()
                prefs.edit().putString("usage_date", today).putString("usage_seconds", "{}").apply()
            }
        } catch (_: Exception) {}
    }

    private fun saveDailyUsage() {
        try {
            val prefs = getSharedPreferences("app_usage_daily_prefs", Context.MODE_PRIVATE)
            val today = getTodayDateString()
            val obj = JSONObject()
            for ((pkg, sec) in appDailyUsageSeconds) {
                obj.put(pkg, sec)
            }
            prefs.edit().putString("usage_date", today).putString("usage_seconds", obj.toString()).apply()
        } catch (_: Exception) {}
    }

    fun loadAppDailyLimits() {
        try {
            val prefs = getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
            val json = prefs.getString("app_daily_limits", "{}") ?: "{}"
            val obj = JSONObject(json)
            appDailyLimits.clear()
            val keys = obj.keys()
            while (keys.hasNext()) {
                val k = keys.next()
                appDailyLimits[k] = obj.optInt(k, 0)
            }
        } catch (_: Exception) {}
        loadDailyUsage()
    }

    private fun trackAppUsage(pkg: String) {
        val now = System.currentTimeMillis()
        val today = getTodayDateString()
        if (today != lastRecordedDate) {
            lastRecordedDate = today
            warned2MinPackages.clear()
            loadDailyUsage()
        }

        if (activeAppPackage != null && activeAppPackage != pkg) {
            val prevPkg = activeAppPackage!!
            val elapsedMs = now - activeAppForegroundStart
            if (elapsedMs in 500..86400000) {
                val sessionSec = elapsedMs / 1000L
                val base = appSessionStartUsage[prevPkg] ?: (appDailyUsageSeconds[prevPkg] ?: 0L)
                val currentTotal = maxOf(base + sessionSec, getSystemUsageSeconds(prevPkg))
                appDailyUsageSeconds[prevPkg] = currentTotal
                saveDailyUsage()
            }
            activeAppPackage = pkg
            activeAppForegroundStart = now
            val currentUsage = getAppUsageSeconds(pkg, forceSystemQuery = true)
            appSessionStartUsage[pkg] = currentUsage
            appDailyUsageSeconds[pkg] = currentUsage
        } else if (activeAppPackage == null) {
            activeAppPackage = pkg
            activeAppForegroundStart = now
            val currentUsage = getAppUsageSeconds(pkg, forceSystemQuery = true)
            appSessionStartUsage[pkg] = currentUsage
            appDailyUsageSeconds[pkg] = currentUsage
        }
    }

    /**
     * Returns: "time_lock" or "none"
     */
    fun getLockedInMode(): String {
        return try {
            val prefs = getSharedPreferences("locked_in_prefs", Context.MODE_PRIVATE)
            val mode = prefs.getString("locked_in_mode", "") ?: ""
            if (mode == "time_lock") {
                val untilEpoch = prefs.getLong("time_lock_until_epoch", 0L)
                if (System.currentTimeMillis() < untilEpoch) return "time_lock"
                return "none"
            }
            // Fallback to legacy prefs
            val legacyActive = prefs.getBoolean("locked_in_active", false)
            val legacyUntil = prefs.getLong("locked_in_until_epoch", 0L)
            if (legacyActive && System.currentTimeMillis() < legacyUntil) {
                return "time_lock"
            }
            "none"
        } catch (_: Exception) {
            "none"
        }
    }

    fun getTimeLockUntilEpoch(): Long {
        return try {
            val prefs = getSharedPreferences("locked_in_prefs", Context.MODE_PRIVATE)
            val until = prefs.getLong("time_lock_until_epoch", 0L)
            if (until > 0) until else prefs.getLong("locked_in_until_epoch", 0L)
        } catch (_: Exception) {
            0L
        }
    }

    private fun isIgnoredSystemPackage(pkg: String): Boolean {
        val lower = pkg.lowercase(Locale.ROOT)
        return lower == "android" ||
                lower.contains("systemui") ||
                lower.contains("inputmethod") ||
                lower.contains("keyboard") ||
                lower.contains("accessibility") ||
                lower.contains("screenshot") ||
                lower.contains("freeform")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        try {
            checkAndReviveServicesIfNeeded()
            if (event == null) return
            val pkg = event.packageName?.toString() ?: return

            // Ignore our own DayAura app UI unless user explicitly opened MainActivity
            if (pkg == packageName) {
                val cls = event.className?.toString() ?: ""
                if (cls.contains("MainActivity")) {
                    hideWarningOverlay()
                }
                return
            }

            // If an overlay is currently showing and user navigated away to another app/launcher,
            // dismiss it (ignoring transient system UI like notification shade, keyboards, etc.)
            if (redOverlayView != null && currentOverlayPackage != null && pkg != currentOverlayPackage && !isIgnoredSystemPackage(pkg)) {
                hideWarningOverlay()
            }
            if (shortsWarningView != null && pkg != "com.google.android.youtube" && !isIgnoredSystemPackage(pkg)) {
                hideShortsWarningOverlay()
            }

            currentForegroundPackage = pkg
            trackAppUsage(pkg)
            val now = System.currentTimeMillis()
            if (now - lastSettingsRefreshTime > 1500L) {
                lastSettingsRefreshTime = now
                loadAllSettings()
            }
            val mode = getLockedInMode()
            val isWebShieldOn = getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE).getBoolean("vpn_shield_enabled", false)

            if (mode == "none" && !isWebShieldOn) {
                hideWarningOverlay()
                return
            }

            // 1. Anti-Uninstall & Settings Tamper Protection (Strictly active in Time Lock mode)
            // Notice: 'vending' (Google Play Store) is permitted so users have freedom to install study apps without panic.
            if (mode == "time_lock") {
                val lowerPkg = pkg.lowercase(Locale.ROOT)
                val isSecurityPackage = lowerPkg.contains("settings") ||
                        lowerPkg.contains("packageinstaller") ||
                        lowerPkg.contains("permissioncontroller") ||
                        lowerPkg.contains("securitycenter") ||
                        lowerPkg.contains("cleanmaster") ||
                        lowerPkg.contains("safecenter")
                if (isSecurityPackage) {
                    checkAndBlockAntiUninstall(lowerPkg, event)
                    return
                }
            }

            // 2. Distracting App Detection (Strictly active in Time Lock mode)
            if (mode == "time_lock") {
                val isDistracting = synchronized(distractingPackages) {
                    distractingPackages.contains(pkg)
                }
                if (isDistracting) {
                    val limitMinutes = appDailyLimits[pkg] ?: 0
                    if (limitMinutes <= 0) {
                        // 0 min quota: strictly blocked immediately (0ms)!
                        handleDistractingApp(pkg, mode, limitMinutes = 0)
                        return
                    } else {
                        // App has daily quota (e.g. YouTube 30m, Facebook 20m)
                        val usedSec = getAppUsageSeconds(pkg)
                        val remainingSec = (limitMinutes * 60L) - usedSec
                        if (remainingSec <= 0L) {
                            // Daily quota reached! Block & suspend for the rest of today!
                            handleDistractingApp(pkg, mode, limitMinutes = limitMinutes)
                            return
                        } else if (limitMinutes > 2 && remainingSec in 1L..120L) {
                            if (!warned2MinPackages.containsKey(pkg)) {
                                warned2MinPackages[pkg] = true
                                send2MinuteWarningNotification(pkg, limitMinutes, remainingSec)
                            }
                        } else if (limitMinutes <= 2 && remainingSec in 1L..30L) {
                            if (!warned2MinPackages.containsKey(pkg)) {
                                warned2MinPackages[pkg] = true
                                send2MinuteWarningNotification(pkg, limitMinutes, remainingSec)
                            }
                        }
                        // Quota remaining: allowed to run!
                    }
                }

                // 2b. YouTube App Shorts Shield (Even while YouTube has remaining quota for classes)
                if (pkg == "com.google.android.youtube") {
                    inspectYouTubeAppForShorts(event)
                }
            }

            // 3. Browser Policy (Strictly enforce ONLY Google Chrome in Time Lock mode)
            val isBrowser = isBrowserPackage(pkg)
            if (isBrowser) {
                if (mode == "time_lock" && !isAllowedGoogleChrome(pkg)) {
                    // All non-Chrome browsers in the world are strictly blocked in Locked In mode!
                    handleForbiddenBrowser(pkg, mode)
                    return
                }

                var nodeToInspect: AccessibilityNodeInfo? = null
                try {
                    nodeToInspect = rootInActiveWindow
                } catch (_: Throwable) {}

                if (nodeToInspect == null) {
                    try {
                        var src = event.source
                        while (src?.parent != null) {
                            src = src.parent
                        }
                        nodeToInspect = src
                    } catch (_: Throwable) {}
                }

                if (nodeToInspect != null) {
                    try {
                        inspectAndBlockBrowser(pkg, nodeToInspect, if (mode == "none") "time_lock" else mode)
                    } finally {
                        try {
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                                @Suppress("DEPRECATION")
                                nodeToInspect.recycle()
                            }
                        } catch (_: Throwable) {}
                    }
                }
            }
        } catch (t: Throwable) {
            android.util.Log.e("DayAuraAccess", "Safe catch in onAccessibilityEvent", t)
        }
    }

    private var shortsWarningDismissRunnable: Runnable? = null

    private fun hideShortsWarningOverlay() {
        mainHandler.post {
            try {
                shortsWarningDismissRunnable?.let { mainHandler.removeCallbacks(it) }
                shortsWarningDismissRunnable = null
                if (shortsWarningView != null) {
                    try { windowManager?.removeView(shortsWarningView) } catch (_: Throwable) {}
                    shortsWarningView = null
                }
            } catch (_: Throwable) {}
        }
    }

    private fun showShortsWarningOverlay() {
        mainHandler.post {
            try {
                shortsWarningDismissRunnable?.let { mainHandler.removeCallbacks(it) }
                shortsWarningDismissRunnable = null
                if (shortsWarningView != null) {
                    try { windowManager?.removeView(shortsWarningView) } catch (_: Throwable) {}
                    shortsWarningView = null
                }
                val wm = windowManager ?: return@post
                val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                    WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                } else {
                    @Suppress("DEPRECATION")
                    WindowManager.LayoutParams.TYPE_PHONE
                }

                val params = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    layoutFlag,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                    PixelFormat.TRANSLUCENT
                ).apply {
                    gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                    y = dpToPx(56f)
                }

                val card = FrameLayout(this).apply {
                    setPadding(dpToPx(16f), dpToPx(12f), dpToPx(16f), dpToPx(12f))
                    val bg = GradientDrawable().apply {
                        setColor(Color.parseColor("#EE800000")) // Deep crimson red
                        cornerRadius = dpToPx(14f).toFloat()
                        setStroke(dpToPx(1.5f), Color.parseColor("#FFFF5252"))
                    }
                    background = bg

                    val tv = TextView(this@DayAuraAccessibilityService).apply {
                        text = "⚠️ YouTube Shorts is blocked in Locked In Mode!\nWatch full classes and lectures only."
                        setTextColor(Color.WHITE)
                        textSize = 13f
                        setTypeface(null, Typeface.BOLD)
                        gravity = Gravity.CENTER
                        setLineSpacing(dpToPx(2f).toFloat(), 1.15f)
                    }
                    addView(tv, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER))
                }

                val container = FrameLayout(this).apply {
                    setPadding(dpToPx(16f), 0, dpToPx(16f), 0)
                    addView(card, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER))
                }

                shortsWarningView = container
                wm.addView(container, params)

                val dismissRunnable = Runnable {
                    try {
                        if (shortsWarningView != null) {
                            wm.removeView(shortsWarningView)
                            shortsWarningView = null
                        }
                    } catch (_: Throwable) {}
                }
                shortsWarningDismissRunnable = dismissRunnable
                mainHandler.postDelayed(dismissRunnable, 2000L)
            } catch (_: Throwable) {}
        }
    }

    private fun inspectYouTubeAppForShorts(event: AccessibilityEvent) {
        val rootNode = try { rootInActiveWindow ?: event.source } catch (_: Throwable) { null } ?: return
        try {
            if (isYouTubeShortsNode(rootNode)) {
                val now = System.currentTimeMillis()
                if (now - lastShortsBlockedTime > 1800L) {
                    lastShortsBlockedTime = now
                    performGlobalAction(GLOBAL_ACTION_BACK)
                    showShortsWarningOverlay()
                }
            }
        } catch (_: Throwable) {}
    }

    private fun isYouTubeShortsNode(rootNode: AccessibilityNodeInfo): Boolean {
        // 1. Bottom navigation "Shorts" tab is actively SELECTED by user
        try {
            val pivotNodes = rootNode.findAccessibilityNodeInfosByViewId("com.google.android.youtube:id/pivot_shorts")
            if (!pivotNodes.isNullOrEmpty()) {
                for (n in pivotNodes) {
                    if (n.isSelected || (n.parent != null && n.parent.isSelected)) {
                        return true
                    }
                }
            }
        } catch (_: Throwable) {}

        try {
            val shortsTextNodes = rootNode.findAccessibilityNodeInfosByText("Shorts")
            if (!shortsTextNodes.isNullOrEmpty()) {
                for (n in shortsTextNodes) {
                    if (n.isSelected || (n.parent != null && n.parent.isSelected)) {
                        return true
                    }
                }
            }
        } catch (_: Throwable) {}

        // 2. Active full-screen vertical Shorts Reel player is actively playing
        // (We specifically DO NOT check reel_recycler_view or shelf items because they appear in related videos and home feed!)
        val activeShortsPlayerIds = listOf(
            "com.google.android.youtube:id/reel_player_overlay_container",
            "com.google.android.youtube:id/reel_watch_fragment",
            "com.google.android.youtube:id/reel_player_page_view",
            "com.google.android.youtube:id/reel_right_side_controls"
        )
        for (viewId in activeShortsPlayerIds) {
            try {
                val nodes = rootNode.findAccessibilityNodeInfosByViewId(viewId)
                if (!nodes.isNullOrEmpty()) {
                    for (n in nodes) {
                        if (n.isVisibleToUser) {
                            return true
                        }
                    }
                }
            } catch (_: Throwable) {}
        }

        return false
    }

    private fun handleDistractingApp(pkg: String, mode: String, limitMinutes: Int = 0) {
        if (redOverlayView != null && currentOverlayPackage == pkg) {
            return
        }

        val now = System.currentTimeMillis()
        if (now - lastBlockedTime < 800L && lastBlockedTarget == pkg) {
            return
        }
        lastBlockedTime = now
        lastBlockedTarget = pkg
        val appLabel = getAppLabelFast(pkg)

        val usedSec = getAppUsageSeconds(pkg)
        val usedMin = (usedSec / 60L).toInt()

        val message = if (limitMinutes > 0) {
            "Daily limit of ${limitMinutes}m reached for $appLabel (0m remaining • Used: ${usedMin}m today)"
        } else {
            "$appLabel is blocked in Locked In mode"
        }

        if (mode == "time_lock") {
            // Hardcore Time Lock: Instant red overlay FIRST to occlude app in 16ms, then eject Home
            showWarningOverlay(
                displayTarget = message,
                targetKey = pkg,
                isTimeLock = true,
                targetPackage = pkg
            )
            performGlobalAction(GLOBAL_ACTION_HOME)

            // If provisioned as Device Owner, hardware-freeze the package (gray icon in launcher)
            try {
                DayAuraDeviceAdminReceiver.suspendSingleApp(this, pkg, true)
            } catch (_: Throwable) {}
        }
    }

    private fun handleForbiddenBrowser(pkg: String, mode: String) {
        if (redOverlayView != null && currentOverlayPackage == pkg) {
            return
        }

        val now = System.currentTimeMillis()
        if (now - lastBlockedTime < 800L && lastBlockedTarget == pkg) {
            return
        }
        lastBlockedTime = now
        lastBlockedTarget = pkg
        val appLabel = getAppLabelFast(pkg)

        val message = "⚠️ Only Google Chrome is permitted in Locked In mode.\n$appLabel is strictly blocked to prevent bypass."

        showWarningOverlay(
            displayTarget = message,
            targetKey = pkg,
            isTimeLock = true,
            targetPackage = pkg
        )
        performGlobalAction(GLOBAL_ACTION_HOME)

        try {
            DayAuraDeviceAdminReceiver.suspendSingleApp(this, pkg, true)
        } catch (_: Throwable) {}
    }

    private val ADDRESS_BAR_VIEW_IDS = listOf(
        "com.android.chrome:id/url_bar",
        "com.android.chrome:id/search_box_text",
        "com.android.chrome:id/location_bar_edit_text",
        "com.android.chrome:id/location_bar",
        "org.chromium.chrome:id/url_bar",
        "org.chromium.chrome:id/search_box_text",
        "com.chrome.beta:id/url_bar",
        "com.chrome.dev:id/url_bar",
        "com.chrome.canary:id/url_bar",
        "com.brave.browser:id/url_bar",
        "com.microsoft.emmx:id/url_bar",
        "org.mozilla.firefox:id/mozac_browser_toolbar_url_view",
        "org.mozilla.firefox:id/url_bar_title",
        "org.mozilla.firefox:id/toolbar_edit_text",
        "com.sec.android.app.sbrowser:id/location_bar_edit_text",
        "com.opera.browser:id/url_field",
        "com.opera.mini.native:id/url_field",
        "com.mi.globalbrowser:id/url",
        "com.mi.globalbrowser:id/title",
        "com.mi.globalbrowser:id/search_hint",
        "com.android.browser:id/url",
        "com.android.browser:id/title",
        "com.miui.browser:id/url",
        "mark.via.gp:id/search_box",
        "mark.via.gp:id/url_bar",
        "mark.via.gp:id/title",
        "mark.via.gp:id/av",
        "com.duckduckgo.mobile.android:id/omnibar_text_view"
    )

    private fun sanitizeBrowserUrl(rawText: String?): String {
        if (rawText.isNullOrBlank()) return ""
        val t = rawText.trim().lowercase(Locale.ROOT)
        if (t.isEmpty()) return ""
        if (t.startsWith("chrome://") ||
            t.startsWith("about:") ||
            t.startsWith("content://") ||
            t.startsWith("file://") ||
            t == "new tab" ||
            t == "search" ||
            t == "google"
        ) {
            return ""
        }

        // Exact match placeholder with no actual URL
        if (t == "search or type web address" || t == "search or type url" || t == "search or enter address") {
            return ""
        }

        // Extract URL if embedded in compound text/contentDescription
        if (t.contains("search or type") || t.contains("search or enter")) {
            val parts = t.split(" ", "\n", "\t")
            for (part in parts) {
                val p = part.trim()
                if (p.contains(".") || p.contains("/")) {
                    if (!p.contains("google.com") && !p.contains("search")) {
                        return p
                    }
                }
            }
            return ""
        }
        return t
    }

    private fun extractUrlFromBrowser(rootNode: AccessibilityNodeInfo): String? {
        // 1. Ultra-fast direct resource ID query
        for (resId in ADDRESS_BAR_VIEW_IDS) {
            try {
                val nodes = rootNode.findAccessibilityNodeInfosByViewId(resId)
                if (!nodes.isNullOrEmpty()) {
                    for (node in nodes) {
                        val text = node.text?.toString()
                        val sanitizedText = sanitizeBrowserUrl(text)
                        if (sanitizedText.isNotEmpty()) return sanitizedText

                        val desc = node.contentDescription?.toString()
                        val sanitizedDesc = sanitizeBrowserUrl(desc)
                        if (sanitizedDesc.isNotEmpty()) return sanitizedDesc
                    }
                }
            } catch (_: Throwable) {}
        }

        // 2. Traversal fallback up to depth 35
        return extractUrlRecursively(rootNode, depth = 0, maxDepth = 35)
    }

    private fun extractUrlRecursively(node: AccessibilityNodeInfo?, depth: Int, maxDepth: Int): String? {
        if (node == null || depth > maxDepth) return null
        val viewId = try { node.viewIdResourceName?.lowercase(Locale.ROOT) ?: "" } catch (_: Throwable) { "" }

        val isUrlBar = viewId.endsWith(":id/url_bar") ||
                viewId.endsWith(":id/url") ||
                viewId.endsWith(":id/location_bar_edit_text") ||
                viewId.endsWith(":id/mozac_browser_toolbar_url_view") ||
                viewId.endsWith(":id/url_field") ||
                viewId.endsWith(":id/search_box_text") ||
                viewId.endsWith(":id/omnibar_text_view") ||
                viewId.endsWith(":id/search_box") ||
                viewId.endsWith(":id/search_hint") ||
                viewId.endsWith(":id/title") ||
                viewId.contains("address_bar") ||
                viewId.contains("location_bar") ||
                viewId.contains("toolbar_url") ||
                viewId.contains("urlbar") ||
                viewId.contains("omnibox")

        if (isUrlBar) {
            val text = try { node.text?.toString() } catch (_: Throwable) { null }
            val s = sanitizeBrowserUrl(text)
            if (s.isNotEmpty()) return s

            val desc = try { node.contentDescription?.toString() } catch (_: Throwable) { null }
            val sd = sanitizeBrowserUrl(desc)
            if (sd.isNotEmpty()) return sd
        }

        val count = try { node.childCount } catch (_: Throwable) { 0 }
        for (i in 0 until count) {
            val child = try { node.getChild(i) } catch (_: Throwable) { null } ?: continue
            val found = extractUrlRecursively(child, depth + 1, maxDepth)
            if (!found.isNullOrBlank()) return found
        }
        return null
    }

    private fun inspectAndBlockBrowser(browserPkg: String, rootNode: AccessibilityNodeInfo, mode: String) {
        // 1. Direct address bar extraction
        val rawUrl = extractUrlFromBrowser(rootNode)
        val sanitizedUrl = if (!rawUrl.isNullOrBlank()) sanitizeBrowserUrl(rawUrl) else ""
        if (sanitizedUrl.isNotEmpty()) {
            val matched = findBlockedDomainMatch(sanitizedUrl)
            if (matched != null) {
                triggerBrowserBlock(browserPkg, matched, mode)
                return
            }

            // Fix for YouTube search results / desktop mode Shorts click:
            // Single Page Application (SPA) or desktop mode might open a Shorts reel player overlay
            // while address bar still displays search results (e.g. m.youtube.com/results?search_query=bitcoin)!
            val isYouTubePage = sanitizedUrl.contains("youtube.com") || sanitizedUrl.contains("youtu.be")
            if (isYouTubePage) {
                val isShortsBlocked = synchronized(blockedWebsites) {
                    blockedWebsites.any { it.contains("shorts") }
                }
                if (isShortsBlocked) {
                    val screenText = extractAllText(rootNode, depth = 0, maxDepth = 20).lowercase(Locale.ROOT)
                    val isActivelyPlayingShort = (screenText.contains("#shorts") && (screenText.contains("remix") || screenText.contains("dislike") || screenText.contains("sound"))) ||
                            (screenText.contains("shorts") && screenText.contains("remix"))
                    if (isActivelyPlayingShort) {
                        triggerBrowserBlock(browserPkg, "youtube.com/shorts", mode)
                        return
                    }
                }
            }
            return
        }

        // 2. Fallback ONLY when address bar could not be read (e.g. customized browser / fullscreen mode)
        val screenText = extractAllText(rootNode, depth = 0, maxDepth = 25).lowercase(Locale.ROOT)
        if (screenText.isBlank()) return

        synchronized(blockedWebsites) {
            val isShortsBlocked = blockedWebsites.any { it.contains("shorts") }
            val isWholeYtBlocked = blockedWebsites.any {
                val c = it.trim().lowercase(Locale.ROOT).replace("http://", "").replace("https://", "").replace("www.", "")
                c == "youtube.com" || c == "m.youtube.com" || c == "youtu.be"
            }
            val isFbReelsBlocked = blockedWebsites.any { it.contains("reel") }
            val isWholeFbBlocked = blockedWebsites.any {
                val c = it.trim().lowercase(Locale.ROOT).replace("http://", "").replace("https://", "").replace("www.", "")
                c == "facebook.com" || c == "m.facebook.com"
            }
            val isIgReelsBlocked = blockedWebsites.any { it.contains("reels") }
            val isWholeIgBlocked = blockedWebsites.any {
                val c = it.trim().lowercase(Locale.ROOT).replace("http://", "").replace("https://", "").replace("www.", "")
                c == "instagram.com" || c == "m.instagram.com"
            }
            val isTikTokBlocked = blockedWebsites.any { it.contains("tiktok") }

            // A. Whole YouTube blocked
            if (isWholeYtBlocked) {
                if (screenText.contains("youtube.com") || screenText.contains("m.youtube.com")) {
                    triggerBrowserBlock(browserPkg, "youtube.com", mode)
                    return
                }
            }

            // B. YouTube Shorts ONLY blocked (Must NOT block normal YouTube homepage or /watch videos!)
            if (isShortsBlocked && !isWholeYtBlocked) {
                val isHomepageOrFeed = (screenText.contains("home") && screenText.contains("subscriptions")) ||
                        screenText.contains("search youtube")
                
                // Shorts player uniquely has vertical reel controls: "remix" AND "#shorts", or remix button
                val isActivelyPlayingShort = !isHomepageOrFeed && (
                    (screenText.contains("#shorts") && (screenText.contains("remix") || screenText.contains("dislike") || screenText.contains("sound"))) ||
                    (screenText.contains("shorts") && screenText.contains("remix"))
                )
                if (isActivelyPlayingShort) {
                    triggerBrowserBlock(browserPkg, "youtube.com/shorts", mode)
                    return
                }
            }

            // C. Whole Facebook blocked
            if (isWholeFbBlocked) {
                if (screenText.contains("facebook.com") || screenText.contains("m.facebook.com")) {
                    triggerBrowserBlock(browserPkg, "facebook.com", mode)
                    return
                }
            }

            // D. Facebook Reels ONLY blocked
            if (isFbReelsBlocked && !isWholeFbBlocked) {
                val isFbFeed = screenText.contains("what's on your mind") || 
                        screenText.contains("news feed") || 
                        (screenText.contains("home") && screenText.contains("notifications"))
                val isActivelyInReel = !isFbFeed && (
                    screenText.contains("original audio") && (screenText.contains("reel") || screenText.contains("reels"))
                )
                if (isActivelyInReel) {
                    triggerBrowserBlock(browserPkg, "facebook.com/reel", mode)
                    return
                }
            }

            // E. Whole Instagram blocked
            if (isWholeIgBlocked) {
                if (screenText.contains("instagram.com") || screenText.contains("m.instagram.com")) {
                    triggerBrowserBlock(browserPkg, "instagram.com", mode)
                    return
                }
            }

            // F. Instagram Reels ONLY blocked
            if (isIgReelsBlocked && !isWholeIgBlocked) {
                val isIgFeed = screenText.contains("stories") || screenText.contains("direct") || screenText.contains("messages")
                val isActivelyInIgReel = !isIgFeed && (
                    (screenText.contains("reel") || screenText.contains("reels")) && (screenText.contains("original audio") || screenText.contains("audio") || screenText.contains("remix"))
                )
                if (isActivelyInIgReel) {
                    triggerBrowserBlock(browserPkg, "instagram.com/reels", mode)
                    return
                }
            }

            // G. TikTok blocked
            if (isTikTokBlocked) {
                if (screenText.contains("tiktok.com")) {
                    triggerBrowserBlock(browserPkg, "tiktok.com", mode)
                    return
                }
            }

            // H. Other custom blocked domains (e.g. reddit.com, twitter.com, x.com)
            for (site in blockedWebsites) {
                val s = site.trim().lowercase(Locale.ROOT)
                if (s.isEmpty()) continue
                val clean = s.replace("http://", "").replace("https://", "").replace("www.", "").trim()
                if (clean.isEmpty()) continue
                if (clean.contains("shorts") || clean.contains("reel") || clean.contains("tiktok")) continue // Handled above

                val cleanWithoutM = if (clean.startsWith("m.")) clean.substring(2) else clean
                if (clean.contains("/")) {
                    if (screenText.contains(clean) || screenText.contains(cleanWithoutM)) {
                        triggerBrowserBlock(browserPkg, clean, mode)
                        return
                    }
                } else {
                    if (screenText.contains(cleanWithoutM) ||
                        screenText.contains(".$cleanWithoutM") ||
                        screenText.contains("://$cleanWithoutM") ||
                        screenText.contains("/$cleanWithoutM")
                    ) {
                        triggerBrowserBlock(browserPkg, clean, mode)
                        return
                    }
                }
            }

            // I. Adult preset check
            if (blockAdultPreset) {
                for (domain in ADULT_DOMAINS) {
                    if (screenText.contains(domain)) {
                        triggerBrowserBlock(browserPkg, domain, mode)
                        return
                    }
                }
                for (kw in ADULT_KEYWORDS) {
                    if (screenText.contains(" $kw ") || screenText.contains("/$kw")) {
                        triggerBrowserBlock(browserPkg, kw, mode)
                        return
                    }
                }
            }

            // J. Gambling preset check
            if (blockGamblingPreset) {
                for (domain in GAMBLING_DOMAINS) {
                    if (screenText.contains(domain)) {
                        triggerBrowserBlock(browserPkg, domain, mode)
                        return
                    }
                }
                for (kw in GAMBLING_KEYWORDS) {
                    if (screenText.contains(" $kw ") || screenText.contains("/$kw")) {
                        triggerBrowserBlock(browserPkg, kw, mode)
                        return
                    }
                }
            }
        }
    }

    private fun findBlockedDomainMatch(url: String): String? {
        val lowerUrl = url.lowercase(Locale.ROOT).trim()
        if (lowerUrl.isEmpty()) return null

        val normalizedUrl = lowerUrl
            .replace("https://", "")
            .replace("http://", "")
            .replace("www.", "")
            .trim()
        val normalizedWithoutM = if (normalizedUrl.startsWith("m.")) normalizedUrl.substring(2) else normalizedUrl

        // Custom & Catalog blocked domains
        synchronized(blockedWebsites) {
            for (site in blockedWebsites) {
                val s = site.trim().lowercase(Locale.ROOT)
                if (s.isEmpty()) continue
                val clean = s.replace("http://", "").replace("https://", "").replace("www.", "").trim()
                if (clean.isEmpty()) continue
                val cleanWithoutM = if (clean.startsWith("m.")) clean.substring(2) else clean

                // Direct path match (e.g. "youtube.com/shorts", "facebook.com/reel", "instagram.com/reels")
                if (clean.contains("/")) {
                    val cleanTrimmed = clean.trimEnd('/')
                    val cleanWithoutMTrimmed = cleanWithoutM.trimEnd('/')

                    var matchesPath = normalizedUrl.contains(cleanTrimmed) ||
                        normalizedWithoutM.contains(cleanWithoutMTrimmed) ||
                        lowerUrl.contains(cleanTrimmed)

                    if (!matchesPath) {
                        if (cleanTrimmed.contains("reel")) {
                            val alt = if (cleanTrimmed.contains("reels")) cleanTrimmed.replace("reels", "reel") else cleanTrimmed.replace("reel", "reels")
                            val altWithoutM = if (cleanWithoutMTrimmed.contains("reels")) cleanWithoutMTrimmed.replace("reels", "reel") else cleanWithoutMTrimmed.replace("reel", "reels")
                            matchesPath = normalizedUrl.contains(alt) || normalizedWithoutM.contains(altWithoutM) || lowerUrl.contains(alt)
                        } else if (cleanTrimmed.contains("short")) {
                            val alt = if (cleanTrimmed.contains("shorts")) cleanTrimmed.replace("shorts", "short") else cleanTrimmed.replace("short", "shorts")
                            val altWithoutM = if (cleanWithoutMTrimmed.contains("shorts")) cleanWithoutMTrimmed.replace("shorts", "short") else cleanWithoutMTrimmed.replace("short", "shorts")
                            matchesPath = normalizedUrl.contains(alt) || normalizedWithoutM.contains(altWithoutM) || lowerUrl.contains(alt)
                        }
                    }

                    if (matchesPath) {
                        return clean
                    }
                    continue // Do not do broad base domain matching for path rules!
                }

                // Whole domain match (e.g. "youtube.com", "m.youtube.com", "facebook.com", "tiktok.com")
                if (normalizedUrl.contains(clean) ||
                    normalizedWithoutM.contains(cleanWithoutM) ||
                    lowerUrl.contains(clean)
                ) {
                    return clean
                }

                // Domain without TLD boundary check
                val base = cleanWithoutM.split(".").first()
                if (base.length >= 4 && (normalizedWithoutM.contains("$base.") || normalizedWithoutM.contains(".$base") || normalizedWithoutM.contains("/$base"))) {
                    return clean
                }
            }
        }

        // Adult keywords & domains in visited URL
        if (blockAdultPreset) {
            for (domain in ADULT_DOMAINS) {
                if (lowerUrl.contains(domain) || normalizedUrl.contains(domain)) {
                    return domain
                }
            }
            for (kw in ADULT_KEYWORDS) {
                if (lowerUrl.contains(kw) || normalizedUrl.contains(kw)) {
                    return kw
                }
            }
        }

        // Gambling keywords & domains in visited URL
        if (blockGamblingPreset) {
            for (domain in GAMBLING_DOMAINS) {
                if (lowerUrl.contains(domain) || normalizedUrl.contains(domain)) {
                    return domain
                }
            }
            for (kw in GAMBLING_KEYWORDS) {
                if (lowerUrl.contains(kw) || normalizedUrl.contains(kw)) {
                    return kw
                }
            }
        }

        return null
    }

    private fun triggerBrowserBlock(browserPkg: String, matchedDomain: String, mode: String) {
        val now = System.currentTimeMillis()
        if (now - lastBlockedTime < 400L && lastBlockedTarget == matchedDomain) {
            return
        }
        lastBlockedTime = now
        lastBlockedTarget = matchedDomain

        // 1. Show Red Warning Alert FIRST (instantly occludes screen in 16ms)
        showWarningOverlay(
            displayTarget = "Website Blocked: $matchedDomain",
            targetKey = "web_$matchedDomain",
            isTimeLock = true,
            targetPackage = browserPkg
        )

        // 2. Press BACK button to exit/leave the blocked video or tab
        performGlobalAction(GLOBAL_ACTION_BACK)

        // 3. Immediately eject user to Home screen behind overlay
        mainHandler.postDelayed({
            performGlobalAction(GLOBAL_ACTION_HOME)
        }, 60L)
    }

    private fun showWarningOverlay(
        displayTarget: String,
        targetKey: String,
        isTimeLock: Boolean,
        targetPackage: String = ""
    ) {
        val showRunnable = Runnable {
            if (redOverlayView != null) {
                if (currentOverlayTarget == targetKey) return@Runnable
                hideWarningOverlay()
            }

            currentOverlayTarget = targetKey
            currentOverlayPackage = if (targetPackage.isNotEmpty()) targetPackage else targetKey
            val wm = windowManager ?: return@Runnable

            val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }

            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                layoutFlag,
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.CENTER
            }

            // Deep crimson red tinted background
            val root = FrameLayout(this@DayAuraAccessibilityService).apply {
                setBackgroundColor(Color.parseColor("#E67F0000")) // 90% opacity deep red
                isClickable = true
                isFocusable = true
            }

            // Center Warning Card
            val card = LinearLayout(this@DayAuraAccessibilityService).apply {
                orientation = LinearLayout.VERTICAL
                val cardBg = GradientDrawable().apply {
                    setColor(Color.parseColor("#1C0606")) // Dark crimson black
                    cornerRadius = dpToPx(20f).toFloat()
                    setStroke(dpToPx(2.5f), Color.parseColor("#FF5252"))
                }
                background = cardBg
                setPadding(dpToPx(22f), dpToPx(24f), dpToPx(22f), dpToPx(22f))
                elevation = dpToPx(16f).toFloat()
            }

            // Warning Icon & Header
            val header = TextView(this@DayAuraAccessibilityService).apply {
                text = "⚠️ WARNING!"
                textSize = 21f
                setTypeface(null, Typeface.BOLD)
                setTextColor(Color.parseColor("#FF5252"))
                gravity = Gravity.CENTER
            }
            card.addView(header)

            // "You are distracted in [AppName / Website]"
            val appWarning = TextView(this@DayAuraAccessibilityService).apply {
                text = "You are distracted in $displayTarget"
                textSize = 16.5f
                setTypeface(null, Typeface.BOLD)
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
                setPadding(0, dpToPx(10f), 0, dpToPx(14f))
            }
            card.addView(appWarning)

            // The Quote
            val quoteBox = LinearLayout(this@DayAuraAccessibilityService).apply {
                orientation = LinearLayout.VERTICAL
                val qBg = GradientDrawable().apply {
                    setColor(Color.parseColor("#2A0B0B"))
                    cornerRadius = dpToPx(10f).toFloat()
                }
                background = qBg
                setPadding(dpToPx(14f), dpToPx(12f), dpToPx(14f), dpToPx(12f))
            }
            val quoteText = TextView(this@DayAuraAccessibilityService).apply {
                text = "\"Remember, life's greatest failures are rarely sudden; they are the accumulation of small failures over time\""
                textSize = 13.5f
                setTypeface(null, Typeface.ITALIC)
                setTextColor(Color.parseColor("#FFCDD2"))
                gravity = Gravity.CENTER
                setLineSpacing(dpToPx(2f).toFloat(), 1.15f)
            }
            quoteBox.addView(quoteText)
            card.addView(quoteBox)

            // Buttons Container
            val buttonsRow = LinearLayout(this@DayAuraAccessibilityService).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(0, dpToPx(18f), 0, 0)
            }

            // Return to Focus Button
            val returnBtn = Button(this@DayAuraAccessibilityService).apply {
                text = "Return to Focus 🛡️"
                textSize = 14f
                setTypeface(null, Typeface.BOLD)
                setTextColor(Color.WHITE)
                val btnBg = GradientDrawable().apply {
                    setColor(Color.parseColor("#20B77A")) // DayAura green
                    cornerRadius = dpToPx(12f).toFloat()
                }
                background = btnBg
                setOnClickListener {
                    hideWarningOverlay()
                    performGlobalAction(GLOBAL_ACTION_HOME)
                }
            }
            buttonsRow.addView(
                returnBtn,
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dpToPx(48f))
            )

            // Time Lock Notice: Snooze Disabled + Emergency Unlock Option
            val lockedNotice = TextView(this@DayAuraAccessibilityService).apply {
                text = "🔒 Time Lock Active: Snooze Prohibited"
                textSize = 12f
                setTextColor(Color.parseColor("#FFCDD2"))
                gravity = Gravity.CENTER
                setPadding(0, dpToPx(10f), 0, dpToPx(4f))
            }
            buttonsRow.addView(lockedNotice)

            val unlockBtn = Button(this@DayAuraAccessibilityService).apply {
                text = "🔑 Emergency Developer Unlock"
                textSize = 12f
                setTextColor(Color.parseColor("#FFA726"))
                val btnBg = GradientDrawable().apply {
                    setColor(Color.parseColor("#33FFA726"))
                    cornerRadius = dpToPx(10f).toFloat()
                    setStroke(dpToPx(1f), Color.parseColor("#80FFA726"))
                }
                background = btnBg
                setOnClickListener {
                    hideWarningOverlay()
                    val intent = Intent(this@DayAuraAccessibilityService, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                        putExtra("open_emergency_unlock", true)
                    }
                    startActivity(intent)
                }
            }
            val unlockParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dpToPx(38f)
            ).apply {
                setMargins(0, dpToPx(6f), 0, 0)
            }
            buttonsRow.addView(unlockBtn, unlockParams)

            card.addView(buttonsRow)

            val cardLayoutParams = FrameLayout.LayoutParams(
                dpToPx(320f),
                FrameLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.CENTER
            }
            root.addView(card, cardLayoutParams)

            try {
                wm.addView(root, params)
                redOverlayView = root
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        if (Looper.myLooper() == Looper.getMainLooper()) {
            showRunnable.run()
        } else {
            mainHandler.post(showRunnable)
        }
    }

    private fun hideWarningOverlay() {
        val hideRunnable = Runnable {
            val v = redOverlayView ?: return@Runnable
            try {
                windowManager?.removeView(v)
            } catch (_: Exception) {}
            redOverlayView = null
            currentOverlayTarget = null
            currentOverlayPackage = null
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            hideRunnable.run()
        } else {
            mainHandler.post(hideRunnable)
        }
    }

    private fun checkAndBlockAntiUninstall(lowerPkg: String, event: AccessibilityEvent? = null) {
        val rootNode = try { rootInActiveWindow ?: event?.source } catch (_: Throwable) { null }
        try {
            val allText = (if (rootNode != null) extractAllText(rootNode) else "").lowercase(Locale.ROOT)
            val className = event?.className?.toString()?.lowercase(Locale.ROOT) ?: ""

            val mentionsApp = allText.contains("dayaura") ||
                    allText.contains("routine_app") ||
                    allText.contains("routine app") ||
                    allText.contains("example.routine") ||
                    allText.contains("com.example.routine_app")

            // Case 1: Direct uninstall confirmation dialogs from PackageInstaller / PermissionController
            val isUninstallDialog = (lowerPkg.contains("packageinstaller") || lowerPkg.contains("permissioncontroller")) &&
                    (allText.contains("uninstall") || allText.contains("do you want to uninstall") || allText.contains("delete this app") ||
                            className.contains("uninstall") || className.contains("uninstaller"))

            // Case 2: Settings or SecurityCenter opening DayAura App Info or Tampering
            val isSettingsTampering = (lowerPkg.contains("settings") || lowerPkg.contains("securitycenter") ||
                    lowerPkg.contains("cleanmaster") || lowerPkg.contains("safecenter")) && mentionsApp

            // Case 3: Play Store uninstallation
            val isPlayStoreTampering = lowerPkg.contains("vending") && mentionsApp &&
                    (allText.contains("uninstall") || allText.contains("disable"))

            // Case 4: Any device admin screen in Settings
            val isDeviceAdminTampering = lowerPkg.contains("settings") && (
                    allText.contains("device admin") || allText.contains("device administrator") ||
                    allText.contains("admin apps") || allText.contains("special app access") ||
                    className.contains("deviceadmin")
            )

            // Case 5: Accessibility settings tampering (trying to turn off DayAura Accessibility)
            val isAccessibilityTampering = lowerPkg.contains("settings") &&
                    (allText.contains("accessibility") || allText.contains("downloaded apps") || allText.contains("installed services") || allText.contains("installed apps")) &&
                    mentionsApp

            // Case 6: MIUI / Phone Cleaner Whitelist tampering (trying to unlock DayAura from Lock Apps)
            val isCleanerLockTampering = (lowerPkg.contains("settings") || lowerPkg.contains("securitycenter")) &&
                    (allText.contains("lock apps") || allText.contains("boost speed") || allText.contains("lock app") || allText.contains("manage app"))

            // Case 7: Date & Time tampering (trying to change system clock forward/backward)
            val isDateTimeTampering = lowerPkg.contains("settings") && (
                    allText.contains("date & time") ||
                    allText.contains("date and time") ||
                    allText.contains("set time") ||
                    allText.contains("change time") ||
                    allText.contains("automatic date")
            )

            // Case 8: VPN / Private DNS tampering in Settings
            val isVpnTampering = lowerPkg.contains("settings") && (
                    allText.contains("vpn") || allText.contains("private dns")
            ) && (
                    mentionsApp || allText.contains("disconnect") || allText.contains("forget") || allText.contains("turn off")
            )

            if (isUninstallDialog || isSettingsTampering || isPlayStoreTampering ||
                isDeviceAdminTampering || isAccessibilityTampering || isCleanerLockTampering ||
                isDateTimeTampering || isVpnTampering) {

                // Eject to Home screen IMMEDIATELY on every single tampering attempt (0ms response)
                performGlobalAction(GLOBAL_ACTION_HOME)

                val now = System.currentTimeMillis()
                if (now - lastBlockedTime > 1500) {
                    lastBlockedTime = now
                    lastBlockedTarget = "anti_uninstall"

                    mainHandler.post {
                        try {
                            Toast.makeText(
                                applicationContext,
                                "🔒 LOCKED IN PROTECTION: System Settings & Uninstall are LOCKED during Time Lock!",
                                Toast.LENGTH_LONG
                            ).show()
                            showWarningOverlay(
                                displayTarget = "DayAura Settings / Uninstall",
                                targetKey = "anti_uninstall",
                                isTimeLock = true,
                                targetPackage = lowerPkg
                            )
                        } catch (_: Throwable) {}
                    }
                }
            }
        } finally {
            try {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                    @Suppress("DEPRECATION")
                    rootNode?.recycle()
                }
            } catch (_: Throwable) {}
        }
    }

    private fun extractAllText(node: AccessibilityNodeInfo?, depth: Int = 0, maxDepth: Int = 25): String {
        if (node == null || depth > maxDepth) return ""
        val sb = StringBuilder()
        try { node.text?.let { sb.append(it).append(" ") } } catch (_: Throwable) {}
        try { node.contentDescription?.let { sb.append(it).append(" ") } } catch (_: Throwable) {}
        val count = try { node.childCount } catch (_: Throwable) { 0 }
        for (i in 0 until count) {
            val child = try { node.getChild(i) } catch (_: Throwable) { null } ?: continue
            sb.append(extractAllText(child, depth + 1, maxDepth)).append(" ")
        }
        return sb.toString()
    }



    private fun getAppLabelFast(pkg: String): String {
        return appLabelCache.getOrPut(pkg) {
            getAppLabel(pkg)
        }
    }

    private fun getAppLabel(pkg: String): String {
        return try {
            val appInfo = packageManager.getApplicationInfo(pkg, 0)
            packageManager.getApplicationLabel(appInfo).toString()
        } catch (_: Exception) {
            pkg
        }
    }

    private fun dpToPx(dp: Float): Int {
        val density = resources.displayMetrics.density
        return (dp * density + 0.5f).toInt()
    }

    override fun onInterrupt() {
        hideWarningOverlay()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        DayAuraWatchdogReceiver.scheduleWatchdog(applicationContext, 100L)
    }

    override fun onDestroy() {
        super.onDestroy()
        hideWarningOverlay()
        mainHandler.removeCallbacks(serviceWatchdogRunnable)
        try { unregisterReceiver(settingsReceiver) } catch (_: Exception) {}
        DayAuraWatchdogReceiver.scheduleWatchdog(applicationContext, 100L)
        isRunning = false
        instance = null
    }
}

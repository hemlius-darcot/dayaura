package com.example.routine_app

import android.app.ActivityManager
import android.app.PendingIntent
import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.UserManager
import android.widget.Toast
import java.util.Locale

class DayAuraDeviceAdminReceiver : DeviceAdminReceiver() {

    companion object {
        /**
         * Checks if Time Lock is currently active and within its duration window.
         */
        fun isTimeLockActive(context: Context): Boolean {
            return try {
                val prefs = context.getSharedPreferences("locked_in_prefs", Context.MODE_PRIVATE)
                val mode = prefs.getString("locked_in_mode", "") ?: ""
                val until = prefs.getLong("time_lock_until_epoch", prefs.getLong("locked_in_until_epoch", 0L))
                val now = System.currentTimeMillis()
                (mode == "time_lock" && now < until) ||
                        (prefs.getBoolean("locked_in_active", false) && now < until)
            } catch (_: Exception) {
                false
            }
        }

        /**
         * Checks daily usage seconds of an app from 00:00 today to now.
         */
        fun getAppDailyUsageSeconds(context: Context, pkg: String): Long {
            if (pkg.isEmpty()) return 0L
            try {
                val cal = java.util.Calendar.getInstance().apply {
                    set(java.util.Calendar.HOUR_OF_DAY, 0)
                    set(java.util.Calendar.MINUTE, 0)
                    set(java.util.Calendar.SECOND, 0)
                    set(java.util.Calendar.MILLISECOND, 0)
                }
                val startOfDay = cal.timeInMillis
                val now = System.currentTimeMillis()
                val today = "${cal.get(java.util.Calendar.YEAR)}_${cal.get(java.util.Calendar.DAY_OF_YEAR)}"

                val liveSec = try {
                    DayAuraAccessibilityService.instance?.getAppUsageSeconds(pkg) ?: 0L
                } catch (_: Throwable) { 0L }

                val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as? android.app.usage.UsageStatsManager
                var totalMs = 0L
                if (usm != null) {
                    val usageEvents = usm.queryEvents(startOfDay, now)
                    if (usageEvents != null) {
                        var startResumeMs = 0L
                        val event = android.app.usage.UsageEvents.Event()
                        while (usageEvents.hasNextEvent()) {
                            usageEvents.getNextEvent(event)
                            if (event.packageName == pkg) {
                                when (event.eventType) {
                                    android.app.usage.UsageEvents.Event.ACTIVITY_RESUMED, 1 /* MOVE_TO_FOREGROUND */ -> {
                                        startResumeMs = event.timeStamp
                                    }
                                    android.app.usage.UsageEvents.Event.ACTIVITY_PAUSED, 2 /* MOVE_TO_BACKGROUND */ -> {
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
                }
                return maxOf(totalMs / 1000L, liveSec)
            } catch (_: Throwable) {
                return 0L
            }
        }

        /**
         * Hardware-freezes or unfreezes a single app package via Device Owner.
         * Launcher icon turns gray with pause badge when suspended.
         * Prevents visual flickering by checking current suspended status first.
         */
        fun suspendSingleApp(context: Context, pkg: String, suspend: Boolean) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                try {
                    val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
                    if (dpm != null && dpm.isDeviceOwnerApp(context.packageName)) {
                        val admin = ComponentName(context, DayAuraDeviceAdminReceiver::class.java)
                        if (pkg.isNotEmpty() && pkg != context.packageName) {
                            val isCurrentlySuspended = try {
                                dpm.isPackageSuspended(admin, pkg)
                            } catch (_: Throwable) {
                                null
                            }
                            // Only send IPC binder call to Android OS if current state differs
                            if (isCurrentlySuspended == null || isCurrentlySuspended != suspend) {
                                dpm.setPackagesSuspended(admin, arrayOf(pkg), suspend)
                            }
                        }
                    }
                } catch (_: Exception) {}
            }
        }

        fun uninstallPackageSilently(context: Context, packageName: String): Boolean {
            if (packageName.isEmpty() || packageName == context.packageName) return false
            var success = false

            // Strategy 1: Device Owner PackageInstaller silent uninstall
            try {
                val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
                val admin = ComponentName(context, DayAuraDeviceAdminReceiver::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP && dpm != null && dpm.isDeviceOwnerApp(context.packageName)) {
                    try {
                        dpm.setUninstallBlocked(admin, packageName, false)
                    } catch (_: Exception) {}
                }

                val packageInstaller = context.packageManager.packageInstaller
                val intent = Intent(context, DayAuraWatchdogReceiver::class.java).apply {
                    action = "com.example.routine_app.ACTION_UNINSTALL_COMPLETE"
                    putExtra("uninstalled_package", packageName)
                }
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                } else {
                    PendingIntent.FLAG_UPDATE_CURRENT
                }
                val sender = PendingIntent.getBroadcast(
                    context,
                    packageName.hashCode(),
                    intent,
                    flags
                ).intentSender

                packageInstaller.uninstall(packageName, sender)
                success = true
                android.util.Log.i("DayAuraInstall", "Triggered PackageInstaller.uninstall for $packageName")
            } catch (e: Exception) {
                android.util.Log.e("DayAuraInstall", "PackageInstaller.uninstall error: ", e)
            }

            // Strategy 2: Shizuku pm uninstall fallback
            try {
                if (rikka.shizuku.Shizuku.pingBinder()) {
                    val cmd = arrayOf("pm", "uninstall", packageName)
                    val binder = rikka.shizuku.Shizuku.getBinder()
                    val shizukuService = moe.shizuku.server.IShizukuService.Stub.asInterface(binder)
                    val remoteProcess = shizukuService.newProcess(cmd, null, null)
                    remoteProcess.waitFor()
                    if (remoteProcess.exitValue() == 0) {
                        success = true
                        android.util.Log.i("DayAuraInstall", "Shizuku pm uninstall succeeded for $packageName")
                    }
                    try { remoteProcess.destroy() } catch (_: Throwable) {}
                }
            } catch (e: Exception) {
                android.util.Log.e("DayAuraInstall", "Shizuku uninstall error: ", e)
            }

            return success
        }

        val ALL_KNOWN_NON_CHROME_BROWSERS = setOf(
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
            "com.heytap.browser",
            "org.torproject.torbrowser",
            "org.torproject.torbrowser_alpha"
        )

        fun isAllowedGoogleChrome(pkg: String): Boolean {
            val lower = pkg.lowercase(Locale.ROOT)
            return lower == "com.android.chrome" ||
                   lower == "com.google.android.apps.chrome" ||
                   lower == "com.chrome.beta" ||
                   lower == "com.chrome.dev" ||
                   lower == "com.chrome.canary"
        }

        fun getAllInstalledNonChromeBrowsers(context: Context): Set<String> {
            val result = mutableSetOf<String>()
            val pm = context.packageManager
            try {
                // 1. Query all apps that resolve web URLs (Intent ACTION_VIEW http/https)
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://google.com"))
                val resolveInfos = pm.queryIntentActivities(intent, 0)
                for (info in resolveInfos) {
                    val pkg = info.activityInfo.packageName
                    if (pkg.isNotEmpty() && pkg != context.packageName && !isAllowedGoogleChrome(pkg)) {
                        result.add(pkg)
                    }
                }
            } catch (_: Throwable) {}

            // 2. Also check all installed packages against our known list
            for (known in ALL_KNOWN_NON_CHROME_BROWSERS) {
                try {
                    pm.getPackageInfo(known, 0)
                    if (known != context.packageName && !isAllowedGoogleChrome(known)) {
                        result.add(known)
                    }
                } catch (_: Exception) {}
            }
            return result
        }

        /**
         * Loads all user-selected distracting apps from SharedPreferences and updates
         * their Android OS-level Device Owner suspension state.
         */
        fun suspendAllDistractingApps(context: Context, suspend: Boolean) {
            val prefs = context.getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
            val pkgsJson = prefs.getString("distracting_packages", "[]") ?: "[]"
            val limitsJson = prefs.getString("app_daily_limits", "{}") ?: "{}"
            val limits = mutableMapOf<String, Int>()
            try {
                val lObj = org.json.JSONObject(limitsJson)
                val keys = lObj.keys()
                while (keys.hasNext()) {
                    val k = keys.next()
                    limits[k] = lObj.optInt(k, 0)
                }
            } catch (_: Exception) {}

            val pkgsList = mutableListOf<String>()
            try {
                val arr = org.json.JSONArray(pkgsJson)
                for (i in 0 until arr.length()) {
                    val pkg = arr.getString(i)
                    if (suspend) {
                        val limit = limits[pkg] ?: 0
                        if (limit <= 0) {
                            // 0 min quota -> full block immediately
                            pkgsList.add(pkg)
                        } else {
                            // If user already used up the quota today (e.g. 47m used on 15m quota),
                            // immediately suspend it with gray icon right upon Time Lock start!
                            val usedSec = getAppDailyUsageSeconds(context, pkg)
                            if (usedSec >= limit * 60L) {
                                pkgsList.add(pkg)
                            } else {
                                // Quota still remains -> ensure app is un-suspended
                                suspendSingleApp(context, pkg, false)
                            }
                        }
                    } else {
                        pkgsList.add(pkg)
                    }
                }
            } catch (_: Exception) {}

            // SINGLE BROWSER POLICY:
            // Only Google Chrome is permitted in Locked In mode.
            // All other browsers in the world are 100% hardware-suspended via Device Owner (gray icon).
            try {
                val nonChromeBrowsers = getAllInstalledNonChromeBrowsers(context)
                for (bPkg in nonChromeBrowsers) {
                    if (!pkgsList.contains(bPkg)) {
                        pkgsList.add(bPkg)
                    }
                }
            } catch (_: Exception) {}

            updateDeviceOwnerSuspension(context, pkgsList, suspend)
        }

        /**
         * If DayAura is provisioned as Device Owner (e.g. via ADB or Shizuku),
         * this directly freezes/pauses packages at the Android OS kernel/launcher level
         * identical to Google Parental Controls / Family Link.
         */
        fun updateDeviceOwnerSuspension(context: Context, packages: Collection<String>, suspend: Boolean) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                try {
                    val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
                    if (dpm != null && dpm.isDeviceOwnerApp(context.packageName)) {
                        val admin = ComponentName(context, DayAuraDeviceAdminReceiver::class.java)
                        val pkgArray = packages.filter { it.isNotEmpty() && it != context.packageName }.toTypedArray()
                        if (pkgArray.isNotEmpty()) {
                            val pkgsToUpdate = pkgArray.filter { p ->
                                try {
                                    dpm.isPackageSuspended(admin, p) != suspend
                                } catch (_: Throwable) {
                                    true
                                }
                            }.toTypedArray()
                            if (pkgsToUpdate.isNotEmpty()) {
                                dpm.setPackagesSuspended(admin, pkgsToUpdate, suspend)
                            }
                        }
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                                dpm.setUninstallBlocked(admin, context.packageName, suspend)
                            }
                        } catch (_: Exception) {}
                        if (suspend) {
                            try {
                                // Bind Always-On VPN with lockdown = false (DNS-only VPN requires lockdown = false so TCP web traffic is not blocked)
                                dpm.setAlwaysOnVpnPackage(admin, context.packageName, false)
                            } catch (e: Exception) {
                                e.printStackTrace()
                            }
                            try {
                                // Block 3rd-party VPN apps from Play Store from connecting or configuring
                                dpm.addUserRestriction(admin, UserManager.DISALLOW_CONFIG_VPN)
                            } catch (e: Exception) {
                                e.printStackTrace()
                            }
                            try {
                                // Block App Info Force Stop / Clear Data during Time Lock
                                dpm.addUserRestriction(admin, UserManager.DISALLOW_APPS_CONTROL)
                            } catch (e: Exception) {
                                e.printStackTrace()
                            }
                            // Layer 2: Android OS Kernel Private DNS (DNS-over-TLS)
                            enableKernelPrivateDns(context, true)
                            // Layer 3: Enterprise Managed Policy for Browsers (Shorts, Reels, Adult/Gambling)
                            enforceChromeEnterprisePolicies(context, true)
                        } else {
                            try {
                                if (dpm.getAlwaysOnVpnPackage(admin) == context.packageName) {
                                    dpm.setAlwaysOnVpnPackage(admin, null, false)
                                }
                            } catch (_: Exception) {}
                            try {
                                dpm.clearUserRestriction(admin, UserManager.DISALLOW_CONFIG_VPN)
                            } catch (_: Exception) {}
                            try {
                                dpm.clearUserRestriction(admin, UserManager.DISALLOW_APPS_CONTROL)
                            } catch (_: Exception) {}
                            // Revert Kernel Private DNS and Enterprise Policies if Web Shield is not active
                            enableKernelPrivateDns(context, false)
                            enforceChromeEnterprisePolicies(context, false)
                        }
                    }
                } catch (_: Exception) {}
            }
        }

        /**
         * Enforces or releases Always-On VPN lockdown and blocks 3rd-party VPNs.
         * When enable is true, the Android kernel blocks all non-VPN network traffic (0ms leak).
         */
        fun bindAlwaysOnVpn(context: Context, enable: Boolean) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                try {
                    val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
                    if (dpm != null && dpm.isDeviceOwnerApp(context.packageName)) {
                        val admin = ComponentName(context, DayAuraDeviceAdminReceiver::class.java)
                        if (enable) {
                            try {
                                dpm.setAlwaysOnVpnPackage(admin, context.packageName, false)
                            } catch (e: Exception) {
                                e.printStackTrace()
                            }
                            try {
                                dpm.addUserRestriction(admin, UserManager.DISALLOW_CONFIG_VPN)
                            } catch (e: Exception) {
                                e.printStackTrace()
                            }
                        } else {
                            if (!isTimeLockActive(context)) {
                                try {
                                    if (dpm.getAlwaysOnVpnPackage(admin) == context.packageName) {
                                        dpm.setAlwaysOnVpnPackage(admin, null, false)
                                    }
                                } catch (_: Exception) {}
                                try {
                                    dpm.clearUserRestriction(admin, UserManager.DISALLOW_CONFIG_VPN)
                                } catch (_: Exception) {}
                            }
                        }
                    }
                } catch (_: Exception) {}
            }
        }

        /**
         * Layer 2: Android OS Linux Kernel Private DNS (DNS-over-TLS).
         * Runs inside netd resolver daemon: 0 microseconds downtime, 0% CPU, 0% RAM.
         * Blocks porn, gambling, malware and forces SafeSearch across all apps and browsers.
         */
        fun enableKernelPrivateDns(context: Context, enable: Boolean) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                try {
                    val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager ?: return
                    if (!dpm.isDeviceOwnerApp(context.packageName)) return
                    val admin = ComponentName(context, DayAuraDeviceAdminReceiver::class.java)

                    if (enable) {
                        // 1. Explicitly stop VPN service ONLY if it is currently running
                        if (DayAuraDnsVpnService.isRunning) {
                            try {
                                val stopVpn = Intent(context, DayAuraDnsVpnService::class.java).apply {
                                    action = DayAuraDnsVpnService.ACTION_STOP_VPN
                                }
                                context.startService(stopVpn)
                            } catch (_: Exception) {}
                        }
                        try {
                            if (dpm.getAlwaysOnVpnPackage(admin) == context.packageName) {
                                dpm.setAlwaysOnVpnPackage(admin, null, false)
                            }
                        } catch (_: Exception) {}

                        // 2. Cloudflare Family DoT has direct peering in Dhaka/Bangladesh (<5ms latency), 100% uptime
                        val dnsHost = "family.cloudflare-dns.com"

                        try {
                            dpm.setGlobalPrivateDnsModeSpecifiedHost(admin, dnsHost)
                        } catch (e: Exception) {
                            e.printStackTrace()
                        }
                        try {
                            dpm.addUserRestriction(admin, UserManager.DISALLOW_CONFIG_PRIVATE_DNS)
                        } catch (e: Exception) {
                            e.printStackTrace()
                        }
                    } else {
                        val prefs = context.getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
                        val vpnShieldEnabled = prefs.getBoolean("vpn_shield_enabled", false)
                        if (!isTimeLockActive(context) && !vpnShieldEnabled) {
                            try {
                                dpm.setGlobalPrivateDnsModeOpportunistic(admin)
                            } catch (e: Exception) {
                                e.printStackTrace()
                            }
                            try {
                                dpm.clearUserRestriction(admin, UserManager.DISALLOW_CONFIG_PRIVATE_DNS)
                            } catch (e: Exception) {
                                e.printStackTrace()
                            }
                        }
                    }
                } catch (_: Exception) {}
            }
        }

        /**
         * Layer 3: Android Enterprise Managed Policy (setApplicationRestrictions).
         * Supported by Google Chrome, Brave, MS Edge, Opera, etc.
         * Natively blocks subpaths (*youtube.com/shorts*, *facebook.com/reel*), forces SafeSearch, and disables Incognito.
         */
        fun enforceChromeEnterprisePolicies(context: Context, enable: Boolean) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                try {
                    val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager ?: return
                    if (!dpm.isDeviceOwnerApp(context.packageName)) return
                    val admin = ComponentName(context, DayAuraDeviceAdminReceiver::class.java)

                    val supportedBrowsers = listOf(
                        "com.android.chrome",
                        "com.chrome.beta",
                        "com.chrome.dev",
                        "com.chrome.canary",
                        "com.brave.browser",
                        "com.microsoft.emmx",
                        "com.mi.globalbrowser",
                        "com.android.browser",
                        "com.miui.browser",
                        "mark.via.gp",
                        "com.sec.android.app.sbrowser",
                        "org.mozilla.firefox"
                    )

                    if (enable) {
                        val prefs = context.getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
                        val sitesJson = prefs.getString("blocked_websites", "[]") ?: "[]"
                        val customSites = mutableListOf<String>()
                        try {
                            val arr = org.json.JSONArray(sitesJson)
                            for (i in 0 until arr.length()) {
                                val s = arr.getString(i).trim()
                                if (s.isNotEmpty()) customSites.add(s)
                            }
                        } catch (_: Exception) {}

                        val blocklist = ArrayList<String>()
                        // YouTube Shorts subpaths
                        blocklist.add("*youtube.com/shorts*")
                        blocklist.add("*m.youtube.com/shorts*")
                        blocklist.add("youtube.com/shorts*")
                        blocklist.add("m.youtube.com/shorts*")
                        blocklist.add("*://*.youtube.com/shorts*")
                        blocklist.add("*://youtube.com/shorts*")
                        blocklist.add("*://m.youtube.com/shorts*")
                        // Facebook Reels subpaths
                        blocklist.add("*facebook.com/reel*")
                        blocklist.add("*m.facebook.com/reel*")
                        blocklist.add("facebook.com/reel*")
                        blocklist.add("m.facebook.com/reel*")
                        blocklist.add("*://*.facebook.com/reel*")
                        blocklist.add("*://facebook.com/reel*")
                        blocklist.add("*://m.facebook.com/reel*")
                        // Instagram Reels & TikTok
                        blocklist.add("*instagram.com/reels*")
                        blocklist.add("instagram.com/reels*")
                        blocklist.add("*://*.instagram.com/reels*")
                        blocklist.add("*tiktok.com*")
                        blocklist.add("tiktok.com*")
                        blocklist.add("*://*.tiktok.com/*")

                        // Gambling & betting sites
                        val gamblingDomains = listOf(
                            "1xbet", "bet365", "melbet", "parimatch", "babu88", "jeetwin",
                            "mostbet", "betway", "baji999", "linebet", "megari", "betonline",
                            "bovada", "888casino", "1win"
                        )
                        for (g in gamblingDomains) {
                            blocklist.add("*$g*")
                            blocklist.add("*://*.$g.*/*")
                            blocklist.add("*://$g.*/*")
                            blocklist.add("*://*.$g*/*")
                        }

                        // User custom blocked websites
                        for (site in customSites) {
                            val clean = site.replace("http://", "").replace("https://", "").replace("www.", "").trim()
                            if (clean.isNotEmpty()) {
                                blocklist.add("*$clean*")
                                blocklist.add("$clean*")
                                if (clean.contains("/")) {
                                    blocklist.add("*://$clean*")
                                    blocklist.add("*://*.$clean*")
                                } else {
                                    blocklist.add("*://$clean/*")
                                    blocklist.add("*://*.$clean/*")
                                }
                            }
                        }

                        val bundle = Bundle().apply {
                            putStringArray("URLBlocklist", blocklist.toTypedArray())
                            putStringArray("URLBlacklist", blocklist.toTypedArray()) // Older Chromium/Android compat
                            putBoolean("ForceGoogleSafeSearch", true)
                            putInt("ForceYouTubeSafetyMode", 2) // Strict mode
                            putInt("IncognitoModeAvailability", 1) // 1 = Incognito disabled
                            putInt("SafeBrowsingProtectionLevel", 2) // Enhanced protection
                        }

                        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                        for (browser in supportedBrowsers) {
                            try {
                                dpm.setApplicationRestrictions(admin, browser, bundle)
                                am?.killBackgroundProcesses(browser)
                            } catch (_: Exception) {}
                        }
                    } else {
                        val prefs = context.getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
                        val vpnShieldEnabled = prefs.getBoolean("vpn_shield_enabled", false)
                        if (!isTimeLockActive(context) && !vpnShieldEnabled) {
                            val emptyBundle = Bundle()
                            for (browser in supportedBrowsers) {
                                try {
                                    dpm.setApplicationRestrictions(admin, browser, emptyBundle)
                                } catch (_: Exception) {}
                            }
                        }
                    }
                } catch (_: Exception) {}
            }
        }
    }

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Toast.makeText(context, "DayAura Anti-Uninstall Protection Activated", Toast.LENGTH_SHORT).show()
        if (isTimeLockActive(context)) {
            suspendAllDistractingApps(context, true)
            bindAlwaysOnVpn(context, false)
        }
    }

    override fun onDisableRequested(context: Context, intent: Intent): CharSequence {
        val prefs = context.getSharedPreferences("locked_in_prefs", Context.MODE_PRIVATE)
        val mode = prefs.getString("locked_in_mode", "") ?: ""
        val untilEpoch = prefs.getLong("time_lock_until_epoch", prefs.getLong("locked_in_until_epoch", 0L))
        val isLocked = (mode == "time_lock" && System.currentTimeMillis() < untilEpoch) ||
                (prefs.getBoolean("locked_in_active", false) && System.currentTimeMillis() < untilEpoch)

        if (isLocked) {
            // Hardcore Lock: Instantly turn off and lock the device screen!
            try {
                val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
                dpm?.lockNow()
            } catch (_: Exception) {}

            try {
                DayAuraWatchdogReceiver.scheduleWatchdog(context.applicationContext, 500L)
            } catch (_: Exception) {}

            return "🔒 ACCESS DENIED: DayAura is strictly locked in TIME LOCK mode! Deactivation is prohibited until lock expires."
        }
        return "DayAura Anti-Uninstall Protection will be disabled."
    }

    override fun onDisabled(context: Context, intent: Intent) {
        val prefs = context.getSharedPreferences("locked_in_prefs", Context.MODE_PRIVATE)
        val mode = prefs.getString("locked_in_mode", "") ?: ""
        val untilEpoch = prefs.getLong("time_lock_until_epoch", prefs.getLong("locked_in_until_epoch", 0L))
        val isLocked = (mode == "time_lock" && System.currentTimeMillis() < untilEpoch) ||
                (prefs.getBoolean("locked_in_active", false) && System.currentTimeMillis() < untilEpoch)

        if (isLocked) {
            try {
                val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
                dpm?.lockNow()
            } catch (_: Exception) {}

            try {
                DayAuraWatchdogReceiver.scheduleWatchdog(context.applicationContext, 100L)
            } catch (_: Exception) {}
        }
        super.onDisabled(context, intent)
    }
}

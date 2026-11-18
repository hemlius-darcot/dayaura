package com.example.routine_app

import android.accessibilityservice.AccessibilityServiceInfo
import android.app.Activity
import android.app.ActivityManager
import android.app.AppOpsManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.admin.DevicePolicyManager
import android.app.usage.UsageStatsManager
import android.app.usage.UsageEvents
import android.content.ComponentName
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.view.accessibility.AccessibilityManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.MediaStore
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import rikka.shizuku.Shizuku
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.example.routine_app/distraction_tracker"
        private const val ALARM_NOTIFICATION_ID = 2002
        private const val SHIZUKU_REQUEST_CODE = 9001
        var methodChannel: MethodChannel? = null
        private var currentRingtone: Ringtone? = null

        fun sendDistractionToFlutter(name: String, timeLabel: String, isoTimestamp: String, id: String): Boolean {
            val channel = methodChannel ?: return false
            Handler(Looper.getMainLooper()).post {
                val map = mapOf(
                    "name" to name,
                    "timeLabel" to timeLabel,
                    "timestamp" to isoTimestamp,
                    "id" to id
                )
                channel.invokeMethod("onDistractionLogged", map)
            }
            return true
        }

        fun sendAppInstallEventToFlutter(packageName: String, appName: String): Boolean {
            val channel = methodChannel ?: return false
            Handler(Looper.getMainLooper()).post {
                val map = mapOf(
                    "packageName" to packageName,
                    "appName" to appName
                )
                channel.invokeMethod("onAppInstalledDuringTimeLock", map)
            }
            return true
        }
    }

    private var packageInstallReceiver: DayAuraPackageInstallReceiver? = null

    private val binderReceivedListener = Shizuku.OnBinderReceivedListener {
        Handler(Looper.getMainLooper()).post {
            methodChannel?.invokeMethod("onShizukuStatusChanged", true)
        }
    }

    private val binderDeadListener = Shizuku.OnBinderDeadListener {
        Handler(Looper.getMainLooper()).post {
            methodChannel?.invokeMethod("onShizukuStatusChanged", false)
        }
    }

    private val shizukuPermissionListener = Shizuku.OnRequestPermissionResultListener { requestCode, grantResult ->
        if (requestCode == SHIZUKU_REQUEST_CODE) {
            val granted = grantResult == PackageManager.PERMISSION_GRANTED
            Handler(Looper.getMainLooper()).post {
                methodChannel?.invokeMethod("onShizukuPermissionResult", granted)
            }
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
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
        } catch (_: Exception) {}
        try {
            Shizuku.addBinderReceivedListenerSticky(binderReceivedListener)
            Shizuku.addBinderDeadListener(binderDeadListener)
            Shizuku.addRequestPermissionResultListener(shizukuPermissionListener)
        } catch (_: Throwable) {}
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "canPostNotifications" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        result.success(checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
                    } else {
                        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        result.success(manager.areNotificationsEnabled())
                    }
                }
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 201)
                    }
                    result.success(true)
                }
                "showAlarmNotification" -> {
                    val title = call.argument<String>("title") ?: "Task Ending Soon"
                    val timeLabel = call.argument<String>("timeLabel") ?: ""
                    val leadMinutes = call.argument<Int>("leadMinutes") ?: 5
                    showTaskAlarmNotification(title, timeLabel, leadMinutes)
                    result.success(true)
                }
                "stopAlarmNotification" -> {
                    stopTaskAlarmNotification()
                    result.success(true)
                }
                "canDrawOverlays" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        var canDraw = Settings.canDrawOverlays(this)
                        if (!canDraw) {
                            try {
                                val appOps = getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
                                val mode = appOps?.checkOpNoThrow(
                                    AppOpsManager.OPSTR_SYSTEM_ALERT_WINDOW,
                                    Process.myUid(),
                                    packageName
                                )
                                canDraw = (mode == AppOpsManager.MODE_ALLOWED)
                            } catch (_: Exception) {}
                        }
                        result.success(canDraw)
                    } else {
                        result.success(true)
                    }
                }
                "requestOverlayPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                    }
                    result.success(null)
                }
                "startFloatingService" -> {
                    val intent = Intent(this, FloatingTrackerService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "stopFloatingService" -> {
                    val intent = Intent(this, FloatingTrackerService::class.java)
                    stopService(intent)
                    result.success(true)
                }
                "isFloatingServiceRunning" -> {
                    result.success(FloatingTrackerService.isRunning)
                }
                "getPendingDistractions" -> {
                    val list = mutableListOf<Map<String, String>>()
                    try {
                        val file = File(filesDir, "pending_distractions.json")
                        if (file.exists() && file.length() > 0) {
                            val array = JSONArray(file.readText())
                            for (i in 0 until array.length()) {
                                val obj = array.getJSONObject(i)
                                list.add(
                                    mapOf(
                                        "id" to obj.optString("id", System.currentTimeMillis().toString()),
                                        "name" to obj.optString("name", "Distracted"),
                                        "timestamp" to obj.optString("timestamp", ""),
                                        "timeLabel" to obj.optString("timeLabel", "")
                                    )
                                )
                            }
                            file.delete()
                        }
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                    result.success(list)
                }
                "getPinnedChips" -> {
                    val prefs = getSharedPreferences("distraction_custom_chips_prefs", Context.MODE_PRIVATE)
                    val json = prefs.getString("pinned_chips", "[]") ?: "[]"
                    val list = mutableListOf<String>()
                    try {
                        val arr = JSONArray(json)
                        for (i in 0 until arr.length()) list.add(arr.getString(i))
                    } catch (_: Exception) {}
                    result.success(list)
                }
                "savePinnedChips" -> {
                    val chips = call.argument<List<String>>("chips") ?: emptyList()
                    val prefs = getSharedPreferences("distraction_custom_chips_prefs", Context.MODE_PRIVATE)
                    val arr = JSONArray()
                    chips.forEach { arr.put(it) }
                    prefs.edit().putString("pinned_chips", arr.toString()).apply()

                    // Strict Google Clipboard Mutual Exclusivity: Remove from recent chips if newly pinned
                    val recentJson = prefs.getString("recent_chips", "[]") ?: "[]"
                    try {
                        val rArr = JSONArray(recentJson)
                        val rList = mutableListOf<String>()
                        for (i in 0 until rArr.length()) {
                            val item = rArr.getString(i)
                            if (chips.none { it.equals(item, ignoreCase = true) }) {
                                rList.add(item)
                            }
                        }
                        val newRArr = JSONArray()
                        rList.take(20).forEach { newRArr.put(it) }
                        prefs.edit().putString("recent_chips", newRArr.toString()).apply()
                    } catch (_: Exception) {}

                    result.success(true)
                }
                "getRecentChips" -> {
                    val prefs = getSharedPreferences("distraction_custom_chips_prefs", Context.MODE_PRIVATE)
                    val pJson = prefs.getString("pinned_chips", "[]") ?: "[]"
                    val pinnedList = mutableListOf<String>()
                    try {
                        val pArr = JSONArray(pJson)
                        for (i in 0 until pArr.length()) pinnedList.add(pArr.getString(i))
                    } catch (_: Exception) {}

                    val json = prefs.getString("recent_chips", "[]") ?: "[]"
                    val list = mutableListOf<String>()
                    try {
                        val arr = JSONArray(json)
                        for (i in 0 until arr.length()) {
                            val it = arr.getString(i)
                            if (pinnedList.none { p -> p.equals(it, ignoreCase = true) }) {
                                list.add(it)
                            }
                        }
                    } catch (_: Exception) {}
                    result.success(list)
                }
                "saveRecentChips" -> {
                    val chips = call.argument<List<String>>("chips") ?: emptyList()
                    val prefs = getSharedPreferences("distraction_custom_chips_prefs", Context.MODE_PRIVATE)
                    val pJson = prefs.getString("pinned_chips", "[]") ?: "[]"
                    val pinnedList = mutableListOf<String>()
                    try {
                        val pArr = JSONArray(pJson)
                        for (i in 0 until pArr.length()) pinnedList.add(pArr.getString(i))
                    } catch (_: Exception) {}

                    val arr = JSONArray()
                    chips.filter { c -> pinnedList.none { p -> p.equals(c, ignoreCase = true) } }
                        .take(20)
                        .forEach { arr.put(it) }
                    prefs.edit().putString("recent_chips", arr.toString()).apply()
                    result.success(true)
                }
                "distractionLogged" -> {
                    try {
                        val name = call.argument<String>("name") ?: ""
                        val timeLabel = call.argument<String>("timeLabel") ?: ""
                        val timestamp = call.argument<String>("timestamp") ?: ""
                        val id = call.argument<String>("id") ?: System.currentTimeMillis().toString()
                        if (name.isNotEmpty()) {
                            appendDailyDistractionFile(id, name, timestamp, timeLabel)
                        }
                    } catch (_: Exception) {}
                    result.success(true)
                }
                "syncTodayDistractions" -> {
                    try {
                        @Suppress("UNCHECKED_CAST")
                        val items = call.argument<List<Map<String, Any>>>("items")
                        if (items != null) {
                            syncDailyDistractionsFile(items)
                        }
                    } catch (_: Exception) {}
                    result.success(true)
                }
                "saveBackupFile" -> {
                    val fileName = call.argument<String>("fileName") ?: "dayaura_backup_${System.currentTimeMillis()}.json"
                    val content = call.argument<String>("content") ?: ""
                    try {
                        var savedPath = ""
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val contentValues = ContentValues().apply {
                                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                                put(MediaStore.MediaColumns.MIME_TYPE, "application/json")
                                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/DayAura")
                            }
                            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                            if (uri != null) {
                                contentResolver.openOutputStream(uri)?.use { outputStream ->
                                    outputStream.write(content.toByteArray(Charsets.UTF_8))
                                    outputStream.flush()
                                }
                                savedPath = "Download/DayAura/$fileName"
                            } else {
                                val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "DayAura")
                                if (!dir.exists()) dir.mkdirs()
                                val file = File(dir, fileName)
                                file.writeText(content, Charsets.UTF_8)
                                savedPath = "Download/DayAura/$fileName"
                            }
                        } else {
                            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "DayAura")
                            if (!dir.exists()) dir.mkdirs()
                            val file = File(dir, fileName)
                            file.writeText(content, Charsets.UTF_8)
                            savedPath = "Download/DayAura/$fileName"
                        }
                        result.success(savedPath)
                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", e.message, null)
                    }
                }
                "playAlarmSound" -> {
                    try {
                        val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                        val ringtone = RingtoneManager.getRingtone(applicationContext, alarmUri)
                        currentRingtone?.stop()
                        currentRingtone = ringtone
                        ringtone.play()
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                            vibrator?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 400, 200, 400), -1))
                        }
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                    result.success(true)
                }
                "stopAlarmSound" -> {
                    stopTaskAlarmNotification()
                    result.success(true)
                }
                "canAccessUsageStats" -> {
                    try {
                        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
                        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
                        } else {
                            appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
                        }
                        result.success(mode == AppOpsManager.MODE_ALLOWED)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "requestUsageStatsPermission" -> {
                    try {
                        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "getInstalledApps" -> {
                    try {
                        val pm = packageManager
                        val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
                            addCategory(Intent.CATEGORY_LAUNCHER)
                        }
                        val resolveInfos = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            pm.queryIntentActivities(mainIntent, PackageManager.ResolveInfoFlags.of(0))
                        } else {
                            pm.queryIntentActivities(mainIntent, 0)
                        }
                        val appList = mutableListOf<Map<String, String>>()
                        val seenPackages = mutableSetOf<String>()
                        for (info in resolveInfos) {
                            val pkg = info.activityInfo.packageName
                            if (pkg == packageName || seenPackages.contains(pkg)) continue
                            seenPackages.add(pkg)
                            val label = info.loadLabel(pm).toString()
                            appList.add(mapOf("packageName" to pkg, "appName" to label))
                        }
                        appList.sortBy { (it["appName"] ?: "").lowercase() }
                        result.success(appList)
                    } catch (e: Exception) {
                        result.success(emptyList<Map<String, String>>())
                    }
                }
                "getDistractingApps" -> {
                    val prefs = getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
                    val json = prefs.getString("distracting_packages", "[]") ?: "[]"
                    val list = mutableListOf<String>()
                    try {
                        val arr = JSONArray(json)
                        for (i in 0 until arr.length()) list.add(arr.getString(i))
                    } catch (_: Exception) {}
                    result.success(list)
                }
                "saveDistractingApps" -> {
                    val pkgs = call.argument<List<String>>("packages") ?: emptyList()
                    val prefs = getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
                    val arr = JSONArray()
                    pkgs.forEach { arr.put(it) }
                    prefs.edit().putString("distracting_packages", arr.toString()).apply()
                    notifySettingsReloaded()
                    if (DayAuraDeviceAdminReceiver.isTimeLockActive(applicationContext)) {
                        DayAuraDeviceAdminReceiver.suspendAllDistractingApps(applicationContext, true)
                    }
                    result.success(true)
                }
                "getAppDailyLimits" -> {
                    val prefs = getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
                    val json = prefs.getString("app_daily_limits", "{}") ?: "{}"
                    val map = mutableMapOf<String, Int>()
                    try {
                        val obj = JSONObject(json)
                        val keys = obj.keys()
                        while (keys.hasNext()) {
                            val k = keys.next()
                            map[k] = obj.optInt(k, 0)
                        }
                    } catch (_: Exception) {}
                    result.success(map)
                }
                "saveAppDailyLimits" -> {
                    val rawLimits = call.argument<Map<*, *>>("limits") ?: emptyMap<Any, Any>()
                    val prefs = getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
                    val obj = JSONObject()
                    rawLimits.forEach { (k, v) ->
                        val pkg = k?.toString()?.trim() ?: ""
                        val limit = (v as? Number)?.toInt() ?: 0
                        if (pkg.isNotEmpty()) {
                            obj.put(pkg, limit)
                        }
                    }
                    prefs.edit().putString("app_daily_limits", obj.toString()).apply()
                    notifySettingsReloaded()
                    if (DayAuraDeviceAdminReceiver.isTimeLockActive(applicationContext)) {
                        DayAuraDeviceAdminReceiver.suspendAllDistractingApps(applicationContext, true)
                    }
                    result.success(true)
                }
                "getAppDailyUsage" -> {
                    val map = mutableMapOf<String, Long>()
                    val cal = Calendar.getInstance().apply {
                        set(Calendar.HOUR_OF_DAY, 0)
                        set(Calendar.MINUTE, 0)
                        set(Calendar.SECOND, 0)
                        set(Calendar.MILLISECOND, 0)
                    }
                    val startOfDay = cal.timeInMillis
                    val now = System.currentTimeMillis()
                    val today = "${cal.get(Calendar.YEAR)}_${cal.get(Calendar.DAY_OF_YEAR)}"

                    try {
                        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
                        if (usm != null) {
                            // Digital Wellbeing-exact foreground screen time calculation from 00:00:00 today
                            val usageEvents = usm.queryEvents(startOfDay, now)
                            if (usageEvents != null) {
                                val startTimes = mutableMapOf<String, Long>()
                                val event = UsageEvents.Event()
                                while (usageEvents.hasNextEvent()) {
                                    usageEvents.getNextEvent(event)
                                    val p = event.packageName ?: continue
                                    when (event.eventType) {
                                        UsageEvents.Event.ACTIVITY_RESUMED, 1 /* MOVE_TO_FOREGROUND */ -> {
                                            startTimes[p] = event.timeStamp
                                        }
                                        UsageEvents.Event.ACTIVITY_PAUSED, 2 /* MOVE_TO_BACKGROUND */ -> {
                                            val startMs = startTimes.remove(p) ?: 0L
                                            if (startMs > 0L && event.timeStamp > startMs) {
                                                map[p] = (map[p] ?: 0L) + ((event.timeStamp - startMs) / 1000L)
                                            }
                                        }
                                    }
                                }
                                for ((p, startMs) in startTimes) {
                                    if (startMs > 0L && now > startMs) {
                                        map[p] = (map[p] ?: 0L) + ((now - startMs) / 1000L)
                                    }
                                }
                            }
                        }
                    } catch (_: Exception) {}

                    try {
                        val prefs = getSharedPreferences("app_usage_daily_prefs", Context.MODE_PRIVATE)
                        val savedDate = prefs.getString("usage_date", "")
                        if (savedDate == today) {
                            val json = prefs.getString("usage_seconds", "{}") ?: "{}"
                            val obj = JSONObject(json)
                            val keys = obj.keys()
                            while (keys.hasNext()) {
                                val k = keys.next()
                                val sec = obj.optLong(k, 0L)
                                map[k] = maxOf(map[k] ?: 0L, sec)
                            }
                        } else {
                            // Date rolled over: clear stale yesterday cache
                            prefs.edit().putString("usage_date", today).putString("usage_seconds", "{}").apply()
                        }
                    } catch (_: Exception) {}

                    // Also ask running AccessibilityService instance for live current foreground second count
                    DayAuraAccessibilityService.instance?.let { service ->
                        val limits = service.getAppDailyLimitsMap()
                        for (pkg in limits.keys) {
                            val liveSec = service.getAppUsageSeconds(pkg, forceSystemQuery = true)
                            map[pkg] = liveSec
                        }
                    }

                    result.success(map)
                }
                "isDeviceAdminActive" -> {
                    try {
                        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                        val comp = ComponentName(this, DayAuraDeviceAdminReceiver::class.java)
                        result.success(dpm.isAdminActive(comp))
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "requestDeviceAdmin" -> {
                    val comp = ComponentName(this, DayAuraDeviceAdminReceiver::class.java)
                    var opened = false

                    // Attempt 1: Standard ACTION_ADD_DEVICE_ADMIN via startActivityForResult
                    try {
                        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                            putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, comp)
                            putExtra(
                                DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                                "DayAura Anti-Uninstall Protection prevents removing DayAura during Locked In focus sessions."
                            )
                        }
                        startActivityForResult(intent, 401)
                        opened = true
                    } catch (_: Exception) {}

                    // Attempt 2: Direct Xiaomi / MIUI DeviceAdminAdd Component
                    if (!opened) {
                        try {
                            val miuiIntent = Intent().apply {
                                component = ComponentName("com.android.settings", "com.android.settings.DeviceAdminAdd")
                                putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, comp)
                                putExtra(
                                    DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                                    "DayAura Anti-Uninstall Protection"
                                )
                            }
                            startActivity(miuiIntent)
                            opened = true
                        } catch (_: Exception) {}
                    }

                    // Attempt 3: Open Device Admin Settings list in Android Settings
                    if (!opened) {
                        try {
                            val listIntent = Intent().apply {
                                component = ComponentName(
                                    "com.android.settings",
                                    "com.android.settings.Settings\$DeviceAdminSettingsActivity"
                                )
                            }
                            startActivity(listIntent)
                            opened = true
                        } catch (_: Exception) {}
                    }

                    // Attempt 4: Fallback to General Security Settings
                    if (!opened) {
                        try {
                            startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
                            opened = true
                        } catch (_: Exception) {}
                    }

                    result.success(opened)
                }
                "isAccessibilityServiceEnabled" -> {
                    try {
                        val am = getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
                        val list = am?.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK) ?: emptyList()
                        val isEnabled = list.any { it.resolveInfo.serviceInfo.packageName == packageName }
                        result.success(isEnabled)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "requestAccessibilityPermission" -> {
                    try {
                        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "getBlockedWebsites" -> {
                    val prefs = getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
                    val json = prefs.getString("blocked_websites", "[]") ?: "[]"
                    val list = mutableListOf<String>()
                    try {
                        val arr = JSONArray(json)
                        for (i in 0 until arr.length()) list.add(arr.getString(i))
                    } catch (_: Exception) {}
                    val blockAdult = prefs.getBoolean("block_adult_preset", true)
                    val blockGambling = prefs.getBoolean("block_gambling_preset", true)
                    val forceSafeSearch = prefs.getBoolean("force_safesearch", true)
                    result.success(mapOf(
                        "websites" to list,
                        "blockAdult" to blockAdult,
                        "blockGambling" to blockGambling,
                        "forceSafeSearch" to forceSafeSearch
                    ))
                }
                "saveBlockedWebsites" -> {
                    val sites = call.argument<List<String>>("websites") ?: emptyList()
                    val blockAdult = call.argument<Boolean>("blockAdult") ?: true
                    val blockGambling = call.argument<Boolean>("blockGambling") ?: true
                    val forceSafeSearch = call.argument<Boolean>("forceSafeSearch") ?: true
                    val prefs = getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
                    val arr = JSONArray()
                    sites.forEach { arr.put(it) }
                    prefs.edit()
                        .putString("blocked_websites", arr.toString())
                        .putBoolean("block_adult_preset", blockAdult)
                        .putBoolean("block_gambling_preset", blockGambling)
                        .putBoolean("force_safesearch", forceSafeSearch)
                        .apply()
                    notifySettingsReloaded()
                    if (DayAuraDeviceAdminReceiver.isTimeLockActive(applicationContext) || prefs.getBoolean("vpn_shield_enabled", false)) {
                        DayAuraDeviceAdminReceiver.enableKernelPrivateDns(applicationContext, true)
                        DayAuraDeviceAdminReceiver.enforceChromeEnterprisePolicies(applicationContext, true)
                    }
                    result.success(true)
                }
                "getLockedInConfig" -> {
                    val prefs = getSharedPreferences("locked_in_prefs", Context.MODE_PRIVATE)
                    val mode = prefs.getString("locked_in_mode", "none") ?: "none"
                    val untilEpoch = prefs.getLong("time_lock_until_epoch", 0L)
                    result.success(mapOf(
                        "mode" to mode,
                        "untilEpoch" to untilEpoch
                    ))
                }
                "setLockedInMode" -> {
                    val mode = call.argument<String>("mode") ?: "none"
                    val untilEpoch = (call.argument<Number>("untilEpoch"))?.toLong() ?: 0L
                    val prefs = getSharedPreferences("locked_in_prefs", Context.MODE_PRIVATE)
                    prefs.edit()
                        .putString("locked_in_mode", mode)
                        .putLong("time_lock_until_epoch", untilEpoch)
                        .putBoolean("locked_in_active", mode == "time_lock")
                        .putLong("locked_in_until_epoch", untilEpoch)
                        .apply()
                    notifySettingsReloaded()
                    val distractingPrefs = getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
                    val pkgsJson = distractingPrefs.getString("distracting_packages", "[]") ?: "[]"
                    val pkgsList = mutableListOf<String>()
                    try {
                        val arr = JSONArray(pkgsJson)
                        for (i in 0 until arr.length()) pkgsList.add(arr.getString(i))
                    } catch (_: Exception) {}

                    if (mode == "time_lock") {
                        DayAuraWatchdogReceiver.scheduleWatchdog(applicationContext, 10_000L)
                        try {
                            val gIntent = Intent(this@MainActivity, DayAuraGuardianService::class.java)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(gIntent)
                            } else {
                                startService(gIntent)
                            }
                        } catch (_: Exception) {}

                        // Ensure VPN is completely stopped during Time Lock to prevent DoT conflict
                        try {
                            val stopVpn = Intent(this@MainActivity, DayAuraDnsVpnService::class.java).apply {
                                action = DayAuraDnsVpnService.ACTION_STOP_VPN
                            }
                            startService(stopVpn)
                            DayAuraDeviceAdminReceiver.bindAlwaysOnVpn(applicationContext, false)
                        } catch (_: Exception) {}

                        DayAuraDeviceAdminReceiver.suspendAllDistractingApps(applicationContext, true)
                        DayAuraDeviceAdminReceiver.enableKernelPrivateDns(applicationContext, true)
                        DayAuraDeviceAdminReceiver.enforceChromeEnterprisePolicies(applicationContext, true)
                    } else {
                        val distPrefs = getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
                        val vpnShield = distPrefs.getBoolean("vpn_shield_enabled", false)
                        if (!vpnShield) {
                            try {
                                stopService(Intent(this@MainActivity, DayAuraGuardianService::class.java))
                            } catch (_: Exception) {}
                            try {
                                val stopVpn = Intent(this@MainActivity, DayAuraDnsVpnService::class.java).apply {
                                    action = DayAuraDnsVpnService.ACTION_STOP_VPN
                                }
                                startService(stopVpn)
                            } catch (_: Exception) {}
                            DayAuraDeviceAdminReceiver.bindAlwaysOnVpn(applicationContext, false)
                            DayAuraDeviceAdminReceiver.enableKernelPrivateDns(applicationContext, false)
                            DayAuraDeviceAdminReceiver.enforceChromeEnterprisePolicies(applicationContext, false)
                        }
                        DayAuraDeviceAdminReceiver.suspendAllDistractingApps(applicationContext, false)
                    }
                    result.success(true)
                }
                "getLockedInState" -> {
                    val prefs = getSharedPreferences("locked_in_prefs", Context.MODE_PRIVATE)
                    val mode = prefs.getString("locked_in_mode", "none") ?: "none"
                    val untilEpoch = prefs.getLong("time_lock_until_epoch", prefs.getLong("locked_in_until_epoch", 0L))
                    val now = System.currentTimeMillis()
                    val active = (mode == "time_lock" && now < untilEpoch) || (prefs.getBoolean("locked_in_active", false) && now < untilEpoch)
                    result.success(mapOf(
                        "mode" to mode,
                        "active" to active,
                        "untilEpoch" to untilEpoch
                    ))
                }
                "setLockedInState" -> {
                    val active = call.argument<Boolean>("active") ?: false
                    val untilEpoch = (call.argument<Number>("untilEpoch"))?.toLong() ?: 0L
                    val mode = if (active) "time_lock" else "none"
                    val prefs = getSharedPreferences("locked_in_prefs", Context.MODE_PRIVATE)
                    prefs.edit()
                        .putString("locked_in_mode", mode)
                        .putLong("time_lock_until_epoch", untilEpoch)
                        .putBoolean("locked_in_active", active)
                        .putLong("locked_in_until_epoch", untilEpoch)
                        .apply()
                    notifySettingsReloaded()
                    val distractingPrefs = getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
                    val pkgsJson = distractingPrefs.getString("distracting_packages", "[]") ?: "[]"
                    val pkgsList = mutableListOf<String>()
                    try {
                        val arr = JSONArray(pkgsJson)
                        for (i in 0 until arr.length()) pkgsList.add(arr.getString(i))
                    } catch (_: Exception) {}

                    if (active) {
                        DayAuraWatchdogReceiver.scheduleWatchdog(applicationContext, 10_000L)
                        try {
                            val gIntent = Intent(this@MainActivity, DayAuraGuardianService::class.java)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(gIntent)
                            } else {
                                startService(gIntent)
                            }
                        } catch (_: Exception) {}
                        // Stop VPN during Time Lock to prevent port 853 Private DNS clash
                        try {
                            val stopVpn = Intent(this@MainActivity, DayAuraDnsVpnService::class.java).apply {
                                action = DayAuraDnsVpnService.ACTION_STOP_VPN
                            }
                            startService(stopVpn)
                            DayAuraDeviceAdminReceiver.bindAlwaysOnVpn(applicationContext, false)
                        } catch (_: Exception) {}

                        DayAuraDeviceAdminReceiver.suspendAllDistractingApps(applicationContext, true)
                        DayAuraDeviceAdminReceiver.enableKernelPrivateDns(applicationContext, true)
                        DayAuraDeviceAdminReceiver.enforceChromeEnterprisePolicies(applicationContext, true)
                    } else {
                        val distPrefs = getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
                        val vpnShield = distPrefs.getBoolean("vpn_shield_enabled", false)
                        if (!vpnShield) {
                            try {
                                stopService(Intent(this@MainActivity, DayAuraGuardianService::class.java))
                            } catch (_: Exception) {}
                            try {
                                val stopVpn = Intent(this@MainActivity, DayAuraDnsVpnService::class.java).apply {
                                    action = DayAuraDnsVpnService.ACTION_STOP_VPN
                                }
                                startService(stopVpn)
                            } catch (_: Exception) {}
                            DayAuraDeviceAdminReceiver.bindAlwaysOnVpn(applicationContext, false)
                        }
                        DayAuraDeviceAdminReceiver.suspendAllDistractingApps(applicationContext, false)
                    }
                    result.success(true)
                }
                "openAutostartSettings" -> {
                    val opened = openAutostartSettings()
                    result.success(opened)
                }
                "openBatteryOptimizationSettings" -> {
                    val opened = openBatteryOptimizationSettings()
                    result.success(opened)
                }
                "isBatteryOptimizationIgnored" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        try {
                            val pm = getSystemService(Context.POWER_SERVICE) as? android.os.PowerManager
                            result.success(pm?.isIgnoringBatteryOptimizations(packageName) ?: false)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "prepareVpn" -> {
                    val intent = android.net.VpnService.prepare(this)
                    if (intent != null) {
                        startActivityForResult(intent, 2048)
                        result.success(false)
                    } else {
                        result.success(true)
                    }
                }
                "startVpn" -> {
                    try {
                        if (DayAuraDeviceAdminReceiver.isTimeLockActive(applicationContext)) {
                            // In Time Lock, Kernel Private DNS & Chrome policies handle protection directly without VPN
                            result.success(true)
                            return@setMethodCallHandler
                        }
                        val prefs = getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
                        prefs.edit().putBoolean("vpn_shield_enabled", true).apply()
                        DayAuraDeviceAdminReceiver.bindAlwaysOnVpn(applicationContext, true)
                        DayAuraDeviceAdminReceiver.enableKernelPrivateDns(applicationContext, true)
                        DayAuraDeviceAdminReceiver.enforceChromeEnterprisePolicies(applicationContext, true)
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
                        // Start Guardian daemon to protect VPN
                        try {
                            val gIntent = Intent(this, DayAuraGuardianService::class.java)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(gIntent)
                            } else {
                                startService(gIntent)
                            }
                        } catch (_: Exception) {}
                        DayAuraWatchdogReceiver.scheduleWatchdog(applicationContext, 10_000L)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "stopVpn" -> {
                    try {
                        val prefs = getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
                        prefs.edit().putBoolean("vpn_shield_enabled", false).apply()
                        val stopIntent = Intent(this, DayAuraDnsVpnService::class.java).apply {
                            action = DayAuraDnsVpnService.ACTION_STOP_VPN
                        }
                        startService(stopIntent)
                        if (!DayAuraDeviceAdminReceiver.isTimeLockActive(applicationContext)) {
                            DayAuraDeviceAdminReceiver.bindAlwaysOnVpn(applicationContext, false)
                            DayAuraDeviceAdminReceiver.enableKernelPrivateDns(applicationContext, false)
                            DayAuraDeviceAdminReceiver.enforceChromeEnterprisePolicies(applicationContext, false)
                            try {
                                stopService(Intent(this, DayAuraGuardianService::class.java))
                            } catch (_: Exception) {}
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "isVpnRunning" -> {
                    val fileActive = File(filesDir, "vpn_running").exists()
                    result.success(DayAuraDnsVpnService.isRunning || fileActive || isServiceRunning(DayAuraDnsVpnService::class.java))
                }
                "startGuardian" -> {
                    try {
                        val gIntent = Intent(this, DayAuraGuardianService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(gIntent)
                        } else {
                            startService(gIntent)
                        }
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "checkShizukuStatus" -> {
                    val isRunning = try { Shizuku.pingBinder() } catch (_: Throwable) { false }
                    val hasPermission = if (isRunning) {
                        try {
                            if (Shizuku.isPreV11()) {
                                checkSelfPermission("moe.shizuku.manager.permission.API_V23") == PackageManager.PERMISSION_GRANTED
                            } else {
                                Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
                            }
                        } catch (_: Throwable) { false }
                    } else false
                    val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                    val isOwner = dpm.isDeviceOwnerApp(packageName)
                    result.success(mapOf(
                        "isRunning" to isRunning,
                        "hasPermission" to hasPermission,
                        "isDeviceOwner" to isOwner
                    ))
                }
                "requestShizukuPermission" -> {
                    try {
                        if (!Shizuku.pingBinder()) {
                            result.success(mapOf("success" to false, "message" to "Shizuku is not running"))
                            return@setMethodCallHandler
                        }
                        val hasPerm = if (Shizuku.isPreV11()) {
                            checkSelfPermission("moe.shizuku.manager.permission.API_V23") == PackageManager.PERMISSION_GRANTED
                        } else {
                            Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
                        }
                        if (hasPerm) {
                            result.success(mapOf("success" to true, "message" to "Permission already granted"))
                        } else {
                            if (Shizuku.isPreV11()) {
                                requestPermissions(arrayOf("moe.shizuku.manager.permission.API_V23"), SHIZUKU_REQUEST_CODE)
                            } else {
                                Shizuku.requestPermission(SHIZUKU_REQUEST_CODE)
                            }
                            result.success(mapOf("success" to true, "message" to "Permission requested"))
                        }
                    } catch (e: Throwable) {
                        result.success(mapOf("success" to false, "message" to (e.message ?: "Failed to request permission")))
                    }
                }
                "activateDeviceOwnerViaShizuku" -> {
                    val autoRemoveUsers = call.argument<Boolean>("autoRemoveUsers") ?: false
                    val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                    if (dpm.isDeviceOwnerApp(packageName)) {
                        result.success(mapOf(
                            "success" to true,
                            "isDeviceOwner" to true,
                            "message" to "DayAura is already Device Owner!"
                        ))
                        return@setMethodCallHandler
                    }

                    val isRunning = try { Shizuku.pingBinder() } catch (_: Throwable) { false }
                    if (!isRunning) {
                        result.success(mapOf(
                            "success" to false,
                            "isDeviceOwner" to false,
                            "message" to "Shizuku service is not running. Please launch Shizuku and start it via Wireless Debugging first."
                        ))
                        return@setMethodCallHandler
                    }

                    val hasPerm = try {
                        if (Shizuku.isPreV11()) {
                            checkSelfPermission("moe.shizuku.manager.permission.API_V23") == PackageManager.PERMISSION_GRANTED
                        } else {
                            Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
                        }
                    } catch (_: Throwable) { false }

                    if (!hasPerm) {
                        try {
                            if (Shizuku.isPreV11()) {
                                requestPermissions(arrayOf("moe.shizuku.manager.permission.API_V23"), SHIZUKU_REQUEST_CODE)
                            } else {
                                Shizuku.requestPermission(SHIZUKU_REQUEST_CODE)
                            }
                        } catch (_: Throwable) {}
                        result.success(mapOf(
                            "success" to false,
                            "isDeviceOwner" to false,
                            "needPermission" to true,
                            "message" to "Shizuku permission requested. Please tap 'Allow' or 'Always Allow' in the popup, then tap activate again."
                        ))
                        return@setMethodCallHandler
                    }

                    Thread {
                        try {
                            val binder = Shizuku.getBinder()
                            val shizukuService = moe.shizuku.server.IShizukuService.Stub.asInterface(binder)

                            if (autoRemoveUsers) {
                                try {
                                    val listProc = shizukuService.newProcess(arrayOf("pm", "list", "users"), null, null)
                                    val listOut = listProc.inputStream?.let { android.os.ParcelFileDescriptor.AutoCloseInputStream(it).bufferedReader().readText() } ?: ""
                                    listProc.waitFor()
                                    try { listProc.destroy() } catch (_: Throwable) {}

                                    val regex = Regex("""UserInfo\{(\d+):""")
                                    for (m in regex.findAll(listOut)) {
                                        val uid = m.groupValues[1].toIntOrNull()
                                        if (uid != null && uid != 0) {
                                            val remProc = shizukuService.newProcess(arrayOf("pm", "remove-user", uid.toString()), null, null)
                                            remProc.waitFor()
                                            try { remProc.destroy() } catch (_: Throwable) {}
                                        }
                                    }
                                    Thread.sleep(600L)
                                } catch (_: Throwable) {}
                            }

                            val candidateCmds = listOf(
                                arrayOf("sh", "-c", "dpm set-device-owner $packageName/.DayAuraDeviceAdminReceiver"),
                                arrayOf("sh", "-c", "dpm set-device-owner --user 0 $packageName/.DayAuraDeviceAdminReceiver")
                            )

                            var output = ""
                            var exitCode = -1
                            var isOwnerNow = dpm.isDeviceOwnerApp(packageName)
                            var detectedHasAccounts = false
                            var detectedSeveralUsers = false

                            for (cmd in candidateCmds) {
                                if (isOwnerNow) break
                                try {
                                    val remoteProcess = shizukuService.newProcess(cmd, null, null)
                                    val out = remoteProcess.inputStream?.let { android.os.ParcelFileDescriptor.AutoCloseInputStream(it).bufferedReader().readText() } ?: ""
                                    val err = remoteProcess.errorStream?.let { android.os.ParcelFileDescriptor.AutoCloseInputStream(it).bufferedReader().readText() } ?: ""
                                    exitCode = remoteProcess.waitFor()
                                    try { remoteProcess.destroy() } catch (_: Throwable) {}
                                    val curOut = (out + "\n" + err).trim()
                                    if (curOut.isNotEmpty()) {
                                        output = curOut
                                    }

                                    if (curOut.contains("already some accounts", ignoreCase = true) || curOut.contains("accounts on the device", ignoreCase = true)) {
                                        detectedHasAccounts = true
                                        output = curOut
                                        break
                                    }
                                    if (curOut.contains("several users", ignoreCase = true)) {
                                        detectedSeveralUsers = true
                                        output = curOut
                                        break
                                    }

                                    Thread.sleep(300L)
                                    isOwnerNow = dpm.isDeviceOwnerApp(packageName)
                                    if (isOwnerNow) break
                                } catch (_: Throwable) {}
                            }

                            if (!isOwnerNow) {
                                Thread.sleep(600L)
                                isOwnerNow = dpm.isDeviceOwnerApp(packageName)
                            }
                            val success = isOwnerNow
                            if (success) {
                                try {
                                    val autostartCmds = listOf(
                                        arrayOf("cmd", "appops", "set", packageName, "AUTO_START", "allow"),
                                        arrayOf("cmd", "appops", "set", packageName, "OP_AUTO_START", "allow"),
                                        arrayOf("cmd", "appops", "set", packageName, "RUN_IN_BACKGROUND", "allow"),
                                        arrayOf("dumpsys", "deviceidle", "whitelist", "+$packageName")
                                    )
                                    for (ac in autostartCmds) {
                                        try {
                                            val p = shizukuService.newProcess(ac, null, null)
                                            p.waitFor()
                                            try { p.destroy() } catch (_: Throwable) {}
                                        } catch (_: Throwable) {}
                                    }
                                } catch (_: Throwable) {}

                                if (DayAuraDeviceAdminReceiver.isTimeLockActive(applicationContext)) {
                                    DayAuraDeviceAdminReceiver.suspendAllDistractingApps(applicationContext, true)
                                    DayAuraDeviceAdminReceiver.bindAlwaysOnVpn(applicationContext, false)
                                } else {
                                    val distPrefs = getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
                                    if (distPrefs.getBoolean("vpn_shield_enabled", false)) {
                                        DayAuraDeviceAdminReceiver.bindAlwaysOnVpn(applicationContext, true)
                                    }
                                }
                            }
                            val detectedAccounts = mutableListOf<String>()
                            if (!success) {
                                try {
                                    val accProc = shizukuService.newProcess(arrayOf("dumpsys", "account"), null, null)
                                    val accOut = accProc.inputStream?.let { android.os.ParcelFileDescriptor.AutoCloseInputStream(it).bufferedReader().readText() } ?: ""
                                    accProc.waitFor()
                                    try { accProc.destroy() } catch (_: Throwable) {}
                                    val accRegex = Regex("""Account \{name=(.*?), type=(.*?)\}""")
                                    for (m in accRegex.findAll(accOut)) {
                                        val name = m.groupValues[1]
                                        val type = m.groupValues[2]
                                        detectedAccounts.add("$name ($type)")
                                    }
                                } catch (_: Throwable) {}
                            }

                            val severalUsers = detectedSeveralUsers || output.contains("several users", ignoreCase = true)
                            val hasAccounts = detectedHasAccounts ||
                                    detectedAccounts.isNotEmpty() ||
                                    output.contains("already some accounts", ignoreCase = true) ||
                                    output.contains("accounts on the device", ignoreCase = true)

                            Handler(Looper.getMainLooper()).post {
                                result.success(mapOf(
                                    "success" to success,
                                    "isDeviceOwner" to isOwnerNow,
                                    "exitCode" to exitCode,
                                    "output" to output,
                                    "severalUsers" to severalUsers,
                                    "hasAccounts" to hasAccounts,
                                    "accounts" to detectedAccounts
                                ))
                            }
                        } catch (t: Throwable) {
                            Handler(Looper.getMainLooper()).post {
                                result.success(mapOf(
                                    "success" to false,
                                    "isDeviceOwner" to dpm.isDeviceOwnerApp(packageName),
                                    "message" to (t.message ?: "Failed to execute command via Shizuku")
                                ))
                            }
                        }
                    }.start()
                }
                "removeSecondaryUsersViaShizuku" -> {
                    val isRunning = try { Shizuku.pingBinder() } catch (_: Throwable) { false }
                    if (!isRunning) {
                        result.success(mapOf("success" to false, "message" to "Shizuku not running"))
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val binder = Shizuku.getBinder()
                            val shizukuService = moe.shizuku.server.IShizukuService.Stub.asInterface(binder)
                            val listProc = shizukuService.newProcess(arrayOf("pm", "list", "users"), null, null)
                            val listOut = listProc.inputStream?.let { android.os.ParcelFileDescriptor.AutoCloseInputStream(it).bufferedReader().readText() } ?: ""
                            listProc.waitFor()
                            try { listProc.destroy() } catch (_: Throwable) {}

                            val regex = Regex("""UserInfo\{(\d+):""")
                            var count = 0
                            for (m in regex.findAll(listOut)) {
                                val uid = m.groupValues[1].toIntOrNull()
                                if (uid != null && uid != 0) {
                                    val remProc = shizukuService.newProcess(arrayOf("pm", "remove-user", uid.toString()), null, null)
                                    remProc.waitFor()
                                    try { remProc.destroy() } catch (_: Throwable) {}
                                    count++
                                }
                            }
                            Thread.sleep(600L)
                            Handler(Looper.getMainLooper()).post {
                                result.success(mapOf("success" to true, "removedCount" to count))
                            }
                        } catch (t: Throwable) {
                            Handler(Looper.getMainLooper()).post {
                                result.success(mapOf("success" to false, "message" to (t.message ?: "Failed to remove users")))
                            }
                        }
                    }.start()
                }
                "openDualAppsSettings" -> {
                    try {
                        val intent = Intent().apply {
                            component = ComponentName("com.miui.securityadd", "com.miui.securityadd.dualapp.DualAppSettingsActivity")
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (_: Exception) {
                        try {
                            val fallback = Intent(Settings.ACTION_APPLICATION_SETTINGS).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(fallback)
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                }
                "openAccountsSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_SYNC_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "isDeviceOwner" -> {
                    val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                    result.success(dpm.isDeviceOwnerApp(packageName))
                }
                "openShizukuApp" -> {
                    try {
                        val launchIntent = packageManager.getLaunchIntentForPackage("moe.shizuku.privileged.api")
                        if (launchIntent != null) {
                            launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            startActivity(launchIntent)
                            result.success(true)
                        } else {
                            val playStoreIntent = Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=moe.shizuku.privileged.api")).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(playStoreIntent)
                            result.success(true)
                        }
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "releaseDeviceOwner" -> {
                    val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                    if (!dpm.isDeviceOwnerApp(packageName)) {
                        result.success(mapOf("success" to true, "message" to "Not device owner"))
                        return@setMethodCallHandler
                    }
                    try {
                        dpm.clearDeviceOwnerApp(packageName)
                        val stillOwner = dpm.isDeviceOwnerApp(packageName)
                        result.success(mapOf("success" to !stillOwner, "isDeviceOwner" to stillOwner))
                    } catch (e: Exception) {
                        val isRunning = try { Shizuku.pingBinder() } catch (_: Throwable) { false }
                        if (isRunning) {
                            Thread {
                                try {
                                    val cmd = arrayOf("dpm", "remove-active-admin", "$packageName/.DayAuraDeviceAdminReceiver")
                                    val binder = Shizuku.getBinder()
                                    val shizukuService = moe.shizuku.server.IShizukuService.Stub.asInterface(binder)
                                    val remoteProcess = shizukuService.newProcess(cmd, null, null)
                                    remoteProcess.waitFor()
                                    try { remoteProcess.destroy() } catch (_: Throwable) {}
                                    val stillOwner = dpm.isDeviceOwnerApp(packageName)
                                    Handler(Looper.getMainLooper()).post {
                                        result.success(mapOf("success" to !stillOwner, "isDeviceOwner" to stillOwner))
                                    }
                                } catch (t: Throwable) {
                                    Handler(Looper.getMainLooper()).post {
                                        result.success(mapOf("success" to false, "message" to (t.message ?: e.message)))
                                    }
                                }
                            }.start()
                        } else {
                            result.success(mapOf("success" to false, "message" to e.message))
                        }
                    }
                }
                "uninstallPackageSilently" -> {
                    val pkg = call.argument<String>("packageName") ?: ""
                    val ok = DayAuraDeviceAdminReceiver.uninstallPackageSilently(applicationContext, pkg)
                    DayAuraPackageInstallReceiver.removePendingApp(applicationContext, pkg)
                    result.success(ok)
                }
                "unfreezePackage" -> {
                    val pkg = call.argument<String>("packageName") ?: ""
                    DayAuraDeviceAdminReceiver.suspendSingleApp(applicationContext, pkg, false)
                    DayAuraPackageInstallReceiver.removePendingApp(applicationContext, pkg)
                    result.success(true)
                }
                "getPendingInstalledApps" -> {
                    val list = DayAuraPackageInstallReceiver.getPendingApps(applicationContext)
                    result.success(list)
                }
                "removePendingInstalledApp" -> {
                    val pkg = call.argument<String>("packageName") ?: ""
                    DayAuraPackageInstallReceiver.removePendingApp(applicationContext, pkg)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 2048 && resultCode == Activity.RESULT_OK) {
            try {
                val vpnIntent = Intent(this, DayAuraDnsVpnService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(vpnIntent)
                } else {
                    startService(vpnIntent)
                }
            } catch (_: Exception) {}
        }
    }

    private fun notifySettingsReloaded() {
        try {
            FloatingTrackerService.reloadDistractingApps()
            DayAuraAccessibilityService.reloadAllSettings()
            val intent = Intent(DayAuraWatchdogReceiver.ACTION_RELOAD_SETTINGS).apply {
                setPackage(packageName)
            }
            sendBroadcast(intent)
            val vpnReload = Intent(DayAuraDnsVpnService.ACTION_RELOAD_VPN_SETTINGS).apply {
                setPackage(packageName)
            }
            sendBroadcast(vpnReload)
        } catch (_: Exception) {}
    }

    private fun openAutostartSettings(): Boolean {
        val manufacturer = Build.MANUFACTURER.lowercase(java.util.Locale.ROOT)
        try {
            val intent = Intent()
            if (manufacturer.contains("xiaomi") || manufacturer.contains("redmi")) {
                intent.component = ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity"
                )
            } else if (manufacturer.contains("oppo") || manufacturer.contains("realme")) {
                intent.component = ComponentName(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.permission.startup.StartupAppListActivity"
                )
            } else if (manufacturer.contains("vivo")) {
                intent.component = ComponentName(
                    "com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
                )
            } else if (manufacturer.contains("huawei") || manufacturer.contains("honor")) {
                intent.component = ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.optimize.process.ProtectActivity"
                )
            } else {
                return false
            }
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            startActivity(intent)
            return true
        } catch (_: Exception) {
            try {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(intent)
                return true
            } catch (_: Exception) {
                return false
            }
        }
    }

    private fun openBatteryOptimizationSettings(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(intent)
                return true
            } catch (_: Exception) {}
            try {
                val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(intent)
                return true
            } catch (_: Exception) {}
        }
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
            return true
        } catch (_: Exception) {
            return false
        }
    }

    private fun showTaskAlarmNotification(title: String, timeLabel: String, leadMinutes: Int) {
        try {
            val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val ringtone = RingtoneManager.getRingtone(applicationContext, alarmUri)
            currentRingtone?.stop()
            currentRingtone = ringtone
            ringtone?.play()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                vibrator?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 500, 250, 500), -1))
            }

            val channelId = "routine_task_alarms"
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    channelId,
                    "Task Alarms",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "High priority alarms for routine tasks"
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 500, 250, 500)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
                notificationManager.createNotificationChannel(channel)
            }

            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
            )

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, channelId)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }

            val contentText = if (timeLabel.isNotEmpty()) {
                "Ends at $timeLabel ($leadMinutes min remaining). Tap to view."
            } else {
                "$leadMinutes min remaining. Tap to view."
            }

            builder.setContentTitle("⏰ Task Alarm: $title")
                .setContentText(contentText)
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentIntent(pendingIntent)
                .setFullScreenIntent(pendingIntent, true)
                .setAutoCancel(true)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                builder.setCategory(Notification.CATEGORY_ALARM)
                builder.setPriority(Notification.PRIORITY_MAX)
            }

            notificationManager.notify(ALARM_NOTIFICATION_ID, builder.build())
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopTaskAlarmNotification() {
        try {
            currentRingtone?.stop()
            currentRingtone = null
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancel(ALARM_NOTIFICATION_ID)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onResume() {
        super.onResume()
        if (DayAuraDeviceAdminReceiver.isTimeLockActive(applicationContext)) {
            DayAuraDeviceAdminReceiver.suspendAllDistractingApps(applicationContext, true)
            DayAuraDeviceAdminReceiver.bindAlwaysOnVpn(applicationContext, false)
        }
        checkUnlockIntent(intent)
    }

    private fun isServiceRunning(serviceClass: Class<*>): Boolean {
        return try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager ?: return false
            @Suppress("DEPRECATION")
            for (service in am.getRunningServices(Int.MAX_VALUE)) {
                if (serviceClass.name == service.service.className) {
                    return true
                }
            }
            false
        } catch (_: Exception) {
            false
        }
    }

    private fun appendDailyDistractionFile(id: String, name: String, timestamp: String, timeLabel: String) {
        try {
            val todayKey = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
            val file = File(filesDir, "daily_distractions_log.json")
            val root = if (file.exists() && file.length() > 0) {
                try { JSONObject(file.readText()) } catch (_: Exception) { JSONObject() }
            } else {
                JSONObject()
            }
            val savedDate = root.optString("date", "")
            val items = if (savedDate == todayKey) {
                root.optJSONArray("items") ?: JSONArray()
            } else {
                JSONArray()
            }

            var isDup = false
            for (i in 0 until items.length()) {
                val obj = items.getJSONObject(i)
                if (obj.optString("id") == id) {
                    isDup = true
                    break
                }
            }

            if (!isDup) {
                val obj = JSONObject().apply {
                    put("id", id)
                    put("name", name)
                    put("timestamp", timestamp)
                    put("timeLabel", timeLabel)
                }
                items.put(obj)
                root.put("date", todayKey)
                root.put("items", items)
                file.writeText(root.toString())
            }
        } catch (_: Exception) {}
    }

    private fun syncDailyDistractionsFile(itemsList: List<Map<String, Any>>) {
        try {
            val todayKey = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
            val file = File(filesDir, "daily_distractions_log.json")
            val root = JSONObject()
            val arr = JSONArray()
            for (m in itemsList) {
                val obj = JSONObject().apply {
                    put("id", m["id"]?.toString() ?: "")
                    put("name", m["name"]?.toString() ?: "")
                    put("timestamp", m["timestamp"]?.toString() ?: "")
                    put("timeLabel", m["timeLabel"]?.toString() ?: "")
                }
                arr.put(obj)
            }
            root.put("date", todayKey)
            root.put("items", arr)
            file.writeText(root.toString())
        } catch (_: Exception) {}
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        checkUnlockIntent(intent)
    }

    private fun checkUnlockIntent(intent: Intent?) {
        if (intent?.getBooleanExtra("open_emergency_unlock", false) == true) {
            intent.removeExtra("open_emergency_unlock")
            Handler(Looper.getMainLooper()).postDelayed({
                methodChannel?.invokeMethod("openEmergencyUnlock", null)
            }, 300)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        methodChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        try {
            if (packageInstallReceiver != null) {
                unregisterReceiver(packageInstallReceiver)
                packageInstallReceiver = null
            }
        } catch (_: Exception) {}
        try {
            Shizuku.removeBinderReceivedListener(binderReceivedListener)
            Shizuku.removeBinderDeadListener(binderDeadListener)
            Shizuku.removeRequestPermissionResultListener(shizukuPermissionListener)
        } catch (_: Throwable) {}
        methodChannel = null
        super.onDestroy()
    }
}

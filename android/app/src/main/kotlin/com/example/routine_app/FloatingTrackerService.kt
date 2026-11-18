package com.example.routine_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.TextView
import android.widget.Toast
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs

class FloatingTrackerService : Service() {

    companion object {
        var isRunning = false
        var instance: FloatingTrackerService? = null

        fun isSnoozed(): Boolean {
            val inst = instance ?: return false
            return System.currentTimeMillis() < inst.snoozedUntil
        }

        fun reloadDistractingApps() {
            instance?.loadDistractingPackages()
        }

        fun showWebsiteWarningOverlay(domain: String) {
            Handler(Looper.getMainLooper()).post {
                instance?.showRedOverlayForWebsite(domain)
            }
        }

        fun showAppWarningOverlay(pkg: String) {
            Handler(Looper.getMainLooper()).post {
                instance?.showRedOverlay(pkg)
            }
        }

        fun showAntiUninstallOverlay() {
            Handler(Looper.getMainLooper()).post {
                instance?.showRedOverlayInternal("DayAura Settings / Uninstall", "anti_uninstall")
            }
        }
    }

    private var windowManager: WindowManager? = null
    private var floatingButtonView: View? = null
    private var popupCardView: View? = null
    private var floatingParams: WindowManager.LayoutParams? = null

    // Distraction Guard & Red Alert Overlay
    private var redOverlayView: View? = null
    private var appMonitorThread: HandlerThread? = null
    private var appMonitorHandler: Handler? = null
    private var appMonitorRunnable: Runnable? = null
    private val distractingPackages = mutableSetOf<String>()
    private var snoozedUntil = 0L
    private var currentDistractedPackage: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        loadDistractingPackages()
        return START_STICKY
    }

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        instance = this
        startForegroundServiceNotification()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        createFloatingButton()
        loadDistractingPackages()
        startAppMonitor()
    }

    private fun startForegroundServiceNotification() {
        val channelId = "routine_distraction_tracker"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Distraction Tracker",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Keeps the floating distraction button active"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setContentTitle("Distraction Tracker Active")
            .setContentText("Tap the floating button anytime you get distracted")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setOngoing(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }

        val notification = builder.build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(1001, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(1001, notification)
        }
    }

    private fun dpToPx(dp: Float): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp,
            resources.displayMetrics
        ).toInt()
    }

    private fun createFloatingButton() {
        val sizePx = dpToPx(56f)

        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        floatingParams = WindowManager.LayoutParams(
            sizePx,
            sizePx,
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dpToPx(16f)
            y = dpToPx(160f)
        }

        val prefs = getSharedPreferences("distraction_custom_chips_prefs", Context.MODE_PRIVATE)
        val savedOpacityPct = prefs.getInt("floating_button_opacity", 100).coerceIn(10, 100)

        // Circular Red Button
        val container = FrameLayout(this).apply {
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#E53935")) // Red color
                setStroke(dpToPx(2.5f), Color.WHITE)
            }
            background = bg
            elevation = dpToPx(8f).toFloat()
            alpha = savedOpacityPct / 100f

            val textView = TextView(this@FloatingTrackerService).apply {
                text = "⚡"
                textSize = 22f
                gravity = Gravity.CENTER
                setTextColor(Color.WHITE)
            }
            addView(
                textView,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
            )
        }

        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var isDragging = false

        container.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = floatingParams!!.x
                    initialY = floatingParams!!.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    isDragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val deltaX = event.rawX - initialTouchX
                    val deltaY = event.rawY - initialTouchY
                    if (abs(deltaX) > 10 || abs(deltaY) > 10) {
                        isDragging = true
                    }
                    if (isDragging) {
                        floatingParams!!.x = (initialX + deltaX).toInt()
                        floatingParams!!.y = (initialY + deltaY).toInt()
                        windowManager?.updateViewLayout(container, floatingParams)
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!isDragging) {
                        onFloatingButtonClicked()
                    }
                    true
                }
                else -> false
            }
        }

        floatingButtonView = container
        windowManager?.addView(floatingButtonView, floatingParams)
    }

    private fun onFloatingButtonClicked() {
        if (popupCardView != null) {
            closePopupCard()
            return
        }
        showPopupCard()
    }

    private fun getPinnedChips(): MutableList<String> {
        val prefs = getSharedPreferences("distraction_custom_chips_prefs", Context.MODE_PRIVATE)
        val json = prefs.getString("pinned_chips", "[]") ?: "[]"
        val list = mutableListOf<String>()
        try {
            val arr = JSONArray(json)
            for (i in 0 until arr.length()) list.add(arr.getString(i))
        } catch (_: Exception) {}
        return list
    }

    private fun savePinnedChips(list: List<String>) {
        val prefs = getSharedPreferences("distraction_custom_chips_prefs", Context.MODE_PRIVATE)
        val arr = JSONArray()
        list.forEach { arr.put(it) }
        prefs.edit().putString("pinned_chips", arr.toString()).apply()
    }

    private fun getRecentChips(): MutableList<String> {
        val prefs = getSharedPreferences("distraction_custom_chips_prefs", Context.MODE_PRIVATE)
        val json = prefs.getString("recent_chips", "[]") ?: "[]"
        val list = mutableListOf<String>()
        try {
            val arr = JSONArray(json)
            for (i in 0 until arr.length()) list.add(arr.getString(i))
        } catch (_: Exception) {}
        // Strict Google Clipboard Mutual Exclusivity: Never return chips that are currently pinned
        val pinned = getPinnedChips()
        return list.filter { r -> pinned.none { it.equals(r, ignoreCase = true) } }.toMutableList()
    }

    private fun saveRecentChips(list: List<String>) {
        val prefs = getSharedPreferences("distraction_custom_chips_prefs", Context.MODE_PRIVATE)
        val pinned = getPinnedChips()
        val arr = JSONArray()
        list.filter { r -> pinned.none { it.equals(r, ignoreCase = true) } }
            .take(20)
            .forEach { arr.put(it) }
        prefs.edit().putString("recent_chips", arr.toString()).apply()
    }

    private fun addRecentChip(name: String) {
        val clean = name.trim()
        if (clean.isEmpty()) return
        val pinned = getPinnedChips()
        // Pinned items stay exclusively in pinned, never duplicate into recent
        if (pinned.any { it.equals(clean, ignoreCase = true) }) return
        val list = getRecentChips()
        list.removeAll { it.equals(clean, ignoreCase = true) }
        list.add(0, clean)
        saveRecentChips(list)
    }

    private fun pinChip(name: String) {
        val clean = name.trim()
        if (clean.isEmpty()) return
        val pinned = getPinnedChips()
        if (pinned.none { it.equals(clean, ignoreCase = true) }) {
            pinned.add(0, clean)
            savePinnedChips(pinned)
        }
        val recent = getRecentChips()
        recent.removeAll { it.equals(clean, ignoreCase = true) }
        saveRecentChips(recent)
    }

    private fun unpinChip(name: String) {
        val clean = name.trim()
        if (clean.isEmpty()) return
        val pinned = getPinnedChips()
        pinned.removeAll { it.equals(clean, ignoreCase = true) }
        savePinnedChips(pinned)
        // Moves to top of recent like Google Clipboard
        val recent = getRecentChips()
        recent.removeAll { it.equals(clean, ignoreCase = true) }
        recent.add(0, clean)
        saveRecentChips(recent)
    }

    data class DistractionHistoryItem(
        val id: String,
        val name: String,
        val timeLabel: String,
        val timestamp: String
    )

    private fun appendDailyDistraction(id: String, name: String, timestamp: String, timeLabel: String) {
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
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun getTodayDistractionsList(): List<DistractionHistoryItem> {
        val result = mutableListOf<DistractionHistoryItem>()
        val seenIds = mutableSetOf<String>()
        val todayKey = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

        // 1. Read from daily_distractions_log.json
        try {
            val file = File(filesDir, "daily_distractions_log.json")
            if (file.exists() && file.length() > 0) {
                val root = JSONObject(file.readText())
                if (root.optString("date") == todayKey) {
                    val arr = root.optJSONArray("items")
                    if (arr != null) {
                        for (i in 0 until arr.length()) {
                            val obj = arr.getJSONObject(i)
                            val id = obj.optString("id", "")
                            if (id.isNotEmpty() && !seenIds.contains(id)) {
                                seenIds.add(id)
                                result.add(
                                    DistractionHistoryItem(
                                        id = id,
                                        name = obj.optString("name", "Distraction"),
                                        timeLabel = obj.optString("timeLabel", ""),
                                        timestamp = obj.optString("timestamp", "")
                                    )
                                )
                            }
                        }
                    }
                }
            }
        } catch (_: Exception) {}

        // 2. Read from pending_distractions.json (if any pending offline)
        try {
            val file = File(filesDir, "pending_distractions.json")
            if (file.exists() && file.length() > 0) {
                val arr = JSONArray(file.readText())
                for (i in 0 until arr.length()) {
                    val obj = arr.getJSONObject(i)
                    val id = obj.optString("id", "")
                    if (id.isNotEmpty() && !seenIds.contains(id)) {
                        seenIds.add(id)
                        result.add(
                            DistractionHistoryItem(
                                id = id,
                                name = obj.optString("name", "Distraction"),
                                timeLabel = obj.optString("timeLabel", ""),
                                timestamp = obj.optString("timestamp", "")
                            )
                        )
                    }
                }
            }
        } catch (_: Exception) {}

        // 3. Read from today_distractions.json (written by Flutter in app_flutter dir)
        val flutterDocCandidates = listOf(
            File(filesDir.parentFile, "app_flutter/today_distractions.json"),
            File(filesDir, "app_flutter/today_distractions.json")
        )
        for (f in flutterDocCandidates) {
            try {
                if (f.exists() && f.length() > 0) {
                    val root = JSONObject(f.readText())
                    if (root.optString("date") == todayKey) {
                        val arr = root.optJSONArray("items")
                        if (arr != null) {
                            for (i in 0 until arr.length()) {
                                val obj = arr.getJSONObject(i)
                                val id = obj.optString("id", "")
                                if (id.isNotEmpty() && !seenIds.contains(id)) {
                                    seenIds.add(id)
                                    result.add(
                                        DistractionHistoryItem(
                                            id = id,
                                            name = obj.optString("name", "Distraction"),
                                            timeLabel = obj.optString("timeLabel", ""),
                                            timestamp = obj.optString("timestamp", "")
                                        )
                                    )
                                }
                            }
                        }
                    }
                }
            } catch (_: Exception) {}
        }

        return result.sortedByDescending { it.timestamp.ifEmpty { it.id } }
    }

    private fun showPopupCard() {
        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val cardWidth = dpToPx(350f)
        val cardParams = WindowManager.LayoutParams(
            cardWidth,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER
        }

        val rootCard = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val bg = GradientDrawable().apply {
                setColor(Color.parseColor("#1E232A"))
                cornerRadius = dpToPx(16f).toFloat()
                setStroke(dpToPx(1.5f), Color.parseColor("#37474F"))
            }
            background = bg
            setPadding(dpToPx(16f), dpToPx(14f), dpToPx(16f), dpToPx(16f))
            elevation = dpToPx(12f).toFloat()
        }

        renderTrackView(rootCard)

        popupCardView = rootCard
        windowManager?.addView(popupCardView, cardParams)
    }

    private fun renderTrackView(rootCard: LinearLayout) {
        rootCard.removeAllViews()

        // Header Row: Title on Left, Elegant '📜' History Button on Right
        val headerRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 0, 0, dpToPx(6f))
        }

        val title = TextView(this).apply {
            text = "⚠️ Distracted? Track It!"
            textSize = 15f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER_VERTICAL
        }
        val titleLp = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        headerRow.addView(title, titleLp)

        val historyBtn = TextView(this).apply {
            text = "📜"
            textSize = 17f
            gravity = Gravity.CENTER
            val btnBg = GradientDrawable().apply {
                setColor(Color.parseColor("#263238"))
                cornerRadius = dpToPx(8f).toFloat()
                setStroke(dpToPx(1f), Color.parseColor("#455A64"))
            }
            background = btnBg
            setPadding(dpToPx(8f), dpToPx(4f), dpToPx(8f), dpToPx(4f))
            setOnClickListener {
                renderHistoryView(rootCard)
            }
        }
        val histLp = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            setMargins(dpToPx(6f), 0, 0, 0)
        }
        headerRow.addView(historyBtn, histLp)
        rootCard.addView(headerRow)

        // Visibility Slider (Horizontal line with draggable point)
        val visibilitySeekBar = SeekBar(this).apply {
            max = 100
            val cardPrefs = getSharedPreferences("distraction_custom_chips_prefs", Context.MODE_PRIVATE)
            val currentAlphaPct = cardPrefs.getInt("floating_button_opacity", 100).coerceIn(10, 100)
            progress = currentAlphaPct

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                progressDrawable?.colorFilter = android.graphics.BlendModeColorFilter(
                    Color.parseColor("#E53935"),
                    android.graphics.BlendMode.SRC_IN
                )
                thumb?.colorFilter = android.graphics.BlendModeColorFilter(
                    Color.WHITE,
                    android.graphics.BlendMode.SRC_IN
                )
            } else {
                @Suppress("DEPRECATION")
                progressDrawable?.setColorFilter(Color.parseColor("#E53935"), android.graphics.PorterDuff.Mode.SRC_IN)
                @Suppress("DEPRECATION")
                thumb?.setColorFilter(Color.WHITE, android.graphics.PorterDuff.Mode.SRC_IN)
            }

            setPadding(dpToPx(10f), dpToPx(2f), dpToPx(10f), dpToPx(10f))

            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(sb: SeekBar?, progressVal: Int, fromUser: Boolean) {
                    val safeProgress = progressVal.coerceIn(10, 100)
                    val alphaFloat = safeProgress / 100f
                    floatingButtonView?.alpha = alphaFloat
                    cardPrefs.edit().putInt("floating_button_opacity", safeProgress).apply()
                }
                override fun onStartTrackingTouch(sb: SeekBar?) {}
                override fun onStopTrackingTouch(sb: SeekBar?) {}
            })
        }
        rootCard.addView(visibilitySeekBar)

        // Custom name input row (Input + Pin button)
        val inputRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 0, 0, dpToPx(8f))
        }

        val customInput = EditText(this).apply {
            hint = "Reason + emoji (e.g. Reels 📱)..."
            setHintTextColor(Color.GRAY)
            setTextColor(Color.WHITE)
            textSize = 13f
            val inputBg = GradientDrawable().apply {
                setColor(Color.parseColor("#14181E"))
                cornerRadius = dpToPx(8f).toFloat()
                setStroke(dpToPx(1f), Color.parseColor("#37474F"))
            }
            background = inputBg
            setPadding(dpToPx(10f), dpToPx(8f), dpToPx(10f), dpToPx(8f))
        }
        inputRow.addView(customInput, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

        val pinCurrentBtn = Button(this).apply {
            text = "📌 Pin"
            textSize = 11f
            setTextColor(Color.WHITE)
            val btnBg = GradientDrawable().apply {
                setColor(Color.parseColor("#1A3A3A"))
                cornerRadius = dpToPx(8f).toFloat()
                setStroke(dpToPx(1f), Color.parseColor("#00897B"))
            }
            background = btnBg
            setOnClickListener {
                val text = customInput.text.toString().trim()
                if (text.isNotEmpty()) {
                    val pinned = getPinnedChips()
                    if (pinned.none { it.equals(text, ignoreCase = true) }) {
                        pinChip(text)
                        Toast.makeText(this@FloatingTrackerService, "📌 Pinned: $text", Toast.LENGTH_SHORT).show()
                        renderTrackView(rootCard)
                    } else {
                        Toast.makeText(this@FloatingTrackerService, "Already pinned!", Toast.LENGTH_SHORT).show()
                    }
                }
            }
        }
        val pinLp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dpToPx(38f)).apply {
            setMargins(dpToPx(6f), 0, 0, 0)
        }
        inputRow.addView(pinCurrentBtn, pinLp)
        rootCard.addView(inputRow)

        // Scrollable area for Pinned & Recent chips
        val scrollView = ScrollView(this).apply {
            isFillViewport = true
        }
        val scrollContent = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }

        val pinnedChips = getPinnedChips()
        val recentChips = getRecentChips()

        // 1. PINNED SECTION
        if (pinnedChips.isNotEmpty()) {
            val pinnedLabel = TextView(this).apply {
                text = "📌 Pinned (Tap to track • Long-press to unpin)"
                textSize = 11f
                setTextColor(Color.parseColor("#80CBC4"))
                setPadding(0, dpToPx(4f), 0, dpToPx(4f))
            }
            scrollContent.addView(pinnedLabel)

            val pinnedContainer = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
            }
            var row: LinearLayout? = null
            pinnedChips.forEachIndexed { index, chipText ->
                if (index % 2 == 0) {
                    row = LinearLayout(this).apply {
                        orientation = LinearLayout.HORIZONTAL
                        weightSum = 2f
                        setPadding(0, 0, 0, dpToPx(5f))
                    }
                    pinnedContainer.addView(row)
                }
                val btn = Button(this).apply {
                    text = "📌 $chipText"
                    textSize = 11f
                    setTextColor(Color.WHITE)
                    val btnBg = GradientDrawable().apply {
                        setColor(Color.parseColor("#1A3333"))
                        cornerRadius = dpToPx(8f).toFloat()
                        setStroke(dpToPx(1f), Color.parseColor("#26A69A"))
                    }
                    background = btnBg
                    setOnClickListener {
                        logDistraction(chipText)
                        // Pinned chips stay in pinned, no duplicate in recent
                        closePopupCard()
                    }
                    setOnLongClickListener {
                        unpinChip(chipText)
                        Toast.makeText(this@FloatingTrackerService, "Unpinned: $chipText", Toast.LENGTH_SHORT).show()
                        renderTrackView(rootCard)
                        true
                    }
                }
                val lp = LinearLayout.LayoutParams(0, dpToPx(36f), 1f).apply {
                    setMargins(dpToPx(2f), 0, dpToPx(2f), 0)
                }
                row?.addView(btn, lp)
            }
            scrollContent.addView(pinnedContainer)
        }

        // 2. RECENT SECTION
        if (recentChips.isNotEmpty()) {
            val recentLabel = TextView(this).apply {
                text = "🕒 Recent (Tap to track • Long-press to pin)"
                textSize = 11f
                setTextColor(Color.parseColor("#90A4AE"))
                setPadding(0, dpToPx(6f), 0, dpToPx(4f))
            }
            scrollContent.addView(recentLabel)

            val recentContainer = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
            }
            var row: LinearLayout? = null
            recentChips.forEachIndexed { index, chipText ->
                if (index % 2 == 0) {
                    row = LinearLayout(this).apply {
                        orientation = LinearLayout.HORIZONTAL
                        weightSum = 2f
                        setPadding(0, 0, 0, dpToPx(5f))
                    }
                    recentContainer.addView(row)
                }
                val btn = Button(this).apply {
                    text = chipText
                    textSize = 11f
                    setTextColor(Color.WHITE)
                    val btnBg = GradientDrawable().apply {
                        setColor(Color.parseColor("#252C36"))
                        cornerRadius = dpToPx(8f).toFloat()
                        setStroke(dpToPx(1f), Color.parseColor("#37474F"))
                    }
                    background = btnBg
                    setOnClickListener {
                        logDistraction(chipText)
                        addRecentChip(chipText)
                        closePopupCard()
                    }
                    setOnLongClickListener {
                        pinChip(chipText)
                        Toast.makeText(this@FloatingTrackerService, "📌 Pinned: $chipText", Toast.LENGTH_SHORT).show()
                        renderTrackView(rootCard)
                        true
                    }
                }
                val lp = LinearLayout.LayoutParams(0, dpToPx(36f), 1f).apply {
                    setMargins(dpToPx(2f), 0, dpToPx(2f), 0)
                }
                row?.addView(btn, lp)
            }
            scrollContent.addView(recentContainer)
        }

        if (pinnedChips.isEmpty() && recentChips.isEmpty()) {
            val emptyHint = TextView(this).apply {
                text = "Type any reason above and tap '📌 Pin' or 'Save'. Pinned items stay permanently on your clipboard."
                textSize = 12f
                setTextColor(Color.GRAY)
                gravity = Gravity.CENTER
                setPadding(dpToPx(8f), dpToPx(12f), dpToPx(8f), dpToPx(12f))
            }
            scrollContent.addView(emptyHint)
        }

        val scrollLp = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dpToPx(180f)
        ).apply {
            setMargins(0, dpToPx(4f), 0, dpToPx(8f))
        }
        scrollView.addView(scrollContent)
        rootCard.addView(scrollView, scrollLp)

        // Bottom actions (Cancel / Save ⚡)
        val actionsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            weightSum = 2f
        }

        val cancelBtn = Button(this).apply {
            text = "Cancel"
            textSize = 13f
            setTextColor(Color.parseColor("#B0BEC5"))
            val btnBg = GradientDrawable().apply {
                setColor(Color.TRANSPARENT)
            }
            background = btnBg
            setOnClickListener { closePopupCard() }
        }
        actionsRow.addView(
            cancelBtn,
            LinearLayout.LayoutParams(0, dpToPx(40f), 1f)
        )

        val submitBtn = Button(this).apply {
            text = "Save ⚡"
            textSize = 13f
            setTextColor(Color.WHITE)
            val btnBg = GradientDrawable().apply {
                setColor(Color.parseColor("#E53935"))
                cornerRadius = dpToPx(8f).toFloat()
            }
            background = btnBg
            setOnClickListener {
                val text = customInput.text.toString().trim()
                if (text.isNotEmpty()) {
                    logDistraction(text)
                    addRecentChip(text)
                }
                closePopupCard()
            }
        }
        actionsRow.addView(
            submitBtn,
            LinearLayout.LayoutParams(0, dpToPx(40f), 1f)
        )

        rootCard.addView(actionsRow)
    }

    private fun renderHistoryView(rootCard: LinearLayout) {
        rootCard.removeAllViews()

        val todayDistractions = getTodayDistractionsList()

        // Header Row: Back button, Title "📜 Today's Distractions", and Count Badge
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 0, 0, dpToPx(8f))
        }

        val backIcon = TextView(this).apply {
            text = "←"
            textSize = 20f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(dpToPx(2f), dpToPx(2f), dpToPx(10f), dpToPx(2f))
            setOnClickListener {
                renderTrackView(rootCard)
            }
        }
        header.addView(backIcon)

        val title = TextView(this).apply {
            text = "📜 Today's Distractions"
            textSize = 15f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
        }
        header.addView(title, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

        val countBadge = TextView(this).apply {
            text = "${todayDistractions.size} times"
            textSize = 11f
            setTextColor(Color.parseColor("#EF9A9A"))
            val badgeBg = GradientDrawable().apply {
                setColor(Color.parseColor("#3E2723"))
                cornerRadius = dpToPx(12f).toFloat()
                setStroke(dpToPx(1f), Color.parseColor("#E53935"))
            }
            background = badgeBg
            setPadding(dpToPx(8f), dpToPx(3f), dpToPx(8f), dpToPx(3f))
        }
        header.addView(countBadge)
        rootCard.addView(header)

        // Scrollable list of distractions
        val scrollView = ScrollView(this).apply {
            isFillViewport = true
        }
        val listContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }

        if (todayDistractions.isEmpty()) {
            val emptyBox = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPadding(dpToPx(16f), dpToPx(36f), dpToPx(16f), dpToPx(36f))
            }
            val emoji = TextView(this).apply {
                text = "🎉"
                textSize = 30f
                gravity = Gravity.CENTER
            }
            emptyBox.addView(emoji)

            val emptyTitle = TextView(this).apply {
                text = "No distractions logged today!"
                textSize = 13f
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
                setPadding(0, dpToPx(6f), 0, dpToPx(2f))
            }
            emptyBox.addView(emptyTitle)

            val emptySub = TextView(this).apply {
                text = "Stay focused and keep it up."
                textSize = 11f
                setTextColor(Color.GRAY)
                gravity = Gravity.CENTER
            }
            emptyBox.addView(emptySub)
            listContainer.addView(emptyBox)
        } else {
            todayDistractions.forEach { item ->
                val itemRow = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    val itemBg = GradientDrawable().apply {
                        setColor(Color.parseColor("#14181E"))
                        cornerRadius = dpToPx(8f).toFloat()
                        setStroke(dpToPx(1f), Color.parseColor("#263238"))
                    }
                    background = itemBg
                    setPadding(dpToPx(10f), dpToPx(8f), dpToPx(10f), dpToPx(8f))
                }

                val timeView = TextView(this).apply {
                    text = "🕒 ${item.timeLabel}"
                    textSize = 11f
                    setTextColor(Color.parseColor("#90A4AE"))
                    setPadding(0, 0, dpToPx(10f), 0)
                }
                itemRow.addView(timeView)

                val nameView = TextView(this).apply {
                    text = item.name
                    textSize = 13f
                    setTextColor(Color.WHITE)
                    typeface = Typeface.DEFAULT_BOLD
                }
                itemRow.addView(nameView, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

                val lp = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply {
                    setMargins(0, 0, 0, dpToPx(6f))
                }
                listContainer.addView(itemRow, lp)
            }
        }

        val scrollLp = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dpToPx(220f)
        ).apply {
            setMargins(0, dpToPx(4f), 0, dpToPx(8f))
        }
        scrollView.addView(listContainer)
        rootCard.addView(scrollView, scrollLp)

        // Bottom actions for History View
        val actionsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            weightSum = 2f
        }

        val backBtn = Button(this).apply {
            text = "← Back to Track"
            textSize = 12f
            setTextColor(Color.parseColor("#80CBC4"))
            val btnBg = GradientDrawable().apply {
                setColor(Color.parseColor("#1A3333"))
                cornerRadius = dpToPx(8f).toFloat()
                setStroke(dpToPx(1f), Color.parseColor("#00897B"))
            }
            background = btnBg
            setOnClickListener {
                renderTrackView(rootCard)
            }
        }
        actionsRow.addView(backBtn, LinearLayout.LayoutParams(0, dpToPx(38f), 1f).apply {
            setMargins(0, 0, dpToPx(4f), 0)
        })

        val closeBtn = Button(this).apply {
            text = "Close"
            textSize = 12f
            setTextColor(Color.parseColor("#B0BEC5"))
            val btnBg = GradientDrawable().apply {
                setColor(Color.parseColor("#263238"))
                cornerRadius = dpToPx(8f).toFloat()
            }
            background = btnBg
            setOnClickListener { closePopupCard() }
        }
        actionsRow.addView(closeBtn, LinearLayout.LayoutParams(0, dpToPx(38f), 1f).apply {
            setMargins(dpToPx(4f), 0, 0, 0)
        })

        rootCard.addView(actionsRow)
    }

    private fun closePopupCard() {
        if (popupCardView != null) {
            windowManager?.removeView(popupCardView)
            popupCardView = null
        }
    }

    private fun logDistraction(name: String) {
        val now = Date()
        val timeLabel = SimpleDateFormat("hh:mm a", Locale.US).format(now)
        val isoTimestamp = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).format(now)
        val id = System.currentTimeMillis().toString()

        // Haptic feedback
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vibratorManager?.defaultVibrator?.vibrate(VibrationEffect.createOneShot(50, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                vibrator?.vibrate(50)
            }
        } catch (_: Exception) {}

        Toast.makeText(this, "Logged distraction: $name ($timeLabel)", Toast.LENGTH_SHORT).show()

        // Persist to daily distraction log for overlay history
        appendDailyDistraction(id, name, isoTimestamp, timeLabel)

        // 1. Notify MainActivity via MethodChannel if running
        val sent = MainActivity.sendDistractionToFlutter(name, timeLabel, isoTimestamp, id)

        // 2. Persist to pending file only if Flutter is not active to pick it up immediately
        if (!sent) {
            saveToPendingFile(id, name, isoTimestamp, timeLabel)
        }
    }

    private fun saveToPendingFile(id: String, name: String, timestamp: String, timeLabel: String) {
        try {
            val file = File(filesDir, "pending_distractions.json")
            val array = if (file.exists() && file.length() > 0) {
                JSONArray(file.readText())
            } else {
                JSONArray()
            }
            val obj = JSONObject().apply {
                put("id", id)
                put("name", name)
                put("timestamp", timestamp)
                put("timeLabel", timeLabel)
            }
            array.put(obj)
            file.writeText(array.toString())
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun loadDistractingPackages() {
        try {
            val prefs = getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
            val json = prefs.getString("distracting_packages", "[]") ?: "[]"
            val arr = JSONArray(json)
            synchronized(distractingPackages) {
                distractingPackages.clear()
                for (i in 0 until arr.length()) {
                    distractingPackages.add(arr.getString(i))
                }
            }
        } catch (_: Exception) {}
    }

    private fun startAppMonitor() {
        val thread = HandlerThread("DistractionMonitorThread")
        thread.start()
        appMonitorThread = thread
        appMonitorHandler = Handler(thread.looper)
        appMonitorRunnable = object : Runnable {
            override fun run() {
                checkForegroundApp()
                appMonitorHandler?.postDelayed(this, 1200L)
            }
        }
        appMonitorHandler?.post(appMonitorRunnable!!)
    }

    private fun stopAppMonitor() {
        appMonitorRunnable?.let { appMonitorHandler?.removeCallbacks(it) }
        appMonitorThread?.quitSafely()
        appMonitorThread = null
        appMonitorHandler = null
        appMonitorRunnable = null
    }

    private fun checkForegroundApp() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return
        val currentPkg = getForegroundAppPackage()
        Handler(Looper.getMainLooper()).post {
            handleForegroundPackage(currentPkg)
        }
    }

    private fun getForegroundAppPackage(): String? {
        try {
            val usm = getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager ?: return null
            val time = System.currentTimeMillis()
            val usageEvents = usm.queryEvents(time - 12000, time) ?: return null
            var lastPkg: String? = null
            val event = UsageEvents.Event()
            while (usageEvents.hasNextEvent()) {
                usageEvents.getNextEvent(event)
                if (event.eventType == UsageEvents.Event.ACTIVITY_RESUMED ||
                    event.eventType == 1 /* UsageEvents.Event.MOVE_TO_FOREGROUND */) {
                    lastPkg = event.packageName
                }
            }
            if (!lastPkg.isNullOrEmpty()) {
                return lastPkg
            }

            val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, time - 10000, time)
            if (!stats.isNullOrEmpty()) {
                val mostRecent = stats.maxByOrNull { it.lastTimeUsed }
                if (mostRecent != null && (time - mostRecent.lastTimeUsed) < 5000) {
                    return mostRecent.packageName
                }
            }
        } catch (_: Exception) {}
        return null
    }

    private fun handleForegroundPackage(pkg: String?) {
        // Red alert overlays are strictly handled by DayAuraAccessibilityService
        // FloatingTrackerService is dedicated solely to the floating bubble note widget.
    }

    fun isLockedInActive(): Boolean {
        return try {
            val prefs = getSharedPreferences("locked_in_prefs", Context.MODE_PRIVATE)
            val isLocked = prefs.getBoolean("locked_in_active", false)
            val untilEpoch = prefs.getLong("locked_in_until_epoch", 0L)
            isLocked && System.currentTimeMillis() < untilEpoch
        } catch (_: Exception) {
            false
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

    fun showRedOverlayForWebsite(domain: String) {
        showRedOverlayInternal("Website: $domain", "website_$domain")
    }

    private fun showRedOverlay(pkg: String) {
        val appLabel = getAppLabel(pkg)
        showRedOverlayInternal(appLabel, pkg)
    }

    private fun showRedOverlayInternal(displayTarget: String, targetKey: String) {
        if (redOverlayView != null) {
            if (currentDistractedPackage == targetKey) return
            hideRedOverlay()
        }

        currentDistractedPackage = targetKey

        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
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
        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#E67F0000")) // 90% opacity deep red
            isClickable = true
            isFocusable = true
        }

        // Center Warning Card
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val cardBg = GradientDrawable().apply {
                setColor(Color.parseColor("#1C0606")) // Dark crimson black
                cornerRadius = dpToPx(20f).toFloat()
                setStroke(dpToPx(2.5f), Color.parseColor("#FF5252"))
            }
            background = cardBg
            setPadding(dpToPx(24f), dpToPx(24f), dpToPx(24f), dpToPx(24f))
            elevation = dpToPx(16f).toFloat()
        }

        // Warning Icon & Header
        val header = TextView(this).apply {
            text = "⚠️ WARNING!"
            textSize = 20f
            setTypeface(null, Typeface.BOLD)
            setTextColor(Color.parseColor("#FF5252"))
            gravity = Gravity.CENTER
        }
        card.addView(header)

        // "You are distracted in [AppName / Website]"
        val appWarning = TextView(this).apply {
            text = "You are distracted in $displayTarget"
            textSize = 17f
            setTypeface(null, Typeface.BOLD)
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(0, dpToPx(10f), 0, dpToPx(14f))
        }
        card.addView(appWarning)

        // The Quote
        val quoteBox = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val qBg = GradientDrawable().apply {
                setColor(Color.parseColor("#2A0B0B"))
                cornerRadius = dpToPx(10f).toFloat()
            }
            background = qBg
            setPadding(dpToPx(14f), dpToPx(12f), dpToPx(14f), dpToPx(12f))
        }
        val quoteText = TextView(this).apply {
            text = "\"Remember, life's greatest failures are rarely sudden; they are the accumulation of small failures over time\""
            textSize = 13.5f
            setTypeface(null, Typeface.ITALIC)
            setTextColor(Color.parseColor("#FFCDD2"))
            gravity = Gravity.CENTER
            setLineSpacing(dpToPx(2f).toFloat(), 1.15f)
        }
        quoteBox.addView(quoteText)
        card.addView(quoteBox)

        // Buttons Row
        val buttonsRow = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dpToPx(20f), 0, 0)
        }

        // Return to Focus Button
        val returnBtn = Button(this).apply {
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
                hideRedOverlay()
                val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(homeIntent)
            }
        }
        buttonsRow.addView(returnBtn, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dpToPx(48f)))

        // Snooze 1 Min Button (Only if NOT Locked In)
        if (!isLockedInActive()) {
            val snoozeBtn = Button(this).apply {
                text = "Snooze (1 Minute)"
                textSize = 12.5f
                setTextColor(Color.parseColor("#FF8A80"))
                val btnBg = GradientDrawable().apply {
                    setColor(Color.TRANSPARENT)
                    cornerRadius = dpToPx(12f).toFloat()
                    setStroke(dpToPx(1f), Color.parseColor("#66FF8A80"))
                }
                background = btnBg
                setOnClickListener {
                    snoozedUntil = System.currentTimeMillis() + 60_000L
                    hideRedOverlay()
                    Toast.makeText(this@FloatingTrackerService, "Warning paused for 1 min", Toast.LENGTH_SHORT).show()
                }
            }
            val snoozeParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dpToPx(40f)).apply {
                setMargins(0, dpToPx(8f), 0, 0)
            }
            buttonsRow.addView(snoozeBtn, snoozeParams)
        } else {
            val lockedNotice = TextView(this).apply {
                text = "🔒 Locked In Mode: Snooze Disabled"
                textSize = 12f
                setTextColor(Color.parseColor("#FFCDD2"))
                gravity = Gravity.CENTER
                setPadding(0, dpToPx(8f), 0, dpToPx(4f))
            }
            buttonsRow.addView(lockedNotice)

            val unlockBtn = Button(this).apply {
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
                    hideRedOverlay()
                    val intent = Intent(this@FloatingTrackerService, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                        putExtra("open_emergency_unlock", true)
                    }
                    startActivity(intent)
                }
            }
            val unlockParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dpToPx(38f)).apply {
                setMargins(0, dpToPx(6f), 0, 0)
            }
            buttonsRow.addView(unlockBtn, unlockParams)
        }

        card.addView(buttonsRow)

        val cardLayoutParams = FrameLayout.LayoutParams(
            dpToPx(320f),
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.CENTER
        }
        root.addView(card, cardLayoutParams)

        redOverlayView = root
        try {
            windowManager?.addView(redOverlayView, params)
        } catch (e: Exception) {
            e.printStackTrace()
            redOverlayView = null
            return
        }

        // Sensory alert: Vibration
        try {
            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 250, 100, 250), -1))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(250)
            }
        } catch (_: Exception) {}
    }

    private fun hideRedOverlay() {
        if (redOverlayView != null) {
            try {
                windowManager?.removeView(redOverlayView)
            } catch (_: Exception) {}
            redOverlayView = null
            currentDistractedPackage = null
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        DayAuraWatchdogReceiver.scheduleWatchdog(applicationContext, 200L)
    }

    override fun onDestroy() {
        super.onDestroy()
        DayAuraWatchdogReceiver.scheduleWatchdog(applicationContext, 500L)
        isRunning = false
        instance = null
        stopAppMonitor()
        hideRedOverlay()
        closePopupCard()
        if (floatingButtonView != null) {
            windowManager?.removeView(floatingButtonView)
            floatingButtonView = null
        }
    }
}

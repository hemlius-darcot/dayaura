package com.example.routine_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import org.json.JSONArray
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class DayAuraDnsVpnService : VpnService() {

    companion object {
        const val ACTION_START_VPN = "com.example.routine_app.START_VPN"
        const val ACTION_STOP_VPN = "com.example.routine_app.STOP_VPN"
        const val ACTION_RELOAD_VPN_SETTINGS = "com.example.routine_app.RELOAD_VPN_SETTINGS"

        const val NOTIFICATION_CHANNEL_ID = "dayaura_vpn_shield"
        const val NOTIFICATION_ID = 2002

        var isRunning = false

        // SafeSearch Official VIP IP addresses
        val GOOGLE_SAFESEARCH_IP = byteArrayOf(216.toByte(), 239.toByte(), 38.toByte(), 120.toByte()) // forcesafesearch.google.com
        val BING_SAFESEARCH_IP = byteArrayOf(204.toByte(), 79.toByte(), 197.toByte(), 220.toByte())   // strict.bing.com
        val YOUTUBE_SAFESEARCH_IP = byteArrayOf(216.toByte(), 239.toByte(), 38.toByte(), 120.toByte()) // restrict.youtube.com
        val DUCKDUCKGO_SAFESEARCH_IP = byteArrayOf(20.toByte(), 207.toByte(), 72.toByte(), 188.toByte()) // safe.duckduckgo.com

        val BLOCKED_SINKHOLE_IP = byteArrayOf(0.toByte(), 0.toByte(), 0.toByte(), 0.toByte()) // 0.0.0.0

        // Well-known public DNS & DoH / DoT IP addresses to route and intercept/RST
        val DOH_INTERCEPT_IPS = listOf(
            "8.8.8.8", "8.8.4.4",            // Google Public DNS / DoH
            "1.1.1.1", "1.0.0.1",            // Cloudflare Standard DNS / DoH
            "9.9.9.9", "149.112.112.112",    // Quad9
            "208.67.222.222", "208.67.220.220", // OpenDNS
            "94.140.14.14", "94.140.15.15"       // AdGuard
        )

        // Known DoH hostnames to sinkhole immediately so browsers cannot bootstrap DoH
        val DOH_HOSTNAMES = setOf(
            "dns.google", "dns.google.com",
            "cloudflare-dns.com", "one.one.one.one",
            "dns.quad9.net",
            "doh.opendns.com", "dns.adguard.com",
            "dns.adguard-dns.com", "dns.nextdns.io"
        )
    }

    private var vpnInterface: ParcelFileDescriptor? = null
    private var vpnThread: Thread? = null
    @Volatile private var isVpnActive = false

    private val blockedWebsites = mutableSetOf<String>()
    private var blockAdultPreset = true
    private var blockGamblingPreset = true
    private var forceSafeSearch = true

    private val dnsDnsCache = ConcurrentHashMap<String, ByteArray>()
    private var dnsWorkerPool: ExecutorService? = null

    // Unique brand substrings for adult blocking (extension-agnostic: .com, .tv, .desi, .net, etc.)
    private val ADULT_UNIQUE_BRANDS = listOf(
        "xnxx", "xvideos", "xhamster", "pornhub", "stripchat", "chaturbate",
        "onlyfans", "brazzers", "spankbang", "hentai", "eporner", "redtube",
        "youporn", "fapello", "erome", "bongacams", "camsoda", "manyvids",
        "daftsex", "rule34", "tnaflix", "tube8", "pornhat", "hqporner",
        "txxx", "upornia", "livejasmin", "beeg", "cam4"
    )

    // Token keywords in domain labels
    private val ADULT_LABEL_TOKENS = setOf(
        "porn", "porno", "xxx", "sexx", "sex", "sexy", "adult",
        "nude", "nudes", "boobs", "milf", "nsfw", "lust", "erotic"
    )

    // Unique brand substrings for gambling blocking
    private val GAMBLING_UNIQUE_BRANDS = listOf(
        "1xbet", "bet365", "melbet", "parimatch", "babu88", "jeetwin",
        "mostbet", "betway", "baji999", "linebet", "megari", "betonline",
        "bovada", "draftkings", "fanduel", "betmgm", "888casino", "1win"
    )

    // Token keywords in domain labels for gambling
    private val GAMBLING_LABEL_TOKENS = setOf(
        "casino", "gambling", "betting", "bookmaker", "slots", "roulette", "jackpot"
    )

    @Volatile private var isExplicitStop = false

    private val settingsReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            loadFilterSettings()
        }
    }

    override fun onCreate() {
        super.onCreate()
        isExplicitStop = false
        loadFilterSettings()
        try {
            val filter = IntentFilter(ACTION_RELOAD_VPN_SETTINGS)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(settingsReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(settingsReceiver, filter)
            }
        } catch (_: Exception) {}
    }

    private fun loadFilterSettings() {
        try {
            val prefs = getSharedPreferences("distraction_apps_prefs", Context.MODE_PRIVATE)
            val json = prefs.getString("blocked_websites", "[]") ?: "[]"
            val arr = JSONArray(json)
            synchronized(blockedWebsites) {
                blockedWebsites.clear()
                for (i in 0 until arr.length()) {
                    val s = arr.getString(i).trim().lowercase(Locale.ROOT)
                    if (s.isNotEmpty()) blockedWebsites.add(s)
                }
            }
            blockAdultPreset = prefs.getBoolean("block_adult_preset", true)
            blockGamblingPreset = prefs.getBoolean("block_gambling_preset", true)
            forceSafeSearch = prefs.getBoolean("force_safesearch", true)
            dnsDnsCache.clear()
        } catch (_: Exception) {}
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_STOP_VPN) {
            isExplicitStop = true
            stopVpnShield()
            stopSelf()
            return START_NOT_STICKY
        }

        // Hardcore Guard: Never allow VPN to run during Time Lock (Kernel Private DNS & Chrome policies handle security)
        val lockedPrefs = getSharedPreferences("locked_in_prefs", Context.MODE_PRIVATE)
        val mode = lockedPrefs.getString("locked_in_mode", "") ?: ""
        val until = lockedPrefs.getLong("time_lock_until_epoch", lockedPrefs.getLong("locked_in_until_epoch", 0L))
        val isTimeLock = mode == "time_lock" && System.currentTimeMillis() < until
        if (isTimeLock) {
            isExplicitStop = true
            stopVpnShield()
            stopSelf()
            return START_NOT_STICKY
        }

        isExplicitStop = false
        startVpnNotification()
        loadFilterSettings()
        startVpnEngine()
        return START_STICKY
    }

    private fun startVpnNotification() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "DayAura Web Shield",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Keeps SafeSearch and browser blocklist enforced"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }

        val openAppIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setContentTitle("DayAura Web Shield Active 🛡️")
            .setContentText("SafeSearch Enforced • Distracting Sites Blocked")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }

        val notification = builder.build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    @Synchronized
    private fun startVpnEngine() {
        if (isVpnActive) return
        try {
            val builder = Builder()
                .setSession("DayAura Web Shield")
                .addAddress("10.0.0.2", 32)
                .addDnsServer("10.0.0.2")
                .addRoute("10.0.0.2", 32)
                .setMtu(1500)
                .setBlocking(true)

            // Route all well-known public DNS & DoH / DoT IPs into TUN interface
            for (ip in DOH_INTERCEPT_IPS) {
                try {
                    builder.addRoute(ip, 32)
                } catch (_: Exception) {}
            }

            // Optional IPv6 interface & DoH interception
            try {
                builder.addAddress("fd00::2", 128)
                builder.addDnsServer("fd00::2")
                builder.addRoute("fd00::2", 128)
                builder.addRoute("2001:4860:4860::8888", 128)
                builder.addRoute("2001:4860:4860::8844", 128)
                builder.addRoute("2606:4700:4700::1111", 128)
                builder.addRoute("2606:4700:4700::1001", 128)
            } catch (_: Throwable) {}

            vpnInterface = builder.establish()
            if (vpnInterface == null) {
                return
            }

            isVpnActive = true
            isRunning = true
            try {
                val file = File(filesDir, "vpn_running")
                file.writeText("1")
            } catch (_: Exception) {}
            dnsWorkerPool = Executors.newFixedThreadPool(4)

            vpnThread = Thread({ runVpnLoop() }, "DayAura-VpnLoop").apply {
                priority = Thread.MAX_PRIORITY
                start()
            }
        } catch (e: Exception) {
            e.printStackTrace()
            isVpnActive = false
            isRunning = false
        }
    }

    private fun runVpnLoop() {
        val pfd = vpnInterface ?: return
        val inputStream = FileInputStream(pfd.fileDescriptor)
        val outputStream = FileOutputStream(pfd.fileDescriptor)
        val packet = ByteArray(1500)

        while (isVpnActive) {
            try {
                val length = inputStream.read(packet)
                if (length <= 0) continue

                val version = (packet[0].toInt() and 0xF0) shr 4
                if (version != 4) continue // IPv4 handling

                val ihl = (packet[0].toInt() and 0x0F) * 4
                val protocol = packet[9].toInt() and 0xFF

                // CASE A: UDP PACKETS (Protocol 17)
                if (protocol == 17) {
                    val clientPort = ((packet[ihl].toInt() and 0xFF) shl 8) or (packet[ihl + 1].toInt() and 0xFF)
                    val destPort = ((packet[ihl + 2].toInt() and 0xFF) shl 8) or (packet[ihl + 3].toInt() and 0xFF)

                    // Standard DNS query (Port 53)
                    if (destPort == 53) {
                        val clientIp = ByteArray(4)
                        System.arraycopy(packet, 12, clientIp, 0, 4)
                        val serverIp = ByteArray(4)
                        System.arraycopy(packet, 16, serverIp, 0, 4)

                        val dnsOffset = ihl + 8
                        val dnsLength = length - dnsOffset
                        if (dnsLength >= 12) {
                            val dnsData = ByteArray(dnsLength)
                            System.arraycopy(packet, dnsOffset, dnsData, 0, dnsLength)

                            dnsWorkerPool?.execute {
                                handleDnsPacket(clientIp, serverIp, clientPort, destPort, dnsData, outputStream)
                            }
                        }
                    }
                    // For UDP Port 443 (QUIC / DoQ) or 853 (DoT), silently drop to force TCP / standard DNS fallback
                    continue
                }

                // CASE B: TCP PACKETS (Protocol 6) - Intercept DoH / DoT on routed IPs
                if (protocol == 6) {
                    val clientPort = ((packet[ihl].toInt() and 0xFF) shl 8) or (packet[ihl + 1].toInt() and 0xFF)
                    val destPort = ((packet[ihl + 2].toInt() and 0xFF) shl 8) or (packet[ihl + 3].toInt() and 0xFF)

                    // Intercept HTTPS DoH (port 443) on routed IPs only
                    if (destPort == 443) {
                        val clientIp = ByteArray(4)
                        System.arraycopy(packet, 12, clientIp, 0, 4)
                        val serverIp = ByteArray(4)
                        System.arraycopy(packet, 16, serverIp, 0, 4)

                        val seq0 = packet[ihl + 4].toLong() and 0xFF
                        val seq1 = packet[ihl + 5].toLong() and 0xFF
                        val seq2 = packet[ihl + 6].toLong() and 0xFF
                        val seq3 = packet[ihl + 7].toLong() and 0xFF
                        val clientSeq = (seq0 shl 24) or (seq1 shl 16) or (seq2 shl 8) or seq3

                        val ack0 = packet[ihl + 8].toLong() and 0xFF
                        val ack1 = packet[ihl + 9].toLong() and 0xFF
                        val ack2 = packet[ihl + 10].toLong() and 0xFF
                        val ack3 = packet[ihl + 11].toLong() and 0xFF
                        val clientAck = (ack0 shl 24) or (ack1 shl 16) or (ack2 shl 8) or ack3

                        val tcpFlags = packet[ihl + 13].toInt() and 0xFF
                        val hasSyn = (tcpFlags and 0x02) != 0

                        // Send instant TCP RST back to Chrome / browser
                        val rstPacket = buildTcpRstPacket(
                            srcIp = serverIp,
                            dstIp = clientIp,
                            srcPort = destPort,
                            dstPort = clientPort,
                            clientSeq = clientSeq,
                            clientAck = clientAck,
                            hasSyn = hasSyn
                        )
                        synchronized(outputStream) {
                            outputStream.write(rstPacket)
                        }
                    }
                }
            } catch (_: InterruptedException) {
                break
            } catch (e: Exception) {
                if (!isVpnActive) break
            }
        }
    }

    private fun handleDnsPacket(
        clientIp: ByteArray,
        serverIp: ByteArray,
        clientPort: Int,
        serverPort: Int,
        dnsData: ByteArray,
        outputStream: FileOutputStream
    ) {
        try {
            val domain = extractDomainFromDns(dnsData) ?: return

            // 1. Check if domain is a DoH probe hostname (e.g. dns.google, cloudflare-dns.com)
            // Sinkhole immediately to force browser back to UDP 53
            if (isDohDomain(domain)) {
                val dnsResp = buildDnsResponse(dnsData, BLOCKED_SINKHOLE_IP)
                val ipUdpPacket = buildIpUdpPacket(clientIp, serverIp, clientPort, serverPort, dnsResp)
                synchronized(outputStream) {
                    outputStream.write(ipUdpPacket)
                }
                return
            }

            // 2. Check if domain should be BLOCKED (Custom websites, Adult Preset, Gambling Preset)
            val isBlocked = shouldBlockDomain(domain)
            if (isBlocked) {
                val dnsResp = buildDnsResponse(dnsData, BLOCKED_SINKHOLE_IP)
                val ipUdpPacket = buildIpUdpPacket(clientIp, serverIp, clientPort, serverPort, dnsResp)
                synchronized(outputStream) {
                    outputStream.write(ipUdpPacket)
                }
                return
            }

            // 3. Check for SafeSearch enforcement (Google, Bing, YouTube, DuckDuckGo)
            if (forceSafeSearch) {
                val safeIp = getSafeSearchIp(domain)
                if (safeIp != null) {
                    val dnsResp = buildDnsResponse(dnsData, safeIp)
                    val ipUdpPacket = buildIpUdpPacket(clientIp, serverIp, clientPort, serverPort, dnsResp)
                    synchronized(outputStream) {
                        outputStream.write(ipUdpPacket)
                    }
                    return
                }
            }

            // 4. For legitimate domains: check local cache
            val cached = dnsDnsCache[domain]
            if (cached != null) {
                cached[0] = dnsData[0]
                cached[1] = dnsData[1]
                val ipUdpPacket = buildIpUdpPacket(clientIp, serverIp, clientPort, serverPort, cached)
                synchronized(outputStream) {
                    outputStream.write(ipUdpPacket)
                }
                return
            }

            // 5. Forward query to Cloudflare Family (1.1.1.3) / CleanBrowsing (185.228.168.168)
            // These cloud resolvers automatically sinkhole dynamic adult mirrors (e.g. ster46.desi) & malware
            val upstreamResp = forwardDnsQuery(dnsData)
            if (upstreamResp != null) {
                if (dnsDnsCache.size < 500) {
                    dnsDnsCache[domain] = upstreamResp.clone()
                }
                val ipUdpPacket = buildIpUdpPacket(clientIp, serverIp, clientPort, serverPort, upstreamResp)
                synchronized(outputStream) {
                    outputStream.write(ipUdpPacket)
                }
            }
        } catch (_: Exception) {}
    }

    private fun isDohDomain(domain: String): Boolean {
        val lower = domain.lowercase(Locale.ROOT)
        if (DOH_HOSTNAMES.contains(lower)) return true
        for (h in DOH_HOSTNAMES) {
            if (lower.endsWith(".$h")) return true
        }
        return false
    }

    private fun shouldBlockDomain(domain: String): Boolean {
        val lower = domain.lowercase(Locale.ROOT)

        // Custom blocked websites from user settings
        synchronized(blockedWebsites) {
            for (site in blockedWebsites) {
                val clean = site.replace("http://", "").replace("https://", "").replace("www.", "").trim()
                if (clean.contains("/")) continue // URL path rules (e.g. youtube.com/shorts) are enforced at browser level by Accessibility Service
                if (clean.isNotEmpty() && (lower == clean || lower.endsWith(".$clean") || lower.contains(clean))) {
                    return true
                }
            }
        }

        // Adult protection shield
        if (blockAdultPreset) {
            // Check unique adult brands
            for (brand in ADULT_UNIQUE_BRANDS) {
                if (lower.contains(brand)) return true
            }
            // Check domain label tokens
            val tokens = lower.split('.', '-', '_')
            for (t in tokens) {
                if (ADULT_LABEL_TOKENS.contains(t)) return true
            }
        }

        // Gambling protection shield
        if (blockGamblingPreset) {
            for (g in GAMBLING_UNIQUE_BRANDS) {
                if (lower.contains(g)) return true
            }
            val tokens = lower.split('.', '-', '_')
            for (t in tokens) {
                if (GAMBLING_LABEL_TOKENS.contains(t)) return true
            }
        }

        return false
    }

    private fun getSafeSearchIp(domain: String): ByteArray? {
        val lower = domain.lowercase(Locale.ROOT)

        // Google SafeSearch: forcesafesearch.google.com (216.239.38.120)
        if (lower == "google.com" || lower == "www.google.com" ||
            lower.endsWith(".google.com") || lower.contains("google.co.") || lower.contains("google.com.")) {
            return GOOGLE_SAFESEARCH_IP
        }

        // Bing Strict SafeSearch: strict.bing.com (204.79.197.220)
        if (lower == "bing.com" || lower == "www.bing.com" || lower.endsWith(".bing.com")) {
            return BING_SAFESEARCH_IP
        }

        // YouTube Restricted Mode: restrict.youtube.com (216.239.38.120)
        if (lower == "youtube.com" || lower == "www.youtube.com" || lower == "m.youtube.com" ||
            lower == "youtu.be" || lower.endsWith(".youtube.com") || lower == "youtubei.googleapis.com") {
            return YOUTUBE_SAFESEARCH_IP
        }

        // DuckDuckGo Safe VIP: safe.duckduckgo.com (20.207.72.188)
        if (lower == "duckduckgo.com" || lower == "www.duckduckgo.com" || lower.endsWith(".duckduckgo.com")) {
            return DUCKDUCKGO_SAFESEARCH_IP
        }

        return null
    }

    private fun forwardDnsQuery(dnsQuery: ByteArray): ByteArray? {
        // 1. Primary: Cloudflare Family (1.1.1.3:53) - Cloud adult & malware blocker
        var resp = sendDnsQueryTo("1.1.1.3", dnsQuery)
        if (resp != null) return resp

        // 2. Secondary: CleanBrowsing Family (185.228.168.168:53) - Cloud adult sinkhole
        resp = sendDnsQueryTo("185.228.168.168", dnsQuery)
        if (resp != null) return resp

        // 3. Fallback: OpenDNS FamilyShield (208.67.222.123:53)
        resp = sendDnsQueryTo("208.67.222.123", dnsQuery)
        return resp
    }

    private fun sendDnsQueryTo(upstreamIp: String, dnsQuery: ByteArray): ByteArray? {
        var socket: DatagramSocket? = null
        try {
            socket = DatagramSocket()
            protect(socket) // Critical: Ensure upstream packet bypasses VPN TUN interface
            socket.soTimeout = 1800

            val upstream = InetAddress.getByName(upstreamIp)
            val sendPacket = DatagramPacket(dnsQuery, dnsQuery.size, upstream, 53)
            socket.send(sendPacket)

            val buffer = ByteArray(1500)
            val recvPacket = DatagramPacket(buffer, buffer.size)
            socket.receive(recvPacket)

            val response = ByteArray(recvPacket.length)
            System.arraycopy(recvPacket.data, 0, response, 0, recvPacket.length)
            return response
        } catch (_: Exception) {
            return null
        } finally {
            try { socket?.close() } catch (_: Exception) {}
        }
    }

    private fun extractDomainFromDns(dnsData: ByteArray): String? {
        if (dnsData.size < 12) return null
        var ptr = 12
        val sb = StringBuilder()
        while (ptr < dnsData.size) {
            val len = dnsData[ptr].toInt() and 0xFF
            ptr++
            if (len == 0) break
            if (len > 63 || ptr + len > dnsData.size) return null
            if (sb.isNotEmpty()) sb.append('.')
            sb.append(String(dnsData, ptr, len, Charsets.US_ASCII))
            ptr += len
        }
        return sb.toString().lowercase(Locale.ROOT)
    }

    private fun buildDnsResponse(queryPacket: ByteArray, resolvedIp: ByteArray): ByteArray {
        val txId0 = queryPacket[0]
        val txId1 = queryPacket[1]

        var qEnd = 12
        while (qEnd < queryPacket.size && queryPacket[qEnd] != 0.toByte()) {
            val len = queryPacket[qEnd].toInt() and 0xFF
            qEnd += (len + 1)
        }
        qEnd += 1 // zero byte
        qEnd += 4 // QTYPE (2) + QCLASS (2)
        if (qEnd > queryPacket.size) qEnd = queryPacket.size

        val qSectionLen = qEnd - 12
        val responseLen = 12 + qSectionLen + 16
        val out = ByteArray(responseLen)

        out[0] = txId0
        out[1] = txId1
        out[2] = 0x81.toByte() // Standard response
        out[3] = 0x80.toByte() // No error
        out[4] = 0x00; out[5] = 0x01 // Questions = 1
        out[6] = 0x00; out[7] = 0x01 // Answer RRs = 1
        out[8] = 0x00; out[9] = 0x00
        out[10] = 0x00; out[11] = 0x00

        System.arraycopy(queryPacket, 12, out, 12, qSectionLen)

        var aPtr = 12 + qSectionLen
        out[aPtr++] = 0xc0.toByte(); out[aPtr++] = 0x0c.toByte() // Name pointer to QNAME (offset 12)
        out[aPtr++] = 0x00; out[aPtr++] = 0x01 // Type A
        out[aPtr++] = 0x00; out[aPtr++] = 0x01 // Class IN
        out[aPtr++] = 0x00; out[aPtr++] = 0x00; out[aPtr++] = 0x00; out[aPtr++] = 0x3c // TTL 60s
        out[aPtr++] = 0x00; out[aPtr++] = 0x04 // RDLength 4
        out[aPtr++] = resolvedIp[0]
        out[aPtr++] = resolvedIp[1]
        out[aPtr++] = resolvedIp[2]
        out[aPtr] = resolvedIp[3]

        return out
    }

    private fun buildIpUdpPacket(
        clientIp: ByteArray,
        serverIp: ByteArray,
        clientPort: Int,
        serverPort: Int,
        udpPayload: ByteArray
    ): ByteArray {
        val ipHeaderLen = 20
        val udpHeaderLen = 8
        val totalLen = ipHeaderLen + udpHeaderLen + udpPayload.size
        val packet = ByteArray(totalLen)

        // IP Header
        packet[0] = 0x45.toByte() // IPv4, IHL=5
        packet[1] = 0x00
        packet[2] = ((totalLen shr 8) and 0xFF).toByte()
        packet[3] = (totalLen and 0xFF).toByte()
        packet[4] = 0x00; packet[5] = 0x00
        packet[6] = 0x40.toByte(); packet[7] = 0x00 // DF
        packet[8] = 64.toByte() // TTL
        packet[9] = 17.toByte() // UDP
        packet[10] = 0x00; packet[11] = 0x00

        // Swap IPs: server is source, client is destination
        packet[12] = serverIp[0]; packet[13] = serverIp[1]
        packet[14] = serverIp[2]; packet[15] = serverIp[3]
        packet[16] = clientIp[0]; packet[17] = clientIp[1]
        packet[18] = clientIp[2]; packet[19] = clientIp[3]

        val ipChecksum = computeInternetChecksum(packet, 0, ipHeaderLen)
        packet[10] = ((ipChecksum shr 8) and 0xFF).toByte()
        packet[11] = (ipChecksum and 0xFF).toByte()

        // UDP Header
        val udpOffset = ipHeaderLen
        packet[udpOffset] = ((serverPort shr 8) and 0xFF).toByte()
        packet[udpOffset + 1] = (serverPort and 0xFF).toByte()
        packet[udpOffset + 2] = ((clientPort shr 8) and 0xFF).toByte()
        packet[udpOffset + 3] = (clientPort and 0xFF).toByte()
        val udpLen = udpHeaderLen + udpPayload.size
        packet[udpOffset + 4] = ((udpLen shr 8) and 0xFF).toByte()
        packet[udpOffset + 5] = (udpLen and 0xFF).toByte()
        packet[udpOffset + 6] = 0x00; packet[udpOffset + 7] = 0x00 // Checksum optional in IPv4 UDP

        System.arraycopy(udpPayload, 0, packet, ipHeaderLen + udpHeaderLen, udpPayload.size)
        return packet
    }

    private fun buildTcpRstPacket(
        srcIp: ByteArray,
        dstIp: ByteArray,
        srcPort: Int,
        dstPort: Int,
        clientSeq: Long,
        clientAck: Long,
        hasSyn: Boolean
    ): ByteArray {
        val ipHeaderLen = 20
        val tcpHeaderLen = 20
        val totalLen = ipHeaderLen + tcpHeaderLen
        val packet = ByteArray(totalLen)

        // IPv4 Header
        packet[0] = 0x45.toByte()
        packet[1] = 0x00
        packet[2] = ((totalLen shr 8) and 0xFF).toByte()
        packet[3] = (totalLen and 0xFF).toByte()
        packet[4] = 0x00; packet[5] = 0x00
        packet[6] = 0x40.toByte(); packet[7] = 0x00 // DF flag
        packet[8] = 64.toByte() // TTL
        packet[9] = 6.toByte()  // Protocol 6 = TCP
        packet[10] = 0x00; packet[11] = 0x00

        packet[12] = srcIp[0]; packet[13] = srcIp[1]
        packet[14] = srcIp[2]; packet[15] = srcIp[3]
        packet[16] = dstIp[0]; packet[17] = dstIp[1]
        packet[18] = dstIp[2]; packet[19] = dstIp[3]

        val ipChecksum = computeInternetChecksum(packet, 0, ipHeaderLen)
        packet[10] = ((ipChecksum shr 8) and 0xFF).toByte()
        packet[11] = (ipChecksum and 0xFF).toByte()

        // TCP Header
        val tcpOffset = ipHeaderLen
        packet[tcpOffset] = ((srcPort shr 8) and 0xFF).toByte()
        packet[tcpOffset + 1] = (srcPort and 0xFF).toByte()
        packet[tcpOffset + 2] = ((dstPort shr 8) and 0xFF).toByte()
        packet[tcpOffset + 3] = (dstPort and 0xFF).toByte()

        val outSeq = if (hasSyn) 0L else clientAck
        val outAck = if (hasSyn) (clientSeq + 1L) and 0xFFFFFFFFL else 0L
        val flags = if (hasSyn) 0x14 else 0x04 // RST|ACK or RST

        packet[tcpOffset + 4] = ((outSeq shr 24) and 0xFF).toByte()
        packet[tcpOffset + 5] = ((outSeq shr 16) and 0xFF).toByte()
        packet[tcpOffset + 6] = ((outSeq shr 8) and 0xFF).toByte()
        packet[tcpOffset + 7] = (outSeq and 0xFF).toByte()

        packet[tcpOffset + 8] = ((outAck shr 24) and 0xFF).toByte()
        packet[tcpOffset + 9] = ((outAck shr 16) and 0xFF).toByte()
        packet[tcpOffset + 10] = ((outAck shr 8) and 0xFF).toByte()
        packet[tcpOffset + 11] = (outAck and 0xFF).toByte()

        packet[tcpOffset + 12] = 0x50.toByte() // 20 bytes
        packet[tcpOffset + 13] = flags.toByte()
        packet[tcpOffset + 14] = 0x00; packet[tcpOffset + 15] = 0x00
        packet[tcpOffset + 16] = 0x00; packet[tcpOffset + 17] = 0x00
        packet[tcpOffset + 18] = 0x00; packet[tcpOffset + 19] = 0x00

        // TCP pseudo-header checksum
        val pseudoHeader = ByteArray(12 + tcpHeaderLen)
        System.arraycopy(srcIp, 0, pseudoHeader, 0, 4)
        System.arraycopy(dstIp, 0, pseudoHeader, 4, 4)
        pseudoHeader[8] = 0x00
        pseudoHeader[9] = 6.toByte()
        pseudoHeader[10] = ((tcpHeaderLen shr 8) and 0xFF).toByte()
        pseudoHeader[11] = (tcpHeaderLen and 0xFF).toByte()
        System.arraycopy(packet, tcpOffset, pseudoHeader, 12, tcpHeaderLen)

        val tcpChecksum = computeInternetChecksum(pseudoHeader, 0, pseudoHeader.size)
        packet[tcpOffset + 16] = ((tcpChecksum shr 8) and 0xFF).toByte()
        packet[tcpOffset + 17] = (tcpChecksum and 0xFF).toByte()

        return packet
    }

    private fun computeInternetChecksum(data: ByteArray, offset: Int, length: Int): Int {
        var sum = 0
        var i = offset
        val end = offset + length
        while (i < end - 1) {
            val word = ((data[i].toInt() and 0xFF) shl 8) or (data[i + 1].toInt() and 0xFF)
            sum += word
            i += 2
        }
        if (i < end) {
            sum += (data[i].toInt() and 0xFF) shl 8
        }
        while (sum shr 16 > 0) {
            sum = (sum and 0xFFFF) + (sum shr 16)
        }
        return sum.inv() and 0xFFFF
    }

    @Synchronized
    private fun stopVpnShield() {
        isVpnActive = false
        isRunning = false
        try {
            val file = File(filesDir, "vpn_running")
            if (file.exists()) file.delete()
        } catch (_: Exception) {}
        try { vpnThread?.interrupt() } catch (_: Exception) {}
        vpnThread = null
        try { dnsWorkerPool?.shutdownNow() } catch (_: Exception) {}
        dnsWorkerPool = null
        try { vpnInterface?.close() } catch (_: Exception) {}
        vpnInterface = null
        stopForeground(true)
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        if (isVpnActive && isRunning) {
            startVpnNotification()
            DayAuraWatchdogReceiver.scheduleWatchdog(applicationContext, 100L)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try { unregisterReceiver(settingsReceiver) } catch (_: Exception) {}
        if (!isExplicitStop) {
            // Unexpected kill (by cleaner or system) - immediately schedule watchdog and broadcast revival!
            DayAuraWatchdogReceiver.scheduleWatchdog(applicationContext, 100L)
            try {
                val restartIntent = Intent(applicationContext, DayAuraWatchdogReceiver::class.java).apply {
                    action = DayAuraWatchdogReceiver.ACTION_RESTART_GUARD
                }
                applicationContext.sendBroadcast(restartIntent)
            } catch (_: Exception) {}
        }
        stopVpnShield()
    }
}

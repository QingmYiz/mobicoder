package com.mobicoder.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import io.flutter.plugin.common.EventChannel
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.net.InetSocketAddress
import java.net.Socket

class AgentService : Service() {
    companion object {
        const val CHANNEL_ID = "mobicoder_agent"
        const val NOTIFICATION_ID = 1
        private const val AGENT_PORT = 18790
        private const val AGENT_START_COMMAND = "mobicoder-agent"
        var isRunning = false
            private set
        var logSink: EventChannel.EventSink? = null
        private var instance: AgentService? = null
        private val mainHandler = Handler(Looper.getMainLooper())

        fun isProcessAlive(): Boolean {
            val inst = instance ?: return false
            if (!isRunning) return false
            val proc = inst.agentProcess
            if (proc != null) return proc.isAlive
            val thread = inst.agentThread
            if (thread != null && thread.isAlive) return true
            val elapsed = System.currentTimeMillis() - inst.startTime
            return elapsed < 120_000
        }

        fun start(context: Context) {
            val intent = Intent(context, AgentService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, AgentService::class.java)
            context.stopService(intent)
        }
    }

    private var agentProcess: Process? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var restartCount = 0
    private val maxRestarts = 5
    private var startTime: Long = 0
    private var processStartTime: Long = 0
    private var uptimeThread: Thread? = null
    private var watchdogThread: Thread? = null
    private var agentThread: Thread? = null
    private val lock = Object()
    @Volatile private var stopping = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification("Starting..."))
        if (isRunning) {
            updateNotificationRunning()
            return START_STICKY
        }
        stopping = false
        acquireWakeLock()
        startAgent()
        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        instance = null
        uptimeThread?.interrupt()
        uptimeThread = null
        watchdogThread?.interrupt()
        watchdogThread = null
        stopAgent()
        releaseWakeLock()
        super.onDestroy()
    }

    private fun isPortInUse(port: Int = AGENT_PORT): Boolean {
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress("127.0.0.1", port), 1000)
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun startAgent() {
        synchronized(lock) {
            if (stopping) return
            if (agentProcess?.isAlive == true) return

            isRunning = true
            instance = this
            startTime = System.currentTimeMillis()
        }

        agentThread = Thread {
            try {
                if (isPortInUse()) {
                    emitLog("[INFO] Agent already running on port $AGENT_PORT, adopting existing instance")
                    updateNotificationRunning()
                    startUptimeTicker()
                    startWatchdog()
                    return@Thread
                }

                emitLog("[INFO] Setting up environment...")
                val filesDir = applicationContext.filesDir.absolutePath
                val nativeLibDir = applicationContext.applicationInfo.nativeLibraryDir
                val pm = ProcessManager(filesDir, nativeLibDir)

                val bootstrapManager = BootstrapManager(applicationContext, filesDir, nativeLibDir)
                try {
                    bootstrapManager.setupDirectories()
                    emitLog("[INFO] Directories ready")
                } catch (e: Exception) {
                    emitLog("[WARN] setupDirectories failed: ${e.message}")
                }
                try {
                    bootstrapManager.writeResolvConf()
                } catch (e: Exception) {
                    emitLog("[WARN] writeResolvConf failed: ${e.message}")
                }

                val resolvContent = "nameserver 8.8.8.8\nnameserver 8.8.4.4\n"
                try {
                    val resolvFile = File(filesDir, "config/resolv.conf")
                    if (!resolvFile.exists() || resolvFile.length() == 0L) {
                        resolvFile.parentFile?.mkdirs()
                        resolvFile.writeText(resolvContent)
                        emitLog("[INFO] resolv.conf created (inline fallback)")
                    }
                } catch (e: Exception) {
                    emitLog("[WARN] inline resolv.conf fallback failed: ${e.message}")
                }
                try {
                    val rootfsResolv = File(filesDir, "rootfs/ubuntu/etc/resolv.conf")
                    if (!rootfsResolv.exists() || rootfsResolv.length() == 0L) {
                        rootfsResolv.parentFile?.mkdirs()
                        rootfsResolv.writeText(resolvContent)
                    }
                } catch (_: Exception) {}

                if (stopping) return@Thread

                if (isPortInUse()) {
                    emitLog("[INFO] Agent already running on port $AGENT_PORT, skipping launch")
                    updateNotificationRunning()
                    startUptimeTicker()
                    startWatchdog()
                    return@Thread
                }

                emitLog("[INFO] Spawning proot process...")
                synchronized(lock) {
                    if (stopping) return@Thread
                    processStartTime = System.currentTimeMillis()
                    agentProcess = pm.startProotProcess(AGENT_START_COMMAND)
                }
                updateNotificationRunning()
                emitLog("[INFO] Agent process spawned")
                startUptimeTicker()
                startWatchdog()

                val proc = agentProcess!!
                val stdoutReader = BufferedReader(InputStreamReader(proc.inputStream))
                Thread {
                    try {
                        var line: String?
                        while (stdoutReader.readLine().also { line = it } != null) {
                            val l = line ?: continue
                            emitLog(l)
                        }
                    } catch (_: Exception) {}
                }.start()

                val stderrReader = BufferedReader(InputStreamReader(proc.errorStream))
                val currentRestartCount = restartCount
                Thread {
                    try {
                        var line: String?
                        while (stderrReader.readLine().also { line = it } != null) {
                            val l = line ?: continue
                            if (currentRestartCount == 0 ||
                                (!l.contains("proot warning") && !l.contains("can't sanitize"))) {
                                emitLog("[ERR] $l")
                            }
                        }
                    } catch (_: Exception) {}
                }.start()

                val exitCode = proc.waitFor()
                val uptimeMs = System.currentTimeMillis() - processStartTime
                val uptimeSec = uptimeMs / 1000
                emitLog("[INFO] Agent exited with code $exitCode (uptime: ${uptimeSec}s)")

                if (stopping) return@Thread

                if (uptimeMs > 60_000) {
                    restartCount = 0
                }

                if (isRunning && restartCount < maxRestarts) {
                    restartCount++
                    val delayMs = minOf(2000L * (1 shl (restartCount - 1)), 16000L)
                    emitLog("[INFO] Auto-restarting in ${delayMs / 1000}s (attempt $restartCount/$maxRestarts)...")
                    updateNotification("Restarting in ${delayMs / 1000}s (attempt $restartCount)...")
                    Thread.sleep(delayMs)
                    if (!stopping) {
                        startTime = System.currentTimeMillis()
                        startAgent()
                    }
                } else if (restartCount >= maxRestarts) {
                    emitLog("[WARN] Max restarts reached. Agent stopped.")
                    updateNotification("Agent stopped (crashed)")
                    isRunning = false
                }
            } catch (e: Exception) {
                if (!stopping) {
                    emitLog("[ERROR] Agent error: ${e.message}")
                    isRunning = false
                    updateNotification("Agent error")
                }
            }
        }.also { it.start() }
    }

    private fun stopAgent() {
        val procToStop: Process?
        synchronized(lock) {
            stopping = true
            restartCount = maxRestarts
            uptimeThread?.interrupt()
            uptimeThread = null
            watchdogThread?.interrupt()
            watchdogThread = null
            agentThread?.interrupt()
            agentThread = null
            procToStop = agentProcess
            agentProcess = null
        }
        emitLog("Agent stopped by user")
        procToStop?.let { proc ->
            Thread({
                try {
                    proc.destroy()
                    if (!proc.waitFor(3, java.util.concurrent.TimeUnit.SECONDS)) {
                        proc.destroyForcibly()
                    }
                } catch (_: Exception) {
                    try { proc.destroyForcibly() } catch (_: Exception) {}
                }
            }, "agent-stop").apply { isDaemon = true }.start()
        }
    }

    private fun startWatchdog() {
        watchdogThread?.interrupt()
        watchdogThread = Thread {
            try {
                Thread.sleep(45_000)
                while (!Thread.interrupted() && isRunning && !stopping) {
                    val proc = agentProcess
                    if (proc != null && !proc.isAlive) {
                        emitLog("[WARN] Watchdog: agent process not alive")
                        break
                    }
                    if (proc != null && !isPortInUse()) {
                        emitLog("[WARN] Watchdog: port $AGENT_PORT not responding")
                    }
                    Thread.sleep(15_000)
                }
            } catch (_: InterruptedException) {}
        }.apply { isDaemon = true; start() }
    }

    private fun startUptimeTicker() {
        uptimeThread?.interrupt()
        uptimeThread = Thread {
            try {
                while (!Thread.interrupted() && isRunning) {
                    Thread.sleep(60_000)
                    if (isRunning) {
                        updateNotificationRunning()
                    }
                }
            } catch (_: InterruptedException) {}
        }.apply { isDaemon = true; start() }
    }

    private fun formatUptime(): String {
        val elapsed = System.currentTimeMillis() - startTime
        val seconds = elapsed / 1000
        val minutes = seconds / 60
        val hours = minutes / 60
        return when {
            hours > 0 -> "${hours}h ${minutes % 60}m"
            minutes > 0 -> "${minutes}m"
            else -> "${seconds}s"
        }
    }

    private fun updateNotificationRunning() {
        updateNotification("Running on port $AGENT_PORT • ${formatUptime()}")
    }

    private fun emitLog(message: String) {
        try {
            val ts = java.time.Instant.now().toString()
            val formatted = "$ts $message"
            mainHandler.post {
                try {
                    logSink?.success(formatted)
                } catch (_: Exception) {}
            }
        } catch (_: Exception) {}
    }

    private fun acquireWakeLock() {
        releaseWakeLock()
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "MobiCoder::AgentWakeLock"
        )
        wakeLock?.acquire(24 * 60 * 60 * 1000L)
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "MobiCoder Agent",
                NotificationManager.IMPORTANCE_LOW
            )
            channel.description = "Keeps the MobiCoder agent running in background"
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("MobiCoder Agent")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(text: String) {
        try {
            val manager = getSystemService(NotificationManager::class.java)
            manager.notify(NOTIFICATION_ID, buildNotification(text))
        } catch (_: Exception) {}
    }
}

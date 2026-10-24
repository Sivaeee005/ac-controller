package com.sivaeee005.ac_controller

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.content.FileProvider
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Debug log and report for troubleshooting on the user's phone.
 *
 * Privacy: the app never writes the Wi-Fi password or the setup code to the
 * log. As a second safety net the report masks long digit groups (setup
 * codes, PINs). The user reviews the report before sharing it.
 */
object DebugReport {
  private const val TAG = "DebugReport"
  private const val LOG_FILE = "debug_log.txt"
  private const val CRASH_FILE = "last_crash.txt"
  private const val MAX_LOG_BYTES = 256 * 1024
  private val time = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)

  @Volatile private var appContext: Context? = null

  /** Call once at startup: keeps the context and records uncaught Java crashes. */
  fun install(context: Context) {
    appContext = context.applicationContext
    val previous = Thread.getDefaultUncaughtExceptionHandler()
    Thread.setDefaultUncaughtExceptionHandler { thread, error ->
      try {
        File(context.filesDir, CRASH_FILE)
          .writeText("${time.format(Date())} thread=${thread.name}\n${Log.getStackTraceString(error)}")
        log("CRASH ${error.javaClass.name}: ${error.message}")
      } catch (_: Throwable) {}
      previous?.uncaughtException(thread, error)
    }
  }

  /** Appends one line to the persistent debug log (also sent to logcat). */
  fun log(message: String) {
    Log.i("AcDebug", message)
    val ctx = appContext ?: return
    try {
      val f = File(ctx.filesDir, LOG_FILE)
      if (f.exists() && f.length() > MAX_LOG_BYTES) {
        val tail = f.readText().takeLast(MAX_LOG_BYTES / 2)
        f.writeText(tail)
      }
      f.appendText("${time.format(Date())} $message\n")
    } catch (e: Exception) {
      Log.w(TAG, "log write failed", e)
    }
  }

  fun build(context: Context): String {
    val sb = StringBuilder()
    val pkg = context.packageManager.getPackageInfo(context.packageName, 0)
    sb.appendLine("=== AC Controller debug report ===")
    sb.appendLine("Created: ${time.format(Date())}")
    sb.appendLine("App: ${pkg.versionName} (${if (Build.VERSION.SDK_INT >= 28) pkg.longVersionCode else 0})")
    sb.appendLine("Device: ${Build.MANUFACTURER} ${Build.MODEL} (${Build.DEVICE})")
    sb.appendLine("Android: ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT}), ABIs: ${Build.SUPPORTED_ABIS.joinToString()}")
    sb.appendLine()

    sb.appendLine("=== Previous app exits (Android records) ===")
    if (Build.VERSION.SDK_INT >= 30) {
      try {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val exits = am.getHistoricalProcessExitReasons(context.packageName, 0, 5)
        if (exits.isEmpty()) sb.appendLine("none")
        for (e in exits) {
          sb.appendLine("- ${time.format(Date(e.timestamp))} reason=${reasonName(e.reason)} status=${e.status} ${e.description ?: ""}")
          if (e.reason == ApplicationExitInfo.REASON_CRASH_NATIVE ||
            e.reason == ApplicationExitInfo.REASON_ANR
          ) {
            val trace = e.traceInputStream?.use { s -> s.readBytes().decodeToString(throwOnInvalidSequence = false) }
            if (trace != null) sb.appendLine(trace.take(20_000))
          }
        }
      } catch (ex: Exception) {
        sb.appendLine("unavailable: ${ex.message}")
      }
    } else {
      sb.appendLine("not available before Android 11")
    }
    sb.appendLine()

    sb.appendLine("=== Last Java crash ===")
    val crash = File(context.filesDir, CRASH_FILE)
    sb.appendLine(if (crash.exists()) crash.readText() else "none")
    sb.appendLine()

    sb.appendLine("=== App debug log ===")
    val log = File(context.filesDir, LOG_FILE)
    sb.appendLine(if (log.exists()) log.readText().takeLast(60_000) else "empty")
    sb.appendLine()

    sb.appendLine("=== System log (this app only) ===")
    sb.appendLine(readLogcat())
    return mask(sb.toString())
  }

  /** Writes the report to a file and opens the Android share sheet. */
  fun share(context: Context, report: String) {
    val dir = File(context.cacheDir, "reports").apply { mkdirs() }
    val file = File(dir, "ac-controller-debug-report.txt")
    file.writeText(report)
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.reports", file)
    val send =
      Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_STREAM, uri)
        putExtra(Intent.EXTRA_SUBJECT, "AC Controller debug report")
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
      }
    context.startActivity(
      Intent.createChooser(send, "Share debug report").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    )
  }

  fun clear(context: Context) {
    File(context.filesDir, LOG_FILE).delete()
    File(context.filesDir, CRASH_FILE).delete()
    try {
      Runtime.getRuntime().exec(arrayOf("logcat", "-c")).waitFor()
    } catch (_: Exception) {}
  }

  private fun readLogcat(): String =
    try {
      // Android lets an app read only its own log lines.
      val p = Runtime.getRuntime().exec(arrayOf("logcat", "-d", "-v", "threadtime", "-t", "4000"))
      val text = p.inputStream.bufferedReader().readText()
      p.waitFor()
      text.takeLast(120_000)
    } catch (e: Exception) {
      "unavailable: ${e.message}"
    }

  /** Masks digit groups that could be a setup code or PIN (8+ digits). */
  private fun mask(text: String): String =
    text
      .replace(Regex("""\b\d{4}-\d{3}-\d{4}\b"""), "####-###-####")
      .replace(Regex("""(?<![\d.:x])\d{8,11}(?![\d.:])"""), "<masked>")
      .replace(Regex("""MT:[0-9A-Z.\-]{10,}"""), "MT:<masked>")

  private fun reasonName(reason: Int): String =
    when (reason) {
      ApplicationExitInfo.REASON_CRASH -> "CRASH (Java)"
      ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH (native)"
      ApplicationExitInfo.REASON_ANR -> "ANR (not responding)"
      ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY"
      ApplicationExitInfo.REASON_USER_REQUESTED -> "USER_REQUESTED"
      ApplicationExitInfo.REASON_USER_STOPPED -> "USER_STOPPED"
      ApplicationExitInfo.REASON_EXIT_SELF -> "EXIT_SELF"
      ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED"
      ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "PERMISSION_CHANGE"
      ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
      ApplicationExitInfo.REASON_OTHER -> "OTHER"
      else -> "code $reason"
    }
}

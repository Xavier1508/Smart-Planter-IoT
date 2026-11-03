package io.github.xavier1508.smart_planter

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Append-only CSV history, one file per device per day. Reading only the tail
 * keeps the UI small; exporting merges all days for the active device into
 * Downloads/Tunas without growing the Flutter heap.
 */
object HistoryStore {
    private const val HISTORY_DIR = "history"
    private const val HEADER_PREFIX = "timestamp_utc,"

    private fun safeDeviceId(deviceId: String): String {
        val safe = deviceId.replace(Regex("[^A-Za-z0-9._-]"), "_").take(48)
        return safe.ifEmpty { "planter" }
    }

    private fun stamp(date: Date = Date()): String =
        SimpleDateFormat("yyyyMMdd", Locale.US).format(date)

    private fun stampTime(date: Date = Date()): String =
        SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(date)

    private fun directory(context: Context): File =
        File(context.filesDir, HISTORY_DIR).apply { mkdirs() }

    private fun fileFor(context: Context, deviceId: String): File =
        File(directory(context), "${safeDeviceId(deviceId)}-${stamp()}.csv")

    private fun filesFor(context: Context, deviceId: String): List<File> {
        val prefix = "${safeDeviceId(deviceId)}-"
        return directory(context)
            .listFiles()
            ?.filter { it.isFile && it.name.startsWith(prefix) && it.name.endsWith(".csv") }
            ?.sortedBy { it.name }
            ?: emptyList()
    }

    fun append(context: Context, deviceId: String, header: String, line: String) {
        val target = fileFor(context, deviceId)
        val isNew = !target.exists() || target.length() == 0L
        FileOutputStream(target, true).bufferedWriter(Charsets.UTF_8).use { writer ->
            if (isNew) {
                writer.write(header)
                writer.newLine()
            }
            writer.write(line)
            writer.newLine()
        }
    }

    fun readTail(context: Context, deviceId: String, limit: Int): List<String> {
        val max = limit.coerceIn(1, 10000)
        val rows = ArrayDeque<String>()
        val files = filesFor(context, deviceId).sortedByDescending { it.name }
        for (file in files) {
            if (rows.size >= max) break
            if (!file.exists()) continue
            val lines = file.readLines(Charsets.UTF_8)
            for (index in lines.indices.reversed()) {
                val line = lines[index]
                if (line.isBlank() || line.startsWith(HEADER_PREFIX)) continue
                rows.addFirst(line)
                if (rows.size >= max) break
            }
        }
        return rows.toList()
    }

    /** Total appended data rows across every day for one device. */
    fun count(context: Context, deviceId: String): Int {
        var total = 0
        for (file in filesFor(context, deviceId)) {
            if (!file.exists()) continue
            file.bufferedReader(Charsets.UTF_8).useLines { lines ->
                lines.forEach { line ->
                    if (line.isNotBlank() && !line.startsWith(HEADER_PREFIX)) {
                        total++
                    }
                }
            }
        }
        return total
    }

    fun export(context: Context, deviceId: String): String? {
        val files = filesFor(context, deviceId)
        if (files.isEmpty()) return null
        val name = "tunas-${safeDeviceId(deviceId)}-" +
            "${SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())}.csv"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, "text/csv")
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    "${Environment.DIRECTORY_DOWNLOADS}/Tunas",
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val resolver = context.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: return null
            resolver.openOutputStream(uri)?.use { output -> writeMerged(files, output) }
                ?: return null
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return "Downloads/Tunas/$name"
        }
        val targetDirectory = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: context.filesDir
        targetDirectory.mkdirs()
        val target = File(targetDirectory, name)
        target.outputStream().use { output -> writeMerged(files, output) }
        return target.absolutePath
    }

    fun saveDataset(
        context: Context,
        deviceId: String,
        csv: String,
        kind: String = "full",
    ): String? {
        val hasCanonicalHeader = csv.startsWith("schema_version,") &&
            csv.lineSequence().firstOrNull()?.contains("recorded_at_utc") == true
        val hasLegacyHeader = csv.startsWith("recorded_at_utc,")
        if ((!hasCanonicalHeader && !hasLegacyHeader) ||
            csv.length > 64 * 1024 * 1024 ||
            !csv.endsWith("\n")
        ) {
            return null
        }
        val suffix = if (kind == "ml") "ml" else "full"
        val safe = safeDeviceId(deviceId)
        val canonicalDirectory = File(context.filesDir, "datasets").apply { mkdirs() }
        val canonical = File(canonicalDirectory, "tunas-$safe-$suffix.csv")
        val temporary = File(canonicalDirectory, "tunas-$safe-$suffix.csv.tmp")
        temporary.writeText(csv, Charsets.UTF_8)
        if (canonical.exists() && !canonical.delete()) {
            temporary.delete()
            return null
        }
        if (!temporary.renameTo(canonical)) {
            temporary.delete()
            return null
        }

        val name = "tunas-$safe-$suffix-${stampTime()}.csv"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, "text/csv")
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    "${Environment.DIRECTORY_DOWNLOADS}/Tunas",
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val resolver = context.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: return canonical.absolutePath
            try {
                val output = resolver.openOutputStream(uri)
                    ?: throw IllegalStateException("download stream unavailable")
                output.use { stream ->
                    stream.write(csv.toByteArray(Charsets.UTF_8))
                }
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                return "Downloads/Tunas/$name"
            } catch (error: Exception) {
                resolver.delete(uri, null, null)
                return canonical.absolutePath
            }
        }
        val targetDirectory = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: return canonical.absolutePath
        targetDirectory.mkdirs()
        val target = File(targetDirectory, name)
        target.writeText(csv, Charsets.UTF_8)
        return target.absolutePath
    }

    private fun writeMerged(files: List<File>, output: OutputStream) {
        var headerWritten = false
        for (file in files) {
            file.bufferedReader(Charsets.UTF_8).useLines { lines ->
                lines.forEachIndexed { index, line ->
                    if (index == 0 && line.startsWith(HEADER_PREFIX)) {
                        if (!headerWritten) {
                            output.write((line + "\n").toByteArray(Charsets.UTF_8))
                            headerWritten = true
                        }
                    } else if (line.isNotBlank()) {
                        output.write((line + "\n").toByteArray(Charsets.UTF_8))
                    }
                }
            }
        }
    }

    fun clear(context: Context, deviceId: String): Boolean {
        var removed = false
        for (file in filesFor(context, deviceId)) {
            if (file.delete()) removed = true
        }
        return removed
    }
}

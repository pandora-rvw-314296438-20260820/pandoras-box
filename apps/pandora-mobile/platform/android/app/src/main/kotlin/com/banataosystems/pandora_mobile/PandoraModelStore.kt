package com.banataosystems.pandora_mobile

import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import org.json.JSONObject

/** All paths are in noBackupFilesDir. A download never writes the active model. */
data class PandoraModelManifest(
    val version: String,
    val sha256: String,
    val bytes: Long,
    val minSdk: Int,
    val minRamBytes: Long,
    val reserveBytes: Long,
    val downloadUrl: String? = null,
) {
    init {
        require(version.matches(Regex("[a-zA-Z0-9._-]{1,80}")))
        require(sha256.matches(Regex("[0-9a-f]{64}")))
        require(bytes in 1L..(8L * 1024 * 1024 * 1024))
        require(minSdk >= 29 && minRamBytes > 0 && reserveBytes >= 0)
    }

    // Never persist a signed URL or an access token.
    fun persistentJson(): JSONObject = JSONObject()
        .put("version", version).put("sha256", sha256).put("bytes", bytes)
        .put("minSdk", minSdk).put("minRamBytes", minRamBytes)
        .put("reserveBytes", reserveBytes)

    companion object {
        fun parse(value: JSONObject): PandoraModelManifest = PandoraModelManifest(
            value.getString("version"), value.getString("sha256"),
            value.getLong("bytes"), value.getInt("minSdk"),
            value.getLong("minRamBytes"), value.getLong("reserveBytes"),
            value.optString("downloadUrl").takeIf { it.isNotEmpty() },
        )
    }
}

class PandoraModelStore(
    val root: File,
    private val permittedHost: String = "jcyqixttuebxqqfkjonq.supabase.co",
    private val connect: (URL) -> HttpURLConnection = { it.openConnection() as HttpURLConnection },
) {
    init { check(root.mkdirs() || root.isDirectory) }
    private val activePointer = File(root, "active.json")
    private val previousPointer = File(root, "previous.json")
    private val trialPointer = File(root, "trial.json")

    fun model(manifest: PandoraModelManifest) = File(root, manifest.sha256 + ".gguf")
    fun partial(manifest: PandoraModelManifest) = File(root, manifest.sha256 + ".part")
    fun active(): PandoraModelManifest? = readPointer(activePointer)
    fun previous(): PandoraModelManifest? = readPointer(previousPointer)

    private fun readPointer(file: File): PandoraModelManifest? = try {
        if (!file.isFile || file.length() > 4096) null
        else PandoraModelManifest.parse(JSONObject(file.readText()))
    } catch (_: Exception) { null }

    fun verify(manifest: PandoraModelManifest, file: File = model(manifest)): Boolean =
        file.isFile && file.length() == manifest.bytes && digest(file) == manifest.sha256

    fun rejected(manifest: PandoraModelManifest): Boolean {
        val marker = File(root, manifest.sha256 + ".retry-after")
        val until = marker.takeIf { it.isFile }?.readText()?.toLongOrNull() ?: 0
        return System.currentTimeMillis() < until
    }

    fun beginTrial(manifest: PandoraModelManifest) {
        atomicJson(trialPointer, manifest.persistentJson())
    }

    /** A process death during candidate loading cannot promote that candidate. */
    fun recoverInterruptedTrial() {
        readPointer(trialPointer)?.let { reject(it) }
        trialPointer.delete()
    }

    fun reject(manifest: PandoraModelManifest) {
        File(root, manifest.sha256 + ".retry-after")
            .writeText((System.currentTimeMillis() + 15 * 60_000L).toString())
        trialPointer.delete()
    }

    /** Called only after successful native token generation in the current process. */
    fun activateAfterHealthTest(manifest: PandoraModelManifest, tokenEvents: Int) {
        require(tokenEvents > 0)
        require(verify(manifest))
        val old = active()
        if (old != null && old.sha256 != manifest.sha256) {
            atomicJson(previousPointer, old.persistentJson())
        }
        atomicJson(activePointer, manifest.persistentJson())
        trialPointer.delete()
        File(root, manifest.sha256 + ".retry-after").delete()
        // Keep previous and active. Incomplete newer downloads are independently resumable.
    }

    /** Returns a fully verified immutable candidate, without changing the active pointer. */
    fun acquire(manifest: PandoraModelManifest, progress: (Long) -> Unit = {}): File {
        val complete = model(manifest)
        if (verify(manifest, complete)) return complete
        val address = URL(requireNotNull(manifest.downloadUrl) { "grant_required" })
        require(address.protocol == "https" && address.host == permittedHost)
        require(address.port == -1 || address.port == 443)
        require(address.path.startsWith("/storage/v1/object/sign/pandora-models/"))
        require(!address.path.contains("..") && address.userInfo == null)
        val temp = partial(manifest)
        if (temp.length() > manifest.bytes) check(temp.delete())
        require(root.usableSpace >= manifest.bytes - temp.length() + manifest.reserveBytes) {
            "storage_admission"
        }
        if (temp.length() != manifest.bytes) {
            transfer(address, manifest, temp, progress)
        }
        if (!verify(manifest, temp)) {
            // A corrupt candidate must not poison a subsequent resume.
            temp.delete()
            error("candidate_integrity")
        }
        Files.move(temp.toPath(), complete.toPath(),
            StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        check(verify(manifest, complete))
        return complete
    }

    private fun transfer(
        address: URL,
        manifest: PandoraModelManifest,
        temp: File,
        progress: (Long) -> Unit,
    ) {
        val initialOffset = temp.length()
        val connection = connect(address)
        connection.instanceFollowRedirects = false
        connection.connectTimeout = 15_000
        connection.readTimeout = 30_000
        connection.setRequestProperty("Accept-Encoding", "identity")
        if (initialOffset > 0) connection.setRequestProperty("Range", "bytes=" + initialOffset + "-")
        try {
            val code = connection.responseCode
            require(code == 200 || code == 206) { "download_http_" + code }
            val offset = if (code == 200) 0L else initialOffset
            if (code == 206) {
                val range = Regex("bytes ([0-9]+)-([0-9]+)/([0-9]+)")
                    .matchEntire(connection.getHeaderField("Content-Range") ?: "")
                    ?: error("download_range_missing")
                require(range.groupValues[1].toLong() == initialOffset)
                require(range.groupValues[3].toLong() == manifest.bytes)
                require(range.groupValues[2].toLong() == manifest.bytes - 1)
            }
            val declared = connection.getHeaderFieldLong("Content-Length", -1)
            if (declared >= 0) require(declared == manifest.bytes - offset)
            RandomAccessFile(temp, "rw").use { output ->
                // A server that ignores Range is safely restarted, never appended.
                output.setLength(offset)
                output.seek(offset)
                var copied = offset
                var lastProgress = 0L
                connection.inputStream.buffered(256 * 1024).use { input ->
                    val buffer = ByteArray(256 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (count == 0) continue
                        require(copied + count <= manifest.bytes) { "download_oversize" }
                        require(root.usableSpace >= manifest.reserveBytes) { "storage_pressure" }
                        output.write(buffer, 0, count)
                        copied += count
                        val now = System.currentTimeMillis()
                        if (now - lastProgress > 2000) {
                            progress(copied)
                            lastProgress = now
                        }
                    }
                }
                output.fd.sync()
                require(copied == manifest.bytes) { "download_incomplete" }
            }
        } finally { connection.disconnect() }
    }

    private fun atomicJson(target: File, value: JSONObject) {
        val temporary = File(root, target.name + ".tmp")
        FileOutputStream(temporary).use {
            it.write(value.toString().toByteArray(Charsets.UTF_8))
            it.fd.sync()
        }
        Files.move(temporary.toPath(), target.toPath(),
            StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
    }

    companion object {
        fun digest(file: File): String {
            val hash = MessageDigest.getInstance("SHA-256")
            file.inputStream().buffered(256 * 1024).use { input ->
                val bytes = ByteArray(256 * 1024)
                while (true) {
                    val count = input.read(bytes)
                    if (count < 0) break
                    if (count > 0) hash.update(bytes, 0, count)
                }
            }
            return hash.digest().joinToString("") { "%02x".format(it) }
        }
    }
}

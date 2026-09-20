package com.banataosystems.pandora_mobile

import java.io.ByteArrayInputStream
import java.io.File
import java.io.InputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.nio.file.Files
import java.security.MessageDigest
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class PandoraModelStoreTest {
    private val bytes = ByteArray(4096) { (it % 251).toByte() }
    private fun manifest(data: ByteArray = bytes, version: String = "v1") =
        PandoraModelManifest(version,
            MessageDigest.getInstance("SHA-256").digest(data).joinToString("") { "%02x".format(it) },
            data.size.toLong(), 29, 1, 0,
            "https://jcyqixttuebxqqfkjonq.supabase.co/storage/v1/object/sign/pandora-models/version/model.gguf?token=ephemeral")

    private class Reply(
        address: URL, val payload: ByteArray, val code: Int = 200,
        val range: String? = null, val failAt: Int? = null,
    ) : HttpURLConnection(address) {
        val requestHeaders = mutableMapOf<String, String>()
        override fun connect() {}
        override fun disconnect() {}
        override fun usingProxy() = false
        override fun setRequestProperty(key: String, value: String) { requestHeaders[key] = value }
        override fun getResponseCode() = code
        override fun getHeaderField(key: String?): String? = when (key) {
            "Content-Range" -> range
            "Content-Length" -> payload.size.toString()
            else -> null
        }
        override fun getInputStream(): InputStream {
            if (failAt == null) return ByteArrayInputStream(payload)
            return object : InputStream() {
                var position = 0
                override fun read(): Int {
                    if (position >= failAt) throw IOException("interrupted")
                    return if (position >= payload.size) -1 else payload[position++].toInt() and 255
                }
                override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                    if (position >= failAt) throw IOException("interrupted")
                    val count = minOf(length, failAt - position, payload.size - position)
                    if (count == 0) return -1
                    System.arraycopy(payload, position, buffer, offset, count)
                    position += count
                    return count
                }
            }
        }
    }

    private fun directory() = Files.createTempDirectory("pandora-model-test").toFile()
    private fun expectFailure(block: () -> Unit) {
        try { block(); fail("Expected rejection") } catch (_: IllegalArgumentException) {
        } catch (_: IllegalStateException) {
        } catch (_: IOException) { }
    }

    @Test fun interruptedDownloadResumesExactRangeAndOnlyThenBecomesCandidate() {
        val root = directory()
        val m = manifest()
        val first = PandoraModelStore(root, connect = { Reply(it, bytes, failAt = 1024) })
        expectFailure { first.acquire(m) }
        assertEquals(1024L, first.partial(m).length())
        assertFalse(first.model(m).exists())
        lateinit var response: Reply
        val restarted = PandoraModelStore(root, connect = {
            Reply(it, bytes.copyOfRange(1024, bytes.size), 206,
                "bytes 1024-4095/4096").also { reply -> response = reply }
        })
        restarted.acquire(m)
        assertEquals("bytes=1024-", response.requestHeaders["Range"])
        assertTrue(restarted.verify(m))
        assertNull(restarted.active())
        assertFalse(restarted.partial(m).exists())
    }

    @Test fun verifiedCacheSurvivesReopenAndNeedsNoNetwork() {
        val root = directory()
        val m = manifest()
        val first = PandoraModelStore(root, connect = { Reply(it, bytes) })
        first.acquire(m)
        first.activateAfterHealthTest(m, 2)
        var requests = 0
        val restarted = PandoraModelStore(root, connect = { requests++; error("offline") })
        assertTrue(restarted.verify(restarted.active()!!))
        restarted.acquire(m.copy(downloadUrl = null))
        assertEquals(0, requests)
    }

    @Test fun corruptUpdateNeverReplacesActiveAndZeroTokensCannotActivate() {
        val root = directory()
        val old = manifest()
        val good = PandoraModelStore(root, connect = { Reply(it, bytes) })
        good.acquire(old)
        good.activateAfterHealthTest(old, 2)
        val updateBytes = ByteArray(4096) { 42 }
        val update = manifest(updateBytes, "v2")
        val corrupt = PandoraModelStore(root, connect = { Reply(it, bytes) })
        expectFailure { corrupt.acquire(update) }
        assertEquals(old.sha256, corrupt.active()!!.sha256)
        assertTrue(corrupt.verify(old))
        assertFalse(corrupt.partial(update).exists())
        val next = PandoraModelStore(root, connect = { Reply(it, updateBytes) })
        next.acquire(update)
        expectFailure { next.activateAfterHealthTest(update, 0) }
        assertEquals(old.sha256, next.active()!!.sha256)
    }

    @Test fun deathDuringActivationRollsBackAndRetainsPreviousVerifiedBytes() {
        val root = directory()
        val old = manifest()
        val updateBytes = ByteArray(4096) { 7 }
        val update = manifest(updateBytes, "v2")
        val store = PandoraModelStore(root, connect = { Reply(it, bytes) })
        store.acquire(old); store.activateAfterHealthTest(old, 1)
        val next = PandoraModelStore(root, connect = { Reply(it, updateBytes) })
        next.acquire(update); next.beginTrial(update)
        val reopened = PandoraModelStore(root)
        reopened.recoverInterruptedTrial()
        assertEquals(old.sha256, reopened.active()!!.sha256)
        assertTrue(reopened.rejected(update))
        assertTrue(reopened.verify(old))
        next.activateAfterHealthTest(update, 3)
        assertEquals(update.sha256, next.active()!!.sha256)
        assertEquals(old.sha256, next.previous()!!.sha256)
    }

    @Test fun serverIgnoringRangeRestartsRatherThanAppending() {
        val root = directory()
        val m = manifest()
        val store = PandoraModelStore(root, connect = { Reply(it, bytes) })
        store.partial(m).writeBytes(bytes.copyOfRange(0, 1024))
        store.acquire(m)
        assertTrue(store.verify(m))
        assertEquals(bytes.size.toLong(), store.model(m).length())
    }

    @Test fun incorrectRangeAndTruncationCannotBePromoted() {
        val root = directory()
        val m = manifest()
        val store = PandoraModelStore(root, connect = { Reply(it, bytes.copyOfRange(1024, 4096), 206,
            "bytes 0-3071/4096") })
        store.partial(m).writeBytes(bytes.copyOfRange(0, 1024))
        expectFailure { store.acquire(m) }
        assertFalse(store.model(m).exists())
        assertNull(store.active())
    }

    @Test fun persistedManifestContainsNoSignedLocationOrCredentials() {
        val m = manifest()
        val json = m.persistentJson().toString()
        assertFalse(json.contains("downloadUrl"))
        assertFalse(json.contains("token"))
        assertFalse(json.contains("https"))
        assertEquals(m.sha256, PandoraModelManifest.parse(JSONObject(json)).sha256)
    }

    @Test fun untrustedLocationsAndTraversalAreRejectedBeforeNetwork() {
        val store = PandoraModelStore(directory(), connect = { error("must not connect") })
        expectFailure { store.acquire(manifest().copy(downloadUrl = "https://attacker.example/model")) }
        expectFailure { manifest().copy(sha256 = "../../outside") }
        expectFailure { manifest().copy(version = "../outside") }
    }
}

package com.banataosystems.pandora_mobile

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import android.util.Base64
import org.json.JSONObject
import java.io.File
import java.io.InputStream
import java.security.MessageDigest
import java.security.Signature
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.util.zip.ZipFile

internal class PandoraSignedUpdateChannel(private val context: Context) {
    companion object {
        private const val SCHEMA_VERSION = "1.0.0"
        private const val STAGING_DIRECTORY = "pandora-updates"
        private const val MAX_MANIFEST_BYTES = 64 * 1024
        private const val MAX_APK_BYTES = 512L * 1024L * 1024L
        private const val MAX_SOURCE_SCAN_BYTES = 256L * 1024L * 1024L
        private const val MAX_RELEASE_WINDOW_SECONDS = 30L * 24L * 60L * 60L
        private const val CLOCK_SKEW_SECONDS = 5L * 60L
        private val HEX_40 = Regex("^[0-9a-f]{40}$")
        private val HEX_64 = Regex("^[0-9a-f]{64}$")
        private val CHANNELS = setOf("stable", "enterprise")
        private val TOP_LEVEL_KEYS = setOf(
            "schemaVersion", "packageName", "channel", "issuedAtEpochSeconds",
            "expiresAtEpochSeconds", "productionRelease", "candidate", "recovery"
        )
        private val CANDIDATE_KEYS = setOf(
            "apkSha256", "sourceSha", "sourceTree", "versionCode",
            "versionName", "signerSha256"
        )
        private val RECOVERY_KEYS = CANDIDATE_KEYS + "rollbackTargetSourceSha"
    }

    private data class ArtifactExpectation(
        val apkSha256: String,
        val sourceSha: String,
        val sourceTree: String,
        val versionCode: Long,
        val versionName: String,
        val signerSha256: String,
        val rollbackTargetSourceSha: String? = null
    )

    private data class ArtifactProof(
        val path: String,
        val apkSha256: String,
        val sourceSha: String,
        val sourceTree: String,
        val versionCode: Long,
        val versionName: String,
        val signerSha256: String
    )

    fun policySnapshot(deviceOwnerProvisioned: Boolean): Map<String, Any?> {
        val declaresUnknownSourcePermission = requestedPermissions().contains(
            "android.permission.REQUEST_INSTALL_PACKAGES"
        )
        return mapOf(
            "schemaVersion" to SCHEMA_VERSION,
            "platform" to "android",
            "packageName" to context.packageName,
            "artifactStagingScope" to "app_private_only",
            "manifestSignatureAuthority" to "installed_app_signer",
            "signerRotationPolicy" to "exact_current_signer_v1",
            "sourceShaAuthority" to "apk_embedded_revision",
            "sourceTreeAuthority" to "signed_manifest",
            "rollbackStrategy" to "forward_version_signed_recovery",
            "requiresCandidateAndRecovery" to true,
            "requestInstallPackagesAllowed" to false,
            "requestInstallPackagesDeclared" to declaresUnknownSourcePermission,
            "unknownSourcesInstallAllowed" to false,
            "directInstallerExposed" to false,
            "deviceOwnerProvisioned" to deviceOwnerProvisioned,
            "installRoute" to installRoute(deviceOwnerProvisioned),
            "userConfirmationRequired" to !deviceOwnerProvisioned,
            "productionVerificationAvailable" to (!isDebuggable() && !declaresUnknownSourcePermission),
            "physicalUpdateVerified" to false,
            "physicalRollbackVerified" to false
        )
    }

    fun verifyBundle(
        rawArguments: Map<String, Any?>?,
        deviceOwnerProvisioned: Boolean
    ): Map<String, Any?> {
        val arguments = rawArguments ?: reject("Signed update arguments are required.")
        rejectUnknown(arguments.keys, setOf(
            "manifestPayload", "manifestSignatureBase64", "candidatePath", "recoveryPath"
        ), "update arguments")
        val payload = boundedText(arguments["manifestPayload"], "manifestPayload", MAX_MANIFEST_BYTES)
        val signatureBase64 = boundedText(
            arguments["manifestSignatureBase64"],
            "manifestSignatureBase64",
            16 * 1024
        )
        if (isDebuggable()) reject("Production update verification is disabled on debuggable builds.")
        if (requestedPermissions().contains("android.permission.REQUEST_INSTALL_PACKAGES")) {
            reject("Unknown-source installation permission violates the update trust boundary.")
        }

        val installed = installedPackageInfo()
        val installedCertificate = singleSigningCertificate(installed)
        val installedSigner = certificateSha256(installedCertificate)
        verifyManifestSignature(payload, signatureBase64, installedCertificate)
        val manifest = try {
            JSONObject(payload)
        } catch (_: Exception) {
            reject("Signed update manifest is not valid JSON.")
        }
        rejectUnknown(jsonKeys(manifest), TOP_LEVEL_KEYS, "signed update manifest")
        if (requiredString(manifest, "schemaVersion", 20) != SCHEMA_VERSION) {
            reject("Unsupported signed update schema.")
        }
        if (requiredString(manifest, "packageName", 200) != context.packageName) {
            reject("Signed update package does not match Pandora.")
        }
        val channel = requiredString(manifest, "channel", 32)
        if (!CHANNELS.contains(channel)) reject("Unsupported signed update channel.")
        if (!requiredBoolean(manifest, "productionRelease")) {
            reject("Update bundle must be an explicit production release.")
        }
        verifyReleaseWindow(manifest)

        val candidate = parseArtifact(manifest.getJSONObject("candidate"), false)
        val recovery = parseArtifact(manifest.getJSONObject("recovery"), true)
        if (candidate.signerSha256 != installedSigner || recovery.signerSha256 != installedSigner) {
            reject("Candidate and recovery signer must exactly match the installed Pandora signer.")
        }
        val currentVersionCode = longVersionCode(installed)
        if (candidate.versionCode <= currentVersionCode) {
            reject("Candidate version code must advance the installed version.")
        }
        if (recovery.versionCode <= candidate.versionCode) {
            reject("Recovery version code must advance the candidate; Android downgrade is forbidden.")
        }
        val rollbackTarget = recovery.rollbackTargetSourceSha
            ?: reject("Recovery rollback target source is required.")
        if (!apkContainsSourceRevision(File(context.applicationInfo.sourceDir), rollbackTarget)) {
            reject("Recovery rollback target is not the source revision installed on this device.")
        }

        val candidateProof = verifyArtifact(
            boundedText(arguments["candidatePath"], "candidatePath", 1024),
            candidate,
            installedSigner
        )
        val recoveryProof = verifyArtifact(
            boundedText(arguments["recoveryPath"], "recoveryPath", 1024),
            recovery,
            installedSigner
        )
        return mapOf(
            "schemaVersion" to SCHEMA_VERSION,
            "status" to "verified",
            "channel" to channel,
            "packageName" to context.packageName,
            "productionRelease" to true,
            "manifestSignatureVerified" to true,
            "installedSignerVerified" to true,
            "candidateVerified" to true,
            "recoveryVerified" to true,
            "sourceShaAuthority" to "apk_embedded_revision",
            "sourceTreeAuthority" to "signed_manifest",
            "rollbackStrategy" to "forward_version_signed_recovery",
            "currentVersionCode" to currentVersionCode,
            "candidate" to proofMap(candidateProof),
            "recovery" to (proofMap(recoveryProof) + mapOf(
                "rollbackTargetSourceSha" to rollbackTarget
            )),
            "installRoute" to installRoute(deviceOwnerProvisioned),
            "userConfirmationRequired" to !deviceOwnerProvisioned,
            "requestInstallPackagesAllowed" to false,
            "directInstallerExposed" to false,
            "installExecuted" to false,
            "physicalUpdateVerified" to false,
            "physicalRollbackVerified" to false
        )
    }

    private fun parseArtifact(json: JSONObject, recovery: Boolean): ArtifactExpectation {
        rejectUnknown(jsonKeys(json), if (recovery) RECOVERY_KEYS else CANDIDATE_KEYS, "artifact")
        val apkSha = requiredHex(json, "apkSha256", HEX_64)
        val sourceSha = requiredHex(json, "sourceSha", HEX_40)
        val sourceTree = requiredHex(json, "sourceTree", HEX_40)
        val signerSha = requiredHex(json, "signerSha256", HEX_64)
        val versionCode = requiredPositiveLong(json, "versionCode")
        val versionName = requiredString(json, "versionName", 80)
        val target = if (recovery) requiredHex(json, "rollbackTargetSourceSha", HEX_40) else null
        return ArtifactExpectation(
            apkSha, sourceSha, sourceTree, versionCode, versionName, signerSha, target
        )
    }

    private fun verifyArtifact(
        rawPath: String,
        expected: ArtifactExpectation,
        installedSigner: String
    ): ArtifactProof {
        val file = requirePrivateStagedApk(rawPath)
        val digest = sha256File(file)
        if (digest != expected.apkSha256) reject("Staged APK digest does not match signed manifest.")
        val info = archivePackageInfo(file)
        if (info.packageName != context.packageName) reject("Staged APK package mismatch.")
        if (longVersionCode(info) != expected.versionCode || info.versionName != expected.versionName) {
            reject("Staged APK version identity does not match signed manifest.")
        }
        val archiveSigner = certificateSha256(singleSigningCertificate(info))
        if (archiveSigner != expected.signerSha256 || archiveSigner != installedSigner) {
            reject("Staged APK signer does not match installed Pandora signer.")
        }
        if (!apkContainsSourceRevision(file, expected.sourceSha)) {
            reject("Staged APK does not contain its signed source revision.")
        }
        return ArtifactProof(
            file.canonicalPath,
            digest,
            expected.sourceSha,
            expected.sourceTree,
            expected.versionCode,
            expected.versionName,
            archiveSigner
        )
    }

    private fun proofMap(proof: ArtifactProof): Map<String, Any?> = mapOf(
        "staging" to "app_private_verified",
        "apkSha256" to proof.apkSha256,
        "sourceSha" to proof.sourceSha,
        "sourceTree" to proof.sourceTree,
        "versionCode" to proof.versionCode,
        "versionName" to proof.versionName,
        "signerSha256" to proof.signerSha256,
        "hashVerified" to true,
        "packageVerified" to true,
        "versionVerified" to true,
        "sourceShaVerified" to true,
        "signerVerified" to true
    )

    private fun verifyManifestSignature(
        payload: String,
        signatureBase64: String,
        certificate: X509Certificate
    ) {
        val signatureBytes = try {
            Base64.decode(signatureBase64, Base64.DEFAULT)
        } catch (_: IllegalArgumentException) {
            reject("Signed update signature is not valid base64.")
        }
        if (signatureBytes.isEmpty() || signatureBytes.size > 16 * 1024) {
            reject("Signed update signature size is invalid.")
        }
        val algorithm = when (certificate.publicKey.algorithm.uppercase()) {
            "RSA" -> "SHA256withRSA"
            "EC", "ECDSA" -> "SHA256withECDSA"
            else -> reject("Installed Pandora signer algorithm is unsupported for update manifests.")
        }
        val verifier = Signature.getInstance(algorithm)
        verifier.initVerify(certificate.publicKey)
        verifier.update(payload.toByteArray(Charsets.UTF_8))
        if (!verifier.verify(signatureBytes)) reject("Signed update manifest signature verification failed.")
    }

    private fun verifyReleaseWindow(json: JSONObject) {
        val issuedAt = requiredPositiveLong(json, "issuedAtEpochSeconds")
        val expiresAt = requiredPositiveLong(json, "expiresAtEpochSeconds")
        val now = System.currentTimeMillis() / 1000L
        if (issuedAt > now + CLOCK_SKEW_SECONDS) reject("Signed update manifest is issued in the future.")
        if (expiresAt <= now) reject("Signed update manifest has expired.")
        if (expiresAt <= issuedAt || expiresAt - issuedAt > MAX_RELEASE_WINDOW_SECONDS) {
            reject("Signed update manifest validity window is invalid.")
        }
    }

    private fun requirePrivateStagedApk(rawPath: String): File {
        val file = File(rawPath).canonicalFile
        val roots = listOf(
            File(context.filesDir, STAGING_DIRECTORY).canonicalFile,
            File(context.cacheDir, STAGING_DIRECTORY).canonicalFile
        )
        if (roots.none { isInside(file, it) }) reject("Staged APK must remain in Pandora app-private storage.")
        if (!file.isFile || !file.name.endsWith(".apk", ignoreCase = true)) {
            reject("Staged update artifact must be a regular APK file.")
        }
        if (file.length() <= 0L || file.length() > MAX_APK_BYTES) reject("Staged APK size is invalid.")
        return file
    }

    private fun isInside(file: File, root: File): Boolean {
        val prefix = root.path + File.separator
        return file.path == root.path || file.path.startsWith(prefix)
    }

    private fun apkContainsSourceRevision(file: File, sourceSha: String): Boolean {
        if (!HEX_40.matches(sourceSha)) reject("Source revision format is invalid.")
        return try {
            ZipFile(file).use { zip ->
                val entry = zip.getEntry("assets/flutter_assets/kernel_blob.bin") ?: return false
                if (entry.size > MAX_SOURCE_SCAN_BYTES) return false
                zip.getInputStream(entry).use { stream ->
                    containsAscii(stream, sourceSha.toByteArray(Charsets.US_ASCII))
                }
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun containsAscii(stream: InputStream, needle: ByteArray): Boolean {
        val buffer = ByteArray(64 * 1024)
        var matched = 0
        var total = 0L
        while (true) {
            val count = stream.read(buffer)
            if (count <= 0) return false
            total += count
            if (total > MAX_SOURCE_SCAN_BYTES) return false
            for (index in 0 until count) {
                if (buffer[index] == needle[matched]) {
                    matched += 1
                    if (matched == needle.size) return true
                } else {
                    matched = if (buffer[index] == needle[0]) 1 else 0
                }
            }
        }
    }

    private fun sha256File(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { stream ->
            val buffer = ByteArray(128 * 1024)
            while (true) {
                val count = stream.read(buffer)
                if (count <= 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun installedPackageInfo(): PackageInfo = try {
        if (Build.VERSION.SDK_INT >= 33) {
            context.packageManager.getPackageInfo(
                context.packageName,
                PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES.toLong())
            )
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageInfo(
                context.packageName,
                PackageManager.GET_SIGNING_CERTIFICATES
            )
        }
    } catch (_: PackageManager.NameNotFoundException) {
        reject("Installed Pandora package identity is unavailable.")
    }

    private fun archivePackageInfo(file: File): PackageInfo {
        val info = if (Build.VERSION.SDK_INT >= 33) {
            context.packageManager.getPackageArchiveInfo(
                file.path,
                PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES.toLong())
            )
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageArchiveInfo(file.path, PackageManager.GET_SIGNING_CERTIFICATES)
        }
        return info ?: reject("Staged APK package identity is unreadable.")
    }

    private fun singleSigningCertificate(info: PackageInfo): X509Certificate {
        val signatureBytes = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signingInfo = info.signingInfo ?: reject("APK signing information is unavailable.")
            val signers = if (signingInfo.hasMultipleSigners()) {
                signingInfo.apkContentsSigners
            } else {
                signingInfo.signingCertificateHistory
            }
            if (signers.size != 1) reject("Pandora update channel currently requires one exact signer.")
            signers[0].toByteArray()
        } else {
            @Suppress("DEPRECATION")
            val signers = info.signatures ?: reject("APK signing information is unavailable.")
            if (signers.size != 1) reject("Pandora update channel currently requires one exact signer.")
            signers[0].toByteArray()
        }
        return CertificateFactory.getInstance("X.509")
            .generateCertificate(signatureBytes.inputStream()) as X509Certificate
    }

    private fun certificateSha256(certificate: X509Certificate): String =
        MessageDigest.getInstance("SHA-256").digest(certificate.encoded)
            .joinToString("") { "%02x".format(it) }

    private fun longVersionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }

    private fun requestedPermissions(): Set<String> = try {
        val info = if (Build.VERSION.SDK_INT >= 33) {
            context.packageManager.getPackageInfo(
                context.packageName,
                PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong())
            )
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
        }
        info.requestedPermissions?.toSet().orEmpty()
    } catch (_: PackageManager.NameNotFoundException) {
        emptySet()
    }

    private fun installRoute(deviceOwnerProvisioned: Boolean): String =
        if (deviceOwnerProvisioned) "managed_device_owner_distribution" else "trusted_store_or_user_installer"

    private fun isDebuggable(): Boolean =
        (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

    private fun jsonKeys(json: JSONObject): Set<String> {
        val keys = mutableSetOf<String>()
        val iterator = json.keys()
        while (iterator.hasNext()) keys += iterator.next()
        return keys
    }

    private fun rejectUnknown(actual: Set<String>, allowed: Set<String>, label: String) {
        if (actual != allowed) reject("$label fields do not match the signed update contract.")
    }

    private fun requiredString(json: JSONObject, key: String, maxLength: Int): String {
        val value = try { json.getString(key).trim() } catch (_: Exception) { reject("$key is invalid.") }
        if (value.isEmpty() || value.length > maxLength) reject("$key is invalid.")
        return value
    }

    private fun requiredHex(json: JSONObject, key: String, pattern: Regex): String {
        val value = requiredString(json, key, 128).lowercase()
        if (!pattern.matches(value)) reject("$key is invalid.")
        return value
    }

    private fun requiredPositiveLong(json: JSONObject, key: String): Long {
        val value = try { json.getLong(key) } catch (_: Exception) { reject("$key is invalid.") }
        if (value <= 0L) reject("$key must be positive.")
        return value
    }

    private fun requiredBoolean(json: JSONObject, key: String): Boolean =
        try { json.getBoolean(key) } catch (_: Exception) { reject("$key is invalid.") }

    private fun boundedText(value: Any?, label: String, maxLength: Int): String {
        if (value !is String || value.isEmpty() || value.length > maxLength) reject("$label is invalid.")
        return value
    }

    private fun reject(message: String): Nothing = throw IllegalArgumentException(message)
}
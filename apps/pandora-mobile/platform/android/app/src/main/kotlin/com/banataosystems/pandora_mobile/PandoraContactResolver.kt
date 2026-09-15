package com.banataosystems.pandora_mobile

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.ContactsContract
import android.telephony.PhoneNumberUtils
import java.util.Locale

internal class PandoraContactResolver(private val context: Context) {
    companion object {
        private const val MAX_QUERY_LENGTH = 120
        private const val MAX_CANDIDATES = 5
        private val RECIPIENT_PATTERN = Regex("^[0-9+*#(). -]{1,64}$")
    }

    private data class PhoneCandidate(
        val contactId: Long,
        val displayName: String,
        val phoneNumber: String,
        val normalizedPhoneNumber: String,
        val isPrimary: Boolean,
        val isSuperPrimary: Boolean,
        val type: Int
    )

    fun resolve(rawQuery: String): Map<String, Any?> {
        val query = rawQuery.trim().replace(Regex("\\s+"), " ")
        require(query.isNotEmpty() && query.length <= MAX_QUERY_LENGTH) {
            "Invalid contact query."
        }

        if (context.packageManager.checkPermission(
                Manifest.permission.READ_CONTACTS,
                context.packageName
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return permissionRequired()
        }

        val candidates = try {
            queryCandidates()
        } catch (_: SecurityException) {
            return permissionRequired()
        } catch (_: RuntimeException) {
            return unavailable("contacts_query_failed")
        }
        if (candidates.isEmpty()) return notFound()

        val normalizedQuery = normalizeName(query)
        val exact = candidates.filter { normalizeName(it.displayName) == normalizedQuery }
        if (exact.isNotEmpty()) {
            return resolveIdentitySet(exact, "exact")
        }

        if (!normalizedQuery.contains(' ')) {
            val firstNameMatches = candidates.filter {
                normalizeName(it.displayName).substringBefore(' ') == normalizedQuery
            }
            if (firstNameMatches.isNotEmpty()) {
                return resolveIdentitySet(firstNameMatches, "unique_first_name")
            }
        }

        return notFound()
    }

    private fun queryCandidates(): List<PhoneCandidate> {
        val projection = arrayOf(
            ContactsContract.CommonDataKinds.Phone.CONTACT_ID,
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
            ContactsContract.CommonDataKinds.Phone.NUMBER,
            ContactsContract.CommonDataKinds.Phone.NORMALIZED_NUMBER,
            ContactsContract.CommonDataKinds.Phone.IS_PRIMARY,
            ContactsContract.CommonDataKinds.Phone.IS_SUPER_PRIMARY,
            ContactsContract.CommonDataKinds.Phone.TYPE
        )
        val result = ArrayList<PhoneCandidate>()
        context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                projection,
                null,
                null,
                null
        )?.use { cursor ->
                val contactIdIndex = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.CONTACT_ID)
                val displayNameIndex = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                val numberIndex = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                val normalizedIndex = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NORMALIZED_NUMBER)
                val primaryIndex = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.IS_PRIMARY)
                val superPrimaryIndex = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.IS_SUPER_PRIMARY)
                val typeIndex = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.TYPE)
                while (cursor.moveToNext()) {
                    if (contactIdIndex < 0 || displayNameIndex < 0 || numberIndex < 0) continue
                    val contactId = cursor.getLong(contactIdIndex)
                    val displayName = cursor.getString(displayNameIndex)?.trim().orEmpty()
                    val rawNumber = cursor.getString(numberIndex)?.trim().orEmpty()
                    if (contactId <= 0L || displayName.isEmpty() || rawNumber.isEmpty()) continue
                    val normalizedFromProvider = if (normalizedIndex >= 0) {
                        cursor.getString(normalizedIndex)?.trim().orEmpty()
                    } else {
                        ""
                    }
                    val normalizedNumber = normalizePhoneNumber(
                        if (normalizedFromProvider.isNotEmpty()) normalizedFromProvider else rawNumber
                    )
                    if (!isSupportedRecipient(normalizedNumber)) continue
                    result.add(
                        PhoneCandidate(
                            contactId = contactId,
                            displayName = displayName,
                            phoneNumber = normalizedNumber,
                            normalizedPhoneNumber = normalizedNumber,
                            isPrimary = primaryIndex >= 0 && cursor.getInt(primaryIndex) == 1,
                            isSuperPrimary = superPrimaryIndex >= 0 && cursor.getInt(superPrimaryIndex) == 1,
                            type = if (typeIndex >= 0) cursor.getInt(typeIndex) else ContactsContract.CommonDataKinds.Phone.TYPE_OTHER
                        )
                    )
                }
            }
        return result.distinctBy { "${it.contactId}:${it.normalizedPhoneNumber}" }
    }

    private fun resolveIdentitySet(
        matches: List<PhoneCandidate>,
        resolution: String
    ): Map<String, Any?> {
        val identities = matches.groupBy { it.contactId }
        if (identities.size != 1) {
            return ambiguous(identities.values.map { it.first() }, resolution, "multiple_contacts")
        }

        val numbers = identities.values.single().distinctBy { it.normalizedPhoneNumber }
        if (numbers.isEmpty()) return notFound()
        if (numbers.size == 1) return resolved(numbers.single(), resolution)

        val ranked = numbers.sortedWith(
            compareByDescending<PhoneCandidate> { it.isSuperPrimary }
                .thenByDescending { it.isPrimary }
                .thenByDescending { typePriority(it.type) }
                .thenBy { it.normalizedPhoneNumber }
        )
        val best = ranked.first()
        val bestRank = Triple(best.isSuperPrimary, best.isPrimary, typePriority(best.type))
        val tied = ranked.filter {
            Triple(it.isSuperPrimary, it.isPrimary, typePriority(it.type)) == bestRank
        }
        if (tied.size == 1) return resolved(best, resolution)
        return ambiguous(tied, resolution, "multiple_numbers")
    }

    private fun resolved(candidate: PhoneCandidate, resolution: String): Map<String, Any?> = mapOf(
        "status" to "resolved",
        "source" to "android_contacts",
        "resolution" to resolution,
        "displayName" to candidate.displayName,
        "phoneNumber" to candidate.phoneNumber,
        "normalizedPhoneNumber" to candidate.normalizedPhoneNumber,
        "contactId" to candidate.contactId.toString(),
        "requiredPermission" to Manifest.permission.READ_CONTACTS,
        "candidates" to emptyList<Map<String, Any?>>()
    )

    private fun ambiguous(
        candidates: List<PhoneCandidate>,
        resolution: String,
        reason: String
    ): Map<String, Any?> = mapOf(
        "status" to "ambiguous",
        "source" to "android_contacts",
        "resolution" to resolution,
        "reason" to reason,
        "requiredPermission" to Manifest.permission.READ_CONTACTS,
        "candidates" to candidates
            .distinctBy { "${it.contactId}:${it.normalizedPhoneNumber}" }
            .take(MAX_CANDIDATES)
            .map {
                mapOf(
                    "contactId" to it.contactId.toString(),
                    "displayName" to it.displayName,
                    "phoneNumber" to it.phoneNumber,
                    "normalizedPhoneNumber" to it.normalizedPhoneNumber
                )
            }
    )

    private fun permissionRequired(): Map<String, Any?> = mapOf(
        "status" to "permission_required",
        "source" to "android_contacts",
        "requiredPermission" to Manifest.permission.READ_CONTACTS,
        "resolution" to null,
        "candidates" to emptyList<Map<String, Any?>>()
    )

    private fun notFound(): Map<String, Any?> = mapOf(
        "status" to "not_found",
        "source" to "android_contacts",
        "resolution" to null,
        "requiredPermission" to Manifest.permission.READ_CONTACTS,
        "candidates" to emptyList<Map<String, Any?>>()
    )

    private fun unavailable(reason: String): Map<String, Any?> = mapOf(
        "status" to "unavailable",
        "source" to "android_contacts",
        "resolution" to null,
        "reason" to reason,
        "requiredPermission" to Manifest.permission.READ_CONTACTS,
        "candidates" to emptyList<Map<String, Any?>>()
    )

    private fun normalizeName(value: String): String =
        value.trim().lowercase(Locale.ROOT).replace(Regex("\\s+"), " ")

    private fun normalizePhoneNumber(value: String): String {
        val normalized = PhoneNumberUtils.normalizeNumber(value).trim()
        return if (normalized.startsWith("00") && normalized.length > 2) {
            "+${normalized.substring(2)}"
        } else {
            normalized
        }
    }

    private fun isSupportedRecipient(value: String): Boolean =
        RECIPIENT_PATTERN.matches(value) && value.count(Char::isDigit) >= 3

    private fun typePriority(type: Int): Int = when (type) {
        ContactsContract.CommonDataKinds.Phone.TYPE_MOBILE -> 3
        ContactsContract.CommonDataKinds.Phone.TYPE_MAIN -> 2
        ContactsContract.CommonDataKinds.Phone.TYPE_WORK_MOBILE -> 2
        else -> 1
    }
}

package com.banataosystems.pandora_mobile

import java.util.Locale

internal data class PandoraOemAdapterPolicy(
    val adapterId: String,
    val family: String,
    val autostartManagement: String
)

internal interface PandoraOemFamilyAdapter {
    val policy: PandoraOemAdapterPolicy

    fun matches(manufacturer: String, brand: String): Boolean
}

private abstract class AliasOemFamilyAdapter(
    final override val policy: PandoraOemAdapterPolicy,
    aliases: Set<String>
) : PandoraOemFamilyAdapter {
    private val normalizedAliases = aliases.mapTo(mutableSetOf()) {
        it.lowercase(Locale.ROOT)
    }

    final override fun matches(manufacturer: String, brand: String): Boolean =
        manufacturer in normalizedAliases || brand in normalizedAliases
}

private object XiaomiOemFamilyAdapter : AliasOemFamilyAdapter(
    PandoraOemAdapterPolicy(
        adapterId = "xiaomi_public_v1",
        family = "xiaomi",
        autostartManagement = "manual_oem_control"
    ),
    setOf("xiaomi", "redmi", "poco")
)

private object SamsungOemFamilyAdapter : AliasOemFamilyAdapter(
    PandoraOemAdapterPolicy(
        adapterId = "samsung_public_v1",
        family = "samsung",
        autostartManagement = "public_api_unavailable"
    ),
    setOf("samsung")
)

private object PixelOemFamilyAdapter : AliasOemFamilyAdapter(
    PandoraOemAdapterPolicy(
        adapterId = "pixel_public_v1",
        family = "pixel",
        autostartManagement = "public_api_unavailable"
    ),
    setOf("google", "pixel")
)

private object OnePlusOemFamilyAdapter : AliasOemFamilyAdapter(
    PandoraOemAdapterPolicy(
        adapterId = "oneplus_public_v1",
        family = "oneplus",
        autostartManagement = "public_api_unavailable"
    ),
    setOf("oneplus")
)

internal object PandoraOemAdapterRegistry {
    private val adapters: List<PandoraOemFamilyAdapter> = listOf(
        XiaomiOemFamilyAdapter,
        SamsungOemFamilyAdapter,
        PixelOemFamilyAdapter,
        OnePlusOemFamilyAdapter
    )

    private val genericPolicy = PandoraOemAdapterPolicy(
        adapterId = "android_generic_public_v1",
        family = "generic",
        autostartManagement = "public_api_unavailable"
    )

    fun resolve(manufacturer: String, brand: String): PandoraOemAdapterPolicy {
        val normalizedManufacturer = manufacturer.lowercase(Locale.ROOT)
        val normalizedBrand = brand.lowercase(Locale.ROOT)
        return adapters.firstOrNull {
            it.matches(normalizedManufacturer, normalizedBrand)
        }?.policy ?: genericPolicy
    }
}

package fr.eiter.plexibeer

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.RequestBody.Companion.toRequestBody

/** Beerquest state — enabled=false si RPG off / non autorisé. */
suspend fun BeerAPI.rpgMe(): RpgState = withContext(Dispatchers.IO) {
    try {
        val (body, code) = execute(
            requestBuilder("api/rpg/me").get().build(),
            allowUnauthorizedBody = true
        )
        if (code !in 200..299) return@withContext RpgState(enabled = false)
        gson.fromJson(body, RpgState::class.java) ?: RpgState(enabled = false)
    } catch (_: Exception) {
        RpgState(enabled = false)
    }
}

suspend fun BeerAPI.rpgSetClass(classKey: String): Boolean = withContext(Dispatchers.IO) {
    try {
        val json = gson.toJson(mapOf("class" to classKey))
        val (body, code) = execute(
            requestBuilder("api/rpg/class").post(json.toRequestBody(BeerAPI.JSON)).build()
        )
        code in 200..299 && (gson.fromJson(body, OkResponse::class.java)?.ok == true)
    } catch (_: Exception) {
        false
    }
}

suspend fun BeerAPI.rpgIntroSeen(): Boolean = withContext(Dispatchers.IO) {
    try {
        val (_, code) = execute(
            requestBuilder("api/rpg/intro-seen")
                .post("{}".toRequestBody(BeerAPI.JSON))
                .build()
        )
        code in 200..299
    } catch (_: Exception) {
        false
    }
}

suspend fun BeerAPI.adminRpgPlayers(): List<RpgAdminPlayer> = withContext(Dispatchers.IO) {
    try {
        val (body, code) = execute(requestBuilder("api/admin/rpg/players").get().build())
        if (code !in 200..299) return@withContext emptyList()
        gson.fromJson(body, RpgAdminPlayersResponse::class.java)?.players.orEmpty()
    } catch (_: Exception) {
        emptyList()
    }
}

/** Liste joueurs + flags RPG (pour les toggles admin). */
suspend fun BeerAPI.adminRpgPlayersBundle(): RpgAdminPlayersResponse = withContext(Dispatchers.IO) {
    try {
        val (body, code) = execute(requestBuilder("api/admin/rpg/players").get().build())
        if (code !in 200..299) return@withContext RpgAdminPlayersResponse()
        gson.fromJson(body, RpgAdminPlayersResponse::class.java) ?: RpgAdminPlayersResponse()
    } catch (_: Exception) {
        RpgAdminPlayersResponse()
    }
}

suspend fun BeerAPI.adminRpgGetSettings(): RpgAdminFlags? = withContext(Dispatchers.IO) {
    try {
        val (body, code) = execute(requestBuilder("api/admin/rpg/settings").get().build())
        if (code !in 200..299) return@withContext null
        gson.fromJson(body, RpgAdminSettingsResponse::class.java)?.flags
    } catch (_: Exception) {
        null
    }
}

suspend fun BeerAPI.adminRpgPatchSettings(payload: Map<String, Any?>): RpgAdminFlags? =
    withContext(Dispatchers.IO) {
        try {
            val json = gson.toJson(payload)
            val (body, code) = execute(
                requestBuilder("api/admin/rpg/settings")
                    .patch(json.toRequestBody(BeerAPI.JSON))
                    .build()
            )
            if (code !in 200..299) return@withContext null
            gson.fromJson(body, RpgAdminSettingsResponse::class.java)?.flags
        } catch (_: Exception) {
            null
        }
    }

/**
 * @param allowed true=force ON, false=force OFF, null=auto (défaut allowlist/env)
 * Renvoie le détail complet à jour (le backend lève aussi la quarantaine si ON/Auto).
 */
suspend fun BeerAPI.adminRpgSetUserAllowed(username: String, allowed: Boolean?): RpgAdminPlayerDetail? =
    withContext(Dispatchers.IO) {
        try {
            val enc = java.net.URLEncoder.encode(username, "UTF-8")
            // null JSON explicite
            val json = if (allowed == null) {
                """{"allowed":null}"""
            } else {
                gson.toJson(mapOf("allowed" to allowed))
            }
            val (body, code) = execute(
                requestBuilder("api/admin/rpg/settings/users/$enc")
                    .put(json.toRequestBody(BeerAPI.JSON))
                    .build()
            )
            if (code !in 200..299) return@withContext null
            gson.fromJson(body, RpgAdminPlayerDetail::class.java)
        } catch (_: Exception) {
            null
        }
    }

suspend fun BeerAPI.adminRpgAdjustXp(username: String, delta: Int): RpgAdminPlayerDetail? = withContext(Dispatchers.IO) {
    try {
        val json = gson.toJson(mapOf("delta" to delta))
        val enc = java.net.URLEncoder.encode(username, "UTF-8")
        val (body, code) = execute(
            requestBuilder("api/admin/rpg/players/$enc/xp").post(json.toRequestBody(BeerAPI.JSON)).build()
        )
        if (code !in 200..299) return@withContext null
        gson.fromJson(body, RpgAdminPlayerDetail::class.java)
    } catch (_: Exception) {
        null
    }
}

suspend fun BeerAPI.adminRpgResetDaily(username: String): RpgAdminPlayerDetail? = withContext(Dispatchers.IO) {
    try {
        val enc = java.net.URLEncoder.encode(username, "UTF-8")
        val (body, code) = execute(
            requestBuilder("api/admin/rpg/players/$enc/reset-daily")
                .post(ByteArray(0).toRequestBody())
                .build()
        )
        if (code !in 200..299) return@withContext null
        gson.fromJson(body, RpgAdminPlayerDetail::class.java)
    } catch (_: Exception) {
        null
    }
}

/** GET détail complet d'un joueur (profil, badges, quêtes, événements, atlas…). */
suspend fun BeerAPI.adminRpgPlayer(username: String): RpgAdminPlayerDetail? = withContext(Dispatchers.IO) {
    try {
        val enc = java.net.URLEncoder.encode(username, "UTF-8")
        val (body, code) = execute(requestBuilder("api/admin/rpg/players/$enc").get().build())
        if (code !in 200..299) return@withContext null
        gson.fromJson(body, RpgAdminPlayerDetail::class.java)
    } catch (_: Exception) {
        null
    }
}

suspend fun BeerAPI.adminRpgGrantBadge(username: String, badgeKey: String): RpgAdminBadgeActionResponse? =
    withContext(Dispatchers.IO) {
        try {
            val enc = java.net.URLEncoder.encode(username, "UTF-8")
            val json = gson.toJson(mapOf("badge_key" to badgeKey))
            val (body, code) = execute(
                requestBuilder("api/admin/rpg/players/$enc/badges").post(json.toRequestBody(BeerAPI.JSON)).build()
            )
            if (code !in 200..299) return@withContext null
            gson.fromJson(body, RpgAdminBadgeActionResponse::class.java)
        } catch (_: Exception) {
            null
        }
    }

suspend fun BeerAPI.adminRpgRevokeBadge(username: String, badgeKey: String): RpgAdminBadgeActionResponse? =
    withContext(Dispatchers.IO) {
        try {
            val encU = java.net.URLEncoder.encode(username, "UTF-8")
            val encB = java.net.URLEncoder.encode(badgeKey, "UTF-8")
            val (body, code) = execute(
                requestBuilder("api/admin/rpg/players/$encU/badges/$encB").delete().build()
            )
            if (code !in 200..299) return@withContext null
            gson.fromJson(body, RpgAdminBadgeActionResponse::class.java)
        } catch (_: Exception) {
            null
        }
    }

/** Efface tout le profil RPG (niveau/XP/badges/quêtes/historique) — garde le carnet de dégustations. */
suspend fun BeerAPI.adminRpgWipePlayer(username: String): Boolean = withContext(Dispatchers.IO) {
    try {
        val enc = java.net.URLEncoder.encode(username, "UTF-8")
        val (_, code) = execute(
            requestBuilder("api/admin/rpg/players/$enc/wipe").post(ByteArray(0).toRequestBody()).build()
        )
        code in 200..299
    } catch (_: Exception) {
        false
    }
}

/** Lève la quarantaine anti-triche (audit + override allowed → auto). */
suspend fun BeerAPI.adminRpgUnquarantine(username: String): RpgAdminPlayerDetail? = withContext(Dispatchers.IO) {
    try {
        val enc = java.net.URLEncoder.encode(username, "UTF-8")
        val (body, code) = execute(
            requestBuilder("api/admin/rpg/players/$enc/unquarantine").post(ByteArray(0).toRequestBody()).build()
        )
        if (code !in 200..299) return@withContext null
        gson.fromJson(body, RpgAdminPlayerDetail::class.java)
    } catch (_: Exception) {
        null
    }
}

suspend fun BeerAPI.adminRpgPatchPlayer(username: String, payload: Map<String, Any?>): RpgAdminPlayerDetail? =
    withContext(Dispatchers.IO) {
        try {
            val enc = java.net.URLEncoder.encode(username, "UTF-8")
            val json = gson.toJson(payload)
            val (body, code) = execute(
                requestBuilder("api/admin/rpg/players/$enc")
                    .patch(json.toRequestBody(BeerAPI.JSON))
                    .build()
            )
            if (code !in 200..299) return@withContext null
            gson.fromJson(body, RpgAdminPlayerDetail::class.java)
        } catch (_: Exception) {
            null
        }
    }

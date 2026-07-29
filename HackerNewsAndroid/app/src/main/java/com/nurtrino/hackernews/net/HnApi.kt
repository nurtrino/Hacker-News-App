package com.nurtrino.hackernews.net

import com.nurtrino.hackernews.model.Feed
import com.nurtrino.hackernews.model.HnUser
import com.nurtrino.hackernews.model.Item
import com.nurtrino.hackernews.model.ItemKind
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.util.Collections

/**
 * Client for the official Firebase Hacker News API.
 *
 * Items are memoised in-process, because a 500-comment thread would otherwise
 * re-request the same parents on every collapse/expand round trip.
 */
object HnApi {
    private const val BASE = "https://hacker-news.firebaseio.com/v0"

    /** HN's CDN is happy with far more; this just keeps the socket pool sane. */
    private val gate = Semaphore(12)

    private val cache: MutableMap<Int, Item> =
        Collections.synchronizedMap(mutableMapOf<Int, Item>())

    suspend fun ids(feed: Feed, forceRefresh: Boolean = false): List<Int> {
        val body = Http.getString("$BASE/${feed.endpoint}.json", forceRefresh)
        if (isNull(body)) return emptyList()
        return runCatching {
            Http.json.parseToJsonElement(body).jsonArray.mapNotNull { it.jsonPrimitive.intOrNull }
        }.getOrDefault(emptyList())
    }

    suspend fun item(id: Int, forceRefresh: Boolean = false): Item? {
        if (!forceRefresh) cache[id]?.let { return it }
        val body = runCatching { Http.getString("$BASE/item/$id.json", forceRefresh) }.getOrNull()
            ?: return null
        val parsed = parseItem(body) ?: return null
        cache[id] = parsed
        return parsed
    }

    /**
     * Fetches many items concurrently, returns them in the requested order and
     * drops any that failed or were deleted upstream.
     */
    suspend fun items(ids: List<Int>, forceRefresh: Boolean = false): List<Item> {
        if (ids.isEmpty()) return emptyList()
        return coroutineScope {
            val jobs: List<Deferred<Item?>> = ids.map { id ->
                async { gate.withPermit { item(id, forceRefresh) } }
            }
            jobs.mapNotNull { it.await() }
        }
    }

    suspend fun user(name: String): HnUser? {
        val encoded = java.net.URLEncoder.encode(name, "UTF-8")
        val body = Http.getString("$BASE/user/$encoded.json")
        if (isNull(body)) return null
        val obj = runCatching { Http.json.parseToJsonElement(body) as? JsonObject }.getOrNull()
            ?: return null
        return HnUser(
            id = obj.str("id") ?: name,
            created = obj.long("created"),
            karma = obj.int("karma") ?: 0,
            about = obj.str("about"),
        )
    }

    fun clearCache() {
        cache.clear()
        Http.clearCache()
    }

    private fun isNull(body: String): Boolean {
        val trimmed = body.trim()
        return trimmed.isEmpty() || trimmed == "null"
    }

    private fun parseItem(body: String): Item? {
        if (isNull(body)) return null
        val obj = runCatching { Http.json.parseToJsonElement(body) as? JsonObject }.getOrNull()
            ?: return null
        val id = obj.int("id") ?: return null
        return Item(
            id = id,
            kind = ItemKind.parse(obj.str("type")),
            deleted = obj.bool("deleted") ?: false,
            dead = obj.bool("dead") ?: false,
            by = obj.str("by"),
            time = obj.long("time"),
            text = obj.str("text"),
            parent = obj.int("parent"),
            kids = obj.intList("kids"),
            url = obj.str("url"),
            score = obj.int("score"),
            title = obj.str("title"),
            descendants = obj.int("descendants"),
        )
    }
}

// Forgiving accessors: a null or wrongly-typed field should never take down
// the whole item.

internal fun JsonObject.prim(key: String): JsonPrimitive? =
    (this[key] as? JsonPrimitive)?.takeIf { it.contentOrNull != null }

internal fun JsonObject.str(key: String): String? = prim(key)?.contentOrNull

internal fun JsonObject.int(key: String): Int? = prim(key)?.intOrNull

internal fun JsonObject.long(key: String): Long? = prim(key)?.longOrNull

internal fun JsonObject.bool(key: String): Boolean? = prim(key)?.booleanOrNull

internal fun JsonObject.intList(key: String): List<Int> =
    runCatching {
        (this[key] as? kotlinx.serialization.json.JsonArray)
            ?.mapNotNull { (it as? JsonPrimitive)?.intOrNull }
            ?: emptyList()
    }.getOrDefault(emptyList())

internal fun JsonObject.strList(key: String): List<String> =
    runCatching {
        (this[key] as? kotlinx.serialization.json.JsonArray)
            ?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull }
            ?: emptyList()
    }.getOrDefault(emptyList())

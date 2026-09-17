package com.nurtrino.hackernews.net

import com.nurtrino.hackernews.model.CommentNode
import com.nurtrino.hackernews.model.Forum
import com.nurtrino.hackernews.model.LobstersFeed
import com.nurtrino.hackernews.model.LobstersHtml
import com.nurtrino.hackernews.model.LobstersId
import com.nurtrino.hackernews.model.LobstersStory
import com.nurtrino.hackernews.model.withDescendantCounts
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import java.net.URLEncoder
import java.time.Instant
import java.time.OffsetDateTime

/**
 * Client for lobste.rs's JSON endpoints.
 *
 * Lobsters has no separate API host: every HTML page has a `.json` twin, and
 * a story's JSON carries its whole comment tree, already thread-sorted.
 */
object LobstersApi {
    private const val BASE = "https://lobste.rs"

    /** Lobsters asks automated clients to identify themselves. */
    private val headers = mapOf(
        "User-Agent" to "HackerNewsApp/1.0 (+https://github.com/nurtrino/Hacker-News-App)",
        "Accept" to "application/json",
    )

    /** One page (about 25 stories) of a feed. Empty means the list ran out. */
    suspend fun stories(feed: LobstersFeed, page: Int = 1, forceRefresh: Boolean = false): List<LobstersStory> {
        val body = Http.getString(BASE + feed.path(page), forceRefresh, headers)
        val array = runCatching { Http.json.parseToJsonElement(body) as? JsonArray }.getOrNull()
            ?: return emptyList()
        return array.mapNotNull { parseStory(it as? JsonObject) }
    }

    /** The story record plus its flattened discussion, in one request. */
    suspend fun thread(shortId: String, forceRefresh: Boolean = false): Pair<LobstersStory?, List<CommentNode>> {
        val encoded = URLEncoder.encode(shortId, "UTF-8")
        val body = Http.getString("$BASE/s/$encoded.json", forceRefresh, headers)
        val root = runCatching { Http.json.parseToJsonElement(body) as? JsonObject }.getOrNull()
            ?: return null to emptyList()
        return parseStory(root) to flatten(root["comments"] as? JsonArray)
    }

    // Parsing

    private fun parseStory(obj: JsonObject?): LobstersStory? {
        if (obj == null) return null
        val shortId = obj.str("short_id")?.takeIf { it.isNotEmpty() } ?: return null
        return LobstersStory(
            shortId = shortId,
            title = obj.str("title") ?: "(untitled)",
            url = obj.str("url")?.takeIf { it.isNotEmpty() },
            score = obj.int("score") ?: 0,
            commentCount = obj.int("comment_count") ?: 0,
            descriptionHtml = obj.str("description")?.takeIf { it.isNotEmpty() },
            commentsUrl = obj.str("comments_url"),
            submitter = username(obj["submitter_user"]),
            tags = obj.strList("tags"),
            createdAt = epochSeconds(obj.str("created_at")),
        )
    }

    /**
     * Lobsters already returns comments thread-sorted, each with its parent
     * id, so depth comes from the parent's depth rather than a tree walk.
     */
    private fun flatten(comments: JsonArray?): List<CommentNode> {
        if (comments == null) return emptyList()
        val depthById = HashMap<String, Int>()
        val result = ArrayList<CommentNode>(comments.size)

        for (element in comments) {
            val obj = element as? JsonObject ?: continue
            val shortId = obj.str("short_id")?.takeIf { it.isNotEmpty() } ?: continue
            val parentId = obj.str("parent_comment")?.takeIf { it.isNotEmpty() }

            val parentDepth = parentId?.let { depthById[it] }
            val depth = when {
                parentDepth != null -> parentDepth + 1
                obj.int("depth") != null -> maxOf(0, obj.int("depth")!!)
                obj.int("indent_level") != null -> maxOf(0, obj.int("indent_level")!! - 1)
                else -> 0
            }
            depthById[shortId] = depth

            val html = obj.str("comment").orEmpty()
            val author = username(obj["commenting_user"])
            val isDeleted = (obj.bool("is_deleted") ?: false) || (html.isEmpty() && author == null)

            result.add(
                CommentNode(
                    id = LobstersId.number(shortId),
                    parent = parentId?.let { LobstersId.number(it) },
                    author = author,
                    html = LobstersHtml.normalize(html),
                    time = epochSeconds(obj.str("created_at")),
                    depth = depth,
                    isDeleted = isDeleted,
                    forum = Forum.LOBSTERS,
                    permalink = obj.str("url")?.takeIf { it.isNotEmpty() } ?: "https://lobste.rs/c/$shortId",
                )
            )
        }

        // A deleted comment with no surviving replies adds nothing; one that
        // still has replies stays as a placeholder so the thread keeps shape.
        val kept = ArrayList<CommentNode>(result.size)
        for (index in result.indices) {
            val node = result[index]
            val hasReplies = index + 1 < result.size && result[index + 1].depth > node.depth
            if (node.isDeleted && !hasReplies) continue
            kept.add(node)
        }
        return kept.withDescendantCounts()
    }

    /** Newer API versions send a bare username; older ones an object. */
    private fun username(element: JsonElement?): String? = when (element) {
        is JsonObject -> element.str("username")?.takeIf { it.isNotEmpty() }
        is JsonPrimitive -> element.contentOrNull?.takeIf { it.isNotEmpty() }
        else -> null
    }

    /** `2024-05-01T10:23:45.000-05:00`, with or without the fraction. */
    private fun epochSeconds(text: String?): Long? {
        if (text.isNullOrEmpty()) return null
        return runCatching { OffsetDateTime.parse(text).toEpochSecond() }.getOrNull()
            ?: runCatching { Instant.parse(text).epochSecond }.getOrNull()
    }
}

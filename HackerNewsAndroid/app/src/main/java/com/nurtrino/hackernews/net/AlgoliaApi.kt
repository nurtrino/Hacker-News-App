package com.nurtrino.hackernews.net

import com.nurtrino.hackernews.model.CommentNode
import com.nurtrino.hackernews.model.Item
import com.nurtrino.hackernews.model.ItemKind
import com.nurtrino.hackernews.model.withDescendantCounts
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import java.net.URLEncoder

enum class SearchScope(val title: String, val tag: String) {
    STORIES("Stories", "story"),
    COMMENTS("Comments", "comment"),
    ASK("Ask HN", "ask_hn"),
    SHOW("Show HN", "show_hn"),
}

enum class SearchSort(val title: String, val path: String) {
    RELEVANCE("Relevance", "search"),
    DATE("Newest", "search_by_date"),
}

enum class SearchPeriod(val title: String, val windowSeconds: Long?) {
    ALL_TIME("All time", null),
    DAY("Past 24h", 86_400),
    WEEK("Past week", 7 * 86_400),
    MONTH("Past month", 30 * 86_400),
    YEAR("Past year", 365 * 86_400),
}

data class SearchResults(
    val items: List<Item> = emptyList(),
    val page: Int = 0,
    val totalPages: Int = 0,
    val totalHits: Int = 0,
) {
    val hasMore: Boolean get() = page + 1 < totalPages
}

/**
 * Client for HN Search (the Algolia-backed index).
 *
 * Two jobs: full-text search, and pulling an entire comment tree in a single
 * request — which is why threads open fast. Walking the Firebase API would
 * need one request per comment.
 */
object AlgoliaApi {
    private const val BASE = "https://hn.algolia.com/api/v1"

    suspend fun search(
        query: String,
        scope: SearchScope,
        sort: SearchSort,
        period: SearchPeriod,
        page: Int = 0,
        hitsPerPage: Int = 30,
        nowSeconds: Long = System.currentTimeMillis() / 1000,
    ): SearchResults {
        val params = buildString {
            append("query=").append(encode(query))
            append("&tags=").append(encode(scope.tag))
            append("&page=").append(page)
            append("&hitsPerPage=").append(hitsPerPage)
            period.windowSeconds?.let {
                append("&numericFilters=").append(encode("created_at_i>${nowSeconds - it}"))
            }
        }
        return parseSearch(Http.getString("$BASE/${sort.path}?$params"))
    }

    /** Stories or comments submitted by one account, newest first. */
    suspend fun submissions(author: String, scope: SearchScope, page: Int = 0): SearchResults {
        val params = "tags=${encode("author_$author,${scope.tag}")}&page=$page&hitsPerPage=30"
        return parseSearch(Http.getString("$BASE/search_by_date?$params"))
    }

    /** The whole comment tree for a story, already flattened into reading order. */
    suspend fun thread(id: Int): Pair<Item?, List<CommentNode>> {
        val body = Http.getString("$BASE/items/$id")
        val root = Http.json.parseToJsonElement(body) as? JsonObject
            ?: return null to emptyList()

        val flat = mutableListOf<CommentNode>()
        flatten(root["children"] as? JsonArray, 0, flat)
        return rootAsStory(root) to flat.withDescendantCounts()
    }

    private fun flatten(children: JsonArray?, depth: Int, out: MutableList<CommentNode>) {
        if (children == null) return
        for (element in children) {
            val node = element as? JsonObject ?: continue
            val nodeId = node.int("id") ?: continue
            val text = node.str("text").orEmpty()
            val author = node.str("author")
            val kids = node["children"] as? JsonArray
            val isDeleted = author == null && text.isEmpty()

            // A deleted comment with no surviving replies adds nothing; one
            // that still has replies stays as a placeholder so the thread
            // keeps its shape.
            if (isDeleted && (kids == null || kids.isEmpty())) continue

            out.add(
                CommentNode(
                    id = nodeId,
                    parent = node.int("parent_id"),
                    author = author,
                    html = text,
                    time = node.long("created_at_i"),
                    depth = depth,
                    isDeleted = isDeleted,
                )
            )
            flatten(kids, depth + 1, out)
        }
    }

    /**
     * The root of a thread response doubles as the story record, which lets a
     * deep link open a discussion without a second round trip.
     */
    private fun rootAsStory(root: JsonObject): Item? {
        val id = root.int("id") ?: return null
        val type = root.str("type")
        if (type == "comment") return null
        return Item(
            id = id,
            kind = ItemKind.parse(type),
            by = root.str("author"),
            time = root.long("created_at_i"),
            text = root.str("text"),
            url = root.str("url"),
            score = root.int("points"),
            title = root.str("title"),
        )
    }

    private fun parseSearch(body: String): SearchResults {
        val obj = runCatching { Http.json.parseToJsonElement(body) as? JsonObject }.getOrNull()
            ?: return SearchResults()
        val hits = (obj["hits"] as? JsonArray).orEmpty()
        return SearchResults(
            items = hits.mapNotNull { hitToItem(it as? JsonObject) },
            page = obj.int("page") ?: 0,
            totalPages = obj.int("nbPages") ?: 0,
            totalHits = obj.int("nbHits") ?: 0,
        )
    }

    private fun hitToItem(hit: JsonObject?): Item? {
        if (hit == null) return null
        val id = hit.str("objectID")?.toIntOrNull() ?: return null
        val tags = hit.strList("_tags")
        val kind = when {
            tags.contains("comment") -> ItemKind.COMMENT
            tags.contains("job") -> ItemKind.JOB
            else -> ItemKind.STORY
        }
        return Item(
            id = id,
            kind = kind,
            by = hit.str("author"),
            time = hit.long("created_at_i"),
            text = hit.str("story_text") ?: hit.str("comment_text"),
            parent = hit.int("parent_id"),
            url = hit.str("url"),
            score = hit.int("points"),
            title = hit.str("title"),
            descendants = hit.int("num_comments"),
            storyTitle = hit.str("story_title"),
            storyId = hit.int("story_id"),
        )
    }

    private fun encode(value: String): String = URLEncoder.encode(value, "UTF-8")
}

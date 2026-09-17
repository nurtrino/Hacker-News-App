package com.nurtrino.hackernews.model

import kotlinx.serialization.Serializable

/** The kind of object the HN API returned. Unknown values fall back to [UNKNOWN]. */
enum class ItemKind {
    STORY, COMMENT, JOB, POLL, POLLOPT, UNKNOWN;

    companion object {
        fun parse(raw: String?): ItemKind = when (raw) {
            null, "story" -> STORY
            "comment" -> COMMENT
            "job" -> JOB
            "poll" -> POLL
            "pollopt" -> POLLOPT
            else -> UNKNOWN
        }
    }
}

/**
 * A single Hacker News object (story, comment, job, poll).
 *
 * Every field past the id is optional: the API omits keys entirely for missing
 * values and occasionally sends null for keys it does include.
 */
@Serializable
data class Item(
    val id: Int,
    val kind: ItemKind = ItemKind.STORY,
    val deleted: Boolean = false,
    val dead: Boolean = false,
    val by: String? = null,
    /** Epoch seconds. */
    val time: Long? = null,
    val text: String? = null,
    val parent: Int? = null,
    val kids: List<Int> = emptyList(),
    val url: String? = null,
    val score: Int? = null,
    val title: String? = null,
    val descendants: Int? = null,
    /** Set when the item came from the search index, which knows its parent. */
    val storyTitle: String? = null,
    val storyId: Int? = null,
) {
    val displayTitle: String
        get() = title?.takeIf { it.isNotEmpty() }
            ?: storyTitle?.takeIf { it.isNotEmpty() }
            ?: "(untitled)"

    val author: String get() = by ?: "unknown"

    /** The external article link, if this story points off-site. */
    val link: String?
        get() = url?.takeIf { it.isNotBlank() && (it.startsWith("http://") || it.startsWith("https://")) }

    val hnUrl: String get() = "https://news.ycombinator.com/item?id=$id"

    /** Article for link posts, discussion for text posts. */
    val primaryUrl: String get() = link ?: hnUrl

    /** `example.com` for `https://www.example.com/a/b`. */
    val host: String? get() = hostOf(link)

    val commentCount: Int get() = descendants ?: 0

    val isTextPost: Boolean get() = link == null

    /** Single character for the row's monogram badge. */
    val sourceLabel: String
        get() {
            host?.firstOrNull()?.let { return it.uppercase() }
            if (kind == ItemKind.JOB) return "J"
            val lowered = displayTitle.lowercase()
            if (lowered.startsWith("ask hn")) return "A"
            if (lowered.startsWith("show hn")) return "S"
            return "Y"
        }
}

/** `example.com` for `https://www.example.com/a/b`; null when there's no usable link. */
fun hostOf(link: String?): String? {
    val raw = link ?: return null
    val afterScheme = raw.substringAfter("://", "")
    if (afterScheme.isEmpty()) return null
    val authority = afterScheme.substringBefore('/').substringBefore('?').substringBefore('#')
    val hostOnly = authority.substringAfterLast('@').substringBefore(':')
    if (hostOnly.isEmpty()) return null
    return hostOnly.removePrefix("www.")
}

/** The sites the app reads from. */
enum class Forum(val title: String) {
    HACKER_NEWS("Hacker News"),
    LOBSTERS("Lobsters");

    /** The author's profile page on this site. */
    fun profileUrl(username: String): String {
        val encoded = java.net.URLEncoder.encode(username, "UTF-8")
        return when (this) {
            HACKER_NEWS -> "https://news.ycombinator.com/user?id=$encoded"
            LOBSTERS -> "https://lobste.rs/~$encoded"
        }
    }
}

/** A Hacker News account profile. */
@Serializable
data class HnUser(
    val id: String,
    val created: Long? = null,
    val karma: Int = 0,
    val about: String? = null,
)

/**
 * One comment, already flattened out of the reply tree.
 *
 * Threads are held as a flat, depth-tagged list in reading order, which makes
 * collapsing a subtree a matter of skipping the run of following nodes whose
 * depth is greater than the collapsed one's.
 */
data class CommentNode(
    val id: Int,
    val parent: Int?,
    val author: String?,
    /** Raw comment HTML — parsed lazily and memoised. */
    val html: String,
    val time: Long?,
    val depth: Int,
    val isDeleted: Boolean,
    val descendantCount: Int = 0,
    /** Which site the comment came from; decides where "open on…" links go. */
    val forum: Forum = Forum.HACKER_NEWS,
    /** The comment's own page, for sites whose URLs aren't derivable from [id]. */
    val permalink: String? = null,
) {
    val isTopLevel: Boolean get() = depth == 0

    /** The comment's web page. */
    val webUrl: String get() = permalink ?: "https://news.ycombinator.com/item?id=$id"

    /** The author's profile page on the comment's site. */
    val authorUrl: String? get() = author?.let { forum.profileUrl(it) }
}

/** Fills in [CommentNode.descendantCount] in one pass using a stack of open ancestors. */
fun List<CommentNode>.withDescendantCounts(): List<CommentNode> {
    val counts = IntArray(size)
    val ancestors = ArrayDeque<Int>()
    for (i in indices) {
        while (ancestors.isNotEmpty() && this[ancestors.last()].depth >= this[i].depth) {
            ancestors.removeLast()
        }
        for (index in ancestors) counts[index]++
        ancestors.addLast(i)
    }
    return mapIndexed { index, node -> node.copy(descendantCount = counts[index]) }
}

/** The six story lists the Firebase API exposes. */
enum class Feed(val title: String, val longTitle: String, val endpoint: String, val showsRank: Boolean) {
    TOP("Top", "Top Stories", "topstories", true),
    NEW("New", "New Stories", "newstories", false),
    BEST("Best", "Best Stories", "beststories", true),
    ASK("Ask HN", "Ask HN", "askstories", false),
    SHOW("Show HN", "Show HN", "showstories", false),
    JOB("Jobs", "Jobs", "jobstories", false),
}

/** Progress of any screen that loads from the network. */
sealed interface LoadPhase {
    data object Idle : LoadPhase
    data object Loading : LoadPhase
    data object Loaded : LoadPhase
    data class Failed(val message: String) : LoadPhase
}

package com.nurtrino.hackernews.model

/** The story lists lobste.rs exposes as JSON. */
enum class LobstersFeed(val title: String, val longTitle: String, val webUrl: String) {
    ACTIVE("Active", "Lobsters · Active", "https://lobste.rs/active"),
    HOTTEST("Hottest", "Lobsters · Hottest", "https://lobste.rs"),
    NEWEST("Newest", "Lobsters · Newest", "https://lobste.rs/newest");

    /**
     * Path (without host) of the JSON list for a 1-based page. The first page
     * has its own short route; later pages use the `/page/N` form.
     */
    fun path(page: Int): String = when (this) {
        ACTIVE -> if (page <= 1) "/active.json" else "/active/page/$page.json"
        NEWEST -> if (page <= 1) "/newest.json" else "/newest/page/$page.json"
        HOTTEST -> if (page <= 1) "/hottest.json" else "/page/$page.json"
    }
}

/** One lobste.rs submission, as returned by the list and story endpoints. */
data class LobstersStory(
    /** Lobsters' own identifier, e.g. `lzgsvb`. */
    val shortId: String,
    val title: String,
    /** External link; null for text posts. */
    val url: String? = null,
    val score: Int = 0,
    val commentCount: Int = 0,
    /** Text-post body as HTML. */
    val descriptionHtml: String? = null,
    /** The discussion page on lobste.rs (with the title slug). */
    val commentsUrl: String? = null,
    val submitter: String? = null,
    val tags: List<String> = emptyList(),
    /** Epoch seconds. */
    val createdAt: Long? = null,
) {
    /** Stable integer for read-state, which is keyed by Int because HN ids are. */
    val numericId: Int get() = LobstersId.number(shortId)

    val author: String get() = submitter ?: "unknown"

    /** The external article link, if this story points off-site. */
    val link: String?
        get() = url?.takeIf { it.isNotBlank() && (it.startsWith("http://") || it.startsWith("https://")) }

    /** The canonical discussion page. */
    val lobstersUrl: String
        get() = commentsUrl?.takeIf { it.isNotBlank() } ?: "https://lobste.rs/s/$shortId"

    /** Article for link posts, discussion for text posts. */
    val primaryUrl: String get() = link ?: lobstersUrl

    val host: String? get() = hostOf(link)

    val isTextPost: Boolean get() = link == null

    /** Single character for the row's monogram badge. */
    val sourceLabel: String get() = host?.firstOrNull()?.uppercase() ?: "L"
}

/** Lobsters ids are short strings; the rest of the app keys things on Int. */
object LobstersId {
    /**
     * FNV-1a, folded to 30 bits with bit 30 forced on, so it stays positive
     * and clear of any Hacker News id in the shared read-state list.
     */
    fun number(shortId: String): Int {
        var hash = 0x811c9dc5.toInt()
        for (byte in shortId.encodeToByteArray()) {
            hash = hash xor (byte.toInt() and 0xff)
            hash *= 0x01000193
        }
        return (hash and 0x3fffffff) or 0x40000000
    }
}

/**
 * Lobsters renders Markdown, so its HTML uses a few block tags HN never
 * emits. Rewrite those into the `<p>`/`<b>`/`<i>` subset the shared parser
 * understands rather than teaching it a second dialect.
 */
object LobstersHtml {
    private val rules: List<Pair<String, String>> = listOf(
        "<blockquote>" to "<p><i>",
        "</blockquote>" to "</i><p>",
        "<li>" to "<p>• ",
        "</li>" to "",
        "<h1>" to "<p><b>", "</h1>" to "</b><p>",
        "<h2>" to "<p><b>", "</h2>" to "</b><p>",
        "<h3>" to "<p><b>", "</h3>" to "</b><p>",
        "<h4>" to "<p><b>", "</h4>" to "</b><p>",
        "<h5>" to "<p><b>", "</h5>" to "</b><p>",
        "<h6>" to "<p><b>", "</h6>" to "</b><p>",
        "<hr>" to "<p>", "<hr/>" to "<p>", "<hr />" to "<p>",
    )

    fun normalize(html: String): String {
        if (!html.contains('<')) return html
        var output = html
        for ((from, to) in rules) output = output.replace(from, to, ignoreCase = true)
        return output
    }
}

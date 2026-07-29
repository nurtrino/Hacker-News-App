package com.nurtrino.hackernews.text

/** A renderable piece of a comment body, before any Compose types get involved. */
sealed interface RichBlock {
    /** Text plus the inline spans that apply to ranges of it. */
    data class Paragraph(val text: String, val spans: List<Span>) : RichBlock

    data class Code(val text: String) : RichBlock
}

data class Span(
    val start: Int,
    val end: Int,
    val italic: Boolean = false,
    val bold: Boolean = false,
    val link: String? = null,
)

/**
 * A small, targeted parser for the HTML subset Hacker News actually emits.
 *
 * HN bodies only ever contain unclosed `<p>`, `<i>`/`<b>`, `<a href>`,
 * `<pre><code>` and character entities. Handing that to `Html.fromHtml` would
 * lose the code blocks and give no control over link handling, so this walks
 * the string directly instead.
 *
 * Deliberately free of Android and Compose imports so it stays unit-testable.
 */
object HnHtml {

    fun parse(html: String): List<RichBlock> {
        if (html.isEmpty()) return emptyList()

        val blocks = mutableListOf<RichBlock>()
        val paragraph = StringBuilder()
        val spans = mutableListOf<Span>()
        val pending = StringBuilder()
        val code = StringBuilder()

        var italicDepth = 0
        var boldDepth = 0
        val linkStack = ArrayDeque<String?>()
        var inPre = false

        fun flushRun() {
            if (pending.isEmpty()) return
            val decoded = decodeEntities(pending.toString())
            pending.setLength(0)
            if (decoded.isEmpty()) return

            val start = paragraph.length
            paragraph.append(decoded)
            val link = linkStack.lastOrNull()
            if (italicDepth > 0 || boldDepth > 0 || link != null) {
                spans.add(
                    Span(
                        start = start,
                        end = paragraph.length,
                        italic = italicDepth > 0,
                        bold = boldDepth > 0,
                        link = link,
                    )
                )
            }
        }

        fun flushParagraph() {
            flushRun()
            val raw = paragraph.toString()
            val leading = raw.indexOfFirst { !it.isWhitespace() }
            if (leading >= 0) {
                val trailing = raw.indexOfLast { !it.isWhitespace() } + 1
                val trimmed = raw.substring(leading, trailing)
                val shifted = spans.mapNotNull { span ->
                    val start = (span.start - leading).coerceIn(0, trimmed.length)
                    val end = (span.end - leading).coerceIn(0, trimmed.length)
                    if (start >= end) null else span.copy(start = start, end = end)
                }
                blocks.add(RichBlock.Paragraph(trimmed, shifted))
            }
            paragraph.setLength(0)
            spans.clear()
        }

        fun flushCode() {
            val text = decodeEntities(code.toString()).trim('\n')
            code.setLength(0)
            if (text.isNotEmpty()) blocks.add(RichBlock.Code(text))
        }

        var index = 0
        while (index < html.length) {
            val character = html[index]
            if (character != '<') {
                if (inPre) code.append(character) else pending.append(character)
                index++
                continue
            }

            // Only a letter or '/' can start a real tag. Anything else is a
            // literal '<' in the prose ("a < b"), and treating it as a tag
            // would swallow everything up to the next '>'.
            val next = html.getOrNull(index + 1)
            if (next == null || !(next.isLetter() || next == '/')) {
                if (inPre) code.append(character) else pending.append(character)
                index++
                continue
            }

            val close = html.indexOf('>', index)
            if (close < 0) {
                // Unterminated tag: the rest is just text.
                pending.append(html, index, html.length)
                break
            }

            val tag = Tag(html.substring(index + 1, close))
            index = close + 1

            when (tag.name) {
                "p" -> if (inPre) code.append('\n') else flushParagraph()
                "br" -> if (inPre) {
                    code.append('\n')
                } else {
                    flushRun()
                    paragraph.append('\n')
                }
                "i", "em" -> {
                    flushRun()
                    italicDepth = maxOf(0, italicDepth + if (tag.isClosing) -1 else 1)
                }
                "b", "strong" -> {
                    flushRun()
                    boldDepth = maxOf(0, boldDepth + if (tag.isClosing) -1 else 1)
                }
                "a" -> {
                    flushRun()
                    if (tag.isClosing) {
                        linkStack.removeLastOrNull()
                    } else if (!tag.isSelfClosing) {
                        linkStack.addLast(sanitizeUrl(tag.attribute("href")))
                    }
                }
                "pre" -> if (tag.isClosing) {
                    inPre = false
                    flushCode()
                } else {
                    flushParagraph()
                    inPre = true
                }
                // Everything else is structural in HN's output; the contents
                // still count, so there's nothing to do but keep reading.
            }
        }

        if (inPre) flushCode()
        flushParagraph()
        return blocks
    }

    /** Tag-free, entity-decoded text — used for sharing, copying and snippets. */
    fun plainText(html: String): String {
        val output = StringBuilder()
        var index = 0
        while (index < html.length) {
            val character = html[index]
            val next = html.getOrNull(index + 1)
            if (character == '<' && next != null && (next.isLetter() || next == '/')) {
                val close = html.indexOf('>', index)
                if (close >= 0) {
                    val name = Tag(html.substring(index + 1, close)).name
                    if (name == "p" || name == "br") output.append('\n')
                    index = close + 1
                    continue
                }
            }
            output.append(character)
            index++
        }
        return decodeEntities(output.toString()).trim()
    }

    /** One-line preview of a comment, for search results and saved rows. */
    fun snippet(html: String, limit: Int = 220): String {
        val text = plainText(html).replace('\n', ' ').replace("  ", " ")
        return if (text.length <= limit) text else text.take(limit).trimEnd() + "…"
    }

    private class Tag(raw: String) {
        val isClosing: Boolean
        val isSelfClosing: Boolean
        val body: String
        val name: String

        init {
            var trimmed = raw.trim()
            isClosing = trimmed.startsWith("/")
            if (isClosing) trimmed = trimmed.substring(1)
            isSelfClosing = trimmed.endsWith("/")
            body = trimmed
            name = trimmed.takeWhile { !it.isWhitespace() && it != '/' }.lowercase()
        }

        /** Value of an attribute, handling quoted and bare forms. */
        fun attribute(key: String): String? {
            val marker = body.indexOf("$key=", ignoreCase = true)
            if (marker < 0) return null
            var rest = body.substring(marker + key.length + 1)
            if (rest.isEmpty()) return null
            val quote = rest[0]
            if (quote == '"' || quote == '\'') {
                rest = rest.substring(1)
                val end = rest.indexOf(quote)
                return if (end < 0) null else rest.substring(0, end)
            }
            return rest.takeWhile { !it.isWhitespace() && it != '>' }
        }
    }

    /**
     * Only http(s) links are followed — anything else in a comment body is
     * either broken or trying to be clever.
     */
    private fun sanitizeUrl(raw: String?): String? {
        val decoded = decodeEntities(raw ?: return null).trim()
        val lowered = decoded.lowercase()
        return if (lowered.startsWith("http://") || lowered.startsWith("https://")) decoded else null
    }

    private val namedEntities = mapOf(
        "amp" to "&", "lt" to "<", "gt" to ">", "quot" to "\"", "apos" to "'",
        "nbsp" to "\u00A0", "hellip" to "…", "mdash" to "—", "ndash" to "–",
        "lsquo" to "‘", "rsquo" to "’", "ldquo" to "“",
        "rdquo" to "”", "times" to "×", "middot" to "·", "deg" to "°",
        "laquo" to "«", "raquo" to "»", "bull" to "•", "dagger" to "†",
        "copy" to "©", "reg" to "®", "trade" to "™", "frac12" to "½",
        "frac14" to "¼", "sup2" to "²", "sup3" to "³", "micro" to "µ",
        "plusmn" to "±", "ne" to "≠", "le" to "≤", "ge" to "≥",
        "rarr" to "→", "larr" to "←", "harr" to "↔", "infin" to "∞",
        "sect" to "§", "para" to "¶", "euro" to "€", "pound" to "£",
        "yen" to "¥", "eacute" to "é", "egrave" to "è", "agrave" to "à",
        "ccedil" to "ç", "uuml" to "ü", "ouml" to "ö", "auml" to "ä",
        "szlig" to "ß", "ntilde" to "ñ",
    )

    fun decodeEntities(input: String): String {
        if (!input.contains('&')) return input

        val output = StringBuilder(input.length)
        var index = 0
        while (index < input.length) {
            val character = input[index]
            if (character != '&') {
                output.append(character)
                index++
                continue
            }

            // Entities are short; anything longer is a literal ampersand.
            val horizon = minOf(index + 12, input.length)
            val semicolon = input.indexOf(';', index).takeIf { it in 0 until horizon }
            if (semicolon == null) {
                output.append(character)
                index++
                continue
            }

            val replacement = entityFor(input.substring(index + 1, semicolon))
            if (replacement != null) {
                output.append(replacement)
                index = semicolon + 1
            } else {
                output.append(character)
                index++
            }
        }
        return output.toString()
    }

    private fun entityFor(body: String): String? {
        if (body.isEmpty()) return null

        if (body.startsWith("#")) {
            val digits = body.substring(1)
            val value = if (digits.startsWith("x") || digits.startsWith("X")) {
                digits.substring(1).toIntOrNull(16)
            } else {
                digits.toIntOrNull()
            } ?: return null
            if (value !in 1..0x10FFFF) return null
            return runCatching { String(Character.toChars(value)) }.getOrNull()
        }

        return namedEntities[body.lowercase()]
    }
}

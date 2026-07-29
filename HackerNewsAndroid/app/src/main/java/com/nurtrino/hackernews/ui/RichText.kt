package com.nurtrino.hackernews.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.ClickableText
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.nurtrino.hackernews.text.HnHtml
import com.nurtrino.hackernews.text.RichBlock

private const val URL_TAG = "url"

/**
 * Renders a Hacker News HTML body: paragraphs with inline links and emphasis,
 * plus horizontally scrollable code blocks.
 *
 * Parsing is memoised per body — threads re-compose constantly while scrolling
 * and collapsing, and re-parsing a long comment every pass is the difference
 * between a smooth list and a stuttery one.
 */
@Composable
fun RichText(
    html: String,
    modifier: Modifier = Modifier,
    style: TextStyle = LocalTextStyle.current,
    color: Color = MaterialTheme.colorScheme.onSurface,
    onLinkClick: (String) -> Unit,
) {
    val blocks = remember(html) { HnHtml.parse(html) }
    val linkColor = MaterialTheme.colorScheme.primary

    Column(modifier = modifier) {
        blocks.forEachIndexed { index, block ->
            when (block) {
                is RichBlock.Paragraph -> {
                    val annotated = remember(block, linkColor) {
                        buildParagraph(block, linkColor)
                    }
                    ClickableText(
                        text = annotated,
                        style = style.merge(TextStyle(color = color)),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = if (index == 0) 0.dp else 10.dp),
                        onClick = { offset ->
                            annotated.getStringAnnotations(URL_TAG, offset, offset)
                                .firstOrNull()
                                ?.let { onLinkClick(it.item) }
                        },
                    )
                }

                is RichBlock.Code -> {
                    Text(
                        text = block.text,
                        style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                        color = color,
                        maxLines = Int.MAX_VALUE,
                        softWrap = false,
                        modifier = Modifier
                            .padding(top = if (index == 0) 0.dp else 10.dp)
                            .fillMaxWidth()
                            .background(
                                MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f),
                                RoundedCornerShape(8.dp),
                            )
                            .horizontalScroll(rememberScrollState())
                            .padding(10.dp),
                    )
                }
            }
        }
    }
}

private fun buildParagraph(block: RichBlock.Paragraph, linkColor: Color): AnnotatedString =
    buildAnnotatedStringCompat(block, linkColor)

private fun buildAnnotatedStringCompat(
    block: RichBlock.Paragraph,
    linkColor: Color,
): AnnotatedString {
    val builder = AnnotatedString.Builder(block.text)
    for (span in block.spans) {
        if (span.start >= span.end || span.end > block.text.length) continue
        builder.addStyle(
            SpanStyle(
                fontStyle = if (span.italic) FontStyle.Italic else null,
                fontWeight = if (span.bold) FontWeight.Bold else null,
                color = if (span.link != null) linkColor else Color.Unspecified,
                textDecoration = if (span.link != null) TextDecoration.Underline else null,
            ),
            span.start,
            span.end,
        )
        if (span.link != null) {
            builder.addStringAnnotation(URL_TAG, span.link, span.start, span.end)
        }
    }
    return builder.toAnnotatedString()
}

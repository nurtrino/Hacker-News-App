package com.nurtrino.hackernews.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.nurtrino.hackernews.model.CommentNode

/** One comment, indented by depth with a coloured rail per level. */
@Composable
fun CommentRow(
    node: CommentNode,
    isCollapsed: Boolean,
    isOriginalPoster: Boolean,
    onToggle: () -> Unit,
    onAuthorClick: (String) -> Unit,
    onLinkClick: (String) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(IntrinsicSize.Min)
            .padding(end = 14.dp, top = 8.dp, bottom = 8.dp),
    ) {
        // One rail per ancestor level, so it's obvious how deep a reply sits.
        val rails = node.depth.coerceAtMost(Metrics.MAX_INDENT_DEPTH)
        Spacer(modifier = Modifier.width(12.dp))
        repeat(rails) { level ->
            Box(
                modifier = Modifier
                    .width(2.dp)
                    .fillMaxHeight()
                    .background(threadColor(level).copy(alpha = 0.55f)),
            )
            Spacer(modifier = Modifier.width(9.dp))
        }

        Column(modifier = Modifier.fillMaxWidth()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    // Only the header toggles the thread — the body has to
                    // stay tappable for the links inside it.
                    .clickable(onClick = onToggle)
                    .padding(vertical = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    node.author ?: "unknown",
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = if (isOriginalPoster) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                    modifier = Modifier.clickable(enabled = node.author != null) {
                        node.author?.let(onAuthorClick)
                    },
                )

                if (isOriginalPoster) {
                    Text(
                        "OP",
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier
                            .background(
                                MaterialTheme.colorScheme.primary.copy(alpha = 0.18f),
                                RoundedCornerShape(4.dp),
                            )
                            .padding(horizontal = 4.dp),
                    )
                }

                Text(
                    shortAge(node.time),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )

                Spacer(modifier = Modifier.weight(1f))

                if (isCollapsed && node.descendantCount > 0) {
                    Text(
                        "+${node.descendantCount}",
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                Icon(
                    if (isCollapsed) Icons.Filled.KeyboardArrowRight else Icons.Filled.KeyboardArrowDown,
                    contentDescription = if (isCollapsed) "Expand thread" else "Collapse thread",
                    modifier = Modifier.size(16.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            if (!isCollapsed) {
                if (node.isDeleted) {
                    Text(
                        "[deleted]",
                        style = MaterialTheme.typography.bodyMedium,
                        fontStyle = FontStyle.Italic,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 4.dp),
                    )
                } else {
                    RichText(
                        html = node.html,
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.padding(top = 4.dp),
                        onLinkClick = onLinkClick,
                    )
                }
            }
        }
    }
}

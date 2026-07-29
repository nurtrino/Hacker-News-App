package com.nurtrino.hackernews.ui

import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.nurtrino.hackernews.data.Library
import com.nurtrino.hackernews.data.Settings
import com.nurtrino.hackernews.model.Item
import com.nurtrino.hackernews.model.ItemKind
import com.nurtrino.hackernews.text.HnHtml

/**
 * One story in a list. Shared by the feeds, search results and saved items so
 * they all read the same way.
 */
@Composable
fun StoryRow(
    item: Item,
    settings: Settings,
    library: Library,
    rank: Int? = null,
    showSnippet: Boolean = false,
    onClick: () -> Unit,
) {
    val context = LocalContext.current
    var menuOpen by remember { mutableStateOf(false) }
    val isRead = library.isRead(item.id)
    val saved = library.isSaved(item.id)

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(onClick = onClick, onLongClick = { menuOpen = true })
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.Top,
    ) {
        if (rank != null) {
            Text(
                rank.toString(),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.widthIn(min = 22.dp).padding(top = 2.dp, end = 10.dp),
            )
        } else if (settings.showSourceBadges) {
            Row(modifier = Modifier.padding(end = 11.dp)) {
                SourceBadge(item.sourceLabel, item.host ?: "ycombinator")
            }
        }

        Column(modifier = Modifier.fillMaxWidth()) {
            Text(
                item.displayTitle,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                color = if (isRead && settings.dimReadStories) {
                    MaterialTheme.colorScheme.onSurfaceVariant
                } else {
                    MaterialTheme.colorScheme.onSurface
                },
                maxLines = 4,
            )

            item.host?.let { host ->
                Text(
                    host,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                    maxLines = 1,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }

            if (showSnippet && !item.text.isNullOrEmpty()) {
                Text(
                    HnHtml.snippet(item.text, 160),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 3,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }

            Row(
                modifier = Modifier.padding(top = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                item.score?.let { MetaLabel(Icons.Filled.KeyboardArrowUp, abbreviated(it)) }
                if (item.kind != ItemKind.JOB) {
                    MetaLabel(Icons.Filled.List, abbreviated(item.commentCount))
                }
                item.by?.let { MetaLabel(Icons.Filled.Person, it) }
                MetaLabel(Icons.Filled.DateRange, shortAge(item.time))
                if (saved) {
                    Icon(
                        Icons.Filled.Star,
                        contentDescription = "Saved",
                        modifier = Modifier.size(14.dp),
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }
            }
        }
    }

    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
        item.link?.let { link ->
            DropdownMenuItem(
                text = { Text("Open Article") },
                onClick = {
                    menuOpen = false
                    openLink(context, link, settings.linkTarget)
                },
            )
        }
        DropdownMenuItem(
            text = { Text("Open on Hacker News") },
            onClick = {
                menuOpen = false
                openLink(context, item.hnUrl, settings.linkTarget)
            },
        )
        DropdownMenuItem(
            text = { Text(if (saved) "Remove from Saved" else "Save Story") },
            onClick = {
                menuOpen = false
                library.toggleSave(item)
            },
        )
        HorizontalDivider()
        DropdownMenuItem(
            text = { Text("Share Link") },
            onClick = {
                menuOpen = false
                shareLink(context, item.primaryUrl, item.displayTitle)
            },
        )
        DropdownMenuItem(
            text = { Text("Share Discussion") },
            onClick = {
                menuOpen = false
                shareLink(context, item.hnUrl, item.displayTitle)
            },
        )
        DropdownMenuItem(
            text = { Text("Copy Link") },
            onClick = {
                menuOpen = false
                copyToClipboard(context, item.primaryUrl)
            },
        )
    }
}

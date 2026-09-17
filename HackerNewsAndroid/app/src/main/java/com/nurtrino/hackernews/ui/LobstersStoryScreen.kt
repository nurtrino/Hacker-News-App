package com.nurtrino.hackernews.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.nurtrino.hackernews.data.LobstersThreadViewModel
import com.nurtrino.hackernews.data.Settings
import com.nurtrino.hackernews.model.Forum
import com.nurtrino.hackernews.model.LoadPhase
import com.nurtrino.hackernews.model.LobstersHtml

/** A lobste.rs story and its discussion. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LobstersStoryScreen(
    model: LobstersThreadViewModel,
    settings: Settings,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    var menuOpen by remember { mutableStateOf(false) }
    val story = model.story
    val visible = model.visibleNodes

    LaunchedEffect(Unit) { model.loadIfNeeded(settings.autoCollapseDeepThreads) }

    val openLinkHandler: (String) -> Unit = { openLink(context, it, settings.linkTarget) }
    // There's no in-app Lobsters profile screen, so authors open on the site.
    val openAuthor: (String) -> Unit = { openLinkHandler(Forum.LOBSTERS.profileUrl(it)) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        if (model.nodes.isEmpty()) "Discussion"
                        else pluralized(model.nodes.size, "comment"),
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { model.retry(settings.autoCollapseDeepThreads) }) {
                        Icon(Icons.Filled.Refresh, contentDescription = "Refresh")
                    }
                    IconButton(onClick = { menuOpen = true }) {
                        Icon(Icons.Filled.MoreVert, contentDescription = "More")
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        story.link?.let { link ->
                            DropdownMenuItem(
                                text = { Text("Open Article") },
                                onClick = { menuOpen = false; openLinkHandler(link) },
                            )
                        }
                        DropdownMenuItem(
                            text = { Text("Open on Lobsters") },
                            onClick = { menuOpen = false; openLinkHandler(story.lobstersUrl) },
                        )
                        HorizontalDivider()
                        DropdownMenuItem(
                            text = { Text("Share Link") },
                            onClick = {
                                menuOpen = false
                                shareLink(context, story.primaryUrl, story.title)
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("Share Discussion") },
                            onClick = {
                                menuOpen = false
                                shareLink(context, story.lobstersUrl, story.title)
                            },
                        )
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(modifier = Modifier.padding(padding)) {
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                ) {
                    Text(
                        story.title,
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.clickable { openLinkHandler(story.primaryUrl) },
                    )
                    story.host?.let { host ->
                        Text(
                            host,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.padding(top = 6.dp),
                        )
                    }
                    if (story.tags.isNotEmpty()) {
                        LobstersTagRow(story.tags, modifier = Modifier.padding(top = 8.dp))
                    }
                    Row(
                        modifier = Modifier.padding(top = 10.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            pluralized(story.score, "point"),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.primary,
                        )
                        Text(
                            story.author,
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.clickable { openAuthor(story.author) },
                        )
                        Text(
                            shortAge(story.createdAt),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }

                    story.descriptionHtml?.let { html ->
                        RichText(
                            html = LobstersHtml.normalize(html),
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.padding(top = 12.dp),
                            onLinkClick = openLinkHandler,
                        )
                    }
                }
                HorizontalDivider()

                if (model.nodes.isNotEmpty()) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            pluralized(model.nodes.size, "comment").uppercase(),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.weight(1f),
                        )
                        TextButton(
                            onClick = {
                                if (model.isFullyCollapsed) model.expandAll() else model.collapseAll()
                            },
                        ) {
                            Text(if (model.isFullyCollapsed) "Expand All" else "Collapse All")
                        }
                    }
                    HorizontalDivider()
                }
            }

            val phase = model.phase
            when {
                model.nodes.isEmpty() && phase == LoadPhase.Loading ->
                    item { LoadingState("Loading discussion…") }

                model.nodes.isEmpty() && phase is LoadPhase.Failed ->
                    item {
                        EmptyState(
                            icon = Icons.Filled.Warning,
                            title = "Something went wrong",
                            message = phase.message,
                            actionLabel = "Try Again",
                            onAction = { model.retry(settings.autoCollapseDeepThreads) },
                        )
                    }

                model.nodes.isEmpty() && phase == LoadPhase.Loaded ->
                    item {
                        EmptyState(
                            icon = Icons.Filled.List,
                            title = "No comments yet",
                            message = "Open this story on Lobsters to reply.",
                        )
                    }

                else -> items(count = visible.size) { index ->
                    val node = visible[index]
                    CommentRow(
                        node = node,
                        isCollapsed = model.isCollapsed(node.id),
                        isOriginalPoster = node.author != null && node.author == story.submitter,
                        onToggle = { model.toggleCollapse(node) },
                        onAuthorClick = openAuthor,
                        onLinkClick = openLinkHandler,
                    )
                    HorizontalDivider()
                }
            }
        }
    }
}

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
import com.nurtrino.hackernews.data.Library
import com.nurtrino.hackernews.data.Settings
import com.nurtrino.hackernews.data.ThreadViewModel
import com.nurtrino.hackernews.model.LoadPhase

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StoryScreen(
    model: ThreadViewModel,
    settings: Settings,
    library: Library,
    onBack: () -> Unit,
    onOpenUser: (String) -> Unit,
) {
    val context = LocalContext.current
    var menuOpen by remember { mutableStateOf(false) }
    val story = model.story
    val visible = model.visibleNodes

    LaunchedEffect(Unit) { model.loadIfNeeded(settings.autoCollapseDeepThreads) }
    LaunchedEffect(story) { library.refreshSaved(story) }

    val openLinkHandler: (String) -> Unit = { openLink(context, it, settings.linkTarget) }

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
                            text = { Text("Open on Hacker News") },
                            onClick = { menuOpen = false; openLinkHandler(story.hnUrl) },
                        )
                        DropdownMenuItem(
                            text = {
                                Text(
                                    if (library.isSaved(story.id)) "Remove from Saved"
                                    else "Save Story",
                                )
                            },
                            onClick = { menuOpen = false; library.toggleSave(story) },
                        )
                        HorizontalDivider()
                        DropdownMenuItem(
                            text = { Text("Share Link") },
                            onClick = {
                                menuOpen = false
                                shareLink(context, story.primaryUrl, story.displayTitle)
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("Share Discussion") },
                            onClick = {
                                menuOpen = false
                                shareLink(context, story.hnUrl, story.displayTitle)
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
                        story.displayTitle,
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
                    Row(
                        modifier = Modifier.padding(top = 10.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        story.score?.let {
                            Text(
                                pluralized(it, "point"),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.primary,
                            )
                        }
                        Text(
                            story.author,
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.clickable { onOpenUser(story.author) },
                        )
                        Text(
                            shortAge(story.time),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }

                    if (!story.text.isNullOrEmpty()) {
                        RichText(
                            html = story.text!!,
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
                            message = "Open this story on Hacker News to reply.",
                        )
                    }

                else -> items(count = visible.size) { index ->
                    val node = visible[index]
                    CommentRow(
                        node = node,
                        isCollapsed = model.isCollapsed(node.id),
                        isOriginalPoster = node.author != null && node.author == story.by,
                        onToggle = { model.toggleCollapse(node) },
                        onAuthorClick = onOpenUser,
                        onLinkClick = openLinkHandler,
                    )
                    HorizontalDivider()
                }
            }
        }
    }
}
